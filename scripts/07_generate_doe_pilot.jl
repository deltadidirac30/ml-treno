using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using JLD2
using Statistics

include(joinpath(@__DIR__, "..", "src", "doe_generator.jl"))
using .DOEGenerator

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const REAL_ROUTES_DIR = joinpath(PROJECT_ROOT, "data_profiles", "real_routes")
const DEFAULT_OUTPUT_DIR = joinpath(PROJECT_ROOT, "data_generated", "doe_pilot")

function load_real_profile(route_id::Int)
    dir = joinpath(REAL_ROUTES_DIR, string(route_id))

    slope_df = CSV.read(joinpath(dir, "slope.csv"), DataFrame)
    p = Float64.(slope_df.pendenza_permille)

    stops_df = CSV.read(joinpath(dir, "stops.csv"), DataFrame)
    stops = Float64.(stops_df.fermata_km)

    vlim_df = CSV.read(joinpath(dir, "vlim.csv"), DataFrame)
    segments = Tuple{Float64,Float64,Float64}[]
    for row in eachrow(vlim_df)
        start_km = Float64(row.start_km)
        end_km = Float64(row.end_km)
        end_km > start_km || continue
        push!(segments, (start_km, end_km, Float64(row.v_max_kmh)))
    end

    L = segments[end][2]
    return (L=L, p=p, vlim_segments=segments, stops=stops)
end

function reference_metrics(config::DOEConfig)
    rows = NamedTuple[]
    for route_id in 1:3
        profile = load_real_profile(route_id)
        metrics = profile_metrics(profile; config)
        push!(rows, merge((route_id=route_id,), metrics))
    end
    return DataFrame(rows)
end

function validation_row(row, metrics, config::DOEConfig)
    slope_mean_error = abs(metrics.slope_mean_actual - row.slope_mean)
    slope_std_relative_error = row.slope_std > 1e-8 ?
        abs(metrics.slope_std_actual - row.slope_std) / row.slope_std :
        abs(metrics.slope_std_actual)

    if row.is_flat || row.slope_std <= 1e-10
        slope_segment_mean_relative_error = 0.0
        slope_segment_mean_pass = true
        slope_segment_minimum_pass = true
    else
        slope_segment_mean_relative_error = abs(
            metrics.slope_segment_length_mean_actual_km -
            row.slope_segment_length_mean_km,
        ) / row.slope_segment_length_mean_km
        slope_segment_mean_pass =
            slope_segment_mean_relative_error <= 0.15
        slope_segment_minimum_pass =
            metrics.slope_segment_length_min_actual_km >=
            config.slope_segment_min_km - 1e-8
    end

    if row.n_stops >= 2 && row.stop_spacing_cv > 1e-6
        stop_cv_relative_error =
            abs(metrics.stop_spacing_cv_actual - row.stop_spacing_cv) /
            row.stop_spacing_cv
        stop_cv_pass = stop_cv_relative_error <= 0.20
    else
        stop_cv_relative_error =
            abs(metrics.stop_spacing_cv_actual - row.stop_spacing_cv)
        stop_cv_pass = true
    end

    target_vmean = row.v_max_kmh -
        row.speed_restriction_index *
        (row.v_max_kmh - config.speed_min_kmh)
    speed_mean_error = abs(metrics.v_mean_actual_kmh - target_vmean)

    checks = (
        length_pass=abs(metrics.L_actual_km - row.L_km) <= 0.0005,
        slope_mean_pass=slope_mean_error <= 0.10,
        slope_std_pass=slope_std_relative_error <= 0.05,
        slope_segment_mean_pass=slope_segment_mean_pass,
        slope_segment_minimum_pass=slope_segment_minimum_pass,
        slope_bounds_pass=
            metrics.slope_min_actual >= -config.slope_abs_limit - 1e-8 &&
            metrics.slope_max_actual <= config.slope_abs_limit + 1e-8,
        stops_count_pass=metrics.n_stops_actual == row.n_stops,
        stop_cv_pass=stop_cv_pass,
        stop_spacing_pass=
            metrics.stop_min_spacing_actual >=
            config.stop_min_spacing_km - 1e-8,
        vmax_pass=metrics.v_max_actual_kmh == row.v_max_kmh,
        speed_mean_pass=speed_mean_error <= 5.0,
        speed_changes_pass=
            abs(metrics.n_vlim_segments_actual - row.n_vlim_segments) <= 1,
        speed_segment_pass=
            metrics.speed_min_segment_actual >=
            config.speed_min_segment_km - 1e-8,
    )

    return merge(
        (
            route_id=row.route_id,
            slope_mean_error=slope_mean_error,
            slope_std_relative_error=slope_std_relative_error,
            slope_segment_mean_relative_error=
                slope_segment_mean_relative_error,
            stop_cv_relative_error=stop_cv_relative_error,
            target_vmean_kmh=target_vmean,
            speed_mean_error_kmh=speed_mean_error,
        ),
        checks,
        (overall_pass=all(values(checks)),),
    )
end

