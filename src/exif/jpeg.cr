module EXIF
  # Minimal JPEG segment handling, used to embed EXIF data into JPEG files.
  #
  # NOTE: libexif itself does not write image files.
  module JPEG
    extend self

    SOI  = 0xD8_u8
    EOI  = 0xD9_u8
    SOS  = 0xDA_u8
    APP0 = 0xE0_u8
    APP1 = 0xE1_u8

    EXIF_HEADER = "Exif\0\0".to_slice

    # Maximum payload size of a single JPEG segment.
    MAX_SEGMENT_SIZE = UInt16::MAX - 2

    # Returns `true` if *bytes* start with a JPEG SOI marker.
    def jpeg?(bytes : Bytes) : Bool
      bytes.size >= 2 && bytes[0] == 0xFF && bytes[1] == SOI
    end

    # Returns a copy of the *jpeg* image with its EXIF segment(s)
    # replaced with *exif* (an APP1 payload, as returned by `Data#to_slice`).
    def embed(jpeg : Bytes, exif : Bytes) : Bytes
      unless exif[0, EXIF_HEADER.size]? == EXIF_HEADER
        raise JPEGError.new("Invalid EXIF payload (missing EXIF header)")
      end
      if exif.size > MAX_SEGMENT_SIZE
        raise JPEGError.new(
          "EXIF data too large (#{exif.size} > #{MAX_SEGMENT_SIZE} bytes), " \
          "consider removing the thumbnail (`Data#thumbnail = nil`)"
        )
      end

      rewrite(jpeg) do |io|
        io.write_byte 0xFF_u8
        io.write_byte APP1
        io.write_bytes (exif.size + 2).to_u16, IO::ByteFormat::BigEndian
        io.write exif
      end
    end

    # Returns a copy of the *jpeg* image without any EXIF segments.
    def strip(jpeg : Bytes) : Bytes
      rewrite(jpeg) { }
    end

    # Reads the payload of the first EXIF segment (starting with the `Exif\0\0` header)
    # from the JPEG stream *io*, positioned right after the SOI marker.
    #
    # Reads only up to the EXIF segment, skipping over any other ones, and returns
    # `nil` once the image data is reached, or for malformed and truncated streams.
    # A truncated EXIF segment is returned as is.
    def read_exif?(io : IO) : Bytes?
      loop do
        return unless io.read_byte == 0xFF

        # Skip fill bytes
        marker = io.read_byte
        while marker == 0xFF
          marker = io.read_byte
        end
        return if marker.nil? || marker == SOS || marker == EOI
        next if standalone?(marker)

        # The segment length includes the length field itself
        length = io.read_bytes(UInt16, IO::ByteFormat::BigEndian).to_i - 2
        return if length.negative?

        unless marker == APP1 && length >= EXIF_HEADER.size
          io.skip(length)
          next
        end
        payload = Bytes.new(length)
        payload = payload[0, EXIF.read_up_to(io, payload)]
        return payload if payload[0, EXIF_HEADER.size]? == EXIF_HEADER
      end
    rescue IO::EOFError
    end

    # Returns the offset of the first marker following the entropy-coded data
    # starting at *pos*, in which `0xFF` bytes are either stuffed (followed by `0x00`)
    # or start RSTn markers.
    private def scan_end(jpeg : Bytes, pos : Int32) : Int32
      while pos = jpeg.index(0xFF_u8, pos)
        following = jpeg[pos + 1]? || break
        return pos unless following.zero? || 0xD0 <= following <= 0xD7
        pos += 2
      end
      jpeg.size
    end

    # Returns `true` if *bytes* start with the EXIF header, or (if truncated) a part of it.
    private def exif_prefix?(bytes : Bytes) : Bool
      size = Math.min(bytes.size, EXIF_HEADER.size)
      bytes[0, size] == EXIF_HEADER[0, size]
    end

    # Returns `true` for markers which carry no length (TEM, RSTn).
    private def standalone?(marker : UInt8) : Bool
      marker == 0x01 || 0xD0 <= marker <= 0xD7
    end

    # ameba:disable Metrics/CyclomaticComplexity
    private def rewrite(jpeg : Bytes, & : IO ->) : Bytes
      raise JPEGError.new("Not a JPEG image (missing SOI marker)") unless jpeg?(jpeg)

      io = IO::Memory.new(jpeg.size + MAX_SEGMENT_SIZE)
      io.write jpeg[0, 2]

      inserted = false
      pos = 2

      while pos < jpeg.size
        raise JPEGError.new("Invalid JPEG marker at offset #{pos}") unless jpeg[pos] == 0xFF

        # Skip fill bytes
        while pos + 1 < jpeg.size && jpeg[pos + 1] == 0xFF
          pos += 1
        end
        marker = jpeg[pos + 1]? || raise JPEGError.new("Truncated JPEG marker")

        # Insert after APP0 (JFIF) segments, which by spec must come first
        unless inserted || marker == APP0
          yield io
          inserted = true
        end

        if marker == EOI
          io.write jpeg[pos..]
          break
        end

        if standalone?(marker)
          io.write jpeg[pos, 2]
          pos += 2
          next
        end

        # The segment length includes the length field itself (but not the marker)
        length = jpeg[pos + 2, 2]?.try { |bytes| IO::ByteFormat::BigEndian.decode(UInt16, bytes).to_i }
        if length && length < 2
          raise JPEGError.new("Invalid JPEG segment length (#{length}) at offset #{pos}")
        end

        # Copy truncated segments verbatim, unless they could hold EXIF data
        unless length && (segment = jpeg[pos, length + 2]?)
          if marker == APP1 && exif_prefix?(jpeg[Math.min(pos + 4, jpeg.size)..])
            raise JPEGError.new("Truncated EXIF segment at offset #{pos}")
          end
          io.write jpeg[pos..]
          break
        end

        unless marker == APP1 && segment[4, EXIF_HEADER.size]? == EXIF_HEADER
          io.write segment
        end
        pos += segment.size

        # Copy the entropy-coded data of a scan, which might be followed by
        # further segments (i.e. in progressive JPEG images)
        if marker == SOS
          scan_end = scan_end(jpeg, pos)
          io.write jpeg[pos...scan_end]
          pos = scan_end
        end
      end

      yield io unless inserted

      io.to_slice
    end
  end
end
