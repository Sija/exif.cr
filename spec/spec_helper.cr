require "spec"
require "../src/exif"

def fixture_path(name : String) : String
  File.join(__DIR__, "fixtures", name)
end

def fixture(name : String) : Bytes
  File.read(fixture_path(name)).to_slice
end

def canon_data : EXIF::Data
  EXIF::Data.open(fixture_path("canon.jpg"))
end