function write_summary(
    path::AbstractString,
    design_df::DataFrame,
    metrics_df::DataFrame,
    validation_df::DataFrame,
    reference_df::DataFrame,
)
    check_columns = filter(name -> endswith(name, "_pass"), names(validation_df))

    open(path, "w") do io
        println(io, "# Report DoE pilota")
        println(io)
        println(io, "- Tratte sintetiche: $(nrow(design_df))")
        println(
            io,
            "- Profili completamente conformi: ",
            count(identity, validation_df.overall_pass),
            "/",
            nrow(validation_df),
        )
        println(io)

        println(io, "## Esito dei controlli")
        println(io)
        println(io, "| Controllo | Superati | Falliti |")
        println(io, "|---|---:|---:|")
        for column in check_columns
            passed = count(identity, validation_df[!, column])
            println(io, "| `$column` | $passed | $(nrow(validation_df)-passed) |")
        end
        println(io)

        println(io, "## Copertura dei fattori")
        println(io)
        println(io, "| Fattore | Minimo | Massimo |")
        println(io, "|---|---:|---:|")
        for column in [
            "L_km",
            "slope_mean",
            "slope_std",
            "slope_segment_length_mean_km",
            "stop_density",
            "stop_spacing_cv",
            "v_max_kmh",
            "speed_restriction_index",
            "speed_change_density",
        ]
            values_col = Float64.(design_df[!, column])
            println(
                io,
                "| `$column` | ",
                round(minimum(values_col); digits=4),
                " | ",
                round(maximum(values_col); digits=4),
                " |",
            )
        end
        println(io)

        println(io, "## Confronto con le tre tratte reali")
        println(io)
        println(
            io,
            "| Tratta | L [km] | μp [‰] | σp [‰] | ℓp [km] | ",
            "stop/km | CV stop | vmax | rv | cambi/km |",
        )
        println(io, "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in eachrow(reference_df)
            println(
                io,
                "| $(row.route_id) | ",
                "$(round(row.L_actual_km; digits=3)) | ",
                "$(round(row.slope_mean_actual; digits=3)) | ",
                "$(round(row.slope_std_actual; digits=3)) | ",
                "$(round(row.slope_segment_length_mean_actual_km; digits=3)) | ",
                "$(round(row.stop_density_actual; digits=4)) | ",
                "$(round(row.stop_spacing_cv_actual; digits=3)) | ",
                "$(round(row.v_max_actual_kmh; digits=1)) | ",
                "$(round(row.speed_restriction_actual; digits=3)) | ",
                "$(round(row.speed_change_density_actual; digits=4)) |",
            )
        end
        println(io)

        println(io, "## Errori massimi osservati")
        println(io)
        println(
            io,
            "- Errore massimo media pendenza: ",
            round(maximum(validation_df.slope_mean_error); digits=6),
            "‰",
        )
        println(
            io,
            "- Errore relativo massimo deviazione pendenza: ",
            round(maximum(validation_df.slope_std_relative_error); digits=6),
        )
        println(
            io,
            "- Errore relativo massimo lunghezza media segmenti: ",
            round(
                maximum(
                    validation_df.slope_segment_mean_relative_error,
                );
                digits=6,
            ),
        )
        println(
            io,
            "- Errore massimo velocità media: ",
            round(maximum(validation_df.speed_mean_error_kmh); digits=3),
            " km/h",
        )
        println(io)

        println(io, "## File prodotti")
        println(io)
        println(io, "- `design.csv`: parametri richiesti dal DoE")
        println(io, "- `metrics.csv`: parametri misurati sui profili generati")
        println(io, "- `validation.csv`: errori e controlli di accettazione")
        println(io, "- `reference_metrics.csv`: metriche delle tre tratte reali")
        println(io, "- `profiles.jld2`: profili completi del pilota")
        println(io, "- `factor_coverage.png`: copertura dei nove fattori")
        println(io, "- `reference_comparison.png`: confronto con le tratte reali")
    end
end

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 60
    seed = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 20260723
    output_dir = length(ARGS) >= 3 ? abspath(ARGS[3]) : DEFAULT_OUTPUT_DIR
    mkpath(output_dir)

    config = DOEConfig()
    design = sample_doe(n; seed, config)
    design_df = DataFrame(design)
    CSV.write(joinpath(output_dir, "design.csv"), design_df)

    profiles = Dict{Int,NamedTuple}()
    metric_rows = NamedTuple[]
    validation_rows = NamedTuple[]

    println("Generating $n pilot routes...")
    for (index, row) in enumerate(design)
        profile = generate_route(row; config)
        metrics = profile_metrics(profile; config)
        profiles[row.route_id] = profile
        push!(metric_rows, merge((route_id=row.route_id,), metrics))
        push!(validation_rows, validation_row(row, metrics, config))
        index % 10 == 0 && println("  $index / $n")
    end

    metrics_df = DataFrame(metric_rows)
    validation_df = DataFrame(validation_rows)
    reference_df = reference_metrics(config)

    CSV.write(joinpath(output_dir, "metrics.csv"), metrics_df)
    CSV.write(joinpath(output_dir, "validation.csv"), validation_df)
    CSV.write(joinpath(output_dir, "reference_metrics.csv"), reference_df)
    JLD2.jldsave(
        joinpath(output_dir, "profiles.jld2");
        compress=true,
        profile_data=profiles,
    )

    write_summary(
        joinpath(output_dir, "pilot_report.md"),
        design_df,
        metrics_df,
        validation_df,
        reference_df,
    )

    passed = count(identity, validation_df.overall_pass)
    println("Pilot completed: $passed / $n routes passed all checks.")
    println("Outputs: $output_dir")
end

main()
