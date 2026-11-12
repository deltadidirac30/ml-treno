module DOEGenerator

using Random
using Statistics
using StatsBase: autocor

export DOEConfig
export latin_hypercube, sample_doe
export sobol_sequence, scrambled_sobol, sample_doe_sobol
export generate_slope, generate_stops, generate_vlim, generate_route
export estimate_correlation_length, profile_metrics, slope_segment_count
export max_stops, round_trip_features, estimate_round_trip_h

# Limiti del DoE (10/11/2026), allargati per coprire le 166 linee non
# elettrificate della rete. Gli stessi vincoli sono nel generatore MATLAB
# (funzioni_preconfiguratore/doe_generator_settings.m del preconfiguratore).
# Revisione D27 (11/11/2026), sulle linee reali (tratte_rete/riepilogo.csv):
# indice di restrizione 0-0,6; al più 30 fermate di sola andata, capolinea
# compresi, e al più 0,6 fermate per km capolinea compresi; andata e ritorno
# entro 12 h (stima della durata calibrata sulla dinamica, L accorciata).
Base.@kwdef struct DOEConfig
    L_min::Float64 = 5.0
    L_max::Float64 = 300.0

    slope_mean_abs_max::Float64 = 20.0
    slope_std_max::Float64 = 20.0
    slope_segment_mean_min_km::Float64 = 0.5
    slope_segment_mean_max_km::Float64 = 3.5
    slope_segment_min_km::Float64 = 0.5
    slope_segment_length_cv::Float64 = 0.60
    slope_abs_limit::Float64 = 40.0
    elevation_abs_max_m::Float64 = 12_000.0
    # profili oltre ±slope_abs_limit compressi con limit*tanh(p/limit) e
    # riportati a media e deviazione richieste (al massimo tante iterazioni)
    slope_squash_iterations::Int = 100

    # fermate di sola andata, capolinea compresi: al più stop_count_max e al
    # più stop_density_max per km (n_stops + 2 <= floor(stop_density_max*L));
    # n_stops = round(u_5 * max_stops(L)), uniforme tra 0 e il massimo
    stop_count_max::Int = 30
    stop_density_max::Float64 = 0.6
    stop_spacing_cv_max::Float64 = 1.5
    stop_min_spacing_km::Float64 = 0.2

    # fino a 160 km/h: velocità massima del treno simulato (Hitachi Blues)
    speed_classes::Vector{Float64} = collect(60.0:5.0:160.0)
    # limite più basso dei tratti e riferimento dell'indice di restrizione:
    # velocità media obiettivo = v_max - indice*(v_max - speed_min_kmh)
    speed_min_kmh::Float64 = 30.0
    speed_step_kmh::Float64 = 5.0
    speed_restriction_max::Float64 = 0.6
    speed_change_density_max::Float64 = 0.25
    speed_min_segment_km::Float64 = 0.05
    speed_segment_cv::Float64 = 0.40
    speed_mean_tolerance_kmh::Float64 = 5.0

    flat_fraction::Float64 = 0.10
    no_stops_fraction::Float64 = 0.10
    constant_speed_fraction::Float64 = 0.10

    # durata dell'andata e ritorno simulata: al più round_trip_max_h, altrimenti
    # L si accorcia (velocità e fermate restano distribuite come sono). Stima
    # (estimate_round_trip_h): soste di dwell_s, capolinea di terminus_s, tempo
    # ai limiti per duration_alpha e kappa secondi per m/s di velocità a ogni
    # partenza e arrivo; tutto per (1 + duration_margin). Coefficienti calibrati
    # sulla dinamica del preconfiguratore (D26, D27, treno di 255 t).
    # Calibrazione (11/11/2026, report_natanti/D27.md del repo train-powertrain):
    # 512 tratte esportate dal MATLAB (le 384 più lunghe e 128 a caso), dinamica
    # con D26 e D27 a 255 t, minimi quadrati: alpha 0,99567, kappa 1,1303. Il
    # profilo dei limiti di Julia non è quello di build_doe_route (stesso
    # algoritmo, estrazioni diverse): vera/stimata fino a 1,114 sopra le 9 h,
    # da cui il margine del 12% (scelta dell'utente: circa il 3% delle tratte
    # accorciate invece dell'1,4% strettamente necessario).
    round_trip_max_h::Float64 = 12.0
    dwell_s::Float64 = 120.0
    terminus_s::Float64 = 300.0
    duration_alpha::Float64 = 0.9957
    duration_kappa_s_per_ms::Float64 = 1.130
    duration_margin::Float64 = 0.12
end

"""
    latin_hypercube(rng, n, d)

Generate an `n × d` Latin hypercube in the open interval `[0, 1)`.
Every column contains exactly one sample in each of the `n` equal strata.
"""
function latin_hypercube(rng::AbstractRNG, n::Int, d::Int)::Matrix{Float64}
    n > 0 || throw(ArgumentError("n must be positive"))
    d > 0 || throw(ArgumentError("d must be positive"))

    design = Matrix{Float64}(undef, n, d)
    for j in 1:d
        strata = randperm(rng, n)
        @inbounds for i in 1:n
            design[i, j] = (strata[i] - 1 + rand(rng)) / n
        end
    end
    return design
end

