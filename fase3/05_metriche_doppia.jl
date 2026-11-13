# Fase 3: metriche della doppia partenza (da 04_doppia_partenza.jl), sulle 1024 tratte DoE v2, ripetizione 1.
# Strategie, per insieme (p69, p66) e soglia di incertezza (0,05–0,95; 0,1–0,9; 0,2–0,8):
#   singola 200          S200 su tutte le tratte;
#   doppia 200 + 200     nelle tratte incerte il migliore tra S200 e A200, altrove S200;
#   doppia 100 + 100     nelle tratte incerte il migliore tra S100 e A100 (stesso budget della singola), altrove S200.
# "Migliore" = fattibile di costo minimo, altrimenti costo minimo (regola di _risultato). Rimpianto contro il
# riferimento v2. Categorie: totale, vicino a m_min (ibride v2 con 0,03 ≤ m* < 0,04), tratte che attivano la doppia.
# Costo: valutazioni e secondi per tratta (somma dei lanci; processo a un thread, 8 processi in parallelo), contro la
# campagna NOMAD-PB completa (conclusi.csv per le valutazioni; registro.csv per i secondi di valutazione per tratta;
# runner.log per il tempo di parete).
# Uso, da ml_treno/fase3:   julia --project=. 05_metriche_doppia.jl
# Scrive risultati/doppia_metriche.csv e risultati/doppia_metriche.txt.
using CSV, DataFrames, Statistics, Printf
const C = "/Users/kairos/Documents/lavoro/train-powertrain/campagne/2026-10-08_ottimizza_ar_1024tratte"
d = CSV.read(joinpath(@__DIR__, "..", "fase2bis", "dati", "dataset_doe_v2.csv"), DataFrame)
Y = Dict(zip(d.tratta, d.y_costo_EUR_km)); I = Dict(zip(d.tratta, d.y_ibrido .== 1))
MMIN = Set(d.tratta[(d.y_ibrido .== 1) .& (d.y_m_star .< 0.04)])
l = CSV.read(joinpath(@__DIR__, "risultati", "doppia_lanci.csv"), DataFrame)
P = Dict(ins => (p = CSV.read("/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis/cv/pred_r1_$(ins).csv", DataFrame);
                 p = p[p.famiglia .== "gb", :]; Dict(zip(p.tratta, p.p_ibrido))) for ins in ("p69", "p66"))

# controllo: S200 p69 contro la rifinitura gb budget 200 della fase 2bis
r2 = CSV.read(joinpath(@__DIR__, "..", "fase2bis", "risultati", "rifinitura_p69.csv"), DataFrame); r2 = r2[r2.budget .== 200, :]
R2 = Dict(zip(r2.tratta, r2.costo)); s = l[(l.insieme .== "p69") .& (l.lancio .== "S200"), :]
diversi = count(r -> r.costo != R2[r.tratta], eachrow(s))

migliore(rs) = (f = filter(x -> x.fattibile, rs); isempty(f) ? rs[argmin([x.costo for x in rs])] : f[argmin([x.costo for x in f])])
camp = CSV.read(joinpath(C, "conclusi.csv"), DataFrame)
reg = CSV.read(joinpath(C, "registro.csv"), DataFrame; select = [:tratta, :tempo_s])
sec_camp = combine(groupby(reg, :tratta), :tempo_s => sum => :s, nrow => :n)

tab = DataFrame()
q(v, p) = isempty(v) ? NaN : quantile(v, p)
for ins in ("p69", "p66"), (lo, hi) in ((0.05, 0.95), (0.1, 0.9), (0.2, 0.8)), strat in ("singola 200", "doppia 200+200", "doppia 100+100")
    li = l[l.insieme .== ins, :]; G = Dict(k.tratta => collect(eachrow(g)) for (k, g) in pairs(groupby(li, :tratta)))
    fin = DataFrame()
    for (t, rs) in G
        inc = lo < P[ins][t] < hi
        L(n) = only(filter(x -> x.lancio == n, rs))
        sel = strat == "singola 200" || !inc ? [L("S200")] : strat == "doppia 200+200" ? [L("S200"), L("A200")] : [L("S100"), L("A100")]
        b = migliore(sel)
        push!(fin, (tratta = t, incerta = inc, fattibile = b.fattibile, rimpianto = (b.costo - Y[t]) / Y[t], ibrido_fin = b.m > 0,
                    valutazioni = sum(x.valutazioni for x in sel), secondi = sum(x.secondi for x in sel)))
    end
    for (cat, f) in (("totale", x -> trues(nrow(x))), ("vicino a m_min", x -> in.(x.tratta, Ref(MMIN))), ("tratte incerte", x -> x.incerta))
        x = fin[f(fin), :]; nrow(x) == 0 && continue
        rp = x.rimpianto[x.fattibile]
        push!(tab, (insieme = ins, soglia = "$(lo)–$(hi)", strategia = strat, categoria = cat, tratte = nrow(x), attivate = count(x.incerta),
                    non_fattibili_pct = 100mean(.!x.fattibile), errore_regime_pct = 100mean(x.ibrido_fin .!= [I[t] for t in x.tratta]),
                    rimpianto_mediana_pct = 100q(rp, 0.5), rimpianto_p95_pct = 100q(rp, 0.95), rimpianto_max_pct = isempty(rp) ? NaN : 100maximum(rp),
                    entro_025_pct = 100mean(x.fattibile .& (x.rimpianto .<= 0.0025)),
                    valutazioni_medie = mean(x.valutazioni), secondi_medi = mean(x.secondi)))
    end
end
CSV.write(joinpath(@__DIR__, "risultati", "doppia_metriche.csv"), tab)
open(joinpath(@__DIR__, "risultati", "doppia_metriche.txt"), "w") do io
    for o in (stdout, io)
        @printf(o, "controllo: S200 p69 diverso dalla rifinitura 200 della fase 2bis in %d tratte su %d\n", diversi, nrow(s))
        @printf(o, "campagna NOMAD-PB: valutazioni per tratta media %.0f (conclusi.csv); secondi di valutazione per tratta media %.1f, mediana %.1f (registro.csv, %d valutazioni); parete 3607,6 s × 8 processi / 1024 = %.1f s per tratta\n",
                mean(camp.valutazioni), mean(sec_camp.s), median(sec_camp.s), sum(sec_camp.n), 3607.59 * 8 / 1024)
        @printf(o, "secondi per valutazione: campagna %.1f ms; lanci S200 %.1f ms\n", 1000sum(sec_camp.s) / sum(sec_camp.n),
                1000sum(l.secondi[l.lancio .== "S200"]) / sum(l.valutazioni[l.lancio .== "S200"]))
        for r in eachrow(tab)
            @printf(o, "%s %-9s %-16s %-15s %4d tratte (attivate %3d) | non fatt. %4.1f%% | err. regime %4.1f%% | rimpianto med %6.3f%% p95 %6.2f%% max %6.2f%% | entro 0,25%% %5.1f%% | valutazioni %5.0f | secondi %5.2f\n",
                    r.insieme, r.soglia, r.strategia, r.categoria, r.tratte, r.attivate, r.non_fattibili_pct, r.errore_regime_pct,
                    r.rimpianto_mediana_pct, r.rimpianto_p95_pct, r.rimpianto_max_pct, r.entro_025_pct, r.valutazioni_medie, r.secondi_medi)
        end
    end
end
