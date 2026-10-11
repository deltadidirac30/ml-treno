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
        @test abs(row.slope_mean) + 3 * row.slope_std <=
              config.slope_abs_limit + 1e-8
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
        @test abs(row.slope_mean) + 3 * row.slope_std <=
              config.slope_abs_limit + 1e-8
        @test row.n_stops <=
              floor(Int, row.L_km / config.stop_min_spacing_km) - 1
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
            @test isapprox(
                mean(segment_lengths_km),
                row.slope_segment_length_mean_km;
                rtol=0.15,
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
    end
end
