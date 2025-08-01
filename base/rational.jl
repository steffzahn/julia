# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    Rational{T<:Integer} <: Real

Rational number type, with numerator and denominator of type `T`.
Rationals are checked for overflow.
"""
struct Rational{T<:Integer} <: Real
    num::T
    den::T

    # Unexported inner constructor of Rational that bypasses all checks
    global unsafe_rational(::Type{T}, num, den) where {T} = new{T}(num, den)
end

unsafe_rational(num::T, den::T) where {T<:Integer} = unsafe_rational(T, num, den)
unsafe_rational(num::Integer, den::Integer) = unsafe_rational(promote(num, den)...)

function checked_den(::Type{T}, num::T, den::T) where T<:Integer
    if signbit(den)
        den = checked_neg(den)
        num = checked_neg(num)
    end
    return unsafe_rational(T, num, den)
end
checked_den(num::T, den::T) where T<:Integer = checked_den(T, num, den)
checked_den(num::Integer, den::Integer) = checked_den(promote(num, den)...)

@noinline __throw_rational_argerror_zero(T) = throw(ArgumentError(LazyString("invalid rational: zero(", T, ")//zero(", T, ")")))
function Rational{T}(num::Integer, den::Integer) where T<:Integer
    iszero(den) && iszero(num) && __throw_rational_argerror_zero(T)
    if T <: Union{Unsigned, Bool}
        # Throw InexactError if the result is negative.
        if !iszero(num) && (signbit(den) ⊻ signbit(num))
            throw(InexactError(:Rational, Rational{T}, num, den))
        end
        unum = uabs(num)
        uden = uabs(den)
        r_unum, r_uden = divgcd(unum, uden)
        return unsafe_rational(T, promote(T(r_unum), T(r_uden))...)
    else
        r_num, r_den = divgcd(num, den)
        return checked_den(T, promote(T(r_num), T(r_den))...)
    end
end

Rational(n::T, d::T) where {T<:Integer} = Rational{T}(n, d)
Rational(n::Integer, d::Integer) = Rational(promote(n, d)...)
Rational(n::Integer) = unsafe_rational(n, one(n))

"""
    divgcd(x::Integer, y::Integer)

Returns `(x÷gcd(x,y), y÷gcd(x,y))`.

See also [`div`](@ref), [`gcd`](@ref).
"""
function divgcd(x::TX, y::TY)::Tuple{TX, TY} where {TX<:Integer, TY<:Integer}
    g = gcd(uabs(x), uabs(y))
    div(x,g), div(y,g)
end

"""
    //(num, den)

Divide two integers or rational numbers, giving a [`Rational`](@ref) result.
More generally, `//` can be used for exact rational division of other numeric types
with integer or rational components, such as complex numbers with integer components.

Note that floating-point ([`AbstractFloat`](@ref)) arguments are not permitted by `//`
(even if the values are rational).
The arguments must be subtypes of [`Integer`](@ref), `Rational`, or composites thereof.

