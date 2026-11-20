lib LibEXIF
  type EXIFContentPrivate = Void

  # Holds all EXIF tags in a single IFD
  struct EXIFContent
    entries : EXIFEntry**
    count : LibC::UInt
    # Data containing this content
    parent : EXIFData*
    priv : EXIFContentPrivate*
  end

  alias EXIFContentForeachEntryFunc = EXIFEntry*, Void* -> Void

  fun exif_content_new : EXIFContent*
  fun exif_content_new_mem(mem : EXIFMem*) : EXIFContent*
  fun exif_content_ref(content : EXIFContent*)
  fun exif_content_unref(content : EXIFContent*)
  fun exif_content_free(content : EXIFContent*)

  fun exif_content_add_entry(c : EXIFContent*, entry : EXIFEntry*)
  fun exif_content_remove_entry(c : EXIFContent*, e : EXIFEntry*)
  fun exif_content_get_entry(content : EXIFContent*, tag : EXIFTag) : EXIFEntry*
  fun exif_content_fix(c : EXIFContent*)
  fun exif_content_foreach_entry(content : EXIFContent*, func : EXIFContentForeachEntryFunc, user_data : Void*)
  fun exif_content_get_ifd(c : EXIFContent*) : EXIFIfd
  fun exif_content_dump(content : EXIFContent*, indent : LibC::UInt)
  fun exif_content_log(content : EXIFContent*, log : EXIFLog*)
end
