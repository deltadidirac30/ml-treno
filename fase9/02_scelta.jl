# fase9/02_scelta.jl: passo 5b, la scelta della coppia migliore fra le 288 di ogni tratta di validazione.
#
#   julia -t 8 --project=fase9 fase9/02_scelta.jl > ~/Documents/lavoro/ml_treno_dati/fase9_log/log_02.txt 2>&1
#
# Per ogni tratta: la migliore vera (fattibile, costo minimo del simulatore) contro la scelta del surrogato (fattibile e
# più economica secondo il surrogato, da surrogato_validazione.arrow del passo 5a). Rimpianto = costo vero della scelta /
# costo della migliore − 1; scelta non fattibile = errore grave.
# Più: surrogato + verifica (le k coppie migliori secondo il surrogato verificate dal simulatore, qui lette dal registro:
# tutte le 288 sono simulate); due confronti semplici (la coppia più spesso migliore nell'addestramento; la migliore della
# tratta di addestramento più vicina nelle 66 caratteristiche standardizzate). Nessuna simulazione.
# Scrive in fase9_log: 02_scelta.txt, 02_tratte.csv, fig_rimpianto_*.png.

include(joinpath(@__DIR__, "comune.jl"))
using Random, Plots
gr()
const LOG = joinpath(BASE, "fase9_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase9")
const OUT = open(joinpath(LOG, "02_scelta.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase9/02_scelta.jl  ", now(), "  thread: ", Threads.nthreads())

const S = Arrow.Table(joinpath(DAT, "surrogato_validazione.arrow"))
const TR = Int.(S.tratta); const CP = Int.(S.coppia); const M = collect(S.m)
const F_S = collect(S.fattibile); const C_S = collect(S.costo_totale)
const F_V = collect(S.vero_fattibile); const C_V = collect(S.vero_costo_totale)
const TRATTE = sort(unique(TR))
const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const KS = (1, 2, 3, 5, 10)
say("validazione: ", length(TRATTE), " tratte; tratte segnalate presenti: ", intersect(TRATTE, [2366, 14664, 13258]))

# ── confronti semplici dall'addestramento ────────────────────────────────────────
const RIA = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "tratte_riassunto.arrow"))
const GRUPPI_ADD = [g for (g, s) in (split.(readlines(joinpath(@__DIR__, "..", "fase6", "risultati", "01_gruppi.csv"))[2:end], ',') .|>
                                     x -> (parse(Int, x[1]), x[4])) if s == "addestramento"]
const TR_ADD = [r for r in 1:16384 if cld(r, 1024) in GRUPPI_ADD]
const COP_MIG = Int.(RIA.coppia_migliore)
popolare = let c = Dict{Int,Int}(); for r in TR_ADD; c[COP_MIG[r]] = get(c, COP_MIG[r], 0) + 1; end; argmax(c) end
say(@sprintf("coppia più spesso migliore nell'addestramento: %d (migliore in %d tratte su %d)", popolare,
             count(r -> COP_MIG[r] == popolare, TR_ADD), length(TR_ADD)))
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const XC = reduce(hcat, (collect(getproperty(CT, c)) for c in Arrow.names(CT) if c != :route_id))
μ = mean(XC[TR_ADD, :]; dims = 1); σ = std(XC[TR_ADD, :]; dims = 1)
const Z = (XC .- μ) ./ σ
const ZA = Z[TR_ADD, :]
function vicina(r)
    d = vec(sum((ZA .- Z[r:r, :]) .^ 2; dims = 2))
    return TR_ADD[argmin(d)]
end

