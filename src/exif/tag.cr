module EXIF
  # EXIF tag, i.e. an identifier of an `Entry`.
  #
  # NOTE: GPS tags reuse numeric values of other tags, so they live
  # in a separate enum, see `GPSTag`.
  alias Tag = LibEXIF::EXIFTag

  # EXIF tag found in the GPS `IFD`.
  alias GPSTag = LibEXIF::EXIFGPSTag

  # Either kind of tag.
  alias AnyTag = Tag | GPSTag

  # IFDs in which (non-GPS) `Tag`s are looked up, in order of priority.
  TAG_LOOKUP_IFDS = {IFD::Zero, IFD::EXIF, IFD::Interoperability, IFD::One}
end

enum LibEXIF::EXIFTag
  # Returns the tag with the given EXIF *name* (i.e. `"FNumber"`), or `nil`.
  #
  # NOTE: Names of GPS tags return `nil`, use `GPSTag.from_name?` instead.
  def self.from_name?(name : String) : self?
    tag = LibEXIF.exif_tag_from_name(name)
    # libexif resolves GPS tag names too, which overlap numerically with other tags
    tag unless tag.value.zero? || LibEXIF::EXIFGPSTag.from_name?(name)
  end

  # Returns the tag with the given EXIF *name* (i.e. `"FNumber"`).
  def self.from_name(name : String) : self
    from_name?(name) || raise ArgumentError.new("Unknown EXIF tag: #{name.inspect}")
  end

  # Returns the EXIF name of the tag (i.e. `"FNumber"`).
  def name(ifd : LibEXIF::EXIFIfd? = nil) : String?
    ::EXIF.string? \
      ifd ? LibEXIF.exif_tag_get_name_in_ifd(self, ifd) : LibEXIF.exif_tag_get_name(self)
  end

  # Returns the localized title of the tag (i.e. `"F-Number"`).
  def title(ifd : LibEXIF::EXIFIfd? = nil) : String?
    ::EXIF.string? \
      ifd ? LibEXIF.exif_tag_get_title_in_ifd(self, ifd) : LibEXIF.exif_tag_get_title(self)
  end

  # Returns the localized description of the tag.
  def description(ifd : LibEXIF::EXIFIfd? = nil) : String?
    ::EXIF.string? \
      ifd ? LibEXIF.exif_tag_get_description_in_ifd(self, ifd) : LibEXIF.exif_tag_get_description(self)
  end

  # Returns the support level of the tag in the given *ifd*.
  def support_level(ifd : LibEXIF::EXIFIfd, data_type : LibEXIF::EXIFDataType = :unknown) : LibEXIF::EXIFSupportLevel
    LibEXIF.exif_tag_get_support_level_in_ifd(self, ifd, data_type)
  end

  # Returns `true` if the tag is known to be recorded in the given *ifd*.
  def known_in?(ifd : LibEXIF::EXIFIfd) : Bool
    !LibEXIF.exif_tag_get_name_in_ifd(self, ifd).null?
  end

  # Returns the IFD in which an entry of this tag should be created.
  def default_ifd : LibEXIF::EXIFIfd?
    lookup_ifds.find { |ifd| known_in?(ifd) }
  end

  # Returns the IFDs in which entries of this tag are looked up, in order of priority.
  def lookup_ifds
    ::EXIF::TAG_LOOKUP_IFDS
  end

  # Returns `self`.
  def to_tag : self
    self
  end
end

enum LibEXIF::EXIFGPSTag
  # Returns the tag with the given EXIF *name* (i.e. `"GPSLatitude"`), or `nil`.
  def self.from_name?(name : String) : self?
    values.find(&.name.== name)
  end

  # Returns the tag with the given EXIF *name* (i.e. `"GPSLatitude"`).
  def self.from_name(name : String) : self
    from_name?(name) || raise ArgumentError.new("Unknown EXIF GPS tag: #{name.inspect}")
  end

  # Returns the EXIF name of the tag (i.e. `"GPSLatitude"`).
  def name : String?
    to_tag.name(:gps)
  end

  # Returns the localized title of the tag.
  def title : String?
    to_tag.title(:gps)
  end

  # Returns the localized description of the tag.
  def description : String?
    to_tag.description(:gps)
  end

  # Returns the support level of the tag in the GPS IFD.
  def support_level(data_type : LibEXIF::EXIFDataType = :unknown) : LibEXIF::EXIFSupportLevel
    to_tag.support_level(:gps, data_type)
  end

  # Returns `IFD::GPS`.
  def default_ifd : LibEXIF::EXIFIfd
    LibEXIF::EXIFIfd::GPS
  end

  # Returns the IFDs in which entries of this tag are looked up (`IFD::GPS`).
  def lookup_ifds
    {LibEXIF::EXIFIfd::GPS}
  end

  # Returns the raw (numeric) `Tag` value, as used by libexif.
  def to_tag : LibEXIF::EXIFTag
    LibEXIF::EXIFTag.new(value)
  end
end
