
# We explicitly store the first 11 roots of the Airy function in double precision
const airy_roots = [-2.338107410459767, -4.08794944413097, -5.520559828095551,
    -6.786708090071759, -7.944133587120853, -9.02265085340981, -10.04017434155809,
    -11.00852430373326, -11.93601556323626, -12.828776752865757, -13.69148903521072]

# heuristic for the number of terms
asy_gl_terms(n) = max(1, ceil(Int, 50/log(n)))

# heuristic for the last index of the bessel region
asy_gl_index_bessel(n) = max(ceil(Int, sqrt(n)), 7)

# heuristic for the first index of the airy region
asy_gl_index_airy(n) = floor(Int, 0.9*n)

"""
Compute the generalised Gauss-Laguerre rule with parameter `α` using explicit
asymptotic expansions for the nodes and weights.

Optional parameters are:
- `reduced`: compute a reduced quadrature rule, discarding all points and weights
as soon as the weights underflow
- `order`: the order of the expansion. Set `order=-1` to determine the order adaptively
depending on the size of the terms in the expansion
- `recompute`: if a crude measure of the error is larger than a tolerance,
the points and weights are recomputed using the (slower) recursion+newton approach,
yielding more reliable accurate results.
"""
function asy_gausslaguerre(n::Integer, α;
    reduced = false,
    order = asy_gl_terms(n),
    recompute = false,
    verbose = false)

    if α^2/n > 1
        @warn "A large value of α may lead to inaccurate results."
    end

    ELT = typeof(float(α))

    n_alloc = reduced ? 0 : n
    x = zeros(ELT, n_alloc)
    w = zeros(ELT, n_alloc)

    # The expansions are given in powers of 1/(4n+2α+2)
    d = one(ELT)/(4n+2α+2)

    # Heuristical indices for Bessel and Airy regions
    k_bessel = asy_gl_index_bessel(n)
    k_airy = asy_gl_index_airy(n)

    # The Bessel region
    # First compute the roots of the Bessel function of order α
    jak_vector = approx_besselroots(α, k_bessel)

    bessel_wins = true
    k = 0
    while bessel_wins && k < n
        k += 1
        # We iterate until the estimated error of the bulk expansion is smaller
        # than the one of the Bessel expansion
        jak = (k < k_bessel) ? jak_vector[k] : jak = FastGaussQuadrature.McMahon(α, k)

        xk, wk, δ_bessel = asy_gausslaguerre_bessel(n, α, jak, d, order)
        xkb, wkb, δ_bulk = asy_gausslaguerre_bulk(n, α, k, d, order)
        if δ_bulk < δ_bessel
            bessel_wins = false
            xk = xkb
            wk = wkb
        end
        if recompute
            δ = min(δ_bessel,δ_bulk)
            if δ > 1e-13
                xk_rec, wk_rec = gl_rec_newton(xk, n, α)
                if abs(xk_rec-xk) < 100δ
                    xk = xk_rec
                    wk = wk_rec
                end
            end
        end
        if reduced
            if abs(wk) < underflow_threshold(ELT)
                return x, w
            else
                push!(x, xk); push!(w, wk)
            end
        else
            x[k] = xk; w[k] = wk
        end
    end
    verbose && println("Bessel region truncated at index k = $(k).")

    # The bulk region
    # - First we go from where we left of to our heuristic
    while k < k_airy-1
        k += 1
        xk, wk, δ_bulk = asy_gausslaguerre_bulk(n, α, k, d, order)
        if recompute
            if δ_bulk > 1e-13
                xk_rec, wk_rec = gl_rec_newton(xk, n, α)
                if abs(xk_rec-xk) < 100δ_bulk
                    xk = xk_rec
                    wk = wk_rec
                end
            end
        end
        if reduced
            if abs(wk) < underflow_threshold(ELT)
                return x, w
            else
                push!(x, xk); push!(w, wk)
            end
        else
            x[k] = xk; w[k] = wk
        end
    end

    # - Then we compare to Airy until it wins, and then we switch to just Airy
    bulk_wins = true
    while bulk_wins && k < n
        k += 1
        xk, wk, δ_bulk = asy_gausslaguerre_bulk(n, α, k, d, order)
        xka, wka, δ_airy = asy_gausslaguerre_airy(n, α, k, d, order)
        if δ_airy < δ_bulk
            bulk_wins = false
            xk = xka
            wk = wka
        end
        if recompute
            δ = min(δ_airy,δ_bulk)
            if δ > 1e-13
                xk_rec, wk_rec = gl_rec_newton(xk, n, α)
                if abs(xk_rec-xk) < 100δ
                    xk = xk_rec
                    wk = wk_rec
                end
            end
        end
        if reduced
            if abs(wk) < underflow_threshold(ELT)
                return x, w
            else
                push!(x, xk); push!(w, wk)
            end
        else
            x[k] = xk; w[k] = wk
        end
    end

    verbose && println("Airy region starts at index k = $(k+1).")

    # The Airy region
    while k < n
        k += 1
        xk, wk, δ_airy = asy_gausslaguerre_airy(n, α, k, d, order)
        if recompute
            if δ_airy > 1e-13
                xk_rec, wk_rec = gl_rec_newton(xk, n, α)
                if abs(xk_rec-xk) < 100δ_airy
                    xk = xk_rec
                    wk = wk_rec
                end
            end
        end
        if reduced
            if abs(wk) < underflow_threshold(ELT)
                return x, w
            else
                push!(x, xk); push!(w, wk)
            end
        else
            x[k] = xk; w[k] = wk
        end
    end

    # Sanity check
    if ( minimum(x) < 0.0 ) || ( maximum(x) > 4*n + 2*α + 2 ) ||  ( minimum(diff(x)) <= 0.0 ) || (minimum(w) < 0.0)
        @warn "Unexpected inconsistency in the computation of nodes and weights"
    end

    x, w
