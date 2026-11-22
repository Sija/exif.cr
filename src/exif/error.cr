module EXIF
  # Base class for all errors raised by this library.
  class Error < Exception
  end

  # Raised when the given source contains no EXIF data.
  class NoDataError < Error
    def initialize(message = "No EXIF data found")
      super(message)
    end
  end

  # Raised when a value cannot be stored in an entry of the given format.
  class ValueError < Error
  end

  # Raised when a JPEG stream cannot be parsed or written.
  class JPEGError < Error
  end
end
