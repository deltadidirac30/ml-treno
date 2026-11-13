# fase7/01_durata.jl: passo 3 del surrogato, primo modello su una grandezza: la durata del viaggio A/R.
#
#   julia -t 8 --project=fase7 fase7/01_durata.jl > ~/Documents/lavoro/ml_treno_dati/fase7_log/log_01.txt 2>&1
#
# Ingressi: le 66 caratteristiche della tratta + m + n (68). Uscita: y_durata_viaggio_s, su tutti i casi simulati
# (completed e rejected D3: la durata c'è in entrambi). Il test non si tocca.
#
#   A  costante × durata minima teorica (x_tempo_limiti_ar_s), un parametro, minimi quadrati sull'addestramento
#   B  regressione lineare su [1, T, T·m, T·n, m, n] con T = x_tempo_limiti_ar_s (massa del treno ~ m, n)
#   C  gradient boosting (EvoTrees 0.19.0, perdita MSE, istogrammi a 255 classi): griglia profondità × eta sul
#      sottoinsieme di sviluppo (gruppi 1 e 2, 2048 tratte), arresto anticipato sulla validazione
#   D  la configurazione migliore di C su tutto l'addestramento (12 gruppi), arresto anticipato sulla validazione
# Metriche sulla validazione (gruppi 7 e 12). Scrive in ~/Documents/lavoro/ml_treno_dati/fase7_log: 01_durata.txt,
# 01_metriche.csv, 01_griglia.csv, 01_importanza.csv, figure fig_*.png; predizioni e modello in ml_treno_dati/fase7.

using Arrow, EvoTrees, Statistics, Printf, Random, LinearAlgebra, Dates, Plots
gr()

