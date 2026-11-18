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

    # Approximates the given floating-point *value* with a rational number.
    def self.new(value : Float) : self
      raise ValueError.new("Cannot represent #{value} as a rational") unless value.finite?

      denominator = 1_i64
      until (value * denominator).round == value * denominator || denominator >= 1_000_000
        denominator *= 10
      end
      numerator = (value * denominator).round.to_i64
      gcd = numerator.gcd(denominator)
      gcd = 1_i64 if gcd.zero?

      new(numerator // gcd, denominator // gcd)
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
      numerator.to_i64 // denominator.to_i64
    end

    # Returns the reduced form of this rational.
    def reduce : self
      gcd = numerator.gcd(denominator)
      return self if gcd.zero? || gcd == 1
      self.class.new(numerator // gcd, denominator // gcd)
    end

    def <=>(other : Rational) : Int32?
      to_f <=> other.to_f
    end

    def ==(other : Rational) : Bool
      numerator.to_i64 * other.denominator.to_i64 == other.numerator.to_i64 * denominator.to_i64 &&
        undefined? == other.undefined?
    end

    def ==(other : Number) : Bool
      to_f == other
    end

    def hash(hasher)
      reduced = reduce
      hasher = reduced.numerator.hash(hasher)
      reduced.denominator.hash(hasher)
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
