# ============================================================================
# 02_synthesize.jl: Load driving profiles from data_profiles/
#
# Replaces synthetic generation with real measured profiles.
# For each row in raw_rows.csv, looks up the matching profile folder based on
# (explicit_param, explicit_value) and reads slope.csv, vlim.csv, stops.csv.
#
# Mapping explicit_param → subfolder in data_profiles/:
#   "n_stops"        → sensitivity_stops/{value}/
#   "L_km"           → sensitivity_length/{value}/
#   "slope_permille" → sensitivity_slope/{value}/
#   "v_max_kmh"      → sensitivity_vel/{value}/
#   "template_id"    → real_routes/{value}/
#
# Subfolder name = string(Int(round(explicit_value)))  e.g. 50, 3, 10, 80, 1
#
# Each profile folder must contain:
#   slope.csv  — columns: posizione_m, pendenza_permille
#   vlim.csv   — columns: start_km, end_km, v_max_kmh
#   stops.csv  — column:  fermata_km
# ============================================================================

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

using CSV, DataFrames, JLD2

const PARAM_TO_SUBDIR = Dict(
    "n_stops"        => "sensitivity_stops",
    "L_km"           => "sensitivity_length",
    "slope_permille" => "sensitivity_slope",
    "v_max_kmh"      => "sensitivity_vel",
    "template_id"    => "real_routes",
)

function load_profile(profiles_root::String, explicit_param::String, explicit_value::Float64)::NamedTuple
    subdir   = PARAM_TO_SUBDIR[explicit_param]
    val_name = string(Int(round(explicit_value)))
    dir      = joinpath(profiles_root, subdir, val_name)

    if !isdir(dir)
        error("Profile folder not found: $dir\n  (param=$explicit_param, value=$explicit_value)")
    end

    p = Float64.(CSV.read(joinpath(dir, "slope.csv"), DataFrame).pendenza_permille)

    v_df = CSV.read(joinpath(dir, "vlim.csv"), DataFrame)
    vlim_segments = [(Float64(r.start_km), Float64(r.end_km), Float64(r.v_max_kmh))
                     for r in eachrow(v_df)]

    stops_df = CSV.read(joinpath(dir, "stops.csv"), DataFrame)
    stops    = nrow(stops_df) > 0 ? Float64.(stops_df.fermata_km) : Float64[]

    L = vlim_segments[end][2]

    expected_len = round(Int, L * 1000) + 1
    if abs(length(p) - expected_len) > 2
        @warn "Profile $subdir/$val_name: slope has $(length(p)) points, expected $expected_len for L=$(L) km."
    end

    return (L=L, p=p, vlim_segments=vlim_segments, stops=stops)
end

function main()
    raw_rows_path  = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")
    profiles_path  = joinpath(@__DIR__, "..", "data_generated", "profiles.jld2")
    profiles_root  = joinpath(@__DIR__, "..", "data_profiles")

    if !isfile(raw_rows_path)
        println("Error: raw_rows.csv not found. Run scripts/01_ingest.jl first.")
        exit(1)
    end

    df = CSV.read(raw_rows_path, DataFrame)
    N  = nrow(df)
    println("Loading profiles for $N rows from data_profiles/ ...")

    profile_data = Dict{Int, NamedTuple}()

    for row_idx in 1:N
        row = df[row_idx, :]
        profile_data[row_idx] = load_profile(profiles_root,
                                              String(row.explicit_param),
                                              Float64(row.explicit_value))
        row_idx % 500 == 0 && println("  $row_idx / $N")
    end

    JLD2.save(profiles_path, "profile_data", profile_data)
    println("\nSaved $N profiles → $profiles_path")
end

main()
