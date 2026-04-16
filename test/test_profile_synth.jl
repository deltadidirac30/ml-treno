using Test
using Random
using Statistics

include(joinpath(@__DIR__, "..", "src", "profile_synth.jl"))

@testset "synthesize_slope" begin
    rng = MersenneTwister(12345)
    L = 5.0
    slope_baseline = 6.0
    p = synthesize_slope(rng, L, slope_baseline)
    
    @test length(p) == Int(L * 1000) + 1
    
    rng2 = MersenneTwister(12345)
    p2 = synthesize_slope(rng2, L, slope_baseline)
    @test p == p2
    
    @test all(-35.0 .<= p .<= 35.0)
end

@testset "synthesize_slope determinism" begin
    L = 50.0
    slope_baseline = 6.0
    seed = 12345
    
    rng1 = MersenneTwister(seed)
    p1 = synthesize_slope(rng1, L, slope_baseline)
    
    rng2 = MersenneTwister(seed)
    p2 = synthesize_slope(rng2, L, slope_baseline)
    
    @test p1 == p2
end

@testset "synthesize_slope small L" begin
    rng = MersenneTwister(42)
    L = 3.0
    slope_baseline = 5.0
    p = synthesize_slope(rng, L, slope_baseline)
    
    @test length(p) == Int(L * 1000) + 1
    @test all(-35.0 .<= p .<= 35.0)
end

@testset "synthesize_vlim" begin
    rng = MersenneTwister(12345)
    L = 50.0
    v_max_baseline = 140.0
    
    vlim = synthesize_vlim(rng, L, v_max_baseline)
    
    @test !isempty(vlim)
    @test vlim[1][1] == 0.0
    @test vlim[end][2] == L
    
    total_len = sum(seg[2] - seg[1] for seg in vlim)
    @test total_len ≈ L
    
    for seg in vlim
        v = seg[3]
        @test v in [50.0, 70.0, 90.0, 110.0, 130.0, 150.0]
        @test 50.0 <= v <= 150.0
    end
end

@testset "synthesize_vlim determinism" begin
    L = 50.0
    v_max_baseline = 120.0
    seed = 12345
    
    rng1 = MersenneTwister(seed)
    vlim1 = synthesize_vlim(rng1, L, v_max_baseline)
    
    rng2 = MersenneTwister(seed)
    vlim2 = synthesize_vlim(rng2, L, v_max_baseline)
    
    @test vlim1 == vlim2
end

@testset "synthesize_vlim with p" begin
    rng = MersenneTwister(12345)
    L = 10.0
    v_max_baseline = 140.0
    
    p = synthesize_slope(MersenneTwister(42), L, 25.0)
    vlim = synthesize_vlim(rng, L, v_max_baseline; p=p)
    
    total_len = sum(seg[2] - seg[1] for seg in vlim)
    @test total_len ≈ L
end

@testset "synthesize_stops zero" begin
    rng = MersenneTwister(12345)
    L = 50.0
    n_stops = 0
    
    stops = synthesize_stops(rng, L, n_stops)
    @test isempty(stops)
end

@testset "synthesize_stops basic" begin
    rng = MersenneTwister(12345)
    L = 50.0
    n_stops = 5
    
    stops = synthesize_stops(rng, L, n_stops)
    
    @test length(stops) <= n_stops
    @test issorted(stops)
    
    if length(stops) > 1
        for i in 2:length(stops)
            @test stops[i] - stops[i-1] >= 1.0
        end
    end
end

@testset "synthesize_stops determinism" begin
    L = 50.0
    n_stops = 10
    seed = 12345
    
    rng1 = MersenneTwister(seed)
    stops1 = synthesize_stops(rng1, L, n_stops)
    
    rng2 = MersenneTwister(seed)
    stops2 = synthesize_stops(rng2, L, n_stops)
    
    @test stops1 == stops2
end

@testset "synthesize_row" begin
    row = (
        seed=UInt32(12345),
        explicit_param="n_stops",
        explicit_value=5.0,
    )
    
    result = synthesize_row(row)
    
    @test haskey(result, :L)
    @test haskey(result, :p)
    @test haskey(result, :vlim_segments)
    @test haskey(result, :stops)
    
    @test result.L >= 30.0 && result.L <= 300.0
    @test length(result.p) == Int(result.L * 1000) + 1
end