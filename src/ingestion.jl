using XLSX
using DataFrames
using CSV
using Random

# Export these functions so they can be used from other files that include this module
export ingest_all, parse_eu_float, parse_eu_int

# ============================================================================
# This dictionary maps Excel filenames to the parameter name they represent.
# For example, "opt_results_sensitivity_stops.xlsx" contains experiments where
# the number of stops (n_stops) was varied.
# ============================================================================
const FILE_PARAM_MAP = Dict(
    "opt_results_sensitivity_stops.xlsx" => "n_stops",
    "opt_results_sensitivity_length.xlsx" => "L_km",
    "opt_results_sensitivity_slope.xlsx" => "slope_permille",
    "opt_results_sensitivity_vel.xlsx" => "v_max_kmh",
    "opt_results_real_routes.xlsx" => "template_id",
)


# ============================================================================
# Parses a value into a Float64, handling European decimal format (comma instead of dot).
# Also handles various input types (Int, String, already Float64, or missing).
# Returns: Float64 number or `missing` if parsing fails.
# 
# Example inputs that all produce 12.5:
#   - 12.5 (Float64) -> 12.5
#   - 12 (Int) -> 12.0
#   - "12,5" (String with comma) -> 12.5
#   - "12.5" (String with dot) -> 12.5
#   - "invalid" -> missing
# ============================================================================
function parse_eu_float(val)::Union{Float64, Missing}
    # If already missing, return missing
    if ismissing(val)
        return missing
    end
    # If already Float64, return as-is
    if val isa Float64
        return val
    end
    # If it's an Integer, convert to Float64 (e.g., 5 -> 5.0)
    if val isa Int
        return Float64(val)
    end
    # If it's a String, try to parse it
    # European format uses comma as decimal separator: "12,5" -> "12.5"
    if val isa String
        # Replace comma with dot
        cleaned = replace(val, "," => ".")
        try
            # Try to convert string to Float64
            return parse(Float64, cleaned)
        catch
            # If parsing fails (invalid string), return missing
            return missing
        end
    end
    # If none of the above, return missing (unknown type)
    return missing
end


# ============================================================================
# Parses a value into an Integer, handling European decimal format.
# Similar to parse_eu_float but for integers.
# Returns: Integer or `missing` if parsing fails.
# 
# Example inputs:
#   - 5 (Int) -> 5
#   - 5.7 (Float64) -> 6 (rounds)
#   - "10" (String) -> 10
#   - "10,0" (String) -> 10
# ============================================================================
function parse_eu_int(val)::Union{Int, Missing}
    if ismissing(val)
        return missing
    end
    if val isa Int
        return val
    end
    # If Float64, round to nearest integer
    if val isa Float64
        return Int(round(val))
    end
    if val isa String
        cleaned = replace(val, "," => ".")
        try
            # Parse as Float first, then round to Int
            return Int(round(parse(Float64, cleaned)))
        catch
            return missing
        end
    end
    return missing
end


# ============================================================================
# Searches recursively through a folder and finds all Excel files (.xlsx)
# that start with "opt_results_".
# 
# INPUT:  data_root - path to the root folder to search
# OUTPUT: Vector of full paths to matching Excel files
# 
# Example: If data_root contains:
#   - /data/opt_results_sensitivity_stops.xlsx  (included)
#   - /data/other_file.xlsx                      (excluded - doesn't start with opt_results_)
#   - /data/subfolder/real_routes.xlsx           (included if starts with opt_results_)
#   - /data/~$temp.xlsx                          (excluded - temporary file)
# ============================================================================
function find_excel_files(data_root::AbstractString)::Vector{String}
    # Create an empty list to store matching file paths
    files = String[]
    
    # walkdir recursively walks through all folders and subfolders
    # For each folder, it returns:
    #   - root: the current folder path
    #   - dirs: list of subdirectories
    #   - filenames: list of files in this folder
    for (root, dirs, filenames) in walkdir(data_root)
        
        # Loop through each file in the current folder
        for fname in filenames
            
            # Skip temporary Excel files (created when someone has Excel open)
            # These start with "~$" (e.g., "~$file.xlsx")
            if startswith(fname, "~\$")
                continue  # Skip to next file
            end
            
            # Check if file:
            #   1. Ends with .xlsx (case-insensitive)
            #   2. Starts with "opt_results_"
            if endswith(lowercase(fname), ".xlsx") && startswith(fname, "opt_results_")
                # Add the full path to our list
                push!(files, joinpath(root, fname))
            end
        end
    end
    
    return files
