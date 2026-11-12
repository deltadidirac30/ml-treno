using Test
using Statistics
using Random

include(joinpath(@__DIR__, "..", "src", "doe_generator.jl"))
using .DOEGenerator

@testset "Latin hypercube" begin
    n = 25
    d = 9
    design = latin_hypercube(MersenneTwister(11), n, d)

    @test size(design) == (n, d)
    @test all((0.0 .<= design) .& (design .< 1.0))
    for j in 1:d
        strata = floor.(Int, n .* design[:, j])
        @test sort(strata) == collect(0:n-1)
    end
end

@testset "Progressive scrambled Sobol" begin
    expected = [
        0.00 0.00
        0.50 0.50
        0.75 0.25
        0.25 0.75
    ]
    @test sobol_sequence(4, 2) == expected

    first_block = scrambled_sobol(64, 9; seed=20260723)
    extended = scrambled_sobol(128, 9; seed=20260723)
    second_block = scrambled_sobol(
        64,
        9;
        seed=20260723,
        skip=64,
    )

    @test first_block == extended[1:64, :]
    @test second_block == extended[65:128, :]
    @test first_block != scrambled_sobol(64, 9; seed=20260724)
    @test all((0.0 .<= extended) .& (extended .< 1.0))

    # Every one-dimensional projection of a 2^m-point scrambled block retains
    # one point in each of the 2^m equal strata.
    for j in axes(first_block, 2)
        strata = floor.(Int, 64 .* first_block[:, j])
        @test sort(strata) == collect(0:63)
    end

    routes_64 = sample_doe_sobol(64; seed=20260723)
    routes_128 = sample_doe_sobol(128; seed=20260723)
    routes_65_128 = sample_doe_sobol(
        64;
        start_index=65,
        seed=20260723,
    )

    @test routes_64 == routes_128[1:64]
    @test routes_65_128 == routes_128[65:128]
    @test getproperty.(routes_65_128, :route_id) == collect(65:128)

    config = DOEConfig()
    for row in routes_128
        @test config.L_min <= row.L_km <= config.L_max
        @test abs(row.slope_mean * row.L_km) <=
              config.elevation_abs_max_m + 1e-8
        @test row.slope_mean^2 + row.slope_std^2 <=
              config.slope_abs_limit^2
        if row.is_flat
            @test row.slope_segment_length_mean_km == 0
        else
            @test config.slope_segment_mean_min_km <=
                  row.slope_segment_length_mean_km <=
                  config.slope_segment_mean_max_km
        end
        @test row.n_stops <=
              floor(Int, row.L_km / config.stop_min_spacing_km) - 1
        @test row.n_vlim_segments <=
              floor(Int, row.L_km / config.speed_min_segment_km)
    end
end

@testset "Constrained DoE sampling" begin
    config = DOEConfig()
    @test config.elevation_abs_max_m ==
          config.slope_abs_limit * config.L_max
    rows = sample_doe(40; seed=123, config)

    @test length(rows) == 40
    @test count(r -> r.is_flat, rows) == 4
    @test count(r -> r.no_stops, rows) == 4
    @test count(r -> r.constant_speed, rows) == 4

    for row in rows
        @test config.L_min <= row.L_km <= config.L_max
        @test abs(row.slope_mean * row.L_km) <=
              config.elevation_abs_max_m + 1e-8
        @test row.slope_mean^2 + row.slope_std^2 <=
              config.slope_abs_limit^2
        @test row.n_stops <=
              floor(Int, row.L_km / config.stop_min_spacing_km) - 1
        @test row.n_stops <= max_stops(row.L_km, config)
        @test row.speed_restriction_index <= config.speed_restriction_max
        @test row.round_trip_estimate_h <= config.round_trip_max_h
        @test row.n_vlim_segments <=
              floor(Int, row.L_km / config.speed_min_segment_km)
        @test row.v_max_kmh in config.speed_classes

        if row.is_flat
            @test row.slope_mean == 0
            @test row.slope_std == 0
            @test row.slope_segment_length_mean_km == 0
        else
            @test config.slope_segment_mean_min_km <=
                  row.slope_segment_length_mean_km <=
                  config.slope_segment_mean_max_km
        end
        if row.no_stops
            @test row.n_stops == 0
        end
        if row.constant_speed
            @test row.n_vlim_segments == 1
            @test row.speed_restriction_index == 0
        else
            @test row.n_vlim_segments >= 2
        end
    end
