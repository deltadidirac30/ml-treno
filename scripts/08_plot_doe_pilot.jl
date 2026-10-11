using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using JLD2
using Plots

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const PILOT_DIR = joinpath(PROJECT_ROOT, "data_generated", "doe_pilot")
const REAL_DIR = joinpath(PROJECT_ROOT, "data_profiles", "real_routes")

function load_real_profile(route_id::Int)
    dir = joinpath(REAL_DIR, string(route_id))
    slope_df = CSV.read(joinpath(dir, "slope.csv"), DataFrame)
    stops_df = CSV.read(joinpath(dir, "stops.csv"), DataFrame)
    vlim_df = CSV.read(joinpath(dir, "vlim.csv"), DataFrame)

    segments = [
        (Float64(r.start_km), Float64(r.end_km), Float64(r.v_max_kmh))
        for r in eachrow(vlim_df)
        if Float64(r.end_km) > Float64(r.start_km)
    ]

    return (
        L=segments[end][2],
        p=Float64.(slope_df.pendenza_permille),
        stops=Float64.(stops_df.fermata_km),
        vlim_segments=segments,
    )
end

function speed_step(segments, L)
    x = Float64[]
    y = Float64[]
    for segment in segments
        append!(x, (segment[1] / L, segment[2] / L))
        append!(y, (segment[3], segment[3]))
    end
    return x, y
end

function closest_synthetic(design::DataFrame, reference, route_id::Int)
    columns = [
        :L_km,
        :slope_mean,
        :slope_std,
        :slope_segment_length_mean_km,
        :stop_density,
        :stop_spacing_cv,
        :v_max_kmh,
        :speed_restriction_index,
        :speed_change_density,
    ]
    scales = [185.0, 20.0, 8.0, 3.3, 0.32, 0.70, 80.0, 0.60, 0.15]
    target = [
        reference.L_actual_km,
        reference.slope_mean_actual,
        reference.slope_std_actual,
        reference.slope_segment_length_mean_actual_km,
        reference.stop_density_actual,
        reference.stop_spacing_cv_actual,
        reference.v_max_actual_kmh,
        reference.speed_restriction_actual,
        reference.speed_change_density_actual,
    ]

    best_id = 0
    best_distance = Inf
    for row in eachrow(design)
        reference.slope_std_actual < 1e-8 && !Bool(row.is_flat) && continue
        distance = 0.0
        for (j, column) in enumerate(columns)
            j == 4 && isnan(target[j]) && continue
            distance += ((Float64(row[column]) - target[j]) / scales[j])^2
        end
        if distance < best_distance
            best_distance = distance
            best_id = Int(row.route_id)
        end
    end
    return best_id
end

function plot_factor_coverage(design, references, output_path)
    definitions = [
        (:L_km, "L [km]", :auto),
        (:slope_mean, "μp [‰]", :auto),
        (:slope_std, "σp [‰]", :auto),
        (:slope_segment_length_mean_km, "L segmento medio [km]", :auto),
        (:stop_density, "Fermate/km", :auto),
        (:stop_spacing_cv, "CV distanze", :auto),
        (:v_max_kmh, "vmax [km/h]", 9),
        (:speed_restriction_index, "Indice rv", :auto),
        (:speed_change_density, "Cambi velocità/km", :auto),
    ]
    reference_columns = [
        :L_actual_km,
        :slope_mean_actual,
        :slope_std_actual,
        :slope_segment_length_mean_actual_km,
        :stop_density_actual,
        :stop_spacing_cv_actual,
        :v_max_actual_kmh,
        :speed_restriction_actual,
        :speed_change_density_actual,
    ]

    panels = Any[]
    for ((column, label, bins), reference_column) in
        zip(definitions, reference_columns)
        values = Float64.(design[!, column])
        panel = histogram(
            values;
            bins,
            xlabel=label,
            ylabel="N",
            legend=false,
            color=:steelblue,
            alpha=0.65,
            title="",
        )
        reference_values = filter(isfinite, Float64.(references[!, reference_column]))
        for value in reference_values
            vline!(panel, [value]; color=:red, linewidth=1.5, alpha=0.8)
        end
        push!(panels, panel)
    end

    figure = plot(panels...; layout=(3, 3), size=(1200, 850))
    savefig(figure, output_path)
end

function plot_reference_comparison(design, references, profiles, output_path)
    panels = Any[]

    for route_id in 1:3
        real_profile = load_real_profile(route_id)
        reference = references[route_id, :]
        synthetic_id = closest_synthetic(design, reference, route_id)
        synthetic = profiles[synthetic_id]

        real_stride = max(1, floor(Int, length(real_profile.p) / 2500))
        syn_stride = max(1, floor(Int, length(synthetic.p) / 2500))
        real_indices = 1:real_stride:length(real_profile.p)
        syn_indices = 1:syn_stride:length(synthetic.p)

        slope_panel = plot(
            (real_indices .- 1) ./ (length(real_profile.p) - 1),
            real_profile.p[real_indices];
            label="Reale $route_id",
            xlabel="x/L",
            ylabel="Pendenza [‰]",
            linewidth=1.5,
        )
        plot!(
            slope_panel,
            (syn_indices .- 1) ./ (length(synthetic.p) - 1),
            synthetic.p[syn_indices];
            label="Sintetica $synthetic_id",
            linewidth=1.2,
            alpha=0.8,
        )
        push!(panels, slope_panel)

        xr, yr = speed_step(real_profile.vlim_segments, real_profile.L)
        xs, ys = speed_step(synthetic.vlim_segments, synthetic.L)
        speed_panel = plot(
            xr,
            yr;
            label="Reale $route_id",
            xlabel="x/L",
            ylabel="Limite [km/h]",
            linewidth=2,
        )
        plot!(
            speed_panel,
            xs,
            ys;
            label="Sintetica $synthetic_id",
            linewidth=1.5,
            alpha=0.8,
        )
        scatter!(
            speed_panel,
            real_profile.stops ./ real_profile.L,
            fill(52.0, length(real_profile.stops));
            label="Fermate reali",
            marker=:diamond,
            markersize=3,
        )
        scatter!(
            speed_panel,
            synthetic.stops ./ synthetic.L,
            fill(57.0, length(synthetic.stops));
            label="Fermate sintetiche",
            marker=:circle,
            markersize=2.5,
        )
        ylims!(speed_panel, 45, 170)
        push!(panels, speed_panel)
    end

    figure = plot(panels...; layout=(3, 2), size=(1200, 1000))
    savefig(figure, output_path)
end

function main()
    design = CSV.read(joinpath(PILOT_DIR, "design.csv"), DataFrame)
    references = CSV.read(joinpath(PILOT_DIR, "reference_metrics.csv"), DataFrame)
    profiles = JLD2.load(joinpath(PILOT_DIR, "profiles.jld2"), "profile_data")

    plot_factor_coverage(
        design,
        references,
        joinpath(PILOT_DIR, "factor_coverage.png"),
    )
    plot_reference_comparison(
        design,
        references,
        profiles,
        joinpath(PILOT_DIR, "reference_comparison.png"),
    )
    println("Plots saved in $PILOT_DIR")
end

main()
