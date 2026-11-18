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
    # Converts decimal *degrees* into a degrees/minutes/seconds triple of rationals.
    def self.to_dms(degrees : Float64) : Array(URational)
      degrees = degrees.abs
      d = degrees.floor
      m = ((degrees - d) * 60).floor
      s = ((degrees - d) * 60 - m) * 60
      [
        URational.new(d.to_i),
        URational.new(m.to_i),
        URational.new((s * 10_000).round.to_i64, 10_000).reduce,
      ]
    end

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