end

@testset "Profile generation and reproducibility" begin
    config = DOEConfig()
    rows = sample_doe(12; seed=77, config)

    for row in rows
        profile_a = generate_route(row; config)
        profile_b = generate_route(row; config)

        @test profile_a == profile_b
        @test length(profile_a.p) == round(Int, row.L_km * 1000) + 1
        @test minimum(profile_a.p) >= -config.slope_abs_limit - 1e-8
        @test maximum(profile_a.p) <= config.slope_abs_limit + 1e-8
        @test isapprox(mean(profile_a.p), row.slope_mean; atol=1e-10)

        if row.is_flat
            @test all(iszero, profile_a.p)
        else
            @test isapprox(std(profile_a.p), row.slope_std; atol=1e-10)

            change_positions_m = findall(!iszero, diff(profile_a.p))
            segment_lengths_km =
                diff(vcat(0, change_positions_m, length(profile_a.p) - 1)) ./
                1000.0
            @test minimum(segment_lengths_km) >=
                  config.slope_segment_min_km - 1e-8
            @test length(segment_lengths_km) >= 2
            @test !all(==(segment_lengths_km[1]), segment_lengths_km)
            @test length(segment_lengths_km) == slope_segment_count(
                round(Int, row.L_km * 1000),
                row.slope_segment_length_mean_km,
                row.slope_std;
                config,
            )
        end

        stops_with_ends = vcat(0.0, profile_a.stops, row.L_km)
        @test issorted(stops_with_ends)
        @test length(profile_a.stops) == row.n_stops
        @test minimum(diff(stops_with_ends)) >=
              config.stop_min_spacing_km - 1e-8

        segments = profile_a.vlim_segments
        @test length(segments) == row.n_vlim_segments
        @test segments[1][1] == 0.0
        @test segments[end][2] == row.L_km
        @test all(s -> s[2] > s[1], segments)
        @test all(s -> s[2] - s[1] >=
                       config.speed_min_segment_km - 1e-8, segments)
        @test maximum(s[3] for s in segments) == row.v_max_kmh
        @test all(segments[i][3] != segments[i+1][3]
                  for i in 1:length(segments)-1)
        @test all(s -> s[3] >= config.speed_min_kmh &&
                       mod(s[3], config.speed_step_kmh) == 0, segments)
        vmean = sum((s[2] - s[1]) * s[3] for s in segments) / row.L_km
        @test abs(vmean - (row.v_max_kmh - row.speed_restriction_index *
                  (row.v_max_kmh - config.speed_min_kmh))) <=
              config.speed_mean_tolerance_kmh + 1e-9

        gaps = diff(stops_with_ends)
        if row.n_stops >= 2 && row.stop_spacing_cv > 0
            @test isapprox(std(gaps) / mean(gaps), row.stop_spacing_cv;
                           rtol=1e-6)
        end
    end
end