# Primitive-polynomial parameters and initial direction numbers for the first
# nine Sobol dimensions (Bratley-Fox convention). The route DoE currently has
# exactly nine independent dimensions, so a larger external dependency is not
# needed here.
const _SOBOL_PARAMS = (
    (s=0, a=0, m=Int[]),
    (s=1, a=0, m=[1]),
    (s=2, a=1, m=[1, 3]),
    (s=3, a=1, m=[1, 3, 1]),
    (s=3, a=2, m=[1, 1, 1]),
    (s=4, a=1, m=[1, 1, 3, 3]),
    (s=4, a=4, m=[1, 3, 5, 13]),
    (s=5, a=2, m=[1, 1, 5, 5, 17]),
    (s=5, a=4, m=[1, 1, 5, 5, 5]),
)

function _sobol_directions(d::Int, bits::Int)
    1 <= d <= length(_SOBOL_PARAMS) ||
        throw(ArgumentError("Sobol implementation supports 1:9 dimensions"))
    1 <= bits <= 63 || throw(ArgumentError("bits must be in 1:63"))

    directions = Matrix{UInt64}(undef, d, bits)
    @inbounds for j in 1:bits
        directions[1, j] = UInt64(1) << (64 - j)
    end

    @inbounds for dim in 2:d
        params = _SOBOL_PARAMS[dim]
        s = params.s
        a = params.a

        for j in 1:min(s, bits)
            directions[dim, j] = UInt64(params.m[j]) << (64 - j)
        end

        for j in s+1:bits
            value = xor(
                directions[dim, j-s],
                directions[dim, j-s] >> s,
            )
            for k in 1:s-1
                coefficient = (a >> (s - 1 - k)) & 1
                coefficient == 1 && (value = xor(value, directions[dim, j-k]))
            end
            directions[dim, j] = value
        end
    end
    return directions
end

"""
    sobol_sequence(n, d; skip=0, bits=52)

Generate `n` points of an unscrambled Sobol sequence in `d ≤ 9` dimensions.
`skip` is a zero-based sequence offset. The first point is the all-zero point,
as in the standard base-2 construction.
"""
function sobol_sequence(
    n::Int,
    d::Int;
    skip::Int=0,
    bits::Int=52,
)::Matrix{Float64}
    n > 0 || throw(ArgumentError("n must be positive"))
    skip >= 0 || throw(ArgumentError("skip must be non-negative"))
    skip + n <= (Int(1) << bits) ||
        throw(ArgumentError("requested sequence exceeds selected bit depth"))

    directions = _sobol_directions(d, bits)
    state = zeros(UInt64, d)

    # Advance from sequence index zero to `skip`.
    @inbounds for index in 1:skip
        column = trailing_zeros(index) + 1
        for dim in 1:d
            state[dim] = xor(state[dim], directions[dim, column])
        end
    end

    scale = exp2(-64)
    design = Matrix{Float64}(undef, n, d)
    @inbounds for row in 1:n
        for dim in 1:d
            design[row, dim] = Float64(state[dim]) * scale
        end

        global_index = skip + row
        row == n && continue
        column = trailing_zeros(global_index) + 1
        for dim in 1:d
            state[dim] = xor(state[dim], directions[dim, column])
        end
    end
    return design
end

function _splitmix64(value::UInt64)
    value += 0x9e3779b97f4a7c15
    value = (value ⊻ (value >> 30)) * 0xbf58476d1ce4e5b9
    value = (value ⊻ (value >> 27)) * 0x94d049bb133111eb
    return value ⊻ (value >> 31)
end

function _scramble_masks(seed::UInt64, dim::Int, bits::Int)
    state = seed ⊻ (UInt64(dim) * 0xd2b74407b1ce6e93)
    masks = Vector{UInt64}(undef, bits)
    @inbounds for bit in 1:bits
        state = _splitmix64(state)
        diagonal = UInt64(1) << (64 - bit)
        prefix = bit == 1 ? UInt64(0) :
            typemax(UInt64) << (65 - bit)
        masks[bit] = diagonal | (state & prefix)
    end
    state = _splitmix64(state)
    shift_mask = typemax(UInt64) << (64 - bits)
    return masks, state & shift_mask
end

function _linear_scramble(
    value::UInt64,
    masks::Vector{UInt64},
    shift::UInt64,
)
    result = shift
    @inbounds for bit in eachindex(masks)
        isodd(count_ones(value & masks[bit])) &&
            (result = xor(result, UInt64(1) << (64 - bit)))
    end
    return result
end

"""
    scrambled_sobol(n, d; seed=42, skip=0, bits=52)

Generate a reproducible randomized Sobol design using an invertible binary
linear matrix scramble and a digital shift. Calling the function later with
the same seed and a larger `n`, or with the corresponding `skip`, preserves
all points already generated.
"""
function scrambled_sobol(
    n::Int,
    d::Int;
    seed::Int=42,
    skip::Int=0,
    bits::Int=52,
)::Matrix{Float64}
    seed >= 0 || throw(ArgumentError("seed must be non-negative"))
    raw = sobol_sequence(n, d; skip, bits)
    directions = _sobol_directions(d, bits)

    # Reconstruct the exact binary states rather than scrambling rounded
    # Float64 values.
    states = zeros(UInt64, d)
    @inbounds for index in 1:skip
        column = trailing_zeros(index) + 1
        for dim in 1:d
            states[dim] = xor(states[dim], directions[dim, column])
        end
    end

    scale = exp2(-64)
    design = similar(raw)
    @inbounds for dim in 1:d
        masks, shift = _scramble_masks(UInt64(seed), dim, bits)
        state = states[dim]
        for row in 1:n
            design[row, dim] =
                Float64(_linear_scramble(state, masks, shift)) * scale
            global_index = skip + row
            row == n && continue
            column = trailing_zeros(global_index) + 1
            state = xor(state, directions[dim, column])
        end
    end
    return design
