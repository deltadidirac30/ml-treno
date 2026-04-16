# ============================================================================
# This script extracts numerical features from the synthesized profiles.
# 
# What it does:
#   1. Reads raw_rows.csv (the original data with P_nom_fc, C_batt, etc.)
#   2. Reads profiles.jld2 (the synthesized driving profiles)
#   3. For each row, extracts 69 numerical features describing:
#      - Route properties (length, power, battery)
#      - Slope characteristics (statistics, integrals, structure)
#      - Speed limit characteristics (statistics, changes, classes)
#      - Stop characteristics (density, spacing, energy)
#      - Cross-features (combinations of slope, speed, stops)
#      - Spatial binning (10 bins of slope and speed)
#   4. Saves everything to features_matrix.csv
# 
# The output is a matrix with:
#   - Rows: one per data point
#   - Columns: 69 features + row_idx
# ============================================================================

# Activate the project's Julia environment
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))


# Import required packages
using CSV           # For reading/writing CSV files
using DataFrames    # For working with tabular data
using JLD2          # For loading the profiles file


# Include the features extraction module
# This contains all the functions to compute the 69 features
include(joinpath(@__DIR__, "..", "src", "features.jl"))


# ============================================================================
# Main function that orchestrates the feature extraction
# ============================================================================
function main()
    
    # Define input paths
    raw_csv_path = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")
    profiles_path = joinpath(@__DIR__, "..", "data_generated", "profiles.jld2")
    
    # Define output path
    out_path = joinpath(@__DIR__, "..", "data_generated", "features_matrix.csv")
    
    
    # Read the raw data (from 01_ingest.jl)
    # This contains: P_nom_fc, C_batt, H2_cons, seed, explicit_param, etc.
    println("Loading raw_rows.csv...")
    rows_df = CSV.read(raw_csv_path, DataFrame)
    n_rows = nrow(rows_df)
    println("  Rows: $n_rows")
    
    
    # Load the synthesized profiles (from 02_synthesize.jl)
    # This contains: L, p (slope), vlim_segments, stops for each row
    println("Loading profiles.jld2...")
    raw_profiles = load(profiles_path)
    profiles = raw_profiles["profile_data"]  # Extract the dictionary
    println("  Profile records: $(length(profiles))")
    
    
    # Pre-allocate the features matrix
    # n_rows rows × 69 columns
    features_matrix = Matrix{Float64}(undef, n_rows, 69)
    
    # Also keep track of which row_idx each feature row corresponds to
    row_indices = Vector{Int}(undef, n_rows)
    
    
    # Loop through each row and extract features
    for i in 1:n_rows
        
        # Get the row from raw data
        row = rows_df[i, :]
        
        # Get the row_idx (unique ID for this data point)
        row_idx = row.row_idx
        
        
        # Get the corresponding profile
        # profiles is a dictionary: key = row_idx, value = profile
        prof = profiles[row_idx]
        
        
        # Extract features using the function from features.jl
        # This computes all 69 features for this profile + vehicle config
        feat = extract_features(
            p = prof.p,                    # Slope profile (vector of slopes per meter)
            vlim_segments = prof.vlim_segments,  # Speed limit segments
            stops = prof.stops,            # Stop positions
            L = Float64(prof.L),           # Route length in km
            P_nom_fc = Float64(row.P_nom_fc),   # Fuel cell power
            C_batt = Float64(row.C_batt),      # Battery capacity
        )
        
        
        # Store the features in our matrix
        features_matrix[i, :] = feat
        
        # Store the row index for reference
        row_indices[i] = row_idx
        
        
        # Print progress every 500 rows
        if i % 500 == 0
            println("  Processed $i / $n_rows rows")
        end
    end
    
    
    # Write the output CSV
    println("Writing features_matrix.csv...")
    
    # Create a DataFrame with the feature matrix and column names
    # FEATURE_NAMES is defined in features.jl (list of 69 feature names)
    out_df = DataFrame(features_matrix, FEATURE_NAMES)
    
    # Add the row_idx column
    out_df.row_idx = row_indices
    
    # Save to CSV
    CSV.write(out_path, out_df)
    
    
    # Print completion message
    println("Done. Output: $out_path")
    println("Shape: $(nrow(out_df)) rows × $(ncol(out_df) - 1) features (+ row_idx)")
    
    
    # Print some statistics about the first few rows
    # This helps verify the output looks reasonable
    first_row_stats = select(out_df[1:3, :], FEATURE_NAMES)
    println("\nFirst 3 rows stats:")
    describe(first_row_stats)
end


# Run the main function
main()