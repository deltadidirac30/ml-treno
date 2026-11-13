# fase8/01_grandezze.jl: passo 4 del surrogato, le altre grandezze con la ricetta della durata (fase 7).
#
#   julia -t 8 --project=fase8 fase8/01_grandezze.jl [nome ...] > ~/Documents/lavoro/ml_treno_dati/fase8_log/log_01.txt 2>&1
#
# Per ogni grandezza: un obiettivo con la scala fisica naturale (per km, logaritmo, classe), gradient boosting
# (EvoTrees 0.19.0) su tutto l'addestramento con arresto anticipato sulla validazione, confronto con la mediana della
# coppia (m, n) nell'addestramento (vede m e n ma non la tratta). Metriche sulla validazione nelle unità naturali.
# Il test non si tocca. Senza argomenti tutte le grandezze; con argomenti solo quelle nominate.
#
# Scrive in ~/Documents/lavoro/ml_treno_dati/fase8_log: 01_grandezze.txt, 01_metriche.csv, 01_importanza_<nome>.csv,
# figure fig_*.png; in ~/Documents/lavoro/ml_treno_dati/fase8: pred_<nome>.arrow (validazione), modello_<nome>.bson.

using Arrow, EvoTrees, Statistics, Printf, Random, Dates, Plots
gr()