end

## Expansion coefficients
# These are explicit formulas of the coefficients, up to a simple postprocessing
# that is common to all factors and not included here (see below).
#
# General expressions are given in terms of α, more specific expressions
# follow for the special case α = 0.

## The bulk

# Note: there is always one division by an integer, placed such that it preserves the type of `d`
gl_bulk_x3(t, d, α) = -(12*α^2 + 5*(1-t)^(-2) - 4*(1-t)^(-1) - 4) * d / 12
gl_bulk_x5(t, d, α) = d^3*(1-t)/t/720*(1600*(1-t)^(-6) - 3815*(1-t)^(-5)
    + 480*α^4 +2814*(1-t)^(-4) - 576*(1-t)^(-3) - 960*α^2 - 48*(15*α^4 - 30*α^2 + 7)*(1-t)^(-1)
    -16*(1-t)^(-2) + 224)
gl_bulk_x7(t, d, α) = -d^5/181440*(1-t)^2/t^2*(10797500*(1-t)^(-10) - 43122800*(1-t)^(-9)
    + 66424575*(1-t)^(-8) -48469876*(1-t)^(-7) + 193536*α^6 + 16131880*(1-t)^(-6)
    + 80*(315*α^4 - 630*α^2 -221)*(1-t)^(-4) - 1727136*(1-t)^(-5)
    - 967680*α^4 - 320*(63*α^4 - 126*α^2 +43)*(1-t)^(-3)
    + 384*(945*α^6 - 4620*α^4 + 6405*α^2 - 1346)*(1-t)^(-2)
    + 1354752*α^2   - 23040*(21*α^6 - 105*α^4 + 147*α^2 - 31)*(1-t)^(-1) -285696)