const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const TAB = joinpath(BASE, "P9_D28_16384", "tabella")
const LOG = joinpath(BASE, "fase7_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase7"); mkpath(DAT)
const OUT = open(joinpath(LOG, "01_durata.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase7/01_durata.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION, "  EvoTrees ", pkgversion(EvoTrees))
t_inizio = time()

# ── dati ─────────────────────────────────────────────────────────────────────────
const GRUPPI_SVILUPPO = (1, 2)
ta = Arrow.Table(joinpath(TAB, "addestramento.arrow"))
tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
NX = [c for c in Arrow.names(ta) if startswith(String(c), "x_")]
COLS = vcat(NX, [:m, :n]); NOMI = String.(COLS)
matrice(t) = reduce(hcat, (Vector{Float64}(getproperty(t, c)) for c in COLS))
Xa = matrice(ta); ya = Vector{Float64}(ta.y_durata_viaggio_s); ga = collect(ta.gruppo); ra = Int.(ta.tratta)
Xv = matrice(tv); yv = Vector{Float64}(tv.y_durata_viaggio_s); rv = Int.(tv.tratta)
dev = findall(in(GRUPPI_SVILUPPO), ga)
say(@sprintf("addestramento %d righe (%d tratte); sviluppo = gruppi %s: %d righe (%d tratte); validazione %d righe (%d tratte)",
             length(ya), length(unique(ra)), GRUPPI_SVILUPPO, length(dev), length(unique(ra[dev])), length(yv), length(unique(rv))))
say(@sprintf("durata: da %.0f a %.0f s, mediana %.0f s (%.2f h); NaN/Inf: %d", minimum(ya), maximum(ya), median(ya), median(ya) / 3600,
             count(!isfinite, ya) + count(!isfinite, yv)))
jT = findfirst(==("x_tempo_limiti_ar_s"), NOMI); jm = findfirst(==("m"), NOMI); jn = findfirst(==("n"), NOMI)

function metriche(nome, p, y)
    e = p .- y; ep = 100 .* abs.(e) ./ y
    return (modello = nome, MAE_s = mean(abs.(e)), RMSE_s = sqrt(mean(abs2, e)), bias_s = mean(e),
            err_pct_mediana = median(ep), err_pct_p95 = quantile(ep, 0.95), err_pct_p99 = quantile(ep, 0.99), err_pct_max = maximum(ep),
            err_s_p95 = quantile(abs.(e), 0.95), err_s_max = maximum(abs.(e)))
end
riga(m) = @sprintf("  %-34s MAE %7.1f s  RMSE %7.1f s  bias %+6.1f s | errore %%: mediana %.3f  p95 %.3f  p99 %.3f  max %.2f",
                   m.modello, m.MAE_s, m.RMSE_s, m.bias_s, m.err_pct_mediana, m.err_pct_p95, m.err_pct_p99, m.err_pct_max)
risultati = NamedTuple[]

# ── rumore della durata: quanto è "liscia" in (m, n) dentro una tratta ─────────────
# per ogni tratta di validazione, minimi quadrati su [1, m, n, m², n², m·n]: lo scarto residuo è il rumore della
# dinamica a passo di 1 s (più la parte non quadratica), un pavimento indicativo per qualunque modello
say("\n[0] rumore della durata dentro la tratta (validazione, polinomio di 2° grado in m, n per tratta)")
let res = Float64[], resr = Float64[]
    idx = Dict{Int,Vector{Int}}(); for i in eachindex(rv); push!(get!(idx, rv[i], Int[]), i); end
    for (r, ii) in idx
        m = Xv[ii, jm]; n = Xv[ii, jn]
        A = hcat(ones(length(ii)), m, n, m .^ 2, n .^ 2, m .* n)
        e = yv[ii] .- A * (A \ yv[ii])
        append!(res, e); append!(resr, 100 .* abs.(e) ./ yv[ii])
    end
    say(@sprintf("  scarto: RMSE %.1f s, |scarto| p95 %.1f s, max %.1f s; in %%: mediana %.3f, p95 %.3f", sqrt(mean(abs2, res)),
                 quantile(abs.(res), 0.95), maximum(abs.(res)), median(resr), quantile(resr, 0.95)))
end

# ── A, B ─────────────────────────────────────────────────────────────────────────
say("\n[1] modelli semplici (stimati su tutto l'addestramento)")
T = Xa[:, jT]
c = dot(T, ya) / dot(T, T)
pA = c .* Xv[:, jT]
say(@sprintf("  A: durata = %.5f × tempo_limiti_ar_s", c))
push!(risultati, metriche("A costante × durata minima", pA, yv))
B(X) = (T = X[:, jT]; hcat(ones(size(X, 1)), T, T .* X[:, jm], T .* X[:, jn], X[:, jm], X[:, jn]))
β = B(Xa) \ ya
pB = B(Xv) * β
say("  B: coefficienti [1, T, T·m, T·n, m, n] = ", join((@sprintf("%.5g", b) for b in β), ", "))
push!(risultati, metriche("B lineare (T, T·m, T·n, m, n)", pB, yv))
say(riga(risultati[1])); say(riga(risultati[2]))

# ── C: griglia sul sottoinsieme di sviluppo ──────────────────────────────────────
const NBINS = 255; const ROWS = 0.8; const COLS_S = 0.8; const L2 = 1.0; const MAXR = 4000; const ESR = 50
say(@sprintf("\n[2] boosting, griglia sullo sviluppo (nbins %d, rowsample %.1f, colsample %.1f, L2 %.1f, fino a %d alberi, arresto dopo %d senza miglioramenti sulla validazione)",
             NBINS, ROWS, COLS_S, L2, MAXR, ESR))
function allena(X, y; prof, eta, seme = 1)
    cfg = EvoTreeRegressor(loss = :mse, metric = :mse, nrounds = MAXR, eta = eta, max_depth = prof, nbins = NBINS,
                           rowsample = ROWS, colsample = COLS_S, L2 = L2, seed = seme, early_stopping_rounds = ESR)
    t0 = time()
    m = EvoTrees.fit(cfg; x_train = X, y_train = y, x_eval = Xv, y_eval = yv, feature_names = NOMI, verbosity = 0)
    lg = m.info[:logger]
    return (m = m, tempo = time() - t0, best = lg[:best_iter], curva = sqrt.(Float64.(lg[:metrics])))
end
predici(r, X) = vec(EvoTrees.predict(r.m, X; ntree_limit = r.best + 1))
griglia = NamedTuple[]
curve = Dict{String,Vector{Float64}}()
Xd = Xa[dev, :]; yd = ya[dev]
for prof in (6, 8, 10), eta in (0.05, 0.1)
    r = allena(Xd, yd; prof, eta)
    p = predici(r, Xv)
    mt = metriche("C prof $prof eta $eta", p, yv)
    push!(griglia, (prof = prof, eta = eta, alberi = r.best, tempo_s = r.tempo, RMSE_val_s = mt.RMSE_s, MAE_val_s = mt.MAE_s,
                    err_pct_mediana = mt.err_pct_mediana, err_pct_p95 = mt.err_pct_p95))
    curve["prof $prof, eta $eta"] = r.curva
    say(@sprintf("  prof %2d eta %.2f: %4d alberi, %5.1f s | RMSE %.1f s, MAE %.1f s, errore %% mediana %.3f p95 %.3f",
                 prof, eta, r.best, r.tempo, mt.RMSE_s, mt.MAE_s, mt.err_pct_mediana, mt.err_pct_p95))
end
ib = argmin([g.RMSE_val_s for g in griglia]); gb = griglia[ib]
say(@sprintf("  migliore sulla validazione: profondità %d, eta %.2f (%d alberi)", gb.prof, gb.eta, gb.alberi))
rC = allena(Xd, yd; prof = gb.prof, eta = gb.eta)
pC = predici(rC, Xv)
push!(risultati, metriche("C boosting, sviluppo (2048 tratte)", pC, yv))

# ── D: tutto l'addestramento ─────────────────────────────────────────────────────
say("\n[3] boosting sulla configurazione migliore, tutto l'addestramento (12288 tratte)")
rD = allena(Xa, ya; prof = gb.prof, eta = gb.eta)
pD = predici(rD, Xv)
push!(risultati, metriche("D boosting, addestramento (12288)", pD, yv))
say(@sprintf("  %d alberi, %.1f s", rD.best, rD.tempo))
# sovradattamento: errore sull'addestramento (un campione di 500 000 righe)
ic = randperm(Xoshiro(7), length(ya))[1:500_000]
mtr = metriche("D sull'addestramento (campione)", predici(rD, Xa[ic, :]), ya[ic])
t0 = time(); predici(rD, Xv); tp = time() - t0

say("\n[4] risultati sulla validazione (2048 tratte mai viste, 589 824 casi)")
foreach(m -> say(riga(m)), risultati)
say(riga(mtr), "   ← stesso modello D sui dati che ha visto: confronto per il sovradattamento")
say(@sprintf("  tempo di previsione del modello D: %.2f s per %d casi = %.2f µs a caso (8 thread)", tp, length(yv), 1e6tp / length(yv)))
open(joinpath(LOG, "01_metriche.csv"), "w") do io
    println(io, join(keys(risultati[1]), ','))
    for m in vcat(risultati, [mtr]); println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(m)), ',')); end
