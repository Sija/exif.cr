module EXIF
  # Byte order of the EXIF data.
  alias ByteOrder = LibEXIF::EXIFByteOrder

  # Type of the image data to which the EXIF data applies.
  alias DataType = LibEXIF::EXIFDataType

  # Data format of an `Entry`.
  alias Format = LibEXIF::EXIFFormat

  # Image File Directory (IFD), i.e. a group of entries.
  alias IFD = LibEXIF::EXIFIfd

  # All (real) IFDs, excluding `IFD::Count`.
  IFDS = {IFD::Zero, IFD::One, IFD::EXIF, IFD::GPS, IFD::Interoperability}

  # Level of support a `Tag` enjoys in the given `IFD`.
  alias SupportLevel = LibEXIF::EXIFSupportLevel

  # Options affecting how `Data` is loaded and saved.
  alias Options = LibEXIF::EXIFDataOption

  # Class of a libexif log message.
  alias LogCode = LibEXIF::EXIFLogCode

  # Image orientation, as stored in the `Tag::Orientation` entry.
  enum Orientation : UInt16
    TopLeft     = 1
    TopRight    = 2
    BottomRight = 3
    BottomLeft  = 4
    LeftTop     = 5
    RightTop    = 6
    RightBottom = 7
    LeftBottom  = 8

    # Returns `true` if the image width and height are swapped.
    def transposed? : Bool
      value >= 5
    end
  end
end

enum LibEXIF::EXIFByteOrder
  # Returns the localized name of the byte order.
  def label : String
    ::EXIF.string?(LibEXIF.exif_byte_order_get_name(self)) || to_s
  end

  # Returns the matching `IO::ByteFormat`.
  def byte_format : IO::ByteFormat
    motorola? ? IO::ByteFormat::BigEndian : IO::ByteFormat::LittleEndian
  end
end

enum LibEXIF::EXIFFormat
  # Returns the textual name of the format.
  def label : String
    ::EXIF.string?(LibEXIF.exif_format_get_name(self)) || to_s
  end

  # Returns the size (in bytes) of a single component of this format.
  def bytesize : Int32
    LibEXIF.exif_format_get_size(self).to_i
  end
end

enum LibEXIF::EXIFIfd
  # Returns the textual name of the IFD.
  def label : String
    ::EXIF.string?(LibEXIF.exif_ifd_get_name(self)) || to_s
  end

  # All real IFDs (excluding `Count`).
  def self.all : Array(self)
    ::EXIF::IFDS.to_a
  end
end

@[Flags]
enum LibEXIF::EXIFDataOption
  # libexif's default options.
  def self.default : self
    IgnoreUnknownTags | FollowSpecification
  end

  # Returns the short name of the option.
  def label : String
    ::EXIF.string?(LibEXIF.exif_data_option_get_name(self)) || to_s
  end

  # Returns the description of the option.
  def description : String?
    ::EXIF.string?(LibEXIF.exif_data_option_get_description(self))
  end
end

enum LibEXIF::EXIFLogCode
  # Returns the textual title of the log code.
  def title : String?
    ::EXIF.string?(LibEXIF.exif_log_code_get_title(self))
  end

  # Returns the verbose message of the log code.
  def message : String?
    ::EXIF.string?(LibEXIF.exif_log_code_get_message(self))
  end
end