gl_bulk_x9(t, d, α) = d^7/10886400*(1-t)^3/t^3*(43222750000*(1-t)^(-14) - 241928673000*(1-t)^(-13)
    + 566519158800*(1-t)^(-12) -714465642135*(1-t)^(-11) + 518401904799*(1-t)^(-10)
    + 672*(12000*α^4 - 24000*α^2 +64957561)*(1-t)^(-8) - 212307298152*(1-t)^(-9)
    + 24883200*α^8 - 192*(103425*α^4 -206850*α^2 + 15948182)*(1-t)^(-7)
    + 3360*(4521*α^4 - 9042*α^2 - 7823)*(1-t)^(-6) -232243200*α^6
    - 1792*(3375*α^6 - 13905*α^4  + 17685*α^2 - 1598)*(1-t)^(-5)
    + 16128*(450*α^6 - 2155*α^4 + 2960*α^2 - 641)*(1-t)^(-4)
    + 812851200*α^4 -768*(70875*α^8 - 631260*α^6 + 2163630*α^4
    - 2716980*α^2 +555239)*(1-t)^(-3)  + 768*(143325*α^8 - 1324260*α^6
    + 4613070*α^4 -5826660*α^2 + 1193053)*(1-t)^(-2) - 1028505600*α^2
    - 5806080*(15*α^8 -140*α^6 + 490*α^4 - 620*α^2 + 127)*(1-t)^(-1) + 210677760)

gl_bulk_w3(t, d, α) = d^2/6*(2*t + 3)/(t-1)^3
gl_bulk_w5(t, d, α) = (1-t)^2/720/t^2*d^4*(8000*(1-t)^(-8) - 24860*(1-t)^(-7) + 27517*(1-t)^(-6)
    - 12408*(1-t)^(-5) + 1712*(1-t)^(-4) +16*(15*α^4 - 30*α^2 + 7)*(1-t)^(-2) + 32*(1-t)^(-3))
gl_bulk_w7(t, d, α) = -(1-t)^3/90720/t^3*d^6*(43190000*(1-t)^(-12) -204917300*(1-t)^(-11)
    + 393326325*(1-t)^(-10) - 386872990*(1-t)^(-9) + 201908326*(1-t)^(-8)
    + 80*(315*α^4 - 630*α^2 + 53752)*(1-t)^(-6)  - 50986344*(1-t)^(-7)
    - 320*(189*α^4 -378*α^2 - 89)*(1-t)^(-5) + 480*(63*α^4 - 126*α^2
    + 43)*(1-t)^(-4)  -384*(315*α^6 - 1470*α^4 + 1995*α^2 - 416)*(1-t)^(-3)
    + 2304*(21*α^6 -105*α^4 + 147*α^2 - 31)*(1-t)^(-2) )

# And for α = 0
gl_bulk_x3(t, d) = -d/12*(5*(1-t)^(-2) - 4*(1-t)^(-1) - 4)
gl_bulk_x5(t, d) = d^3*(1-t)/t/720*(1600*(1-t)^(-6) - 3815*(1-t)^(-5) + 2814*(1-t)^(-4)
    - 576*(1-t)^(-3) - 48*7*(1-t)^(-1) -16*(1-t)^(-2) + 224)
gl_bulk_x7(t, d) = -d^5/181440*(1-t)^2/t^2*(10797500*(1-t)^(-10)
    - 43122800*(1-t)^(-9) + 66424575*(1-t)^(-8) -48469876*(1-t)^(-7)
    + 16131880*(1-t)^(-6) - 80*221*(1-t)^(-4) - 1727136*(1-t)^(-5) - 320*43*(1-t)^(-3)
    - 384*1346*(1-t)^(-2) + 23040*31*(1-t)^(-1) -285696)
gl_bulk_x9(t, d) = d^7/10886400*(1-t)^3/t^3*(43222750000*(1-t)^(-14)
    - 241928673000*(1-t)^(-13) + 566519158800*(1-t)^(-12) -714465642135*(1-t)^(-11)
    + 518401904799*(1-t)^(-10) + 672*64957561*(1-t)^(-8)   - 212307298152*(1-t)^(-9)
    - 192*15948182*(1-t)^(-7)  - 3360*7823*(1-t)^(-6) + 1792*1598*(1-t)^(-5)
    + 16128*(- 641)*(1-t)^(-4)  -768*555239*(1-t)^(-3)  + 768*1193053*(1-t)^(-2)
    - 5806080*127*(1-t)^(-1) + 210677760)

gl_bulk_w3(t, d) = d^2/6*(2*t + 3)/(t-1)^3
gl_bulk_w5(t, d) = (1-t)^2/720/t^2*d^4*(8000*(1-t)^(-8) - 24860*(1-t)^(-7)
    + 27517*(1-t)^(-6) - 12408*(1-t)^(-5) + 1712*(1-t)^(-4) +16*7*(1-t)^(-2)
    + 32*(1-t)^(-3))
