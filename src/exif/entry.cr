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

    # Yields the raw libexif entry, holding extra references to it (and to the
    # libexif data) meanwhile, see `Data#retain`.
    private def retain(& : LibEXIF::EXIFEntry* -> T) : T forall T
      ptr = @ptr
      LibEXIF.exif_entry_ref(ptr)
      begin
        data.retain { yield ptr }
      ensure
        LibEXIF.exif_entry_unref(ptr)
      end
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
      retain do |ptr|
        data, size = ptr.value.data, ptr.value.size.to_i
        data.null? ? Bytes.empty : Slice.new(data, size).dup
      end
    end

    # Returns the decoded entry value, see `Value`.
    def value : Value
      retain { Codec.new(self, data.byte_order).decode }
    end

    # Encodes and stores the given *value*.
    #
    # Integers, floats and rationals may be given either as a scalar or an `Array`,
    # `String` is accepted by `Format::Ascii` and `Format::Undefined` entries,
    # `Bytes` by `Format::Undefined`, `Format::Byte` and `Format::SByte` ones.
    #
    # Raises `ValueError` if the value can't be stored in the entry format.
    def value=(value)
      retain { Codec.new(self, data.byte_order).encode(value) }
    end

    # Returns the human-readable (localized) value of the entry, as formatted by libexif.
    def to_s(io : IO) : Nil
      maxlen = Math.max(1024, bytesize * 6 + 64)
      buffer = Bytes.new(maxlen)
      value = retain { |ptr| LibEXIF.exif_entry_get_value(ptr, buffer, maxlen) }
      io << String.new(value) unless value.null?
    end

    # Fixes the format and components of the entry to bring it into specification.
    def fix : self
      retain { |ptr| LibEXIF.exif_entry_fix(ptr) }
      self
    end

    # Removes the entry from its IFD.
    def delete : self
      retain do |ptr|
        parent = ptr.value.parent
        LibEXIF.exif_content_remove_entry(parent, ptr) unless parent.null?
      end
      self
    end

    # Returns `true` if both wrap the same libexif entry.
    def ==(other : Entry) : Bool
      @ptr == other.to_unsafe
    end

    def hash(hasher)
      @ptr.address.hash(hasher)
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
      # Character code prefixes used by `Tag::UserComment`.
      USER_COMMENT_ASCII   = "ASCII\0\0\0".to_slice
      USER_COMMENT_UNICODE = "UNICODE\0".to_slice

      # Tags holding UTF-16LE strings, stored in `Format::Byte`.
      XP_TAGS = {Tag::XPTitle, Tag::XPComment, Tag::XPAuthor, Tag::XPKeywords, Tag::XPSubject}

      def initialize(@entry : Entry, @byte_order : ByteOrder)
      end

      private def raw
        @entry.raw.value
      end

      private def user_comment_tag? : Bool
        raw.tag.user_comment? && @entry.ifd? != IFD::GPS
      end

      private def xp_tag? : Bool
        raw.tag.in?(XP_TAGS) && @entry.ifd? != IFD::GPS
      end

      # --- Decoding ---

      def decode : Value
        data = raw.data
        return raw.format.ascii? ? "" : Bytes.empty if data.null?

        bytes = Slice.new(data, raw.size.to_i)
        decode_text(bytes) || decode_numbers(bytes) || bytes.dup
      end

      # Decodes textual formats and tags, returning `nil` for other ones.
      private def decode_text(bytes : Bytes) : String?
        case
        when raw.format.ascii?
          decode_string(bytes[0, bytes.index(0_u8) || bytes.size])
        when user_comment_tag? && raw.format.undefined?
          decode_user_comment(bytes)
        when xp_tag? && raw.format.byte?
          decode_utf16(bytes, IO::ByteFormat::LittleEndian)
        end
      end

      # Decodes numeric formats, returning `nil` for other ones.
      private def decode_numbers(bytes : Bytes) : Value?
        format = raw.format
        return unless format.in?(NUMERIC_FORMATS)

        size = format.bytesize
        count = Math.min(raw.components.to_i, bytes.size // size)
        p = bytes.to_unsafe

        case format
        when .rational?
          collapse Array(URational).new(count) { |i| URational.from(LibEXIF.exif_get_rational(p + i * size, @byte_order)) }
        when .s_rational?
          collapse Array(SRational).new(count) { |i| SRational.from(LibEXIF.exif_get_srational(p + i * size, @byte_order)) }
        when .float?, .double?
          collapse Array(Float64).new(count) { |i| read_float(bytes[i * size, size]) }
        else
          collapse Array(Int64).new(count) { |i| read_int(p + i * size) }
        end
      end

      NUMERIC_FORMATS = {
        Format::Byte, Format::SByte, Format::Short, Format::SShort, Format::Long, Format::SLong,
        Format::Rational, Format::SRational, Format::Float, Format::Double,
      }

      private def collapse(values : Array(T)) : Value forall T
        values.size == 1 ? values.first : values
      end

      # Decodes text as UTF-8, falling back to ISO-8859-1 (commonly used by cameras).
      private def decode_string(bytes : Bytes) : String
        string = String.new(bytes)
        string.valid_encoding? ? string : String.new(bytes, "ISO-8859-1")
      end

      private def decode_user_comment(bytes : Bytes) : String
        return "" if bytes.size < 8

        charset, text = bytes[0, 8], bytes[8..]
        if charset == USER_COMMENT_UNICODE
          decode_utf16(text, @byte_order.byte_format)
        else
          decode_string(text).rstrip("\0 ")
        end
      end

      private def decode_utf16(bytes : Bytes, format : IO::ByteFormat) : String
        units = Slice(UInt16).new(bytes.size // 2) do |i|
          format.decode(UInt16, bytes[i * 2, 2])
        end
        if nul = units.index(0_u16)
          units = units[0, nul]
        end
        String.from_utf16(units)
      end

      private def read_int(p : UInt8*) : Int64
        case raw.format
        when .byte?    then p.value.to_i64
        when .s_byte?  then p.value.to_i8!.to_i64
        when .short?   then LibEXIF.exif_get_short(p, @byte_order).to_i64
        when .s_short? then LibEXIF.exif_get_sshort(p, @byte_order).to_i64
        when .long?    then LibEXIF.exif_get_long(p, @byte_order).to_i64
        else                LibEXIF.exif_get_slong(p, @byte_order).to_i64
        end
      end

      private def read_float(bytes : Bytes) : Float64
        format = @byte_order.byte_format
        raw.format.float? ? format.decode(Float32, bytes).to_f64 : format.decode(Float64, bytes)
      end

      # --- Encoding ---

      # Encodes the *value* and stores it in the entry.
      #
      # The value is fully serialized before the entry is modified, so that
      # the entry is left intact if the value can't be stored.
      def encode(value) : Nil
        format, bytes, components = serialize(value)
        commit(format, bytes, components)
      end

      private def serialize(value : String) : {Format, Bytes, Int32}
        if user_comment_tag?
          bytes =
            if value.ascii_only?
              USER_COMMENT_ASCII + value.to_slice
            else
              USER_COMMENT_UNICODE + encode_utf16(value, @byte_order.byte_format)
            end
          return {Format::Undefined, bytes, bytes.size}
        end
        if xp_tag?
          bytes = encode_utf16(value, IO::ByteFormat::LittleEndian) + Bytes.new(2)
          return {Format::Byte, bytes, bytes.size}
        end

        case format = target_format(value)
        when .ascii?
          bytes = value.to_slice + Bytes.new(1)
          {format, bytes, bytes.size}
        when .undefined?, .byte?
          {format, value.to_slice.dup, value.bytesize}
        else
          mismatch!(value, format)
        end
      end

      private def serialize(value : Bytes) : {Format, Bytes, Int32}
        format = target_format(value)
        mismatch!(value, format) unless format.undefined? || format.byte? || format.s_byte?
        {format, value.dup, value.size}
      end

      private def serialize(value : Int | Float | Rational) : {Format, Bytes, Int32}
        serialize({value})
      end

      private def serialize(values : Indexable) : {Format, Bytes, Int32}
        raise ValueError.new("Cannot store an empty array") if values.empty?

        format = target_format(values.first)
        size = format.bytesize
        bytes = Bytes.new(values.size * size)
        values.each_with_index do |value, i|
          write(bytes.to_unsafe + i * size, format, value)
        end
        {format, bytes, values.size}
      end

      private def serialize(value) : NoReturn
        mismatch!(value, raw.format)
      end

      private def write(p : UInt8*, format : Format, value) : NoReturn
        mismatch!(value, format)
      end

      private def write(p : UInt8*, format : Format, value : Int) : Nil
        case format
        when .rational?, .s_rational?, .float?, .double?
          write(p, format, value.to_f64)
        else
          write_int(p, format, value)
        end
      rescue OverflowError
        out_of_range!(value, format)
      end

      private def write_int(p : UInt8*, format : Format, value : Int) : Nil
        case format
        when .byte?, .undefined? then p.value = value.to_u8
        when .s_byte?            then p.value = value.to_i8.to_u8!
        when .short?             then LibEXIF.exif_set_short(p, @byte_order, value.to_u16)
        when .s_short?           then LibEXIF.exif_set_sshort(p, @byte_order, value.to_i16)
        when .long?              then LibEXIF.exif_set_long(p, @byte_order, value.to_u32)
        when .s_long?            then LibEXIF.exif_set_slong(p, @byte_order, value.to_i32)
        else                          mismatch!(value, format)
        end
      end

      private def write(p : UInt8*, format : Format, value : Float) : Nil
        case format
        when .float?      then @byte_order.byte_format.encode(value.to_f32, Slice.new(p, 4))
        when .double?     then @byte_order.byte_format.encode(value.to_f64, Slice.new(p, 8))
        when .rational?   then write(p, format, URational.new(value))
        when .s_rational? then write(p, format, SRational.new(value))
        else
          raise ValueError.new("Cannot store a float in an entry of #{format} format") unless value == value.round
          write_int(p, format, value.to_i64)
        end
      rescue OverflowError
        out_of_range!(value, format)
      end

      private def write(p : UInt8*, format : Format, value : Rational) : Nil
        case format
        when .rational?   then LibEXIF.exif_set_rational(p, @byte_order, URational.new(value.numerator, value.denominator).to_lib)
        when .s_rational? then LibEXIF.exif_set_srational(p, @byte_order, SRational.new(value.numerator, value.denominator).to_lib)
        else                   write(p, format, value.to_f)
        end
      rescue OverflowError
        out_of_range!(value, format)
      end

      private def encode_utf16(value : String, format : IO::ByteFormat) : Bytes
        units = value.to_utf16
        bytes = Bytes.new(units.size * 2)
        units.each_with_index do |unit, i|
          format.encode(unit, bytes[i * 2, 2])
        end
        bytes
      end

      # Returns the entry format, or one inferred from the *value*
      # when the entry has none yet (i.e. for tags unknown to libexif).
      private def target_format(value) : Format
        format = raw.format
        return format if Format.valid?(format)

        case value
        when String    then Format::Ascii
        when Bytes     then Format::Undefined
        when SRational then Format::SRational
        when URational then Format::Rational
        when Float     then value.negative? ? Format::SRational : Format::Rational
        when Int       then value.negative? ? Format::SLong : Format::Long
        else                mismatch!(value, format)
        end
      end

      # Replaces the entry data with *bytes*.
      private def commit(format : Format, bytes : Bytes, components : Int) : Nil
        data = Pointer(UInt8).null
        unless bytes.empty?
          data = EXIF.alloc(bytes.size)
          data.copy_from(bytes.to_unsafe, bytes.size)
        end
        EXIF.free(raw.data)

        entry = @entry.raw
        entry.value.format = format
        entry.value.data = data
        entry.value.size = bytes.size.to_u32
        entry.value.components = LibC::ULong.new(components)
      end

      private def mismatch!(value, format : Format) : NoReturn
        raise ValueError.new("Cannot store #{value.class} in an entry of #{format} format")
      end

      private def out_of_range!(value, format : Format) : NoReturn
        raise ValueError.new("Value #{value} out of range for format #{format}")
      end
    end
  end
end
