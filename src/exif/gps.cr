module EXIF
  # Geographic position decoded from the GPS `IFD`.
  #
  # Latitude and longitude are expressed in decimal degrees
  # (negative for South and West respectively), altitude in meters
  # (negative below sea level).
  record GPS,
    latitude : Float64,
    longitude : Float64,
    altitude : Float64? = nil do
    # Converts decimal *degrees* into a degrees/minutes/seconds triple of rationals,
    # with seconds rounded to 1/10000th.
    def self.to_dms(degrees : Float64) : Array(URational)
      # Round once in the smallest unit, so that i.e. 59.99999" carries over to the minutes
      total = (degrees.abs * 3600 * DMS_PRECISION).round.to_i64
      minutes, seconds = total.divmod(60 * DMS_PRECISION)
      degrees, minutes = minutes.divmod(60)
      [
        URational.new(degrees),
        URational.new(minutes),
        URational.new(seconds, DMS_PRECISION).reduce,
      ]
    end

    # Precision (fractions of a second) used by `.to_dms`.
    DMS_PRECISION = 10_000

    # Converts a degrees/minutes/seconds array into decimal degrees.
    def self.from_dms(dms : Array) : Float64
      dms.map_with_index { |value, i| value.to_f / 60.0 ** i }.sum
    end

    def to_s(io : IO) : Nil
      io << latitude << ", " << longitude
      if altitude = @altitude
        io << " (" << altitude << " m)"
      end
    end
  end
end
