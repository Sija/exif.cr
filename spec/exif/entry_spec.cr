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

    it "decodes entries without data as empty values of their format" do
      data = EXIF::Data.new
      clear = ->(entry : EXIF::Entry) do
        raw = entry.to_unsafe
        EXIF.free(raw.value.data)
        raw.value.data, raw.value.size, raw.value.components = Pointer(UInt8).null, 0_u32, 0_u64
        entry
      end

      data[:orientation] = 1
      clear.call(data[:orientation]).value.should eq [] of Int64
      data[:orientation].as_a.should be_empty

      data[:x_resolution] = 72
      clear.call(data[:x_resolution]).value.should eq [] of EXIF::URational

      data[:model] = "x"
      clear.call(data[:model]).value.should eq ""

      data[:maker_note] = Bytes[1]
      clear.call(data[:maker_note]).value.should eq Bytes.empty
    end
  end

  it "decodes non-UTF-8 text as ISO-8859-1" do
    data = EXIF::Data.new
    data[:make] = String.new(Bytes[0x4E, 0x69, 0x6B, 0xF3, 0x6E])
    data[:make].value.should eq "Nikón"
    data.make.try(&.valid_encoding?).should be_true

    data[:user_comment] = "ASCII\0\0\0Caf".to_slice + Bytes[0xE9]
    data.user_comment.should eq "Café"
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

    it "decodes Unicode user comments with byte order marks" do
      {EXIF::ByteOrder::Intel, EXIF::ByteOrder::Motorola}.each do |byte_order|
        data = EXIF::Data.new
        data.byte_order = byte_order

        data[:user_comment] = "UNICODE\0".to_slice + Bytes[0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00]
        data.user_comment.should eq "Hi"

        data[:user_comment] = "UNICODE\0".to_slice + Bytes[0xFE, 0xFF, 0x00, 0x48, 0x00, 0x69]
        data.user_comment.should eq "Hi"
      end
    end

    it "strips the padding of user comments" do
      data = EXIF::Data.new
      data.byte_order = :motorola
      data[:user_comment] = "ASCII\0\0\0Hi  \0".to_slice
      data.user_comment.should eq "Hi"

      data[:user_comment] = "UNICODE\0".to_slice + Bytes[0, 0x48, 0, 0x69, 0, 0x20, 0, 0x20]
      data[:user_comment].value.should eq "Hi"
    end

    it "converts Unicode user comments when changing the byte order" do
      data = EXIF::Data.new
      data.byte_order = :intel
      data.user_comment = "Zażółć"

      data.byte_order = :motorola
      data.user_comment.should eq "Zażółć"
      data[:user_comment].to_slice[8, 2].should eq Bytes[0x00, 0x5A]
      EXIF::Data.new(data.to_slice).user_comment.should eq "Zażółć"

      data.byte_order = :motorola # unchanged
      data.byte_order = :intel
      data.user_comment.should eq "Zażółć"

      # Comments with byte order marks are left as they are
      bom = "UNICODE\0".to_slice + Bytes[0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00]
      data[:user_comment] = bom
      data.byte_order = :motorola
      data[:user_comment].to_slice.should eq bom
      data.user_comment.should eq "Hi"
    end

    it "encodes Windows XP tags as UTF-16" do
      data = EXIF::Data.new
      data[:xp_title] = "Tytuł"
      data[:xp_title].format.should eq EXIF::Format::Byte
      EXIF::Data.new(data.to_slice)[:xp_title].value.should eq "Tytuł"
    end

    it "leaves the entry intact when the value can't be stored" do
      data = EXIF::Data.new
      data[:orientation] = 6
      expect_raises(EXIF::ValueError) { data[:orientation].value = 70_000 }
      expect_raises(EXIF::ValueError) { data[:orientation].value = [1, 70_000] }
      data[:orientation].value.should eq 6
      data[:orientation].components.should eq 1

      data[:model] = "Canon"
      expect_raises(EXIF::ValueError) { data[:model].value = 1 }
      data[:model].value.should eq "Canon"
    end

    it "raises ValueError for out of range floats" do
      data = EXIF::Data.new
      expect_raises(EXIF::ValueError) { data[:f_number] = -2.8 }
      expect_raises(EXIF::ValueError) { data[:f_number] = Float64::NAN }
      data.has_key?(:f_number).should be_false
    end

    it "uses the specification formats for tags without a libexif default" do
      data = EXIF::Data.new
      data[:subject_area] = [1, 2]
      data[:subject_area].format.should eq EXIF::Format::Short

      data[:lens_specification] = [24, 70, 4, 4]
      data[:lens_specification].format.should eq EXIF::Format::Rational
      data[:lens_specification].value.should eq [24, 70, 4, 4].map { |v| EXIF::URational.new(v) }

      data[:offset_time] = "+01:00"
      data[:offset_time].format.should eq EXIF::Format::Ascii
      expect_raises(EXIF::ValueError) { data[:lens_model] = 5 }

      data[EXIF::GPSTag::GPSHPositioningError] = 2.5
      data[EXIF::GPSTag::GPSHPositioningError].format.should eq EXIF::Format::Rational
    end

    it "keeps the formats libexif initializes tags without a default with" do
      data = EXIF::Data.new
      expect_raises(EXIF::ValueError) { data[:gps_latitude_ref] = 1 }
      data[:gps_latitude_ref] = "N"
      data[:gps_latitude_ref].format.should eq EXIF::Format::Ascii
    end

    it "infers the format for unknown tags" do
      tag = EXIF::Tag.new(0xc0de)
      content = EXIF::Data.new.ifd(:exif)
      content[tag] = -0.5
      content[tag].format.should eq EXIF::Format::SRational
      content[tag].value.should eq EXIF::SRational.new(-1, 2)

      content[tag] = nil
      content[tag] = "foo"
      content[tag].format.should eq EXIF::Format::Ascii
    end

    it "infers the format for unknown tags from all values" do
      tag = EXIF::Tag.new(0xc0de)
      content = EXIF::Data.new.ifd(:exif)
      {
        [1, 2]                          => {EXIF::Format::Long, [1_i64, 2_i64]},
        [1, -1]                         => {EXIF::Format::SLong, [1_i64, -1_i64]},
        [2, 1.5]                        => {EXIF::Format::Rational, [EXIF::URational.new(2), EXIF::URational.new(3, 2)]},
        [1, -0.5]                       => {EXIF::Format::SRational, [EXIF::SRational.new(1), EXIF::SRational.new(-1, 2)]},
        [EXIF::URational.new(1, 3), -2] => {EXIF::Format::SRational, [EXIF::SRational.new(1, 3), EXIF::SRational.new(-2)]},
        [1, EXIF::SRational.new(1, 3)]  => {EXIF::Format::SRational, [EXIF::SRational.new(1), EXIF::SRational.new(1, 3)]},
      }.each do |values, (format, decoded)|
        content[tag] = nil
        content[tag] = values
        content[tag].format.should eq format
        content[tag].value.should eq decoded
      end

      content[tag] = nil
      expect_raises(EXIF::ValueError) { content[tag] = [1, "foo"] }
      content.has_key?(tag).should be_false
    end

    it "doesn't set tags generated by libexif" do
      data = canon_data
      expect_raises(ArgumentError, /thumbnail/) { data[:jpeg_interchange_format] = 65_536 }
      expect_raises(ArgumentError, /thumbnail/) { data[:jpeg_interchange_format_length] = 4 }
      expect_raises(ArgumentError) { data[:exif_ifd_pointer] = 0 }
      expect_raises(ArgumentError) { data.ifd(:zero)[:gps_info_ifd_pointer] = 0 }
      expect_raises(ArgumentError) { data[:interoperability_ifd_pointer] = 0 }

      EXIF::Data.new(data.to_slice).model.should eq "Canon PowerShot S70"
      data.has_key?(:exif_ifd_pointer).should be_false
    end

    it "stores values beyond SHORT range as LONG for tags allowing both" do
      data = canon_data
      data[:pixel_x_dimension].format.should eq EXIF::Format::Short
      data[:pixel_x_dimension] = 70_000
      data[:pixel_x_dimension].format.should eq EXIF::Format::Long
      data.width.should eq 70_000

      data[:image_width] = 100_000
      data[:image_width].format.should eq EXIF::Format::Long
      data[:image_width].value.should eq 100_000

      loaded = EXIF::Data.new(data.to_slice)
      loaded.width.should eq 70_000
      loaded[:image_width].value.should eq 100_000
    end

    it "keeps SHORT format for values in range" do
      data = EXIF::Data.new
      data[:image_width] = 640
      data[:image_width].format.should eq EXIF::Format::Short
    end

    it "doesn't promote tags allowing only SHORT" do
      data = EXIF::Data.new
      data[:orientation] = 1
      expect_raises(EXIF::ValueError) { data[:orientation] = 70_000 }
      data[:orientation].format.should eq EXIF::Format::Short
    end

    it "raises on mismatched values" do
      data = EXIF::Data.new
      data[:orientation] = 1
      expect_raises(EXIF::ValueError) { data[:orientation].value = "top" }
      expect_raises(EXIF::ValueError) { data[:orientation].value = 70_000 }
      expect_raises(EXIF::ValueError) { data[:orientation].value = [] of Int32 }
    end
  end

  it "hashes consistently with equality" do
    data = canon_data
    data[:make].hash.should eq data[:make].hash
    Set{data[:make], data[:make]}.size.should eq 1
    data[:make].should_not eq data[:model]
  end

  describe "#delete" do
    it "keeps detached entries formattable" do
      data = canon_data
      data.delete(:model).to_s.should eq "Canon PowerShot S70"
      data.delete(:orientation).to_s.should eq "6"
      data.delete(:f_number).to_s.should eq "28/10"
      data.delete(:maker_note).to_s.should eq "904 bytes undefined data"

      data[:bits_per_sample] = [8, 8, 8]
      data.delete(:bits_per_sample).to_s.should eq "8, 8, 8"
    end

    it "detaches the entry" do
      data = canon_data
      entry = data[:make].delete
      entry.ifd?.should be_nil
      entry.value.should eq "Canon"
      data.has_key?(:make).should be_false
    end

    it "keeps the identity of detached GPS entries" do
      data = EXIF::Data.new
      data.gps = EXIF::GPS.new(52.0, 21.0)

      entry = data[:gps_latitude]
      copy = entry.dup
      entry.delete

      {entry, copy}.each do |detached|
        detached.ifd?.should be_nil
        detached.tag.should eq EXIF::GPSTag::GPSLatitude
        detached.name.should eq "GPSLatitude"
        detached.title.should eq EXIF::GPSTag::GPSLatitude.title
      end
    end
  end
end
