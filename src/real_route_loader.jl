# ============================================================================
# real_route_loader.jl
#
# Loads real route profiles from CSV files in the info_tratta/ folder.
# Used by scripts/02_synthesize.jl to replace synthetic profiles with real
# measured data when the data is available.
#
# Expected folder structure:
#   info_tratta/
#     {LABEL}/
#       slope.csv    — single column "p": slope in permille, one row per meter
#       vlim.csv     — columns "start_km", "end_km", "v_kmh": speed limit segments
#       stops.csv    — single column "km": stop positions in km
#
# The LABEL must match the Excel sheet name in opt_results_real_routes.xlsx.
# To add a new route: create the folder and CSV files. No code changes needed.
# ============================================================================

using CSV
using DataFrames

# Returns true if a real profile folder exists for the given route label.
# label is the sheet_name value from raw_rows.csv (e.g. "LRL").
# info_tratta_dir is the absolute path to the info_tratta/ directory.
function has_real_route(info_tratta_dir::AbstractString, label::AbstractString)::Bool
    return isdir(joinpath(info_tratta_dir, label))
end

# Loads a complete real route profile from CSV files.
#
# INPUTS:
#   info_tratta_dir  — absolute path to the info_tratta/ directory
#   label            — route label matching the subfolder name, e.g. "LRL"
#
# OUTPUT:
#   NamedTuple with fields (L, p, vlim_segments, stops)
#   Same structure returned by synthesize_row() in profile_synth.jl.
function load_real_route(info_tratta_dir::AbstractString, label::AbstractString)::NamedTuple
    dir = joinpath(info_tratta_dir, label)

    # slope.csv: column "pendenza_permille" — slope in permille, one row per meter
    p = Float64.(CSV.read(joinpath(dir, "slope.csv"), DataFrame).pendenza_permille)

    # vlim.csv: columns start_km, end_km, v_max_kmh — one row per speed limit segment
    v_df = CSV.read(joinpath(dir, "vlim.csv"), DataFrame)
    vlim_segments = [(Float64(r.start_km), Float64(r.end_km), Float64(r.v_max_kmh))
                     for r in eachrow(v_df)]

    # stops.csv: column "fermata_km" — stop positions in km
    stops = Float64.(CSV.read(joinpath(dir, "stops.csv"), DataFrame).fermata_km)

    # Route length is derived from the end of the last speed-limit segment
    L = vlim_segments[end][2]

    # Sanity check: slope vector must have one entry per meter
    expected_len = round(Int, L * 1000) + 1
    if length(p) != expected_len
        @warn "Route $label: slope has $(length(p)) points, expected $expected_len for L=$(L) km. Continuing."
    end

    return (L=L, p=p, vlim_segments=vlim_segments, stops=stops)
end
