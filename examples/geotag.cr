# Sets the GPS position of the given JPEG image.
#
# Usage: crystal examples/geotag.cr -- photo.jpg LATITUDE LONGITUDE [ALTITUDE]
require "../src/exif"

path, latitude, longitude, altitude = ARGV[0], ARGV[1].to_f, ARGV[2].to_f, ARGV[3]?.try(&.to_f)

data = EXIF::Data.open?(path) || EXIF::Data.new.tap do |empty|
  # mandatory entries (resolution, EXIF version, ...)
  empty.data_type = :compressed
  empty.fix
end
data.gps = EXIF::GPS.new(latitude, longitude, altitude)
data.save(path)

puts "#{path}: #{EXIF::Data.open(path).gps}"
