# fase7/03_durata_rapporto.jl: passo 3b, la durata imparata come rapporto r = durata / durata minima teorica.
#
#   julia -t 8 --project=fase7 fase7/03_durata_rapporto.jl > ~/Documents/lavoro/ml_treno_dati/fase7_log/log_03.txt 2>&1
#
# Stessi dati, ingressi, impostazioni fisse e arresto anticipato di 01_durata.jl (modello D), ma l'obiettivo è
# r = y_durata_viaggio_s / x_tempo_limiti_ar_s (≈ 1,06) e la durata prevista è r̂ · x_tempo_limiti_ar_s. Con la perdita
# quadratica su r l'errore pesa in proporzione alla durata: tratte corte e lunghe contano allo stesso modo.
#   griglia su sviluppo (gruppi 1 e 2): profondità 4, 6, 8 × eta 0,05 e 0,1 (la migliore di D era sul bordo, profondità 6)
#   E: la migliore su tutto l'addestramento, confrontata con D (predizioni salvate da 01_durata.jl)
# Scrive in fase7_log: 03_rapporto.txt, 03_metriche.csv, 03_griglia.csv, 03_importanza.csv, fig_rapporto_*.png.

using Arrow, EvoTrees, Statistics, Printf, Random, Dates, Plots
gr()

const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const TAB = joinpath(BASE, "P9_D28_16384", "tabella")
const LOG = joinpath(BASE, "fase7_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase7"); mkpath(DAT)
const OUT = open(joinpath(LOG, "03_rapporto.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase7/03_durata_rapporto.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION, "  EvoTrees ", pkgversion(EvoTrees))
t_inizio = time()

# ── dati (come 01_durata.jl) ─────────────────────────────────────────────────────
const GRUPPI_SVILUPPO = (1, 2)
ta = Arrow.Table(joinpath(TAB, "addestramento.arrow"))
tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
NX = [c for c in Arrow.names(ta) if startswith(String(c), "x_")]
COLS = vcat(NX, [:m, :n]); NOMI = String.(COLS)
matrice(t) = reduce(hcat, (Vector{Float64}(getproperty(t, c)) for c in COLS))
Xa = matrice(ta); ya = Vector{Float64}(ta.y_durata_viaggio_s); ga = collect(ta.gruppo)
Xv = matrice(tv); yv = Vector{Float64}(tv.y_durata_viaggio_s); rv = Int.(tv.tratta)
jT = findfirst(==("x_tempo_limiti_ar_s"), NOMI); jL = findfirst(==("x_L_km"), NOMI); jm = findfirst(==("m"), NOMI)
Ta = Xa[:, jT]; Tv = Xv[:, jT]
ra_ = ya ./ Ta; rv_ = yv ./ Tv
dev = findall(in(GRUPPI_SVILUPPO), ga)
say(@sprintf("rapporto r = durata / durata minima: addestramento da %.4f a %.4f, mediana %.4f; validazione da %.4f a %.4f",
             minimum(ra_), maximum(ra_), median(ra_), minimum(rv_), maximum(rv_)))
say(@sprintf("  dispersione di r: deviazione standard %.4f (relativa alla mediana %.2f%%)", std(ra_), 100std(ra_) / median(ra_)))

function metriche(nome, p, y)
    e = p .- y; ep = 100 .* abs.(e) ./ y
    return (modello = nome, MAE_s = mean(abs.(e)), RMSE_s = sqrt(mean(abs2, e)), bias_s = mean(e),
            err_pct_mediana = median(ep), err_pct_p95 = quantile(ep, 0.95), err_pct_p99 = quantile(ep, 0.99), err_pct_max = maximum(ep))
end
riga(m) = @sprintf("  %-38s MAE %6.1f s  RMSE %6.1f s  bias %+6.1f s | errore %%: mediana %.3f  p95 %.3f  p99 %.3f  max %.2f",
                   m.modello, m.MAE_s, m.RMSE_s, m.bias_s, m.err_pct_mediana, m.err_pct_p95, m.err_pct_p99, m.err_pct_max)

# ── boosting su r ────────────────────────────────────────────────────────────────
const NBINS = 255; const ROWS = 0.8; const COLS_S = 0.8; const L2 = 1.0; const MAXR = 4000; const ESR = 50
say(@sprintf("\n[1] boosting su r, griglia sullo sviluppo (nbins %d, rowsample %.1f, colsample %.1f, L2 %.1f, fino a %d alberi, arresto dopo %d)",
             NBINS, ROWS, COLS_S, L2, MAXR, ESR))
function allena(X, y; prof, eta, seme = 1)
    cfg = EvoTreeRegressor(loss = :mse, metric = :mse, nrounds = MAXR, eta = eta, max_depth = prof, nbins = NBINS,
                           rowsample = ROWS, colsample = COLS_S, L2 = L2, seed = seme, early_stopping_rounds = ESR)
    t0 = time()
    m = EvoTrees.fit(cfg; x_train = X, y_train = y, x_eval = Xv, y_eval = rv_, feature_names = NOMI, verbosity = 0)
    lg = m.info[:logger]
    return (m = m, tempo = time() - t0, best = lg[:best_iter], curva = sqrt.(Float64.(lg[:metrics])))
end
durata(r, X) = vec(EvoTrees.predict(r.m, X; ntree_limit = r.best + 1)) .* X[:, jT]
griglia = NamedTuple[]; curve = Dict{String,Vector{Float64}}()
Xd = Xa[dev, :]; rd = ra_[dev]
for prof in (4, 6, 8), eta in (0.05, 0.1)
    r = allena(Xd, rd; prof, eta)
    mt = metriche("r prof $prof eta $eta", durata(r, Xv), yv)
    push!(griglia, (prof = prof, eta = eta, alberi = r.best, tempo_s = r.tempo, RMSE_r_val = r.curva[r.best + 1], RMSE_val_s = mt.RMSE_s, MAE_val_s = mt.MAE_s,
                    err_pct_mediana = mt.err_pct_mediana, err_pct_p95 = mt.err_pct_p95, err_pct_max = mt.err_pct_max))
    curve["prof $prof, eta $eta"] = r.curva
    say(@sprintf("  prof %d eta %.2f: %4d alberi, %5.1f s | RMSE %.1f s, MAE %.1f s, errore %% mediana %.3f p95 %.3f max %.2f",
                 prof, eta, r.best, r.tempo, mt.RMSE_s, mt.MAE_s, mt.err_pct_mediana, mt.err_pct_p95, mt.err_pct_max))
end
# scelta: RMSE di r sulla validazione (la metrica dell'arresto anticipato, cioè un errore relativo)
gb = griglia[argmin([g.RMSE_r_val for g in griglia])]
say(@sprintf("  migliore (RMSE di r sulla validazione): profondità %d, eta %.2f (%d alberi)", gb.prof, gb.eta, gb.alberi))
open(joinpath(LOG, "03_griglia.csv"), "w") do io
    println(io, join(keys(griglia[1]), ','))
    for g in griglia; println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(g)), ',')); end
