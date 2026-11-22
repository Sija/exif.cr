lib LibEXIF
  # Internal data used by libexif itself
  type EXIFEntryPrivate = Void

  # Data found in one EXIF tag
  struct EXIFEntry
    # EXIF tag for this entry
    tag : EXIFTag
    # Type of data in this entry
    format : EXIFFormat
    # Number of elements in the array, if this is an array entry.
    # Contains 1 for non-array data types.
    components : LibC::ULong
    # Pointer to the raw EXIF data for this entry. It is allocated
    # by `exif_entry_initialize` and is `NULL` beforehand.
    data : UInt8*
    # Number of bytes in the buffer at `data`. This must be no less
    # than `exif_format_get_size(format) * components`
    size : LibC::UInt
    # `EXIFContent` containing this entry
    parent : EXIFContent*
    # Internal data to be used by libexif itself
    priv : EXIFEntryPrivate*
  end

  fun exif_entry_new : EXIFEntry*
  fun exif_entry_new_mem(mem : EXIFMem*) : EXIFEntry*
  fun exif_entry_ref(entry : EXIFEntry*)
  fun exif_entry_unref(entry : EXIFEntry*)
  fun exif_entry_free(entry : EXIFEntry*)

  fun exif_entry_initialize(e : EXIFEntry*, tag : EXIFTag)
  fun exif_entry_fix(entry : EXIFEntry*)

  fun exif_entry_get_value(entry : EXIFEntry*, val : LibC::Char*, maxlen : LibC::UInt) : LibC::Char*
  fun exif_entry_dump(entry : EXIFEntry*, indent : LibC::UInt)
end