end


# ============================================================================
# Given a filename, determines which parameter varies in that file.
# Uses the FILE_PARAM_MAP dictionary.
# 
# INPUT:  filename - e.g., "opt_results_sensitivity_stops.xlsx"
# OUTPUT: Parameter name string - e.g., "n_stops"
# 
# Example:
#   "opt_results_sensitivity_stops.xlsx" -> "n_stops"
#   "opt_results_real_routes.xlsx" -> "template_id"
#   "unknown_file.xlsx" -> "unknown"
# ============================================================================
function get_param_name(filename::AbstractString)::String
    # Get just the filename without the folder path
    # e.g., "/folder/file.xlsx" -> "file.xlsx"
    basename_file = basename(filename)
    
    # Loop through each key-value pair in the dictionary
    for (key, param) in FILE_PARAM_MAP
        # Check if the filename ends with the dictionary key
        # e.g., "opt_results_sensitivity_stops.xlsx" ends with "opt_results_sensitivity_stops.xlsx"
        if endswith(basename_file, key)
            return param  # Found a match, return the parameter name
        end
    end
    
    # If no match found, return "unknown"
    return "unknown"
end


# ============================================================================
# Cleans a column name by removing all spaces and trimming whitespace.
# This helps match column names that might have extra formatting in Excel.
# 
# INPUT:  s - column name string, e.g., "TCO (€/km)"
# OUTPUT: Cleaned string, e.g., "TCO(€/km)"
# 
# Example:
#   "TCO (€/km)" -> "TCO(€/km)"
#   "P_nom_fc "   -> "P_nom_fc"
#   "  H2_cons"   -> "H2_cons"
# ============================================================================
function normalize_colname(s::String)::String
    # First replace all spaces with nothing, then trim whitespace from edges
    return strip(replace(s, " " => ""))
end


# ============================================================================
# Searches for a column by name within a list of column names.
# Uses normalized names (spaces removed) for flexible matching.
# 
# INPUT:
#   - colnames: list of column names from the Excel sheet
#   - target: the column name we're looking for (e.g., "TCO (€/km)")
# OUTPUT:
#   - The index (1-based) of the column if found
#   - nothing if not found
# 
# Example:
#   colnames = ["TCO (€/km)", "P_nom_fc ", "C_batt"]
#   find_col_idx(colnames, "P_nom_fc") -> 2
#   find_col_idx(colnames, "Missing") -> nothing
# ============================================================================
function find_col_idx(colnames, target::String)
    # Normalize the target name (remove spaces)
    target_norm = normalize_colname(target)
    
    # Loop through all column names with their index
    # enumerate() gives us both the index (i) and value (c)
    for (i, c) in enumerate(colnames)
        # Normalize each column name
        col_str = normalize_colname(string(c))
        
        # If they match, return the index (1-based)
        if col_str == target_norm
            return i
        end
    end
    
    # If we loop through all and find nothing, return nothing
    return nothing
end


