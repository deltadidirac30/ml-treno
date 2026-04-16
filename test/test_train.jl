using Test
using Random
using Flux
using Zygote

include(joinpath(@__DIR__, "..", "src", "model.jl"))
include(joinpath(@__DIR__, "..", "src", "train.jl"))

@testset "Train smoke tests" begin
    Random.seed!(123)

    @testset "zscore_fit / zscore_apply round-trip" begin
        X = randn(Float32, 69, 50)
        μ, σ = zscore_fit(X)
        X_n = zscore_apply(X, μ, σ)
        @test size(X_n) == size(X)
        @test abs(mean(X_n)) < 0.1f0
        @test abs(std(X_n) - 1.0f0) < 0.1f0
        @test !any(isnan, X_n)
    end

    @testset "loss_fn is finite on real data" begin
        ŷ = randn(Float32, 4, 32)
        y = randn(Float32, 4, 32)
        l = loss_fn(ŷ, y)
        @test isfinite(l)
        @test l >= 0f0
    end

    @testset "loss_fn gradient is non-nothing" begin
        model = build_model(69)
        xb = rand(Float32, 69, 8)
        yb = rand(Float32, 4, 8)
        lval, grads = Zygote.withgradient(model) do m
            loss_fn(m(xb), yb)
        end
        @test isfinite(lval)
        @test grads[1] !== nothing
    end

    @testset "train! runs without NaN for 5 epochs" begin
        Random.seed!(42)
        X_tr = randn(Float32, 69, 100)
        Y_tr = randn(Float32, 4, 100)
        X_va = randn(Float32, 69, 20)
        Y_va = randn(Float32, 4, 20)

        model = build_model(69)
        log, best = train!(model, X_tr, Y_tr, X_va, Y_va; epochs=5, batch_size=16, lr=1e-3, patience=5)

        @test length(log) == 5
        @test best isa MLPSurrogate
        @test all(l -> isfinite(l.train_loss), log)
        @test all(l -> isfinite(l.val_loss), log)
        @test all(l -> l.train_loss >= 0f0, log)
        @test all(l -> l.val_loss >= 0f0, log)
    end

    @testset "loss_fn W weights are correct" begin
        @test W == Float32[1.0, 1.0, 2.0, 2.0]
    end
end