@testset "Extreme routes of the extended DoE" begin
    config = DOEConfig()
    base = (route_id=1, profile_seed=UInt32(12345), is_flat=false,
            no_stops=false, constant_speed=false, L_km=60.0,
            slope_mean=0.0, slope_std=8.0,
            slope_segment_length_mean_km=1.5, stop_spacing_cv=0.4,
            n_stops=10, v_max_kmh=130.0, speed_restriction_index=0.3,
            n_vlim_segments=6)
    cases = [
        merge(base, (L_km=5.0, n_stops=2, stop_spacing_cv=0.5,
                     n_vlim_segments=2, slope_segment_length_mean_km=3.5,
                     v_max_kmh=160.0, speed_restriction_index=1.0)),
        merge(base, (L_km=300.0, n_stops=150, stop_spacing_cv=1.0,
                     n_vlim_segments=76, slope_mean=20.0, slope_std=20.0,
                     v_max_kmh=60.0, speed_restriction_index=1.0)),
        merge(base, (L_km=120.0, slope_mean=-20.0, slope_std=20.0,
                     slope_segment_length_mean_km=0.5, n_stops=60,
                     v_max_kmh=155.0, speed_restriction_index=0.95,
                     n_vlim_segments=2)),
    ]
    for row in cases, seed in UInt32[1, 77, 4242]
        r = merge(row, (profile_seed=seed,))
        profile = generate_route(r; config)
        @test maximum(abs, profile.p) <= config.slope_abs_limit + 1e-9
        @test isapprox(mean(profile.p), r.slope_mean; atol=1e-9)
        @test isapprox(std(profile.p), r.slope_std; rtol=1e-9)
        stops = vcat(0.0, profile.stops, r.L_km)
        @test minimum(diff(stops)) >= config.stop_min_spacing_km - 1e-8
        seg = profile.vlim_segments
        @test all(s -> s[2] - s[1] >= config.speed_min_segment_km - 1e-8, seg)
        vmean = sum((s[2] - s[1]) * s[3] for s in seg) / r.L_km
        @test abs(vmean - (r.v_max_kmh - r.speed_restriction_index *
                  (r.v_max_kmh - config.speed_min_kmh))) <= 5 + 1e-9
    end
end

@testset "Revisione dell'11/11/2026: fermate, indice, andata e ritorno entro 12 h" begin
    config = DOEConfig()
    # al più 30 fermate di sola andata e 0,6 per km, capolinea compresi; distanza minima 0,2 km
    @test max_stops(5.0, config) == 1
    @test max_stops(20.0, config) == 10
    @test max_stops(50.0, config) == 28
    @test max_stops(300.0, config) == 28
    @test max_stops(4.9, DOEConfig(stop_density_max = 10.0)) == floor(Int, 4.9 / 0.2) - 1

    rows = sample_doe_sobol(2048; seed=20261110, config)
    @test all(r -> r.n_stops <= max_stops(r.L_km, config), rows)
    @test all(r -> r.n_stops + 2 <= config.stop_count_max, rows)
    @test all(r -> r.n_stops == 0 || r.n_stops + 2 <= floor(Int, config.stop_density_max * r.L_km), rows)
    @test all(r -> r.speed_restriction_index <= config.speed_restriction_max, rows)
    # durata stimata entro 12 h; le tratte accorciate hanno L più corta di quella campionata
    @test all(r -> r.round_trip_estimate_h <= config.round_trip_max_h, rows)
    @test all(r -> r.round_trip_estimate_h ≈ estimate_round_trip_h(r; config), rows)
    @test all(r -> r.shortened == (r.L_km < r.L_km_requested), rows)
    @test all(r -> r.shortened || r.L_km == r.L_km_requested, rows)
    quota = count(r -> r.shortened, rows) / length(rows)
    @test 0.01 <= quota <= 0.06
    # fermate uniformi tra 0 e il massimo, non ammassate sul massimo
    x = [r.n_stops / max_stops(r.L_km, config) for r in rows if !r.no_stops && max_stops(r.L_km, config) >= 20]
    @test 0.45 <= sum(x) / length(x) <= 0.55
    @test count(==(1.0), x) / length(x) < 0.1
    # senza accorciamento (durata massima infinita) le righe non accorciate sono le stesse
    libere = sample_doe_sobol(2048; seed=20261110, config=DOEConfig(round_trip_max_h=Inf))
    @test all(rows[i].L_km == libere[i].L_km && rows[i].n_stops == libere[i].n_stops
              for i in eachindex(rows) if !rows[i].shortened)
    # stima: soste e capolinea entrano linearmente
    r = rows[findfirst(r -> r.n_stops > 0, rows)]
    @test estimate_round_trip_h(merge(r, (n_stops = r.n_stops,)); config=DOEConfig(duration_margin=0.0)) * 3600 >=
          config.terminus_s + 2 * config.dwell_s * r.n_stops
end
