# fase12/02_tratte_vere.jl: passi 8b e 8c, la rete 6b su tratte vere, con il piano di REPORT_FASE12_ESAME.md.
#
#   julia -t 8 --project=fase12 fase12/02_tratte_vere.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_02.txt 2>&1
#
# 8b  tratte reali (train-powertrain/tratte_reali: Calabria, Canavese, Firenze; Firenze-BRoute = Firenze, Sulmona-Carpinone
#     esclusa): il simulatore valuta la griglia fitta intera (9702 progetti) e le 288 coppie della campagna; la rete la stessa
#     griglia. Strategie come il test: scelta secca, margine piccolo + verifica delle 5 migliori (i candidati sono punti della
#     griglia, già simulati). Riferimento: la migliore della griglia simulata.
# 8c  le 166 linee della rete (dati_rete/archivio/tratte_rete_20261110 = tratte_rete committata in correzioni-modello): il
#     simulatore valuta le 288 coppie di ogni linea; la rete sceglie fra le 288 (secca e verifica delle prime 5) e sulla griglia
#     fitta (margine piccolo + verifica delle 5 migliori, simulate). Riferimento: la migliore delle 288 simulate. A parte le 43
#     linee fuori dal dominio DoE (fase 5) e per distanza dalle tratte di addestramento.
# Caratteristiche delle tratte: fase 5 (caratteristiche_reali.arrow, caratteristiche_rete_20261110.arrow, stesso codice).
# Simulatore: TrainPowertrain invariato, configurazione della campagna (config.txt controllato), esegui_campagna.
# Scrive in fase12_log: 02_tratte_vere.txt, 02_reali.csv, 02_rete.csv, fig_reali_mappe.png, fig_rete_scelta.png.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
using Random, Plots
gr()
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const SIM = joinpath(BASE, "fase12", "sim_vere")
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_REALI = joinpath(TPR, "tratte_reali")
const DIR_RETE = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")
const OUT = open(joinpath(LOG, "02_tratte_vere.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/02_tratte_vere.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()

const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]); const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end
qq(p) = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)

"""Caratteristiche (66, ordine NORM.nx) per nome di tratta, da un file della fase 5."""
function caratteristiche(file)
    t = Arrow.Table(file)
    return Dict(String(t.tratta[i]) => [Float64(getproperty(t, c)[i]) for c in NORM.nx] for i in eachindex(t.tratta))
