lib LibEXIF
  # Should work like `calloc()`
  alias EXIFMemAllocFunc = EXIFLong -> Void*
  # Should work like `realloc()`
  alias EXIFMemReallocFunc = Void*, EXIFLong -> Void*
  # Free method for `EXIFMem`
  alias EXIFMemFreeFunc = Void* -> Void

  # Defines a memory allocator
  type EXIFMem = Void

  fun exif_mem_new(a : EXIFMemAllocFunc, r : EXIFMemReallocFunc, f : EXIFMemFreeFunc) : EXIFMem*
  fun exif_mem_new_default : EXIFMem*
  fun exif_mem_ref(mem : EXIFMem*)
  fun exif_mem_unref(mem : EXIFMem*)

  fun exif_mem_alloc(mem : EXIFMem*, s : EXIFLong) : Void*
  fun exif_mem_realloc(mem : EXIFMem*, p : Void*, s : EXIFLong) : Void*
  fun exif_mem_free(mem : EXIFMem*, p : Void*)
end
