# fase10/03_banco.jl: passo 6c, la rete neurale sul banco di prova della fase 9 (passi 5a e 5b), accanto al boosting.
#
#   julia -t 8 --project=fase10 fase10/03_banco.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_03.txt 2>&1
#
# Grandezze previste dalla rete (pred_validazione_6b.arrow) → valuta() della fase 9 (D3 dalla regola C-rate > 20):
# fattibilità e costo caso per caso; una sola grandezza prevista (le altre vere); scelta fra le 288 coppie di ogni tratta
# (scelta secca e verifica delle prime k); una piccola prova dei margini (SOC, scarica). Il boosting con le stesse misure
# da surrogato_validazione.arrow (fase 9). Nessuna simulazione. Scrive in fase10_log: 03_banco.txt, 03_scelta.csv.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))     # valuta, taglie, grandezze_vere, sostituisci
const LOG = joinpath(BASE, "fase10_log")
const OUT = open(joinpath(LOG, "03_banco.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase10/03_banco.jl  ", now(), "  thread: ", Threads.nthreads())

const tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
const PR = Arrow.Table(joinpath(BASE, "fase10", "pred_validazione_6b.arrow"))
const SB = Arrow.Table(joinpath(BASE, "fase9", "surrogato_validazione.arrow"))
collect(PR.tratta) == collect(tv.tratta) == collect(SB.tratta) && collect(PR.coppia) == collect(tv.coppia) == collect(SB.coppia) ||
    error("previsioni non allineate alla validazione")
const M = collect(tv.m); const Nn = collect(tv.n); const L = collect(tv.x_L_km); const TR = Int.(tv.tratta); const CP = Int.(tv.coppia)
const STATO = collect(tv.stato); const IBR = M .> 0
const V = grandezze_vere(tv)
const FATT_VERO = collect(tv.fattibile); const D3_VERO = collect(tv.d3); const TOT_VERO = collect(tv.total_cost_EUR_km)
const RV = valuta(M, Nn, L, V; d3 = D3_VERO)                        # vincoli veri, vincolo per vincolo
all(RV.fattibile .== FATT_VERO) || error("collaudo del banco di prova non superato")

const Q = Dict(
    "rete" => (durata = collect(PR.durata), serbatoio = collect(PR.serbatoio), H2 = collect(PR.H2), SOC = collect(PR.SOC),
               scarica = collect(PR.p_scarica) .>= 0.5, vita_batt = collect(PR.vita_batt), vita_FC_f1 = collect(PR.vita_FC_f1),
               C_rate = collect(PR.C_rate)),
    "boosting" => (durata = collect(SB.durata), serbatoio = collect(SB.serbatoio), H2 = collect(SB.H2), SOC = collect(SB.SOC),
                   scarica = collect(SB.p_scarica) .>= 0.5, vita_batt = collect(SB.vita_batt), vita_FC_f1 = collect(SB.vita_FC_f1),
                   C_rate = collect(SB.C_rate)))
const PSC = Dict("rete" => collect(PR.p_scarica), "boosting" => collect(SB.p_scarica))
const MODELLI = ("boosting", "rete")
R = Dict(k => valuta(M, Nn, L, Q[k]) for k in MODELLI)

function errcost(ct, sel)
    e = 100 .* abs.(ct[sel] .- TOT_VERO[sel]) ./ TOT_VERO[sel]
    return (mediana = median(e), p95 = quantile(e, 0.95), p99 = quantile(e, 0.99), bias = 100mean((ct[sel] .- TOT_VERO[sel]) ./ TOT_VERO[sel]))
end

# ── 5a ──
say("\n[1] caso per caso (passo 5a): fattibilità e costo")
for k in MODELLI
    r = R[k]
    tp = count(r.fattibile .& FATT_VERO); fn = count(.!r.fattibile .& FATT_VERO); fp = count(r.fattibile .& .!FATT_VERO)
    say(@sprintf("  %-9s fattibilità giusta %.3f%%; fattibili scartati %.2f%%; non fattibili promossi %.2f%%; detti fattibili e lo sono %.3f%%",
                 k, 100count(r.fattibile .== FATT_VERO) / length(M), 100fn / count(FATT_VERO), 100fp / count(.!FATT_VERO), 100tp / (tp + fp)))
end
say("  vincolo per vincolo: giusto % (mancati / in più)")
for (nome, a, f) in (("D3", D3_VERO, r -> r.d3), ("massa", RV.viol_massa, r -> r.viol_massa), ("SOC < 0,2", RV.viol_soc, r -> r.viol_soc),
                     ("scarica", RV.viol_scarica, r -> r.viol_scarica))
    say("    ", rpad(nome, 10), join((let b = f(R[k]); @sprintf("%s %.3f%% (%d / %d)", k, 100count(a .== b) / length(a), count(a .& .!b), count(.!a .& b)) end
                                    for k in MODELLI), "   "))
end
say("  costo senza penalità, errore relativo % sui casi davvero fattibili (mediana / p95 / p99; bias):")
for (nome, s) in (("tutti", FATT_VERO), ("sola batteria", FATT_VERO .& .!IBR), ("ibridi", FATT_VERO .& IBR))
    say("    ", rpad(nome, 14), join((let r = R[k], e = errcost(r.costo_totale, s .& .!r.d3)
        @sprintf("%s %.3f / %.3f / %.3f (%+.2f%%)", k, e.mediana, e.p95, e.p99, e.bias) end for k in MODELLI), "   "))
end
say("  una sola grandezza prevista dalla rete (le altre vere): fattibilità giusta; costo ibridi mediana / p95; sola batteria mediana / p95")
for g in NOMI_Q
    r = valuta(M, Nn, L, sostituisci(V, Q["rete"], g))
    s = FATT_VERO .& .!r.d3 .& isfinite.(r.costo_totale)
    ei = errcost(r.costo_totale, s .& IBR); eb = errcost(r.costo_totale, s .& .!IBR)
    say(@sprintf("    %-11s %.3f%%   %.3f%% / %.3f%%   %.3f%% / %.3f%%", g, 100count(r.fattibile .== FATT_VERO) / length(M),
                 ei.mediana, ei.p95, eb.mediana, eb.p95))
end

# ── 5b ──
const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const TRATTE = sort(collect(keys(RIGHE)))
const BEST = Dict(r => minimum(TOT_VERO[i] for i in RIGHE[r] if FATT_VERO[i]) for r in TRATTE)
const KS = (1, 2, 3, 5, 10)
"""Per ogni tratta: per k in KS, rimpianto della migliore davvero fattibile fra le prime k del surrogato (NaN se nessuna)."""
function scelta(fatt, costo)
    out = Dict(k => fill(NaN, length(TRATTE)) for k in KS)
    for (t, r) in enumerate(TRATTE)
        ii = [i for i in RIGHE[r] if fatt[i]]
        ord = ii[sortperm(costo[ii])]
        for k in KS
            c = [i for i in ord[1:min(k, end)] if FATT_VERO[i]]
            isempty(c) || (out[k][t] = minimum(TOT_VERO[c]) / BEST[r] - 1)
        end
    end
    return out
end
riga_s(nome, v) = (n = length(v); rr = filter(isfinite, v);
    @sprintf("  %-34s non fattibili %5.2f%% | rimpianto mediana %.3f%%, p90 %.2f%%, p95 %.2f%%; entro 1%% %.1f%%", nome,
             100count(!isfinite, v) / n, 100median(rr), 100quantile(rr, 0.9), 100quantile(rr, 0.95), 100count(<=(0.01), rr) / n))
say("\n[2] scelta fra le 288 coppie di ognuna delle ", length(TRATTE), " tratte (passo 5b)")
res = NamedTuple[]
for k in MODELLI
    s = scelta(R[k].fattibile, R[k].costo_totale)
    for kk in KS
        say(riga_s("$k, " * (kk == 1 ? "scelta secca" : "verifica delle prime $kk"), s[kk]))
        rr = filter(isfinite, s[kk])
        push!(res, (modello = k, k = kk, non_fattibili_pct = 100count(!isfinite, s[kk]) / length(TRATTE), rimpianto_mediana_pct = 100median(rr),
                    rimpianto_p95_pct = 100quantile(rr, 0.95), entro_1pct = 100count(<=(0.01), rr) / length(TRATTE)))
    end
end
open(joinpath(LOG, "03_scelta.csv"), "w") do io
    println(io, join(keys(res[1]), ','))
    for x in res; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : v for v in values(x)), ',')); end
