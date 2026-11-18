require "../spec_helper"

describe EXIF::Entry do
  it "exposes metadata" do
    entry = canon_data[:f_number]
    entry.tag.should eq EXIF::Tag::FNumber
    entry.ifd.should eq EXIF::IFD::EXIF
    entry.name.should eq "FNumber"
    entry.title.should eq "F-Number"
    entry.format.should eq EXIF::Format::Rational
    entry.components.should eq 1
    entry.bytesize.should eq 8
    entry.to_slice.size.should eq 8
  end

  it "formats values" do
    data = canon_data
    data[:f_number].to_s.should eq "f/2.8"
    data[:orientation].to_s.should eq "Right-top"
    data[:exif_version].to_s.should eq "Exif Version 2.2"
  end

  describe "#value" do
    it "decodes values" do
      data = canon_data
      data[:make].value.should eq "Canon"
      data[:orientation].value.should eq 6
      data[:f_number].value.should eq EXIF::URational.new(28, 10)
      data[:shutter_speed_value].value.should be_a(EXIF::SRational)
      data[:exif_version].value.should eq "0220".to_slice
    end
  end

  describe "#value=" do
    it "encodes integers" do
      data = EXIF::Data.new
      data[:image_width] = 4000
      data[:image_width].value.should eq 4000
    end

    it "encodes arrays" do
      data = EXIF::Data.new
      data[:bits_per_sample] = [8, 8, 8]
      data[:bits_per_sample].value.should eq [8, 8, 8]
      data[:bits_per_sample].components.should eq 3
    end

    it "encodes floats as rationals" do
      data = EXIF::Data.new
      data[:f_number] = 5.6
      data[:f_number].value.should eq EXIF::URational.new(28, 5)
      data[:exposure_bias_value] = -0.5
      data[:exposure_bias_value].value.should eq EXIF::SRational.new(-1, 2)
    end

    it "encodes bytes" do
      data = EXIF::Data.new
      data[:exif_version] = "0232".to_slice
      data[:exif_version].to_s.should eq "Exif Version 2.32"
    end

    it "encodes user comments" do
      data = EXIF::Data.new
      data[:user_comment] = "Hello"
      data[:user_comment].to_slice.should eq "ASCII\0\0\0Hello".to_slice
      data.user_comment.should eq "Hello"

      data[:user_comment] = "Zażółć"
      data[:user_comment].to_slice[0, 8].should eq "UNICODE\0".to_slice
      EXIF::Data.new(data.to_slice).user_comment.should eq "Zażółć"
    end

    it "encodes Windows XP tags as UTF-16" do
      data = EXIF::Data.new
      data[:xp_title] = "Tytuł"
      data[:xp_title].format.should eq EXIF::Format::Byte
      EXIF::Data.new(data.to_slice)[:xp_title].value.should eq "Tytuł"
    end

    it "raises on mismatched values" do
      data = EXIF::Data.new
      data[:orientation] = 1
      expect_raises(EXIF::ValueError) { data[:orientation].value = "top" }
      expect_raises(EXIF::ValueError) { data[:orientation].value = 70_000 }
      expect_raises(EXIF::ValueError) { data[:orientation].value = [] of Int32 }
    end
  end

  describe "#delete" do
    it "detaches the entry" do
      data = canon_data
      entry = data[:make].delete
      entry.ifd?.should be_nil
      entry.value.should eq "Canon"
      data.has_key?(:make).should be_false
    end
  end
end
