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

  it "doesn't overwrite a new maker note value when saving" do
    raw = Bytes[1, 2, 3, 4]

    data = canon_data
    data[:maker_note] = raw
    data.maker_note?.should be_nil
    loaded = EXIF::Data.new(data.to_slice)
    data[:maker_note].as_bytes.should eq raw
    loaded[:maker_note].as_bytes.should eq raw
    data.options.dont_change_maker_note?.should be_false

    # Re-added after removing it
    data = canon_data
    data.delete(:maker_note)
    data[:maker_note] = raw
    EXIF::Data.new(data.to_slice)[:maker_note].as_bytes.should eq raw
  end

  it "keeps the maker note when saving otherwise" do
    data = canon_data
    data.artist = "Jane Doe"
    loaded = EXIF::Data.new(data.to_slice)
    loaded[:maker_note].as_bytes.should eq data[:maker_note].as_bytes
    loaded.maker_note?.try(&.to_h).should eq data.maker_note?.try(&.to_h)
  end
end
