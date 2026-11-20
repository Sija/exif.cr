module EXIF
  # Represents the entire EXIF data found in an image.
  #
  # ```
  # data = EXIF::Data.open("photo.jpg")
  #
  # data[:model].to_s # => "Canon PowerShot S70"
  # data[:gps_latitude]?.try &.value
  # data.ifd(:exif).size # => 30
  # data.each { |entry| puts "#{entry.title}: #{entry}" }
  #
  # data[:artist] = "Jane Doe"
  # data.save("photo.jpg")
  # ```
  class Data
    include Enumerable(Entry)

    # Size of the TIFF header (byte order, magic number and IFD 0 offset).
    TIFF_HEADER_SIZE = 8

    # Size of the chunks read by `.new(io)`.
    BUFFER_SIZE = 8192

    @ptr : LibEXIF::EXIFData*
    @log : LibEXIF::EXIFLog*
    # Insertion ordered, so that warnings are reported in order (once each)
    @warnings = Set(String).new

    # Set once the `Tag::MakerNote` entry gets a new value, outdating the maker note parsed by libexif.
    @maker_note_replaced = false

    # Returns the options affecting loading and saving.
    getter options : Options

    # Creates a new, empty EXIF data structure.
    def initialize(@options : Options = Options.default)
      @ptr = LibEXIF.exif_data_new
      raise Error.new("Could not allocate EXIF data") if @ptr.null?

      @log = LibEXIF.exif_log_new
      if @log.null?
        LibEXIF.exif_data_unref(@ptr)
        # The finalizer runs even if `initialize` raises
        @ptr = Pointer(LibEXIF::EXIFData).null
        raise Error.new("Could not allocate EXIF log")
      end
      LibEXIF.exif_log_set_func(@log, EXIF::LOG_FUNC, self.as(Void*))
      LibEXIF.exif_data_log(@ptr, @log)

      self.options = options
    end

    # Returns the problems with the data reported by libexif, i.e. corrupted
    # or truncated entries found while loading it, or entries with an invalid
    # number of components found while formatting their values (see `Entry#to_s`).
    #
    # Each distinct problem is reported once.
    #
    # ```
    # data = EXIF::Data.new(truncated_bytes)
    # data.warnings # => ["Bogus offset of IFD1."]
    # ```
    def warnings : Array(String)
      @warnings.to_a
    end

    # :nodoc:
    def add_warning(message : String) : Nil
      # NOTE: The same problems get reported on every formatting of an entry
      @warnings << message
    end

    # Loads EXIF data from the given *bytes*, see `.new(io)`.
    #
    # Raises `NoDataError` if no EXIF data is found.
    def self.new(bytes : Bytes, options : Options = Options.default) : self
      new(IO::Memory.new(bytes, false), options)
    end

    # Loads EXIF data from the given *io*, reading only as much of it as needed.
    #
    # Accepts a JPEG image, a raw EXIF block (starting with an `Exif\0\0` header),
    # or a raw TIFF structure, i.e. the EXIF block without its header (as stored
    # in PNG `eXIf` chunks). Other formats are left to libexif's loader.
    #
    # Raises `NoDataError` if no EXIF data is found.
    def self.new(io : IO, options : Options = Options.default) : self
      # Sniffed in steps, so that JPEG streams are left right after the SOI marker
      head = Bytes.new(JPEG::EXIF_HEADER.size)
      size = EXIF.read_up_to(io, head[0, 2])

      # NOTE: libexif's loader stops at JPEG segments it doesn't know (i.e. APP12),
      # missing the EXIF segments following them, so JPEG streams are read here
      return load_jpeg(io, options) if JPEG.jpeg?(head[0, size])

      size += EXIF.read_up_to(io, head[size, 2]) if size == 2
      if head[0, size].in?(TIFF_HEADERS)
        return load_block(JPEG::EXIF_HEADER + head[0, size] + read_block(io, size), options)
      end

      size += EXIF.read_up_to(io, head[size, 2]) if size == 4
      if head[0, size] == JPEG::EXIF_HEADER
        return load_block(head + read_block(io, 0), options)
      end

      load(options) do |loader|
        next if LibEXIF.exif_loader_write(loader, head, size.to_u32).zero?

        buffer = Bytes.new(BUFFER_SIZE)
        while (read = io.read(buffer)) > 0
          break if LibEXIF.exif_loader_write(loader, buffer, read.to_u32).zero?
        end
      end
    end

    # Loads the first valid EXIF segment from the JPEG stream *io*,
    # positioned right after the SOI marker.
    #
    # NOTE: Some images carry an empty or corrupt EXIF segment
    # before the actual one, so all of them are tried in turn.
    private def self.load_jpeg(io : IO, options : Options) : self
      error = nil
      while exif = JPEG.read_exif?(io)
        begin
          return load_block(exif, options)
        rescue ex : NoDataError
          error ||= ex
        end
      end
      raise error || NoDataError.new
    end

    # Byte order marks and magic numbers starting a TIFF structure.
    TIFF_HEADERS = {"II*\0".to_slice, "MM\0*".to_slice}

    # Maximum size of the EXIF block (including the `Exif\0\0` header) libexif loads.
    #
    # NOTE: One byte more than fits into a JPEG segment (see `JPEG::MAX_SEGMENT_SIZE`),
    # so a block which can be loaded (i.e. by `#dup`) might still be too large to embed.
    MAX_BLOCK_SIZE = 0xFFFE

    # Reads the rest of an EXIF block from *io*, *read* bytes of which (not counting
    # the `Exif\0\0` header) were already read, up to `MAX_BLOCK_SIZE`.
    private def self.read_block(io : IO, read : Int32) : Bytes
      rest = Bytes.new(MAX_BLOCK_SIZE - JPEG::EXIF_HEADER.size - read)
      rest[0, EXIF.read_up_to(io, rest)]
    end

    # Loads EXIF data from the file at the given *path*.
    #
    # Raises `NoDataError` if no EXIF data is found.
    def self.open(path : Path | String, options : Options = Options.default) : self
      File.open(path) { |file| new(file, options) }
    end

    # Loads EXIF data from the file at the given *path*, returning `nil`
    # if it contains none.
    def self.open?(path : Path | String, options : Options = Options.default) : self?
      open(path, options)
    rescue NoDataError
    end

    private def self.load(options : Options, & : LibEXIF::EXIFLoader* ->) : self
      loader = LibEXIF.exif_loader_new
      raise Error.new("Could not allocate EXIF loader") if loader.null?
      begin
        yield loader

        buf = Pointer(UInt8).null
        size = 0_u32
        LibEXIF.exif_loader_get_buf(loader, pointerof(buf), pointerof(size))
        raise NoDataError.new if buf.null? || size.zero?

        load_data(buf, size, options)
      ensure
        LibEXIF.exif_loader_unref(loader)
      end
    end

    # Loads the EXIF data from the EXIF block held in *bytes* (starting with an `Exif\0\0` header).
    private def self.load_block(bytes : Bytes, options : Options) : self
      # The EXIF header has to be followed by (at least) a TIFF header
      if bytes.size < JPEG::EXIF_HEADER.size + TIFF_HEADER_SIZE
        raise NoDataError.new("No valid EXIF data found (too short)")
      end
      load_data(bytes.to_unsafe, bytes.size.to_u32, options)
    end

    # Loads the EXIF data from the raw *buf* (an EXIF block or a JPEG image).
    #
    # Raises `NoDataError` if nothing could be loaded, due to corrupt data.
    private def self.load_data(buf : UInt8*, size : UInt32, options : Options) : self
      data = new(options)
      data.retain { |ptr| LibEXIF.exif_data_load_data(ptr, buf, size) }
      if data.empty? && (warning = data.warnings.first?)
        raise NoDataError.new("No valid EXIF data found (#{warning})")
      end
      data
    end

    def finalize
      # NOTE: Pointers might be null if `initialize` raised
      unless @log.null?
        # The libexif data might outlive this wrapper (see `#retain`),
        # so detach it from the log callback first
        LibEXIF.exif_log_set_func(@log, EXIF::LOG_FUNC, Pointer(Void).null)
      end
      LibEXIF.exif_data_unref(@ptr) unless @ptr.null?
      LibEXIF.exif_log_unref(@log) unless @log.null?
    end

    # :nodoc:
    #
    # Yields the raw libexif data, holding an extra reference to it meanwhile.
    #
    # Wrappers only pass their raw pointers to libexif, so a wrapper which isn't
    # used afterwards (i.e. a temporary) might get garbage collected in the middle
    # of a libexif call, or while its memory is being read; i.e. libexif's log
    # callback allocates, which can trigger a collection within `exif_data_load_data`.
    # The extra reference keeps the libexif data (with all of its IFDs and entries)
    # alive until the block returns, even if the finalizer runs meanwhile.
    def retain(& : LibEXIF::EXIFData* -> T) : T forall T
      ptr = @ptr
      LibEXIF.exif_data_ref(ptr)
      begin
        yield ptr
      ensure
        LibEXIF.exif_data_unref(ptr)
      end
    end

    def to_unsafe : LibEXIF::EXIFData*
      @ptr
    end

    # Returns an independent copy of the data, with the same options and warnings.
    #
    # NOTE: libexif can't copy its data structures, so the copy is created by
    # re-loading the serialized data (see `#to_slice`), raising `Error` if the
    # entries take more than the 64 KB libexif loads (the thumbnail is copied apart).
    def dup : self
      # libexif loads at most 64 KB, which a large thumbnail alone could exceed
      thumbnail = thumbnail?
      bytes = without_thumbnail { to_slice }
      if bytes.size > MAX_BLOCK_SIZE
        raise Error.new("EXIF data too large to copy (#{bytes.size} > #{MAX_BLOCK_SIZE} bytes)")
      end

      copy = self.class.new(bytes, options: Options::None)
      copy.thumbnail = thumbnail
      copy.options = options
      copy.data_type = data_type
      @warnings.each { |warning| copy.add_warning(warning) }
      copy
    end

    # Yields with the thumbnail temporarily detached from the libexif data.
    private def without_thumbnail(&)
      data, size = @ptr.value.data, @ptr.value.size
      @ptr.value.data, @ptr.value.size = Pointer(UInt8).null, 0_u32
      begin
        yield
      ensure
        @ptr.value.data, @ptr.value.size = data, size
      end
    end

    # Sets the options affecting loading and saving.
    def options=(options : Options) : Options
      @options = options
      retain do |ptr|
        Options.values.each do |option|
          if options.includes?(option)
            LibEXIF.exif_data_set_option(ptr, option)
          else
            LibEXIF.exif_data_unset_option(ptr, option)
          end
        end
      end
      options
    end

    # Returns the byte order in use.
    def byte_order : ByteOrder
      LibEXIF.exif_data_get_byte_order(@ptr)
    end

    # Sets the byte order, converting all existing entries.
    def byte_order=(byte_order : ByteOrder) : ByteOrder
      return byte_order if byte_order == self.byte_order

      retain { |ptr| LibEXIF.exif_data_set_byte_order(ptr, byte_order) }
      # libexif leaves `Format::Undefined` entries as they are, including Unicode
      # user comments, which are stored in the byte order of the data
      each(&.swap_unicode_user_comment)
      byte_order
    end

    # Returns the type of image data this EXIF data applies to.
    def data_type : DataType
      LibEXIF.exif_data_get_data_type(@ptr)
    end

    # Sets the type of image data this EXIF data applies to.
    def data_type=(data_type : DataType) : DataType
      LibEXIF.exif_data_set_data_type(@ptr, data_type)
      data_type
    end

    # Returns the content of the given *ifd*.
    def ifd(ifd : IFD) : Content
      raise ArgumentError.new("Invalid IFD: #{ifd}") unless ifd.in?(IFDS)
      Content.new(self, raw_ifd(ifd))
    end

    # Returns the contents of all IFDs.
    def ifds : Array(Content)
      IFDS.to_a { |ifd| ifd(ifd) }
    end

    # Yields each entry across all IFDs.
    def each(& : Entry ->) : Nil
      IFDS.each do |ifd|
        entries_of(raw_ifd(ifd)).each { |entry| yield entry }
      end
    end

    # Returns the total number of entries across all IFDs.
    def size : Int32
      IFDS.sum { |ifd| raw_ifd(ifd).value.count.to_i }
    end

    # Returns `true` if there are no entries.
    def empty? : Bool
      IFDS.all? { |ifd| raw_ifd(ifd).value.count.zero? }
    end

    # Returns the entry for the given *tag*, or `nil`.
    #
    # `Tag`s are looked up in the `IFD::Zero`, `IFD::EXIF` and `IFD::Interoperability`
    # IFDs in turn (see `Tag#lookup_ifds`), `GPSTag`s in the `IFD::GPS` one.
    #
    # NOTE: Entries of `IFD::One`, describing the thumbnail, are left out,
    # use `ifd(:one)[tag]?` to access these.
    def []?(tag : AnyTag) : Entry?
      find_entry(tag, tag.lookup_ifds)
    end

    # Returns the entry for the given *tag*.
    #
    # Raises `KeyError` if there's no such entry.
    def [](tag : AnyTag) : Entry
      self[tag]? || raise KeyError.new("Missing EXIF entry: #{tag}")
    end

    # Returns `true` if there's an entry for the given *tag*.
    def has_key?(tag : AnyTag) : Bool
      tag.lookup_ifds.any? { |ifd| !raw_entry(ifd, tag).null? }
    end

    # Sets the *value* of the entry for the given *tag*.
    #
    # If there's no such entry, it's created in the IFD
    # the tag belongs to (see `Tag#default_ifd`).
    # Setting `nil` removes the entry.
    def []=(tag : AnyTag, value) : Nil
      if entry = self[tag]?
        entry.value = value
      else
        tag.check_settable if tag.is_a?(Tag)
        ifd = tag.default_ifd || raise ArgumentError.new("Cannot determine IFD for tag: #{tag}")
        ifd(ifd)[tag] = value
      end
    end

    # :ditto:
    def []=(tag : AnyTag, value : Nil) : Nil
      delete(tag)
    end

    # Removes the entry for the given *tag*, returning it (or `nil` if not found).
    def delete(tag : AnyTag) : Entry?
      self[tag]?.try(&.delete)
    end

    # :nodoc:
    #
    # Returns wrappers for all entries of the given raw *content*.
    def entries_of(content : LibEXIF::EXIFContent*) : Array(Entry)
      Array(Entry).new(content.value.count) do |i|
        Entry.new(self, content.value.entries[i])
      end
    end

    # Returns the first entry for the given *tag* found in *ifds*, or `nil`.
    private def find_entry(tag : AnyTag, ifds : Enumerable(IFD)) : Entry?
      ifds.each do |ifd|
        ptr = raw_entry(ifd, tag)
        return Entry.new(self, ptr) unless ptr.null?
      end
      nil
    end

    private def raw_entry(ifd : IFD, tag : AnyTag) : LibEXIF::EXIFEntry*
      LibEXIF.exif_content_get_entry(raw_ifd(ifd), tag.to_tag)
    end

    private def raw_ifd(ifd : IFD) : LibEXIF::EXIFContent*
      @ptr.value.ifd[ifd.value]
    end

    # Returns the embedded thumbnail (usually a JPEG image), or `nil`.
    def thumbnail? : Bytes?
      retain do |ptr|
        data, size = ptr.value.data, ptr.value.size.to_i
        Slice.new(data, size).dup unless data.null? || size.zero?
      end
    end

    # Sets (or removes, if `nil`) the embedded thumbnail.
    def thumbnail=(bytes : Bytes?) : Bytes?
      # Allocated upfront, so that the current thumbnail is kept if that fails
      ptr, size = Pointer(UInt8).null, 0_u32
      if bytes && !bytes.empty?
        ptr = EXIF.alloc(bytes.size)
        ptr.copy_from(bytes.to_unsafe, bytes.size)
        size = bytes.size.to_u32
      end
      EXIF.free(@ptr.value.data)
      @ptr.value.data, @ptr.value.size = ptr, size
      bytes
    end

    # Returns the parsed maker note, or `nil` if missing or unsupported.
    #
    # NOTE: libexif parses the maker note when loading the data, so once the
    # `Tag::MakerNote` entry gets removed or set, `nil` is returned (until reloaded).
    #
    # WARNING: A new `Tag::MakerNote` value is saved as is, while some vendors
    # (i.e. Canon) store offsets relative to the start of the TIFF structure
    # within it, which libexif adjusts only for the maker note it parsed;
    # i.e. one copied over from another image might end up pointing elsewhere.
    def maker_note? : MakerNote?
      return if @maker_note_replaced || !has_key?(Tag::MakerNote)

      ptr = LibEXIF.exif_data_get_mnote_data(@ptr)
      MakerNote.new(self, ptr) unless ptr.null?
    end

    # :nodoc:
    #
    # Marks the parsed maker note as outdated by a new `Tag::MakerNote` value,
    # which libexif would otherwise overwrite with it when saving the data.
    def maker_note_replaced : Nil
      @maker_note_replaced = true
    end

    # Fixes the EXIF data to bring it into specification
    # (adds mandatory entries, removes not-recorded ones, ...).
    def fix : self
      retain { |ptr| LibEXIF.exif_data_fix(ptr) }
      self
    end

    # Returns the raw EXIF block (including the `Exif\0\0` header),
    # suitable for embedding as a JPEG APP1 segment.
    def to_slice : Bytes
      buf = Pointer(UInt8).null
      size = 0_u32
      retain do |ptr|
        # libexif regenerates the `Tag::MakerNote` entry from the parsed maker note,
        # unless told not to, which would undo a new value of the entry
        keep_maker_note = @maker_note_replaced && !options.dont_change_maker_note?
        LibEXIF.exif_data_set_option(ptr, Options::DontChangeMakerNote) if keep_maker_note
        begin
          LibEXIF.exif_data_save_data(ptr, pointerof(buf), pointerof(size))
        ensure
          LibEXIF.exif_data_unset_option(ptr, Options::DontChangeMakerNote) if keep_maker_note
        end
      end
      raise Error.new("Could not save EXIF data") if buf.null?
      begin
        Slice.new(buf, size.to_i).dup
      ensure
        EXIF.free(buf)
      end
    end

    # Returns a copy of the given *jpeg* image with this EXIF data embedded.
    def embed(jpeg : Bytes) : Bytes
      JPEG.embed(jpeg, to_slice)
    end

    # Writes the JPEG image read from *source* (by default *path* itself)
    # with this EXIF data embedded to *path*, replacing any existing EXIF data.
    #
    # The image is written atomically, keeping the permissions, owner and group
    # of the replaced file, see `JPEG.write`. Symbolic links are followed.
    def save(path : Path | String, source : Path | String? = nil) : Nil
      if source
        JPEG.write(path, embed(File.read(source).to_slice))
      else
        JPEG.update(path) { |jpeg| embed(jpeg) }
      end
    end

    # Returns a nested hash of IFD names to entry names to their formatted values.
    def to_h : Hash(String, Hash(String, String))
      ifds.reject(&.empty?).to_h do |content|
        {content.ifd.label, content.to_h}
      end
    end

    def inspect(io : IO) : Nil
      io << "#<" << self.class.name
      io << " byte_order=" << byte_order
      ifds.each do |content|
        io << ' ' << content.ifd << '=' << content.size
      end
      io << '>'
    end
  end
end
