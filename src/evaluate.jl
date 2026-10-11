# ============================================================================
# evaluate.jl: Measure neural network prediction quality on test data
#
# The evaluate() function runs the trained model on test data and computes
# four quality metrics for each of the 4 output variables:
#   - MSE (Mean Squared Error): average of squared errors
#   - MAE (Mean Absolute Error): average of absolute errors (more intuitive)
#   - R² (R-squared): proportion of variance explained (1.0 = perfect, 0 = useless)
#   - Accuracy: for integer-valued outputs (num_repl_FC, num_repl_batt)
# ============================================================================

using DataFrames
using Statistics: mean

# ============================================================================
# evaluate(): Compute prediction metrics on test set
#
# Args:
#   model: Trained MLPSurrogate neural network
#   X_test: Input features (69 × n_test) — routes/slopes/speed profiles
#   Y_test: True outputs (4 × n_test) — actual H2_cons, SOC_end, num_repl_FC, num_repl_batt
#   norm_stats: Normalization statistics (μ, σ) for features
#              Fitted on training data and applied to features before prediction
#   output_norm: (Optional) Normalization statistics for outputs
#               If provided, predictions are de-normalized to original units
#               If not provided, metrics are computed on normalized predictions
#
# Returns:
#   DataFrame with columns: output, MSE, MAE, R2, accuracy
#   One row per output variable
# ============================================================================
function evaluate(model, X_test, Y_test, norm_stats; output_norm=nothing)
    # Step 1: Normalize input features to match training statistics
    # (model was trained on normalized inputs, so we must normalize test inputs the same way)
    X_n = (X_test .- norm_stats.μ) ./ norm_stats.σ

    # Step 2: Run the model on normalized inputs
    # Ŷ_raw = predictions from the neural network (in normalized units)
    Ŷ_raw = model(X_n)

    # Step 3: De-normalize outputs if output_norm was provided
    # During training, outputs were normalized to help convergence
    # Now we convert back to original units (e.g., kg/km for H2_cons)
    # Formula: original = (normalized * σ) + μ
    if output_norm !== nothing
        Ŷ = Ŷ_raw .* output_norm.σ .+ output_norm.μ
    else
        # If no normalization was applied, use predictions as-is
        Ŷ = Ŷ_raw
    end

    n_out = size(Ŷ, 1)
    @assert n_out == 4

    outputs = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]
    MSE = Float64[]
    MAE = Float64[]
    R2  = Float64[]
    acc = Union{Missing, Float64}[]

    # Compute metrics for each of the 4 output variables
    for k in 1:4
        # Extract actual and predicted values for this output
        y_true = Float64.(Y_test[k, :])    # True values from test set
        y_pred = Float64.(Ŷ[k, :])        # Predicted values from model

        # ====== METRIC 1: Mean Squared Error (MSE) ======
        # Measures average squared difference between predictions and truth
        # Larger errors are penalized more (due to squaring)
        # Units: squared units of the output (e.g., (kg/km)^2 for H2_cons)
        mse    = mean((y_pred .- y_true).^2)

        # ====== METRIC 2: Mean Absolute Error (MAE) ======
        # Average of absolute differences: more interpretable than MSE
        # Units: same as output (e.g., kg/km for H2_cons)
        mae    = mean(abs.(y_pred .- y_true))

        # ====== METRIC 3: R² (Coefficient of Determination) ======
        # How much variance in the data is explained by the model
        # R² = 1 - (residual_variance / total_variance)
        # R² = 1.0: perfect predictions
        # R² = 0.5: explains half the variance (decent)
        # R² = 0.0: no better than predicting the mean (useless)
        ss_res = sum((y_true .- y_pred).^2)           # Residual sum of squares
        ss_tot = sum((y_true .- mean(y_true)).^2)     # Total sum of squares
        r2     = ss_tot < 1e-10 ? 0.0 : 1.0 - ss_res / ss_tot

        # Add metrics to result lists
        push!(MSE, mse)
        push!(MAE, mae)
        push!(R2,  r2)

        # ====== METRIC 4: Accuracy (for integer outputs only) ======
        # Outputs 3 and 4 (num_repl_FC, num_repl_batt) represent replacement counts
        # These must be non-negative integers, so we:
        #   1. Clamp predictions to ≥ 0 (can't have negative replacements)
        #   2. Round to nearest integer
        #   3. Check if rounded prediction matches rounded truth
        if k ∈ (3, 4)
            # Round predictions to nearest non-negative integer
            # max(0.0, y_pred): clamp to non-negative before rounding
            y_int = round.(Int, max.(0.0, y_pred))
            # Count how many predictions match the truth (as integers)
            accuracy = mean(y_int .== round.(Int, y_true))
            push!(acc, accuracy)
        else
            # Outputs 1 and 2 are continuous (not integers), so accuracy doesn't apply
            push!(acc, missing)
        end
    end

    return DataFrame(; output=outputs, MSE, MAE, R2, accuracy=acc)
end