end

say("\n[2] E: boosting su r, configurazione migliore, tutto l'addestramento (12288 tratte)")
rE = allena(Xa, ra_; prof = gb.prof, eta = gb.eta)
pE = durata(rE, Xv)
say(@sprintf("  %d alberi, %.1f s", rE.best, rE.tempo))
ic = randperm(Xoshiro(7), length(ya))[1:500_000]
mtrE = metriche("E sull'addestramento (campione)", durata(rE, Xa[ic, :]), ya[ic])

# ── confronto con D ──────────────────────────────────────────────────────────────
pv = Arrow.Table(joinpath(DAT, "durata_validazione.arrow"))
collect(pv.tratta) == rv && collect(pv.vero) == yv || error("predizioni di D non allineate alla validazione")
pD = collect(pv.D); pA = collect(pv.A)
res = [metriche("A costante × durata minima", pA, yv), metriche("D boosting sulla durata [s]", pD, yv),
       metriche("E boosting sul rapporto r", pE, yv)]
say("\n[3] validazione (2048 tratte mai viste, 589 824 casi)")
foreach(m -> say(riga(m)), res)
say(riga(mtrE), "   ← E sui dati che ha visto")
open(joinpath(LOG, "03_metriche.csv"), "w") do io
    println(io, join(keys(res[1]), ','))
    for m in vcat(res, [mtrE]); println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(m)), ',')); end
end
L = Xv[:, jL]
epD = 100 .* abs.(pD .- yv) ./ yv; epE = 100 .* abs.(pE .- yv) ./ yv
say("  errore % per fascia di lunghezza (D → E):")
for (a, b) in ((0, 25), (25, 50), (50, 100), (100, 200), (200, 301))
    s = (L .>= a) .& (L .< b)
    say(@sprintf("    L %3d–%3d km: mediana %.3f → %.3f, p95 %.3f → %.3f, max %5.2f → %5.2f", a, b,
                 median(epD[s]), median(epE[s]), quantile(epD[s], 0.95), quantile(epE[s], 0.95), maximum(epD[s]), maximum(epE[s])))
