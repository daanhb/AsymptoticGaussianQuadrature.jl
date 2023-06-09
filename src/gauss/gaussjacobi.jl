
function besselj_asymptotic_zero(nu::T, k::Integer) where {T <: AbstractFloat}
    T(π) * (k-1 + nu/2 + 3*one(T)/4)
end

function besselj_zero(nu, k)
    z = besselj_asymptotic_zero(nu, k)
    bf = (x) -> besselj(nu, x)
    return fzero(bf,z)
end

function approx_besselroots(nu::AbstractFloat, n::Integer)
    [besselj_zero(nu, k) for k in 1:n]
end

asy_gaussjacobi(n::Integer, α::Number, β::Number) =
    asy_gaussjacobi(n, promote(float(α), float(β))...)

function asy_gaussjacobi(n::Integer, α::T, β::T) where {T <: AbstractFloat}
    x = zeros(T, n)
    w = zeros(T, n)
    asy_gaussjacobi!(x, w, α, β)
end

# The expansions are in terms of z = 1/(2n+α+β+1)
jac_z(n, α, β) = 1/(2n+α+β+1)

function asy_gaussjacobi!(x, w, α, β)
    @assert length(x) == length(w)

    n = length(x)
    k_left = ceil(Int, sqrt(n))
    k_right = n-k_left+1

    z = jac_z(n, α, β)
    jb = approx_besselroots(β, k_left)
    δ = zero(eltype(x))
    for k in 1:k_left
        x_left, w_left, δ_left = asy_jacobi_leftendpoint(n, k, α, β, jb[k], z)
        x_bulk, w_bulk, δ_bulk = asy_jacobi_bulk(n, k, α, β, z)
        if δ_left < δ_bulk
            x[k], w[k] = x_left, w_left
            δ = max(δ, δ_left)
        else
            x[k], w[k] = x_bulk, w_bulk
            δ = max(δ, δ_bulk)
        end
    end
    ja = approx_besselroots(α, k_left)
    for k in k_right:n
        x_right, w_right, δ_right = asy_jacobi_rightendpoint(n, k, α, β, ja[n-k+1], z)
        x_bulk, w_bulk, δ_bulk = asy_jacobi_bulk(n, k, α, β, z)
        if δ_right < δ_bulk
            x[k], w[k] = x_right, w_right
            δ = max(δ, δ_right)
        else
            x[k], w[k] = x_bulk, w_bulk
            δ = max(δ, δ_bulk)
        end
    end
    for k in k_left+1:k_right-1
        x[k], w[k], δ_bulk = asy_jacobi_bulk(n, k, α, β, z)
        δ = max(δ, δ_bulk)
    end
    x, w
end

two(T) = 2*one(T)

gj_left_x3(z, jbk, α, β) = 2*jbk^2*z^2
gj_left_x5(z, jbk, α, β) = - 2/3*(jbk^4 - (3α^2 + β^2 - 1)*jbk^2)*z^4
gj_left_x7(z, jbk, α, β) = two(typeof(z))/45 *
    (2*jbk^6 - 3*(5α^2 + 3β^2 - 2)*jbk^4 + (45α^4 + 7β^4 + 20*(3α^2 - 1)*β^2 - 60α^2 + 13)*jbk^2)*z^6
gj_left_x9(z, jbk, α, β) = - two(eltype(z))/2835*(9*jbk^8 - 18*(7α^2 + 5β^2 - 3)*jbk^6
        + (328β^4 + (1512α^2 - 575)*β^2 + 567α^2 -113)*jbk^4
        - (2835α^6 + 247β^6 + 1407*(3α^2 - 1)*β^4 - 8505α^4 + 21*(405α^4 - 600α^2 + 133)*β^2 +8379α^2 - 1633)*jbk^2)*z^8
gj_left_x11(z, jbk, α, β) = two(z)/42525*(6*jbk^10 - 15*(9α^2 + 7β^2 - 4)*jbk^8 + (6615α^4
                + 769β^4 + 2*(1620α^2 - 589)*β^2 - 12150α^2 + 2668)*jbk^6 +
                3*(9450α^6 - 999β^6 - 23*(400α^2 - 147)*β^4 - 40635α^4 -
                (2835α^4 + 1850α^2 - 294)*β^2 + 50650α^2 - 10236)*jbk^4 +
                (42525α^8 + 2327β^8 + 22340*(3α^2 - 1)*β^6 - 226800α^6 + 168*(1530α^4 -
                2415α^2 + 542)*β^4 + 517860α^4 + 20*(11340α^6 - 38745α^4 + 42399α^2
                 - 8488)*β^2 - 509280α^2 + 98717)*jbk^2)*z^10

gj_left_w5(z, jbk, α, β) = one(eltype(z))/3*(3α^2 + β^2 - 2*jbk^2 - 1)*z^2
gj_left_w7(z, jbk, α, β) = one(eltype(z))/45*(45α^4 + 7β^4 + 6*jbk^4 + 20*(3α^2- 1)*β^2
    - 6*(5α^2 + 3β^2 - 2)*jbk^2 - 60α^2 + 13)*z^4
