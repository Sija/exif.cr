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

    it "respects options" do
      raw = EXIF::Data.new.tap { |data| data[:make] = "Foo" }.to_slice

      EXIF::Data.new(raw, options: :none).size.should eq 1
      EXIF::Data.new(raw, options: :follow_specification).size.should be > 1
    end

    it "raises NoDataError for data without EXIF" do
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(fixture("plain.jpg")) }
      expect_raises(EXIF::NoDataError) { EXIF::Data.new(Bytes[1, 2, 3]) }
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
        # Simulates the wrapper being garbage collected in the middle of a libexif call
        data.finalize

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
