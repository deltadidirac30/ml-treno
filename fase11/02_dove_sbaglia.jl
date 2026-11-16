# fase11/02_dove_sbaglia.jl: passo 7b, dove sbaglia la rete neurale 6b (validazione, nessun addestramento, nessuna simulazione).
#
#   julia -t 8 --project=fase11 fase11/02_dove_sbaglia.jl > ~/Documents/lavoro/ml_treno_dati/fase11_log/log_02.txt 2>&1
#
# Dalle previsioni salvate al passo 6b: errori per tipo di tratta (lunghezza, pendenza, fermate, limiti, dislivello), per zona
# di (m, n), del SOC vicino ai limiti; per tratta: errore del costo e rimpianto della scelta (come il 6c), le tratte peggiori e
# la loro distanza dalla tratta di addestramento più vicina (66 caratteristiche standardizzate).
# Scrive in fase11_log: 02_dove_sbaglia.txt, 02_tratte.csv, fig_errori_tratta.png, fig_errori_mn.png.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
using Plots
gr()
const LOG = joinpath(BASE, "fase11_log")
const OUT = open(joinpath(LOG, "02_dove_sbaglia.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase11/02_dove_sbaglia.jl  ", now(), "  thread: ", Threads.nthreads())

const tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
const PR = Arrow.Table(joinpath(BASE, "fase10", "pred_validazione_6b.arrow"))
collect(PR.tratta) == collect(tv.tratta) && collect(PR.coppia) == collect(tv.coppia) || error("previsioni non allineate")
const M = collect(tv.m); const Nn = collect(tv.n); const L = collect(tv.x_L_km); const TR = Int.(tv.tratta); const ST = collect(tv.stato)
const Q = (durata = collect(PR.durata), serbatoio = collect(PR.serbatoio), H2 = collect(PR.H2), SOC = collect(PR.SOC),
           scarica = collect(PR.p_scarica) .>= 0.5, vita_batt = collect(PR.vita_batt), vita_FC_f1 = collect(PR.vita_FC_f1), C_rate = collect(PR.C_rate))
const V = grandezze_vere(tv)
const FATT = collect(tv.fattibile); const TOT = collect(tv.total_cost_EUR_km)
const RS = valuta(M, Nn, L, Q)
ibr = M .> 0; comp = ST .== 1
e_H2 = fill(NaN, length(M)); s = ibr .& comp; e_H2[s] = 100 .* abs.(Q.H2[s] .- V.H2[s]) ./ V.H2[s]
e_ser = fill(NaN, length(M)); e_ser[ibr] = 100 .* abs.(Q.serbatoio[ibr] .- V.serbatoio[ibr]) ./ V.serbatoio[ibr]
e_SOC = abs.(Q.SOC .- V.SOC)
e_vb = 100 .* abs.(Q.vita_batt .- V.vita_batt) ./ V.vita_batt
e_cost = fill(NaN, length(M)); s = FATT .& .!RS.d3; e_cost[s] = 100 .* abs.(RS.costo_totale[s] .- TOT[s]) ./ TOT[s]
fatt_ok = RS.fattibile .== FATT
med(v) = (w = filter(isfinite, v); isempty(w) ? NaN : median(w)); p95(v) = (w = filter(isfinite, v); isempty(w) ? NaN : quantile(w, 0.95))

# ── 1. per tipo di tratta ────────────────────────────────────────────────────────
say("\n[1] errori per tipo di tratta (fasce a quantili delle 2048 tratte di validazione; mediana e p95 sui casi della fascia)")
say("    H2 e serbatoio in %, SOC assoluto, costo % sui casi davvero fattibili, fattibilità giusta %")
for (c, nome) in ((:x_L_km, "lunghezza [km]"), (:x_slope_rms, "pendenza rms [‰]"), (:x_n_fermate, "fermate intermedie"),
                  (:x_vlim_mean, "limite medio [km/h]"), (:x_dislivello_m, "dislivello [m]"), (:x_stops_density, "fermate per km"))
    x = Float64.(getproperty(tv, c))
    q = quantile(x, [0, 0.2, 0.4, 0.6, 0.8, 1.0])
    say("  ", nome, ":")
    for i in 1:5
        f = (x .>= q[i]) .& (i == 5 ? (x .<= q[i+1]) : (x .< q[i+1]))
        any(f) || continue
        say(@sprintf("    %8.3g–%-8.3g  H2 %.2f / %5.1f   serbatoio %.2f / %5.1f   SOC %.4f / %.3f   costo %.2f / %4.1f   fattibilità %.2f",
                     q[i], q[i+1], med(e_H2[f]), p95(e_H2[f]), med(e_ser[f]), p95(e_ser[f]), med(e_SOC[f]), p95(e_SOC[f]),
                     med(e_cost[f]), p95(e_cost[f]), 100mean(fatt_ok[f])))
    end
end

# ── 2. per zona di (m, n) ────────────────────────────────────────────────────────
say("\n[2] errori per zona di (m, n)")
fasce_m = [("m = 0 (sola batteria)", M .== 0), ("0,03 ≤ m < 0,0957 (fascia D25 1)", (M .> 0) .& (M .< 0.0957)),
           ("0,0957 ≤ m < 0,1195 (fasce D25 2-3)", (M .>= 0.0957) .& (M .< 0.1195)), ("0,1195 ≤ m < 0,4", (M .>= 0.1195) .& (M .< 0.4)),
           ("0,4 ≤ m < 0,7", (M .>= 0.4) .& (M .< 0.7)), ("m ≥ 0,7", M .>= 0.7)]
for (nome, f) in fasce_m
    say(@sprintf("  %-36s %6d casi: H2 %.2f%%, SOC %.4f (p95 %.3f), vita batt %.2f%%, costo %.2f%% (p95 %.1f%%), fattibilità giusta %.2f%%",
                 nome, count(f), med(e_H2[f]), med(e_SOC[f]), p95(e_SOC[f]), med(e_vb[f]), med(e_cost[f]), p95(e_cost[f]), 100mean(fatt_ok[f])))
end
for (a, b) in ((0, 0.05), (0.05, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 1.01))
    f = (Nn .>= a) .& (Nn .< b)
    say(@sprintf("  %.2f ≤ n < %.2f %21s %6d casi: H2 %.2f%%, SOC %.4f (p95 %.3f), vita batt %.2f%%, costo %.2f%% (p95 %.1f%%), fattibilità giusta %.2f%%",
                 a, min(b, 1.0), "", count(f), med(e_H2[f]), med(e_SOC[f]), p95(e_SOC[f]), med(e_vb[f]), med(e_cost[f]), p95(e_cost[f]), 100mean(fatt_ok[f])))
end

# ── 3. SOC vicino ai limiti ──────────────────────────────────────────────────────
say("\n[3] errore del SOC finale per valore vero")
for (a, b) in ((0, 1e-9), (1e-9, 0.15), (0.15, 0.25), (0.25, 0.75), (0.75, 0.85), (0.85, 0.9001))
    f = (V.SOC .>= a) .& (V.SOC .< b)
    say(@sprintf("  SOC vero in [%.2f, %.2f): %7d casi, errore mediana %.4f, p95 %.3f; previsto dalla parte sbagliata di 0,2: %.2f%%",
                 a, b, count(f), med(e_SOC[f]), p95(e_SOC[f]), 100mean((Q.SOC[f] .< 0.2) .!= (V.SOC[f] .< 0.2))))
end

# ── 4. per tratta ────────────────────────────────────────────────────────────────
say("\n[4] per tratta: errore del costo e rimpianto della scelta secca fra le 288 coppie; distanza dall'addestramento")
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const NXC = [c for c in Arrow.names(CT) if c != :route_id]
XC = reduce(hcat, (collect(getproperty(CT, c)) for c in NXC))
GR_ADD = [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14]
TR_ADD = [r for r in 1:16384 if cld(r, 1024) in GR_ADD]
μ = mean(XC[TR_ADD, :]; dims = 1); σ = std(XC[TR_ADD, :]; dims = 1)
Z = (XC .- μ) ./ σ; ZA = Z[TR_ADD, :]
righe_t = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(righe_t, TR[i], Int[]), i); end
tratte = sort(collect(keys(righe_t)))
# distanza dal vicino più prossimo fra le tratte di addestramento, e la stessa tra tratte di addestramento (riferimento)
dv_ = zeros(length(tratte))      # un elemento per tratta: un Dict scritto da più thread non è sicuro
Threads.@threads for k in eachindex(tratte)
    r = tratte[k]; d = vec(sum((ZA .- Z[r:r, :]) .^ 2; dims = 2)); dv_[k] = sqrt(minimum(d))
