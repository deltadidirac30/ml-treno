# ============================================================================
# Dataset module: Assembles raw data + features into a unified dataset
# and implements stratified train/test splitting.
#
# Functions exported:
#   - assemble_dataset(): Merge raw simulation data with computed features
#   - train_test_split(): Stratified split by source_group (experiment type)
# ============================================================================

module Dataset

using CSV
using DataFrames
using Random

export assemble_dataset, train_test_split

# ============================================================================
# Target variables: What we want to predict (4 outputs)
# H2_cons: Hydrogen consumption (kg/km)
# SOC_end: Battery state of charge at end of journey (0-100%)
# num_repl_FC: Number of fuel cell module replacements needed
# num_repl_batt: Number of battery module replacements needed
# ============================================================================
const OUTPUT_COLS = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]

# ============================================================================
# Feature columns: 69 features extracted from route profiles
# Organized by category:
#   - Scalars (3): L_km, P_nom_fc, C_batt
#   - Slope features (18): gravitational work, statistics, structure
#   - Speed features (11): statistics, energy, classes
#   - Stop features (10): density, energy, local slope
#   - Cross features (10): slope × speed × stops interactions
#   - Binning features (20): spatial division into 10 segments each for slope & speed
# Total: 69 features (must match features.jl)
# ============================================================================
const FEATURE_COLS_RAW = [
    "L_km", "P_nom_fc", "C_batt", "slope_int_pos", "slope_int_neg",
    "slope_int_abs", "slope_rms", "slope_mean_pos", "slope_std_pos",
    "slope_mean_neg", "slope_std_neg", "slope_max", "slope_min",
    "slope_std_all", "slope_std_sq_pos", "slope_L_up_frac",
    "slope_sign_changes_per_km", "slope_max_run_up_km", "vlim_mean",
    "vlim_std", "vlim_max", "vlim_min", "vlim_sum_abs_dv2",
    "vlim_changes_per_km", "vlim_sum_dv_pos_sq", "vlim_sum_dv_neg_sq",
    "vlim_frac_low", "vlim_frac_mid", "vlim_frac_high", "stops_density",
    "stops_spacing_mean", "stops_spacing_std", "stops_sum_v2",
    "stops_mean_v", "stops_std_v", "stops_sum_v2_segweighted",
    "stops_mean_p", "stops_sum_abs_p", "stops_frac_on_slope",
    "cross_Lup_v", "cross_Ldn_v", "cross_brake_energy_signed",
    "cross_thermal_fatigue", "cross_stops_v_seg", "cross_abs_p_highv",
    "cross_up_lowv", "cross_mean_p_v", "cross_int_p_v", "cross_var_p_v",
    "bin_p_1", "bin_p_2", "bin_p_3", "bin_p_4", "bin_p_5",
    "bin_p_6", "bin_p_7", "bin_p_8", "bin_p_9", "bin_p_10",
    "bin_v_1", "bin_v_2", "bin_v_3", "bin_v_4", "bin_v_5",
    "bin_v_6", "bin_v_7", "bin_v_8", "bin_v_9", "bin_v_10",
]
@assert length(FEATURE_COLS_RAW) == 69 "Feature column count must be 69"

