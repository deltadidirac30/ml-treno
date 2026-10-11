# Fase 2: sensibilità al riferimento. "Miglior noto" = costo fattibile minimo per tratta tra il riferimento congelato
# (fase1/dati/ottimi_riferimento.csv) e tutti i punti fattibili valutati in fase 2 (previsioni secche di sim_cv.csv e
# rifiniture). Il riferimento congelato NON cambia; qui si ricalcolano le metriche principali contro il miglior noto.
# Uso: julia --project=. 07_riferimento_noto.jl. Scrive risultati/riferimento_noto.csv e risultati/sensibilita_riferimento.txt.
using CSV, DataFrames, Statistics, Printf
d = CSV.read("../fase1/dati/dataset_doe.csv", DataFrame)
sim = CSV.read("risultati/sim_cv.csv", DataFrame); rif = CSV.read("risultati/rifinitura_p69.csv", DataFrame)
best = Dict(zip(d.tratta, d.y_costo_EUR_km)); fonte = Dict(t => "riferimento" for t in d.tratta)
for (t, c, f, s) in vcat(collect(zip(sim.tratta, sim.costo, sim.fattibile, fill("previsione", nrow(sim)))),
                         collect(zip(rif.tratta, rif.costo, rif.fattibile, fill("rifinitura", nrow(rif)))))
    f && c < best[t] && (best[t] = c; fonte[t] = s)
end
rn = DataFrame(tratta = d.tratta, costo_riferimento = d.y_costo_EUR_km, costo_miglior_noto = [best[t] for t in d.tratta],
               fonte = [fonte[t] for t in d.tratta])
rn.miglioramento_pct = 100 .* (rn.costo_riferimento .- rn.costo_miglior_noto) ./ rn.costo_riferimento
CSV.write("risultati/riferimento_noto.csv", rn)
open("risultati/sensibilita_riferimento.txt", "w") do io
  for o in (stdout, io)
    m = rn.miglioramento_pct
    @printf(o, "miglior noto < riferimento in %d tratte; > 0,1%%: %d; > 1%%: %d; massimo %.2f%%\n", count(m .> 1e-10), count(m .> 0.1), count(m .> 1), maximum(m))
    B = Dict(zip(rn.tratta, rn.costo_miglior_noto)); R = Dict(zip(rn.tratta, rn.costo_riferimento))
    function riga(nome, t, c, f)
        for (lab, ref) in (("rif. congelato", R), ("miglior noto  ", B))
            r = [(c[i] - ref[t[i]]) / ref[t[i]] for i in eachindex(t) if f[i]]
            @printf(o, "  %-34s %s: non fatt. %5.1f%% | rimpianto med %6.3f%% p90 %6.3f%% p95 %6.3f%% max %6.2f%% | ≤0,25%% e fatt. %5.1f%%\n",
                    nome, lab, 100mean(.!f), 100median(r), 100quantile(r, 0.9), 100quantile(r, 0.95), 100maximum(r), 100count(<=(0.0025), r) / length(f))
        end
    end
    s = sim[(sim.modello .== "gb") .& (sim.insieme .== "p69"), :]; riga("gb p69 secca (5 rip.)", s.tratta, s.costo, s.fattibile)
    for b in (20, 50, 100), mod in ("gb", "mediana+gb", "nulla")
        s = rif[(rif.modello .== mod) .& (rif.budget .== b), :]; riga("$mod + NOMAD-PB $b", s.tratta, s.costo, s.fattibile)
    end
    o2 = CSV.read("../fase1/dati/ottimi_riferimento.csv", DataFrame)
    riga("campagna NOMAD-PB (972 val.)", o2.tratta, o2.costo_nomad_rivalutato, trues(nrow(o2)))
    riga("campagna vecchio ottimizzatore", o2.tratta, o2.costo_vecchio_rivalutato, trues(nrow(o2)))
  end
end