end

_lerp(lo::Real, hi::Real, u::Real) = Float64(lo + u * (hi - lo))

function _log_lerp(lo::Real, hi::Real, u::Real)
    lo > 0 || throw(ArgumentError("logarithmic lower bound must be positive"))
    hi >= lo || throw(ArgumentError("invalid logarithmic bounds"))
    return exp(_lerp(log(lo), log(hi), u))
end

# Quantile della normale standard (Acklam, errore relativo < 1.2e-9): basta
# per la forma delle distanze tra fermate, senza dipendenze in più.
function _norminv(p::Float64)
    0.0 < p < 1.0 || throw(ArgumentError("p must be in (0, 1)"))
    a = (-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00)
    b = (-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
         6.680131188771972e+01, -1.328068155288572e+01)
    c = (-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00)
    d = (7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
         3.754408661907416e+00)
    plow = 0.02425
    if p < plow
        q = sqrt(-2 * log(p))
        return (((((c[1]*q + c[2])*q + c[3])*q + c[4])*q + c[5])*q + c[6]) /
               ((((d[1]*q + d[2])*q + d[3])*q + d[4])*q + 1)
    elseif p > 1 - plow
        q = sqrt(-2 * log(1 - p))
        return -(((((c[1]*q + c[2])*q + c[3])*q + c[4])*q + c[5])*q + c[6]) /
                ((((d[1]*q + d[2])*q + d[3])*q + d[4])*q + 1)
    end
    q = p - 0.5
    r = q * q
    return (((((a[1]*r + a[2])*r + a[3])*r + a[4])*r + a[5])*r + a[6]) * q /
           (((((b[1]*r + b[2])*r + b[3])*r + b[4])*r + b[5])*r + 1)
end

# Forma delle distanze tra fermate (non mescolata): quantili di una
# lognormale di parametro σ, a media 0 e deviazione 1. Asimmetrica (pochi
# intervalli lunghi, molti brevi), così CV alti restano compatibili con la
# distanza minima. Uguale a standardized_lognormal del MATLAB.
function _lognormal_shape(n::Int, σ::Float64)
    (n < 2 || σ <= 0) && return zeros(Float64, n)
    q = [exp(σ * _norminv((i - 0.5) / n)) for i in 1:n]
    z = q .- mean(q)
    return z ./ std(z)
end

_negative_extent(n::Int, σ::Float64) = max(0.0, -minimum(_lognormal_shape(n, σ)))

# Parametro della forma: quello della lognormale con CV = cv; se così la
# distanza minima non è rispettata (cv * estensione negativa > room), forma
# più asimmetrica fino a σ = 8 (oltre, il CV viene ridotto). Come
# lognormal_sigma del MATLAB.
function _lognormal_sigma(n::Int, cv::Float64, room::Float64)
    (n < 2 || cv <= 0) && return 0.0
    σ = sqrt(log1p(cv^2))
    cv * _negative_extent(n, σ) <= room && return σ
    lo, hi = σ, 8.0
    cv * _negative_extent(n, hi) > room && return hi
    for _ in 1:60
        mid = (lo + hi) / 2
        cv * _negative_extent(n, mid) <= room ? (hi = mid) : (lo = mid)
    end
    return hi
end

# CV massimo delle distanze tra fermate compatibile con la distanza minima,
# per k intervalli di lunghezza media mean_gap: con la forma più asimmetrica
# (σ = 8) e un margine rispetto al generatore (0,998 contro 0,999).
function _feasible_stop_cv(k::Int, mean_gap::Float64, config::DOEConfig)
    room = 0.998 * max(0.0, 1.0 - config.stop_min_spacing_km / mean_gap)
    return min(config.stop_spacing_cv_max,
               room / max(_negative_extent(k, 8.0), 1e-12))
end

"""
    max_stops(L, config)

Fermate intermedie massime per una linea di `L` km: al più `stop_count_max`
fermate di sola andata e `stop_density_max` per km, capolinea compresi, e la
distanza minima `stop_min_spacing_km`.
"""
max_stops(L::Real, config::DOEConfig=DOEConfig()) = max(0, min(
    config.stop_count_max - 2,
    floor(Int, config.stop_density_max * L) - 2,
    floor(Int, L / config.stop_min_spacing_km) - 1))

"""
    round_trip_features(row; config)

Grandezze della stima della durata sul profilo generato (`generate_vlim`,
`generate_stops`): tempo ai limiti di sola andata [s] e somma delle velocità
limite [m/s] a ogni partenza e arrivo (origine, fermate due volte, capolinea).
"""
function round_trip_features(row; config::DOEConfig=DOEConfig())
    segments = generate_vlim(row; config)
    t_limits = sum((e - s) / v for (s, e, v) in segments) * 3600.0
    v_at(x) = segments[clamp(searchsortedlast(first.(segments), x), 1, length(segments))][3] / 3.6
    stops = generate_stops(row; config)
    sum_v = v_at(0.0) + v_at(row.L_km - 1e-9) + 2.0 * sum(v_at.(stops); init=0.0)
    return (t_limits_s=t_limits, sum_v_ms=sum_v)
