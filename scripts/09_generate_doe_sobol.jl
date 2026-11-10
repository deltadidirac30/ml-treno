using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using JLD2

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
        println(io, "- Generatore: limiti del 10/11/2026 (DOEConfig), tratte con build_doe_route del preconfiguratore MATLAB (doe-matlab-v3)")
        c = DOEConfig()
        println(io, "- Lunghezza: `$(c.L_min)–$(c.L_max) km`")
        println(io, "- Pendenza media: `±$(c.slope_mean_abs_max) ‰`, deviazione standard `0–$(c.slope_std_max) ‰`, |pendenza| ≤ `$(c.slope_abs_limit) ‰`")
        println(io, "- Lunghezza media dei segmenti di pendenza: `$(c.slope_segment_mean_min_km)–$(c.slope_segment_mean_max_km) km` (log-uniforme), minimo `$(c.slope_segment_min_km) km`")
        println(io, "- Fermate: `0–$(c.stop_density_max)` per km, CV `0–$(c.stop_spacing_cv_max)`, distanza minima `$(c.stop_min_spacing_km) km`")
        println(io, "- Velocità massima: `$(first(c.speed_classes))–$(last(c.speed_classes)) km/h` a passi di `$(c.speed_step_kmh)`; limiti da `$(c.speed_min_kmh) km/h`")
        println(io, "- Indice di restrizione: `0–$(c.speed_restriction_max)` rispetto a `$(c.speed_min_kmh) km/h`; cambi di limite `0–$(c.speed_change_density_max)` per km; tratto minimo `$(c.speed_min_segment_km) km`")
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

    _write_metadata(
        metadata_path;
        n,
        start_index,
        seed,
        profiles_generated=materialize_profiles,
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
