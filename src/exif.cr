require "log"

require "./lib/exif"
require "./exif/version"
require "./exif/error"
require "./exif/enums"
require "./exif/tag"
require "./exif/rational"
require "./exif/value"
require "./exif/entry"
require "./exif/content"
require "./exif/maker_note"
require "./exif/jpeg"
require "./exif/gps"
require "./exif/data"
require "./exif/data/properties"

# Crystal bindings to [libexif](https://libexif.github.io) and a friendly
# facade to read, modify and write EXIF metadata.
#
# ```
# require "exif"
#
# data = EXIF::Data.open("photo.jpg")
# data.model                # => "Canon PowerShot S70"
# data[:exposure_time].to_s # => "1/250 sec."
# data[:f_number].value     # => EXIF::URational(28/10)
# ```
module EXIF
  Log = ::Log.for(self)

  # :nodoc:
  #
  # Returns libexif's default memory allocator, used for every
  # buffer this library hands over to libexif.
  class_getter mem : LibEXIF::EXIFMem* { LibEXIF.exif_mem_new_default }

  # :nodoc:
  #
  # Returns a shared `EXIFLog` instance forwarding libexif messages to `EXIF::Log`.
  class_getter log : LibEXIF::EXIFLog* do
    LibEXIF.exif_log_new.tap do |log|
      LibEXIF.exif_log_set_func(log, ->(_log, code, domain, format, args, _data) {
        # Messages are only formatted if the given severity is enabled
        logger = EXIF.logger(domain)
        case code
        when .corrupt_data? then logger.warn { EXIF.format_message(format, args) }
        when .no_memory?    then logger.error { EXIF.format_message(format, args) }
        else                     logger.debug { EXIF.format_message(format, args) }
        end
      }, nil)
    end
  end

  @@loggers = {} of LibC::Char* => ::Log
  @@loggers_mutex = Mutex.new

  # :nodoc:
  #
  # Returns the logger for the given libexif *domain*.
  #
  # NOTE: libexif domains are static strings, so loggers are cached by their pointers.
  def self.logger(domain : LibC::Char*) : ::Log
    @@loggers_mutex.synchronize do
      @@loggers[domain] ||= Log.for(domain.null? ? "libexif" : String.new(domain))
    end
  end

  # :nodoc:
  #
  # Formats a libexif log message (a `printf` *format* with its `va_list` *args*).
  def self.format_message(format : LibC::Char*, args : Void*) : String
    buffer = uninitialized UInt8[1024]
    LibEXIF.vsnprintf(buffer.to_unsafe, buffer.size, format, args)
    String.new(buffer.to_unsafe)
  end

  # :nodoc:
  #
  # Allocates a buffer of *size* bytes using libexif's default memory allocator.
  def self.alloc(size : Int) : UInt8*
    ptr = LibEXIF.exif_mem_alloc(mem, size.to_u32).as(UInt8*)
    raise Error.new("Could not allocate #{size} byte(s)") if ptr.null?
    ptr
  end

  # :nodoc:
  #
  # Frees a buffer allocated with libexif's default memory allocator.
  def self.free(ptr : Pointer) : Nil
    LibEXIF.exif_mem_free(mem, ptr.as(Void*)) unless ptr.null?
  end

  # :nodoc:
  #
  # Returns a `String` or `nil` in case of a null pointer.
  def self.string?(ptr : LibC::Char*) : String?
    String.new(ptr) unless ptr.null?
  end
end
