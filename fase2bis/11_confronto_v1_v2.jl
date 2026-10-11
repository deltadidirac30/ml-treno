# Fase 2bis, passo 11: tabella v1 contro v2 delle metriche principali (stessi fold, stesse impostazioni).
# v1 = fase2/risultati (riferimento congelato), v2 = fase2bis/risultati (riferimento v2).
# Uso, da ml_treno/fase2bis:   julia --project=. 11_confronto_v1_v2.jl. Scrive risultati/confronto_v1_v2.csv e .md.
using CSV, DataFrames, Printf
leggi(v, f) = CSV.read(joinpath(@__DIR__, "..", v == "v1" ? "fase2" : "fase2bis", "risultati", f), DataFrame)
tab = DataFrame(metrica = String[], v1 = Float64[], v2 = Float64[])
function val(v, f, filtro, col)
    d = leggi(v, f); k = findall(filtro(d))
    length(k) == 1 || return NaN
    return Float64(d[k[1], col])
end
agg!(nome, f, filtro, col) = push!(tab, (nome, val("v1", f, filtro, col), val("v2", f, filtro, col)))
for ins in ("p69", "p66"), (rn, rl) in (("tutte", ""), ("ibride", " (ibride)"), ("sola_batteria", " (sola batteria)"))
    fa(d) = (d.insieme .== ins) .& (d.modello .== "gb") .& (d.regime_vero .== rn)
    rn == "tutte" && agg!("gb $ins secca: errore di regime %", "metriche_a.csv", fa, :errore_regime_pct)
    agg!("gb $ins secca: non fattibili %$rl", "metriche_a.csv", fa, :non_fattibili_pct)
    agg!("gb $ins secca: rimpianto mediana %$rl", "metriche_a.csv", fa, :rimpianto_mediana_pct)
    agg!("gb $ins secca: rimpianto p95 %$rl", "metriche_a.csv", fa, :rimpianto_p95_pct)
end
for b in (50, 100, 200), (rn, rl) in (("tutte", ""), ("ibride", " (ibride)"), ("sola_batteria", " (sola batteria)"))
    fb(d) = (d.partenza .== "gb") .& (d.budget .== b) .& (d.regime_vero .== rn)
    for (col, lab) in ((:non_fattibili_pct, "non fattibili %"), (:rimpianto_mediana_pct, "rimpianto mediana %"),
                       (:rimpianto_p95_pct, "rimpianto p95 %"), (:entro_025_pct, "entro 0,25% e fattibili %"))
        (rn != "tutte" && col in (:non_fattibili_pct, :entro_025_pct)) && continue
        agg!("gb p69 + NOMAD-PB $b: $lab$rl", "metriche_b_p69.csv", fb, col)
    end
end
for (nome, lab) in (("campagna NOMAD-PB (972 val. in media)", "campagna NOMAD-PB"), ("campagna vecchio ottimizzatore", "campagna vecchio ottimizzatore"))
    fc(d) = (d.partenza .== nome) .& (d.regime_vero .== "tutte")
    agg!("$lab: rimpianto mediana %", "metriche_b_p69.csv", fc, :rimpianto_mediana_pct)
    agg!("$lab: rimpianto p95 %", "metriche_b_p69.csv", fc, :rimpianto_p95_pct)
end
for ins in ("p69", "p66"), fam in ("gp", "nn", "gb")
    fk(d) = (d.insieme .== ins) .& (d.modello .== fam) .& (d.regime_vero .== "tutte")
    agg!("costo diretto $fam $ins: |errore| mediana %", "metriche_c.csv", fk, :err_mediana_pct)
    agg!("costo diretto $fam $ins: |errore| p95 %", "metriche_c.csv", fk, :err_p95_pct)
end
for g in ("H2_viaggio_kg", "vita_FC_ore", "E_ricarica_viaggio_kWh")
    ff(d) = (d.grandezza .== g) .& (d.insieme .== "p69") .& (d.famiglia .== "gb")
    agg!("$g gb p69: |errore| mediana %", "metriche_fisiche.csv", ff, :err_mediana_pct)
end
CSV.write(joinpath(@__DIR__, "risultati", "confronto_v1_v2.csv"), tab)
f(x) = isnan(x) ? "—" : @sprintf("%.2f", x)
open(joinpath(@__DIR__, "risultati", "confronto_v1_v2.md"), "w") do io
    for o in (stdout, io)
        println(o, "| metrica | v1 | v2 |\n|---|---:|---:|")
        for r in eachrow(tab); println(o, "| ", r.metrica, " | ", f(r.v1), " | ", f(r.v2), " |"); end
    end
end