# ── per tratta ───────────────────────────────────────────────────────────────────
function per_tratta(r)
    ii = RIGHE[r]
    fv = [i for i in ii if F_V[i]]
    ib = fv[argmin(C_V[fv])]; cbest = C_V[ib]
    costo_vero_di(c) = (j = findfirst(i -> CP[i] == c, ii); j === nothing ? (false, NaN) : (F_V[ii[j]], C_V[ii[j]]))
    # scelta del surrogato e le sue k migliori
    fs = [i for i in ii if F_S[i]]
    ord = fs[sortperm(C_S[fs])]
    scelta = isempty(ord) ? 0 : ord[1]
    topk = Dict{Int,Float64}()
    for k in KS
        cand = [i for i in ord[1:min(k, end)] if F_V[i]]
        topk[k] = isempty(cand) ? NaN : minimum(C_V[cand]) / cbest - 1
    end
    rank = scelta == 0 || !F_V[scelta] ? 0 : 1 + count(i -> C_V[i] < C_V[scelta], fv)
    # confronti semplici
    fp, cp_ = costo_vero_di(popolare)
    cv = COP_MIG[vicina(r)]; fvn, cvn = costo_vero_di(cv)
    return (tratta = r, L_km = XC[r, 1], n_fattibili_veri = length(fv), n_fattibili_surrogato = length(fs),
            coppia_migliore = CP[ib], m_migliore = M[ib], costo_migliore = cbest,
            coppia_surrogato = scelta == 0 ? 0 : CP[scelta], m_surrogato = scelta == 0 ? NaN : M[scelta],
            surrogato_fattibile = scelta != 0 && F_V[scelta],
            rimpianto = scelta != 0 && F_V[scelta] ? C_V[scelta] / cbest - 1 : NaN,
            costo_previsto_scelta = scelta == 0 ? NaN : C_S[scelta], costo_vero_scelta = scelta == 0 ? NaN : C_V[scelta],
            posto = rank, stessa_coppia = scelta != 0 && CP[scelta] == CP[ib],
            regime_giusto = scelta != 0 && (M[scelta] == 0) == (M[ib] == 0),
            top2 = topk[2], top3 = topk[3], top5 = topk[5], top10 = topk[10],
            popolare_fattibile = fp, popolare_rimpianto = fp ? cp_ / cbest - 1 : NaN,
            vicina_fattibile = fvn, vicina_rimpianto = fvn ? cvn / cbest - 1 : NaN)
end
t0 = time()
R = Vector{Any}(undef, length(TRATTE))
Threads.@threads :dynamic for k in eachindex(TRATTE)
    R[k] = per_tratta(TRATTE[k])
end
say(@sprintf("calcolo per tratta: %.1f s", time() - t0))
open(joinpath(LOG, "02_tratte.csv"), "w") do io
    println(io, join(keys(R[1]), ','))
    for x in R; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end

# ── riassunto ────────────────────────────────────────────────────────────────────
NT = length(R)
q(v, p) = isempty(v) ? NaN : quantile(v, p)
function riga(nome, fatt, rimp)
    rr = filter(isfinite, rimp)
    say(@sprintf("  %-40s non fattibile %5d (%5.2f%%) | rimpianto: mediana %.3f%%, p90 %.3f%%, p95 %.3f%%, max %.2f%%; entro 0,5%% %5.1f%%, entro 1%% %5.1f%%",
                 nome, count(!, fatt), 100count(!, fatt) / NT, 100q(rr, 0.5), 100q(rr, 0.9), 100q(rr, 0.95),
                 isempty(rr) ? NaN : 100maximum(rr), 100count(<=(0.005), rr) / NT, 100count(<=(0.01), rr) / NT))
end
say("\n[1] la scelta fra le 288 coppie, ", NT, " tratte di validazione (rimpianto sulle sole scelte fattibili; le percentuali 'entro' su tutte le tratte)")
say("  tratte in cui il surrogato non propone nulla (nessuna coppia detta fattibile): ", count(x -> x.coppia_surrogato == 0, R))
riga("surrogato, scelta secca", [x.surrogato_fattibile for x in R], [x.rimpianto for x in R])
for (k, c) in ((2, :top2), (3, :top3), (5, :top5), (10, :top10))
    v = [getproperty(x, c) for x in R]
    riga("surrogato + verifica delle prime $k", isfinite.(v), v)
end
riga("coppia più spesso migliore (fissa)", [x.popolare_fattibile for x in R], [x.popolare_rimpianto for x in R])
riga("migliore della tratta più vicina", [x.vicina_fattibile for x in R], [x.vicina_rimpianto for x in R])

