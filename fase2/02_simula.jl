# Fase 2, passo 2: il simulatore nel punto previsto (metrica a) e il costo previsto direttamente (metrica c).
#
# Modelli (catene regime → m, n):
#   nulla        regime maggioritario del training (ibrido) e mediane di (m*, n*) del training per quel regime
#   mediana+gb   regime dal classificatore gb, (m, n) = mediane del training per il regime previsto
#   nn1          ottimo della tratta di training più simile (caratteristiche standardizzate)
#   knn          k-NN (k scelto nella CV interna) per regime, m e n
#   rf, gb       foresta casuale, boosting
# Punto previsto: regime ibrido se p_ibrido ≥ 0,5; m = clamp(m̂, 0,03, 1) se ibrido, 0 altrimenti;
# n = clamp(n̂ del regime previsto, 0,005, 1). Simulatore: valuta_progetto, modello corretta, config di default.
#
# Uso, da ml_treno/fase2 (dopo 01_cv.jl):   julia -t 8 --project=. 02_simula.jl
# Scrive risultati/sim_cv.csv (una riga per ripetizione, insieme, modello, tratta), risultati/metriche_a.csv,
# risultati/metriche_c.csv, risultati/metriche.txt.

include(joinpath(@__DIR__, "comune.jl"))
using TrainPowertrain
include(joinpath(@__DIR__, "simulatore.jl"))

d = dati()
const MODELLI = [("nulla", "mediana", "mediana"), ("mediana+gb", "gb", "mediana"), ("nn1", "nn1", "nn1"),
                 ("knn", "knn", "knn"), ("rf", "rf", "rf"), ("gb", "gb", "gb")]

pred = reduce(vcat, [CSV.read(joinpath(RIS, "cv", "pred_r$(r)_$(ins).csv"), DataFrame) for r in 1:NREP for ins in ("p66", "p69")])
righe = DataFrame()
for (nome, fcls, freg) in MODELLI
    pc = pred[pred.famiglia .== fcls, :]; pr = pred[pred.famiglia .== freg, :]
    pc.chiave = string.(pc.rip, "|", pc.insieme, "|", pc.tratta); pr.chiave = string.(pr.rip, "|", pr.insieme, "|", pr.tratta)
    j = innerjoin(select(pc, :chiave, :rip, :fold, :insieme, :tratta, :p_ibrido), select(pr, :chiave, :m_prev, :n_ibr_prev, :n_batt_prev), on = :chiave)
    reg = j.p_ibrido .>= 0.5
    append!(righe, DataFrame(rip = j.rip, fold = j.fold, insieme = j.insieme, modello = nome, tratta = j.tratta,
                             ibrido_prev = reg, m = ifelse.(reg, clamp.(j.m_prev, M_MIN, 1.0), 0.0),
                             n = clamp.(ifelse.(reg, j.n_ibr_prev, j.n_batt_prev), N_MIN, 1.0)))
end
println("punti da valutare: ", nrow(righe), " (unici ", length(unique(zip(righe.tratta, righe.m, righe.n))), ")")
t0 = time()
es = valuta_punti(righe.tratta, righe.m, righe.n)
@printf("valutazioni in %.0f s\n", time() - t0)
sim = hcat(righe, es)
leftjoin!(sim, select(d, :tratta, :y_ibrido, :y_m_star, :y_n_star, :y_costo_EUR_km), on = :tratta)
sim.rimpianto = (sim.costo .- sim.y_costo_EUR_km) ./ sim.y_costo_EUR_km
CSV.write(joinpath(RIS, "sim_cv.csv"), sim)

