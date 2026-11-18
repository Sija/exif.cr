# Prints a short summary of the photo(s) using the semantic accessors.
#
# Usage: crystal examples/summary.cr -- photo.jpg [...]
require "../src/exif"

ARGV.each do |path|
  data = EXIF::Data.open(path)

  summary = {
    "Camera"      => [data.make, data.model].compact.join(' ').presence,
    "Lens"        => data.lens_model,
    "Taken at"    => data.taken_at,
    "Size"        => ("#{data.width}x#{data.height}" if data.width && data.height),
    "Orientation" => data.orientation,
    "Exposure"    => data.exposure_time.try { |time| "#{time.reduce} s" },
    "Aperture"    => data.f_number.try { |number| "f/#{number}" },
    "ISO"         => data.iso,
    "Focal"       => data.focal_length.try { |length| "#{length} mm" },
    "Location"    => data.gps,
  }

  puts path
  summary.each do |label, value|
    puts "  %-12s %s" % {label, value} if value
  end
rescue ex : EXIF::NoDataError
  STDERR.puts "#{path}: #{ex.message}"
end
