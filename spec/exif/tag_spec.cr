require "../spec_helper"

describe EXIF::Tag do
  it "returns names, titles and descriptions" do
    EXIF::Tag::FNumber.name.should eq "FNumber"
    EXIF::Tag::FNumber.title.should eq "F-Number"
    EXIF::Tag::FNumber.description.should_not be_nil
  end

  it "resolves names within the given IFD" do
    EXIF::Tag::InteroperabilityIndex.name(:interoperability).should eq "InteroperabilityIndex"
  end

  describe ".from_name?" do
    it "finds tags by name" do
      EXIF::Tag.from_name?("Model").should eq EXIF::Tag::Model
      EXIF::Tag.from_name("ExposureTime").should eq EXIF::Tag::ExposureTime
    end

    it "returns nil for unknown names" do
      EXIF::Tag.from_name?("Bogus").should be_nil
      expect_raises(ArgumentError) { EXIF::Tag.from_name("Bogus") }
    end
  end

  it "returns the support level" do
    EXIF::Tag::EXIFVersion.support_level(:exif, :compressed).should eq EXIF::SupportLevel::Mandatory
    EXIF::Tag::EXIFVersion.support_level(:gps, :compressed).should eq EXIF::SupportLevel::NotRecorded
  end

  it "returns the default IFD" do
    EXIF::Tag::Make.default_ifd.should eq EXIF::IFD::Zero
    EXIF::Tag::ExposureTime.default_ifd.should eq EXIF::IFD::EXIF
  end
end

describe EXIF::GPSTag do
  it "returns names and titles" do
    EXIF::GPSTag::GPSLatitude.name.should eq "GPSLatitude"
    EXIF::GPSTag::GPSLatitude.title.should eq "Latitude"
  end

  it "maps onto raw tag values" do
    EXIF::GPSTag::GPSLatitude.to_tag.value.should eq 0x0002
    EXIF::GPSTag::GPSLatitude.default_ifd.should eq EXIF::IFD::GPS
  end

  it "finds tags by name" do
    EXIF::GPSTag.from_name?("GPSAltitude").should eq EXIF::GPSTag::GPSAltitude
    EXIF::GPSTag.from_name?("Model").should be_nil
  end
end
