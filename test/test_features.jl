using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

using Test
using Statistics

include(joinpath(@__DIR__, "..", "src", "features.jl"))

@testset "test_features.jl" begin

    flat_p = zeros(Float64, 100_001)
    flat_segments = [(0.0, 100.0, 120.0)]
    flat_stops = Float64[]

    @testset "flat p ≡ 0" begin
        out = extract_features(
            p = flat_p,
            vlim_segments = flat_segments,
            stops = flat_stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test length(out) == 69
        @test all(isfinite, out)
        @test out[4] ≈ 0.0
        @test out[5] ≈ 0.0
        @test out[7] ≈ 0.0
        @test out[12] ≈ 0.0
        @test out[13] ≈ 0.0
        @test out[8] ≈ 0.0
        @test out[10] ≈ 0.0
        @test out[30] ≈ 0.0
    end

    @testset "length == 69" begin
        out = extract_features(
            p = flat_p,
            vlim_segments = flat_segments,
            stops = flat_stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test length(out) == 69
    end

    @testset "all finite" begin
        out = extract_features(
            p = flat_p,
            vlim_segments = flat_segments,
            stops = flat_stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test all(isfinite, out)
    end

    @testset "p ≡ 10 positive" begin
        pos_p = fill(10.0, 100_001)
        out = extract_features(
            p = pos_p,
            vlim_segments = flat_segments,
            stops = flat_stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test length(out) == 69
        @test all(isfinite, out)
        @test out[8] ≈ 10.0
        @test out[5] ≈ 0.0
        @test out[6] ≈ 100.0
    end

    @testset "p ≡ -10 negative" begin
        neg_p = fill(-10.0, 100_001)
        out = extract_features(
            p = neg_p,
            vlim_segments = flat_segments,
            stops = flat_stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test length(out) == 69
        @test all(isfinite, out)
        @test out[10] ≈ -10.0
        @test out[4] ≈ 0.0
    end

    @testset "helper: vlim_at" begin
        segs = [(0.0, 30.0, 80.0), (30.0, 70.0, 120.0), (70.0, 100.0, 100.0)]
        @test vlim_at(15.0, segs) == 80.0
        @test vlim_at(30.0, segs) == 120.0
        @test vlim_at(70.0, segs) == 100.0
        @test vlim_at(99.9, segs) == 100.0
    end

    @testset "helper: slope_at" begin
        p_test = Float64[i for i in 1:1001]
        @test slope_at(0.0, p_test) == 1.0
        @test slope_at(0.5, p_test) == 501.0
        @test slope_at(1.0, p_test) == 1001.0
    end

    @testset "helper: max_run_positive" begin
        @test max_run_positive([1.0, 2.0, 3.0, 0.0, 1.0]) == 3
        @test max_run_positive([0.0, 0.0, 5.0]) == 1
        @test max_run_positive([0.0, 0.0]) == 0
        @test max_run_positive(Float64[]) == 0
    end

    @testset "helper: n_sign_changes" begin
        @test n_sign_changes([1.0, 2.0, -1.0, -2.0, 3.0]) == 2
        @test n_sign_changes([1.0, 1.0, 1.0]) == 0
        @test n_sign_changes(Float64[]) == 0
        @test n_sign_changes([1.0]) == 0
    end

    @testset "helper: _count" begin
        @test _count(x -> x > 0, [1.0, -2.0, 3.0]) == 2
        @test _count(x -> x > 5, Float64[]) == 0
        @test _count(x -> x > 0, [0.0, 0.0]) == 0
    end

    @testset "helper: bin_means" begin
        v = Float64[1:10...]
        result = bin_means(v, 5)
        @test length(result) == 5
        @test result[1] ≈ 1.5
        @test result[5] ≈ 9.5
        @test all(isfinite, result)
    end

    @testset "edge: no stops" begin
        out = extract_features(
            p = flat_p,
            vlim_segments = flat_segments,
            stops = Float64[],
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test all(isfinite, out)
        @test out[30] ≈ 0.0
        @test out[31] ≈ 100.0
        @test out[32] ≈ 0.0
    end

    @testset "edge: single stop" begin
        out = extract_features(
            p = flat_p,
            vlim_segments = flat_segments,
            stops = [50.0],
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test all(isfinite, out)
        @test out[30] ≈ 0.01
    end

    @testset "multiple vlim segments" begin
        segs = [(0.0, 25.0, 60.0), (25.0, 60.0, 100.0), (60.0, 100.0, 160.0)]
        out = extract_features(
            p = flat_p,
            vlim_segments = segs,
            stops = Float64[],
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test all(isfinite, out)
        @test out[22] ≈ 160.0
        @test out[23] ≈ 60.0
    end

    @testset "cross features with stops" begin
        p_test = zeros(Float64, 100_001)
        segs = [(0.0, 100.0, 120.0)]
        stops = [10.0, 50.0, 90.0]
        out = extract_features(
            p = p_test,
            vlim_segments = segs,
            stops = stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test all(isfinite, out)
        @test out[30] ≈ 0.03
        @test out[33] ≈ 3 * 120.0^2
    end

    @testset "binned features" begin
        p_var = Float64[10.0 * sin(i / 1000) for i in 0:100_000]
        out = extract_features(
            p = p_var,
            vlim_segments = flat_segments,
            stops = Float64[],
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test all(isfinite, out)
        @test length(out) == 69
    end

    @testset "FEATURE_NAMES length" begin
        @test length(FEATURE_NAMES) == 69
    end

    @testset "extract_features returns Vector{Float64}" begin
        out = extract_features(
            p = flat_p,
            vlim_segments = flat_segments,
            stops = flat_stops,
            L = 100.0,
            P_nom_fc = 200.0,
            C_batt = 50.0,
        )
        @test out isa Vector{Float64}
        @test length(out) == 69
    end

end
