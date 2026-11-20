lib LibEXIF
  # Represents the type of image data to which the EXIF data applies.
  enum EXIFDataType
    UncompressedChunky = 0
    UncompressedPlanar
    UncompressedYCC
    Compressed
    Count

    Unknown = Count
  end
end