gl_bulk_w7(t, d) = -(1-t)^3/90720/t^3*d^6*(43190000*(1-t)^(-12)
    - 204917300*(1-t)^(-11) + 393326325*(1-t)^(-10) - 386872990*(1-t)^(-9)
    + 201908326*(1-t)^(-8) +80*53752*(1-t)^(-6)
    - 50986344*(1-t)^(-7) + 320*89*(1-t)^(-5)
    + 480*43*(1-t)^(-4) + 384*416*(1-t)^(-3) - 2304*31*(1-t)^(-2) )


## The hard edge (Bessel region)

gl_bessel_x3(jak, d, α) = (jak^2 + 2*α^2 - 2)*d^2 / 3
gl_bessel_x5(jak, d, α) = (11*jak^4 +3*jak^2*(11*α^2-19) +46*α^4 -140*α^2 +94)*d^4 / 45
gl_bessel_x7(jak, d, α) = (657*jak^6 +36*jak^4*(73*α^2-181) +2*jak^2*(2459*α^4 -10750*α^2 +14051)
    + 4*(1493*α^6 -9303*α^4 +19887*α^2 - 12077) )*d^6 / 2835
gl_bessel_x9(jak, d, α) = (10644*jak^8 + 60*(887*α^2 - 2879)*jak^6 + (125671*α^4 -729422*α^2 + 1456807)*jak^4
    + 3*(63299*α^6 - 507801*α^4 + 1678761*α^2 - 2201939)*jak^2 + 2*(107959*α^8
    - 1146220*α^6 + 5095482*α^4 -10087180*α^2 + 6029959) )*d^8 / 42525

gl_bessel_w3(jak, d, α) = (α^2 + jak^2 -1)*2*d^2 / 3
gl_bessel_w5(jak, d, α) = (46*α^4 + 33*jak^4 +6*jak^2*(11*α^2 -19) -140*α^2 +94)*d^4 / 45
gl_bessel_w7(jak, d, α) = (1493*α^6 + 657*jak^6 + 27*(73*α^2 - 181)*jak^4 - 9303*α^4
    + (2459*α^4 -10750*α^2 + 14051)*jak^2 + 19887*α^2 - 12077)*4*d^6 / 2835
gl_bessel_w9(jak, d, α) = (215918*α^8 + 53220*jak^8 + 240*(887*α^2 - 2879)*jak^6 -2292440*α^6 +
    3*(125671*α^4 - 729422*α^2 + 1456807)*jak^4 + 10190964*α^4  +
    6*(63299*α^6 - 507801*α^4 + 1678761*α^2 -2201939)*jak^2 -
    20174360*α^2 + 12059918)*d^8 / 42525

# And for α = 0:
gl_bessel_x3(jak, d) = (jak^2 - 2)*d^2 / 3
gl_bessel_x5(jak, d) = (11*jak^4 - 57*jak^2 + 94)d^4 / 45
gl_bessel_x7(jak, d) = (657*jak^6 - 6516*jak^4 + 28102*jak^2 - 48308)*d^6 / 2835
gl_bessel_x9(jak, d) = (10644*jak^8 - 172740*jak^6 + 1456807*jak^4 -  6605817*jak^2 + 12059918)*d^8 / 42525
gl_bessel_x11(jak, d) = (410649*jak^10 -  9908262*jak^8 + 138902061*jak^6 - 1248722004*jak^4 + 6028914206*jak^2 - 11427291076)*d^10 / 1403325

gl_bessel_w3(jak, d) = (jak^2 - 1)*2*d^2 / 3
gl_bessel_w5(jak, d) = (33*jak^4 -114*jak^2 + 94)*d^4 / 45
gl_bessel_w7(jak, d) = (657*jak^6 - 4887*jak^4 + 14051*jak^2 - 12077)*4*d^6 / 2835
gl_bessel_w9(jak, d) = (53220*jak^8 - 690960*jak^6 + 4370421*jak^4 - 13211634*jak^2 + 12059918)*d^8 / 42525
gl_bessel_w11(jak, d) = (1231947*jak^10 - 24770655*jak^8 + 277804122*jak^6 - 1873083006*jak^4 + 6028914206*jak^2 - 5713645538)*2*d^10 / 1403325


