# fase10/02_addestra.jl: passo 6b, addestramento completo della rete neurale unica.
#
#   julia -t 8 --project=fase10 fase10/02_addestra.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_02.txt 2>&1
#
# Tutto l'addestramento (12 gruppi, 12 288 tratte), validazione (gruppi 7 e 12) per l'arresto anticipato; 40 epoche al più,
# rete 4 × 256, lotti di 4096, Adam con passo coseno 1e-3 → 1e-5, pesi uguali, seme 1. Il test non si tocca.
# Scrive in ~/Documents/lavoro/ml_treno_dati/fase10: rete_6b.jld2 (modello, normalizzazione, scale), pred_validazione_6b.arrow;
# in fase10_log: 02_addestra.txt, 02_storia.csv, 02_metriche.csv, fig_curve.png.

include(joinpath(@__DIR__, "comune.jl"))
using Plots
gr()
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase10_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase10"); mkpath(DAT)
const OUT = open(joinpath(LOG, "02_addestra.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase10/02_addestra.jl  ", now(), "  thread: ", Threads.nthreads(), "  Flux ", pkgversion(Flux), "  julia ", VERSION)
const T0 = time()

const IMPOSTAZIONI = (epoche = 40, lotto = 4096, lr = 1f-3, lr_fine = 1f-5, larghezza = 256, strati = 4, seme = 1, pazienza = 5)
say("impostazioni: ", IMPOSTAZIONI)
ta = Arrow.Table(joinpath(TAB, "addestramento.arrow")); tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
norm = normalizzazione(ta)
t0 = time(); da = prepara(ta, norm); dv = prepara(tv, norm)
sc = scale_bersagli(da)
say(@sprintf("dati: addestramento %d righe, validazione %d righe, %d ingressi (%.1f s)", size(da.X, 2), size(dv.X, 2), size(da.X, 1), time() - t0))

say("\n[1] addestramento")
model, storia = addestra(da, dv, sc; epoche = IMPOSTAZIONI.epoche, lotto = IMPOSTAZIONI.lotto, lr = IMPOSTAZIONI.lr,
                         lr_fine = IMPOSTAZIONI.lr_fine, larghezza = IMPOSTAZIONI.larghezza, strati = IMPOSTAZIONI.strati,
                         seme = IMPOSTAZIONI.seme, pazienza = IMPOSTAZIONI.pazienza, say)
say(@sprintf("  tempo di addestramento: %.1f min (%.1f s per epoca)", sum(s.tempo_s for s in storia) / 60, mean(s.tempo_s for s in storia)))
salva_modello(joinpath(DAT, "rete_6b.jld2"), model, norm, sc, merge(IMPOSTAZIONI, (nin = size(da.X, 1),)))
say("  modello salvato in ", joinpath(DAT, "rete_6b.jld2"))
open(joinpath(LOG, "02_storia.csv"), "w") do io
    println(io, "epoca,eta,perdita_add,perdita_val,", join((String(h.nome) for h in TESTE), ','), ",tempo_s")
    for s in storia
        println(io, s.epoca, ',', s.eta, ',', s.perdita_add, ',', s.perdita_val, ',', join(s.per_testa_val, ','), ',', s.tempo_s)
    end
end

say("\n[2] metriche sulla validazione (2048 tratte mai viste), rete contro boosting")
p = previsioni(model, dv, sc)
ref = riferimento_boosting(joinpath(@__DIR__, ".."))
mt = metriche(tv, p, dv)
for x in mt
    b = ref[x.grandezza]
    if x.tipo == "accuratezza"
        say(@sprintf("  %-11s accuratezza %.2f%%, Brier %.4f      | boosting %.2f%%, Brier %.4f", x.grandezza, x.mediana, x.p95, b.mediana, b.p95))
    else
        u = x.tipo == "rel" ? "%" : " (ass.)"
        say(@sprintf("  %-11s mediana %.3f%s  p95 %.3f  p99 %.3f  max %.3g   | boosting mediana %.3f  p95 %.3f", x.grandezza, x.mediana, u,
                     x.p95, x.p99, x.max, b.mediana, b.p95))
    end
end
open(joinpath(LOG, "02_metriche.csv"), "w") do io
    println(io, "grandezza,tipo,mediana,p95,p99,max,boosting_mediana,boosting_p95")
    for x in mt
        b = ref[x.grandezza]
        println(io, join((x.grandezza, x.tipo, @sprintf("%.6g", x.mediana), @sprintf("%.6g", x.p95), @sprintf("%.6g", x.p99),
                          @sprintf("%.6g", x.max), @sprintf("%.6g", b.mediana), @sprintf("%.6g", b.p95)), ','))
    end
end
# sovradattamento: le stesse metriche su un campione dell'addestramento (590 000 righe: gruppi 1 e 2)
let sel = findall(in((1, 2)), collect(ta.gruppo))
    dsub = prepara(ta, norm; sel)
    ps = previsioni(model, dsub, sc)
    tsub = (; (c => getproperty(ta, c)[sel] for c in (:y_durata_viaggio_s, :y_massa_serbatoio_kg, :y_H2_cons_kg, :y_SOC_end,
                                                       :y_vita_batt_cicli_viaggi, :y_vita_FC_f1_ore, :y_C_rate_scarica_max, :y_scarica_s))...)
    say("  sovradattamento: mediana sulle tratte di addestramento (gruppi 1–2) contro validazione: ",
        join((@sprintf("%s %.3f/%.3f", a.grandezza, a.mediana, b.mediana) for (a, b) in zip(metriche(tsub, ps, dsub), mt)), ", "))
end
Arrow.write(joinpath(DAT, "pred_validazione_6b.arrow"),
            (tratta = dv.tratta, coppia = dv.coppia, durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC,
             p_scarica = p.p_scarica, vita_batt = p.vita_batt, vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate))
say("  previsioni salvate in ", joinpath(DAT, "pred_validazione_6b.arrow"))

# curve
e = [s.epoca for s in storia]
plt = plot(layout = (1, 2), size = (1400, 520), dpi = 120)
plot!(plt[1], e, [s.perdita_add for s in storia]; lw = 2, marker = :circle, ms = 3, label = "addestramento", yscale = :log10,
      xlabel = "epoca", ylabel = "perdita totale (scala log)", title = "perdita totale")
plot!(plt[1], e, [s.perdita_val for s in storia]; lw = 2, marker = :circle, ms = 3, label = "validazione")
for (k, h) in enumerate(TESTE)
    plot!(plt[2], e, [s.per_testa_val[k] for s in storia]; lw = 2, label = String(h.nome), yscale = :log10, xlabel = "epoca",
          ylabel = "perdita di validazione per testa (scala log)", title = "perdita di validazione per testa", legend = :topright)
end
savefig(plt, joinpath(LOG, "fig_curve.png"))
say("\nfigura: fig_curve.png")
say(@sprintf("tempo totale: %.1f min", (time() - T0) / 60))
close(OUT)