end
dvic = Dict(zip(tratte, dv_))
R = NamedTuple[]
for r in tratte
    ii = righe_t[r]
    fv = [i for i in ii if FATT[i]]; best = minimum(TOT[fv])
    fs = [i for i in ii if RS.fattibile[i]]
    sc = isempty(fs) ? 0 : fs[argmin(RS.costo_totale[fs])]
    rimp = sc == 0 || !FATT[sc] ? NaN : TOT[sc] / best - 1
    push!(R, (tratta = r, L_km = XC[r, 1], d_vicino = dvic[r], costo_err_mediana = med(e_cost[ii]), SOC_err_mediana = med(e_SOC[ii]),
              H2_err_mediana = med(e_H2[ii]), fattibilita_giusta = 100mean(fatt_ok[ii]), scelta_fattibile = sc != 0 && FATT[sc], rimpianto = rimp))
end
open(joinpath(LOG, "02_tratte.csv"), "w") do io
    println(io, join(keys(R[1]), ','))
    for x in R; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end
dd = [x.d_vicino for x in R]; ce = [x.costo_err_mediana for x in R]
say(@sprintf("  distanza dalla tratta di addestramento più vicina: mediana %.2f, p95 %.2f, max %.2f", median(dd), quantile(dd, 0.95), maximum(dd)))
rango(v) = invperm(sortperm(v)) .* 1.0
say(@sprintf("  correlazione (Spearman) fra distanza ed errore mediano del costo della tratta: %.2f", cor(rango(dd), rango(ce))))
q = quantile(dd, [0, 0.25, 0.5, 0.75, 0.9, 1.0])
for i in 1:5
    s = [x for x in R if q[i] <= x.d_vicino <= q[i+1]]
    rr = filter(isfinite, [x.rimpianto for x in s])
    say(@sprintf("    distanza %.2f–%.2f: %4d tratte, errore del costo mediana %.2f%%, SOC %.4f, fattibilità %.2f%%, scelta secca non fattibile %.1f%%, rimpianto p95 %.1f%%",
                 q[i], q[i+1], length(s), median([x.costo_err_mediana for x in s]), median([x.SOC_err_mediana for x in s]),
                 median([x.fattibilita_giusta for x in s]), 100count(x -> !x.scelta_fattibile, s) / length(s), 100quantile(rr, 0.95)))
