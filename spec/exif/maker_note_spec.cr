require "../spec_helper"

describe EXIF::MakerNote do
  it "parses vendor-specific entries" do
    maker_note = canon_data.maker_note?.should_not be_nil
    maker_note.size.should be > 0
    maker_note["Macro Mode"].value.should eq "Normal"
    maker_note["Quality"].value.should eq "Superfine"
    maker_note.to_h["Self-timer"].should eq "Off"
  end

  it "looks up entries by name" do
    maker_note = canon_data.maker_note?.should_not be_nil
    maker_note["Quality"].should eq maker_note.find(&.name.== "Quality")
    maker_note["Bogus"]?.should be_nil
    expect_raises(KeyError) { maker_note["Bogus"] }
  end

  it "is nil when missing" do
    EXIF::Data.new.maker_note?.should be_nil
  end

  it "is nil after removing the maker note entry" do
    data = canon_data
    data.delete(:maker_note)
    data.maker_note?.should be_nil
  end
end
