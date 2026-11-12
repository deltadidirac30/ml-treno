using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using JLD2
using Statistics: median

include(joinpath(@__DIR__, "..", "src", "doe_generator.jl"))
using .DOEGenerator

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_DIR =
    joinpath(PROJECT_ROOT, "data_generated", "doe_sobol")

function _block_label(start_index::Int, n::Int)
    last_index = start_index + n - 1
    return lpad(start_index, 6, '0') * "_" * lpad(last_index, 6, '0')
end

function _write_metadata(
    path::AbstractString;
    n::Int,
    start_index::Int,
    seed::Int,
    profiles_generated::Bool,
    stats=nothing,
)
    last_index = start_index + n - 1
    open(path, "w") do io
        println(io, "# Blocco DoE Sobol scrambled")
        println(io)
        println(io, "- Metodo: Sobol base 2 con scramble binario e digital shift")
        println(io, "- Seed globale: `$seed`")
        println(io, "- Primo `route_id`: `$start_index`")
        println(io, "- Ultimo `route_id`: `$last_index`")
        println(io, "- Numero di tratte: `$n`")
        println(io, "- Profili completi generati: `$profiles_generated`")
        println(io, "- Generatore: limiti del 10/11/2026 rivisti l'11/11/2026 (DOEConfig), tratte con build_doe_route del preconfiguratore MATLAB (doe-matlab-v3)")
        c = DOEConfig()
        println(io, "- Lunghezza: `$(c.L_min)–$(c.L_max) km`")
        println(io, "- Pendenza media: `±$(c.slope_mean_abs_max) ‰`, deviazione standard `0–$(c.slope_std_max) ‰`, |pendenza| ≤ `$(c.slope_abs_limit) ‰`")
        println(io, "- Lunghezza media dei segmenti di pendenza: `$(c.slope_segment_mean_min_km)–$(c.slope_segment_mean_max_km) km` (log-uniforme), minimo `$(c.slope_segment_min_km) km`")
        println(io, "- Fermate di sola andata: al più `$(c.stop_count_max)` e `$(c.stop_density_max)` per km, capolinea compresi (n_stops = round(u₅·n_max(L)), uniforme tra 0 e n_max); CV `0–$(c.stop_spacing_cv_max)`, distanza minima `$(c.stop_min_spacing_km) km`; senza fermate il `$(round(Int, 100c.no_stops_fraction))%`")
        println(io, "- Velocità massima: `$(first(c.speed_classes))–$(last(c.speed_classes)) km/h` a passi di `$(c.speed_step_kmh)`; limiti da `$(c.speed_min_kmh) km/h`")
        println(io, "- Indice di restrizione: `0–$(c.speed_restriction_max)` rispetto a `$(c.speed_min_kmh) km/h`; cambi di limite `0–$(c.speed_change_density_max)` per km; tratto minimo `$(c.speed_min_segment_km) km`")
        println(io, "- Andata e ritorno simulata entro `$(c.round_trip_max_h) h`: stima della durata (soste `$(c.dwell_s) s`, capolinea `$(c.terminus_s) s`, alpha `$(c.duration_alpha)`, kappa `$(c.duration_kappa_s_per_ms) s per m/s`, margine `$(c.duration_margin)`); oltre, L si accorcia con gli stessi fattori unitari")
        if stats !== nothing
            println(io)
            println(io, "## Statistiche del blocco")
            println(io)
            for (k, v) in stats
                println(io, "- ", k, ": ", v)
            end
        end
        println(io)
        println(
            io,
            "Per estendere il DoE non modificare il seed e usare come ",
            "`start_index` il valore `$(last_index + 1)`.",
        )
    end
end

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 256
    start_index = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1
    seed = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 20260723
    output_dir =
        length(ARGS) >= 4 ? abspath(ARGS[4]) : DEFAULT_OUTPUT_DIR
    materialize_profiles =
        length(ARGS) >= 5 ? parse(Bool, ARGS[5]) : false

    n > 0 || error("n must be positive")
    start_index > 0 || error("start_index must be positive")
    seed >= 0 || error("seed must be non-negative")
    mkpath(output_dir)

    config = DOEConfig()
    design = sample_doe_sobol(n; start_index, seed, config)
    last_index = start_index + n - 1
    label = _block_label(start_index, n)

    design_path = joinpath(output_dir, "design_$label.csv")
    unit_path = joinpath(output_dir, "unit_design_$label.csv")
    registry_path = joinpath(output_dir, "registry_$label.csv")
    metadata_path = joinpath(output_dir, "metadata_$label.md")

    design_df = DataFrame(design)
    CSV.write(design_path, design_df)

    unit_design = scrambled_sobol(
        n,
        9;
        seed,
        skip=start_index - 1,
    )
    unit_df = DataFrame(route_id=start_index:last_index)
    for column in 1:9
        unit_df[!, Symbol("u_$column")] = unit_design[:, column]
    end
    CSV.write(unit_path, unit_df)

    registry_df = DataFrame(
        route_id=start_index:last_index,
        status=fill("pending", n),
        assignee=fill("", n),
        result_path=fill("", n),
        notes=fill("", n),
    )
    CSV.write(registry_path, registry_df)

    if materialize_profiles
        profiles = Dict{Int,NamedTuple}()
        println("Generating $n complete route profiles...")
        for (position, row) in enumerate(design)
            profiles[row.route_id] = generate_route(row; config)
            position % 10 == 0 && println("  $position / $n")
        end
        JLD2.jldsave(
            joinpath(output_dir, "profiles_$label.jld2");
            compress=true,
            profile_data=profiles,
        )
    end

    accorciate = [r for r in design if r.shortened]
    stats = [
        "Fermate intermedie" => "massimo $(maximum(r.n_stops for r in design)), mediana $(median([r.n_stops for r in design])), senza fermate $(count(r -> r.n_stops == 0, design))",
        "Indice di restrizione" => "massimo $(round(maximum(r.speed_restriction_index for r in design); digits=4)), mediana $(round(median([r.speed_restriction_index for r in design]); digits=4))",
        "Lunghezza [km]" => "da $(round(minimum(r.L_km for r in design); digits=2)) a $(round(maximum(r.L_km for r in design); digits=2)), mediana $(round(median([r.L_km for r in design]); digits=2))",
        "Durata stimata dell'andata e ritorno [h]" => "massimo $(round(maximum(r.round_trip_estimate_h for r in design); digits=3)), mediana $(round(median([r.round_trip_estimate_h for r in design]); digits=3))",
        "Tratte accorciate" => "$(length(accorciate)) ($(round(100 * length(accorciate) / n; digits=2))%), L ridotta in mediana del $(isempty(accorciate) ? 0 : round(100 * median([1 - r.L_km / r.L_km_requested for r in accorciate]); digits=1))%",
        "Pianeggianti, senza fermate, a velocità costante" => "$(count(r -> r.is_flat, design)), $(count(r -> r.no_stops, design)), $(count(r -> r.constant_speed, design))",
    ]
    _write_metadata(
        metadata_path;
        n,
        start_index,
        seed,
        profiles_generated=materialize_profiles,
        stats,
    )

    # Internal extension check: generating the same global prefix in one call
    # must reproduce this independently requested block exactly.
    full_prefix = sample_doe_sobol(last_index; seed, config)
    full_prefix[start_index:last_index] == design ||
        error("Sobol extension check failed")

    println("Generated routes $start_index:$last_index with seed $seed.")
    println("Design: $design_path")
    println("Registry: $registry_path")
end

main()
