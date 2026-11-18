module EXIF
  # A single EXIF tag together with its value.
  #
  # ```
  # entry = data[:exposure_time]
  # entry.name   # => "ExposureTime"
  # entry.title  # => "Exposure Time"
  # entry.format # => EXIF::Format::Rational
  # entry.value  # => EXIF::URational(1/250)
  # entry.to_s   # => "1/250 sec."
  # ```
  class Entry
    # Returns the `Data` this entry belongs to.
    getter data : Data

    @ptr : LibEXIF::EXIFEntry*

    protected def initialize(@data : Data, @ptr : LibEXIF::EXIFEntry*)
      LibEXIF.exif_entry_ref(@ptr)
    end

    def finalize
      LibEXIF.exif_entry_unref(@ptr)
    end

    def to_unsafe : LibEXIF::EXIFEntry*
      @ptr
    end

    # Returns the IFD the entry is stored in, or `nil` if it was removed.
    def ifd? : IFD?
      parent = @ptr.value.parent
      LibEXIF.exif_content_get_ifd(parent) unless parent.null?
    end

    # Returns the IFD the entry is stored in.
    def ifd : IFD
      ifd? || raise Error.new("Entry is not attached to any IFD")
    end

    # Returns the entry tag (a `GPSTag` for entries stored in the GPS IFD).
    def tag : AnyTag
      tag = @ptr.value.tag
      ifd?.try(&.gps?) ? GPSTag.new(tag.value) : tag
    end

    # Returns the raw (numeric) tag, as used by libexif.
    protected def raw_tag : Tag
      @ptr.value.tag
    end

    # Returns the EXIF name of the entry tag (i.e. `"FNumber"`).
    def name : String
      raw_tag.name(ifd?) || raw_tag.name || "0x%04x" % raw_tag.value
    end

    # Returns the localized title of the entry tag (i.e. `"F-Number"`).
    def title : String?
      raw_tag.title(ifd?) || raw_tag.title
    end

    # Returns the localized description of the entry tag.
    def description : String?
      raw_tag.description(ifd?) || raw_tag.description
    end

    # Returns the support level of this entry within its IFD.
    def support_level : SupportLevel
      raw_tag.support_level(ifd, data.data_type)
    end

    # Returns the data format of the entry.
    def format : Format
      @ptr.value.format
    end

    # Returns the number of components (values) stored in the entry.
    def components : Int32
      @ptr.value.components.to_i
    end

    # Returns the size (in bytes) of the raw data.
    def bytesize : Int32
      @ptr.value.size.to_i
    end

    # Returns a copy of the raw entry data.
    def to_slice : Bytes
      return Bytes.empty if @ptr.value.data.null?
      Slice.new(@ptr.value.data, bytesize).dup
    end

    # Returns the decoded entry value, see `Value`.
    def value : Value
      Codec.new(self, data.byte_order).decode
    end

    # Encodes and stores the given *value*.
    #
    # Integers, floats and rationals may be given either as a scalar or an `Array`,
    # `String` is accepted by `Format::Ascii` and `Format::Undefined` entries,
    # `Bytes` by `Format::Undefined`, `Format::Byte` and `Format::SByte` ones.
    #
    # Raises `ValueError` if the value can't be stored in the entry format.
    def value=(value)
      Codec.new(self, data.byte_order).encode(value)
    end

    # Returns the human-readable (localized) value of the entry, as formatted by libexif.
    def to_s(io : IO) : Nil
      maxlen = Math.max(1024, bytesize * 6 + 64)
      buffer = Bytes.new(maxlen)
      ptr = LibEXIF.exif_entry_get_value(@ptr, buffer, maxlen)
      io << String.new(ptr) unless ptr.null?
    end

    # Fixes the format and components of the entry to bring it into specification.
    def fix : self
      LibEXIF.exif_entry_fix(@ptr)
      self
    end

    # Removes the entry from its IFD.
    def delete : self
      parent = @ptr.value.parent
      LibEXIF.exif_content_remove_entry(parent, @ptr) unless parent.null?
      self
    end

    def ==(other : Entry) : Bool
      @ptr == other.to_unsafe
    end

    def inspect(io : IO) : Nil
      io << "#<" << self.class.name << ' ' << name
      io << " ifd=" << ifd?
      io << " format=" << format
      io << " components=" << components
      io << " value=" << to_s.inspect
      io << '>'
    end

    # :nodoc:
    protected def raw : LibEXIF::EXIFEntry*
      @ptr
    end

    # Reads and writes entry values in the given byte order.
    private struct Codec
      def initialize(@entry : Entry, @byte_order : ByteOrder)
      end

      private def raw
        @entry.raw.value
      end

      private def ptr : UInt8*
        raw.data
      end

      def decode : Value
        return decode_ascii if raw.format.ascii?
        return Bytes.empty if ptr.null?
        return decode_user_comment if user_comment_tag? && raw.format.undefined?
        return decode_utf16(Slice.new(ptr, raw.size.to_i), IO::ByteFormat::LittleEndian) if xp_tag? && raw.format.byte?
        return @entry.to_slice if raw.format.undefined?

        count = Math.min(raw.components.to_i, raw.size.to_i // Math.max(raw.format.bytesize, 1))
        case raw.format
        when .byte?, .short?, .long?, .s_byte?, .s_short?, .s_long?
          collapse Array(Int64).new(count) { |i| read_int(i) }
        when .float?, .double?
          collapse Array(Float64).new(count) { |i| read_float(i) }
        when .rational?
          collapse Array(URational).new(count) { |i| URational.from(LibEXIF.exif_get_rational(at(i), @byte_order)) }
        when .s_rational?
          collapse Array(SRational).new(count) { |i| SRational.from(LibEXIF.exif_get_srational(at(i), @byte_order)) }
        else
          @entry.to_slice
        end
      end

      private def collapse(values : Array(T)) : Value forall T
        values.size == 1 ? values.first : values
      end

      private def decode_ascii : String
        return "" if ptr.null?
        slice = Slice.new(ptr, raw.size.to_i)
        if nul = slice.index(0_u8)
          slice = slice[0, nul]
        end
        String.new(slice)
      end

      # Character code prefixes used by `Tag::UserComment`.
      USER_COMMENT_ASCII   = "ASCII\0\0\0".to_slice
      USER_COMMENT_UNICODE = "UNICODE\0".to_slice

      # Tags holding UTF-16LE strings, stored in `Format::Byte`.
      XP_TAGS = {Tag::XPTitle, Tag::XPComment, Tag::XPAuthor, Tag::XPKeywords, Tag::XPSubject}

      private def user_comment_tag? : Bool
        raw.tag.user_comment? && @entry.ifd? != IFD::GPS
      end

      private def xp_tag? : Bool
        raw.tag.in?(XP_TAGS) && @entry.ifd? != IFD::GPS
      end

      private def decode_user_comment : String
        slice = Slice.new(ptr, raw.size.to_i)
        return "" if slice.size < 8

        charset, text = slice[0, 8], slice[8..]
        if charset == USER_COMMENT_UNICODE
          decode_utf16(text, @byte_order.byte_format)
        else
          String.new(text).rstrip("\0 ")
        end
      end

      private def decode_utf16(slice : Bytes, format : IO::ByteFormat) : String
        units = Slice(UInt16).new(slice.size // 2) do |i|
          format.decode(UInt16, slice[i * 2, 2])
        end
        if nul = units.index(0_u16)
          units = units[0, nul]
        end
        String.from_utf16(units)
      end

      private def encode_utf16(value : String, format : IO::ByteFormat) : Bytes
        units = value.to_utf16
        io = IO::Memory.new(units.size * 2)
        units.each { |unit| io.write_bytes(unit, format) }
        io.to_slice
      end

      private def at(index : Int) : UInt8*
        ptr + index * raw.format.bytesize
      end

      private def read_int(index : Int) : Int64
        p = at(index)
        case raw.format
        when .byte?    then p.value.to_i64
        when .s_byte?  then p.value.to_i8!.to_i64
        when .short?   then LibEXIF.exif_get_short(p, @byte_order).to_i64
        when .s_short? then LibEXIF.exif_get_sshort(p, @byte_order).to_i64
        when .long?    then LibEXIF.exif_get_long(p, @byte_order).to_i64
        when .s_long?  then LibEXIF.exif_get_slong(p, @byte_order).to_i64
        else                raise "BUG: not an integer format: #{raw.format}"
        end
      end

      private def read_float(index : Int) : Float64
        slice = Slice.new(at(index), raw.format.bytesize)
        format = @byte_order.byte_format
        raw.format.float? ? format.decode(Float32, slice).to_f64 : format.decode(Float64, slice)
      end

      def encode(value : String) : Nil
        if user_comment_tag?
          @entry.raw.value.format = Format::Undefined
          return encode(
            if value.ascii_only?
              USER_COMMENT_ASCII + value.to_slice
            else
              USER_COMMENT_UNICODE + encode_utf16(value, @byte_order.byte_format)
            end
          )
        end
        if xp_tag?
          @entry.raw.value.format = Format::Byte
          return encode(encode_utf16(value, IO::ByteFormat::LittleEndian) + Bytes.new(2))
        end

        bytes = value.to_slice
        case format_for(value)
        when .ascii?
          resize(bytes.size + 1, bytes.size + 1)
          ptr.copy_from(bytes.to_unsafe, bytes.size)
          ptr[bytes.size] = 0_u8
        when .undefined?, .byte?
          encode(bytes)
        else
          mismatch!(value)
        end
      end

      def encode(value : Bytes) : Nil
        case format_for(value)
        when .undefined?, .byte?, .s_byte?
          resize(value.size, value.size)
          ptr.copy_from(value.to_unsafe, value.size)
        else
          mismatch!(value)
        end
      end

      def encode(value : Int | Float | Rational) : Nil
        encode({value})
      end

      def encode(values : Indexable) : Nil
        raise ValueError.new("Cannot store an empty array") if values.empty?

        format = format_for(values.first)
        resize(values.size * format.bytesize, values.size)
        values.each_with_index do |value, i|
          write(i, format, value)
        end
      end

      def encode(value) : NoReturn
        mismatch!(value)
      end

      private def write(index, format : Format, value) : NoReturn
        mismatch!(value)
      end

      private def write(index, format : Format, value : Int) : Nil
        p = at(index)
        case format
        when .byte?, .undefined? then p.value = value.to_u8
        when .s_byte?            then p.value = value.to_i8.to_u8!
        when .short?             then LibEXIF.exif_set_short(p, @byte_order, value.to_u16)
        when .s_short?           then LibEXIF.exif_set_sshort(p, @byte_order, value.to_i16)
        when .long?              then LibEXIF.exif_set_long(p, @byte_order, value.to_u32)
        when .s_long?            then LibEXIF.exif_set_slong(p, @byte_order, value.to_i32)
        when .rational?          then write(index, format, URational.new(value))
        when .s_rational?        then write(index, format, SRational.new(value))
        when .float?, .double?   then write(index, format, value.to_f64)
        else                          mismatch!(value)
        end
      rescue OverflowError
        raise ValueError.new("Value #{value} out of range for format #{format}")
      end

      private def write(index, format : Format, value : Float) : Nil
        p = at(index)
        case format
        when .float?      then @byte_order.byte_format.encode(value.to_f32, Slice.new(p, 4))
        when .double?     then @byte_order.byte_format.encode(value.to_f64, Slice.new(p, 8))
        when .rational?   then write(index, format, URational.new(value))
        when .s_rational? then write(index, format, SRational.new(value))
        else
          raise ValueError.new("Cannot store a float in an entry of #{format} format") unless value == value.round
          write(index, format, value.to_i64)
        end
      end

      private def write(index, format : Format, value : Rational) : Nil
        p = at(index)
        case format
        when .rational?   then LibEXIF.exif_set_rational(p, @byte_order, URational.new(value.numerator, value.denominator).to_lib)
        when .s_rational? then LibEXIF.exif_set_srational(p, @byte_order, SRational.new(value.numerator, value.denominator).to_lib)
        else                   write(index, format, value.to_f)
        end
      rescue OverflowError
        raise ValueError.new("Value #{value} out of range for format #{format}")
      end

      # Returns the entry format, or sets one inferred from the *value*
      # when the entry has none yet (i.e. for tags unknown to libexif).
      private def format_for(value) : Format
        format = raw.format
        return format if Format.valid?(format)

        format =
          case value
          when String    then Format::Ascii
          when Bytes     then Format::Undefined
          when SRational then Format::SRational
          when URational then Format::Rational
          when Float     then Format::Rational
          when Int       then value.negative? ? Format::SLong : Format::Long
          else                mismatch!(value)
          end
        @entry.raw.value.format = format
      end

      # Reallocates the data buffer to hold *size* bytes and *components* values.
      private def resize(size : Int, components : Int) : Nil
        EXIF.free(raw.data)
        @entry.raw.value.data = size.zero? ? Pointer(UInt8).null : EXIF.alloc(size)
        @entry.raw.value.size = size.to_u32
        @entry.raw.value.components = LibC::ULong.new(components)
      end

      private def mismatch!(value) : NoReturn
        raise ValueError.new("Cannot store #{value.class} in an entry of #{raw.format} format")
      end
    end
  end
end
