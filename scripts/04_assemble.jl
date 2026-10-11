# ============================================================================
# 04_assemble.jl: Final dataset assembly and train/test split
#
# This script orchestrates the creation of the final machine learning dataset:
#   1. Reads raw_rows.csv (outputs from simulation) - from 01_ingest.jl
#   2. Reads features_matrix.csv (computed features) - from 03_features.jl
#   3. Merges them into dataset_final.csv
#   4. Validates data integrity (69 features, no missing values)
#   5. Converts numeric columns to Float32 (memory efficient for training)
#   6. Performs stratified train/test split (80/20) by experiment group
#   7. Outputs train.csv and test.csv
#
# Output structure: 75 columns
#   - row_idx (1): unique identifier linking back to original data
#   - targets (4): H2_cons, SOC_end, num_repl_FC, num_repl_batt
#   - features (69): slope, speed, stops, cross-interaction, spatial binning
#   - source_group (1): experiment type for stratification
# ============================================================================

# Activate project environment and load dependencies
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

using CSV         # For reading/writing CSV files
using DataFrames  # For tabular data manipulation
using Statistics  # For statistical functions

# Include the Dataset module which contains:
#   - assemble_dataset(): Merge raw data with features
#   - train_test_split(): Stratified splitting by source group
include(joinpath(@__DIR__, "..", "src", "dataset.jl"))
using .Dataset

# ============================================================================
# File paths: Input and output locations
# ============================================================================
const RAW_PATH = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")
# ^ Input: Simulation outputs from 01_ingest.jl (nrows × 9 columns)
#   Columns: row_idx, P_nom_fc, C_batt, H2_cons, SOC_end, num_repl_FC, num_repl_batt,
#            explicit_param, explicit_value, source_file

const FEAT_PATH = joinpath(@__DIR__, "..", "data_generated", "features_matrix.csv")
# ^ Input: Feature vectors from 03_features.jl (nrows × 70 columns)
#   Columns: row_idx, + 69 feature columns (slope, speed, stops, cross, binning)

const OUT_FINAL = joinpath(@__DIR__, "..", "data_generated", "dataset_final.csv")
# ^ Output: Complete assembled dataset (nrows × 75 columns)
#   Contains: row_idx, 4 outputs, 69 features, source_group

const OUT_TRAIN  = joinpath(@__DIR__, "..", "data_generated", "train.csv")
# ^ Output: Training subset (≈80% of rows, same 75 columns)

const OUT_TEST  = joinpath(@__DIR__, "..", "data_generated", "test.csv")
# ^ Output: Test subset (≈20% of rows, same 75 columns)

# ============================================================================
# Convert numeric columns to Float32 for memory efficiency
#
# Rationale:
#   - Most features are continuous floats, not requiring Float64 precision
#   - Float32 uses half the memory, speeds up neural network training
#   - Acceptable precision loss for surrogate models
#
# This modifies df in-place, converting all numeric columns except those
# already Float32 type
# ============================================================================
function _to_float32!(df::DataFrame)
    for col in names(df)
        T = eltype(df[!, col])
        # Check if column is numeric and not already Float32
        if T <: Number && !(T <: Float32)
            # Convert to Float32 and replace column in-place
            df[!, col] = Float32.(df[!, col])
        end
    end
end

# ============================================================================
# Step 1: Assemble the complete dataset by merging raw outputs with features
# ============================================================================
println("Assembling dataset...")
df = assemble_dataset(RAW_PATH, FEAT_PATH)

# Validate: must have exactly 75 columns
#   1 (row_idx) + 4 (outputs) + 69 (features) + 1 (source_group) = 75
expected_cols = 75
@assert ncol(df) == expected_cols "Expected $expected_cols columns, got $(ncol(df))"

# Validate: no missing values (NaN, Inf) in numeric columns
# This ensures data quality for training
num_cols = filter(n -> eltype(df[!, n]) <: Number, names(df))
@assert all(c -> all(isfinite, df[!, c]), num_cols) "Non-finite values in numeric columns"

# Convert all numeric columns to Float32 for memory efficiency during training
_to_float32!(df)

# Save the complete assembled dataset
CSV.write(OUT_FINAL, df)
println("  → dataset_final.csv  ($(nrow(df)) rows, $(ncol(df)) cols)")

# ============================================================================
# Step 2: Stratified train/test split (80% train, 20% test)
#
# Stratified by source_group ensures:
#   - Each experiment type appears in both train and test
#   - Balanced representation of different route/parameter configurations
#   - No experiment type is exclusive to train or test
# ============================================================================
println("Splitting train/test...")
train_df, test_df = train_test_split(df; test_frac=0.2, seed=42)
# ^ Seed=42 ensures reproducible split across runs

# Validate: stratification worked correctly
all_groups = unique(df.source_group)           # All experiment groups
train_groups = unique(train_df.source_group)   # Groups in training set
test_groups = unique(test_df.source_group)     # Groups in test set
@assert issubset(train_groups, all_groups) && issubset(test_groups, all_groups) "Stratification failed"

# Save training and test sets
CSV.write(OUT_TRAIN, train_df)
CSV.write(OUT_TEST, test_df)
println("  → train.csv  ($(nrow(train_df)) rows)")
println("  → test.csv   ($(nrow(test_df)) rows)")

# ============================================================================
# Step 3: Report stratification results
#
# Shows the distribution of each experiment group across train and test sets.
# Verifies that the split is reasonably balanced.
# ============================================================================
println("\nGroup distribution (train / test):")
for g in sort!(unique(df.source_group))
    # Count rows for this group in training set
    n_tr = count(==(g), train_df.source_group)
    # Count rows for this group in test set
    n_te = count(==(g), test_df.source_group)
    # Print balance (should be roughly 80/20)
    println("  $g  →  train=$n_tr  test=$n_te")
end

println("\nDone.")
