require "../spec_helper"

describe EXIF::Data do
  describe "#dup" do
    it "returns an independent copy" do
      data = canon_data
      data.artist = "Jane Doe"
      copy = data.dup

      copy.to_h.should eq data.to_h
      copy.options.should eq data.options
      copy.maker_note?.try(&.size).should eq data.maker_note?.try(&.size)

      copy.model = "Something Else"
      data.model.should eq "Canon PowerShot S70"
    end

    it "copies the thumbnail" do
      data = canon_data
      copy = data.dup
      copy.thumbnail?.should eq data.thumbnail?
      copy.to_slice.should eq data.to_slice

      # Beyond the 64 KB libexif loads
      data.thumbnail = Bytes.new(70_000, &.to_u8!)
      copy = data.dup
      copy.thumbnail?.should eq data.thumbnail?
      copy.warnings.should be_empty
      data.thumbnail?.try(&.size).should eq 70_000
    end

    it "refuses to copy entries beyond the 64 KB libexif loads" do
      data = EXIF::Data.new
      data.artist = "A"
      data.image_description = "x" * 70_000
      expect_raises(EXIF::Error, /too large to copy/) { data.dup }

      data.image_description = "x" * 60_000
      data.dup.image_description.try(&.size).should eq 60_000
    end

    it "copies warnings" do
      data = EXIF::Data.new(canon_data.to_slice[0, 500])
      data.dup.warnings.should eq data.warnings
    end
  end
end

describe "wrapper copies" do
  it "don't release shared libexif data twice" do
    20.times do
      data = canon_data
      data.dup
      data[:model].dup.value.should eq "Canon PowerShot S70"
      data.ifd(:zero).dup.size.should eq 8
      data.maker_note?.try(&.dup).try(&.size).should eq 96
      GC.collect
    end
    5.times { GC.collect }
  end
end