end
let eD = Dict{Int,Vector{Float64}}(), eE = Dict{Int,Vector{Float64}}()
    for i in eachindex(rv); push!(get!(eD, rv[i], Float64[]), epD[i]); push!(get!(eE, rv[i], Float64[]), epE[i]); end
    k = collect(keys(eD))
    mD = [mean(eD[r]) for r in k]; mE = [mean(eE[r]) for r in k]
    say(@sprintf("  per tratta, errore %% medio: mediana %.3f → %.3f, p95 %.3f → %.3f, max %.2f → %.2f; tratte migliorate %d su %d",
                 median(mD), median(mE), quantile(mD, 0.95), quantile(mE, 0.95), maximum(mD), maximum(mE), count(mE .< mD), length(k)))
    # quota dell'errore costante nella tratta: varianza della media di tratta / varianza totale (errore relativo con segno)
    sD = Dict{Int,Vector{Float64}}(); sE = Dict{Int,Vector{Float64}}()
    for i in eachindex(rv); push!(get!(sD, rv[i], Float64[]), (pD[i] - yv[i]) / yv[i]); push!(get!(sE, rv[i], Float64[]), (pE[i] - yv[i]) / yv[i]); end
    q(s) = (tot = reduce(vcat, values(s)); sum(length(v) * mean(v)^2 for v in values(s)) / sum(abs2, tot))
    say(@sprintf("  quota dell'errore quadratico relativo che è costante nella tratta: D %.1f%%, E %.1f%%", 100q(sD), 100q(sE)))
    rk = sort(k; by = r -> -mean(eE[r]))[1:5]
    say("  le 5 tratte peggiori per E: ", join((@sprintf("%d (D %.2f%% → E %.2f%%, L %.0f km)", r, mean(eD[r]), mean(eE[r]),
                                                    L[findfirst(==(r), rv)]) for r in rk), ", "))
end
imp = EvoTrees.importance(rE.m)
open(joinpath(LOG, "03_importanza.csv"), "w") do io
    println(io, "caratteristica,importanza"); for (k, v) in imp; println(io, k, ',', v); end
end
say("  importanza di E, prime 10: ", join((@sprintf("%s %.3f", k, v) for (k, v) in imp[1:10]), ", "))
Arrow.write(joinpath(DAT, "durata_validazione_rapporto.arrow"), (tratta = Int32.(rv), coppia = tv.coppia, vero = yv, D = pD, E = pE))
try EvoTrees.save(rE.m, joinpath(DAT, "durata_E.bson")); catch e; say("  modello non salvato: ", sprint(showerror, e)); end

# ── figure ───────────────────────────────────────────────────────────────────────
say("\n[4] figure")
function fasce(x, e, nb)
    q = quantile(x, range(0, 1; length = nb + 1)); xc = Float64[]; med = Float64[]; p95 = Float64[]
    for i in 1:nb
        s = (x .>= q[i]) .& (x .<= q[i+1]); any(s) || continue
        push!(xc, median(x[s])); push!(med, median(e[s])); push!(p95, quantile(e[s], 0.95))
    end
    return xc, med, p95
end
plt = plot(size = (900, 480), dpi = 130, xlabel = "lunghezza della tratta [km]", ylabel = "errore relativo [%]",
           title = "durata: D (secondi) contro E (rapporto), validazione")
for (nome, e, col) in (("D", epD, :gray50), ("E", epE, :steelblue))
    xc, med, p95 = fasce(L, e, 20)
    plot!(plt, xc, p95; lw = 2, ls = :dash, color = col, label = "$nome p95")
    plot!(plt, xc, med; lw = 2, color = col, label = "$nome mediana")
end
savefig(plt, joinpath(LOG, "fig_rapporto_fasce.png"))
plt = plot(size = (800, 450), dpi = 130, xlabel = "|errore| [%] (scala log)", ylabel = "quota dei casi con errore minore",
           xscale = :log10, legend = :bottomright, xlims = (1e-4, 100))
for (nome, p, col) in (("A", pA, :gray70), ("D (secondi)", pD, :gray40), ("E (rapporto)", pE, :steelblue))
    e = sort(max.(100 .* abs.(p .- yv) ./ yv, 1e-4))
    plot!(plt, e[1:50:end], range(0, 1; length = length(e))[1:50:end]; lw = 2, color = col, label = nome)
end
savefig(plt, joinpath(LOG, "fig_rapporto_distribuzione.png"))
plt = plot(size = (800, 450), dpi = 130, xlabel = "numero di alberi", ylabel = "RMSE di r sulla validazione (scala log)", yscale = :log10)
for (k, v) in sort(collect(curve)); plot!(plt, 0:length(v)-1, v; lw = 1.5, label = k); end
plot!(plt, 0:length(rE.curva)-1, rE.curva; lw = 2.5, color = :black, label = "E, tutto l'addestramento")
savefig(plt, joinpath(LOG, "fig_rapporto_curve.png"))
say("  fig_rapporto_fasce.png, fig_rapporto_distribuzione.png, fig_rapporto_curve.png")
say(@sprintf("\ntempo totale: %.1f s", time() - t_inizio))
close(OUT)