const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const TAB = joinpath(BASE, "P9_D28_16384", "tabella")
const LOG = joinpath(BASE, "fase8_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase8"); mkpath(DAT)
const OUT = open(joinpath(LOG, "01_grandezze.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase8/01_grandezze.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION, "  EvoTrees ", pkgversion(EvoTrees))
t_inizio = time()

# ── le grandezze ─────────────────────────────────────────────────────────────────
# righe: :tutte (completed e rejected D3), :ibride (m > 0, simulate), :ibride_completed (m > 0, completed)
# trasf: :per_km (y / 2L), :log, :nessuna, :classe (y > 1e-6, probabilità)
const GRANDEZZE = [
    (nome = "massa_serbatoio", col = :y_massa_serbatoio_kg, righe = :ibride, trasf = :per_km, unita = "kg"),
    (nome = "H2_cons", col = :y_H2_cons_kg, righe = :ibride_completed, trasf = :per_km, unita = "kg"),
    (nome = "SOC_end", col = :y_SOC_end, righe = :tutte, trasf = :nessuna, unita = "-"),
    (nome = "scarica", col = :y_scarica_s, righe = :tutte, trasf = :classe, unita = "-"),
    (nome = "vita_batt", col = :y_vita_batt_cicli_viaggi, righe = :tutte, trasf = :log, unita = "viaggi"),
    (nome = "vita_FC", col = :y_vita_FC_f1_ore, righe = :ibride, trasf = :log, unita = "h"),
    (nome = "C_rate", col = :y_C_rate_scarica_max, righe = :tutte, trasf = :log, unita = "-"),
]
scelte = isempty(ARGS) ? GRANDEZZE : [g for g in GRANDEZZE if g.nome in ARGS]
say("grandezze: ", join((g.nome for g in scelte), ", "))

const PROF = 6; const ETA = 0.1; const NBINS = 255; const ROWS = 0.8; const COLS_S = 0.8; const L2 = 1.0
const MAXR = 3000; const ESR = 50
say(@sprintf("boosting: profondità %d, eta %.2f, nbins %d, rowsample %.1f, colsample %.1f, L2 %.1f, fino a %d alberi, arresto dopo %d",
             PROF, ETA, NBINS, ROWS, COLS_S, L2, MAXR, ESR))

# ── dati ─────────────────────────────────────────────────────────────────────────
ta = Arrow.Table(joinpath(TAB, "addestramento.arrow"))
tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
NX = [c for c in Arrow.names(ta) if startswith(String(c), "x_")]
COLS = vcat(NX, [:m, :n]); NOMI = String.(COLS)
matrice(t) = reduce(hcat, (Vector{Float64}(getproperty(t, c)) for c in COLS))
t0 = time()
const Xa = matrice(ta); const Xv = matrice(tv)
const La = collect(ta.x_L_km); const Lv = collect(tv.x_L_km)
const ma = collect(ta.m); const mv = collect(tv.m)
const sa = collect(ta.stato); const sv = collect(tv.stato)
const ca = Int.(ta.coppia); const cv = Int.(tv.coppia)
const rv = Int.(tv.tratta)
const d3v = collect(tv.d3)
say(@sprintf("dati: addestramento %d righe, validazione %d righe (%.1f s)", size(Xa, 1), size(Xv, 1), time() - t0))

selez(righe, m, s) = righe === :tutte ? trues(length(m)) : righe === :ibride ? m .> 0 : (m .> 0) .& (s .== 1)
avanti(trasf, y, L) = trasf === :per_km ? y ./ (2 .* L) : trasf === :log ? log.(y) : trasf === :classe ? Float64.(y .> 1e-6) : y
indietro(trasf, z, L) = trasf === :per_km ? z .* (2 .* L) : trasf === :log ? exp.(z) : z

# ── metriche ─────────────────────────────────────────────────────────────────────
function met_rel(p, y)
    ep = 100 .* abs.(p .- y) ./ abs.(y)
    return (MAE = mean(abs.(p .- y)), err_pct_mediana = median(ep), err_pct_p95 = quantile(ep, 0.95),
            err_pct_p99 = quantile(ep, 0.99), err_pct_max = maximum(ep))
end
function met_abs(p, y)
    e = abs.(p .- y)
    return (MAE = mean(e), err_pct_mediana = median(e), err_pct_p95 = quantile(e, 0.95), err_pct_p99 = quantile(e, 0.99),
            err_pct_max = maximum(e))   # per SOC: errori assoluti (stesse colonne, in unità di SOC)
end
function met_cls(p, y)
    c = p .>= 0.5
    return (accuratezza = mean(c .== (y .> 0.5)), brier = mean(abs2, p .- y), falsi_pos = count(c .& (y .< 0.5)),
            falsi_neg = count(.!c .& (y .> 0.5)), positivi = count(y .> 0.5))
end
# quota dell'errore (con segno, nello spazio dell'obiettivo) costante nella tratta
function quota_tratta(e, r)
    s = Dict{Int,Vector{Float64}}(); for i in eachindex(r); push!(get!(s, r[i], Float64[]), e[i]); end
    return sum(length(v) * mean(v)^2 for v in values(s)) / sum(abs2, e)
end

const righe_met = NamedTuple[]
# il lavoro per una grandezza, in una funzione (a livello di script i cicli sarebbero interpretati)
function elabora(g)
    say("\n══ ", g.nome, " (", g.col, "; righe ", g.righe, "; obiettivo ", g.trasf, ")")
    t0 = time()
    ia = findall(selez(g.righe, ma, sa)); iv = findall(selez(g.righe, mv, sv))
    ya = Vector{Float64}(getproperty(ta, g.col))[ia]; yv = Vector{Float64}(getproperty(tv, g.col))[iv]
    nb = count(!isfinite, ya) + count(!isfinite, yv)
    nb == 0 || error("$(g.nome): $nb valori non finiti nelle righe scelte")
    za = avanti(g.trasf, ya, La[ia]); zv = avanti(g.trasf, yv, Lv[iv])
    say(@sprintf("  righe: addestramento %d, validazione %d; valori: min %.4g, mediana %.4g, max %.4g", length(ia), length(iv),
                 minimum(yv), median(yv), maximum(yv)))
    cls = g.trasf === :classe
    # confronto semplice: mediana (o frequenza) della coppia nell'addestramento, nello spazio dell'obiettivo
    perc = Dict{Int,Vector{Float64}}(); for (k, i) in enumerate(ia); push!(get!(perc, ca[i], Float64[]), za[k]); end
    stat = Dict(k => (cls ? mean(v) : median(v)) for (k, v) in perc)
    riserva = cls ? mean(za) : median(za)          # per coppie senza righe nell'addestramento (calcolata una volta)
    zb = [get(stat, cv[i], riserva) for i in iv]
    pb = cls ? zb : indietro(g.trasf, zb, Lv[iv])
    # boosting
    cfg = EvoTreeRegressor(loss = cls ? :logloss : :mse, metric = cls ? :logloss : :mse, nrounds = MAXR, eta = ETA, max_depth = PROF,
                           nbins = NBINS, rowsample = ROWS, colsample = COLS_S, L2 = L2, seed = 1, early_stopping_rounds = ESR)
    tf = time()
    mdl = EvoTrees.fit(cfg; x_train = Xa[ia, :], y_train = za, x_eval = Xv[iv, :], y_eval = zv, feature_names = NOMI, verbosity = 0)
    tf = time() - tf
    best = mdl.info[:logger][:best_iter]
    zp = vec(EvoTrees.predict(mdl, Xv[iv, :]; ntree_limit = best + 1))
    pp = cls ? zp : indietro(g.trasf, zp, Lv[iv])
    # sull'addestramento (campione di 300 000 righe), per il sovradattamento
    ic = ia[randperm(Xoshiro(7), length(ia))[1:min(300_000, length(ia))]]
    zt = vec(EvoTrees.predict(mdl, Xa[ic, :]; ntree_limit = best + 1))
    yt = Vector{Float64}(getproperty(ta, g.col))[ic]
    pt = cls ? zt : indietro(g.trasf, zt, La[ic])
    say(@sprintf("  %d alberi, %.1f s", best, tf))
    if cls
        mb = met_cls(pb, zv); mm = met_cls(pp, zv); mt = met_cls(pt, Float64.(yt .> 1e-6))
        for (nome, x) in (("mediana della coppia", mb), ("boosting", mm), ("boosting sull'addestramento", mt))
            say(@sprintf("  %-28s accuratezza %.4f, Brier %.4f, falsi positivi %d, falsi negativi %d (positivi %d)",
                         nome, x.accuratezza, x.brier, x.falsi_pos, x.falsi_neg, x.positivi))
        end
        push!(righe_met, (grandezza = g.nome, modello = "coppia", n = length(iv), MAE = NaN, err_mediana = NaN, err_p95 = NaN,
                          err_p99 = NaN, err_max = NaN, accuratezza = mb.accuratezza, brier = mb.brier, alberi = 0, tempo_s = 0.0))
        push!(righe_met, (grandezza = g.nome, modello = "boosting", n = length(iv), MAE = NaN, err_mediana = NaN, err_p95 = NaN,
                          err_p99 = NaN, err_max = NaN, accuratezza = mm.accuratezza, brier = mm.brier, alberi = best, tempo_s = tf))
        # calibrazione: probabilità prevista contro frequenza vera, per fasce di 0,1
        say("  calibrazione (fascia di p prevista: casi, frequenza vera):")
        for a in 0:0.1:0.9
            s = (pp .>= a) .& (pp .< a + 0.1 + (a ≥ 0.9 ? 1e-9 : 0))
            any(s) && say(@sprintf("    [%.1f, %.1f): %7d, %.3f", a, a + 0.1, count(s), mean(zv[s])))
        end
    else
        f = g.trasf === :nessuna ? met_abs : met_rel
        mb = f(pb, yv); mm = f(pp, yv); mt = f(pt, yt)
        lab = g.trasf === :nessuna ? "errore assoluto" : "errore %"
        for (nome, x) in (("mediana della coppia", mb), ("boosting", mm), ("boosting sull'addestramento", mt))
            say(@sprintf("  %-28s MAE %.4g %s | %s: mediana %.4g  p95 %.4g  p99 %.4g  max %.4g", nome, x.MAE, g.unita, lab,
                         x.err_pct_mediana, x.err_pct_p95, x.err_pct_p99, x.err_pct_max))
        end
        for (mod, x) in (("coppia", mb), ("boosting", mm))
            push!(righe_met, (grandezza = g.nome, modello = mod, n = length(iv), MAE = x.MAE, err_mediana = x.err_pct_mediana,
                              err_p95 = x.err_pct_p95, err_p99 = x.err_pct_p99, err_max = x.err_pct_max, accuratezza = NaN, brier = NaN,
                              alberi = mod == "boosting" ? best : 0, tempo_s = mod == "boosting" ? tf : 0.0))
        end
        say(@sprintf("  quota dell'errore (nello spazio dell'obiettivo) costante nella tratta: %.1f%%", 100quota_tratta(zp .- zv, rv[iv])))
        # per fascia di lunghezza
        ep = g.trasf === :nessuna ? abs.(pp .- yv) : 100 .* abs.(pp .- yv) ./ abs.(yv)
        say("  ", lab, " del boosting per fascia di lunghezza (mediana / p95):  ",
            join((let s = (Lv[iv] .>= a) .& (Lv[iv] .< b); @sprintf("%d–%d km %.3g / %.3g", a, b, median(ep[s]), quantile(ep[s], 0.95)) end
                  for (a, b) in ((0, 25), (25, 100), (100, 200), (200, 301))), ";  "))
        if g.nome == "SOC_end"
            # il vincolo SOC ≥ 0,2: classificazione dal valore previsto
            v = yv .< 0.2; c = pp .< 0.2
            say(@sprintf("  vincolo SOC finale ≥ 0,2 dal valore previsto: giusto %.4f; dato fattibile ma è sotto %d, dato sotto ma è fattibile %d (sotto davvero %d)",
                         mean(v .== c), count(.!c .& v), count(c .& .!v), count(v)))
            lontani = abs.(yv .- 0.2) .> 0.02
            say(@sprintf("    lontano dal limite (|SOC − 0,2| > 0,02, %.1f%% dei casi): giusto %.5f", 100mean(lontani), mean((v .== c)[lontani])))
        end
        if g.nome == "C_rate"
            # regola D3 a posteriori dal C-rate previsto, contro l'esito D3 vero
            d = d3v[iv]; c = pp .> 20; cvero = yv .> 20
            say(@sprintf("  regola D3 (C-rate previsto > 20) contro D3 vero: giusto %.5f; D3 mancati %d, scarti in più %d (D3 veri %d)",
                         mean(c .== d), count(.!c .& d), count(c .& .!d), count(d)))
            say(@sprintf("    con il C-rate vero la regola sbaglia %d casi: il resto è errore del modello", count(cvero .!= d)))
        end
    end
    imp = EvoTrees.importance(mdl)
    open(joinpath(LOG, "01_importanza_$(g.nome).csv"), "w") do io
        println(io, "caratteristica,importanza"); for (k, v) in imp; println(io, k, ',', v); end
    end
    say("  importanza, prime 6: ", join((@sprintf("%s %.3f", k, v) for (k, v) in imp[1:6]), ", "))
    Arrow.write(joinpath(DAT, "pred_$(g.nome).arrow"),
                (tratta = Int32.(rv[iv]), coppia = Int16.(cv[iv]), vero = cls ? zv : yv, boosting = pp, coppia_mediana = pb))
    try EvoTrees.save(mdl, joinpath(DAT, "modello_$(g.nome).bson")); catch e; say("  modello non salvato: ", sprint(showerror, e)); end
    say(@sprintf("  tempo per questa grandezza: %.1f s", time() - t0))
    GC.gc()
end
for g in scelte
    elabora(g)
end

open(joinpath(LOG, isempty(ARGS) ? "01_metriche.csv" : "01_metriche_$(join(ARGS, '_')).csv"), "w") do io
    println(io, join(keys(righe_met[1]), ','))
    for r in righe_met; println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(r)), ',')); end