gj_left_w9(z, jbk, α, β) = one(eltype(z))/2835*(2835α^6 + 247β^6 - 36*jbk^6 + 1407*(3α^2 - 1)*β^4
        + 54*(7α^2 + 5β^2 - 3)*jbk^4 - 8505α^4
        + 21*(405α^4 - 600α^2 + 133)*β^2 - 2*(328β^4 +
        (1512α^2 - 575)*β^2 + 567α^2 - 113)*jbk^2 + 8379α^2 -1633)*z^6

function asy_jacobi_leftendpoint(n::Int, k::Int, α, β, jbk, z = jac_z(n, α, β))
    T = promote_type(typeof(α), typeof(β))
    x = zero(T)
    w = zero(T)

    # Add terms one by one and continue until the next term is larger than the previous one
    x3 = gj_left_x3(z, jbk, α, β)
    δ = abs(x3)
    if δ > eps(T) && δ < 1
        x += x3

        x5 = gj_left_x5(z, jbk, α, β)
        w5 = gj_left_w5(z, jbk, α, β)
        δ = abs(x5)
        if δ > eps(T) && δ < abs(x3)
            x += x5
            w += w5

            x7 = gj_left_x7(z, jbk, α, β)
            w7 = gj_left_w7(z, jbk, α, β)
            δ = abs(x7)
            if δ > eps(T) && δ < abs(x5)
                x += x7
                w += w7

                x9 = gj_left_x9(z, jbk, α, β)
                w9 = gj_left_w9(z, jbk, α, β)
                δ = abs(x9)
                if δ > eps(T) && δ < abs(x7)
                    x += x9
                    w += w9

                    x11 = gj_left_x11(z, jbk, α, β)
                    if abs(x11) > eps(T) && abs(x11) < abs(x9)
                        x += x11
                    end
                end
            end
        end
    end

    x += -1
    jbm = besselj(β-1, jbk)
    w = 8*z^2/jbm^2 * (1-x)^α*(1+x)^β * (1+w)
    x, w, δ
end

function asy_jacobi_rightendpoint(n, k, α, β, jak, z = jac_z(n, α, β))
    x, w, δ = asy_jacobi_leftendpoint(n, n-k, β, α, jak, z)
    -x, w, δ
end

gj_bulk_x3(t, z, α, β) = one(t)/2*(2α^2 - 2β^2 + (2α^2 + 2β^2 - 1)*t)*z^2
gj_bulk_x5(t, z, α, β) = - one(t)/24*(32α^4 - 32β^4 - (16α^4 + 16β^4 + 4*(12α^2 -5)*β^2 - 20α^2 + 5)*t^3
    - 24*(α^2 - β^2)*t^2 - 40α^2 + 40β^2+ 3*(16α^4 + 16β^4 + 4*(4α^2 - 7)*β^2
    - 28α^2 + 11)*t)*z^4/(t^2- 1)
gj_bulk_x7(t, z, α, β) = one(t)/240*(576α^6 - 576β^6 + (96α^6 + 96β^6 + 80*(8α^2 - 3)*β^4
    - 240α^4 + 2*(320α^4 - 440α^2 + 101)*β^2 + 202α^2 - 39)*t^5
    -320*(α^2 - 6)*β^4 + 240*(α^2 - β^2)*t^4 - 1920α^4
    -10*(32*(5α^2 + 3)*β^4 + 96α^4 + 2*(80α^4 - 152α^2 - 97)*β^2
    - 194α^2 + 99)*t^3 + 16*(20α^4 - 127)*β^2 + 160*(6α^6 - 6β^6 +
    2*(α^2 + 15)*β^4 - 30α^4 - (2α^4 + 41)*β^2 + 41α^2)*t^2 +
    2032α^2 + 15*(96α^6 + 96β^6 + 16*(4α^2 - 23)*β^4 - 368α^4
    + 2*(32α^4 - 72α^2 + 223)*β^2 + 446α^2 - 173)*t)*z^6/(t^4 - 2*t^2 +1)
