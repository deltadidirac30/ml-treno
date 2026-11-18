# fase14/06_dati_presentazione.jl: i dati della classificazione (fase14/01–05) pronti per i grafici della presentazione, in
# fase14/presentazione/ (vedi il LEGGIMI.md lì dentro). Nessun calcolo nuovo: rilegge le tabelle e le flotte già calcolate.
#
#   julia --project=fase14 fase14/06_dati_presentazione.jl

using JLD2, Statistics, Printf
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const OUTD = joinpath(@__DIR__, "presentazione"); mkpath(OUTD)
const D = load(joinpath(BASE, "fase14", "tabella.jld2"))
const linee, m, n, P_FC, C_BATT, R, jopt, copt = D["linee"], D["m"], D["n"], D["P_FC"], D["C_BATT"], D["R"], D["jopt"], D["copt"]
const NL = length(linee)
const PM = load(joinpath(BASE, "fase14", "pmediana.jld2"))["ris"]
const MO = load(joinpath(BASE, "fase14", "modulari.jld2"))["ris"]
const GE = load(joinpath(BASE, "fase14", "geografico.jld2"))
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
f3(x) = @sprintf("%.3f", x)
taglie(treni) = length(unique(m[j] for j in treni if m[j] > 0)) + length(unique(n[j] for j in treni))
stat(ex) = (f3(100mean(ex)), f3(100median(ex)), f3(100maximum(ex)), count(>(0.05), ex), count(>(0.10), ex))

# ── curve.csv: tutte le strade, una riga per flotta ──────────────────────────────
open(joinpath(OUTD, "curve.csv"), "w") do io
    println(io, "strada,variante,K_treni,taglie_FC,taglie_batteria,taglie_componenti,extra_medio_pct,extra_mediano_pct,extra_peggiore_pct,linee_oltre_5pct,linee_oltre_10pct")
    for (pre, nome) in (("senza", "senza tetto"), ("10", "tetto +10%"), ("15", "tetto +15%")), K in 1:15
        k = "$(pre)_$K"; haskey(PM, k) || continue
        fl = PM[k].flotta; a = length(unique(m[j] for j in fl if m[j] > 0)); b = length(unique(n[j] for j in fl))
        println(io, join(("p-mediana", nome, K, a, b, a + b, stat(PM[k].ex)...), ','))
    end
    for r in Iterators.drop(eachline(joinpath(BASE, "fase14_log", "03_fasce.csv")), 1)
        c = split(r, ','); K = c[3]; tg = c[4]
        println(io, join(("fasce", c[1] == "regime" ? "fasce di m per regime, Δn $(c[2])" : "Δm $(c[1]), Δn $(c[2])", K, "", "", tg, c[5], c[6], c[7], c[8], c[9]), ','))
    end
    for (k, v) in sort(collect(MO); by = first)
        t, a, b = split(k, '_'); used = unique(v.ass)
        println(io, join(("modulare", t == "senza" ? "senza tetto" : "tetto +$(t)%", length(used), a, b, parse(Int, a) + parse(Int, b), stat(v.ex)...), ','))
    end
    for (k, v) in sort(collect(GE["ris"]); by = first)
        s, t, K = split(k, '_')
        a = length(unique(m[j] for j in v.flotta if m[j] > 0)); b = length(unique(n[j] for j in v.flotta))
        println(io, join(("geografico", "stesso treno se in comune ≥ $(s)%", K, a, b, a + b, stat(v.ex)...), ','))
    end
end

# ── le flotte scelte per i grafici ───────────────────────────────────────────────
const SCELTE = [("pm_K3", "p-mediana, 3 treni, senza tetto", PM["senza_3"]),
                ("pm_K5", "p-mediana, 5 treni, senza tetto", PM["senza_5"]),
                ("pm_K8", "p-mediana, 8 treni, senza tetto", PM["senza_8"]),
                ("pm_K8_tetto10", "p-mediana, 8 treni, tetto +10% (consigliata)", PM["10_8"]),
                ("pm_K15", "p-mediana, 15 treni, senza tetto", PM["senza_15"]),
                ("mod_3x3", "modulare 3 FC × 3 batterie, senza tetto", MO["senza_3_3"]),
                ("mod_6x5_tetto10", "modulare 6 FC × 5 batterie, tetto +10%", MO["10_6_5"]),
                ("geo25_K8", "geografico ≥ 25%, 8 treni", GE["ris"]["25_senza_8"]),
                ("geo50_K8", "geografico ≥ 50%, 8 treni", GE["ris"]["50_senza_8"])]
