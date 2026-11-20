# Removes EXIF data from the given JPEG image(s), keeping the orientation.
#
# NOTE: The orientation is read only from EXIF data preceding the image data
# (as the specification requires), while EXIF segments are removed throughout.
#
# Usage: crystal examples/strip.cr -- photo.jpg [...]
require "../src/exif"

ARGV.each do |path|
  # The image is replaced atomically, so it's never left partially written
  EXIF::JPEG.update(path) do |jpeg|
    orientation =
      begin
        EXIF::Data.new(jpeg).orientation
      rescue EXIF::NoDataError
      end

    if orientation
      data = EXIF::Data.new(options: :none)
      data.orientation = orientation
      data.embed(jpeg)
    else
      EXIF::JPEG.strip(jpeg)
    end
  end
  puts "#{path}: stripped"
end