# Examples
```jldoctest
julia> 3 // 5
3//5

julia> (3 // 5) // (2 // 1)
3//10

julia> (1+2im) // (3+4im)
11//25 + 2//25*im

julia> 1.0 // 2
ERROR: MethodError: no method matching //(::Float64, ::Int64)
[...]
```
"""
//(n::Integer,  d::Integer) = Rational(n,d)

function //(x::Rational, y::Integer)
    xn, yn = divgcd(promote(x.num, y)...)
    checked_den(xn, checked_mul(x.den, yn))
end
function //(x::Integer,  y::Rational)
    xn, yn = divgcd(promote(x, y.num)...)
    checked_den(checked_mul(xn, y.den), yn)
end
function //(x::Rational, y::Rational)
    xn,yn = divgcd(promote(x.num, y.num)...)
    xd,yd = divgcd(promote(x.den, y.den)...)
    checked_den(checked_mul(xn, yd), checked_mul(xd, yn))
end

//(x::Complex, y::Real) = complex(real(x)//y, imag(x)//y)
//(x::Number, y::Complex) = x*conj(y)//abs2(y)


//(X::AbstractArray, y::Number) = X .// y

function show(io::IO, x::Rational)
    show(io, numerator(x))

    if isone(denominator(x)) && nonnothing_nonmissing_typeinfo(io) <: Rational
        return
    end

    print(io, "//")
    show(io, denominator(x))
end

function read(s::IO, ::Type{Rational{T}}) where T<:Integer
    r = read(s,T)
    i = read(s,T)
    r//i
end
function write(s::IO, z::Rational)
    write(s,numerator(z),denominator(z))
end
function parse(::Type{Rational{T}}, s::AbstractString) where T<:Integer
    ss = split(s, '/'; limit = 2)
    if isone(length(ss))
        return Rational{T}(parse(T, s))
    end
    @inbounds ns, ds = ss[1], ss[2]
    if startswith(ds, '/')
        ds = chop(ds; head = 1, tail = 0)
    end
    n = parse(T, ns)
    d = parse(T, ds)
    return n//d
end


function Rational{T}(x::Rational) where T<:Integer
    unsafe_rational(T, convert(T, x.num), convert(T, x.den))
end
function Rational{T}(x::Integer) where T<:Integer
    unsafe_rational(T, T(x), T(one(x)))
end

Rational(x::Rational) = x

Bool(x::Rational) = x==0 ? false : x==1 ? true :
    throw(InexactError(:Bool, Bool, x)) # to resolve ambiguity
(::Type{T})(x::Rational) where {T<:Integer} = (isinteger(x) ? convert(T, x.num)::T :
    throw(InexactError(nameof(T), T, x)))

AbstractFloat(x::Rational) = (float(x.num)/float(x.den))::AbstractFloat
function (::Type{T})(x::Rational{S}) where T<:AbstractFloat where S
    P = promote_type(T,S)
    convert(T, convert(P,x.num)/convert(P,x.den))::T
end
 # avoid spurious overflow (#52394).  (Needed for UInt16 or larger;
 # we also include Int16 for consistency of accuracy.)
Float16(x::Rational{<:Union{Int16,Int32,Int64,UInt16,UInt32,UInt64}}) =
    Float16(Float32(x))
Float16(x::Rational{<:Union{Int128,UInt128}}) =
    Float16(Float64(x)) # UInt128 overflows Float32, include Int128 for consistency
Float32(x::Rational{<:Union{Int128,UInt128}}) =
    Float32(Float64(x)) # UInt128 overflows Float32, include Int128 for consistency

function Rational{T}(x::AbstractFloat) where T<:Integer
    r = rationalize(T, x, tol=0)
    x == convert(typeof(x), r) || throw(InexactError(:Rational, Rational{T}, x))
    r
end
Rational(x::Float64) = Rational{Int64}(x)
Rational(x::Float32) = Rational{Int}(x)

big(q::Rational) = unsafe_rational(big(numerator(q)), big(denominator(q)))

big(z::Complex{<:Rational{<:Integer}}) = Complex{Rational{BigInt}}(z)

promote_rule(::Type{Rational{T}}, ::Type{S}) where {T<:Integer,S<:Integer} = Rational{promote_type(T,S)}
promote_rule(::Type{Rational{T}}, ::Type{Rational{S}}) where {T<:Integer,S<:Integer} = Rational{promote_type(T,S)}
promote_rule(::Type{Rational{T}}, ::Type{S}) where {T<:Integer,S<:AbstractFloat} = promote_type(T,S)

widen(::Type{Rational{T}}) where {T} = Rational{widen(T)}

@noinline __throw_negate_unsigned() = throw(OverflowError("cannot negate unsigned number"))

"""
    rationalize([T<:Integer=Int,] x; tol::Real=eps(x))

Approximate floating point number `x` as a [`Rational`](@ref) number with components
of the given integer type. The result will differ from `x` by no more than `tol`.