say("\n[2] la scelta secca del surrogato, nel dettaglio")
say(@sprintf("  stessa coppia della migliore vera: %d tratte (%.1f%%); regime giusto (sola batteria / ibrido): %.1f%%",
             count(x -> x.stessa_coppia, R), 100count(x -> x.stessa_coppia, R) / NT, 100count(x -> x.regime_giusto, R) / NT))
pos = [x.posto for x in R if x.posto > 0]
say(@sprintf("  posto della scelta fra le coppie davvero fattibili (1 = la migliore): mediana %d, p90 %d, max %d; fra le prime 3: %.1f%%",
             median(pos), quantile(pos, 0.9), maximum(pos), 100count(<=(3), pos) / NT))
let s = [x for x in R if x.surrogato_fattibile]
    e = [x.costo_previsto_scelta / x.costo_vero_scelta - 1 for x in s]
    say(@sprintf("  costo previsto della scelta contro il suo costo vero: mediana %+.2f%%, p5 %+.2f%%, p95 %+.2f%% (negativo = il surrogato è ottimista)",
                 100median(e), 100quantile(e, 0.05), 100quantile(e, 0.95)))
end
for (nome, f) in (("migliore vera a sola batteria", x -> x.m_migliore == 0), ("migliore vera ibrida", x -> x.m_migliore > 0))
    s = [x for x in R if f(x)]
    rr = [x.rimpianto for x in s if isfinite(x.rimpianto)]
    say(@sprintf("  %-32s %4d tratte: scelta non fattibile %d, regime sbagliato %d, rimpianto mediana %.3f%% p95 %.3f%%",
                 nome, length(s), count(x -> !x.surrogato_fattibile, s), count(x -> !x.regime_giusto, s), 100median(rr), 100quantile(rr, 0.95)))
end
say("  per lunghezza (rimpianto mediana / p95; scelte non fattibili):")
for (a, b) in ((0, 25), (25, 100), (100, 200), (200, 301))
    s = [x for x in R if a <= x.L_km < b]; rr = [x.rimpianto for x in s if isfinite(x.rimpianto)]
    say(@sprintf("    %3d–%3d km: %4d tratte, %.3f%% / %.3f%%; non fattibili %d", a, b, length(s), 100median(rr), 100quantile(rr, 0.95),
                 count(x -> !x.surrogato_fattibile, s)))
end
let s = sort([x for x in R if isfinite(x.rimpianto)]; by = x -> -x.rimpianto)[1:5]
    say("  i 5 rimpianti più grandi: ", join((@sprintf("%d (%.1f%%, L %.0f km, m %.3f → %.3f)", x.tratta, 100x.rimpianto, x.L_km,
                                                     x.m_migliore, x.m_surrogato) for x in s), ", "))
end
let s = [x for x in R if !x.surrogato_fattibile && x.coppia_surrogato != 0]
    say("  scelte non fattibili, L: ", isempty(s) ? "—" : join((@sprintf("%d (%.0f km)", x.tratta, x.L_km) for x in s[1:min(10, end)]), ", "))
end

# ── 3. perché le scelte non fattibili ────────────────────────────────────────────
say("\n[3] le scelte non fattibili: quale vincolo violano davvero, e di quanto")
const TV = Arrow.Table(joinpath(TAB, "validazione.arrow"))
collect(TV.tratta) == TR && collect(TV.coppia) == CP || error("validazione non allineata a surrogato_validazione.arrow")
const VV = valuta(collect(TV.m), collect(TV.n), collect(TV.x_L_km), grandezze_vere(TV); d3 = collect(TV.d3))
const SOC_V = collect(TV.y_SOC_end); const SOC_S = collect(S.SOC)
const MASSA_V = let tg = Dict{Tuple{Float64,Float64},Any}()
    [begin t = get!(() -> taglie(TV.m[i], TV.n[i]), tg, (TV.m[i], TV.n[i])); t.massa_batt + t.massa_FC + TV.y_massa_serbatoio_kg[i] end for i in eachindex(TR)]