## The soft edge (Airy region)

gl_airy_x1(ak, d, α) = 1/d + ak*(d/4)^(-1/3)
gl_airy_x3(ak, d, α) = ak^2*(d*16)^(1/3)/5 + (11/35-α^2-12/175*ak^3)*d + (16/1575*ak+92/7875*ak^4)*2^(2/3)*d^(5/3)
gl_airy_x5(ak, d, α) = -(15152/3031875*ak^5+1088/121275*ak^2)*2^(1/3)*d^(7/3)

gl_airy_x1(ak, d) = 1/d + ak*(d/4)^(-1/3)
gl_airy_x3(ak, d) = ak^2*(d*16)^(1/3)/5 + (11/35-12/175*ak^3)*d + (16/1575*ak+92/7875*ak^4)*2^(2/3)*d^(5/3)
gl_airy_x5(ak, d) = -(15152/3031875*ak^5+1088/121275*ak^2)*2^(1/3)*d^(7/3)


function gl_bulk_solve_t(n, k, d)
    T = typeof(d)
    pt = (4n-4k+3)*d
    t = T(pi)^2/16*(pt-1)^2
    diff = 100
    iter = 0
    maxiter = 20
    while (abs(diff) > 100eps(T)) && (iter < maxiter)
        iter += 1
        diff = (pt*pi +2*sqrt(t-t^2) -acos(2*t-1) )*sqrt(t/(1-t))/2
        t -= diff
    end
    if iter == maxiter
        @warn "Maximal number of iterations reached in the computation of t for the bulk"
    end
    t
end

function asy_gausslaguerre_bulk(n, α, k, d, order)
    if α == 0
        return asy_gausslaguerre0_bulk(n, k, d, order)
    end

    t = gl_bulk_solve_t(n, k, d)
    x3 = gl_bulk_x3(t, d, α)
    x5 = gl_bulk_x5(t, d, α)
    x7 = gl_bulk_x7(t, d, α)
    x9 = gl_bulk_x9(t, d, α)
    w3 = gl_bulk_w3(t, d, α)
    w5 = gl_bulk_w5(t, d, α)
    w7 = gl_bulk_w7(t, d, α)

    xs = (x3, x5, x7, x9)
    ws = (w3, w5, w7)

    xk, xdelta = (order > 0) ? sum_fixed_terms(xs, (order-1)>>1) : sum_decreasing_terms(xs)
    wk, wdelta = (order > 0) ? sum_fixed_terms(ws, (order-1)>>1) : sum_decreasing_terms(ws)

    xk += t/d

    wfactor = xk^α * exp(-xk) * 2pi * sqrt(t/(1-t))
    wk = wfactor * (1+wk)
    wdelta *= wfactor

    xk, wk, max(xdelta,wdelta)
end


function asy_gausslaguerre0_bulk(n, k, d, order)
    t = gl_bulk_solve_t(n, k, d)
    x3 = gl_bulk_x3(t, d)
    x5 = gl_bulk_x5(t, d)
    x7 = gl_bulk_x7(t, d)
    x9 = gl_bulk_x9(t, d)
    w3 = gl_bulk_w3(t, d)
    w5 = gl_bulk_w5(t, d)
    w7 = gl_bulk_w7(t, d)

    xs = (x3, x5, x7, x9)
    ws = (w3, w5, w7)

    xk, xdelta = (order > 0) ? sum_fixed_terms(xs, (order-1)>>1) : sum_decreasing_terms(xs)
    wk, wdelta = (order > 0) ? sum_fixed_terms(ws, (order-1)>>1) : sum_decreasing_terms(ws)

    xk += t/d

    wfactor = exp(-xk) * 2pi * sqrt(t/(1-t))
    wk = wfactor * (1+wk)
    wdelta *= wfactor

    xk, wk, max(xdelta,wdelta)
end


