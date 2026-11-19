module EXIF
  # Holds all entries of a single `IFD`.
  #
  # ```
  # exif = data.ifd(:exif)
  # exif.size                  # => 30
  # exif[:exposure_time].value # => EXIF::URational(1/250)
  # exif.map(&.name)           # => ["ExposureTime", "FNumber", ...]
  # ```
  class Content
    include Enumerable(Entry)

    # Returns the `Data` this content belongs to.
    getter data : Data

    @ptr : LibEXIF::EXIFContent*

    protected def initialize(@data : Data, @ptr : LibEXIF::EXIFContent*)
      LibEXIF.exif_content_ref(@ptr)
    end

    def finalize
      LibEXIF.exif_content_unref(@ptr)
    end

    def to_unsafe : LibEXIF::EXIFContent*
      @ptr
    end

    # Returns another wrapper of the same libexif IFD.
    def dup : self
      self.class.new(data, @ptr)
    end

    # Returns the IFD this content represents.
    def ifd : IFD
      LibEXIF.exif_content_get_ifd(@ptr)
    end

    # Returns the number of entries.
    def size : Int32
      @ptr.value.count.to_i
    end

    # Returns `true` if there are no entries.
    def empty? : Bool
      size.zero?
    end

    # Yields each entry.
    def each(& : Entry ->) : Nil
      # Collect upfront, so that the block can safely modify the content
      data.retain { data.entries_of(@ptr) }.each { |entry| yield entry }
    end

    # Returns all entry tags.
    def tags : Array(AnyTag)
      map(&.tag)
    end

    # Returns the entry for the given *tag*, or `nil`.
    #
    # NOTE: `GPSTag`s are only found in the GPS IFD, and `Tag`s in all other ones.
    def []?(tag : AnyTag) : Entry?
      ptr = raw_entry(tag)
      Entry.new(data, ptr) unless ptr.null?
    end

    # Returns the entry for the given *tag*.
    #
    # Raises `KeyError` if there's no such entry.
    def [](tag : AnyTag) : Entry
      self[tag]? || raise KeyError.new("Missing EXIF entry: #{tag} (#{ifd})")
    end

    # Returns `true` if there's an entry for the given *tag*.
    def has_key?(tag : AnyTag) : Bool
      !raw_entry(tag).null?
    end

    # Sets the *value* of the entry for the given *tag*, creating it if needed.
    # Setting `nil` removes the entry.
    def []=(tag : AnyTag, value) : Nil
      entry = self[tag]?
      created = entry.nil?
      entry ||= create(tag)
      begin
        entry.value = value
      rescue ex
        entry.delete if created
        raise ex
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

    # Fixes the entries to bring them into specification
    # (adds mandatory entries, removes not-recorded ones, ...).
    def fix : self
      ptr = @ptr
      data.retain { LibEXIF.exif_content_fix(ptr) }
      self
    end

    # Returns a hash of entry names to their formatted values.
    def to_h : Hash(String, String)
      each_with_object({} of String => String) do |entry, hash|
        hash[entry.name] = entry.to_s
      end
    end

    def inspect(io : IO) : Nil
      io << "#<" << self.class.name << ' ' << ifd << " entries=" << size << '>'
    end

    # Returns `true` if the *tag* kind matches this IFD, since `GPSTag`s
    # overlap numerically with other tags.
    private def compatible?(tag : AnyTag) : Bool
      tag.is_a?(GPSTag) == ifd.gps?
    end

    private def raw_entry(tag : AnyTag) : LibEXIF::EXIFEntry*
      return Pointer(LibEXIF::EXIFEntry).null unless compatible?(tag)
      LibEXIF.exif_content_get_entry(@ptr, tag.to_tag)
    end

    private def create(tag : AnyTag) : Entry
      unless compatible?(tag)
        raise ArgumentError.new("Tag #{tag} cannot be stored in the #{ifd} IFD")
      end
      ptr = LibEXIF.exif_entry_new
      raise Error.new("Could not allocate EXIF entry") if ptr.null?
      begin
        # NOTE: libexif refuses to add an entry if one with the same tag already
        # exists, so the tag needs to be set upfront (`GPSTag::GPSVersionID` is `0`)
        ptr.value.tag = tag.to_tag
        LibEXIF.exif_content_add_entry(@ptr, ptr)
        raise Error.new("Could not add entry #{tag} to the #{ifd} IFD") if ptr.value.parent.null?

        LibEXIF.exif_entry_initialize(ptr, tag.to_tag)

        # libexif initializes tags it has no default value for as empty
        # `Format::Undefined` entries, so use the format defined by the specification,
        # or (for unknown tags) reset it to be inferred from the assigned value
        if ptr.value.data.null?
          if ptr.value.format.undefined?
            ptr.value.format = tag.spec_format || Format.new(0)
          end
          ptr.value.components = 0
          ptr.value.size = 0
        end
        Entry.new(data, ptr)
      ensure
        LibEXIF.exif_entry_unref(ptr)
      end
    end
  end
end
