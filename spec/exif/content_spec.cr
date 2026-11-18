require "../spec_helper"

describe EXIF::Content do
  it "exposes entries of an IFD" do
    content = canon_data.ifd(:zero)
    content.ifd.should eq EXIF::IFD::Zero
    content.size.should eq 8
    content.tags.first.should eq EXIF::Tag::Make
    content[:model].value.should eq "Canon PowerShot S70"
    content[:exposure_time]?.should be_nil
  end

  it "rejects GPS tags outside of the GPS IFD" do
    expect_raises(ArgumentError) { EXIF::Data.new.ifd(:zero)[:gps_latitude] = "N" }
    expect_raises(ArgumentError) { EXIF::Data.new.ifd(:gps)[:make] = "Canon" }
  end

  it "doesn't find tags of the other kind (GPS tags overlap numerically)" do
    data = EXIF::Data.new
    data[:gps_latitude_ref] = "N"
    data.ifd(:gps)[:interoperability_index]?.should be_nil
    data.ifd(:gps).has_key?(:interoperability_index).should be_false
    data.ifd(:gps)[:gps_latitude_ref].value.should eq "N"

    data.ifd(:interoperability)[:interoperability_index] = "R98"
    data.ifd(:interoperability)[:gps_latitude_ref]?.should be_nil
  end

  it "allows modifications while iterating" do
    content = canon_data.ifd(:zero)
    content.each(&.delete)
    content.empty?.should be_true
  end

  it "fixes entries" do
    content = EXIF::Data.new.ifd(:zero)
    content.fix
    content.has_key?(:x_resolution).should be_true
  end
end
