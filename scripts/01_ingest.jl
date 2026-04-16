# ============================================================================
# This script is the entry point for the data ingestion process.
# It loads data from Excel files and saves them as a CSV file.
# 
# What it does, step by step:
#   1. Activates the project's Julia environment (loads required packages)
#   2. Includes the ingestion.jl module (contains the data loading functions)
#   3. Calls ingest_all() to read all Excel files and combine them
#   4. Validates that no data is missing
#   5. Saves the combined data to a CSV file
# ============================================================================

# Activate the project's environment.
# This tells Julia to use the packages defined in the Project.toml file.
# Without this, the packages (CSV, DataFrames, etc.) wouldn't be available.
# 
# @__DIR__ = the folder where this script is located (scripts/)
# joinpath(@__DIR__, "..") = go one level up to the project root
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))


# Import the packages we need
using CSV           # For reading/writing CSV files
using DataFrames    # For working with tabular data
using JLD2          # For saving data in Julia's JLD format (not used in this script but might be needed later)
using Random        # For random operations (not used here but might be needed later)


# Include the ingestion module.
# This loads all the functions defined in src/ingestion.jl
# (ingest_all, parse_eu_float, parse_eu_int, etc.)
include(joinpath(@__DIR__, "..", "src", "ingestion.jl"))


# Define the paths to the data folders.
# @__DIR__ gives us the directory where this script is located.
#
# DATA_ROOT: Where the source Excel files are located
#   -> goes up to project root, then to ml_treno_H2/Data
# OUTPUT_PATH: Where we'll save the combined CSV
#   -> goes up to project root, then to data_generated/raw_rows.csv
const DATA_ROOT = joinpath(@__DIR__, "..", "..", "ml_treno_H2", "Data")
const OUTPUT_PATH = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")


# ============================================================================
# The main function that orchestrates the entire ingestion process.
# This is where the actual work happens.
# ============================================================================
function main()
    
    # Print a status message showing where we're reading from
    println("Starting ingestion from: $DATA_ROOT")
    
    
    # Call the ingest_all function from ingestion.jl.
    # This function:
    #   - Finds all Excel files in DATA_ROOT
    #   - Reads each file and each sheet
    #   - Extracts the relevant columns (P_nom_fc, C_batt, etc.)
    #   - Filters out invalid rows (missing data, outliers)
    #   - Combines everything into one big DataFrame
    #   - Returns the combined DataFrame
    df = ingest_all(DATA_ROOT)
    
    
    # Check that we actually got some data.
    # nrow(df) returns the number of rows in the DataFrame.
    # If it's 0, something went wrong (no data was loaded).
    if nrow(df) == 0
        error("No rows were ingested!")  # Stop execution with an error message
    end
    
    
    # Validate that no Float64 columns have missing values.
    # This ensures data quality - we don't want to train ML models on incomplete data.
    # 
    # Loop through each column in the DataFrame
    for col in names(df)
        
        # Get the type of this column
        # If it's Union{Missing, Float64}, it means it CAN contain missing values
        if eltype(df[!, col]) <: Union{Missing, Float64}
            
            # Check if any value in this column is actually missing
            if any(ismissing, df[!, col])
                # If missing values found, stop and report which column
                error("Column $col contains missing values!")
            end
        end
    end
    
    
    # Create the output folder if it doesn't already exist.
    # dirname(OUTPUT_PATH) extracts the folder part of the path
    # mkpath creates all intermediate folders as needed
    mkpath(dirname(OUTPUT_PATH))
    
    
    # Save the DataFrame to a CSV file.
    # CSV.write(filename, dataframe) writes the dataframe to the file.
    CSV.write(OUTPUT_PATH, df)
    
    
    # Print confirmation messages with the results
    println("\nOutput written to: $OUTPUT_PATH")
    println("Total rows written: $(nrow(df))")
end


# Call the main function to run the script.
# This is the entry point - when you run this script, execution starts here.
main()