function asy_gausslaguerre_bessel(n, α, jak, d, order)
    if α == 0
        return asy_gausslaguerre0_bessel(n, jak, d, order)
    end
    x3 = gl_bessel_x3(jak, d, α)
    x5 = gl_bessel_x5(jak, d, α)
    x7 = gl_bessel_x7(jak, d, α)
    x9 = gl_bessel_x9(jak, d, α)
    w3 = gl_bessel_w3(jak, d, α)
    w5 = gl_bessel_w5(jak, d, α)
    w7 = gl_bessel_w7(jak, d, α)
    w9 = gl_bessel_w9(jak, d, α)

    xs = (x3, x5, x7, x9)
    ws = (w3, w5, w7, w9)

    xk, xdelta = (order > 0) ? sum_fixed_terms(xs, (order-1)>>1) : sum_decreasing_terms(xs)
    wk, wdelta = (order > 0) ? sum_fixed_terms(ws, (order-1)>>1) : sum_decreasing_terms(ws)

    xfactor = jak^2 * d
    xk = xfactor * (1 + xk)
    xdelta *= xfactor

    # Invoking the besselj function below is the cause of memory
    # allocation of this routine
    wfactor = 4d * xk^α * exp(-xk) / besselj(α-1, jak)^2
    wk = wfactor * (1 + wk)
    wdelta *= wfactor

    xk, wk, max(xdelta,wdelta)
end

function asy_gausslaguerre0_bessel(n, jak, d, order)
    x3 = gl_bessel_x3(jak, d)
    x5 = gl_bessel_x5(jak, d)
    x7 = gl_bessel_x7(jak, d)
    x9 = gl_bessel_x9(jak, d)
    x11 = gl_bessel_x11(jak, d)
    w3 = gl_bessel_w3(jak, d)
    w5 = gl_bessel_w5(jak, d)
    w7 = gl_bessel_w7(jak, d)
    w9 = gl_bessel_w9(jak, d)
    w11 = gl_bessel_w11(jak, d)

    xs = (x3, x5, x7, x9, x11)
    ws = (w3, w5, w7, w9, w11)

    xk, xdelta = (order > 0) ? sum_fixed_terms(xs, (order-1)>>1) : sum_decreasing_terms(xs)
    wk, wdelta = (order > 0) ? sum_fixed_terms(ws, (order-1)>>1) : sum_decreasing_terms(ws)

    xfactor = jak^2 * d
    xk = xfactor * (1 + xk)
    xdelta *= xfactor

    wfactor = 4d * exp(-xk) / besselj(-1, jak)^2
    wk = wfactor * (1 + wk)
    wdelta *= wfactor

    xk, wk, max(xdelta,wdelta)
end

function compute_airy_root(n, k)
    index = n-k+1
    if index <= 11
        ak = airy_roots[index]
    else
        t = 3 * pi/2 * (index-0.25)
        ak = -t^(2/3)*(1 + 5/48/t^2 - 5/36/t^4 + 77125/82944/t^6 -10856875/6967296/t^8)
    end
    ak
end

function asy_gausslaguerre_airy(n, α, k, d, order)
    if α == 0
        return asy_gausslaguerre0_airy(n, k, d, order)
    end

    ak = compute_airy_root(n, k)
    x1 = gl_airy_x1(ak, d, α)
    x3 = gl_airy_x3(ak, d, α)
    x5 = gl_airy_x5(ak, d, α)

    xs = (x1, x3, x5)

    xk, xdelta = (order > 0) ? sum_fixed_terms(xs, (order+1)>>1) : sum_decreasing_terms(xs)

    wk = 4^(1/3)*xk^(α+1/3)*exp(-xk)/(airyaiprime(ak))^2
    wdelta = abs(wk)

    xk, wk, max(xdelta,wdelta)
end

function asy_gausslaguerre0_airy(n, k, d, order)
    ak = compute_airy_root(n, k)

    x1 = gl_airy_x1(ak, d)
    x3 = gl_airy_x3(ak, d)
    x5 = gl_airy_x5(ak, d)

    xs = (x1, x3, x5)

    xk, xdelta = (order > 0) ? sum_fixed_terms(xs, (order+1)>>1) : sum_decreasing_terms(xs)

    wk = 4^(1/3) * xk^(1/3) * exp(-xk) / (airyaiprime(ak))^2
    wdelta = abs(wk)

    xk, wk, max(xdelta,wdelta)
