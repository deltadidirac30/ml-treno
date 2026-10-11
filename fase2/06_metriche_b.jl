# Fase 2: metriche (b), previsione + rifinitura NOMAD-PB con budget 20, 50, 100 (ripetizione 1), confrontate con la
# previsione secca (budget 0, stessa ripetizione) e con le campagne sulle 1024 tratte (NOMAD-PB, in media 972
# valutazioni; vecchio ottimizzatore) rispetto allo stesso riferimento (il migliore delle due campagne).
# Uso, da ml_treno/fase2:   julia --project=. 06_metriche_b.jl <insieme>
# Scrive risultati/metriche_b_<insieme>.csv e risultati/metriche_b_<insieme>.txt.

using CSV, DataFrames, Statistics, Printf
const INS = ARGS[1]
d = CSV.read(joinpath(@__DIR__, "..", "fase1", "dati", "dataset_doe.csv"), DataFrame)
ott = CSV.read(joinpath(@__DIR__, "..", "fase1", "dati", "ottimi_riferimento.csv"), DataFrame)
rif = CSV.read(joinpath(@__DIR__, "risultati", "rifinitura_$(INS).csv"), DataFrame)
sim = CSV.read(joinpath(@__DIR__, "risultati", "sim_cv.csv"), DataFrame)
vero = Dict(zip(d.tratta, zip(d.y_costo_EUR_km, d.y_ibrido)))

rif.y_costo = [vero[t][1] for t in rif.tratta]; rif.y_ibrido = [vero[t][2] for t in rif.tratta]
rif.rimpianto = (rif.costo .- rif.y_costo) ./ rif.y_costo
rif.ibrido_fin = rif.m .> 0
secca = sim[(sim.rip .== 1) .& (sim.insieme .== INS) .& in.(sim.modello, Ref(Set(unique(rif.modello)))), :]
tab = DataFrame()
q(v, p) = isempty(v) ? NaN : quantile(v, p)
function riga!(nome, budget, regime, fatt, rimp, ibrido_fin, y_ibrido)
    rp = rimp[fatt]
    push!(tab, (partenza = nome, budget = budget, regime_vero = regime, n = length(fatt),
                non_fattibili_pct = 100mean(.!fatt), errore_regime_pct = 100mean(ibrido_fin .!= (y_ibrido .== 1)),
                rimpianto_mediana_pct = 100q(rp, 0.5), rimpianto_p90_pct = 100q(rp, 0.9), rimpianto_p95_pct = 100q(rp, 0.95),
                rimpianto_max_pct = isempty(rp) ? NaN : 100maximum(rp), entro_025_pct = 100mean(fatt .& (rimp .<= 0.0025)),
                meglio_del_riferimento = count(fatt .& (rimp .< -1e-12))))
end
regimi = (("tutte", x -> trues(length(x))), ("ibride", x -> x .== 1), ("sola_batteria", x -> x .== 0))
for mod in unique(rif.modello), (rn, rs) in regimi
    s = secca[secca.modello .== mod, :]; k = rs(s.y_ibrido)
    riga!(mod, 0, rn, s.fattibile[k], s.rimpianto[k], Bool.(s.ibrido_prev[k]), s.y_ibrido[k])
    for b in (20, 50, 100)
        r = rif[(rif.modello .== mod) .& (rif.budget .== b), :]; k = rs(r.y_ibrido)
        riga!(mod, b, rn, r.fattibile[k], r.rimpianto[k], r.ibrido_fin[k], r.y_ibrido[k])
    end
end
# campagne (tutte fattibili), stesso riferimento
yI = [vero[t][2] for t in ott.tratta]
for (nome, c, mcol) in (("campagna NOMAD-PB (972 val. in media)", ott.costo_nomad_rivalutato, ott.m_nomad),
                        ("campagna vecchio ottimizzatore", ott.costo_vecchio_rivalutato, ott.m_vecchio)), (rn, rs) in regimi
    k = rs(yI)
    riga!(nome, -1, rn, trues(count(k)), (c[k] .- ott.costo_star[k]) ./ ott.costo_star[k], mcol[k] .> 0, yI[k])
end
CSV.write(joinpath(@__DIR__, "risultati", "metriche_b_$(INS).csv"), tab)
open(joinpath(@__DIR__, "risultati", "metriche_b_$(INS).txt"), "w") do io
    for o in (stdout, io)
        println(o, "(b) previsione + rifinitura NOMAD-PB, insieme $INS, ripetizione 1 (budget 0 = previsione secca; -1 = campagna)")
        for r in eachrow(tab)
            @printf(o, "  %-38s budget %4d %-13s non fatt. %5.1f%% | err. regime %4.1f%% | rimpianto med %6.3f%% p90 %6.3f%% p95 %6.3f%% max %7.3f%% | ≤0,25%% e fattibili %5.1f%% | meglio del rif. %d\n",
                    r.partenza, r.budget, r.regime_vero, r.non_fattibili_pct, r.errore_regime_pct, r.rimpianto_mediana_pct, r.rimpianto_p90_pct,
                    r.rimpianto_p95_pct, r.rimpianto_max_pct, r.entro_025_pct, r.meglio_del_riferimento)
        end
    end
end
