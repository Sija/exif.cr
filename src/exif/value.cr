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
  # Text tags are decoded as `String` regardless: `Tag::UserComment` (taking its character
  # code into account) and the UTF-16 `Tag::XPTitle`-like tags (stored as `Format::Byte`).
  #
  # Entries with no or more than one component are decoded as an `Array`
  # (numeric formats only; empty `Format::Ascii` and `Format::Undefined` ones
  # are decoded as an empty `String` and `Bytes` respectively).
  alias Value = Scalar | Bytes | Array(Int64) | Array(Float64) | Array(URational) | Array(SRational)
end