end




"""
Calculate Gauss-Laguerre nodes and weights from the eigenvalue decomposition of
the Jacobi matrix.
"""
function gausslaguerre_GW(n, α)
    αvec = 2*(1:n) .+ (α-1)     # 3-term recurrence coeffs a and b
    βvec = sqrt.( (1:n-1).*(α .+ (1:n-1)) )
    J = SymTridiagonal(Vector(αvec), βvec)  # Jacobi matrix
    x, V = eigen(J)                 # eigenvalue decomposition
    w = gamma(α+1)*V[1,:].^2    # Quadrature weights
    x, vec(w)
end


########################## Routines for the forward recurrence ##########################

function gl_rec_newton(x0, n, α; maxiter = 20, computeweight = true)
    T = eltype(x0)
    step = x0
    iter = 0
    xk = x0

    xk_prev = xk
    pn_prev = floatmax(T)
    pn_deriv = zero(T)
    while (abs(step) > 40eps(T)*xk) && (iter < maxiter)
        iter += 1
        pn, pn_deriv = evalLaguerreRec(n, α, xk)
        if abs(pn) >= abs(pn_prev)*(1-50eps(T))
            # The function values do not decrease enough any more due to roundoff errors.
            xk = xk_prev # Set to the previous value and quit.
            break
        end
        step = pn / pn_deriv
        xk_prev = xk
        xk -= step
        pn_prev = pn
    end
    if ( xk < 0 ) || ( xk > 4n + 2α + 2 ) || ( iter == maxiter )
        @warn "Newton method may not have converged in gausslaguerre_rec($n,$α)."
    end
    wk = oftype(xk, 0)
    if computeweight
        pn_min1, ~ = evalLaguerreRec(n-1, α, xk)
        wk = (n^2 +α*n)^(-1/2)/pn_min1/pn_deriv
    end
    xk, wk
end

"Compute Gauss-Laguerre rule based on the recurrence relation, using Newton iterations on an initial guess."
function gausslaguerre_rec(n, α; reduced = false)
    T = typeof(float(α))

    n_alloc = reduced ? 0 : n
    w = zeros(T, n_alloc)
    x = zeros(T, n_alloc)

    # We compute up to 7 starting values for the Newton iterations
    n_pre = min(n, 7)

    nu = 4n + 2α + 2
    x_pre = T.(approx_besselroots(α, n_pre)).^2 / nu # this is a lower bound by [DLMF 18.16.10]

    noUnderflow = true      # this flag turns false once the weights start to underflow
    for k in 1:n
        local pn_deriv

        # Use sextic extrapolation for a new initial guess
        xk = (k <= n_pre) ? x_pre[k] : 7*x[k-1] -21*x[k-2] +35*x[k-3] -35*x[k-4] +21*x[k-5] -7*x[k-6] +x[k-7]

        xk, wk = gl_rec_newton(xk, n, α, maxiter = 20, computeweight = noUnderflow)
        if noUnderflow && abs(wk) < underflow_threshold(T)
            noUnderflow = false
        end

        if reduced
            if !noUnderflow
                return x, w
            else
                push!(x, xk); push!(w, wk)
            end
        else
            x[k] = xk; w[k] = wk
        end
    end
    x, w
end


"""
Evaluate the orthonormal associated Laguerre polynomial with positive leading coefficient,
as well as its derivative, in the point x using the recurrence relation.
"""
function evalLaguerreRec(n, α, x)
    T = typeof(α)
    pnprev = zero(T)
    pn = 1/sqrt(gamma(α+1))
    pndprev = zero(T)
    pnd = zero(T)
    for k in 1:n
        pnold = pn
        pn = (x -2*k -α+1)/sqrt(k*(α+k))*pnold-sqrt((k-1+α)*(k-1)/k/(k+α))*pnprev
        pnprev = pnold
        pndold = pnd
        pnd = (pnold+(x-2*k-α+1)*pndold)/sqrt(k*(α+k)) -sqrt((k-1+α)*(k-1)/k/(α+k))*pndprev
        pndprev = pndold
    end
    pn, pnd
end
