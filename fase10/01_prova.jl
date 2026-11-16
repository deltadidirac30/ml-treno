# fase10/01_prova.jl: passo 6a, prova breve della rete neurale (dati, modello, perdita, addestramento, metriche).
#
#   julia -t 8 --project=fase10 fase10/01_prova.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_01.txt 2>&1
#
# Addestramento su 2 gruppi Sobol dell'addestramento (1 e 2: 2048 tratte), 5 epoche, validazione intera (gruppi 7 e 12).
# Controlli: ingressi senza NaN/Inf e di scala unitaria, bersagli e maschere coerenti con la tabella, la perdita che scende,
# previsioni nelle unità naturali, metriche come la fase 8 accanto al boosting (che però usa 12 288 tratte: il confronto
# vero è al passo 6b). Tempo per epoca e stima per l'addestramento completo.

include(joinpath(@__DIR__, "comune.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase10_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "01_prova.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase10/01_prova.jl  ", now(), "  thread: ", Threads.nthreads(), "  Flux ", pkgversion(Flux), "  julia ", VERSION)
const T0 = time()

ta = Arrow.Table(joinpath(TAB, "addestramento.arrow")); tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
norm = normalizzazione(ta)
say(@sprintf("caratteristiche con log con segno (|asimmetria| > 2): %d su %d: %s", count(c -> norm.trasf[c][1], norm.nx), length(norm.nx),
             join((String(c) for c in norm.nx if norm.trasf[c][1]), ", ")))
say("soglie D25: ", SOGLIE_D25)
dev = findall(in((1, 2)), collect(ta.gruppo))
t0 = time()
da = prepara(ta, norm; sel = dev); dv = prepara(tv, norm)
say(@sprintf("dati: addestramento %d righe (gruppi 1, 2), validazione %d righe; %d ingressi; %.1f s", size(da.X, 2), size(dv.X, 2), size(da.X, 1), time() - t0))

# controlli sui dati
say("\n[1] controlli")
say("  ingressi non finiti: addestramento ", count(!isfinite, da.X), ", validazione ", count(!isfinite, dv.X))
mx = vec(mean(da.X; dims = 2)); sx = vec(std(da.X; dims = 2))
say(@sprintf("  ingressi standardizzati (le 68 continue): media in [%.3f, %.3f], deviazione in [%.3f, %.3f] sui gruppi 1–2", extrema(mx[1:68])..., extrema(sx[1:68])...))
say(@sprintf("  indicatori: ibridi %.1f%%, fasce D25 1–4: %s", 100mean(da.X[69, :]), join((@sprintf("%.1f%%", 100mean(da.X[69+b, :])) for b in 1:4), ", ")))
sc = scale_bersagli(da)
for (k, h) in enumerate(TESTE)
    say(@sprintf("  testa %-9s righe con bersaglio: addestramento %7d, validazione %6d; bersaglio μ %.4f σ %.4f; non finiti %d",
                 h.nome, count(>(0), da.W[k, :]), count(>(0), dv.W[k, :]), sc.μ[k], sc.σ[k], count(!isfinite, da.Y[k, :])))
end
# il bersaglio della durata ricostruisce la durata vera
say(@sprintf("  ricostruzione: max |r·T − durata| = %.2e s", maximum(abs.(Float64.(dv.Y[1, :]) .* dv.T .- Float64.(tv.y_durata_viaggio_s)))))

say("\n[2] addestramento breve: 5 epoche, rete 4 × 256, lotti di 4096, Adam 1e-3 → 1e-5")
model, storia = addestra(da, dv, sc; epoche = 5, say)
tep = mean(s.tempo_s for s in storia)
say(@sprintf("  tempo per epoca: %.1f s su %d righe → stima per l'addestramento completo (3 538 939 righe): %.0f s per epoca, %.0f min per 40 epoche",
             tep, size(da.X, 2), tep * 3_538_939 / size(da.X, 2), tep * 3_538_939 / size(da.X, 2) * 40 / 60))
say("  la perdita di validazione scende: ", all(diff([s.perdita_val for s in storia]) .< 0) ? "sì, a ogni epoca" : "non a ogni epoca: " *
    join((@sprintf("%.4f", s.perdita_val) for s in storia), " → "))

say("\n[3] metriche sulla validazione nelle unità naturali (rete: 2048 tratte, 5 epoche; boosting: 12 288 tratte)")
t0 = time(); p = previsioni(model, dv, sc)
say(@sprintf("  previsioni su %d casi: %.2f s (%.2f µs a caso)", size(dv.X, 2), time() - t0, 1e6 * (time() - t0) / size(dv.X, 2)))
say("  SOC previsto in [0; 0,9]: ", all(0 .<= p.SOC .<= 0.9), "; durata > durata minima: ", all(p.durata .> dv.T), "; vite e masse positive: ",
    all(p.vita_batt .> 0) && all(p.serbatoio .>= 0))
ref = riferimento_boosting(joinpath(@__DIR__, ".."))
for x in metriche(tv, p, dv)
    b = get(ref, x.grandezza, nothing)
    if x.tipo == "accuratezza"
        say(@sprintf("  %-11s accuratezza %.2f%%, Brier %.4f      | boosting %.2f%%, Brier %.4f", x.grandezza, x.mediana, x.p95, b.mediana, b.p95))
    else
        u = x.tipo == "rel" ? "%" : " (assoluto)"
        say(@sprintf("  %-11s mediana %.3f%s  p95 %.3f  max %.3g   | boosting mediana %.3f  p95 %.3f", x.grandezza, x.mediana, u, x.p95, x.max, b.mediana, b.p95))
    end
end
say(@sprintf("\ntempo totale: %.1f s", time() - T0))
close(OUT)
