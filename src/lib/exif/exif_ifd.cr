lib LibEXIF
  # Possible EXIF Image File Directories
  enum EXIFIfd
    Zero             = 0
    One
    EXIF
    GPS
    Interoperability
    Count # Not a real value, just (max_value + 1)
  end

  IFD_COUNT = 5

  fun exif_ifd_get_name(ifd : EXIFIfd) : LibC::Char*
end
