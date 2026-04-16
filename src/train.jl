using Flux
using Zygote
using Optimisers
using Statistics

const W = Float32[1.0, 1.0, 2.0, 2.0]

function loss_fn(ŷ::AbstractMatrix{Float32}, y::AbstractMatrix{Float32})
    sum(W .* mean((ŷ .- y).^2, dims=2)) / 4
end

function zscore_fit(X::AbstractMatrix{Float32})
    μ_vec = vec(mean(X, dims=2))
    σ_vec = vec(std(X, dims=2; corrected=true))
    σ_vec = max.(σ_vec, Float32(1e-8))
    return (μ=μ_vec, σ=σ_vec)
end

function zscore_apply(X::AbstractMatrix{Float32}, μ, σ)
    return (X .- μ) ./ σ
end

function train!(model, X_tr::Matrix{Float32}, Y_tr::Matrix{Float32},
                X_val::Matrix{Float32}, Y_val::Matrix{Float32};
                epochs::Int=200, batch_size::Int=32, lr::Float64=1e-3, patience::Int=20, weight_decay::Float64=0.0)
    opt = if weight_decay > 0.0
        Optimisers.AdamW(lr, (0.9, 0.999), weight_decay, 1e-8)
    else
        Optimisers.Adam(lr)
    end
    opt_state     = Optimisers.setup(opt, model)
    best_val      = Inf32
    no_improve    = 0
    log           = Vector{NamedTuple}()
    best_model    = deepcopy(model)   # snapshot of best-validation model

    for epoch in 1:epochs
        idx = shuffle(1:size(X_tr, 2))
        epoch_loss = 0f0
        nb = 0
        for i in 1:batch_size:length(idx)-batch_size+1
            bi = idx[i:i+batch_size-1]
            xb = X_tr[:, bi]
            yb = Y_tr[:, bi]
            lval, grads = Zygote.withgradient(model) do m
                loss_fn(m(xb), yb)
            end
            Optimisers.update!(opt_state, model, grads[1])
            epoch_loss += lval
            nb += 1
        end
        train_l = epoch_loss / nb
        val_l   = loss_fn(model(X_val), Y_val)
        push!(log, (epoch=epoch, train_loss=train_l, val_loss=val_l))

        if val_l < best_val - 1f-5
            best_val   = val_l
            no_improve = 0
            best_model = deepcopy(model)   # checkpoint best weights
        else
            no_improve += 1
            no_improve ≥ patience && (println("Early stop @ epoch $epoch"); break)
        end
        epoch % 10 == 0 && println("Epoch $epoch  train=$(round(train_l; digits=5))  val=$(round(val_l; digits=5))")
    end

    return log, best_model
end
