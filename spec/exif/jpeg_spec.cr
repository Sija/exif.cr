require "../spec_helper"

describe EXIF::JPEG do
  exif = canon_data.to_slice

  it "embeds EXIF data into an image without it" do
    jpeg = EXIF::JPEG.embed(fixture("plain.jpg"), exif)
    EXIF::JPEG.jpeg?(jpeg).should be_true
    EXIF::Data.new(jpeg).model.should eq "Canon PowerShot S70"
  end

  it "keeps the JFIF APP0 segment first" do
    jpeg = EXIF::JPEG.embed(fixture("plain.jpg"), exif)
    jpeg[2, 2].should eq Bytes[0xFF, 0xE0]
  end

  it "replaces existing EXIF data" do
    data = EXIF::Data.new
    data.artist = "Jane"

    jpeg = EXIF::JPEG.embed(fixture("canon.jpg"), data.to_slice)
    loaded = EXIF::Data.new(jpeg)
    loaded.artist.should eq "Jane"
    loaded.has_key?(:model).should be_false
  end

  it "strips EXIF data" do
    jpeg = EXIF::JPEG.strip(fixture("canon.jpg"))
    expect_raises(EXIF::NoDataError) { EXIF::Data.new(jpeg) }
  end

  it "suggests removing the thumbnail when the EXIF data is too large" do
    data = EXIF::Data.new
    data.thumbnail = Bytes.new(70_000)
    expect_raises(EXIF::JPEGError, /too large.*thumbnail/) { data.embed(fixture("plain.jpg")) }

    data.thumbnail = nil
    EXIF::Data.new(data.embed(fixture("plain.jpg"))).thumbnail?.should be_nil
  end

  it "handles segments of the maximum length" do
    # SOI, APP2 claiming 65535 bytes, truncated
    jpeg = Bytes[0xFF, 0xD8, 0xFF, 0xE2, 0xFF, 0xFF, 1, 2, 3]
    EXIF::JPEG.strip(jpeg).should eq jpeg
    EXIF::JPEG.embed(jpeg, exif)[0, 4].should eq Bytes[0xFF, 0xD8, 0xFF, 0xE1]

    # complete
    segment = Bytes[0xFF, 0xE2, 0xFF, 0xFF] + Bytes.new(65_533)
    jpeg = Bytes[0xFF, 0xD8] + segment + Bytes[0xFF, 0xD9]
    EXIF::JPEG.strip(jpeg).should eq jpeg
  end

  it "raises on invalid segment lengths" do
    {0, 1}.each do |length|
      jpeg = Bytes[0xFF, 0xD8, 0xFF, 0xE2, 0, length, 0xFF, 0xD9]
      expect_raises(EXIF::JPEGError, /Invalid JPEG segment length/) { EXIF::JPEG.strip(jpeg) }
    end
  end

  it "raises on invalid input" do
    expect_raises(EXIF::JPEGError) { EXIF::JPEG.embed(Bytes[1, 2, 3], exif) }
    expect_raises(EXIF::JPEGError) { EXIF::JPEG.embed(fixture("plain.jpg"), Bytes[1, 2, 3]) }
    expect_raises(EXIF::JPEGError) { EXIF::JPEG.embed(fixture("plain.jpg"), Bytes.new(70_000)) }
  end
end
