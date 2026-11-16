# fase11/01_quanti_dati.jl: passo 7a, quanti dati servono. Curva di apprendimento della rete neurale.
#
#   julia -t 8 --project=fase11 fase11/01_quanti_dati.jl > ~/Documents/lavoro/ml_treno_dati/fase11_log/log_01.txt 2>&1
#
# La rete del passo 6b (8 teste, 4 × 256, 40 epoche, Adam coseno 1e-3 → 1e-5, seme 1, arresto anticipato con pazienza 5),
# riaddestrata su sottoinsiemi annidati dei gruppi Sobol di addestramento: {1, 2} (2048 tratte), {1–4} (4096),
# {1–6, 8, 9} (8192). Normalizzazione e scale dai soli dati usati. Il punto a 12 288 tratte è la rete 6b.
# Per ognuna, sulla validazione: errori per grandezza (come il 6b) e scelta fra le 288 coppie (come il 6c: scelta secca e
# verifica delle prime 5). Nessuna simulazione. Il test non si tocca.
# Scrive in ~/Documents/lavoro/ml_treno_dati/fase11: rete_7a_<n>.jld2; in fase11_log: 01_quanti_dati.txt, 01_curva.csv,
# fig_curva_apprendimento.png.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
using Plots
gr()
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase11_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase11"); mkpath(DAT)
const OUT = open(joinpath(LOG, "01_quanti_dati.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase11/01_quanti_dati.jl  ", now(), "  thread: ", Threads.nthreads(), "  Flux ", pkgversion(Flux))
const T0 = time()

const SOTTOINSIEMI = [[1, 2], [1, 2, 3, 4], [1, 2, 3, 4, 5, 6, 8, 9]]
ta = Arrow.Table(joinpath(TAB, "addestramento.arrow")); tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
const GA = collect(ta.gruppo)

# banco di prova sulla validazione (come fase10/03_banco.jl)
const M = collect(tv.m); const Nn = collect(tv.n); const L = collect(tv.x_L_km); const TR = Int.(tv.tratta)
const FATT_VERO = collect(tv.fattibile); const TOT_VERO = collect(tv.total_cost_EUR_km)
const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const TRATTE = sort(collect(keys(RIGHE)))
const BEST = Dict(r => minimum(TOT_VERO[i] for i in RIGHE[r] if FATT_VERO[i]) for r in TRATTE)
function banco(p)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    v = valuta(M, Nn, L, q)
    out = Dict(k => fill(NaN, length(TRATTE)) for k in (1, 5))
    for (t, r) in enumerate(TRATTE)
        ii = [i for i in RIGHE[r] if v.fattibile[i]]; isempty(ii) && continue
        ord = ii[sortperm(v.costo_totale[ii])]
        for k in (1, 5)
            c = [i for i in ord[1:min(k, end)] if FATT_VERO[i]]
            isempty(c) || (out[k][t] = minimum(TOT_VERO[c]) / BEST[r] - 1)
        end
    end
    s = FATT_VERO .& .!v.d3; ec = 100 .* abs.(v.costo_totale[s] .- TOT_VERO[s]) ./ TOT_VERO[s]
    r1 = filter(isfinite, out[1]); r5 = filter(isfinite, out[5])
    return (fattibilita = 100mean(v.fattibile .== FATT_VERO), costo_mediana = median(ec), costo_p95 = quantile(ec, 0.95),
            secca_nonf = 100count(!isfinite, out[1]) / length(TRATTE), secca_p95 = 100quantile(r1, 0.95), secca_entro1 = 100count(<=(0.01), r1) / length(TRATTE),
            top5_nonf = 100count(!isfinite, out[5]) / length(TRATTE), top5_p95 = 100quantile(r5, 0.95), top5_entro1 = 100count(<=(0.01), r5) / length(TRATTE))
end
function riassunto(ntratte, nrighe, p, dv, tempo, epoca)
    mt = Dict(x.grandezza => x for x in metriche(tv, p, dv))
    b = banco(p)
    return (tratte = ntratte, righe = nrighe, epoca_migliore = epoca, tempo_min = tempo / 60,
            durata = mt["durata"].mediana, serbatoio = mt["serbatoio"].mediana, H2 = mt["H2"].mediana, H2_p95 = mt["H2"].p95,
            SOC = mt["SOC"].mediana, SOC_p95 = mt["SOC"].p95, vita_batt = mt["vita_batt"].mediana, vita_FC = mt["vita_FC_f1"].mediana,
            C_rate = mt["C_rate"].mediana, scarica_acc = mt["scarica"].mediana, b...)
end
stampa(x) = say(@sprintf("  %5d tratte: durata %.3f%%, serbatoio %.2f%%, H2 %.2f%% (p95 %.1f%%), SOC %.4f (p95 %.3f), vita batt %.2f%%, vita FC %.2f%%, C-rate %.2f%%, scarica %.2f%% | fattibilità %.2f%%, costo %.2f%% (p95 %.1f%%) | secca: non fatt. %.1f%%, p95 %.1f%%, entro 1%% %.1f%% | prime 5: non fatt. %.2f%%, p95 %.2f%%, entro 1%% %.1f%%",
    x.tratte, x.durata, x.serbatoio, x.H2, x.H2_p95, x.SOC, x.SOC_p95, x.vita_batt, x.vita_FC, x.C_rate, x.scarica_acc, x.fattibilita,
    x.costo_mediana, x.costo_p95, x.secca_nonf, x.secca_p95, x.secca_entro1, x.top5_nonf, x.top5_p95, x.top5_entro1))

curva = NamedTuple[]
for gs in SOTTOINSIEMI
    sel = findall(in(gs), GA)
    nt = length(unique(Int.(ta.tratta[sel])))
    say("\n══ gruppi ", gs, ": ", nt, " tratte, ", length(sel), " righe")
    t0 = time()
    # normalizzazione e scale dai soli dati usati
    tsub = (; (c => getproperty(ta, c)[sel] for c in Arrow.names(ta))...)
    norm = normalizzazione(tsub)
    da = prepara(ta, norm; sel); dv = prepara(tv, norm); sc = scale_bersagli(da)
    model, storia = addestra(da, dv, sc; epoche = 40, lotto = 4096, lr = 1f-3, lr_fine = 1f-5, larghezza = 256, strati = 4, seme = 1,
                             pazienza = 5, say)
    tempo = time() - t0
    salva_modello(joinpath(DAT, "rete_7a_$(nt).jld2"), model, norm, sc, (epoche = 40, lotto = 4096, lr = 1f-3, lr_fine = 1f-5, larghezza = 256,
                  strati = 4, seme = 1, pazienza = 5, nin = size(da.X, 1), gruppi = gs))
    best = storia[argmin([s.perdita_val for s in storia])].epoca
    x = riassunto(nt, length(sel), previsioni(model, dv, sc), dv, tempo, best)
    push!(curva, x); stampa(x)
    GC.gc()
end
# 12 288 tratte: la rete 6b
let (model, norm, sc, info) = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
    dv = prepara(tv, norm)
    x = riassunto(12288, length(GA), previsioni(model, dv, sc), dv, 33.1 * 60, 40)
    say("\n══ tutti i 12 gruppi (rete 6b)"); push!(curva, x); stampa(x)
end
open(joinpath(LOG, "01_curva.csv"), "w") do io
    println(io, join(keys(curva[1]), ','))
    for x in curva; println(io, join((v isa AbstractFloat ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end

# figura
nt = [x.tratte for x in curva]
plt = plot(layout = (1, 3), size = (1650, 480), dpi = 120, xscale = :log2, xticks = (nt, string.(nt)))
for (c, lab) in ((:H2, "idrogeno"), (:serbatoio, "serbatoio"), (:vita_batt, "vita batteria"), (:vita_FC, "vita FC"), (:C_rate, "C-rate"))
    plot!(plt[1], nt, [getproperty(x, c) for x in curva]; marker = :circle, lw = 2, label = lab, xlabel = "tratte di addestramento",
          ylabel = "errore mediano [%]", title = "errori per grandezza", yscale = :log10)
end
plot!(plt[2], nt, [x.SOC for x in curva]; marker = :circle, lw = 2, label = "SOC finale (assoluto, mediana)", xlabel = "tratte di addestramento",
      title = "SOC finale e costo", legend = :topright)
plot!(plt[2], nt, [x.costo_mediana / 100 for x in curva]; marker = :square, lw = 2, label = "costo (errore relativo mediano)")
plot!(plt[3], nt, [x.secca_nonf for x in curva]; marker = :circle, lw = 2, label = "scelta secca: non fattibili [%]", xlabel = "tratte di addestramento",
      title = "scelta fra le 288 coppie", legend = :topright)
plot!(plt[3], nt, [x.secca_p95 for x in curva]; marker = :circle, lw = 2, label = "scelta secca: rimpianto p95 [%]")
plot!(plt[3], nt, [x.top5_p95 for x in curva]; marker = :square, lw = 2, label = "prime 5: rimpianto p95 [%]")
savefig(plt, joinpath(LOG, "fig_curva_apprendimento.png"))
say("\nfigura: fig_curva_apprendimento.png")
say(@sprintf("tempo totale: %.1f min", (time() - T0) / 60))
close(OUT)
