# Removes EXIF data from the given JPEG image(s), keeping the orientation.
#
# Usage: crystal examples/strip.cr -- photo.jpg [...]
require "../src/exif"

ARGV.each do |path|
  jpeg = File.read(path).to_slice
  orientation = EXIF::Data.new(jpeg).orientation rescue nil

  if orientation
    data = EXIF::Data.new(options: :none)
    data.orientation = orientation
    File.write(path, data.embed(jpeg))
  else
    File.write(path, EXIF::JPEG.strip(jpeg))
  end
  puts "#{path}: stripped"
end