end

"""
    estimate_round_trip_h(row; config)

Durata stimata dell'andata e ritorno simulata [h]: due volte il tempo ai limiti
per `duration_alpha`, le soste intermedie (`dwell_s`, andata e ritorno), il
capolinea (`terminus_s`), `duration_kappa_s_per_ms` secondi per m/s a ogni
partenza e arrivo, il tutto per (1 + `duration_margin`).
"""
function estimate_round_trip_h(row; config::DOEConfig=DOEConfig())
    f = round_trip_features(row; config)
    T = 2.0 * config.duration_alpha * f.t_limits_s +
        2.0 * config.dwell_s * row.n_stops + config.terminus_s +
        2.0 * config.duration_kappa_s_per_ms * f.sum_v_ms
    return T * (1.0 + config.duration_margin) / 3600.0
end

function _special_rows(rng::AbstractRNG, n::Int, fraction::Float64)
    count = clamp(round(Int, fraction * n), 0, n)
    count == 0 && return Set{Int}()
    return Set(randperm(rng, n)[1:count])
end

function _rows_from_unit_design(
    design::Matrix{Float64},
    route_ids,
    profile_seeds,
    flat_flags,
    no_stop_flags,
    constant_speed_flags;
    config::DOEConfig,
)
    n = size(design, 1)
    size(design, 2) == 9 ||
        throw(ArgumentError("route DoE requires exactly nine unit factors"))
    all(length(x) == n for x in (
        route_ids,
        profile_seeds,
        flat_flags,
        no_stop_flags,
        constant_speed_flags,
    )) || throw(ArgumentError("row metadata length mismatch"))

    rows = NamedTuple[]

    for i in 1:n
        L_requested = _lerp(config.L_min, config.L_max, design[i, 1])
        row = _row_from_unit(design, i, L_requested, route_ids, profile_seeds,
            flat_flags, no_stop_flags, constant_speed_flags; config)
        # andata e ritorno entro round_trip_max_h: si accorcia L con gli stessi
        # fattori unitari (densità di fermate e cambi, indice, v_max invariati)
        L = L_requested
        T = estimate_round_trip_h(row; config)
        iterations = 0
        while T > config.round_trip_max_h && L > config.L_min
            iterations += 1
            iterations <= 100 || error("route $(route_ids[i]): L non converge")
            L = max(config.L_min, L * min(0.995, config.round_trip_max_h / T))
            row = _row_from_unit(design, i, L, route_ids, profile_seeds,
                flat_flags, no_stop_flags, constant_speed_flags; config)
            T = estimate_round_trip_h(row; config)
        end
        T <= config.round_trip_max_h ||
            error("route $(route_ids[i]): durata stimata $(T) h anche a L minima")
        push!(rows, merge(row, (L_km_requested=L_requested,
            shortened=L < L_requested, round_trip_estimate_h=T)))
    end
    return rows
end

function _row_from_unit(design, i, L, route_ids, profile_seeds, flat_flags,
        no_stop_flags, constant_speed_flags; config::DOEConfig)

        is_flat = flat_flags[i]
        if is_flat
            slope_std = 0.0
            slope_mean = 0.0
            slope_segment_mean = 0.0
        else
            slope_std = _lerp(0.0, config.slope_std_max, design[i, 3])
            # il generatore comprime i profili entro ±slope_abs_limit
            # mantenendo media e deviazione: serve mean² + std² < limit²
            # (con margine; nei limiti attuali non è mai attivo)
            mean_cap = min(
                config.slope_mean_abs_max,
                config.elevation_abs_max_m / L,
                sqrt(max(0.0, (0.95 * config.slope_abs_limit)^2 - slope_std^2)),
            )
            slope_mean = _lerp(-mean_cap, mean_cap, design[i, 2])
            segment_mean_hi = min(config.slope_segment_mean_max_km, L)
            slope_segment_mean = _log_lerp(
                config.slope_segment_mean_min_km,
                segment_mean_hi,
                design[i, 4],
            )
        end

        no_stops = no_stop_flags[i]
        n_max = max_stops(L, config)
        stop_density_requested =
            no_stops || n_max == 0 ? 0.0 : design[i, 5] * n_max / L
        n_stops = no_stops ? 0 :
            min(round(Int, stop_density_requested * L), n_max)
        stop_density = n_stops / L

        if n_stops <= 1
            stop_cv = 0.0
        else
            cv_hi = _feasible_stop_cv(
                n_stops + 1,
                L / (n_stops + 1),
                config,
            )
            stop_cv = _lerp(0.0, cv_hi, design[i, 6])
        end

        class_idx = clamp(
            floor(Int, design[i, 7] * length(config.speed_classes)) + 1,
            1,
            length(config.speed_classes),
        )
        v_max = config.speed_classes[class_idx]

        constant_speed = constant_speed_flags[i]
        if constant_speed
            restriction = 0.0
            speed_density_requested = 0.0
            n_speed_segments = 1
        else
            density_lo = 0.501 / L
            speed_density_requested = _lerp(
                density_lo,
                config.speed_change_density_max,
                design[i, 9],
            )
            n_speed_segments = 1 + round(Int, speed_density_requested * L)
            max_segments = max(1, floor(Int, L / config.speed_min_segment_km))
            n_speed_segments = clamp(n_speed_segments, 2, max_segments)

            minimum_restriction =
                config.speed_step_kmh * config.speed_min_segment_km *
                floor(Int, n_speed_segments / 2) /
                (L * (v_max - config.speed_min_kmh))
            restriction_lo =
                min(config.speed_restriction_max, minimum_restriction)
            restriction = _lerp(
                restriction_lo,
                config.speed_restriction_max,
                design[i, 8],
            )
        end

        speed_density = (n_speed_segments - 1) / L

        return (
            route_id=route_ids[i],
            profile_seed=UInt32(profile_seeds[i]),
            is_flat=is_flat,
            no_stops=no_stops,
            constant_speed=constant_speed,
            L_km=L,
            slope_mean=slope_mean,
            slope_std=slope_std,
            slope_segment_length_mean_km=slope_segment_mean,
            stop_density_requested=stop_density_requested,
            stop_density=stop_density,
            stop_spacing_cv=stop_cv,
            n_stops=n_stops,
            v_max_kmh=v_max,
            speed_restriction_index=restriction,
            speed_change_density_requested=speed_density_requested,
            speed_change_density=speed_density,
            n_vlim_segments=n_speed_segments,
        )