end

# ── figure (dalle predizioni salvate) ────────────────────────────────────────────
say("\n[figure]")
reg = [g for g in scelte if g.trasf !== :classe]
if !isempty(reg)
    plt = plot(layout = (2, 3), size = (1500, 950), dpi = 120, legend = false)
    for (k, g) in enumerate(reg[1:min(6, end)])
        p = Arrow.Table(joinpath(DAT, "pred_$(g.nome).arrow"))
        y = collect(p.vero); q = collect(p.boosting)
        ic = randperm(Xoshiro(3), length(y))[1:min(60_000, length(y))]
        lg = g.trasf === :log
        scatter!(plt[k], y[ic], q[ic]; ms = 1.2, msw = 0, alpha = 0.3, color = :steelblue, title = g.nome,
                 xlabel = "vero [$(g.unita)]", ylabel = "previsto", xscale = lg ? :log10 : :identity, yscale = lg ? :log10 : :identity)
        a, b = extrema(vcat(y[ic], q[ic])); plot!(plt[k], [a, b], [a, b]; color = :black, ls = :dash)
    end
    savefig(plt, joinpath(LOG, "fig_previsto_vero.png"))
    say("  fig_previsto_vero.png")
end
if any(g -> g.nome == "scarica", scelte)
    p = Arrow.Table(joinpath(DAT, "pred_scarica.arrow")); y = collect(p.vero); q = collect(p.boosting)
    xs = Float64[]; fs = Float64[]
    for a in 0:0.05:0.95
        s = (q .>= a) .& (q .< a + 0.05 + (a ≥ 0.95 ? 1e-9 : 0)); any(s) || continue
        push!(xs, mean(q[s])); push!(fs, mean(y[s]))
    end
    plt = plot([0, 1], [0, 1]; color = :black, ls = :dash, label = "calibrazione perfetta", size = (600, 550), dpi = 120,
               xlabel = "probabilità prevista di scarica", ylabel = "frequenza vera", title = "scarica: calibrazione del classificatore")
    plot!(plt, xs, fs; marker = :circle, lw = 2, color = :steelblue, label = "boosting")
    savefig(plt, joinpath(LOG, "fig_scarica_calibrazione.png"))
    say("  fig_scarica_calibrazione.png")
end
say(@sprintf("\ntempo totale: %.1f s", time() - t_inizio))
close(OUT)