# ============================================================================
# Processes a single Excel sheet and extracts all relevant data.
# This is one of the main workhorse functions.
# 
# INPUT:
#   - filepath: full path to the Excel file
#   - sheet_name: name of the sheet to process
#   - param_name: which parameter varies (e.g., "n_stops")
#   - sheet_idx: index number of this sheet
#   - global_row_idx: a shared counter (Ref{Int}) to track unique row IDs
# OUTPUT:
#   - DataFrame with extracted rows from this sheet
# 
# What it does:
#   1. Reads the Excel sheet
#   2. Finds columns (TCO, P_nom_fc, C_batt, etc.)
#   3. Loops through each row
#   4. Filters out invalid rows (missing data, outliers)
#   5. Adds metadata (source file, parameter value, etc.)
#   6. Returns clean data
# ============================================================================
function process_sheet_via_readtable(filepath::String, sheet_name::String, 
                                      param_name::String, sheet_idx:: Int, 
                                      global_row_idx::Ref{Int})::DataFrame
    
    # Create an empty DataFrame with the columns we'll populate
    rows = DataFrame(
        P_nom_fc = Float64[],        # Nominal fuel cell power (kW)
        C_batt = Float64[],          # Battery capacity (kWh)
        H2_cons = Float64[],        # Hydrogen consumption (kg)
        SOC_end = Float64[],         # Final state of charge (%)
        num_repl_FC = Int[],         # Number of fuel cell replacements
        num_repl_batt = Int[],       # Number of battery replacements
        source_file = String[],      # Which Excel file this came from
        sheet_name = String[],       # Which sheet in that file
        explicit_param = String[],   # Parameter being varied (e.g., "n_stops")
        explicit_value = Float64[], # Value of that parameter (e.g., 10 for n_stops=10)
        row_idx = Int[],            # Unique row ID across all files
        seed = UInt32[],            # Random seed for reproducibility
    )
    
    try
        # Read the Excel sheet into a DataFrame
        df = XLSX.readtable(filepath, sheet_name) |> DataFrame
        
        # If the sheet is empty, return empty DataFrame
        if nrow(df) == 0
            return rows
        end
        
        # Get the list of column names from the Excel sheet
        colnames = names(df)
        
        # Find the position (index) of each column we need
        tco_idx = find_col_idx(colnames, "TCO (€/km)")
        p_nom_idx = find_col_idx(colnames, "P_nom_fc")
        c_batt_idx = find_col_idx(colnames, "C_batt")
        h2_idx = find_col_idx(colnames, "H2_cons")
        soc_idx = find_col_idx(colnames, "SOC_end")
        fc_idx = find_col_idx(colnames, "num_repl_FC")
        batt_idx = find_col_idx(colnames, "num_repl_batt")
        
        # If critical columns (TCO, P_nom_fc, C_batt) are missing, abort
        if isnothing(tco_idx) || isnothing(p_nom_idx) || isnothing(c_batt_idx)
            return rows
        end
        
        # Try to extract the parameter value from the sheet name
        # For example, if sheet is named "10", parsed_value = 10.0
        parsed_value = tryparse(Float64, strip(sheet_name))
        
        # Determine the explicit value for this sheet:
        # - If param_name is "template_id", use the sheet index as value
        # - Otherwise, use the parsed value from sheet name (or 0.0 if not a number)
        explicit_value = param_name == "template_id" ? Float64(sheet_idx) : (isnothing(parsed_value) ? 0.0 : parsed_value)
        
        # Loop through each row in the Excel sheet
        for i in 1:nrow(df)
            
            # Get TCO (Total Cost of Ownership) value
            tco_val = parse_eu_float(df[i, tco_idx])
            
            # Skip this row if:
            # - TCO is missing (no data)
            # - TCO > 500 €/km (unrealistic outlier)
            if ismissing(tco_val) || tco_val > 500.0
                continue  # Skip to next row
            end
            
            # Extract and parse other columns
            p_nom = parse_eu_float(df[i, p_nom_idx])
            c_batt = parse_eu_float(df[i, c_batt_idx])
            
            # If column exists (not nothing), parse it; otherwise set to missing
            h2_cons = isnothing(h2_idx) ? missing : parse_eu_float(df[i, h2_idx])
            soc_end = isnothing(soc_idx) ? missing : parse_eu_float(df[i, soc_idx])
            num_repl_fc = isnothing(fc_idx) ? missing : parse_eu_int(df[i, fc_idx])
            num_repl_batt = isnothing(batt_idx) ? missing : parse_eu_int(df[i, batt_idx])
            
            # Skip row if any of the required fields are missing
            if any(ismissing, [p_nom, c_batt, h2_cons, soc_end, num_repl_fc, num_repl_batt])
                continue  # Skip to next row
            end
            
            # Increment the global row counter (shared across all sheets)
            global_row_idx[] += 1
            current_row_idx = global_row_idx[]
            
            # Generate a deterministic random seed from filename + sheet + row number
            # This ensures the same row always gets the same seed (useful for reproducibility)
            seed = hash((basename(filepath), sheet_name, current_row_idx)) % UInt32
            
            # Add this valid row to our results DataFrame
            push!(rows, (
                p_nom, c_batt, h2_cons, soc_end,          # Data values
                num_repl_fc, num_repl_batt,                # Replacement counts
                basename(filepath), sheet_name,           # Source file info
                param_name, explicit_value,               # Parameter info
                current_row_idx, seed,                    # Row ID and seed
            ))
        end
        
    catch e
        # If anything goes wrong, warn but don't crash
        @warn "Error processing sheet $sheet_name in $filepath: $e"
    end
    
    # Return the extracted rows from this sheet
    return rows
