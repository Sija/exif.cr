lib LibEXIF
  # Data found in the MakerNote tag
  type EXIFMnoteData = Void

  fun exif_mnote_data_ref(d : EXIFMnoteData*)
  fun exif_mnote_data_unref(d : EXIFMnoteData*)

  fun exif_mnote_data_load(d : EXIFMnoteData*, buf : UInt8*, buf_size : LibC::UInt)
  fun exif_mnote_data_save(d : EXIFMnoteData*, buf : UInt8**, buf_size : LibC::UInt*)

  fun exif_mnote_data_count(d : EXIFMnoteData*) : LibC::UInt
  fun exif_mnote_data_get_id(d : EXIFMnoteData*, n : LibC::UInt) : LibC::UInt
  fun exif_mnote_data_get_name(d : EXIFMnoteData*, n : LibC::UInt) : LibC::Char*
  fun exif_mnote_data_get_title(d : EXIFMnoteData*, n : LibC::UInt) : LibC::Char*
  fun exif_mnote_data_get_description(d : EXIFMnoteData*, n : LibC::UInt) : LibC::Char*
  fun exif_mnote_data_get_value(d : EXIFMnoteData*, n : LibC::UInt, val : LibC::Char*, maxlen : LibC::UInt) : LibC::Char*

  fun exif_mnote_data_log(d : EXIFMnoteData*, log : EXIFLog*)
end
