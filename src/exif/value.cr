module EXIF
  # A scalar value decoded from an `Entry`.
  alias Scalar = String | Int64 | Float64 | URational | SRational

  # A value decoded from an `Entry`.
  #
  # - `Format::Ascii` is decoded as `String`
  # - `Format::Undefined` is decoded as `Bytes`
  # - integer formats are decoded as `Int64`
  # - `Format::Float` and `Format::Double` are decoded as `Float64`
  # - `Format::Rational` and `Format::SRational` are decoded as
  #   `URational` and `SRational` respectively
  #
  # Entries with more than one component are decoded as an `Array`.
  alias Value = Scalar | Bytes | Array(Int64) | Array(Float64) | Array(URational) | Array(SRational)
end