open(joinpath(OUTD, "flotte_scelte.csv"), "w") do io
    println(io, "flotta,descrizione,treno,m,n,regime,P_FC_kW,C_batt_kWh,linee,extra_medio_pct,extra_peggiore_pct,linea_peggiore")
    for (id, desc, v) in SCELTE
        for (c, j) in enumerate(sort(unique(v.ass); by = j -> (m[j], n[j])))
            li = findall(==(j), v.ass)
            println(io, join((id, "\"$desc\"", c, m[j], n[j], regime(m[j]), round(Int, P_FC[j]), round(Int, C_BATT[j]), length(li),
                              f3(100mean(v.ex[li])), f3(100maximum(v.ex[li])), linee[li[argmax(v.ex[li])]]), ','))
        end
    end
end

# ── linee.csv: una riga per linea, con l'ottimo e il treno di ogni flotta scelta ──
base = let l = readlines(joinpath(@__DIR__, "..", "fase13", "presentazione_146", "linee_146.csv")), h = split(l[1], ',')
    Dict(String(split(r, ',')[1]) => Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r)))
end
gruppo(s) = (G = Dict{Int,Int}(); p = collect(1:NL); tr(x) = (while p[x] != x; x = p[x]; end; x);
             for a in 1:NL, b in a+1:NL; GE["comune"][a, b] >= s * max(GE["Lkm"][a], GE["Lkm"][b]) && (p[tr(a)] = tr(b)); end;
             radici = unique(tr(i) for i in 1:NL); d = Dict(r => k for (k, r) in enumerate(sort(radici; by = r -> -count(i -> tr(i) == r, 1:NL))));
             [d[tr(i)] for i in 1:NL])
g25 = gruppo(0.25); g50 = gruppo(0.50)
open(joinpath(OUTD, "linee.csv"), "w") do io
    println(io, "linea,regione,L_km,lat,lon,ottimo_m,ottimo_n,ottimo_regime,ottimo_P_FC_kW,ottimo_C_batt_kWh,ottimo_costo_EUR_km,gruppo_geo25,gruppo_geo50,",
            join(("$(id)_m,$(id)_n,$(id)_extra_pct" for (id, _, _) in SCELTE), ','))
    for i in 1:NL
        b = base[linee[i]]; j0 = jopt[i]
        println(io, join((linee[i], b["regione"], b["L_km"], b["lat"], b["lon"], m[j0], n[j0], regime(m[j0]), round(Int, P_FC[j0]), round(Int, C_BATT[j0]),
                          @sprintf("%.4f", copt[i]), g25[i], g50[i], (join((m[v.ass[i]], n[v.ass[i]], f3(100v.ex[i])), ',') for (_, _, v) in SCELTE)...), ','))
    end
end

# ── la riduzione e il treno unico (per il grafico a imbuto) ───────────────────────
nf = vec(sum(isfinite.(R); dims = 1))
open(joinpath(OUTD, "riduzione.csv"), "w") do io
    println(io, "passo,treni")
    println(io, "griglia fitta (m 0 e 0,03–0,99 × n 0,01–0,99),", length(m))
    println(io, "fattibili su almeno una linea,", count(>(0), nf))
    println(io, "non dominati (candidati per la flotta),", length(D["tenuti"]))
    println(io, "fattibili su tutte le 146 linee,", count(==(NL), nf))
    println(io, "progetti ottimi distinti delle 146 linee,", length(unique(jopt)))
end
cp(joinpath(BASE, "fase14_log", "03_fasce.csv"), joinpath(OUTD, "fasce.csv"); force = true)
cp(joinpath(BASE, "fase14_log", "04_modulari.csv"), joinpath(OUTD, "modulari.csv"); force = true)
cp(joinpath(BASE, "fase14_log", "05_km_in_comune.csv"), joinpath(OUTD, "km_in_comune.csv"); force = true)
for f in ("fig_curva.png", "fig_piano_mn.png", "fig_mappa_K8.png", "fig_geografico_curva.png", "fig_geografico_mappa_K8.png")
    cp(joinpath(@__DIR__, "figure", f), joinpath(OUTD, f); force = true)
end
println("scritto ", OUTD, ": ", join(readdir(OUTD), ", "))
