lib LibEXIF
  type EXIFDataPrivate = Void

  # Represents the entire EXIF data found in an image
  struct EXIFData
    # Data for each IFD
    ifd : EXIFContent*[IFD_COUNT]
    # Pointer to thumbnail image, or `NULL` if not available
    data : UInt8*
    # Number of bytes in thumbnail image at `data`
    size : LibC::UInt
    priv : EXIFDataPrivate*
  end

  # Options to configure the behaviour of `EXIFData`
  @[Flags]
  enum EXIFDataOption
    # Act as though unknown tags are not present
    IgnoreUnknownTags = 1 << 0
    # Fix the EXIF tags to follow the spec
    FollowSpecification = 1 << 1
    # Leave the MakerNote alone, which could cause it to be corrupted
    DontChangeMakerNote = 1 << 2
  end

  alias EXIFDataForeachContentFunc = EXIFContent*, Void* -> Void

  fun exif_data_new : EXIFData*
  fun exif_data_new_mem(mem : EXIFMem*) : EXIFData*
  fun exif_data_new_from_file(path : LibC::Char*) : EXIFData*
  fun exif_data_new_from_data(data : UInt8*, size : LibC::UInt) : EXIFData*

  fun exif_data_load_data(data : EXIFData*, d : UInt8*, size : LibC::UInt)
  fun exif_data_save_data(data : EXIFData*, d : UInt8**, ds : LibC::UInt*)

  fun exif_data_ref(data : EXIFData*)
  fun exif_data_unref(data : EXIFData*)
  fun exif_data_free(data : EXIFData*)

  fun exif_data_get_byte_order(data : EXIFData*) : EXIFByteOrder
  fun exif_data_set_byte_order(data : EXIFData*, order : EXIFByteOrder)

  fun exif_data_get_mnote_data(d : EXIFData*) : EXIFMnoteData*
  fun exif_data_fix(d : EXIFData*)
  fun exif_data_foreach_content(data : EXIFData*, func : EXIFDataForeachContentFunc, user_data : Void*)

  fun exif_data_option_get_name(o : EXIFDataOption) : LibC::Char*
  fun exif_data_option_get_description(o : EXIFDataOption) : LibC::Char*
  fun exif_data_set_option(d : EXIFData*, o : EXIFDataOption)
  fun exif_data_unset_option(d : EXIFData*, o : EXIFDataOption)

  fun exif_data_set_data_type(d : EXIFData*, dt : EXIFDataType)
  fun exif_data_get_data_type(d : EXIFData*) : EXIFDataType

  fun exif_data_dump(data : EXIFData*)
  fun exif_data_log(data : EXIFData*, log : EXIFLog*)
end