end
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
"""Rete + banco di prova per i punti della tratta di caratteristiche x."""
function rete(x, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    d = Dati(ingressi(repeat(x', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
             m, n, fill(x[IL], N), fill(x[IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    return valuta(m, n, fill(x[IL], N), qq(p)), p
end
function candidati(m, n, amm, costo; k = 5, dmin = 0.03)
    ord = sortperm([amm[i] ? costo[i] : Inf for i in eachindex(costo)]); scelti = Int[]
    for i in ord
        amm[i] || break
        all(j -> max(abs(m[i] - m[j]), abs(n[i] - n[j])) >= dmin - 1e-9, scelti) && push!(scelti, i)
        length(scelti) == k && break
    end
    return scelti
end

# ── simulatore ───────────────────────────────────────────────────────────────────
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = parse(Float64, s)
"""Simula le coppie su tutte le tratte; (tratta, m, n) => grandezze vere, fattibilità, costo."""
function simula(tratte, coppie, cartella)
    spec = CampagnaSpec(tratte = tratte, coppie = unique(coppie), cartella = cartella, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(cartella, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $cartella")
    out = Dict{Tuple{String,Float64,Float64},NamedTuple}()
    for l in readlines(joinpath(cartella, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        soc = c["stato"] == "rejected" ? 0.2 - pf(c["vincolo_soc_pt"]) / 100 : pf(c["SOC_end"])
        out[(String(c["tratta"]), pf(c["m"]), pf(c["n"]))] = (stato = c["stato"], fattibile = c["tipo_esito"] == "fattibile",
            costo_totale = pf(c["total_cost_EUR_km"]), H2 = pf(c["H2_cons_kg"]), SOC = soc, durata = pf(c["durata_viaggio_s"]))
    end
    return out
end
isdir(SIM) && rm(SIM; recursive = true); mkpath(SIM)

"""Errori per grandezza della rete sui punti simulati (H2 sui completati ibridi, SOC su tutti, costo sui fattibili)."""
function errori(v, p, s, nome, punti)
    eH = Float64[]; eS = Float64[]; eC = Float64[]; eD = Float64[]; ok = 0
    for (i, (m, n)) in enumerate(punti)
        t = s[(nome, m, n)]
        t.stato == "error" && continue
        push!(eS, abs(p.SOC[i] - t.SOC)); push!(eD, 100abs(p.durata[i] / t.durata - 1))
        t.stato == "completed" && m > 0 && push!(eH, 100abs(p.H2[i] / t.H2 - 1))
        t.fattibile && !v.d3[i] && push!(eC, 100abs(v.costo_totale[i] / t.costo_totale - 1))
        ok += v.fattibile[i] == t.fattibile
    end
    return (H2 = median(eH), SOC = median(eS), durata = median(eD), costo = median(eC), costo_p95 = quantile(eC, 0.95), fattibilita = 100ok / length(eS))
end

# ═════════════════════════ 8b: tratte reali ═════════════════════════════════════
say("\n══ 8b: tratte reali (riferimento: la griglia fitta simulata per intero)")
const XR = caratteristiche(joinpath(BASE, "fase5_dominio", "caratteristiche_reali.arrow"))
REALI = ["Calabria", "Canavese", "Firenze"]
righe_r = NamedTuple[]
plt = plot(layout = (length(REALI), 2), size = (1300, 450 * length(REALI)), dpi = 110)
for (k, nome) in enumerate(REALI)
    t0 = time()
    tc = leggi_tratte_reali([nome]; cartella = DIR_REALI)
    s = simula(tc, vcat(GRIGLIA, C288), joinpath(SIM, "reale_" * nome))
    v, p = rete(XR[nome], GRIGLIA)
    m = [g[1] for g in GRIGLIA]; n = [g[2] for g in GRIGLIA]
    tv(i) = s[(nome, m[i], n[i])]
    fv = [tv(i).fattibile for i in eachindex(GRIGLIA)]; cv = [tv(i).costo_totale for i in eachindex(GRIGLIA)]
    ib = argmin(ifelse.(fv, cv, Inf)); best = cv[ib]
    b288 = minimum(s[(nome, c...)].costo_totale for c in C288 if s[(nome, c...)].fattibile)
    c1 = candidati(m, n, v.fattibile, v.costo_totale)
    c2 = candidati(m, n, v.fattibile .& (p.SOC .>= 0.21) .& (p.p_scarica .< 0.1), v.costo_totale)
    rel(i) = fv[i] ? cv[i] / best - 1 : NaN
    b5(cc) = (f = filter(isfinite, [rel(i) for i in cc]); isempty(f) ? NaN : minimum(f))
    e = errori(v, p, s, nome, GRIGLIA)
    x = (tratta = nome, L_km = XR[nome][IL], fattibili_veri = count(fv), migliore_m = m[ib], migliore_n = n[ib], migliore_costo = best,
         migliore_288_rel = b288 / best - 1, secca_m = m[c1[1]], secca_n = n[c1[1]], secca_rel = rel(c1[1]), secca_costo_prev = v.costo_totale[c1[1]],
         margine_secca_rel = rel(c2[1]), margine_top5_rel = b5(c2), m_scelta = m[c2[argmin([isfinite(rel(i)) ? rel(i) : Inf for i in c2])]],
         n_scelta = n[c2[argmin([isfinite(rel(i)) ? rel(i) : Inf for i in c2])]], err_H2 = e.H2, err_SOC = e.SOC, err_durata = e.durata,
         err_costo = e.costo, err_costo_p95 = e.costo_p95, fattibilita = e.fattibilita)
    push!(righe_r, x)
    say(@sprintf("  %-9s (L %.1f km, %.1f s): fattibili %d su %d. Migliore simulata: m %.2f, n %.2f, %.4f €/km (migliore delle 288: %+.2f%%).",
                 nome, x.L_km, time() - t0, count(fv), length(fv), x.migliore_m, x.migliore_n, best, 100x.migliore_288_rel))
    say(@sprintf("            rete: errori mediani H2 %.2f%%, SOC %.4f, durata %.2f%%, costo %.2f%% (p95 %.1f%%), fattibilità giusta %.2f%%",
                 e.H2, e.SOC, e.durata, e.costo, e.costo_p95, e.fattibilita))
    say(@sprintf("            scelta secca (m %.2f, n %.2f): %s; margine, scelta secca: %s; margine + verifica delle prime 5: %s (m %.2f, n %.2f)",
                 x.secca_m, x.secca_n, isfinite(x.secca_rel) ? @sprintf("%+.2f%%", 100x.secca_rel) : "NON FATTIBILE",
                 isfinite(x.margine_secca_rel) ? @sprintf("%+.2f%%", 100x.margine_secca_rel) : "NON FATTIBILE",
                 isfinite(x.margine_top5_rel) ? @sprintf("%+.2f%%", 100x.margine_top5_rel) : "NESSUNA FATTIBILE", x.m_scelta, x.n_scelta))
    # mappe: costo vero (fattibili) e costo della rete (detti fattibili)
    Cv = fill(NaN, length(NS), length(MS)); Cr = fill(NaN, length(NS), length(MS))
    for i in eachindex(GRIGLIA)
        a = findfirst(==(m[i]), MS); b = findfirst(==(n[i]), NS)
        fv[i] && (Cv[b, a] = cv[i]); v.fattibile[i] && (Cr[b, a] = v.costo_totale[i])
    end
    lim = (best, best * 1.5)
    heatmap!(plt[k, 1], MS, NS, Cv; clims = lim, c = :viridis, xlabel = "m", ylabel = "n", title = "$nome: costo vero (solo fattibili)")
    heatmap!(plt[k, 2], MS, NS, Cr; clims = lim, c = :viridis, xlabel = "m", ylabel = "n", title = "$nome: costo della rete (detti fattibili)")
    for j in 1:2
        scatter!(plt[k, j], [x.migliore_m], [x.migliore_n]; marker = :star5, ms = 9, color = :red, label = j == 1 ? "migliore vera" : "")
        scatter!(plt[k, j], [x.m_scelta], [x.n_scelta]; marker = :circle, ms = 6, color = :white, msc = :black, label = j == 1 ? "scelta della rete" : "")
    end
end
savefig(plt, joinpath(LOG, "fig_reali_mappe.png"))
open(joinpath(LOG, "02_reali.csv"), "w") do io
    println(io, join(keys(righe_r[1]), ','))
    for x in righe_r; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end

# ═════════════════════════ 8c: le linee della rete ══════════════════════════════
say("\n══ 8c: le linee della rete (versione del 10/11; riferimento: la migliore delle 288 coppie simulate)")
const XL = caratteristiche(joinpath(BASE, "fase5_dominio", "caratteristiche_rete_20261110.arrow"))
const DOM = let l = readlines(joinpath(@__DIR__, "..", "fase5", "risultati", "03_dominio_tratte.csv")), h = split(l[1], ',')
    Dict(String(x[2]) => parse(Int, x[findfirst(==("n_fuori"), h)]) for x in split.(l[2:end], ',') if x[1] == "rete_20261110")
end
nomi = sort(collect(keys(XL)))
t0 = time()
TC = leggi_tratte_reali(nomi; cartella = DIR_RETE)
say(@sprintf("  %d linee lette; fuori dal dominio DoE (fase 5): %d", length(TC), count(r -> DOM[r] > 0, nomi)))
S288 = simula(TC, C288, joinpath(SIM, "rete_288"))
say(@sprintf("  288 coppie × %d linee simulate in %.1f min", length(TC), (time() - t0) / 60))
# distanza dalle tratte di addestramento (66 caratteristiche standardizzate sulle tratte di addestramento)
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
XA = reduce(hcat, (collect(getproperty(CT, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
μa = mean(XA; dims = 1); σa = std(XA; dims = 1); ZA = (XA .- μa) ./ σa
dist(x) = sqrt(minimum(vec(sum((ZA .- ((x' .- μa) ./ σa)) .^ 2; dims = 2))))
righe_l = NamedTuple[]
t0 = time()
for (k, tc) in enumerate(TC)
    nome = tc.id; x = XL[nome]
    tv(c) = S288[(nome, c...)]
    fv = [tv(c).fattibile for c in C288]; cv = [tv(c).costo_totale for c in C288]
    best = minimum(cv[fv])
    v, p = rete(x, C288)
    e = errori(v, p, S288, nome, C288)
    ii = [i for i in 1:288 if v.fattibile[i]]; ord = ii[sortperm(v.costo_totale[ii])]
    s1 = isempty(ord) || !fv[ord[1]] ? NaN : cv[ord[1]] / best - 1
    c5 = [i for i in ord[1:min(5, end)] if fv[i]]; s5 = isempty(c5) ? NaN : minimum(cv[c5]) / best - 1
    # griglia fitta con margine + verifica delle 5 migliori (simulate)
    vg, pg = rete(x, GRIGLIA)
    mg = [g[1] for g in GRIGLIA]; ng = [g[2] for g in GRIGLIA]
    c2 = candidati(mg, ng, vg.fattibile .& (pg.SOC .>= 0.21) .& (pg.p_scarica .< 0.1), vg.costo_totale)
    g5 = NaN
    if !isempty(c2)
        sg = simula([tc], [(mg[i], ng[i]) for i in c2], joinpath(SIM, "rete_griglia_" * nome))
        f = [sg[(nome, mg[i], ng[i])].costo_totale / best - 1 for i in c2 if sg[(nome, mg[i], ng[i])].fattibile]
        isempty(f) || (g5 = minimum(f))
    end
    push!(righe_l, (linea = nome, L_km = x[IL], fuori_dominio = DOM[nome], distanza = dist(x), fattibili_veri = count(fv),
                    err_H2 = e.H2, err_SOC = e.SOC, err_costo = e.costo, fattibilita = e.fattibilita, scelta288_secca = s1, scelta288_top5 = s5,
                    griglia_margine_top5 = g5))
end
say(@sprintf("  rete e verifiche sulla griglia: %.1f min", (time() - t0) / 60))
open(joinpath(LOG, "02_rete.csv"), "w") do io
    println(io, join(keys(righe_l[1]), ','))
    for x in righe_l; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end
function riassunto(nome, R)
    isempty(R) && return
    q(c) = [getproperty(x, c) for x in R]
    sx(v) = (rr = filter(isfinite, v); (nf = 100count(!isfinite, v) / length(v), med = 100median(rr), p95 = 100quantile(rr, 0.95),
                                           e1 = 100count(<=(0.01), rr) / length(v), meglio = 100count(<(-1e-9), rr) / length(v)))
    a = sx(q(:scelta288_secca)); b = sx(q(:scelta288_top5)); c = sx(q(:griglia_margine_top5))
    say(@sprintf("  %-34s %3d linee | errori mediani: H2 %.2f%%, SOC %.4f, costo %.2f%%, fattibilità giusta %.2f%%", nome, length(R),
                 median(q(:err_H2)), median(q(:err_SOC)), median(q(:err_costo)), median(q(:fattibilita))))
    say(@sprintf("      288, scelta secca: non fattibili %.1f%%, rimpianto mediana %.2f%%, p95 %.1f%%, entro 1%% %.1f%%", a.nf, a.med, a.p95, a.e1))
    say(@sprintf("      288 + verifica delle prime 5: non fattibili %.1f%%, rimpianto mediana %.2f%%, p95 %.1f%%, entro 1%% %.1f%%", b.nf, b.med, b.p95, b.e1))
    say(@sprintf("      griglia + margine + verifica delle prime 5: non fattibili %.1f%%, mediana %+.2f%%, p95 %+.1f%%, più economica della migliore delle 288 %.1f%%, entro +1%% %.1f%%",
                 c.nf, c.med, c.p95, c.meglio, c.e1))
end
say("\n  risultati (rispetto alla migliore delle 288 coppie simulate):")
riassunto("tutte le linee", righe_l)
riassunto("dentro il dominio DoE", [x for x in righe_l if x.fuori_dominio == 0])
riassunto("fuori dal dominio DoE (1–2 caratt.)", [x for x in righe_l if x.fuori_dominio > 0])
dd = [x.distanza for x in righe_l]; q = quantile(dd, [0, 0.5, 0.9, 1.0])
say(@sprintf("  distanza dalla tratta di addestramento più vicina: mediana %.2f, p90 %.2f, max %.2f (test DoE: mediana 2,9, max 6,6)", q[2], q[3], q[4]))
riassunto("distanza sotto la mediana", [x for x in righe_l if x.distanza <= q[2]])
riassunto("distanza fra mediana e p90", [x for x in righe_l if q[2] < x.distanza <= q[3]])
riassunto("il 10% più lontano", [x for x in righe_l if x.distanza > q[3]])
let peg = sort([x for x in righe_l]; by = x -> -x.err_costo)[1:8]
    say("  le 8 linee con l'errore del costo più alto:")
    for x in peg
        say(@sprintf("    %-40s L %5.1f km, fuori dominio %d, distanza %.2f: costo %.1f%%, SOC %.3f, H2 %.1f%%; scelta 288+5 %s, griglia+margine+5 %s",
                     x.linea, x.L_km, x.fuori_dominio, x.distanza, x.err_costo, x.err_SOC, x.err_H2,
                     isfinite(x.scelta288_top5) ? @sprintf("%+.1f%%", 100x.scelta288_top5) : "non fattibile",
                     isfinite(x.griglia_margine_top5) ? @sprintf("%+.1f%%", 100x.griglia_margine_top5) : "non fattibile"))
    end
end
plt = plot(size = (950, 520), dpi = 130, xlabel = "costo della scelta rispetto alla migliore delle 288 [%]", ylabel = "quota delle linee",
           legend = :bottomright, xlims = (-10, 15), title = "le 166 linee della rete (curve sotto 1: scelte non fattibili)")
for (nome, sel, col) in (("dentro il dominio", x -> x.fuori_dominio == 0, :steelblue), ("fuori dal dominio", x -> x.fuori_dominio > 0, :darkorange))
    R = [x for x in righe_l if sel(x)]
    for (c, st, lab) in ((:scelta288_top5, :dash, "288 + 5 verifiche"), (:griglia_margine_top5, :solid, "griglia + margine + 5 verifiche"))
        rr = sort(100 .* filter(isfinite, [getproperty(x, c) for x in R]))
        plot!(plt, rr, (1:length(rr)) ./ length(R); lw = 2, color = col, ls = st, label = "$nome, $lab", seriestype = :steppost)
    end
end
vline!(plt, [0]; color = :black, lw = 1, label = "")
savefig(plt, joinpath(LOG, "fig_rete_scelta.png"))
say("\nfigure: fig_reali_mappe.png, fig_rete_scelta.png")
say(@sprintf("tempo totale: %.1f min", (time() - T0) / 60))
close(OUT)
