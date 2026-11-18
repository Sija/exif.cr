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

  it "hashes consistently with equality" do
    EXIF::URational.new(28, 10).hash.should eq EXIF::URational.new(14, 5).hash
    EXIF::SRational.new(1, -2).should eq EXIF::SRational.new(-1, 2)
    EXIF::SRational.new(1, -2).hash.should eq EXIF::SRational.new(-1, 2).hash
    Set{EXIF::URational.new(1, 2), EXIF::URational.new(2, 4)}.size.should eq 1
  end

  it "only equals undefined rationals with identical components" do
    EXIF::URational.new(0, 0).should_not eq EXIF::URational.new(1, 0)
    EXIF::URational.new(1, 0).should_not eq EXIF::URational.new(2, 0)
    EXIF::URational.new(1, 0).should eq EXIF::URational.new(1, 0)
  end

  it "truncates when converting to an integer" do
    EXIF::SRational.new(-3, 2).to_i.should eq -1
    EXIF::URational.new(3, 2).to_i.should eq 1
  end

  it "keeps the original components" do
    rational = EXIF::URational.new(28, 10)
    rational.numerator.should eq 28
    rational.denominator.should eq 10
    rational.reduce.should eq EXIF::URational.new(14, 5)
    rational.reduce.numerator.should eq 14
    EXIF::SRational.new(2, -4).reduce.denominator.should eq 2
    rational.to_s.should eq "28/10"
  end

  it "raises on overflow" do
    expect_raises(OverflowError) { EXIF::URational.new(-1, 2) }
  end
end
