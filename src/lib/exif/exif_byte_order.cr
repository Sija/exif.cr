lib LibEXIF
  # Which byte order to use
  enum EXIFByteOrder
    # Big-endian byte order
    Motorola
    # Little-endian byte order
    Intel
  end

  fun exif_byte_order_get_name(order : EXIFByteOrder) : LibC::Char*

  fun exif_get_short(b : UInt8*, order : EXIFByteOrder) : EXIFShort
  fun exif_get_sshort(b : UInt8*, order : EXIFByteOrder) : EXIFSShort
  fun exif_get_long(b : UInt8*, order : EXIFByteOrder) : EXIFLong
  fun exif_get_slong(b : UInt8*, order : EXIFByteOrder) : EXIFSLong
  fun exif_get_rational(b : UInt8*, order : EXIFByteOrder) : EXIFRational
  fun exif_get_srational(b : UInt8*, order : EXIFByteOrder) : EXIFSRational

  fun exif_set_short(b : UInt8*, order : EXIFByteOrder, value : EXIFShort)
  fun exif_set_sshort(b : UInt8*, order : EXIFByteOrder, value : EXIFSShort)
  fun exif_set_long(b : UInt8*, order : EXIFByteOrder, value : EXIFLong)
  fun exif_set_slong(b : UInt8*, order : EXIFByteOrder, value : EXIFSLong)
  fun exif_set_rational(b : UInt8*, order : EXIFByteOrder, value : EXIFRational)
  fun exif_set_srational(b : UInt8*, order : EXIFByteOrder, value : EXIFSRational)
end
