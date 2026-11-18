require "../../spec_helper"

describe EXIF::Data do
  context "properties" do
    it "reads common properties" do
      data = canon_data
      data.make.should eq "Canon"
      data.model.should eq "Canon PowerShot S70"
      data.artist.should be_nil
      data.orientation.should eq EXIF::Orientation::RightTop
      data.width.should eq 640
      data.height.should eq 480
      data.exposure_time.should eq EXIF::URational.new(1, 1)
      data.f_number.should eq 2.8
      data.focal_length.should eq 5.8125
      data.exposure_bias.should eq 0.0
      data.flash_fired?.should be_false
      data.iso.should be_nil
    end

    it "ignores thumbnail (IFD1) entries" do
      data = EXIF::Data.new
      data.ifd(:one)[:image_width] = 160
      data.ifd(:one)[:orientation] = 3
      data.ifd(:one)[:make] = "Thumb"

      data.width.should be_nil
      data.orientation.should be_nil
      data.make.should be_nil

      data.orientation = :right_top
      data.make = "Canon"
      data.ifd(:zero)[:orientation].value.should eq 6
      data.ifd(:zero)[:make].value.should eq "Canon"
      data.ifd(:one)[:orientation].value.should eq 3
      data.ifd(:one)[:make].value.should eq "Thumb"

      data.make = nil
      data.ifd(:zero).has_key?(:make).should be_false
      data.ifd(:one).has_key?(:make).should be_true
    end

    it "reads times" do
      data = canon_data
      data.date_time.should eq Time.utc(2009, 10, 10, 16, 42, 32)
      data.taken_at.should eq Time.utc(2009, 10, 10, 16, 42, 32)

      location = Time::Location.fixed(7200)
      data.date_time_original(location).should eq Time.local(2009, 10, 10, 16, 42, 32, location: location)
    end

    it "writes string properties" do
      data = EXIF::Data.new
      data.artist = "Jane Doe"
      data.copyright = "(c) Jane Doe"
      data.artist.should eq "Jane Doe"
      data[:copyright].value.should eq "(c) Jane Doe"

      data.artist = nil
      data.has_key?(:artist).should be_false
    end

    it "writes times with offsets and fractions" do
      time = Time.local(2024, 1, 2, 3, 4, 5, nanosecond: 120_000_000, location: Time::Location.fixed(-5 * 3600))

      data = EXIF::Data.new
      data.date_time_original = time
      data[:date_time_original].value.should eq "2024:01:02 03:04:05"
      data[:offset_time_original].value.should eq "-05:00"
      data[:sub_sec_time_original].value.should eq "120"

      loaded = EXIF::Data.new(data.to_slice)
      loaded.date_time_original.should eq time
      loaded.date_time_original.try(&.offset).should eq -5 * 3600
    end

    it "writes the orientation" do
      data = EXIF::Data.new
      data.orientation = :left_bottom
      data[:orientation].value.should eq 8
      data.orientation.try(&.transposed?).should be_true
    end

    it "reads and writes the GPS position" do
      data = EXIF::Data.new
      data.gps.should be_nil

      data.gps = EXIF::GPS.new(-33.8568, 151.2153, -12.5)
      data[:gps_latitude_ref].value.should eq "S"
      data[:gps_longitude_ref].value.should eq "E"
      data[:gps_version_id].value.should eq [2, 2, 0, 0]

      gps = EXIF::Data.new(data.to_slice).gps.should_not be_nil
      gps.latitude.should be_close(-33.8568, 0.00001)
      gps.longitude.should be_close(151.2153, 0.00001)
      gps.altitude.should eq -12.5

      data.gps = nil
      data.ifd(:gps).empty?.should be_true
    end
  end
end
