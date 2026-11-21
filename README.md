# exif.cr [![CI](https://github.com/Sija/exif.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/Sija/exif.cr/actions/workflows/ci.yml) [![Releases](https://img.shields.io/github/release/Sija/exif.cr.svg)](https://github.com/Sija/exif.cr/releases) [![License](https://img.shields.io/github/license/Sija/exif.cr.svg)](https://github.com/Sija/exif.cr/blob/master/LICENSE)

**exif.cr** provides an FFI for [libexif][libexif].
It also includes a facade to read, modify and write EXIF metadata in a more idiomatic Crystal way.

## Features

- Reading EXIF data from JPEG files, `IO`s, byte slices and raw EXIF blocks (with or without the `Exif\0\0` header, i.e. from PNG `eXIf` chunks)
- Typed entry values (`String`, `Int64`, `Float64`, rationals, arrays, ...), with `#as_s`-style helpers
- Human-readable (localized) entry values, as formatted by libexif
- Semantic accessors for common tags (camera, exposure, time, orientation, GPS, ...)
- Creating, modifying and removing entries
- Embedding EXIF data into JPEG files (and stripping it)
- Thumbnail access (r/w)
- Maker notes (Canon, Fuji, Olympus, Pentax, Apple) [^1]

[^1]: Read-only, as supported by libexif

## Installation

### Prerequisites

  * Crystal: `>= 1.19.0`
  * libexif: `>= 0.6.24`

To install libexif, you can use `homebrew` or `apt-get`, depending on the platform:

#### macOS

```
$ brew install libexif
```

#### Debian/Ubuntu

```
$ apt-get install libexif-dev
```

### Shard

Add this to your application's `shard.yml`:

```yaml
dependencies:
  exif:
    github: Sija/exif.cr
```

## Usage

```crystal
require "exif"

# load EXIF data from a JPEG file
data = EXIF::Data.open("photo.jpg")

# ...or return `nil` instead of raising `EXIF::NoDataError` if there's none
data = EXIF::Data.open?("photo.jpg")

# ...or from an `IO` (reading only as much as needed), or a `Bytes` slice
data = File.open("photo.jpg") { |file| EXIF::Data.new(file) }
data = EXIF::Data.new(bytes)

# use semantic accessors
data.model         # => "Canon PowerShot S70"
data.taken_at      # => 2009-10-10 16:42:32 UTC
data.orientation   # => EXIF::Orientation::RightTop
data.exposure_time # => EXIF::URational(1/250)
data.f_number      # => 2.8
data.gps           # => EXIF::GPS(@latitude=52.2297, @longitude=21.0122, @altitude=110.5)

# ...or access the entries directly
entry = data[:f_number]
entry.name   # => "FNumber"
entry.title  # => "F-Number"
entry.ifd    # => EXIF::IFD::EXIF
entry.format # => EXIF::Format::Rational
entry.value  # => EXIF::URational(28/10)
entry.to_s   # => "f/2.8"

# typed helpers, raising `TypeCastError` on mismatch (`nil` for the `?` variants)
data[:model].as_s            # => "Canon PowerShot S70"
data[:orientation].as_i      # => 6
data[:f_number].as_f         # => 2.8 (converting integers and rationals)
data[:f_number].as_rational  # => EXIF::URational(28/10)
data[:exif_version].as_bytes # => Bytes[48, 50, 50, 48]
data[:gps_latitude].as_a     # => [EXIF::URational(52/1), EXIF::URational(13/1), ...]
data[:model].as_i?           # => nil

# GPS tags have their own enum, since they overlap with other tags
data[:gps_latitude].value # => [EXIF::URational(52/1), EXIF::URational(13/1), ...]

# missing entries
data[:artist]  # raises KeyError
data[:artist]? # => nil

# iterate over all entries...
data.each do |entry|
  puts "#{entry.title}: #{entry}"
end

# ...or the ones within a given IFD
data.ifd(:exif).map(&.name) # => ["ExposureTime", "FNumber", ...]

# vendor-specific maker notes
data.maker_note?.try &.each do |entry|
  puts "#{entry.title}: #{entry.value}"
end

# embedded thumbnail
if thumbnail = data.thumbnail?
  File.write("thumbnail.jpg", thumbnail)
end
```