end
# cause delle scelte secche non fattibili, per la rete
let s1 = scelta(R["rete"].fattibile, R["rete"].costo_totale)[1], r = R["rete"]
    bad = Int[]
    for (t, tr) in enumerate(TRATTE)
        isfinite(s1[t]) && continue
        ii = [i for i in RIGHE[tr] if r.fattibile[i]]; isempty(ii) && continue
        push!(bad, ii[argmin(r.costo_totale[ii])])
    end
    say(@sprintf("  rete, %d scelte secche non fattibili: violano davvero D3 %d, massa %d, SOC %d, scarica %d; SOC vero mediana %.3f, previsto %.3f",
                 length(bad), count(i -> D3_VERO[i], bad), count(i -> RV.viol_massa[i], bad), count(i -> RV.viol_soc[i], bad),
                 count(i -> RV.viol_scarica[i], bad), median(V.SOC[bad]), median(Q["rete"].SOC[bad])))
end

# ── margini ──
say("\n[3] margini con la rete: SOC previsto ≥ 0,2 + δ, probabilità di scarica < p (scelta secca e verifica delle prime 3 e 5)")
let q = Q["rete"], r = R["rete"]
    for dsoc in (0.0, 0.005, 0.01, 0.02, 0.03), pmax in (0.5, 0.3, 0.1)
        amm = .!r.d3 .& .!r.viol_massa .& (q.SOC .>= 0.2 + dsoc) .& (PSC["rete"] .< pmax)
        s = scelta(amm, r.costo_totale)
        say(@sprintf("  δSOC %.3f, p < %.1f: ", dsoc, pmax), join((let rr = filter(isfinite, s[kk])
            @sprintf("k=%d non fattibili %5.2f%% rimpianto mediana %.3f%%", kk, 100count(!isfinite, s[kk]) / length(TRATTE), 100median(rr)) end
            for kk in (1, 3, 5)), " | "))
    end
end
close(OUT)
