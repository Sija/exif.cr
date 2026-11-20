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

  it "inserts EXIF data before a truncated APP0 segment" do
    # SOI, APP0 claiming 65535 bytes, truncated
    jpeg = Bytes[0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xFF, 1, 2, 3]
    embedded = EXIF::JPEG.embed(jpeg, exif)
    embedded[2, 2].should eq Bytes[0xFF, 0xE1]
    embedded[-7..].should eq jpeg[2..]
    EXIF::Data.new(embedded).model.should eq "Canon PowerShot S70"
  end

  it "refuses to keep truncated EXIF segments" do
    # SOI, APP1 claiming 65535 bytes, truncated within the EXIF header or after it
    [
      Bytes[0xFF, 0xD8, 0xFF, 0xE1],
      Bytes[0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0x45, 0x78],
      Bytes[0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF] + exif,
    ].each do |jpeg|
      expect_raises(EXIF::JPEGError, /Truncated EXIF segment/) { EXIF::JPEG.strip(jpeg) }
      expect_raises(EXIF::JPEGError, /Truncated EXIF segment/) { EXIF::JPEG.embed(jpeg, exif) }
    end

    # Other truncated APP1 segments (i.e. XMP) are kept as is
    jpeg = Bytes[0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF] + "http://ns.adobe.com/xap/1.0/\0".to_slice
    EXIF::JPEG.strip(jpeg).should eq jpeg
  end

  it "handles segments between scans" do
    segment = ->(marker : Int32, payload : Bytes) do
      Bytes[0xFF, marker] + Bytes[(payload.size + 2) >> 8, (payload.size + 2) & 0xFF] + payload
    end
    # Entropy-coded data with stuffed bytes, a RSTn marker and fill bytes (which get dropped)
    scan = Bytes[0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56, 0xFF, 0xFF]
    kept_scan = scan[0, scan.size - 2]
    exif_segment = segment.call(0xE1, exif)
    head = Bytes[0xFF, 0xD8] + segment.call(0xC2, Bytes.new(6))
    scan_head = segment.call(0xDA, Bytes.new(6))
    tables = segment.call(0xC4, Bytes.new(4))
    eoi = Bytes[0xFF, 0xD9, 0xAB]

    jpeg = head + exif_segment + scan_head + scan + exif_segment + tables + scan_head + scan + eoi
    first_scan = scan_head + kept_scan
    second_scan = tables + scan_head + kept_scan
    EXIF::JPEG.strip(jpeg).should eq head + first_scan + second_scan + eoi

    embedded = EXIF::JPEG.embed(jpeg, exif)
    embedded.should eq Bytes[0xFF, 0xD8] + exif_segment + head[2..] + first_scan + second_scan + eoi
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
