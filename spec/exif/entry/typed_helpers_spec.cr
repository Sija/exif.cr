require "../../spec_helper"

describe EXIF::Entry do
  context "typed helpers" do
    data = canon_data

    it "#as_s" do
      data[:model].as_s.should eq "Canon PowerShot S70"
      data[:model].as_s?.should eq "Canon PowerShot S70"
      data[:orientation].as_s?.should be_nil
      expect_raises(TypeCastError, "Expected String value of the Orientation entry, not Int64") do
        data[:orientation].as_s
      end
    end

    it "#as_i" do
      data[:orientation].as_i.should eq 6
      data[:model].as_i?.should be_nil
      data[:f_number].as_i?.should be_nil
      expect_raises(TypeCastError) { data[:model].as_i }
    end

    it "#as_f" do
      data[:f_number].as_f.should eq 2.8
      data[:orientation].as_f.should eq 6.0
      data[:model].as_f?.should be_nil
      expect_raises(TypeCastError) { data[:model].as_f }

      undefined = EXIF::Data.new
      undefined[:f_number] = EXIF::URational.new(1, 0)
      undefined[:f_number].as_f.nan?.should be_true
    end

    it "#as_rational" do
      data[:f_number].as_rational.should eq EXIF::URational.new(28, 10)
      data[:shutter_speed_value].as_rational.should be_a(EXIF::SRational)
      data[:orientation].as_rational?.should be_nil
      expect_raises(TypeCastError) { data[:orientation].as_rational }
    end

    it "#as_bytes" do
      data[:exif_version].as_bytes.should eq "0220".to_slice
      data[:model].as_bytes?.should be_nil
      expect_raises(TypeCastError) { data[:model].as_bytes }
    end

    it "#as_a" do
      gps = EXIF::Data.new
      gps.gps = EXIF::GPS.new(52.5, 13.25)
      gps[:gps_latitude].as_a.should eq [EXIF::URational.new(52), EXIF::URational.new(30), EXIF::URational.new(0)]
      data[:model].as_a.should eq ["Canon PowerShot S70"]
      data[:exif_version].as_a?.should be_nil
      expect_raises(TypeCastError) { data[:exif_version].as_a }
    end

    it "doesn't treat arrays as single values" do
      array = EXIF::Data.new
      array[:bits_per_sample] = [8, 8, 8]
      array[:bits_per_sample].as_i?.should be_nil
      array[:bits_per_sample].as_f?.should be_nil
      array[:bits_per_sample].as_a.should eq [8, 8, 8]
    end
  end
end