end

"""
    sample_doe(n; seed=42, config=DOEConfig())

Create a constrained nine-factor route DoE. The returned vector contains both
the requested continuous factors and their realizable discrete counterparts
(`n_stops`, number of speed-limit segments, effective densities).
"""
function sample_doe(n::Int; seed::Int=42, config::DOEConfig=DOEConfig())
    rng = MersenneTwister(seed)
    lhs = latin_hypercube(rng, n, 9)

    flat_rows = _special_rows(rng, n, config.flat_fraction)
    no_stop_rows = _special_rows(rng, n, config.no_stops_fraction)
    constant_speed_rows = _special_rows(rng, n, config.constant_speed_fraction)

    return _rows_from_unit_design(
        lhs,
        collect(1:n),
        rand(rng, UInt32, n),
        [i in flat_rows for i in 1:n],
        [i in no_stop_rows for i in 1:n],
        [i in constant_speed_rows for i in 1:n];
        config,
    )
end

function _stable_uniform(seed::Int, index::Int, salt::UInt64)
    mixed = _splitmix64(
        UInt64(seed) ⊻
        (UInt64(index) * 0x9e3779b97f4a7c15) ⊻
        salt,
    )
    return Float64(mixed >> 11) * exp2(-53)
end

function _stable_profile_seed(seed::Int, index::Int)
    mixed = _splitmix64(
        UInt64(seed) ⊻
        (UInt64(index) * 0xd2b74407b1ce6e93) ⊻
        0xa0761d6478bd642f,
    )
    return UInt32(mixed & 0xffffffff)
end

"""
    sample_doe_sobol(n; start_index=1, seed=42, config=DOEConfig())

Create an extensible constrained route DoE from a scrambled Sobol sequence.
`start_index` is one-based and identifies the rows globally: generating
`1:256` and later `257:512` with the same seed is exactly equivalent to
generating `1:512` in one call.
"""
function sample_doe_sobol(
    n::Int;
    start_index::Int=1,
    seed::Int=42,
    config::DOEConfig=DOEConfig(),
)
    n > 0 || throw(ArgumentError("n must be positive"))
    start_index > 0 || throw(ArgumentError("start_index must be positive"))
    seed >= 0 || throw(ArgumentError("seed must be non-negative"))

    indices = collect(start_index:start_index+n-1)
    design = scrambled_sobol(n, 9; seed, skip=start_index - 1)
    profile_seeds = [_stable_profile_seed(seed, i) for i in indices]
    flat_flags = [
        _stable_uniform(seed, i, 0x243f6a8885a308d3) <
        config.flat_fraction for i in indices
    ]
    no_stop_flags = [
        _stable_uniform(seed, i, 0x13198a2e03707344) <
        config.no_stops_fraction for i in indices
    ]
    constant_speed_flags = [
        _stable_uniform(seed, i, 0xa4093822299f31d0) <
        config.constant_speed_fraction for i in indices
    ]

    return _rows_from_unit_design(
        design,
        indices,
        profile_seeds,
        flat_flags,
        no_stop_flags,
        constant_speed_flags;
        config,
    )
end

function _component_rng(seed::UInt32, salt::UInt32)
    return MersenneTwister(Int(xor(seed, salt)))
end

