module EXIF
  # EXIF rational number, stored as a *numerator* / *denominator* pair.
  #
  # Unlike `BigRational` it keeps the original (non-reduced) components,
  # so they're preserved when writing the value back.
  struct Rational(T)
    include Comparable(Rational)

    getter numerator : T
    getter denominator : T

    def initialize(numerator : Int, denominator : Int = 1)
      @numerator = T.new(numerator)
      @denominator = T.new(denominator)
    end

    # Returns the closest rational approximation of the given floating-point
    # *value* whose components fit within `T`, using continued fractions.
    #
    # ```
    # EXIF::URational.new(2.8)     # => EXIF::URational(14/5)
    # EXIF::URational.new(1.0 / 3) # => EXIF::URational(1/3)
    # EXIF::SRational.new(-0.0001) # => EXIF::SRational(-1/10000)
    # ```
    #
    # Raises `ValueError` for non-finite values and `OverflowError`
    # for values out of `T`'s range.
    def self.new(value : Float) : self
      raise ValueError.new("Cannot represent #{value} as a rational") unless value.finite?

      target = value.abs.to_f64
      max = T::MAX.to_i64
      raise OverflowError.new if target > max

      # Convergents h/k of the continued fraction expansion
      h0, h1 = 0_i64, 1_i64
      k0, k1 = 1_i64, 0_i64

      x = target
      loop do
        a = x.floor
        break if a * h1 + h0 > max || a * k1 + k0 > max

        a = a.to_i64
        h0, h1 = h1, a * h1 + h0
        k0, k1 = k1, a * k1 + k0

        fraction = x - a
        break if fraction.zero? || h1 / k1 == target
        x = 1.0 / fraction
      end

      new(value.negative? ? -h1 : h1, k1)
    end

    protected def self.from(value : LibEXIF::EXIFRational | LibEXIF::EXIFSRational) : self
      new(value.numerator, value.denominator)
    end

    protected def to_lib
      {% if T == UInt32 %}
        LibEXIF::EXIFRational.new(numerator: numerator, denominator: denominator)
      {% else %}
        LibEXIF::EXIFSRational.new(numerator: numerator, denominator: denominator)
      {% end %}
    end

    # Returns `true` if the denominator is zero.
    def undefined? : Bool
      denominator.zero?
    end

    # Returns the value as a `Float64` (`NaN` when `undefined?`).
    def to_f : Float64
      return Float64::NAN if undefined?
      numerator.to_f / denominator
    end

    # :ditto:
    def to_f64 : Float64
      to_f
    end

    # Returns the value as an integer, truncating any fractional part.
    def to_i : Int64
      raise DivisionByZeroError.new if undefined?
      numerator.to_i64.tdiv(denominator.to_i64)
    end

    # Returns the reduced form of this rational, with a positive denominator.
    def reduce : self
      n, d = normalized
      n == numerator && d == denominator ? self : self.class.new(n, d)
    end

    # Returns the components in lowest terms, with a positive denominator.
    # Undefined rationals (with a zero denominator) are returned as is.
    protected def normalized : {Int64, Int64}
      n, d = numerator.to_i64, denominator.to_i64
      return {n, d} if d.zero?

      gcd = n.gcd(d)
      n, d = n // gcd, d // gcd
      d.negative? ? {-n, -d} : {n, d}
    end

    def <=>(other : Rational) : Int32?
      to_f <=> other.to_f
    end

    # Returns `true` if both rationals represent the same value.
    #
    # Undefined rationals are only equal to ones with identical components.
    def ==(other : Rational) : Bool
      normalized == other.normalized
    end

    def ==(other : Number) : Bool
      to_f == other
    end

    def hash(hasher)
      normalized.hash(hasher)
    end

    def to_s(io : IO) : Nil
      io << numerator << '/' << denominator
    end

    def inspect(io : IO) : Nil
      io << {% if T == UInt32 %}"EXIF::URational("{% else %}"EXIF::SRational("{% end %}
      to_s(io)
      io << ')'
    end
  end

  # EXIF unsigned rational (`Format::Rational`).
  alias URational = Rational(UInt32)

  # EXIF signed rational (`Format::SRational`).
  alias SRational = Rational(Int32)
end
