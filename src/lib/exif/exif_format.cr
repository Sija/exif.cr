lib LibEXIF
  # EXIF tag data formats
  enum EXIFFormat
    Byte      =  1
    Ascii     =  2
    Short     =  3
    Long      =  4
    Rational  =  5
    SByte     =  6
    Undefined =  7
    SShort    =  8
    SLong     =  9
    SRational = 10
    Float     = 11
    Double    = 12
  end

  fun exif_format_get_name(format : EXIFFormat) : LibC::Char*
  fun exif_format_get_size(format : EXIFFormat) : UInt8
end
