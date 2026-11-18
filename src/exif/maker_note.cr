module EXIF
  # Vendor-specific data found in the `Tag::MakerNote` entry.
  #
  # Only some maker notes (Canon, Fuji, Olympus, Pentax, Apple) are supported by libexif.
  #
  # ```
  # data.maker_note?.try &.each do |entry|
  #   puts "#{entry.title}: #{entry.value}"
  # end
  # ```
  class MakerNote
    # A single maker note entry.
    record Entry,
      id : UInt32,
      name : String?,
      title : String?,
      description : String?,
      value : String?

    include Enumerable(Entry)

    # Returns the `Data` this maker note belongs to.
    getter data : Data

    @ptr : LibEXIF::EXIFMnoteData*

    protected def initialize(@data : Data, @ptr : LibEXIF::EXIFMnoteData*)
      LibEXIF.exif_mnote_data_ref(@ptr)
    end

    def finalize
      LibEXIF.exif_mnote_data_unref(@ptr)
    end

    def to_unsafe : LibEXIF::EXIFMnoteData*
      @ptr
    end

    # Returns the number of entries.
    def size : Int32
      LibEXIF.exif_mnote_data_count(@ptr).to_i
    end

    # Yields each entry.
    def each(& : Entry ->) : Nil
      buffer = Bytes.new(1024)
      size.times do |i|
        n = i.to_u32
        value = LibEXIF.exif_mnote_data_get_value(@ptr, n, buffer, buffer.size)

        yield Entry.new(
          id: LibEXIF.exif_mnote_data_get_id(@ptr, n).to_u32,
          name: EXIF.string?(LibEXIF.exif_mnote_data_get_name(@ptr, n)),
          title: EXIF.string?(LibEXIF.exif_mnote_data_get_title(@ptr, n)),
          description: EXIF.string?(LibEXIF.exif_mnote_data_get_description(@ptr, n)),
          value: EXIF.string?(value),
        )
      end
    end

    # Returns the first entry with the given *name*, or `nil`.
    def []?(name : String) : Entry?
      find(&.name.== name)
    end

    # Returns the first entry with the given *name*.
    def [](name : String) : Entry
      self[name]? || raise KeyError.new("Missing maker note entry: #{name}")
    end

    # Returns a hash of entry names to their formatted values.
    def to_h : Hash(String, String?)
      each_with_object({} of String => String?) do |entry, hash|
        hash[entry.name || entry.id.to_s] = entry.value
      end
    end

    def inspect(io : IO) : Nil
      io << "#<" << self.class.name << " entries=" << size << '>'
    end
  end
end
