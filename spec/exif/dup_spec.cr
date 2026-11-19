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
