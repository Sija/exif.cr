lib LibEXIF
  # EXIF Unsigned Byte data type
  alias EXIFByte = UInt8 # 1 byte

  # EXIF Signed Byte data type
  alias EXIFSByte = Int8 # 1 byte

  # EXIF Text String data type
  alias EXIFAscii = LibC::Char*

  # EXIF Unsigned Short data type
  alias EXIFShort = UInt16 # 2 bytes

  # EXIF Signed Short data type
  alias EXIFSShort = Int16 # 2 bytes

  # EXIF Unsigned Long data type
  alias EXIFLong = UInt32 # 4 bytes

  # EXIF Signed Long data type
  alias EXIFSLong = Int32 # 4 bytes

  # EXIF Undefined data type
  alias EXIFUndefined = LibC::Char # 1 byte

  # EXIF Unsigned Rational data type
  struct EXIFRational
    numerator : EXIFLong
    denominator : EXIFLong
  end

  # EXIF Signed Rational data type
  struct EXIFSRational
    numerator : EXIFSLong
    denominator : EXIFSLong
  end
end