# Examples
```jldoctest
julia> rationalize(5.6)
28//5

julia> a = rationalize(BigInt, 10.3)
103//10

julia> typeof(numerator(a))
BigInt
```
"""
function rationalize(::Type{T}, x::Union{AbstractFloat, Rational}, tol::Real) where T<:Integer
    if tol < 0
        throw(ArgumentError("negative tolerance $tol"))
    end

    T<:Unsigned && x < 0 && __throw_negate_unsigned()
    isnan(x) && return T(x)//one(T)
    isinf(x) && return unsafe_rational(x < 0 ? -one(T) : one(T), zero(T))

    p,  q  = (x < 0 ? -one(T) : one(T)), zero(T)
    pp, qq = zero(T), one(T)

    x = abs(x)
    a = trunc(x)
    r = x-a
    y = one(x)
    tolx = oftype(x, tol)
    nt, t, tt = tolx, zero(tolx), tolx
    ia = np = nq = zero(T)

    # compute the successive convergents of the continued fraction
    #  np // nq = (p*a + pp) // (q*a + qq)
    while r > nt
        try
            ia = convert(T,a)

            np = checked_add(checked_mul(ia,p),pp)
            nq = checked_add(checked_mul(ia,q),qq)
            p, pp = np, p
            q, qq = nq, q
        catch e
            isa(e,InexactError) || isa(e,OverflowError) || rethrow()
            return p // q
        end

        # naive approach of using
        #   x = 1/r; a = trunc(x); r = x - a
        # is inexact, so we store x as x/y
        x, y = y, r
        a, r = divrem(x,y)

        # maintain
        # x0 = (p + (-1)^i * r) / q
        t, tt = nt, t
        nt = a*t+tt
    end

    # find optimal semiconvergent
    # smallest a such that x-a*y < a*t+tt
    a = cld(x-tt,y+t)
    try
        ia = convert(T,a)
        np = checked_add(checked_mul(ia,p),pp)
        nq = checked_add(checked_mul(ia,q),qq)
        return np // nq
    catch e
        isa(e,InexactError) || isa(e,OverflowError) || rethrow()
        return p // q
    end
end
rationalize(::Type{T}, x::AbstractFloat; tol::Real = eps(x)) where {T<:Integer} = rationalize(T, x, tol)
rationalize(x::Real; kvs...) = rationalize(Int, x; kvs...)
rationalize(::Type{T}, x::Complex; kvs...) where {T<:Integer} = Complex(rationalize(T, x.re; kvs...), rationalize(T, x.im; kvs...))
rationalize(x::Complex; kvs...) = Complex(rationalize(Int, x.re; kvs...), rationalize(Int, x.im; kvs...))
rationalize(::Type{T}, x::Rational; tol::Real = 0) where {T<:Integer} = rationalize(T, x, tol)
rationalize(x::Rational; kvs...) = x
rationalize(x::Integer; kvs...) = Rational(x)
function rationalize(::Type{T}, x::Integer; kvs...) where {T<:Integer}
    if Base.hastypemax(T) # BigInt doesn't
        x < typemin(T) && return unsafe_rational(-one(T), zero(T))
        x > typemax(T) && return unsafe_rational(one(T), zero(T))
    end
    return Rational{T}(x)
end


"""
    numerator(x)

Numerator of the rational representation of `x`.

# Examples
```jldoctest
julia> numerator(2//3)
2

julia> numerator(4)
4
```
"""
numerator(x::Union{Integer,Complex{<:Integer}}) = x
numerator(x::Rational) = x.num
function numerator(z::Complex{<:Rational})
    den = denominator(z)
    reim = (real(z), imag(z))
    result = checked_mul.(numerator.(reim), div.(den, denominator.(reim)))
    complex(result...)
end

"""
    denominator(x)

Denominator of the rational representation of `x`.