end
open(joinpath(LOG, "01_griglia.csv"), "w") do io
    println(io, join(keys(griglia[1]), ','))
    for g in griglia; println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(g)), ',')); end
end

# errore per tratta (il surrogato si usa su una tratta alla volta)
let e = Dict{Int,Vector{Float64}}()
    for i in eachindex(rv); push!(get!(e, rv[i], Float64[]), 100 * abs(pD[i] - yv[i]) / yv[i]); end
    mx = [maximum(v) for v in values(e)]; md = [mean(v) for v in values(e)]
    say(@sprintf("  per tratta (D): errore %% medio sulle 288 coppie: mediana %.3f, p95 %.3f, max %.3f; errore massimo nella tratta: mediana %.3f, p95 %.3f, max %.2f",
                 median(md), quantile(md, 0.95), maximum(md), median(mx), quantile(mx, 0.95), maximum(mx)))
    rk = sort(collect(e); by = x -> -mean(x[2]))[1:5]
    say("  le 5 tratte con l'errore medio più alto: ", join((@sprintf("%d (%.2f%%, L %.0f km)", r, mean(v), Xv[findfirst(==(r), rv), 1]) for (r, v) in rk), ", "))
end
# errore per fascia di lunghezza e per regime
let L = Xv[:, findfirst(==("x_L_km"), NOMI)], ep = 100 .* abs.(pD .- yv) ./ yv
    say("  errore % (D) per fascia di lunghezza:")
    for (a, b) in ((0, 25), (25, 50), (50, 100), (100, 200), (200, 301))
        s = (L .>= a) .& (L .< b)
        say(@sprintf("    L %3d–%3d km: %6d casi, mediana %.3f, p95 %.3f, max %.2f", a, b, count(s), median(ep[s]), quantile(ep[s], 0.95), maximum(ep[s])))
    end
    m0 = Xv[:, jm] .== 0
    say(@sprintf("  sola batteria (m = 0): mediana %.3f, p95 %.3f | ibride: mediana %.3f, p95 %.3f",
                 median(ep[m0]), quantile(ep[m0], 0.95), median(ep[.!m0]), quantile(ep[.!m0], 0.95)))
end

# importanza
imp = EvoTrees.importance(rD.m)
open(joinpath(LOG, "01_importanza.csv"), "w") do io
    println(io, "caratteristica,importanza")
    for (k, v) in imp; println(io, k, ',', v); end
end
say("  importanza (guadagno, normalizzata), prime 10: ", join((@sprintf("%s %.3f", k, v) for (k, v) in imp[1:10]), ", "))

