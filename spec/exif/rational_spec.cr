require "../spec_helper"

describe EXIF::Rational do
  it "converts to float" do
    EXIF::URational.new(1, 250).to_f.should eq 0.004
    EXIF::SRational.new(-1, 3).to_f.should be_close(-0.333, 0.001)
    EXIF::URational.new(1, 0).to_f.nan?.should be_true
  end

  it "approximates floats" do
    EXIF::URational.new(2.8).should eq EXIF::URational.new(14, 5)
    EXIF::URational.new(110.5).should eq EXIF::URational.new(221, 2)
    EXIF::SRational.new(-0.25).should eq EXIF::SRational.new(-1, 4)
  end

  it "compares by value" do
    EXIF::URational.new(28, 10).should eq EXIF::URational.new(14, 5)
    EXIF::URational.new(28, 10).should eq 2.8
    (EXIF::URational.new(1, 2) < EXIF::URational.new(2, 3)).should be_true
  end

  it "keeps the original components" do
    rational = EXIF::URational.new(28, 10)
    rational.numerator.should eq 28
    rational.denominator.should eq 10
    rational.reduce.should eq EXIF::URational.new(14, 5)
    rational.to_s.should eq "28/10"
  end

  it "raises on overflow" do
    expect_raises(OverflowError) { EXIF::URational.new(-1, 2) }
  end
end