"""
    generate_slope(row; config=DOEConfig())

Generate a one-metre, piecewise-constant slope profile with the requested mean
and standard deviation. The fourth DoE factor is the *mean* segment length:
individual segment lengths are random, reproducible and never shorter than
`config.slope_segment_min_km`. Flat scenarios return an all-zero profile.
"""
function generate_slope(row; config::DOEConfig=DOEConfig())::Vector{Float64}
    L_m = round(Int, row.L_km * 1000.0)
    n_points = L_m + 1
    row.is_flat && return zeros(Float64, n_points)

    μ = Float64(row.slope_mean)
    σ = Float64(row.slope_std)
    target_segment_mean =
        Float64(row.slope_segment_length_mean_km)
    target_segment_mean > 0 ||
        throw(ArgumentError(
            "non-flat routes require a positive mean slope-segment length",
        ))

    length_rng = _component_rng(UInt32(row.profile_seed), 0x51a7e101)
    segment_lengths_m = _random_slope_segment_lengths_m(
        length_rng,
        L_m,
        slope_segment_count(L_m, target_segment_mean, σ; config);
        config,
    )
    n_segments = length(segment_lengths_m)

    if σ <= 1e-12
        return fill(μ, n_points)
    end

    for attempt in 0:31
        if attempt > 0 && attempt % 4 == 0
            # few segments (short routes) with a high std may make the
            # bounds unreachable: draw new segment lengths every 4 attempts
            segment_lengths_m = _random_slope_segment_lengths_m(
                length_rng, L_m, n_segments; config,
            )
        end
        rng = _component_rng(
            UInt32(row.profile_seed),
            xor(0x51a7e201, UInt32(attempt)),
        )
        innovations = randn(rng, n_segments)
        z_segments = similar(innovations)
        z_segments[1] = innovations[1]
        @inbounds for i in 2:n_segments
            # A fixed, mild persistence avoids an unnecessary tenth DoE
            # factor while discouraging unrealistically alternating grades.
            z_segments[i] =
                0.35 * z_segments[i-1] +
                sqrt(1.0 - 0.35^2) * innovations[i]
        end
        # Smoothly bound the tails without creating identical adjacent
        # values (hard clipping could accidentally merge two segments).
        z_segments .= 2.5 .* tanh.(z_segments ./ 2.5)

        z = Vector{Float64}(undef, n_points)
        cursor = 1
        for (segment_index, segment_length_m) in
            enumerate(segment_lengths_m)
            segment_end = cursor + segment_length_m - 1
            z[cursor:segment_end] .= z_segments[segment_index]
            cursor = segment_end + 1
        end
        z[end] = z_segments[end]

        z .-= mean(z)
        z_std = std(z)
        z_std > 1e-10 || continue
        z ./= z_std

        p = μ .+ σ .* z
        p = _squash_to_limit(p, μ, σ, config.slope_abs_limit,
            config.slope_squash_iterations)
        bounded =
            minimum(p) >= -config.slope_abs_limit - 1e-9 &&
            maximum(p) <= config.slope_abs_limit + 1e-9
        bounded && return p
    end

    error("Unable to generate a bounded slope profile for route $(row.route_id)")
end

"""
    slope_segment_count(L_m, target_mean_km, σ; config=DOEConfig())

Number of constant-slope segments (same rule as doe_slope_segment_count.m):
round(L / mean length) within 1 and floor(L / minimum length), at least two
when σ > 0 and the route can hold them (short routes, from 5 km), and never a
partition made only of minimum-length segments.
"""
function slope_segment_count(
    L_m::Int,
    target_mean_km::Float64,
    σ::Float64;
    config::DOEConfig=DOEConfig(),
)::Int
    minimum_m = round(Int, 1000.0 * config.slope_segment_min_km)
    maximum_segments = max(1, fld(L_m, minimum_m))
    n_segments = clamp(
        round(Int, L_m / (1000.0 * target_mean_km)),
        1,
        maximum_segments,
    )
    if σ > 1e-12 && n_segments < 2 && maximum_segments >= 2
        n_segments = 2
    end
    # If the route would be partitioned into identical minimum-length
    # segments, use one segment less so that spatial variability remains
    # possible without violating the lower bound.
    if n_segments > 1 && L_m == n_segments * minimum_m
        n_segments -= 1
    end
    return n_segments
end

# Compress values beyond ±limit with limit*tanh(p/limit) and restore the
# requested mean and standard deviation, until the whole profile is within
# the limit (same as squash_to_limit in generate_doe_slope.m). Monotone:
# different segments stay different.
function _squash_to_limit(p::Vector{Float64}, μ::Float64, σ::Float64,
                          limit::Float64, max_iterations::Int)
    x = p
    for _ in 1:max_iterations
        maximum(abs, x) <= limit && return x
        y = limit .* tanh.(x ./ limit)
        y .-= mean(y)
        s = std(y)
        s <= 1e-12 && return x
        x = μ .+ σ .* y ./ s
    end
    return x
end

function _random_slope_segment_lengths_m(
    rng::AbstractRNG,
    L_m::Int,
    n_segments::Int;
    config::DOEConfig,
)::Vector{Int}
    minimum_m = round(Int, 1000.0 * config.slope_segment_min_km)
    minimum_m > 0 || throw(ArgumentError("minimum segment length must be positive"))
    L_m >= minimum_m ||
        throw(ArgumentError("route is shorter than the minimum slope segment"))

    remaining_m = L_m - n_segments * minimum_m
    remaining_m == 0 && return fill(minimum_m, n_segments)

    lognormal_sigma =
        sqrt(log1p(config.slope_segment_length_cv^2))
    weights = exp.(lognormal_sigma .* randn(rng, n_segments))
    exact_extra = remaining_m .* weights ./ sum(weights)
    extra_m = floor.(Int, exact_extra)
    leftover_m = remaining_m - sum(extra_m)

    if leftover_m > 0
        fractional = exact_extra .- extra_m
        order = sortperm(fractional; rev=true)
        extra_m[order[1:leftover_m]] .+= 1
    end

    lengths_m = minimum_m .+ extra_m
    sum(lengths_m) == L_m ||
        error("internal error while allocating slope segments")

    if n_segments > 1 && all(==(lengths_m[1]), lengths_m)
        donor = findfirst(>(minimum_m), lengths_m)
        if donor !== nothing
            receiver = donor == 1 ? 2 : 1
            lengths_m[donor] -= 1
            lengths_m[receiver] += 1
        end
    end
    return lengths_m
end

