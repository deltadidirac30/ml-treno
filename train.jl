using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

include("data.jl")
include("model.jl")

using Flux
using Zygote
using Optimisers
using Statistics
using Random

const W_CONTINUOUS = Float32(1.0)
const W_DISCRETE = Float32(2.0)

function surrogate_loss(ŷ::Matrix{Float32}, y::Matrix{Float32})
    loss_cont = mean((ŷ[1:2, :] .- y[1:2, :]).^2)
    loss_disc = mean((ŷ[3:4, :] .- y[3:4, :]).^2)
    return W_CONTINUOUS * loss_cont + W_DISCRETE * loss_disc
end

function train!(
    model::MLPSurrogate,
    X_train::Matrix{Float32},
    Y_train::Matrix{Float32};
    epochs::Int = 100,
    batch_size::Int = 32,
    lr::Float64 = 1e-3,
)
    opt_state = Optimisers.setup(Optimisers.Adam(lr), model)

    for epoch in 1:epochs
        batches = make_batches(X_train, Y_train, batch_size)
        epoch_loss = Float32(0)

        for (xb, yb) in batches
            loss_val, grads = Zygote.withgradient(model) do m
                ŷ = m(xb)
                surrogate_loss(ŷ, yb)
            end

            Optimisers.update!(opt_state, model, grads[1])

            epoch_loss += loss_val
        end

        if epoch % 10 == 0
            avg_loss = epoch_loss / length(batches)
            println("Epoch $epoch/$epochs — avg batch loss: $(round(avg_loss; digits=6))")
        end
    end
end

function predict(model::MLPSurrogate, X::Matrix{Float32}, μ, σ)
    X_norm = (X .- μ) ./ (σ .+ Float32(1e-8))
    raw = model(X_norm)

    y_cont = raw[1:2, :]

    y_disc = clamp.(raw[3:4, :], Float32(0), Float32(6))
    y_disc = round.(Int, y_disc)

    return y_cont, y_disc
end

function main()
    Random.seed!(0)
    n_input = 64
    n_samples = 2000

    X_raw, Y = generate_dummy_data(n_samples, n_input)
    split = Int(floor(0.8 * n_samples))
    X_tr_raw, X_te_raw = X_raw[:, 1:split], X_raw[:, split+1:end]
    Y_tr, Y_te = Y[:, 1:split], Y[:, split+1:end]

    X_tr, X_te, μ, σ = normalize_inputs(X_tr_raw, X_te_raw)

    model = build_model(n_input)
    @assert length(model.chain.layers) == 4

    println("Training on $(size(X_tr, 2)) samples …")
    train!(model, X_tr, Y_tr; epochs=100, batch_size=32, lr=1e-3)

    ŷ_raw = model(X_te)
    test_loss = surrogate_loss(ŷ_raw, Y_te)
    println("Test loss: $(round(test_loss; digits=6))")

    y_cont, y_disc = predict(model, X_te_raw, μ, σ)
    println("Continuous output sample (first 3 cols):\n", y_cont[:, 1:3])
    println("Discrete output sample  (first 3 cols):\n", y_disc[:, 1:3])
end

main()