# predizioni e modello
Arrow.write(joinpath(DAT, "durata_validazione.arrow"),
            (tratta = Int32.(rv), coppia = tv.coppia, vero = yv, A = pA, B = pB, C = pC, D = pD))
try
    EvoTrees.save(rD.m, joinpath(DAT, "durata_D.bson")); say("  modello D salvato in ", joinpath(DAT, "durata_D.bson"))
catch e
    say("  modello non salvato: ", sprint(showerror, e))
end

# ── figure ───────────────────────────────────────────────────────────────────────
say("\n[5] figure")
rng = Xoshiro(3); ic = randperm(rng, length(yv))[1:60_000]
h(x) = x ./ 3600
plt = plot(layout = (1, 2), size = (1200, 560), dpi = 130, legend = false)
for (k, (nome, p)) in enumerate((("A: costante × durata minima", pA), ("D: boosting", pD)))
    scatter!(plt[k], h(yv[ic]), h(p[ic]); ms = 1.2, msw = 0, alpha = 0.3, color = k == 1 ? :gray40 : :steelblue,
             xlabel = "durata vera [h]", ylabel = "durata prevista [h]", title = nome, aspect_ratio = :equal)
    plot!(plt[k], [0, 12.5], [0, 12.5]; color = :black, lw = 1, ls = :dash)
end
savefig(plt, joinpath(LOG, "fig_previsto_vero.png"))

# errore relativo contro lunghezza, m, n (mediana e p95 per fascia)
function fasce!(p, x, e, nb, lab)
    q = quantile(x, range(0, 1; length = nb + 1)); xc = Float64[]; med = Float64[]; p95 = Float64[]
    for i in 1:nb
        s = (x .>= q[i]) .& (x .<= q[i+1]); any(s) || continue
        push!(xc, median(x[s])); push!(med, median(e[s])); push!(p95, quantile(e[s], 0.95))
    end
    plot!(p, xc, p95; lw = 2, color = :orange, label = "p95", xlabel = lab, ylabel = "errore [%]")
    plot!(p, xc, med; lw = 2, color = :steelblue, label = "mediana")
end
ep = 100 .* abs.(pD .- yv) ./ yv
plt = plot(layout = (1, 3), size = (1500, 450), dpi = 130)
fasce!(plt[1], Xv[:, findfirst(==("x_L_km"), NOMI)], ep, 20, "lunghezza della tratta [km]")
fasce!(plt[2], Xv[:, jm], ep, 20, "m")
fasce!(plt[3], Xv[:, jn], ep, 20, "n")
plot!(plt[1]; title = "D: errore relativo sulla validazione")
savefig(plt, joinpath(LOG, "fig_errore_fasce.png"))

# distribuzione dell'errore relativo, A B D
plt = plot(size = (800, 450), dpi = 130, xlabel = "|errore| [%] (scala log)", ylabel = "quota dei casi con errore minore",
           xscale = :log10, legend = :bottomright, xlims = (1e-4, 100))
for (nome, p, col) in (("A", pA, :gray50), ("B", pB, :purple), ("C (2048 tratte)", pC, :lightblue), ("D (12288 tratte)", pD, :steelblue))
    e = sort(max.(100 .* abs.(p .- yv) ./ yv, 1e-4))
    plot!(plt, e[1:50:end], range(0, 1; length = length(e))[1:50:end]; lw = 2, color = col, label = nome)
end
savefig(plt, joinpath(LOG, "fig_distribuzione_errore.png"))

# curve di apprendimento della griglia
plt = plot(size = (800, 450), dpi = 130, xlabel = "numero di alberi", ylabel = "RMSE sulla validazione [s] (scala log)",
           yscale = :log10, legend = :topright)
for (k, v) in sort(collect(curve)); plot!(plt, 0:length(v)-1, v; lw = 1.5, label = k); end
plot!(plt, 0:length(rD.curva)-1, rD.curva; lw = 2.5, color = :black, label = "D, tutto l'addestramento")
savefig(plt, joinpath(LOG, "fig_curve_apprendimento.png"))

# importanza: stesso disegno di 02_figura_importanza.jl, dal CSV appena scritto
include(joinpath(@__DIR__, "02_figura_importanza.jl"))
say("  fig_previsto_vero.png, fig_errore_fasce.png, fig_distribuzione_errore.png, fig_curve_apprendimento.png, fig_importanza.png")

say(@sprintf("\ntempo totale: %.1f s", time() - t_inizio))
close(OUT)
