module EXIF
  class Data
    # Format of the EXIF date/time strings.
    TIME_FORMAT = "%Y:%m:%d %H:%M:%S"

    {% for name, tag in {
                          make:               "Make",
                          model:              "Model",
                          software:           "Software",
                          artist:             "Artist",
                          copyright:          "Copyright",
                          image_description:  "ImageDescription",
                          user_comment:       "UserComment",
                          lens_make:          "LensMake",
                          lens_model:         "LensModel",
                          body_serial_number: "BodySerialNumber",
                          camera_owner_name:  "CameraOwnerName",
                          image_unique_id:    "ImageUniqueID",
                        } %}
      # Returns the value of the `Tag::{{ tag.id }}` entry, or `nil`.
      def {{ name.id }} : String?
        string?(Tag::{{ tag.id }})
      end

      # Sets (or removes, if `nil`) the value of the `Tag::{{ tag.id }}` entry.
      def {{ name.id }}=(value : String?) : String?
        set_property(Tag::{{ tag.id }}, value)
        value
      end
    {% end %}

    {% for name, tags in {
                           date_time:           {"DateTime", "OffsetTime", "SubSecTime"},
                           date_time_original:  {"DateTimeOriginal", "OffsetTimeOriginal", "SubSecTimeOriginal"},
                           date_time_digitized: {"DateTimeDigitized", "OffsetTimeDigitized", "SubSecTimeDigitized"},
                         } %}
      # Returns the time from the `Tag::{{ tags[0].id }}` entry, taking the
      # `Tag::{{ tags[1].id }}` and `Tag::{{ tags[2].id }}` entries into account.
      #
      # When no time offset is recorded, the time is assumed to be in the given *location*.
      def {{ name.id }}(location : Time::Location = Time::Location::UTC) : Time?
        parse_time(Tag::{{ tags[0].id }}, Tag::{{ tags[1].id }}, Tag::{{ tags[2].id }}, location)
      end

      # Sets the `Tag::{{ tags[0].id }}` and `Tag::{{ tags[1].id }}` entries (or removes them, if `nil`).
      def {{ name.id }}=(time : Time?) : Time?
        write_time(time, Tag::{{ tags[0].id }}, Tag::{{ tags[1].id }}, Tag::{{ tags[2].id }})
      end
    {% end %}

    # Returns the time the image was taken (alias of `#date_time_original`,
    # falling back to `#date_time`).
    def taken_at(location : Time::Location = Time::Location::UTC) : Time?
      date_time_original(location) || date_time(location)
    end

    # Returns the image orientation, or `nil`.
    def orientation : Orientation?
      int?(Tag::Orientation).try { |value| Orientation.from_value?(value) }
    end

    # Sets the image orientation (or removes it, if `nil`).
    def orientation=(orientation : Orientation?) : Orientation?
      set_property(Tag::Orientation, orientation.try(&.value))
      orientation
    end

    # Returns the image width (in pixels), or `nil`.
    def width : Int64?
      int?(Tag::PixelXDimension) || int?(Tag::ImageWidth)
    end

    # Returns the image height (in pixels), or `nil`.
    def height : Int64?
      int?(Tag::PixelYDimension) || int?(Tag::ImageLength)
    end

    # Returns the exposure time (in seconds), or `nil`.
    def exposure_time : URational?
      scalar?(Tag::ExposureTime).as?(URational)
    end

    # Returns the F-number, or `nil`.
    def f_number : Float64?
      float?(Tag::FNumber)
    end

    # Returns the ISO speed, or `nil`.
    #
    # Since EXIF 2.3, `Tag::ISOSpeedRatings` (*PhotographicSensitivity*) is set
    # to 65535 when the actual value doesn't fit, in which case it's taken from
    # `Tag::ISOSpeed`, `Tag::RecommendedExposureIndex` or `Tag::StandardOutputSensitivity`.
    def iso : Int64?
      iso = int?(Tag::ISOSpeedRatings)
      return iso if iso && iso < UInt16::MAX

      int?(Tag::ISOSpeed) ||
        int?(Tag::RecommendedExposureIndex) ||
        int?(Tag::StandardOutputSensitivity) ||
        iso
    end

    # Returns the exposure bias (in EV), or `nil`.
    def exposure_bias : Float64?
      float?(Tag::ExposureBiasValue)
    end

    # Returns the focal length (in millimeters), or `nil`.
    def focal_length : Float64?
      float?(Tag::FocalLength)
    end

    # Returns the 35mm-equivalent focal length (in millimeters), or `nil`.
    def focal_length_in_35mm_film : Int64?
      int?(Tag::FocalLengthIn35mmFilm)
    end

    # Returns whether the flash fired, or `nil` if unknown.
    def flash_fired? : Bool?
      int?(Tag::Flash).try(&.bit(0).==(1))
    end

    # Returns the GPS position, or `nil` if not recorded.
    #
    # NOTE: Besides the degrees/minutes/seconds triples required by the specification,
    # coordinates stored as a single value (decimal degrees) are accepted too.
    def gps : GPS?
      return unless latitude = coordinate?(GPSTag::GPSLatitude, GPSTag::GPSLatitudeRef, "S")
      return unless longitude = coordinate?(GPSTag::GPSLongitude, GPSTag::GPSLongitudeRef, "W")

      altitude = float?(GPSTag::GPSAltitude)
      altitude = -altitude if altitude && int?(GPSTag::GPSAltitudeRef) == 1

      GPS.new(latitude, longitude, altitude.try { |value| value if value.finite? })
    end

    # Returns the coordinate (in decimal degrees) from the *tag* entry, negated
    # if the *ref_tag* entry equals *negative_ref*, or `nil` if missing or malformed.
    private def coordinate?(tag : GPSTag, ref_tag : GPSTag, negative_ref : String) : Float64?
      values =
        case value = self[tag]?.try(&.value)
        when Array                    then value
        when Rational, Int64, Float64 then [value]
        else                               return
        end
      return if values.empty? || values.size > 3

      degrees = GPS.from_dms(values)
      return unless degrees.finite?

      string?(ref_tag).try(&.upcase) == negative_ref ? -degrees : degrees
    end

    # Sets the GPS position (or removes it, if `nil`).
    #
    # NOTE: Any existing GPS entries (i.e. `GPSTag::GPSTimeStamp` or
    # `GPSTag::GPSDestLatitude`) are removed, since they might no longer apply.
    #
    # Raises `ValueError` if the latitude or longitude is out of range.
    def gps=(gps : GPS?) : GPS?
      if gps
        unless gps.latitude.abs <= 90 && gps.longitude.abs <= 180
          raise ValueError.new("Invalid GPS position: #{gps}")
        end
        if (altitude = gps.altitude) && !altitude.finite?
          raise ValueError.new("Invalid GPS altitude: #{altitude}")
        end
      end
      ifd(:gps).each(&.delete)
      return unless gps

      self[GPSTag::GPSVersionID] = Bytes[2, 2, 0, 0]
      self[GPSTag::GPSLatitudeRef] = gps.latitude.negative? ? "S" : "N"
      self[GPSTag::GPSLatitude] = GPS.to_dms(gps.latitude)
      self[GPSTag::GPSLongitudeRef] = gps.longitude.negative? ? "W" : "E"
      self[GPSTag::GPSLongitude] = GPS.to_dms(gps.longitude)

      if altitude = gps.altitude
        self[GPSTag::GPSAltitudeRef] = Bytes[altitude.negative? ? 1 : 0]
        self[GPSTag::GPSAltitude] = URational.new(altitude.abs)
      end
      gps
    end

    # IFDs describing the primary image, searched by the properties
    # (i.e. excluding `IFD::One`, which describes the thumbnail).
    PRIMARY_IFDS = {IFD::Zero, IFD::EXIF, IFD::Interoperability}

    # Returns the entry for the given *tag* describing the primary image, or `nil`.
    private def property(tag : Tag) : Entry?
      find_entry(tag, PRIMARY_IFDS)
    end

    # :ditto:
    private def property(tag : GPSTag) : Entry?
      self[tag]?
    end

    # Sets (or removes, if `nil`) the *value* of the primary image entry for the given *tag*.
    private def set_property(tag : Tag, value) : Nil
      entry = property(tag)
      case
      when value.nil? then entry.try(&.delete)
      when entry      then entry.value = value
      else
        ifd(PRIMARY_IFDS.find { |ifd| tag.known_in?(ifd) } || IFD::Zero)[tag] = value
      end
    end

    private def scalar?(tag : AnyTag) : Value?
      return unless entry = property(tag)
      value = entry.value
      value.is_a?(Array) ? value.first? : value
    end

    private def string?(tag : AnyTag) : String?
      value = scalar?(tag).as?(String).try(&.strip)
      value unless value.nil? || value.empty?
    end

    private def int?(tag : AnyTag) : Int64?
      scalar?(tag).as?(Int64)
    end

    private def float?(tag : AnyTag) : Float64?
      case value = scalar?(tag)
      when Rational
        value.to_f unless value.undefined?
      when Int64, Float64
        value.to_f
      end
    end

    # Returns the time from the *tag* entry, or `nil` if missing or malformed.
    private def parse_time(tag : Tag, offset_tag : Tag, subsec_tag : Tag, location : Time::Location) : Time?
      return unless string = string?(tag)

      location = parse_offset(offset_tag) || location
      time = begin
        Time.parse(string, TIME_FORMAT, location)
      rescue Time::Format::Error | ArgumentError
        # Malformed (i.e. `"    :  :     :  :  "`) or out of range (i.e. month 13)
        return
      end

      if (subsec = string?(subsec_tag)) && subsec.each_char.all?(&.ascii_number?)
        time += (("0." + subsec).to_f * 1_000_000_000).round.to_i.nanoseconds
      end
      time
    end

    # Returns the time zone from the *tag* entry (i.e. `"+01:00"`),
    # or `nil` if missing or malformed.
    private def parse_offset(tag : Tag) : Time::Location?
      return unless offset = string?(tag)
      return unless match = offset.match(/\A([+-])(\d{2}):(\d{2})\z/)

      seconds = match[2].to_i * 3600 + match[3].to_i * 60
      Time::Location.fixed(match[1] == "-" ? -seconds : seconds)
    rescue Time::Location::InvalidTimezoneOffsetError
    end

    private def write_time(time : Time?, tag : Tag, offset_tag : Tag, subsec_tag : Tag) : Time?
      if time
        set_property(tag, time.to_s(TIME_FORMAT))
        set_property(offset_tag, time.to_s("%:z"))
        # Fractional seconds, with trailing zeros removed (`nil` if none)
        subsec = time.to_s("%N").rstrip('0').presence
        set_property(subsec_tag, subsec)
      else
        {tag, offset_tag, subsec_tag}.each { |key| set_property(key, nil) }
      end
      time
    end
  end
end
