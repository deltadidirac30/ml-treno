# ============================================================================
# This script synthesizes driving profiles for each row in the dataset.
# 
# What it does:
#   1. Reads the raw_rows.csv file (created by 01_ingest.jl)
#   2. For each row, synthesizes a complete driving profile containing:
#      - Route length (L)
#      - Slope profile along the route (p)
#      - Speed limit segments (vlim_segments)
#      - Stop positions (stops)
#   3. Saves all profiles to a JLD2 file (faster than CSV for binary data)
# 
# The synthesis uses the seed from each row to ensure reproducibility:
#   - Same row -> same seed -> same random profile
# ============================================================================

# Activate the project's Julia environment (load packages from Project.toml)
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))


# Import required packages
using CSV           # For reading the input CSV file
using DataFrames    # For working with tabular data
using JLD2          # For saving the output (binary format, fast)
using Random        # For random number generation (MersenneTwister)


# Include the profile synthesis module
# This contains the functions that generate driving profiles
# (synthesize_row, synthesize_slope, synthesize_vlim, synthesize_stops, etc.)
include(joinpath(@__DIR__, "..", "src", "profile_synth.jl"))


# ============================================================================
# The main function that orchestrates the profile synthesis
# ============================================================================
function main()
    
    # Define the path to the raw data (output from 01_ingest.jl)
    raw_rows_path = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")
    
    
    # Check if the raw data file exists
    # If not, print an error message and exit (can't continue without the data)
    if !isfile(raw_rows_path)
        println("Error: raw_rows.csv not found at $raw_rows_path")
        println("Please run scripts/01_ynthesize.jl first.")
        exit(1)
    end
    
    
    # Read the raw data from the CSV file into a DataFrame
    # This gives us a table with columns: P_nom_fc, C_batt, H2_cons, etc.
    df = CSV.read(raw_rows_path, DataFrame)
    
    
    # Define the output path for the synthesized profiles
    profiles_path = joinpath(@__DIR__, "..", "data_generated", "profiles.jld2")
    
    
    # Get the number of rows in the dataset
    N = nrow(df)
    println("Synthesizing profiles for $N rows...")
    
    
    # Create a dictionary to store all synthesized profiles
    # Key = row index (1, 2, 3, ...)
    # Value = NamedTuple with (L, p, vlim_segments, stops)
    profile_data = Dict{Int, NamedTuple}()
    
    
    # Loop through each row in the dataset
    for row_idx in 1:N
        
        # Get the current row from the DataFrame
        # df[row_idx, :] extracts all columns for that row
        row = df[row_idx, :]
        
        
        # Call synthesize_row from profile_synth.jl
        # This generates a complete driving profile for this row
        # Uses the row's seed to ensure reproducibility
        synthesized = synthesize_row(row)
        
        
        # Store the synthesized profile in our dictionary
        profile_data[row_idx] = synthesized
        
        
        # Print progress every 500 rows
        if row_idx % 500 == 0
            println("  Processed $row_idx / $N rows")
        end
    end
    
    
    # Save all profiles to a JLD2 file
    # This is much faster than CSV for large amounts of binary data
    # The file will contain a dictionary: "profile_data" -> Dict of profiles
    JLD2.save(profiles_path, "profile_data", profile_data)
    
    
    # Print completion message
    println("\nSynthesized $N profiles to $profiles_path")
end


# Run the main function when the script is executed
main()