require "../spec_helper"

describe EXIF::Format do
  it "returns labels" do
    EXIF::Format::Rational.label.should eq "Rational"
  end

  it "falls back to the numeric value for invalid formats" do
    # i.e. the format of entries unknown to libexif, before a value is assigned
    EXIF::Format.new(0).label.should eq "0"
  end
end

describe EXIF::ByteOrder do
  it "returns labels" do
    EXIF::ByteOrder::Intel.label.should eq "Intel"
    EXIF::ByteOrder.new(42).label.should eq "42"
  end
end

describe EXIF::IFD do
  it "returns labels" do
    EXIF::IFD::EXIF.label.should eq "EXIF"
    EXIF::IFD::Count.label.should eq "Count"
  end
end
