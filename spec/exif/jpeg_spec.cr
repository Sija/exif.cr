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

  it "raises on invalid input" do
    expect_raises(EXIF::JPEGError) { EXIF::JPEG.embed(Bytes[1, 2, 3], exif) }
    expect_raises(EXIF::JPEGError) { EXIF::JPEG.embed(fixture("plain.jpg"), Bytes[1, 2, 3]) }
    expect_raises(EXIF::JPEGError) { EXIF::JPEG.embed(fixture("plain.jpg"), Bytes.new(70_000)) }
  end
end