# ============================================================================
# Assembles the final dataset by merging raw simulation outputs with computed features
#
# INPUT:
#   - raw_rows_path: Path to raw_rows.csv (from 01_ingest.jl)
#     Contains: row_idx, output columns (H2_cons, SOC_end, etc.), source_file
#   - features_path: Path to features_matrix.csv (from 03_features.jl)
#     Contains: row_idx, 69 feature columns
#
# PROCESS:
#   1. Load both CSV files with row_idx as integer
#   2. Validate that required columns exist
#   3. Select only needed columns from each file (drop intermediate data)
#   4. Inner join on row_idx (keeps only rows present in both files)
#   5. Sort by row_idx for reproducibility
#   6. Extract source experiment group from filename (basename)
#   7. Replace source_file with categorical source_group
#
# OUTPUT:
#   - DataFrame with 75 columns:
#     - row_idx (1)
#     - OUTPUT_COLS (4): H2_cons, SOC_end, num_repl_FC, num_repl_batt
#     - FEATURE_COLS_RAW (69): slope, speed, stop, cross, binning features
#     - source_group (1): experiment/file group for stratified splitting
#   - Total rows: count of matching row_idx in both files
#
# ============================================================================
function assemble_dataset(raw_rows_path::AbstractString, features_path::AbstractString)::DataFrame
    # Load CSV files: ensure row_idx is integer type for reliable joining
    raw_df = CSV.read(raw_rows_path, DataFrame; types=Dict(:row_idx=>Int))
    feat_df = CSV.read(features_path, DataFrame; types=Dict(:row_idx=>Int))

    # Validate: both files must have row_idx
    @assert "row_idx" in names(raw_df) && "row_idx" in names(feat_df) "Missing row_idx"
    # Validate: all 69 features must be present in features_matrix.csv
    @assert all(c -> c in names(feat_df), FEATURE_COLS_RAW) "Missing feature columns in features_matrix"
    # Validate: all 4 outputs must be present in raw_rows.csv
    @assert all(c -> c in names(raw_df), OUTPUT_COLS) "Missing output columns in raw_rows"

    # Extract only needed columns from raw data (drop intermediate data like explicit_param)
    raw_narrow = select(raw_df, :row_idx, OUTPUT_COLS..., :source_file)
    # Extract only features (drop row_idx temporarily, will be used for join)
    feat_narrow = select(feat_df, :row_idx, FEATURE_COLS_RAW...)

    # Merge on row_idx: inner join keeps only rows that exist in both files
    joined = innerjoin(raw_narrow, feat_narrow, on=:row_idx)
    # Sort for reproducibility and easier debugging
    sort!(joined, :row_idx)

    # Extract experiment source from filename (e.g., "opt_results_vel.xlsx" or "real_routes.xlsx")
    # This is used later for stratified train/test splitting
    source_group = basename.(joined.source_file)
    # Remove source_file column (no longer needed)
    select!(joined, Not(:source_file))
    # Add source_group as last column
    insertcols!(joined, ncol(joined) + 1, :source_group => source_group)

    return joined
end

# ============================================================================
# Stratified train/test split by source_group (experiment type)
#
# This ensures that:
#   - All experiments are represented in both train and test sets
#   - Small experiment groups (<5 rows) go entirely to training (avoid test leakage)
#   - Larger groups are split with the specified test_frac
#
# INPUT:
#   - df: DataFrame with source_group column
#   - test_frac: Fraction of rows to allocate to test set (default 0.2 = 20%)
#   - seed: Random seed for reproducibility (default 42)
#
# OUTPUT:
#   - Tuple of (train_df, test_df) with same columns as input
#   - No shuffling within returned dataframes; use shuffle() if needed
#
# ============================================================================
function train_test_split(
    df::DataFrame;
    test_frac::Real=0.2,
    seed::Integer=42,
)::Tuple{DataFrame,DataFrame}
    # Set random seed for deterministic shuffling
    Random.seed!(seed)

    train_rows = Int[]  # Collect row_idx values for training
    test_rows = Int[]   # Collect row_idx values for testing

    # Stratified split: process each experiment group independently
    for g in groupby(df, :source_group)
        idxs = g.row_idx        # row_idx values in this group
        n = nrow(g)             # Number of rows in this group

        # Small groups (<5 rows): put entirely in training to avoid overfitting
        if n < 5
            append!(train_rows, idxs)
        else
            # Large groups: split according to test_frac
            n_test = max(1, round(Int, n * test_frac))  # Minimum 1 row for test
            perm = Random.shuffle(1:n)                  # Randomize indices
            test_i = view(perm, 1:n_test)              # First n_test (test set)
            train_i = view(perm, n_test+1:n)           # Rest (training set)
            append!(test_rows, idxs[test_i])           # Select corresponding row_idx
            append!(train_rows, idxs[train_i])         # Select corresponding row_idx
        end
    end

    # Convert to sets for O(1) lookup during filtering
    train_set = Set(train_rows)
    test_set = Set(test_rows)

    # Filter original dataframe to get train and test subsets
    train_df = filter(r -> r.row_idx in train_set, df)
    test_df = filter(r -> r.row_idx in test_set, df)

    # Return both dataframes with same structure but different rows
    return train_df, test_df
end

end  # End of Dataset module