end
const PSC = collect(S.p_scarica)
ns = [x for x in R if x.coppia_surrogato != 0 && !x.surrogato_fattibile]
idx = [RIGHE[x.tratta][findfirst(i -> CP[i] == x.coppia_surrogato, RIGHE[x.tratta])] for x in ns]
say(@sprintf("  %d scelte non fattibili; vincolo violato davvero (anche più d'uno): D3 %d, massa %d, SOC %d, scarica %d",
             length(idx), count(i -> VV.d3[i], idx), count(i -> VV.viol_massa[i], idx), count(i -> VV.viol_soc[i], idx),
             count(i -> VV.viol_scarica[i], idx)))
let s = [i for i in idx if VV.viol_soc[i]]
    isempty(s) || say(@sprintf("  SOC: vero mediana %.4f (p5 %.4f), previsto mediana %.4f; vero entro 0,01 sotto il limite: %d su %d",
                               median(SOC_V[s]), quantile(SOC_V[s], 0.05), median(SOC_S[s]), count(>=(0.19), SOC_V[s]), length(s)))
end
let s = [i for i in idx if VV.viol_massa[i]]
    isempty(s) || say(@sprintf("  massa: oltre il limite di mediana %.0f kg (max %.0f); entro 100 kg: %d su %d",
                               median(MASSA_V[s] .- LIMITE_MASSA), maximum(MASSA_V[s] .- LIMITE_MASSA), count(<=(100), MASSA_V[s] .- LIMITE_MASSA), length(s)))
end
let s = [i for i in idx if VV.viol_scarica[i]]
    isempty(s) || say(@sprintf("  scarica: probabilità prevista mediana %.3f (max %.3f)", median(PSC[s]), maximum(PSC[s])))
end
# la migliore vera: quanto è vicina ai limiti (perché il surrogato ci cade sopra)
let ib = [RIGHE[x.tratta][findfirst(i -> CP[i] == x.coppia_migliore, RIGHE[x.tratta])] for x in R]
    say(@sprintf("  la migliore vera, in tutte le %d tratte: SOC finale entro 0,01 sopra 0,2 in %d (%.0f%%); massa entro 300 kg dal limite in %d (%.0f%%)",
                 length(ib), count(i -> SOC_V[i] < 0.21, ib), 100count(i -> SOC_V[i] < 0.21, ib) / length(ib),
                 count(i -> LIMITE_MASSA - MASSA_V[i] < 300, ib), 100count(i -> LIMITE_MASSA - MASSA_V[i] < 300, ib) / length(ib)))
end

# ── figure ───────────────────────────────────────────────────────────────────────
plt = plot(size = (850, 480), dpi = 130, xlabel = "rimpianto [%] (scala log)", ylabel = "quota delle tratte con rimpianto minore",
           xscale = :log10, xlims = (1e-2, 50), legend = :bottomright, title = "scelta fra le 288 coppie: rimpianto sulle tratte di validazione")
curva(v) = (r = sort(100 .* replace(v, NaN => Inf)); (max.(r, 1e-2), (1:length(r)) ./ length(r)))
for (nome, v, col, st) in (("surrogato, scelta secca", [x.rimpianto for x in R], :steelblue, :solid),
                           ("surrogato + verifica delle prime 3", [x.top3 for x in R], :steelblue, :dash),
                           ("surrogato + verifica delle prime 10", [x.top10 for x in R], :steelblue, :dot),
                           ("migliore della tratta più vicina", [x.vicina_rimpianto for x in R], :gray40, :solid),
                           ("coppia fissa più frequente", [x.popolare_rimpianto for x in R], :gray70, :solid))
    x, y = curva(v); f = isfinite.(x)
    plot!(plt, x[f], y[f]; lw = 2, color = col, ls = st, label = nome)
end
savefig(plt, joinpath(LOG, "fig_rimpianto.png"))
say("\nfigura: fig_rimpianto.png (le tratte con scelta non fattibile non arrivano mai: la curva si ferma sotto 1)")
close(OUT)
