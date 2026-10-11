# ============================================================================
# 05_train.jl: Full training pipeline for the neural network surrogate model
#
# This script:
#   1. Loads training data (69 features, 4 targets)
#   2. Splits into 80% train / 20% validation (internally)
#   3. Normalizes both inputs and outputs for training stability
#   4. Builds and trains a 4-layer neural network
#   5. Saves 3 checkpoint files for use by 06_evaluate.jl:
#      - model.bson: trained neural network weights
#      - norm_stats.bson: input normalization parameters (μ, σ)
#      - output_norm.bson: output normalization parameters
#   6. Saves training_log.csv: loss per epoch for analysis
#
# Run this AFTER 04_assemble.jl has created train.csv
# Run this BEFORE 06_evaluate.jl reads the checkpoints
# ============================================================================

# Activate the Julia project environment
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

# Load data manipulation and neural network libraries
using CSV, DataFrames, Random, Statistics
using BSON                              # For saving/loading binary data
using Statistics: mean, std

using Flux, Zygote, Optimisers          # Neural network and optimization

# Include and import the MLTrenoSurrogate module
include(joinpath(@__DIR__, "..", "src", "MLTrenoSurrogate.jl"))
using .MLTrenoSurrogate:
    build_model, zscore_fit, zscore_apply, loss_fn, train!

# ============================================================================
# Feature column list: The 69 input features (must match features.jl)
# ============================================================================
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

# ============================================================================
# Target/output column list: The 4 variables to predict
# ============================================================================
const OUTPUT_COLS = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]

# ============================================================================
# load_data(): Load and reshape CSV into matrix format for neural networks
#
# Neural networks expect data in matrix form:
#   - Rows = features (69 input features or 4 outputs)
#   - Columns = samples (one row of original data per sample)
#
# CSV format is opposite: rows = samples, columns = features
# Solution: transpose (permutedims) to get the right orientation
#
# Args:
#   path: Path to CSV file (e.g., train.csv)
#
# Returns:
#   X: Features (69 × n_samples) as Float32 matrix
#   Y: Targets (4 × n_samples) as Float32 matrix
# ============================================================================
function load_data(path)
    df = CSV.read(path, DataFrame)
    # Extract feature columns, convert to matrix, transpose to (69 × n_samples)
    X = permutedims(Matrix{Float32}(df[:, FEATURE_COLS]))
    # Extract target columns, convert to matrix, transpose to (4 × n_samples)
    Y = permutedims(Matrix{Float32}(df[:, OUTPUT_COLS]))
    return X, Y
end

# ============================================================================
# main(): Orchestrates the full training pipeline
# ============================================================================
function main()
    # Paths for reading input data and saving model checkpoints
    results_dir = joinpath(@__DIR__, "..", "results")
    data_dir = joinpath(@__DIR__, "..", "data_generated")
    mkpath(results_dir)

    # ========== STAGE 1: LOAD DATA ==========
    println("Loading train.csv …")
    X_all, Y_all = load_data(joinpath(data_dir, "train.csv"))
    @info "Full train set: $(size(X_all,2)) samples, $(size(X_all,1)) features"

    # ========== STAGE 2: TRAIN/VALIDATION SPLIT ==========
    # Split the training data into:
    #   - 80% training (used to adjust weights)
    #   - 20% validation (used to detect overfitting, early stopping)
    # NOTE: This is different from test.csv, which is never seen until evaluation
    Random.seed!(42)
    n = size(X_all, 2)
    perm = randperm(n)              # Random permutation of sample indices
    split = floor(Int, 0.8 * n)    # 80% of samples
    train_idx = perm[1:split]       # First 80%
    val_idx = perm[split+1:end]     # Last 20%

    # Extract subsets using the indices
    X_tr, Y_tr = X_all[:, train_idx], Y_all[:, train_idx]
    X_va, Y_va = X_all[:, val_idx], Y_all[:, val_idx]

    @info "Train: $(size(X_tr,2)) | Val: $(size(X_va,2))"

    # ========== STAGE 3: INPUT NORMALIZATION ==========
    # Normalize input features to mean=0, std=1
    # This stabilizes training: all features on same scale, gradients more uniform
    println("Fitting z-score normalization …")
    # Fit on training data only (to avoid data leakage from val set)
    μ, σ = zscore_fit(X_tr)
    # Apply to both train and val using the SAME fitted parameters
    X_tr_n = zscore_apply(X_tr, μ, σ)
    X_va_n = zscore_apply(X_va, μ, σ)

    # Save normalization parameters for later use in 06_evaluate.jl
    norm_stats = (μ=μ, σ=σ)
    BSON.@save joinpath(results_dir, "norm_stats.bson") norm_stats
    @info "norm_stats.bson saved"

    # ========== STAGE 4: OUTPUT NORMALIZATION ==========
    # Also normalize targets (Y) for training stability
    # Neural networks learn faster when outputs are normalized
    println("Normalizing outputs (per-channel z-score) for training stability …")
    # Fit on training targets only
    Y_μ = vec(mean(Y_tr, dims=2))
    Y_σ = vec(std(Y_tr, dims=2; corrected=true))
    Y_σ = max.(Y_σ, Float32(1e-8))  # Prevent division by zero
    # Normalize training and validation targets
    Y_tr_n = (Y_tr .- Y_μ) ./ Y_σ
    Y_va_n = (Y_va .- Y_μ) ./ Y_σ

    # Save output normalization parameters for de-normalization in evaluate
    output_norm = (μ=Y_μ, σ=Y_σ)
    BSON.@save joinpath(results_dir, "output_norm.bson") output_norm
    @info "output_norm.bson saved"

    # ========== STAGE 5: BUILD NEURAL NETWORK ==========
    # Create a 4-layer MLP: 69 → 128 → 64 → 32 → 4
    println("Building model: 4-layer Dense 128→64→32→4 …")
    model = build_model(69)

    # ========== STAGE 6: TRAIN THE NETWORK ==========
    # Run the mini-batch gradient descent training loop
    println("Training on normalized outputs …")
    log, best_model = train!(model, X_tr_n, Y_tr_n, X_va_n, Y_va_n;
                             epochs=800,       # Maximum iterations
                             batch_size=128,   # Samples per weight update
                             lr=3e-4,          # Learning rate (step size)
                             patience=75,      # Early stopping: stop if 75 epochs no improvement
                             weight_decay=1e-4) # L2 regularization strength

    # ========== STAGE 7: SAVE MODEL CHECKPOINT ==========
    # Save the best model (best validation loss), not the final state
    # Final state may be overfitted; best validation state is most generalizable
    model_path = joinpath(results_dir, "model.bson")
    BSON.@save model_path best_model
    @info "model.bson saved (best-val checkpoint) → $model_path"

    # ========== STAGE 8: SAVE TRAINING LOG ==========
    # Save epoch-by-epoch training history for visualization
    log_df = DataFrame(log)
    CSV.write(joinpath(results_dir, "training_log.csv"), log_df)
    @info "training_log.csv saved"

    # Final status message
    final_val = log[end].val_loss
    @info "Training complete. Final val_loss: $(round(final_val; digits=5))"
    println("Done. All artifacts in results/")
end

main()
