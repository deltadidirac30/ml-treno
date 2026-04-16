using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

using CSV, DataFrames, Random, Statistics
using BSON
using Statistics: mean, std

using Flux, Zygote, Optimisers

include(joinpath(@__DIR__, "..", "src", "MLTrenoSurrogate.jl"))
using .MLTrenoSurrogate:
    build_model, zscore_fit, zscore_apply, loss_fn, train!

const FEATURE_COLS = [
    "L_km", "P_nom_fc", "C_batt",
    "slope_int_pos", "slope_int_neg", "slope_int_abs", "slope_rms",
    "slope_mean_pos", "slope_std_pos", "slope_mean_neg", "slope_std_neg",
    "slope_max", "slope_min", "slope_std_all", "slope_std_sq_pos",
    "slope_L_up_frac", "slope_sign_changes_per_km", "slope_max_run_up_km",
    "vlim_mean", "vlim_std", "vlim_max", "vlim_min",
    "vlim_sum_abs_dv2", "vlim_changes_per_km", "vlim_sum_dv_pos_sq", "vlim_sum_dv_neg_sq",
    "vlim_frac_low", "vlim_frac_mid", "vlim_frac_high",
    "stops_density", "stops_spacing_mean", "stops_spacing_std",
    "stops_sum_v2", "stops_mean_v", "stops_std_v", "stops_sum_v2_segweighted",
    "stops_mean_p", "stops_sum_abs_p", "stops_frac_on_slope",
    "cross_Lup_v", "cross_Ldn_v", "cross_brake_energy_signed", "cross_thermal_fatigue",
    "cross_stops_v_seg", "cross_abs_p_highv", "cross_up_lowv",
    "cross_mean_p_v", "cross_int_p_v", "cross_var_p_v",
    "bin_p_1", "bin_p_2", "bin_p_3", "bin_p_4", "bin_p_5",
    "bin_p_6", "bin_p_7", "bin_p_8", "bin_p_9", "bin_p_10",
    "bin_v_1", "bin_v_2", "bin_v_3", "bin_v_4", "bin_v_5",
    "bin_v_6", "bin_v_7", "bin_v_8", "bin_v_9", "bin_v_10",
]

const OUTPUT_COLS = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]

function load_data(path)
    df = CSV.read(path, DataFrame)
    X = permutedims(Matrix{Float32}(df[:, FEATURE_COLS]))
    Y = permutedims(Matrix{Float32}(df[:, OUTPUT_COLS]))
    return X, Y
end

function main()
    results_dir = joinpath(@__DIR__, "..", "results")
    data_dir = joinpath(@__DIR__, "..", "data_generated")
    mkpath(results_dir)

    println("Loading train.csv …")
    X_all, Y_all = load_data(joinpath(data_dir, "train.csv"))
    @info "Full train set: $(size(X_all,2)) samples, $(size(X_all,1)) features"

    Random.seed!(42)
    n = size(X_all, 2)
    perm = randperm(n)
    split = floor(Int, 0.8 * n)
    train_idx = perm[1:split]
    val_idx = perm[split+1:end]

    X_tr, Y_tr = X_all[:, train_idx], Y_all[:, train_idx]
    X_va, Y_va = X_all[:, val_idx], Y_all[:, val_idx]

    @info "Train: $(size(X_tr,2)) | Val: $(size(X_va,2))"

    println("Fitting z-score normalization …")
    μ, σ = zscore_fit(X_tr)
    X_tr_n = zscore_apply(X_tr, μ, σ)
    X_va_n = zscore_apply(X_va, μ, σ)

    norm_stats = (μ=μ, σ=σ)
    BSON.@save joinpath(results_dir, "norm_stats.bson") norm_stats
    @info "norm_stats.bson saved"

    println("Normalizing outputs (per-channel z-score) for training stability …")
    Y_μ = vec(mean(Y_tr, dims=2))
    Y_σ = vec(std(Y_tr, dims=2; corrected=true))
    Y_σ = max.(Y_σ, Float32(1e-8))
    Y_tr_n = (Y_tr .- Y_μ) ./ Y_σ
    Y_va_n = (Y_va .- Y_μ) ./ Y_σ
    output_norm = (μ=Y_μ, σ=Y_σ)
    BSON.@save joinpath(results_dir, "output_norm.bson") output_norm
    @info "output_norm.bson saved"

    println("Building model: 4-layer Dense 128→64→32→4 …")
    model = build_model(69)

    println("Training on normalized outputs …")
    log, best_model = train!(model, X_tr_n, Y_tr_n, X_va_n, Y_va_n;
                             epochs=800, batch_size=128, lr=3e-4, patience=75, weight_decay=1e-4)

    # Save best-validation model (not final state)
    model_path = joinpath(results_dir, "model.bson")
    BSON.@save model_path best_model
    @info "model.bson saved (best-val checkpoint) → $model_path"

    log_df = DataFrame(log)
    CSV.write(joinpath(results_dir, "training_log.csv"), log_df)
    @info "training_log.csv saved"

    final_val = log[end].val_loss
    @info "Training complete. Final val_loss: $(round(final_val; digits=5))"
    println("Done. All artifacts in results/")
end

main()
