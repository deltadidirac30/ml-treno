using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using Statistics
using Random

function generate_dummy_data(n_samples::Int, n_input::Int; seed::Int=42)
    Random.seed!(seed)
    X = randn(Float32, n_input, n_samples)
    Y = Matrix{Float32}(undef, 4, n_samples)
    Y[1:2, :] = randn(Float32, 2, n_samples)
    Y[3:4, :] = Float32.(rand(0:6, 2, n_samples))
    return (X, Y)
end

function normalize_inputs(X_train::Matrix{Float32}, X_new::Matrix{Float32})
    μ = Statistics.mean(X_train, dims=2)
    σ = Statistics.std(X_train, dims=2)
    X_train_norm = (X_train .- μ) ./ (σ .+ Float32(1e-8))
    X_new_norm = (X_new .- μ) ./ (σ .+ Float32(1e-8))
    return (X_train_norm, X_new_norm, μ, σ)
end

function make_batches(X::Matrix{Float32}, Y::Matrix{Float32}, batch_size::Int)
    n_samples = size(X, 2)
    indices = Random.shuffle(1:n_samples)
    n_batches = div(n_samples, batch_size)
    batches = Vector{Tuple{Matrix{Float32}, Matrix{Float32}}}()
    for i in 1:n_batches
        idx = indices[(i-1)*batch_size+1 : i*batch_size]
        push!(batches, (X[:, idx], Y[:, idx]))
    end
    return batches
end