function _standardized_cosine(rng::AbstractRNG, n::Int)
    phase = 2π * rand(rng)
    z = [cos(2π * (i - 1) / n + phase) for i in 1:n]
    z .-= mean(z)
    s = std(z)
    s > 0 && (z ./= s)
    shuffle!(rng, z)
    return z
end

"""
    generate_stops(row; config=DOEConfig())

Generate exactly `row.n_stops` internal stop positions. Inter-stop distances
include the departure and arrival gaps and match the requested CV whenever it
is feasible under the minimum-spacing constraint.
"""
function generate_stops(row; config::DOEConfig=DOEConfig())::Vector{Float64}
    n_stops = Int(row.n_stops)
    n_stops == 0 && return Float64[]

    k = n_stops + 1
    mean_gap = row.L_km / k
    rng = _component_rng(UInt32(row.profile_seed), 0x570f5001)
    target_cv = Float64(row.stop_spacing_cv)
    room = 0.999 * (1.0 - config.stop_min_spacing_km / mean_gap)
    z = _lognormal_shape(k, _lognormal_sigma(k, target_cv, room))
    target_cv > 0 && shuffle!(rng, z)

    if target_cv > 0
        negative_extent = max(0.0, -minimum(z))
        feasible_cv = negative_extent == 0 ? target_cv :
            0.999 * (1.0 - config.stop_min_spacing_km / mean_gap) /
            negative_extent
        target_cv = min(target_cv, max(0.0, feasible_cv))
    end

    gaps = mean_gap .* (1.0 .+ target_cv .* z)
    gaps .*= row.L_km / sum(gaps)
    minimum(gaps) >= config.stop_min_spacing_km - 1e-8 ||
        error("Minimum stop spacing violated for route $(row.route_id)")

    return cumsum(gaps)[1:n_stops]
end

function _weighted_choice(rng::AbstractRNG, weights::Vector{Float64})::Int
    total = sum(weights)
    total > 0 || return rand(rng, eachindex(weights))
    threshold = rand(rng) * total
    cumulative = 0.0
    @inbounds for i in eachindex(weights)
        cumulative += weights[i]
        cumulative >= threshold && return i
    end
    return lastindex(weights)
end

function _speed_sequence(
    rng::AbstractRNG,
    lengths::Vector{Float64},
    classes::Vector{Float64},
    target_mean::Float64,
)
    m = length(lengths)
    vmax = maximum(classes)
    total_length = sum(lengths)
    temperatures = (5.0, 10.0, 20.0, 40.0)

    lower_class = classes[max(1, length(classes) - 1)]
    best = [isodd(i) ? vmax : lower_class for i in 1:m]
    best_error = abs(sum(lengths .* best) / total_length - target_mean)

    for trial in 1:1600
        temperature = temperatures[mod1(trial, length(temperatures))]
        candidate = Vector{Float64}(undef, m)

        for i in 1:m
            weights = [
                (i > 1 && c == candidate[i-1]) ? 0.0 :
                exp(-abs(c - target_mean) / temperature)
                for c in classes
            ]
            candidate[i] = classes[_weighted_choice(rng, weights)]
        end

        if !any(==(vmax), candidate)
            candidate[argmin(lengths)] = vmax
        end

        any(candidate[i] == candidate[i+1] for i in 1:m-1) && continue
        error = abs(sum(lengths .* candidate) / total_length - target_mean)
        if error < best_error
            best = copy(candidate)
            best_error = error
        end
    end

    # Local discrete optimization while preserving changes and at least one
    # segment at vmax.
    for _ in 1:200
        current_mean = sum(lengths .* best) / total_length
        current_error = abs(current_mean - target_mean)
        move = nothing
        move_error = current_error
        n_vmax = count(==(vmax), best)

        for i in 1:m
            for c in classes
                c == best[i] && continue
                i > 1 && c == best[i-1] && continue
                i < m && c == best[i+1] && continue
                best[i] == vmax && c != vmax && n_vmax == 1 && continue

                new_mean =
                    current_mean + lengths[i] * (c - best[i]) / total_length
                new_error = abs(new_mean - target_mean)
                if new_error + 1e-12 < move_error
                    move = (i, c)
                    move_error = new_error
                end
            end
        end

        move === nothing && break
        best[move[1]] = move[2]
    end

    return best
end

# If the length-weighted mean stays more than `tolerance` from the target
# (high restriction with few segments), shorten by the same factor the
# segments on the wrong side of the target and lengthen the others, never
# below `minimum_km` (same as adjust_lengths_for_mean in the MATLAB).
function _adjust_lengths_for_mean(lengths::Vector{Float64},
        speeds::Vector{Float64}, target::Float64, minimum_km::Float64,
        tolerance::Float64)
    total = sum(lengths)
    current = sum(lengths .* speeds) / total
    abs(current - target) <= tolerance && return lengths
    side = current > target ? speeds .> target : speeds .< target
    (all(side) || !any(side)) && return lengths
    l_side = sum(lengths[side]); l_other = sum(lengths[.!side])
    s_side = sum(lengths[side] .* speeds[side])
    s_other = sum(lengths[.!side] .* speeds[.!side])
    mean_at_1 = (s_side + s_other) / total
    mean_at_0 = s_other * (1 + l_side / l_other) / total
    a = (target - mean_at_0) / (mean_at_1 - mean_at_0)
    a = min(1.0, max(a, minimum_km / minimum(lengths[side])))
    out = copy(lengths)
    out[side] .*= a
    out[.!side] .*= 1 + (1 - a) * l_side / l_other
    return out
