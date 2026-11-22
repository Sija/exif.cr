lib LibEXIF
  # State maintained by the logging interface
  type EXIFLog = Void

  enum EXIFLogCode
    None
    Debug
    NoMemory
    CorruptData
  end

  # Log callback function prototype.
  #
  # NOTE: `va_list` is declared as an opaque pointer, since on all supported
  # ABIs it's passed as a pointer-sized value when used as a function argument.
  alias EXIFLogFunc = EXIFLog*, EXIFLogCode, LibC::Char*, LibC::Char*, Void*, Void* -> Void

  fun exif_log_new : EXIFLog*
  fun exif_log_new_mem(mem : EXIFMem*) : EXIFLog*
  fun exif_log_ref(log : EXIFLog*)
  fun exif_log_unref(log : EXIFLog*)
  fun exif_log_free(log : EXIFLog*)

  fun exif_log_code_get_title(code : EXIFLogCode) : LibC::Char*
  fun exif_log_code_get_message(code : EXIFLogCode) : LibC::Char*

  fun exif_log_set_func(log : EXIFLog*, func : EXIFLogFunc, data : Void*)

  # Used to format the messages passed to `EXIFLogFunc`.
  fun vsnprintf(str : LibC::Char*, size : LibC::SizeT, format : LibC::Char*, ap : Void*) : LibC::Int
end
