using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

using CSV, DataFrames, Random, Statistics
using BSON
using Plots

using Flux

include(joinpath(@__DIR__, "..", "src", "MLTrenoSurrogate.jl"))
using .MLTrenoSurrogate: build_model, evaluate

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

function main()
    results_dir = joinpath(@__DIR__, "..", "results")
    data_dir = joinpath(@__DIR__, "..", "data_generated")
    plots_dir = joinpath(results_dir, "plots")
    mkpath(plots_dir)

    println("Loading model.bson …")
    model_data = BSON.load(joinpath(results_dir, "model.bson"))
    model = haskey(model_data, :best_model) ? model_data[:best_model] : model_data[:model]

    println("Loading norm_stats.bson …")
    ns_data = BSON.load(joinpath(results_dir, "norm_stats.bson"))
    norm_stats = ns_data[:norm_stats]

    println("Loading output_norm.bson …")
    on_data = BSON.load(joinpath(results_dir, "output_norm.bson"))
    output_norm = on_data[:output_norm]

    println("Loading test.csv …")
    df_test = CSV.read(joinpath(data_dir, "test.csv"), DataFrame)
    X_test = permutedims(Matrix{Float32}(df_test[:, FEATURE_COLS]))
    Y_test = permutedims(Matrix{Float32}(df_test[:, OUTPUT_COLS]))

    @info "Test set: $(size(X_test,2)) samples"

    println("Computing metrics …")
    metrics_df = evaluate(model, X_test, Y_test, norm_stats; output_norm)
    CSV.write(joinpath(results_dir, "metrics.csv"), metrics_df)
    println(metrics_df)

    X_n = (X_test .- norm_stats.μ) ./ norm_stats.σ
    Ŷ_raw = model(X_n)
    Ŷ = Ŷ_raw .* output_norm.σ .+ output_norm.μ

    output_names = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]

    for (k, name) in enumerate(output_names)
        y_true = Y_test[k, :]
        y_pred = Ŷ[k, :]
        r2_val = metrics_df[k, :R2]

        p1 = scatter(y_true, y_pred;
                     xlabel="Actual $name",
                     ylabel="Predicted $name",
                     title="$name — R²=$(round(r2_val; digits=3))",
                     legend=false, alpha=0.5, ms=3)
        min_v = min(minimum(y_true), minimum(y_pred))
        max_v = max(maximum(y_true), maximum(y_pred))
        plot!(p1, [min_v, max_v], [min_v, max_v]; color=:red, linewidth=1.5, linestyle=:dash)
        savefig(p1, joinpath(plots_dir, "scatter_$name.png"))

        residuals = y_pred .- y_true
        p2 = histogram(residuals; bins=40,
                      xlabel="Residual ($name)",
                      ylabel="Count",
                      title="$name — Residuals",
                      legend=false, alpha=0.7)
        vline!(p2, [0.0]; color=:red, linewidth=1.5)
        savefig(p2, joinpath(plots_dir, "residuals_$name.png"))
    end

    println("Training curve …")
    log_df = CSV.read(joinpath(results_dir, "training_log.csv"), DataFrame)
    p3 = plot(log_df.train_loss; label="Train", xlabel="Epoch", ylabel="Loss",
              title="Training Curve", linewidth=1.5, color=:blue)
    plot!(p3, log_df.val_loss; label="Val", linewidth=1.5, color=:orange)
    savefig(p3, joinpath(plots_dir, "training_curve.png"))

    n_train = size(CSV.read(joinpath(data_dir, "train.csv"), DataFrame), 1)
    train_frac = 0.8
    n_train_actual = floor(Int, train_frac * n_train)

    top5_rows = []
    bot5_rows = []
    for k in 1:4
        err = abs.(Ŷ[k, :] .- Y_test[k, :])
        o = OUTPUT_COLS[k]
        top5_idx = sortperm(err, rev=true)[1:5]
        bot5_idx = sortperm(err)[1:5]
        for idx in top5_idx
            push!(top5_rows, (output=o, row=idx, actual=round(Y_test[k,idx], digits=4),
                               predicted=round(Ŷ[k,idx], digits=4), error=round(err[idx], digits=4)))
        end
        for idx in bot5_idx
            push!(bot5_rows, (output=o, row=idx, actual=round(Y_test[k,idx], digits=4),
                               predicted=round(Ŷ[k,idx], digits=4), error=round(err[idx], digits=4)))
        end
    end

    mkpath(results_dir)
    report_path = joinpath(results_dir, "test_report.md")
    io = open(report_path, "w")
    try
        write(io, "# Test Report — MLTrenoSurrogate\n\n")
        write(io, "## Metrics\n\n")
        header = "| Output | MSE | MAE | R² | Accuracy |\n|--------|-----|-----|----|----------|\n"
        write(io, header)
        for row in eachrow(metrics_df)
            acc_str = ismissing(row.accuracy) ? "—" : string(round(row.accuracy; digits=4))
            write(io, "| $(row.output) | $(round(row.MSE; digits=6)) | $(round(row.MAE; digits=6)) | $(round(row.R2; digits=4)) | $acc_str |\n")
        end
        write(io, "\n## Top-5 / Bottom-5 Predictions by Error\n\n")
        write(io, "### Worst predictions (highest absolute error)\n\n")
        write(io, "| Output | Test Index | Actual | Predicted | Error |\n")
        write(io, "|--------|------------|--------|-----------|-------|\n")
        for r in top5_rows
            write(io, "| $(r.output) | $(r.row) | $(r.actual) | $(r.predicted) | $(r.error) |\n")
        end
        write(io, "\n### Best predictions (lowest absolute error)\n\n")
        write(io, "| Output | Test Index | Actual | Predicted | Error |\n")
        write(io, "|--------|------------|--------|-----------|-------|\n")
        for r in bot5_rows
            write(io, "| $(r.output) | $(r.row) | $(r.actual) | $(r.predicted) | $(r.error) |\n")
        end
        write(io, "\n## Hyperparameters\n\n")
        write(io, "- Architecture: 69 → 128 → 64 → 32 → 4 (ReLU MLP)\n")
        write(io, "- Optimizer: Adam (lr=1e-3)\n")
        write(io, "- Loss weights: [1.0, 1.0, 2.0, 2.0] per output\n")
        write(io, "- Early stopping patience: 20\n")
        write(io, "- Train/Val split: 80/20 (seed=42)\n\n")
        write(io, "## Dataset\n\n")
        write(io, "- Train size: $n_train_actual\n")
        write(io, "- Test size: $(size(X_test,2))\n\n")
        r2_vals = metrics_df.R2
        n_good = count(>(0.7), r2_vals)
        status = n_good >= 2 ? "ACCETTABILE" : "DA MIGLIORARE"
        write(io, "## Conclusion\n\n")
        write(io, "**Status: $status** — R² ≥ 0.7 for $n_good out of 4 outputs.\n\n")
        if status == "ACCETTABILE"
            write(io, "The surrogate meets the acceptance criteria. Next steps:\n")
            write(io, "- Feature importance analysis for pruning\n")
            write(io, "- Hyperparameter tuning (learning rate, architecture)\n")
            write(io, "- Increase dataset size with more simulations\n")
        else
            write(io, "The surrogate does not yet meet acceptance criteria. Suggestions:\n")
            write(io, "- Collect more training data\n")
            write(io, "- Increase model capacity or try different architectures\n")
            write(io, "- Engineer additional features\n")
        end
    finally
        close(io)
    end

    @info "Plots: $(readdir(plots_dir))"
    @info "test_report.md written → $report_path"
    println("\nAll done.")
end

main()
