# fase10/05_variante.jl: passo 6e, variante della rete: 60 epoche (invece di 40) e una nona testa, la probabilità che il
# progetto sia fattibile. Tutto il resto come il passo 6b (stessi dati, rete 4 × 256, lotti, Adam coseno 1e-3 → 1e-5, seme 1).
#
#   julia -t 8 --project=fase10 fase10/05_variante.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_05.txt 2>&1
#
# Poi: metriche per grandezza contro 6b e boosting; la nuova testa come classificatore di fattibilità; il banco di prova del
# passo 5b (scelta fra le 288 coppie) con diverse regole di ammissione: i vincoli calcolati (come 6c), con il margine piccolo,
# la sola probabilità di fattibilità ≥ τ, e vincoli + probabilità. Nessuna simulazione.
# Scrive in ~/Documents/lavoro/ml_treno_dati/fase10: rete_6e.jld2, pred_validazione_6e.arrow; in fase10_log: 05_variante.txt,
# 05_storia.csv, 05_scelta.csv, fig_curve_6e.png.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))      # valuta, grandezze_vere
include(joinpath(@__DIR__, "comune.jl"))
using Plots
gr()
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase10_log")
const DAT = joinpath(BASE, "fase10")
const OUT = open(joinpath(LOG, "05_variante.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase10/05_variante.jl  ", now(), "  thread: ", Threads.nthreads(), "  Flux ", pkgversion(Flux), "  julia ", VERSION)
const T0 = time()

const IMPOSTAZIONI = (epoche = 60, lotto = 4096, lr = 1f-3, lr_fine = 1f-5, larghezza = 256, strati = 4, seme = 1, pazienza = 5)
say("impostazioni: ", IMPOSTAZIONI, "; teste: ", join((h.nome for h in TESTE_9), ", "))
ta = Arrow.Table(joinpath(TAB, "addestramento.arrow")); tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
norm = normalizzazione(ta)
da = prepara(ta, norm; hs = TESTE_9); dv = prepara(tv, norm; hs = TESTE_9)
sc = scale_bersagli(da)
say(@sprintf("dati: addestramento %d righe, validazione %d; fattibili nell'addestramento %.1f%%", size(da.X, 2), size(dv.X, 2), 100mean(da.Y[9, :])))

say("\n[1] addestramento")
model, storia = addestra(da, dv, sc; epoche = IMPOSTAZIONI.epoche, lotto = IMPOSTAZIONI.lotto, lr = IMPOSTAZIONI.lr,
                         lr_fine = IMPOSTAZIONI.lr_fine, larghezza = IMPOSTAZIONI.larghezza, strati = IMPOSTAZIONI.strati,
                         seme = IMPOSTAZIONI.seme, pazienza = IMPOSTAZIONI.pazienza, say)
say(@sprintf("  tempo di addestramento: %.1f min (%.1f s per epoca)", sum(s.tempo_s for s in storia) / 60, mean(s.tempo_s for s in storia)))
salva_modello(joinpath(DAT, "rete_6e.jld2"), model, norm, sc, merge(IMPOSTAZIONI, (nin = size(da.X, 1), nout = 9)))
open(joinpath(LOG, "05_storia.csv"), "w") do io
    println(io, "epoca,eta,perdita_add,perdita_val,", join((String(h.nome) for h in TESTE_9), ','), ",tempo_s")
    for s in storia; println(io, s.epoca, ',', s.eta, ',', s.perdita_add, ',', s.perdita_val, ',', join(s.per_testa_val, ','), ',', s.tempo_s); end
end

say("\n[2] metriche sulla validazione: variante 6e contro 6b e boosting")
p = previsioni(model, dv, sc)
ref = riferimento_boosting(joinpath(@__DIR__, ".."))
m6b = Dict(x[1] => (parse(Float64, x[3]), parse(Float64, x[4])) for x in split.(readlines(joinpath(@__DIR__, "risultati", "02_metriche.csv"))[2:end], ','))
for x in metriche(tv, p, dv)
    b = ref[x.grandezza]; c = m6b[x.grandezza]
    if x.tipo == "accuratezza"
        say(@sprintf("  %-11s accuratezza 6e %.2f%% | 6b %.2f%% | boosting %.2f%%", x.grandezza, x.mediana, c[1], b.mediana))
    else
        say(@sprintf("  %-11s mediana / p95: 6e %.3f / %.3f | 6b %.3f / %.3f | boosting %.3f / %.3f", x.grandezza, x.mediana, x.p95, c...,
                     b.mediana, b.p95))
    end
end
Arrow.write(joinpath(DAT, "pred_validazione_6e.arrow"),
            (tratta = dv.tratta, coppia = dv.coppia, durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC,
             p_scarica = p.p_scarica, vita_batt = p.vita_batt, vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate, p_fattibile = p.p_fattibile))

# ── la testa di fattibilità e il banco di prova ──────────────────────────────────
const M = collect(tv.m); const Nn = collect(tv.n); const L = collect(tv.x_L_km); const TR = Int.(tv.tratta)
const FATT_VERO = collect(tv.fattibile); const TOT_VERO = collect(tv.total_cost_EUR_km)
q6e = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
       vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
v6e = valuta(M, Nn, L, q6e)
pr6b = Arrow.Table(joinpath(DAT, "pred_validazione_6b.arrow"))
q6b = (durata = collect(pr6b.durata), serbatoio = collect(pr6b.serbatoio), H2 = collect(pr6b.H2), SOC = collect(pr6b.SOC),
       scarica = collect(pr6b.p_scarica) .>= 0.5, vita_batt = collect(pr6b.vita_batt), vita_FC_f1 = collect(pr6b.vita_FC_f1), C_rate = collect(pr6b.C_rate))
v6b = valuta(M, Nn, L, q6b)
pf = p.p_fattibile
say("\n[3] fattibilità caso per caso")
say(@sprintf("  dai vincoli calcolati: 6b %.3f%%, 6e %.3f%% giusta", 100mean(v6b.fattibile .== FATT_VERO), 100mean(v6e.fattibile .== FATT_VERO)))
say(@sprintf("  dalla testa di fattibilità (p ≥ 0,5): %.3f%% giusta; Brier %.4f", 100mean((pf .>= 0.5) .== FATT_VERO), mean(abs2, pf .- FATT_VERO)))
say(@sprintf("  vincoli e testa d'accordo nel %.2f%% dei casi; quando sono d'accordo hanno ragione nel %.3f%%",
             100mean((pf .>= 0.5) .== v6e.fattibile), 100mean(((pf .>= 0.5) .== FATT_VERO)[(pf .>= 0.5) .== v6e.fattibile])))
say("  calibrazione della testa (fascia di p: casi, frequenza vera di fattibili):")
for a in 0:0.1:0.9
    s = (pf .>= a) .& (pf .< a + 0.1 + (a ≥ 0.9 ? 1e-9 : 0))
    any(s) && say(@sprintf("    [%.1f, %.1f): %7d, %.3f", a, a + 0.1, count(s), mean(FATT_VERO[s])))
end
let s = FATT_VERO
    e6b = 100 .* abs.(v6b.costo_totale[s .& .!v6b.d3] .- TOT_VERO[s .& .!v6b.d3]) ./ TOT_VERO[s .& .!v6b.d3]
    e6e = 100 .* abs.(v6e.costo_totale[s .& .!v6e.d3] .- TOT_VERO[s .& .!v6e.d3]) ./ TOT_VERO[s .& .!v6e.d3]
    say(@sprintf("  costo sui casi davvero fattibili: 6b mediana %.3f%% p95 %.3f%% | 6e mediana %.3f%% p95 %.3f%%", median(e6b),
                 quantile(e6b, 0.95), median(e6e), quantile(e6e, 0.95)))
end

const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const TRATTE = sort(collect(keys(RIGHE)))
const BEST = Dict(r => minimum(TOT_VERO[i] for i in RIGHE[r] if FATT_VERO[i]) for r in TRATTE)
function scelta(amm, costo; ks = (1, 3, 5))
    out = Dict(k => fill(NaN, length(TRATTE)) for k in ks); vuote = 0
    for (t, r) in enumerate(TRATTE)
        ii = [i for i in RIGHE[r] if amm[i]]
        isempty(ii) && (vuote += 1; continue)
        ord = ii[sortperm(costo[ii])]
        for k in ks
            c = [i for i in ord[1:min(k, end)] if FATT_VERO[i]]
            isempty(c) || (out[k][t] = minimum(TOT_VERO[c]) / BEST[r] - 1)
        end
    end
    return out, vuote
end
say("\n[4] scelta fra le 288 coppie (", length(TRATTE), " tratte): regole di ammissione")
righe = NamedTuple[]
regole = [("6b, vincoli (come 6c)", v6b.fattibile, v6b.costo_totale),
          ("6b, vincoli + margine (SOC ≥ 0,21, scarica < 0,1)", v6b.fattibile .& (q6b.SOC .>= 0.21) .& (collect(pr6b.p_scarica) .< 0.1), v6b.costo_totale),
          ("6e, vincoli", v6e.fattibile, v6e.costo_totale),
          ("6e, vincoli + margine", v6e.fattibile .& (p.SOC .>= 0.21) .& (p.p_scarica .< 0.1), v6e.costo_totale)]
for τ in (0.5, 0.7, 0.9, 0.95)
    push!(regole, ("6e, solo probabilità di fattibilità ≥ $τ", .!v6e.d3 .& (pf .>= τ), v6e.costo_totale))
    push!(regole, ("6e, vincoli + probabilità ≥ $τ", v6e.fattibile .& (pf .>= τ), v6e.costo_totale))
end
for (nome, amm, costo) in regole
    s, vuote = scelta(amm, costo)
    for k in (1, 3, 5)
        rr = filter(isfinite, s[k]); nf = 100count(!isfinite, s[k]) / length(TRATTE)
        push!(righe, (regola = nome, k = k, non_fattibili_pct = nf, senza_proposta = vuote, rimpianto_mediana_pct = 100median(rr),
                      rimpianto_p95_pct = 100quantile(rr, 0.95), entro_1pct = 100count(<=(0.01), rr) / length(TRATTE)))
    end
    a = righe[end-2]; b = righe[end-1]; c = righe[end]
    say(@sprintf("  %-50s secca: non fattibili %5.2f%%, rimpianto mediana %.3f%% p95 %.2f%% | prime 3: %4.2f%%, p95 %.2f%% | prime 5: %4.2f%%, p95 %.2f%%, entro 1%% %.1f%%%s",
                 nome, a.non_fattibili_pct, a.rimpianto_mediana_pct, a.rimpianto_p95_pct, b.non_fattibili_pct, b.rimpianto_p95_pct,
                 c.non_fattibili_pct, c.rimpianto_p95_pct, c.entro_1pct, vuote > 0 ? "; tratte senza proposta $vuote" : ""))
end
open(joinpath(LOG, "05_scelta.csv"), "w") do io
    println(io, join(keys(righe[1]), ','))
    for x in righe; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : replace(string(v), ',' => ';') for v in values(x)), ',')); end
end

# curve
e = [s.epoca for s in storia]
plt = plot(layout = (1, 2), size = (1400, 520), dpi = 120)
plot!(plt[1], e, [s.perdita_add for s in storia]; lw = 2, label = "addestramento", yscale = :log10, xlabel = "epoca", ylabel = "perdita totale (log)",
      title = "variante 6e: perdita totale (9 teste)")
plot!(plt[1], e, [s.perdita_val for s in storia]; lw = 2, label = "validazione")
for (k, h) in enumerate(TESTE_9)
    plot!(plt[2], e, [s.per_testa_val[k] for s in storia]; lw = 2, label = String(h.nome), yscale = :log10, xlabel = "epoca",
          ylabel = "perdita di validazione per testa (log)", title = "per testa", legend = :topright)
end
savefig(plt, joinpath(LOG, "fig_curve_6e.png"))
say(@sprintf("\ntempo totale: %.1f min", (time() - T0) / 60))
close(OUT)