# Examples
```jldoctest
julia> denominator(2//3)
3

julia> denominator(4)
1
```
"""
denominator(x::Union{Integer,Complex{<:Integer}}) = one(x)
denominator(x::Rational) = x.den
denominator(z::Complex{<:Rational}) = lcm(denominator(real(z)), denominator(imag(z)))

sign(x::Rational) = oftype(x, sign(x.num))
signbit(x::Rational) = signbit(x.num)

abs(x::Rational) = unsafe_rational(checked_abs(x.num), x.den)

typemin(::Type{Rational{T}}) where {T<:Signed} = unsafe_rational(T, -one(T), zero(T))
typemin(::Type{Rational{T}}) where {T<:Integer} = unsafe_rational(T, zero(T), one(T))
typemax(::Type{Rational{T}}) where {T<:Integer} = unsafe_rational(T, one(T), zero(T))

isinteger(x::Rational) = x.den == 1
ispow2(x::Rational) = ispow2(x.num) & ispow2(x.den)

+(x::Rational) = unsafe_rational(+x.num, x.den)
-(x::Rational) = unsafe_rational(-x.num, x.den)

function -(x::Rational{T}) where T<:BitSigned
    x.num == typemin(T) && __throw_rational_numerator_typemin(T)
    unsafe_rational(-x.num, x.den)
end
@noinline __throw_rational_numerator_typemin(T) = throw(OverflowError(LazyString("rational numerator is typemin(", T, ")")))

function -(x::Rational{T}) where T<:Unsigned
    x.num != zero(T) && __throw_negate_unsigned()
    x
end

function +(x::Rational, y::Rational)
    xp, yp = promote(x, y)::NTuple{2,Rational}
    if isinf(x) && x == y
        return xp
    end
    xd, yd = divgcd(promote(x.den, y.den)...)
    Rational(checked_add(checked_mul(x.num,yd), checked_mul(y.num,xd)), checked_mul(x.den,yd))
end

function -(x::Rational, y::Rational)
    xp, yp = promote(x, y)::NTuple{2,Rational}
    if isinf(x) && x == -y
        return xp
    end
    xd, yd = divgcd(promote(x.den, y.den)...)
    Rational(checked_sub(checked_mul(x.num,yd), checked_mul(y.num,xd)), checked_mul(x.den,yd))
end

for (op,chop) in ((:rem,:rem), (:mod,:mod))
    @eval begin
        function ($op)(x::Rational, y::Rational)
            xd, yd = divgcd(promote(x.den, y.den)...)
            Rational(($chop)(checked_mul(x.num,yd), checked_mul(y.num,xd)), checked_mul(x.den,yd))
        end
    end
end

for (op,chop) in ((:+,:checked_add), (:-,:checked_sub), (:rem,:rem), (:mod,:mod))
    @eval begin
        function ($op)(x::Rational, y::Integer)
            unsafe_rational(($chop)(x.num, checked_mul(x.den, y)), x.den)
        end
    end
end
for (op,chop) in ((:+,:checked_add), (:-,:checked_sub))
    @eval begin
        function ($op)(y::Integer, x::Rational)
            unsafe_rational(($chop)(checked_mul(x.den, y), x.num), x.den)
        end
    end
end
for (op,chop) in ((:rem,:rem), (:mod,:mod))
    @eval begin
        function ($op)(y::Integer, x::Rational)
            Rational(($chop)(checked_mul(x.den, y), x.num), x.den)
        end
    end
end

function *(x::Rational, y::Rational)
    xn, yd = divgcd(promote(x.num, y.den)...)
    xd, yn = divgcd(promote(x.den, y.num)...)
    unsafe_rational(checked_mul(xn, yn), checked_mul(xd, yd))
end
function *(x::Rational, y::Integer)
    xd, yn = divgcd(promote(x.den, y)...)
    unsafe_rational(checked_mul(x.num, yn), xd)
end
function *(y::Integer, x::Rational)
    yn, xd = divgcd(promote(y, x.den)...)
    unsafe_rational(checked_mul(yn, x.num), xd)
end
# make `false` a "strong zero": false*1//0 == 0//1 #57409
# This is here instead of in bool.jl with the AbstractFloat method for bootstrapping
function *(x::Bool, y::T)::promote_type(Bool,T) where T<:Rational
    return ifelse(x, y, copysign(zero(y), y))
end
*(y::Rational, x::Bool) = x * y
/(x::Rational, y::Union{Rational, Integer, Complex{<:Union{Integer,Rational}}}) = x//y
/(x::Union{Integer, Complex{<:Union{Integer,Rational}}}, y::Rational) = x//y
inv(x::Rational{T}) where {T} = checked_den(x.den, x.num)

fma(x::Rational, y::Rational, z::Rational) = x*y+z

==(x::Rational, y::Rational) = (x.den == y.den) & (x.num == y.num)
<( x::Rational, y::Rational) = x.den == y.den ? x.num < y.num :
                               widemul(x.num,y.den) < widemul(x.den,y.num)
<=(x::Rational, y::Rational) = x.den == y.den ? x.num <= y.num :
                               widemul(x.num,y.den) <= widemul(x.den,y.num)


==(x::Rational, y::Integer ) = (x.den == 1) & (x.num == y)
==(x::Integer , y::Rational) = y == x
<( x::Rational, y::Integer ) = x.num < widemul(x.den,y)
<( x::Integer , y::Rational) = widemul(x,y.den) < y.num
<=(x::Rational, y::Integer ) = x.num <= widemul(x.den,y)
<=(x::Integer , y::Rational) = widemul(x,y.den) <= y.num

function ==(x::AbstractFloat, q::Rational)
    if isfinite(x)
        (count_ones(q.den) == 1) & (x*q.den == q.num)
    else
        x == q.num/q.den
    end
end

==(q::Rational, x::AbstractFloat) = x == q

for rel in (:<,:<=,:cmp)
    for (Tx,Ty) in ((Rational,AbstractFloat), (AbstractFloat,Rational))
        @eval function ($rel)(x::$Tx, y::$Ty)
            if isnan(x)
                $(rel === :cmp ? :(return isnan(y) ? 0 : 1) :
                                :(return false))
            end
            if isnan(y)
                $(rel === :cmp ? :(return -1) :
                                :(return false))
            end

            xn, xp, xd = decompose(x)
            yn, yp, yd = decompose(y)

            if xd < 0
                xn = -xn
                xd = -xd
            end
            if yd < 0
                yn = -yn
                yd = -yd
            end

            xc, yc = widemul(xn,yd), widemul(yn,xd)
            xs, ys = sign(xc), sign(yc)

            if xs != ys
                return ($rel)(xs,ys)
            elseif xs == 0
                # both are zero or ±Inf
                return ($rel)(xn,yn)
            end

            xb, yb = ndigits0z(xc,2) + xp, ndigits0z(yc,2) + yp

            if xb == yb
                xc, yc = promote(xc,yc)
                if xp > yp
                    xc = (xc<<(xp-yp))
                else
                    yc = (yc<<(yp-xp))
                end
                return ($rel)(xc,yc)
            else
                return xc > 0 ? ($rel)(xb,yb) : ($rel)(yb,xb)
            end
        end
    end
end

# needed to avoid ambiguity between ==(x::Real, z::Complex) and ==(x::Rational, y::Number)
==(z::Complex , x::Rational) = isreal(z) & (real(z) == x)
==(x::Rational, z::Complex ) = isreal(z) & (real(z) == x)

function div(x::Rational, y::Integer, r::RoundingMode)
    xn,yn = divgcd(x.num,y)
    div(xn, checked_mul(x.den,yn), r)
end
function div(x::Integer, y::Rational, r::RoundingMode)
    xn,yn = divgcd(x,y.num)
    div(checked_mul(xn,y.den), yn, r)
end
function div(x::Rational, y::Rational, r::RoundingMode)
    xn,yn = divgcd(x.num,y.num)
    xd,yd = divgcd(x.den,y.den)
    div(checked_mul(xn,yd), checked_mul(xd,yn), r)
end

# For compatibility - to be removed in 2.0 when the generic fallbacks
# are removed from div.jl
div(x::T, y::T, r::RoundingMode) where {T<:Rational} =
    invoke(div, Tuple{Rational, Rational, RoundingMode}, x, y, r)
for (S, T) in ((Rational, Integer), (Integer, Rational), (Rational, Rational))
    @eval begin
        div(x::$S, y::$T) = div(x, y, RoundToZero)
        fld(x::$S, y::$T) = div(x, y, RoundDown)
        cld(x::$S, y::$T) = div(x, y, RoundUp)
    end
end

round(x::Rational, r::RoundingMode=RoundNearest) = round(typeof(x), x, r)

function round(::Type{T}, x::Rational{Tr}, r::RoundingMode=RoundNearest) where {T,Tr}
    if iszero(denominator(x)) && !(T <: Integer)
        return convert(T, copysign(unsafe_rational(one(Tr), zero(Tr)), numerator(x)))
    end
    convert(T, div(numerator(x), denominator(x), r))
end

function round(::Type{T}, x::Rational{Bool}, ::RoundingMode=RoundNearest) where T
    if denominator(x) == false && (T <: Integer)
        throw(DivideError())
    end
    convert(T, x)
end

function ^(x::Rational, n::Integer)
    n >= 0 ? power_by_squaring(x,n) : power_by_squaring(inv(x),-n)
end

^(x::Number, y::Rational) = x^(y.num/y.den)
^(x::T, y::Rational) where {T<:AbstractFloat} = x^convert(T,y)
^(z::Complex{T}, p::Rational) where {T<:Real} = z^convert(typeof(one(T)^p), p)

^(z::Complex{<:Rational}, n::Bool) = n ? z : one(z) # to resolve ambiguity
function ^(z::Complex{<:Rational}, n::Integer)
    n >= 0 ? power_by_squaring(z,n) : power_by_squaring(inv(z),-n)
end

iszero(x::Rational) = iszero(numerator(x))
isone(x::Rational) = isone(numerator(x)) & isone(denominator(x))

function lerpi(j::Integer, d::Integer, a::Rational, b::Rational)
    ((d-j)*a)/d + (j*b)/d
end

float(::Type{Rational{T}}) where {T<:Integer} = float(T)

function gcd(x::Rational, y::Rational)
    if isinf(x) != isinf(y)
        throw(ArgumentError("gcd is not defined between infinite and finite numbers"))
    end
    unsafe_rational(gcd(x.num, y.num), lcm(x.den, y.den))
end
function lcm(x::Rational, y::Rational)
    if isinf(x) != isinf(y)
        throw(ArgumentError("lcm is not defined between infinite and finite numbers"))
    end
    return unsafe_rational(lcm(x.num, y.num), gcd(x.den, y.den))
end
function gcdx(x::Rational, y::Rational)
    c = gcd(x, y)
    if iszero(c.num)
        a, b = zero(c.num), c.num
    elseif iszero(c.den)
        a = ifelse(iszero(x.den), one(c.den), c.den)
        b = ifelse(iszero(y.den), one(c.den), c.den)
    else
        idiv(x, c) = div(x.num, c.num) * div(c.den, x.den)
        _, a, b = gcdx(idiv(x, c), idiv(y, c))
    end
    c, a, b
end

## streamlined hashing for smallish rational types ##

decompose(x::Rational) = numerator(x), 0, denominator(x)
function hash(x::Rational{<:BitInteger64}, h::UInt)
    num, den = Base.numerator(x), Base.denominator(x)
    den == 1 && return hash(num, h)
    den == 0 && return hash(ifelse(num > 0, Inf, -Inf), h)
    if isodd(den) # since den != 1, this rational can't be a Float64
        pow = trailing_zeros(num)
        num >>= pow
        h = hash_integer(den, h)
    else
        pow = trailing_zeros(den)
        den >>= pow
        pow = -pow
        if den == 1
            if uabs(num) < UInt64(maxintfloat(Float64))
                return hash(ldexp(Float64(num),pow),h)
            end
        else
            h = hash_integer(den, h)
        end
    end
    h = hash_integer(pow, h)
    h = hash_integer((pow > 0) ? (num << (pow % 64)) : num, h)
    return h
end

# These methods are only needed for performance. Since `first(r)` and `last(r)` have the
# same denominator (because their difference is an integer), `length(r)` can be calculated
# without calling `gcd`.
function length(r::AbstractUnitRange{T}) where T<:Rational
    @inline
    f = first(r)
    l = last(r)
    return div(l.num - f.num + f.den, f.den)
end
function checked_length(r::AbstractUnitRange{T}) where T<:Rational
    f = first(r)
    l = last(r)
    if isempty(r)
        return f.num - f.num
    end
    return div(checked_add(checked_sub(l.num, f.num), f.den), f.den)
end
