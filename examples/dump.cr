# Prints all EXIF entries found in the given image(s).
#
# Usage: crystal examples/dump.cr -- photo.jpg [...]
require "../src/exif"

ARGV.each do |path|
  unless data = EXIF::Data.open?(path)
    STDERR.puts "#{path}: no EXIF data found"
    next
  end

  puts "#{path} (#{data.byte_order} byte order)"
  data.ifds.reject(&.empty?).each do |content|
    puts "  [#{content.ifd.label}]"
    content.each do |entry|
      puts "    %-32s %s" % {entry.title || entry.name, entry}
    end
  end

  if maker_note = data.maker_note?
    puts "  [MakerNote]"
    maker_note.each do |entry|
      puts "    %-32s %s" % {entry.title || entry.name || entry.id, entry.value}
    end
  end

  if thumbnail = data.thumbnail?
    puts "  Thumbnail: #{thumbnail.size} bytes"
  end
end
