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

    # Size of the chunks read by `.new(io)`.
    BUFFER_SIZE = 8192

    @ptr : LibEXIF::EXIFData*

    # Creates a new, empty EXIF data structure.
    def initialize(options : Options = Options.default)
      @ptr = LibEXIF.exif_data_new
      raise Error.new("Could not allocate EXIF data") if @ptr.null?

      LibEXIF.exif_data_log(@ptr, EXIF.log)
      self.options = options
    end

    # Loads EXIF data from a JPEG image or a raw EXIF block
    # (starting with an `Exif\0\0` header) held in *bytes*.
    #
    # Raises `NoDataError` if no EXIF data is found.
    def self.new(bytes : Bytes, options : Options = Options.default) : self
      # libexif's loader only handles JPEG streams
      if bytes[0, JPEG::EXIF_HEADER.size]? == JPEG::EXIF_HEADER
        return new(options).tap do |data|
          LibEXIF.exif_data_load_data(data, bytes, bytes.size.to_u32)
        end
      end
      load(options) do |loader|
        LibEXIF.exif_loader_write(loader, bytes, bytes.size.to_u32)
      end
    end

    # Loads EXIF data from the given *io*, reading only as much of it as needed.
    #
    # Raises `NoDataError` if no EXIF data is found.
    def self.new(io : IO, options : Options = Options.default) : self
      load(options) do |loader|
        buffer = Bytes.new(BUFFER_SIZE)
        while (read = io.read(buffer)) > 0
          break if LibEXIF.exif_loader_write(loader, buffer, read.to_u32).zero?
        end
      end
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

        new(options).tap do |data|
          LibEXIF.exif_data_load_data(data, buf, size)
        end
      ensure
        LibEXIF.exif_loader_unref(loader)
      end
    end

    def finalize
      LibEXIF.exif_data_unref(@ptr)
    end

    def to_unsafe : LibEXIF::EXIFData*
      @ptr
    end

    # Sets the options affecting loading and saving.
    def options=(options : Options) : Options
      Options.values.each do |option|
        if options.includes?(option)
          LibEXIF.exif_data_set_option(@ptr, option)
        else
          LibEXIF.exif_data_unset_option(@ptr, option)
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
      LibEXIF.exif_data_set_byte_order(@ptr, byte_order)
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
      raise ArgumentError.new("Invalid IFD: #{ifd}") unless ifd.in?(IFD.all)
      Content.new(self, @ptr.value.ifd[ifd.value])
    end

    # Returns the contents of all IFDs.
    def ifds : Array(Content)
      IFD.all.map { |ifd| ifd(ifd) }
    end

    # Yields each entry across all IFDs.
    def each(& : Entry ->) : Nil
      ifds.each do |content|
        content.each { |entry| yield entry }
      end
    end

    # Returns the total number of entries across all IFDs.
    def size : Int32
      ifds.sum(&.size)
    end

    # Returns `true` if there are no entries.
    def empty? : Bool
      ifds.all?(&.empty?)
    end

    # Returns the entry for the given *tag*, or `nil`.
    #
    # `Tag`s are looked up in the `IFD::Zero`, `IFD::EXIF`, `IFD::Interoperability`
    # and `IFD::One` (thumbnail) IFDs in turn, `GPSTag`s in the `IFD::GPS` one.
    def []?(tag : Tag) : Entry?
      TAG_LOOKUP_IFDS.each do |ifd|
        if entry = ifd(ifd)[tag]?
          return entry
        end
      end
      nil
    end

    # :ditto:
    def []?(tag : GPSTag) : Entry?
      ifd(:gps)[tag]?
    end

    # Returns the entry for the given *tag*.
    #
    # Raises `KeyError` if there's no such entry.
    def [](tag : Tag) : Entry
      self[tag]? || raise KeyError.new("Missing EXIF entry: #{tag}")
    end

    # :ditto:
    def [](tag : GPSTag) : Entry
      self[tag]? || raise KeyError.new("Missing EXIF entry: #{tag}")
    end

    # Returns `true` if there's an entry for the given *tag*.
    def has_key?(tag : Tag) : Bool
      !self[tag]?.nil?
    end

    # :ditto:
    def has_key?(tag : GPSTag) : Bool
      !self[tag]?.nil?
    end

    # Sets the *value* of the entry for the given *tag*.
    #
    # If there's no such entry, it's created in the IFD
    # the tag belongs to (see `Tag#default_ifd`).
    def []=(tag : Tag, value) : Nil
      if entry = self[tag]?
        entry.value = value
      else
        ifd = tag.default_ifd || raise ArgumentError.new("Cannot determine IFD for tag: #{tag}")
        ifd(ifd)[tag] = value
      end
    end

    # :ditto:
    def []=(tag : GPSTag, value) : Nil
      ifd(:gps)[tag] = value
    end

    # Removes the entry for the given *tag*, returning it (or `nil` if not found).
    def delete(tag : Tag) : Entry?
      self[tag]?.try(&.delete)
    end

    # :ditto:
    def delete(tag : GPSTag) : Entry?
      self[tag]?.try(&.delete)
    end

    # Returns the embedded thumbnail (usually a JPEG image), or `nil`.
    def thumbnail? : Bytes?
      ptr = @ptr.value.data
      Slice.new(ptr, @ptr.value.size.to_i).dup unless ptr.null? || @ptr.value.size.zero?
    end

    # Sets (or removes, if `nil`) the embedded thumbnail.
    def thumbnail=(bytes : Bytes?) : Bytes?
      EXIF.free(@ptr.value.data)
      @ptr.value.data = Pointer(UInt8).null
      @ptr.value.size = 0

      if bytes && !bytes.empty?
        ptr = EXIF.alloc(bytes.size)
        ptr.copy_from(bytes.to_unsafe, bytes.size)
        @ptr.value.data = ptr
        @ptr.value.size = bytes.size.to_u32
      end
      bytes
    end

    # Returns the parsed maker note, or `nil` if missing or unsupported.
    def maker_note? : MakerNote?
      ptr = LibEXIF.exif_data_get_mnote_data(@ptr)
      MakerNote.new(self, ptr) unless ptr.null?
    end

    # Fixes the EXIF data to bring it into specification
    # (adds mandatory entries, removes not-recorded ones, ...).
    def fix : self
      LibEXIF.exif_data_fix(@ptr)
      self
    end

    # Returns the raw EXIF block (including the `Exif\0\0` header),
    # suitable for embedding as a JPEG APP1 segment.
    def to_slice : Bytes
      buf = Pointer(UInt8).null
      size = 0_u32
      LibEXIF.exif_data_save_data(@ptr, pointerof(buf), pointerof(size))
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

    # Writes the JPEG image read from *source* with this EXIF data
    # embedded to *path*, replacing any existing EXIF data.
    def save(path : Path | String, source : Path | String = path) : Nil
      File.write(path, embed(File.read(source).to_slice))
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