end
say("  le 10 tratte con l'errore del costo più alto:")
for x in sort(R; by = x -> -x.costo_err_mediana)[1:10]
    fx = Dict(c => XC[x.tratta, j] for (j, c) in enumerate(NXC))
    say(@sprintf("    %5d: costo %.1f%%, SOC %.3f, H2 %.1f%% | L %.1f km, fermate %d, pendenza rms %.1f‰, limite medio %.0f km/h, dislivello %.0f m, distanza %.2f",
                 x.tratta, x.costo_err_mediana, x.SOC_err_mediana, x.H2_err_mediana, fx[:x_L_km], Int(fx[:x_n_fermate]), fx[:x_slope_rms],
                 fx[:x_vlim_mean], fx[:x_dislivello_m], x.d_vicino))
end

# ── figure ───────────────────────────────────────────────────────────────────────
plt = plot(layout = (1, 2), size = (1300, 500), dpi = 120)
scatter!(plt[1], dd, ce; ms = 2.5, msw = 0, alpha = 0.5, legend = false, xlabel = "distanza dalla tratta di addestramento più vicina",
         ylabel = "errore mediano del costo nella tratta [%]", title = "errore per tratta contro distanza dall'addestramento", yscale = :log10)
scatter!(plt[2], [x.L_km for x in R], ce; ms = 2.5, msw = 0, alpha = 0.5, legend = false, xlabel = "lunghezza [km]",
         ylabel = "errore mediano del costo nella tratta [%]", title = "errore per tratta contro lunghezza", yscale = :log10)
savefig(plt, joinpath(LOG, "fig_errori_tratta.png"))
# mappa dell'errore del SOC in (m, n)
mb = 0:0.1:1.0; nb = 0:0.1:1.0
H = fill(NaN, length(nb) - 1, length(mb) - 1)
for i in 1:length(mb)-1, j in 1:length(nb)-1
    f = (M .>= mb[i]) .& (M .< (i == length(mb) - 1 ? 1.01 : mb[i+1])) .& (Nn .>= nb[j]) .& (Nn .< (j == length(nb) - 1 ? 1.01 : nb[j+1]))
    any(f) && (H[j, i] = median(e_SOC[f]))
end
plt = heatmap(mb[1:end-1] .+ 0.05, nb[1:end-1] .+ 0.05, H; xlabel = "m", ylabel = "n", title = "errore mediano del SOC finale (assoluto) per zona di (m, n)",
              size = (750, 620), dpi = 120, c = :viridis)
savefig(plt, joinpath(LOG, "fig_errori_mn.png"))
say("\nfigure: fig_errori_tratta.png, fig_errori_mn.png")
close(OUT)
