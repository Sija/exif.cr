require "file_utils"
require "../spec_helper"

describe EXIF::Data do
  describe ".open" do
    it "loads EXIF data from a JPEG file" do
      data = canon_data
      data.byte_order.should eq EXIF::ByteOrder::Intel
      data.ifd(:zero).size.should eq 8
      data.ifd(:exif).size.should eq 30
      data.ifd(:gps).empty?.should be_true
    end

    it "raises NoDataError for files without EXIF data" do
      expect_raises(EXIF::NoDataError) { EXIF::Data.open(fixture_path("plain.jpg")) }
    end
  end

  describe ".open?" do
    it "returns nil for files without EXIF data" do
      EXIF::Data.open?(fixture_path("plain.jpg")).should be_nil
      EXIF::Data.open?(fixture_path("canon.jpg")).should be_a(EXIF::Data)
    end
  end

  describe ".new" do
    it "creates empty data" do
      data = EXIF::Data.new
      data.empty?.should be_true
      data.size.should eq 0
    end

    it "loads JPEG bytes" do
      EXIF::Data.new(fixture("canon.jpg")).model.should eq "Canon PowerShot S70"
    end

    it "loads raw EXIF bytes" do
      EXIF::Data.new(canon_data.to_slice).model.should eq "Canon PowerShot S70"
    end

    it "loads from IO" do
      File.open(fixture_path("canon.jpg")) do |file|
        EXIF::Data.new(file).make.should eq "Canon"
      end
    end

    it "finds EXIF data following any other JPEG segments" do
      segment = ->(marker : Int32, payload : Bytes) do
        IO::Memory.new.tap do |io|
          io.write_byte 0xFF_u8
          io.write_byte marker.to_u8
          io.write_bytes (payload.size + 2).to_u16, IO::ByteFormat::BigEndian
          io.write payload
        end.to_slice
      end
      exif = segment.call(0xE1, canon_data.to_slice)
      image = EXIF::JPEG.strip(fixture("canon.jpg"))[2..]

      # APPn, XMP (APP1), COM, DQT, DHT and DRI segments
      ((0xE0..0xEF).to_a + [0xFE, 0xDB, 0xC4, 0xDD]).each do |marker|
        payload = marker == 0xE1 ? "http://ns.adobe.com/xap/1.0/\0".to_slice : Bytes.new(4)
        jpeg = Bytes[0xFF, 0xD8] + segment.call(marker, payload) + exif + image

        EXIF::Data.new(jpeg).model.should eq "Canon PowerShot S70"
        EXIF::Data.new(IO::Memory.new(jpeg)).model.should eq "Canon PowerShot S70"
      end
    end

    it "loads truncated EXIF segments" do
      jpeg = fixture("canon.jpg")
      data = EXIF::Data.new(jpeg[0, 600])
      data.warnings.should_not be_empty
      data.make.should eq "Canon"
    end

    it "raises NoDataError for malformed JPEG data" do
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(Bytes[0xFF, 0xD8]) }
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(Bytes[0xFF, 0xD8, 0x00]) }
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(Bytes[0xFF, 0xD8, 0xFF, 0xE1, 0x00]) }
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(Bytes[0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x01]) }
    end

    it "exposes options" do
      EXIF::Data.new.options.should eq EXIF::Options.default
      EXIF::Data.new(options: :none).options.should eq EXIF::Options::None
      EXIF::Data.new(fixture("canon.jpg"), options: :ignore_unknown_tags).options.should eq EXIF::Options::IgnoreUnknownTags

      data = EXIF::Data.new
      data.options = :dont_change_maker_note
      data.options.should eq EXIF::Options::DontChangeMakerNote
    end

    it "respects options" do
      raw = EXIF::Data.new.tap { |data| data[:make] = "Foo" }.to_slice

      EXIF::Data.new(raw, options: :none).size.should eq 1
      EXIF::Data.new(raw, options: :follow_specification).size.should be > 1
    end

    it "raises NoDataError for corrupt EXIF data" do
      expect_raises(EXIF::NoDataError, /Unknown encoding/) do
        EXIF::Data.new("Exif\0\0garbage-garbage-garbage".to_slice)
      end
    end

    it "raises NoDataError for a bare EXIF header" do
      expect_raises(EXIF::NoDataError, /too short/) { EXIF::Data.new("Exif\0\0".to_slice) }
      expect_raises(EXIF::NoDataError, /too short/) { EXIF::Data.new("Exif\0\0MM\0*".to_slice) }
    end

    it "loads valid empty EXIF data" do
      EXIF::Data.new(EXIF::Data.new(options: :none).to_slice, options: :none).empty?.should be_true
    end

    it "raises NoDataError for data without EXIF" do
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(fixture("plain.jpg")) }
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(Bytes[1, 2, 3]) }
    end
  end

  describe "#warnings" do
    it "is empty for valid data" do
      canon_data.warnings.should be_empty
      EXIF::Data.new.warnings.should be_empty
    end

    it "reports corrupt data" do
      data = EXIF::Data.new(canon_data.to_slice[0, 500])
      data.size.should be > 0
      # NOTE: also verifies formatting of `printf`-style messages (`va_list` handling)
      data.warnings.should eq ["Tag data past end of buffer (188 > 494)", "Bogus offset of IFD1."]
    end

    it "reports each problem once" do
      data = EXIF::Data.new
      data[:resolution_unit] = [1, 2, 3]
      10.times { data[:resolution_unit].to_s }
      data.warnings.should eq ["The tag 'ResolutionUnit' contains an invalid number of components (3, expected 1)."]
    end

    it "returns a copy" do
      data = EXIF::Data.new(canon_data.to_slice[0, 300])
      data.warnings.clear
      data.warnings.should_not be_empty
    end
  end

  describe "#[]" do
    it "looks up entries across IFDs" do
      data = canon_data
      data[:make].ifd.should eq EXIF::IFD::Zero
      data[:exposure_time].ifd.should eq EXIF::IFD::EXIF
      data[:interoperability_index].ifd.should eq EXIF::IFD::Interoperability
    end

    it "raises KeyError for missing entries" do
      expect_raises(KeyError) { canon_data[:artist] }
      expect_raises(KeyError) { canon_data[:gps_latitude] }
    end
  end

  describe "#[]?" do
    it "returns nil for missing entries" do
      canon_data[:artist]?.should be_nil
      canon_data[:gps_latitude]?.should be_nil
    end
  end

  describe "#has_key?" do
    it "checks for entries" do
      canon_data.has_key?(:model).should be_true
      canon_data.has_key?(:artist).should be_false
    end
  end

  describe "#[]=" do
    it "updates existing entries" do
      data = canon_data
      data[:model] = "Something Else"
      data[:model].value.should eq "Something Else"
      data[:model].components.should eq 15
    end

    it "creates entries in the proper IFD" do
      data = EXIF::Data.new
      data[:artist] = "Jane"
      data[:exposure_time] = EXIF::URational.new(1, 250)
      data[:gps_altitude] = EXIF::URational.new(100)

      data[:artist].ifd.should eq EXIF::IFD::Zero
      data[:exposure_time].ifd.should eq EXIF::IFD::EXIF
      data[:gps_altitude].ifd.should eq EXIF::IFD::GPS
      data[:gps_altitude].tag.should eq EXIF::GPSTag::GPSAltitude
    end

    it "removes entries when set to nil" do
      data = canon_data
      data[:model] = nil
      data.has_key?(:model).should be_false

      data.ifd(:exif)[:f_number] = nil
      data.has_key?(:f_number).should be_false

      data[:artist] = nil # missing
      data.has_key?(:artist).should be_false
    end

    it "doesn't leave half-created entries on errors" do
      data = EXIF::Data.new
      expect_raises(EXIF::ValueError) { data[:orientation] = "nope" }
      data.has_key?(:orientation).should be_false
    end
  end

  describe "#delete" do
    it "removes entries" do
      data = canon_data
      entry = data.delete(:model).should_not be_nil
      entry.ifd?.should be_nil
      data[:model]?.should be_nil
      data.delete(:model).should be_nil
    end
  end

  describe "#each" do
    it "yields all entries" do
      data = canon_data
      data.to_a.size.should eq data.size
      data.map(&.name).should contain "FNumber"
    end
  end

  describe "#to_slice" do
    it "round-trips" do
      data = canon_data
      data[:artist] = "Jane Doe"

      loaded = EXIF::Data.new(data.to_slice)
      loaded.artist.should eq "Jane Doe"
      loaded.to_h.should eq data.to_h
    end
  end

  describe "#byte_order=" do
    it "converts entries" do
      data = canon_data
      data.byte_order = :motorola
      data.byte_order.should eq EXIF::ByteOrder::Motorola
      data[:pixel_x_dimension].value.should eq 640
      EXIF::Data.new(data.to_slice).width.should eq 640
    end
  end

  describe "#thumbnail" do
    it "gets and sets the thumbnail" do
      data = EXIF::Data.new
      data.thumbnail?.should be_nil

      data.thumbnail = fixture("plain.jpg")
      data.thumbnail?.should eq fixture("plain.jpg")

      EXIF::Data.new(data.to_slice).thumbnail?.should eq fixture("plain.jpg")

      data.thumbnail = nil
      data.thumbnail?.should be_nil
    end
  end

  describe "#save" do
    it "embeds the EXIF data into a JPEG file" do
      path = File.tempname("exif", ".jpg")
      begin
        data = canon_data
        data.artist = "Jane Doe"
        data.save(path, source: fixture_path("plain.jpg"))

        EXIF::Data.open(path).artist.should eq "Jane Doe"

        # overwrites existing EXIF data in place
        data.artist = "John Doe"
        data.save(path)
        EXIF::Data.open(path).artist.should eq "John Doe"
      ensure
        File.delete?(path)
      end
    end

    it "keeps the file permissions and leaves no temporary files" do
      dir = File.tempname("exif-spec")
      Dir.mkdir(dir)
      begin
        path = File.join(dir, "photo.jpg")
        File.copy(fixture_path("canon.jpg"), path)
        File.chmod(path, 0o600)

        data = EXIF::Data.open(path)
        data.artist = "Jane Doe"
        data.save(path)

        EXIF::Data.open(path).artist.should eq "Jane Doe"
        File.info(path).permissions.value.should eq 0o600
        Dir.children(dir).should eq ["photo.jpg"]
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "follows symbolic links" do
      dir = File.tempname("exif-spec")
      Dir.mkdir(dir)
      begin
        path = File.join(dir, "photo.jpg")
        link = File.join(dir, "link.jpg")
        File.copy(fixture_path("canon.jpg"), path)
        File.symlink(path, link)

        data = EXIF::Data.open(link)
        data.artist = "Jane Doe"
        data.save(link)

        File.symlink?(link).should be_true
        EXIF::Data.open(path).artist.should eq "Jane Doe"
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "leaves the file intact on errors" do
      path = File.tempname("exif-spec", ".jpg")
      File.write(path, "not a JPEG")
      begin
        expect_raises(EXIF::JPEGError) { EXIF::Data.new.save(path) }
        File.read(path).should eq "not a JPEG"
      ensure
        File.delete?(path)
      end
    end
  end

  describe "#retain" do
    it "keeps the libexif data alive if the wrapper is finalized meanwhile" do
      data = canon_data
      model = data.retain do |ptr|
        # Simulates the wrapper being garbage collected (i.e. its finalizer dropping
        # its reference) in the middle of a libexif call
        LibEXIF.exif_data_unref(ptr)

        entry = LibEXIF.exif_content_get_entry(ptr.value.ifd[0], EXIF::Tag::Model)
        value = String.new(entry.value.data)

        # Restores the reference dropped above, for the actual finalizer
        LibEXIF.exif_data_ref(ptr)
        value
      end
      model.should eq "Canon PowerShot S70"
      data.model.should eq "Canon PowerShot S70"
    end
  end

  describe "#to_h" do
    it "returns formatted values grouped by IFD" do
      hash = canon_data.to_h
      hash.keys.should eq ["0", "1", "EXIF", "Interoperability"]
      hash["0"]["Make"].should eq "Canon"
      hash["EXIF"]["FNumber"].should eq "f/2.8"
    end
  end
end
