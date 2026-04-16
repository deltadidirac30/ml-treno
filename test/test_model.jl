using Test
using Flux
using Zygote
using Random

include(joinpath(@__DIR__, "..", "src", "model.jl"))

@testset "Model tests" begin
    @testset "build_model returns correct structure" begin
        model = build_model(69)
        @test model isa MLPSurrogate
        @test length(model.chain.layers) == 4
    end

    @testset "Forward pass on Matrix{Float32}" begin
        model = build_model(69)
        Random.seed!(42)
        X = rand(Float32, 69, 10)
        Y = model(X)
        @test Y isa Matrix{Float32}
        @test size(Y) == (4, 10)
    end

    @testset "Zygote gradient is non-nothing" begin
        model = build_model(69)
        Random.seed!(42)
        X = rand(Float32, 69, 5)
        Y_true = rand(Float32, 4, 5)
        
        loss, grads = Zygote.withgradient(model) do m
            sum((m(X) .- Y_true).^2)
        end
        
        @test grads[1] !== nothing
    end

    @testset "Default n_input=69" begin
        model = build_model()
        @test model isa MLPSurrogate
        X = rand(Float32, 69, 1)
        Y = model(X)
        @test size(Y) == (4, 1)
    end

    @testset "Trainable parameters count" begin
        model = build_model(69)
        params_count = sum(length, Flux.params(model))
        @test params_count > 0
    end
end