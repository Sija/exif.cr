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

    it "loads raw EXIF blocks from IO" do
      EXIF::Data.new(IO::Memory.new(canon_data.to_slice)).model.should eq "Canon PowerShot S70"
    end

    it "loads raw TIFF structures (EXIF blocks without the header)" do
      {EXIF::ByteOrder::Intel, EXIF::ByteOrder::Motorola}.each do |byte_order|
        data = canon_data
        data.byte_order = byte_order
        tiff = data.to_slice[EXIF::JPEG::EXIF_HEADER.size..]

        {EXIF::Data.new(tiff), EXIF::Data.new(IO::Memory.new(tiff))}.each do |loaded|
          loaded.byte_order.should eq byte_order
          loaded.model.should eq "Canon PowerShot S70"
          loaded.to_h.should eq data.to_h
        end
      end
    end

    it "raises NoDataError for short or unknown input" do
      [Bytes.empty, Bytes[0xFF], "II*".to_slice, "Exif".to_slice, "nothing here".to_slice].each do |bytes|
        expect_raises(EXIF::NoDataError) { EXIF::Data.new(bytes) }
        expect_raises(EXIF::NoDataError) { EXIF::Data.new(IO::Memory.new(bytes)) }
      end
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

    it "skips empty or corrupt EXIF segments preceding a valid one" do
      segment = ->(payload : Bytes) do
        Bytes[0xFF, 0xE1, (payload.size + 2) >> 8, (payload.size + 2) & 0xFF] + payload
      end
      image = EXIF::JPEG.strip(fixture("canon.jpg"))[2..]
      valid = segment.call(canon_data.to_slice)

      [
        "Exif\0\0".to_slice,
        "Exif\0\0".to_slice + Bytes.new(20),
        # Invalid magic number, IFD 0 offset beyond the data (silently ignored by libexif)
        "Exif\0\0MM\0+\0\0\0\x08".to_slice + Bytes.new(20),
        "Exif\0\0II*\0\xFF\0\0\0".to_slice + Bytes.new(20),
      ].each do |bogus|
        jpeg = Bytes[0xFF, 0xD8] + segment.call(bogus) + valid + image
        EXIF::Data.new(jpeg).model.should eq "Canon PowerShot S70"

        # The first error is reported if there's no valid one
        jpeg = Bytes[0xFF, 0xD8] + segment.call(bogus) + image
        expect_raises(EXIF::NoDataError, /No valid EXIF data found/) { EXIF::Data.new(jpeg) }
      end
    end

    it "prefers intact EXIF segments over empty or partially loaded ones" do
      segment = ->(payload : Bytes) do
        Bytes[0xFF, 0xE1, (payload.size + 2) >> 8, (payload.size + 2) & 0xFF] + payload
      end
      image = EXIF::JPEG.strip(fixture("canon.jpg"))[2..]
      intact = EXIF::Data.new.tap(&.artist=("Jane Doe")).to_slice
      empty = EXIF::Data.new(options: :none).to_slice
      partial = canon_data.to_slice[0, 500] # yields warnings

      {EXIF::Options::None, EXIF::Options::FollowSpecification}.each do |options|
        [empty, partial].each do |first|
          jpeg = Bytes[0xFF, 0xD8] + segment.call(first) + segment.call(intact) + image
          data = EXIF::Data.new(jpeg, options: options)
          data.artist.should eq "Jane Doe"
          data.options.should eq options
        end

        # Partially loaded rather than empty data, if nothing loads intact
        jpeg = Bytes[0xFF, 0xD8] + segment.call(empty) + segment.call(partial) + image
        data = EXIF::Data.new(jpeg, options: options)
        data.make.should eq "Canon"
        data.warnings.should_not be_empty

        # Empty data is fixed as requested
        jpeg = Bytes[0xFF, 0xD8] + segment.call(empty) + image
        EXIF::Data.new(jpeg, options: options).empty?.should eq options.none?
      end
    end

    it "loads thumbnails of EXIF segments with no intact entries" do
      thumbnail = EXIF::JPEG.strip(fixture("canon.jpg"))
      data = EXIF::Data.new(options: :none)
      data[:exposure_time] = EXIF::URational.new(1, 250) # pointed to by the only IFD 0 entry
      data.thumbnail = thumbnail
      exif = data.to_slice

      # Points the EXIF IFD past the end of the data
      tiff = exif + EXIF::JPEG::EXIF_HEADER.size
      format = tiff[0, 2] == "II".to_slice ? IO::ByteFormat::LittleEndian : IO::ByteFormat::BigEndian
      ifd0 = format.decode(UInt32, tiff[4, 4])
      format.encode(0xFFFF_u32, tiff[ifd0 + 2 + 8, 4])

      jpeg = Bytes[0xFF, 0xD8, 0xFF, 0xE1, (exif.size + 2) >> 8, (exif.size + 2) & 0xFF] + exif + thumbnail[2..]
      {EXIF::Options::None, EXIF::Options.default}.each do |options|
        loaded = EXIF::Data.new(jpeg, options: options)
        loaded.thumbnail?.should eq thumbnail
        loaded.has_key?(:exposure_time).should be_false
        loaded.warnings.should_not be_empty
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

    it "refuses to save entries with more components than libexif saves" do
      data = EXIF::Data.new
      data.image_description = "x" * 70_000
      expect_raises(EXIF::Error, /ImageDescription too large \(70001 > 65536 components\)/) { data.to_slice }
      expect_raises(EXIF::Error, /too large/) { data.dup }
      expect_raises(EXIF::Error, /too large/) { data.embed(fixture("plain.jpg")) }

      data.image_description = "x" * 65_535
      data.to_slice.size.should be > 65_536
    end

    it "raises NoDataError for invalid TIFF headers" do
      empty = EXIF::Data.new(options: :none).to_slice
      # IFD 0 entry count at the very end
      EXIF::Data.new(empty[0, 16], options: :none).empty?.should be_true

      {
        "Exif\0\0MM\0+\0\0\0\x08\0\0".to_slice,   # magic number
        "Exif\0\0MM\0*\0\0\0\x09\0\0".to_slice,   # IFD 0 entry count beyond the data
        "Exif\0\0II*\0\xFF\xFF\xFF\xFF".to_slice, # IFD 0 offset beyond the data
      }.each do |bytes|
        expect_raises(EXIF::NoDataError, /invalid TIFF header/) { EXIF::Data.new(bytes) }
      end
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

    it "keeps the order of the problems, scaling to many of them" do
      data = EXIF::Data.new
      messages = Array.new(20_000) { |i| "Problem #{i}" }
      2.times { messages.each { |message| data.add_warning(message) } }
      data.warnings.should eq messages
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

    it "leaves thumbnail (IFD1) entries alone" do
      data = canon_data
      data.ifd(:zero).delete(:x_resolution)
      thumbnail_resolution = data.ifd(:one)[:x_resolution].value

      data[:x_resolution]?.should be_nil
      data.has_key?(:x_resolution).should be_false
      expect_raises(KeyError) { data[:x_resolution] }
      data[:compression]?.should be_nil # IFD1 only
      data.ifd(:one).has_key?(:compression).should be_true

      data[:x_resolution] = 300
      data.ifd(:zero)[:x_resolution].value.should eq 300
      data.ifd(:one)[:x_resolution].value.should eq thumbnail_resolution

      data.delete(:x_resolution).try(&.value).should eq 300
      data.delete(:x_resolution).should be_nil
      data.ifd(:one)[:x_resolution].value.should eq thumbnail_resolution
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

    it "follows dangling and chained symbolic links" do
      dir = File.tempname("exif-spec")
      Dir.mkdir(dir)
      begin
        target, link, chain = {"target.jpg", "link.jpg", "chain.jpg"}.map { |name| File.join(dir, name) }
        File.symlink("target.jpg", link) # relative, dangling
        File.symlink(link, chain)

        canon_data.save(chain, source: fixture_path("canon.jpg"))
        File.symlink?(link).should be_true
        File.symlink?(chain).should be_true
        EXIF::Data.open(target).model.should eq "Canon PowerShot S70"

        File.delete(link)
        File.symlink("chain.jpg", link) # loop
        expect_raises(File::Error, /symbolic links/) { canon_data.save(chain, source: fixture_path("canon.jpg")) }
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "reads and replaces the same file when following symbolic links" do
      dir = File.tempname("exif-spec")
      Dir.mkdir(dir)
      begin
        a, b, link = {"a.jpg", "b.jpg", "link.jpg"}.map { |name| File.join(dir, name) }
        File.copy(fixture_path("canon.jpg"), a)
        File.copy(fixture_path("plain.jpg"), b)
        File.symlink(a, link)

        EXIF::JPEG.update(link) do |jpeg|
          # Retargeted between reading and replacing the file
          File.delete(link)
          File.symlink(b, link)
          EXIF::JPEG.strip(jpeg)
        end
        EXIF::Data.open?(a).should be_nil
        File.read(b).should eq File.read(fixture_path("plain.jpg"))
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "replaces files with long names" do
      dir = File.tempname("exif-spec")
      Dir.mkdir(dir)
      begin
        path = File.join(dir, "#{"a" * 250}.jpg")
        File.copy(fixture_path("plain.jpg"), path)
        canon_data.save(path)

        EXIF::Data.open(path).model.should eq "Canon PowerShot S70"
        Dir.children(dir).should eq [File.basename(path)]
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "creates new files with the default permissions" do
      dir = File.tempname("exif-spec")
      Dir.mkdir(dir)
      begin
        path, reference = File.join(dir, "new.jpg"), File.join(dir, "reference")
        File.write(reference, "") # with the default permissions (minus the umask)
        canon_data.save(path, source: fixture_path("canon.jpg"))

        File.info(path).permissions.should eq File.info(reference).permissions
        Dir.children(dir).sort.should eq ["new.jpg", "reference"]
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "keeps the file group" do
      path = File.tempname("exif-spec", ".jpg")
      File.copy(fixture_path("canon.jpg"), path)
      begin
        # Any group of the current user, other than the one new files get
        default_group = File.info(path).group_id
        group = `id -G`.split.find { |id| id != default_group }
        pending!("no secondary group to test with") unless group

        File.chown(path, gid: group.to_i)
        File.chmod(path, 0o640)
        EXIF::Data.open(path).tap(&.artist=("Jane Doe")).save(path)

        info = File.info(path)
        info.group_id.should eq group
        info.permissions.value.should eq 0o640
        EXIF::Data.open(path).artist.should eq "Jane Doe"
      ensure
        File.delete?(path)
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
