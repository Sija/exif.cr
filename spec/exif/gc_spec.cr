require "../spec_helper"

# Wrappers only pass their raw pointers to libexif, so a temporary wrapper might be
# garbage collected while libexif still uses its data (see `EXIF::Data#retain`).
# libexif's log callback allocates, which can trigger collections in the middle
# of libexif calls. These only reproduce with optimizations (`--release`) enabled.
describe "EXIF garbage collection" do
  it "keeps temporary wrappers' data alive during libexif calls" do
    bytes = fixture("canon.jpg")
    backend = Log::IOBackend.new(io: IO::Memory.new, dispatcher: :sync)

    Log.setup("exif.*", :debug, backend)
    1_000.times do
      EXIF::Data.new(bytes)
      EXIF::Data.new(bytes).to_slice
      EXIF::Data.new(bytes)[:maker_note].value
      EXIF::Data.new(bytes)[:model].to_s
      EXIF::Data.new(bytes).maker_note?.try(&.to_a)
      EXIF::Data.new(bytes).ifd(:exif).fix
      EXIF::Data.new(bytes).thumbnail?
      backend.io.as(IO::Memory).clear
    end
  ensure
    Log.setup_from_env
  end
end