gj_bulk_x9(t, z, α, β) = -one(t)/40320*(219648α^8 - 219648β^8 - (9728α^8 + 9728β^8 + 896*(138α^2 - 49)*β^6
    - 43904α^6 + 224*(1160α^4 - 1720α^2 + 389)*β^4 + 87136α^4
    + 8*(15456α^6 -48160α^4 + 49364α^2 - 9785)*β^2 - 78280α^2 + 14921)*t^7 - 10752*(14α^2 - 127)*β^6
    -40320*(α^2 - β^2)*t^6 - 1365504α^6 + 21*(2048α^8 + 2048β^8 + 128*(146α^2 -123)*β^6
    - 15744α^6 + 32*(1320α^4 - 1760α^2 + 2023)*β^4 + 64736α^4 + 8*(2336α^6- 7040α^4
    + 3644α^2 - 11275)*β^2 - 90200α^2 + 37111)*t^5 + 75264*(5α^2 - 49)*β^4
    + 4480*(44α^8 - 44β^8 + 8*(3α^2 + 55)*β^6 - 440α^6 - 24*(7α^2 + 72)*β^4
    +1728α^4 - (24α^6 - 168α^4 - 2405)*β^2 - 2405α^2)*t^4 + 3687936α^4
    + 105*(6656α^8 + 6656β^8 - 128*(50α^2 + 443)*β^6 - 56704α^6 - 32*(296α^4 -696α^2 - 6027)*β^4
    + 192864α^4 - 8*(800α^6 - 2784α^4 + 3580α^2 + 30285)*β^2 -242280α^2 + 99933)*t^3
    + 384*(392α^6 - 980α^4 + 10527)*β^2 + 2688*(424α^8 - 424β^8+ 4*(4α^2 + 783)*β^6 - 3132α^6
    + 4*(35α^2 - 2407)*β^4 + 9628α^4 - (16α^6 +140α^4 - 11429)*β^2 - 11429α^2)*t^2
    - 4042368α^2 + 35*(23552α^8 + 23552β^8 +128*(90α^2 - 1231)*β^6 - 157568α^6
    + 32*(328α^4 - 1376α^2 + 14095)*β^4 +451040α^4 + 8*(1440α^6 - 5504α^4 + 9964α^2 - 65439)*β^2
    - 523512α^2 +206379)*t)*z^8/(t^2 - 1)^3

gj_bulk_w3(t, z, α, β) = -(1 -2α^2 -2β^2)*z^2
gj_bulk_w5(t, z, α, β) = one(t)/12*((16α^4 + 16β^4 + 4*(12α^2 - 5)*β^2 - 20α^2 + 5)*t^4
    + 48α^4 + 48β^4 + 12*(4α^2 - 7)*β^2 - 6*(4*(4α^2 + 1)*β^2
    + 4α^2 - 3)*t^2 - 84α^2 + 64*(α^4 - β^4 - 2α^2 + 2β^2)*t +33)/(t^4 - 2*t^2 + 1)*z^4
gj_bulk_w7(t, z, α, β) = one(t)/120*((96α^6 + 96β^6 + 80*(8α^2 - 3)*β^4 - 240α^4 + 2*(320α^4 - 440α^2 +101)*β^2
    + 202α^2 - 39)*t^6 - 1440α^6 - 1440β^6 - 240*(4α^2 - 23)*β^4 - 5*(96α^6+ 96β^6
    + 16*(20α^2 - 27)*β^4 - 432α^4 + 2*(160α^4 - 136α^2 + 295)*β^2 + 590α^2 - 237)*t^4
    + 5520α^4 - 640*(3α^6 - 3β^6 + (α^2 + 15)*β^4 - 15α^4
    -(α^4 + 22)*β^2 + 22α^2)*t^3 - 30*(32α^4 - 72α^2 + 223)*β^2 - 15*(288α^6 +288β^6
    - 16*(8α^2 + 81)*β^4 - 1296α^4 - 2*(64α^4 - 88α^2 - 863)*β^2 +1726α^2 - 717)*t^2
    - 6690α^2 - 128*(33α^6 - 33β^6 - 5*(α^2 - 27)*β^4 - 135α^4 +(5α^4 - 166)*β^2 + 166α^2)*t
    + 2595)*z^6/(t^6 - 3*t^4 + 3*t^2 - 1)


function asy_jacobi_bulk(n, k, α, β, z = jac_z(n, α, β))
    t = cos(pi * (4n-4k+2α+3)/(4n+2α+2β+2))

    T = eltype(α)
    x = zero(T)
    w = zero(T)

    x3 = gj_bulk_x3(t, z, α, β)
    w3 = gj_bulk_w3(t, z, α, β)

    δ = abs(x3)
    if δ > eps(T) && δ < abs(t)
        x += x3
        w += w3

        x5 = gj_bulk_x5(t, z, α, β)
        w5 = gj_bulk_w5(t, z, α, β)
        δ = abs(x5)
        if δ > eps(T) && δ < abs(x3)
            x += x5
            w += w5

            x7 = gj_bulk_x7(t, z, α, β)
            w7 = gj_bulk_w7(t, z, α, β)
            δ = abs(x7)
            if δ > eps(T) && δ < abs(x5)
                x += x7
                w += w7

                x9 = gj_bulk_x9(t, z, α, β)
                if abs(x9) > eps(T) && abs(x9) < abs(x7)
                    x += x9
                end
            end
        end
    end

    x += t
    w = pi * sqrt(1-t^2) * z * (1-x)^α*(1+x)^β * (2+w)
    x, w, δ
end