end

"""
    generate_vlim(row; config=DOEConfig())

Generate positive-length, adjacent speed-limit segments. The maximum speed is
represented exactly and the length-weighted mean is optimized toward the
restriction-index target.
"""
function generate_vlim(row; config::DOEConfig=DOEConfig())
    m = Int(row.n_vlim_segments)
    L = Float64(row.L_km)
    vmax = Float64(row.v_max_kmh)

    if m == 1
        return Tuple{Float64,Float64,Float64}[(0.0, L, vmax)]
    end

    rng = _component_rng(UInt32(row.profile_seed), 0x5eed5001)
    mean_length = L / m
    z = _standardized_cosine(rng, m)
    negative_extent = max(0.0, -minimum(z))
    feasible_cv = negative_extent == 0 ? config.speed_segment_cv :
        0.999 * (1.0 - config.speed_min_segment_km / mean_length) /
        negative_extent
    segment_cv = min(config.speed_segment_cv, max(0.0, feasible_cv))
    lengths = mean_length .* (1.0 .+ segment_cv .* z)
    lengths .*= L / sum(lengths)

    minimum(lengths) >= config.speed_min_segment_km - 1e-8 ||
        error("Minimum speed-segment length violated for route $(row.route_id)")

    classes = collect(config.speed_min_kmh:config.speed_step_kmh:vmax)
    last(classes) == vmax || push!(classes, vmax)
    sort!(unique!(classes))

    target_mean = vmax -
        row.speed_restriction_index * (vmax - config.speed_min_kmh)
    speeds = _speed_sequence(rng, lengths, classes, target_mean)
    lengths = _adjust_lengths_for_mean(lengths, speeds, target_mean,
        config.speed_min_segment_km, config.speed_mean_tolerance_kmh)

    segments = Tuple{Float64,Float64,Float64}[]
    start_km = 0.0
    @inbounds for i in 1:m
        end_km = i == m ? L : start_km + lengths[i]
        push!(segments, (start_km, end_km, speeds[i]))
        start_km = end_km
    end
    return segments
end

function generate_route(row; config::DOEConfig=DOEConfig())
    return (
        L=Float64(row.L_km),
        p=generate_slope(row; config),
        vlim_segments=generate_vlim(row; config),
        stops=generate_stops(row; config),
    )
end

"""
    estimate_correlation_length(p; dx_km=0.001, stride=10)

Estimate the first `1/e` autocorrelation crossing. The profile is downsampled
before the calculation to keep pilot validation inexpensive.
"""
function estimate_correlation_length(
    p::AbstractVector{<:Real};
    dx_km::Float64=0.001,
    stride::Int=10,
)
    length(p) > 2 || return NaN
    q = Float64.(p[1:stride:end])
    std(q) > 1e-10 || return NaN

    lag_dx = dx_km * stride
    max_lag = min(length(q) - 2, ceil(Int, 5.0 / lag_dx))
    max_lag > 0 || return NaN
    ac = autocor(q, 0:max_lag)
    idx = findfirst(<=(exp(-1)), ac)
    return idx === nothing ? NaN : (idx - 1) * lag_dx
end

function profile_metrics(profile; config::DOEConfig=DOEConfig())
    p = profile.p
    L = Float64(profile.L)
    slope_change_positions_m = findall(!iszero, diff(p))
    slope_segment_bounds_m = vcat(
        0,
        slope_change_positions_m,
        length(p) - 1,
    )
    slope_segment_lengths_km = diff(slope_segment_bounds_m) ./ 1000.0

    stops = Float64.(profile.stops)
    gaps = diff(vcat(0.0, stops, L))
    stop_cv = length(gaps) > 1 ? std(gaps) / mean(gaps) : 0.0

    segments = profile.vlim_segments
    lengths = Float64[s[2] - s[1] for s in segments]
    speeds = Float64[s[3] for s in segments]
    vmean = sum(lengths .* speeds) / L
    vmax = maximum(speeds)
    restriction = (vmax - vmean) / (vmax - config.speed_min_kmh)

    return (
        L_actual_km=(length(p) - 1) / 1000.0,
        slope_mean_actual=mean(p),
        slope_std_actual=std(p),
        slope_corr_actual_km=estimate_correlation_length(p),
        slope_min_actual=minimum(p),
        slope_max_actual=maximum(p),
        n_slope_segments_actual=length(slope_segment_lengths_km),
        slope_segment_length_mean_actual_km=
            mean(slope_segment_lengths_km),
        slope_segment_length_std_actual_km=
            length(slope_segment_lengths_km) > 1 ?
            std(slope_segment_lengths_km) : 0.0,
        slope_segment_length_min_actual_km=
            minimum(slope_segment_lengths_km),
        slope_segment_length_max_actual_km=
            maximum(slope_segment_lengths_km),
        n_stops_actual=length(stops),
        stop_density_actual=length(stops) / L,
        stop_spacing_cv_actual=stop_cv,
        stop_min_spacing_actual=minimum(gaps),
        v_max_actual_kmh=vmax,
        v_mean_actual_kmh=vmean,
        speed_restriction_actual=restriction,
        n_vlim_segments_actual=length(segments),
        speed_change_density_actual=(length(segments) - 1) / L,
        speed_min_segment_actual=minimum(lengths),
    )
end

end # module DOEGenerator
