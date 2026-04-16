using DataFrames
using Statistics: mean

function evaluate(model, X_test, Y_test, norm_stats; output_norm=nothing)
    X_n = (X_test .- norm_stats.μ) ./ norm_stats.σ
    Ŷ_raw = model(X_n)

    if output_norm !== nothing
        Ŷ = Ŷ_raw .* output_norm.σ .+ output_norm.μ
    else
        Ŷ = Ŷ_raw
    end

    n_out = size(Ŷ, 1)
    @assert n_out == 4

    outputs = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]
    MSE = Float64[]
    MAE = Float64[]
    R2  = Float64[]
    acc = Union{Missing, Float64}[]

    for k in 1:4
        y_true = Float64.(Y_test[k, :])
        y_pred = Float64.(Ŷ[k, :])
        mse    = mean((y_pred .- y_true).^2)
        mae    = mean(abs.(y_pred .- y_true))
        ss_res = sum((y_true .- y_pred).^2)
        ss_tot = sum((y_true .- mean(y_true)).^2)
        r2     = ss_tot < 1e-10 ? 0.0 : 1.0 - ss_res / ss_tot
        push!(MSE, mse)
        push!(MAE, mae)
        push!(R2,  r2)
        if k ∈ (3, 4)
            # Round to nearest non-negative integer; no upper clamp (range depends on data)
            y_int = round.(Int, max.(0.0, y_pred))
            push!(acc, mean(y_int .== round.(Int, y_true)))
        else
            push!(acc, missing)
        end
    end

    return DataFrame(; output=outputs, MSE, MAE, R2, accuracy=acc)
end