end


# ============================================================================
# MAIN FUNCTION: Coordinates the entire ingestion process.
# This is the entry point called by 01_ingest.jl
# 
# INPUT:
#   - data_root: folder path containing Excel files
# OUTPUT:
#   - DataFrame with all combined data from all Excel files and sheets
# 
# What it does, step by step:
#   1. Creates an empty DataFrame to hold all results
#   2. Finds all Excel files in the data folder
#   3. For each Excel file:
#       a. Opens the file
#       b. Gets all sheet names
#       c. For each sheet (skipping ones starting with "_"):
#           - Calls process_sheet_via_readtable to extract data
#           - Appends valid rows to the combined DataFrame
#   4. Tracks how many rows came from each file
#   5. Prints a summary
#   6. Returns the combined DataFrame
# ============================================================================
function ingest_all(data_root::AbstractString)::DataFrame
    
    # Create an empty DataFrame with all the columns we want in the final output
    all_rows = DataFrame(
        P_nom_fc = Float64[],
        C_batt = Float64[],
        H2_cons = Float64[],
        SOC_end = Float64[],
        num_repl_FC = Int[],
        num_repl_batt = Int[],
        source_file = String[],
        sheet_name = String[],
        explicit_param = String[],
        explicit_value = Float64[],
        row_idx = Int[],
        seed = UInt32[],
    )
    
    # Find all Excel files in the data folder
    files = find_excel_files(data_root)
    
    # Dictionary to track how many rows come from each file
    stats = Dict{String, NamedTuple}()
    
    # Shared counter for unique row IDs across all files
    global_row_idx = Ref{Int}(0)
    
    # Loop through each Excel file
    for filepath in files
        
        # Get just the filename (without folder path)
        filename = basename(filepath)
        
        # Determine which parameter varies in this file (e.g., "n_stops")
        param_name = get_param_name(filepath)
        
        # Remember how many rows we have before this file
        rows_before = nrow(all_rows)
        
        try
            # Open the Excel file
            xf = XLSX.readxlsx(filepath)
            
            # Get list of all sheet names in this file
            sheet_names = XLSX.sheetnames(xf)
            
            # Loop through each sheet in this file
            for (sheet_idx, sn) in enumerate(sheet_names)
                
                # Skip sheets that start with "_" (these are metadata, not data)
                if startswith(sn, "_")
                    continue  # Skip to next sheet
                end
                
                # Process this sheet and get the extracted data
                sheet_df = process_sheet_via_readtable(filepath, sn, param_name, sheet_idx, global_row_idx)
                
                # If the sheet had valid data, append it to our combined DataFrame
                if nrow(sheet_df) > 0
                    append!(all_rows, sheet_df)
                end
            end
            
        catch e
            # If something goes wrong with this file, warn but continue with next
            @warn "Error processing file $filename: $e"
        end
        
        # Record how many rows were added from this file
        rows_after = nrow(all_rows)
        stats[filename] = (rows_added=rows_after - rows_before,)
    end
    
    # Print a summary of what was ingested
    total_rows = nrow(all_rows)
    println("\n=== Ingestion Summary ===")
    println("Total rows: $total_rows")
    println("\nBreakdown per source file:")
    for (fname, s) in sort(collect(stats))
        println("  $fname: $(s.rows_added) rows")
    end
    
    # Return the combined DataFrame with all data from all files
    return all_rows
end