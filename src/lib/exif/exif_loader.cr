lib LibEXIF
  # Data used by the loader interface
  type EXIFLoader = Void

  fun exif_loader_new : EXIFLoader*
  fun exif_loader_new_mem(mem : EXIFMem*) : EXIFLoader*
  fun exif_loader_ref(loader : EXIFLoader*)
  fun exif_loader_unref(loader : EXIFLoader*)

  fun exif_loader_write_file(loader : EXIFLoader*, fname : LibC::Char*)
  fun exif_loader_write(loader : EXIFLoader*, buf : UInt8*, sz : LibC::UInt) : UInt8
  fun exif_loader_reset(loader : EXIFLoader*)
  fun exif_loader_get_data(loader : EXIFLoader*) : EXIFData*
  fun exif_loader_get_buf(loader : EXIFLoader*, buf : UInt8**, buf_size : LibC::UInt*)
  fun exif_loader_log(loader : EXIFLoader*, log : EXIFLog*)
end