### Writing

```crystal
data = EXIF::Data.open("photo.jpg")

# set values, entries are created within the proper IFD if needed
data[:artist] = "Jane Doe"
data[:image_width] = 4000
data[:f_number] = 5.6 # => stored as EXIF::URational(28/5)
data[:bits_per_sample] = [8, 8, 8]
data[:user_comment] = "Zażółć gęślą jaźń" # => character code is handled for you

# ...or use semantic setters
data.copyright = "(c) Jane Doe"
data.date_time_original = Time.local
data.orientation = :top_left
data.gps = EXIF::GPS.new(52.2297, 21.0122, altitude: 110.5)

# remove entries
data.delete(:maker_note)
data.artist = nil

# write it back into the image (replacing any existing EXIF data)...
data.save("photo.jpg")

# ...or into another one
data.save("copy.jpg", source: "other.jpg")

# raw EXIF block (APP1 payload), e.g. to embed it yourself
data.to_slice # => Bytes[69, 120, 105, 102, 0, 0, ...]

# strip EXIF data from a JPEG image
EXIF::JPEG.strip(File.read("photo.jpg").to_slice)

# ...or replace the file in place (atomically, see `Data#save`)
EXIF::JPEG.update("photo.jpg") { |jpeg| EXIF::JPEG.strip(jpeg) }
```

### Options

By default, libexif fixes the data to follow the specification when loading,
which might add or remove entries. Pass `options` to change that:

```crystal
data = EXIF::Data.open("photo.jpg", options: :none)
data = EXIF::Data.open("photo.jpg", options: EXIF::Options::IgnoreUnknownTags)

data.options # => EXIF::Options::IgnoreUnknownTags
```

### Corrupt data

Problems found while loading (i.e. truncated or corrupted entries) don't make
loading fail, as long as anything could be loaded; check `#warnings` to find out:

```crystal
data = EXIF::Data.open("photo.jpg")
data.warnings # => ["Tag data past end of buffer (188 > 494)", "Bogus offset of IFD1."]
```

### Logging

libexif messages are forwarded to the `exif` [`Log`](https://crystal-lang.org/api/Log.html) source:

```crystal
Log.setup("exif.*", :debug)
```

### Limitations

- Only JPEG images (and raw EXIF blocks) are supported. TIFF-based formats
  (TIFF, DNG and most camera RAW formats) can't be read reliably, since libexif
  only loads the first 64 KiB of data, while their metadata can be anywhere in the file.
- `Data#save` replaces the file atomically, keeping its permissions, owner and group;
  it refuses to replace files whose owner it can't keep (i.e. other users' files),
  or whose group it can't keep while the group has other permissions than others. Being a new file,
  it doesn't keep extended attributes (i.e. macOS Finder tags) nor other hard links to the file.
- Maker notes are read-only, and reflect the data as loaded. A new `MakerNote` value
  (only allowed in the EXIF IFD) is saved as is, so one copied over from another image might not be readable
  (some vendors store offsets relative to the start of the EXIF data within it).

## Examples

See the [`examples`](examples) directory, e.g.:

```
$ crystal run examples/dump.cr -- photo.jpg
$ crystal run examples/summary.cr -- photo.jpg
$ crystal run examples/geotag.cr -- photo.jpg 52.2297 21.0122
$ crystal run examples/strip.cr -- photo.jpg
```

## Development

```
$ crystal spec
$ ./lib/ameba/bin/ameba.cr
```

Test fixture `spec/fixtures/canon.jpg` comes from the [libexif test suite](https://github.com/libexif/libexif/tree/master/test/testdata).

## Contributing

1. Fork it (<https://github.com/Sija/exif.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Sijawusz Pur Rahnama](https://github.com/Sija) - creator and maintainer

[libexif]: https://github.com/libexif/libexif