# ── metriche (a) ─────────────────────────────────────────────────────────────
out = open(joinpath(RIS, "metriche.txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))
q(v, p) = isempty(v) ? NaN : quantile(v, p)
function metriche(s)
    f = s.fattibile; rp = s.rimpianto[f]
    err = mean(Bool.(s.ibrido_prev) .!= (s.y_ibrido .== 1))
    perrip = [mean(.!g.fattibile) for g in groupby(s, :rip)]
    medrip = [median(g.rimpianto[g.fattibile]) for g in groupby(s, :rip) if any(g.fattibile)]
    return (n = nrow(s), errore_regime_pct = 100err,
            ibr_come_batt = count((s.y_ibrido .== 1) .& .!Bool.(s.ibrido_prev)), batt_come_ibr = count((s.y_ibrido .== 0) .& Bool.(s.ibrido_prev)),
            non_fattibili_pct = 100mean(.!f), nf_min_pct = 100minimum(perrip), nf_max_pct = 100maximum(perrip),
            nf_SOC_pct = 100mean(s.viol_SOC), nf_massa_pct = 100mean(s.viol_massa), nf_D3_pct = 100mean(s.viol_D3),
            nf_altro_pct = 100mean(s.viol_altro),
            rimpianto_mediana_pct = 100q(rp, 0.5), rimp_med_min = 100minimum(medrip), rimp_med_max = 100maximum(medrip),
            rimpianto_p90_pct = 100q(rp, 0.9), rimpianto_p95_pct = 100q(rp, 0.95), rimpianto_max_pct = isempty(rp) ? NaN : 100maximum(rp),
            entro_025_pct_dei_fattibili = 100mean(rp .<= 0.0025), utili_pct = 100mean(f .& (s.rimpianto .<= 0.0025)))
end
ma = DataFrame()
for g in groupby(sim, [:insieme, :modello], sort = false), (rnome, sel) in (("tutte", trues(nrow(g))), ("ibride", g.y_ibrido .== 1), ("sola_batteria", g.y_ibrido .== 0))
    push!(ma, merge((insieme = g.insieme[1], modello = g.modello[1], regime_vero = rnome), metriche(g[sel, :])))
end
CSV.write(joinpath(RIS, "metriche_a.csv"), ma)
say("(a) previsione secca, 5 ripetizioni × 1024 tratte (ogni tratta 5 volte); rimpianto sui fattibili; 'utili' = fattibili con rimpianto ≤ 0,25%")
for r in eachrow(ma)
    say(@sprintf("  %-4s %-11s %-13s err.regime %5.1f%% (I→B %3d, B→I %3d) | non fatt. %5.1f%% [%4.1f–%4.1f] SOC %5.1f massa %5.1f D3 %4.1f altro %3.1f | rimpianto med %6.3f%% [%5.3f–%5.3f] p90 %6.2f p95 %6.2f max %7.2f | ≤0,25%% %5.1f%% dei fatt., utili %5.1f%%",
                 r.insieme, r.modello, r.regime_vero, r.errore_regime_pct, r.ibr_come_batt, r.batt_come_ibr, r.non_fattibili_pct, r.nf_min_pct, r.nf_max_pct,
                 r.nf_SOC_pct, r.nf_massa_pct, r.nf_D3_pct, r.nf_altro_pct, r.rimpianto_mediana_pct, r.rimp_med_min, r.rimp_med_max,
                 r.rimpianto_p90_pct, r.rimpianto_p95_pct, r.rimpianto_max_pct, r.entro_025_pct_dei_fattibili, r.utili_pct))
end

# ── metriche (c): costo previsto direttamente ────────────────────────────────
pc = leftjoin(pred, select(d, :tratta, :y_ibrido, :y_costo_EUR_km), on = :tratta)
pc.err = pc.costo_prev ./ pc.y_costo_EUR_km .- 1
mc = DataFrame()
for g in groupby(pc, [:insieme, :famiglia], sort = false), (rnome, sel) in (("tutte", trues(nrow(g))), ("ibride", g.y_ibrido .== 1), ("sola_batteria", g.y_ibrido .== 0))
    e = abs.(g.err[sel])
    push!(mc, (insieme = g.insieme[1], modello = g.famiglia[1], regime_vero = rnome, n = length(e),
               err_mediana_pct = 100median(e), err_p95_pct = 100quantile(e, 0.95), err_max_pct = 100maximum(e),
               distorsione_mediana_pct = 100median(g.err[sel])))
end
CSV.write(joinpath(RIS, "metriche_c.csv"), mc)
say("\n(c) costo €/km previsto direttamente: |errore relativo|")
for r in eachrow(mc)
    say(@sprintf("  %-4s %-8s %-13s mediana %5.2f%%  p95 %6.2f%%  max %6.2f%%  (distorsione mediana %+5.2f%%)",
                 r.insieme, r.modello, r.regime_vero, r.err_mediana_pct, r.err_p95_pct, r.err_max_pct, r.distorsione_mediana_pct))
end
close(out)
