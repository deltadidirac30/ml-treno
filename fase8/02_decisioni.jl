# fase8/02_decisioni.jl: numeri per le tre decisioni sui dati prima del passo 5 (nessuna simulazione).
#
#   julia -t 8 --project=fase8 fase8/02_decisioni.jl > ~/Documents/lavoro/ml_treno_dati/fase8_log/log_02.txt 2>&1
#
# 1. tratte 2366, 14664 (righe in errore D29) e 13258 (oltre 12 h): dove stanno, quante coppie mancano, la migliore
# 2. energia di ricarica negativa (SOC finale > 0,8): quanto vale il credito nella migliore, e se la migliore cambia
#    azzerando il credito (E_ricarica = max(E, 0), costo ricalcolato con costo_da_grandezze, prezzi di default)
# 3. batterie che durano poco: quante migliori hanno vita < 1, 2, 5 anni, e come cambierebbe la migliore escludendo i
#    progetti con la batteria sotto 1 anno
# Scrive in fase8_log: 02_decisioni.txt.

include(joinpath(@__DIR__, "..", "fase4", "comune.jl"))   # carica_tutto, COL_COSTO, CFG (= ConfigModello())
using Statistics
const LOG8 = expanduser("~/Documents/lavoro/ml_treno_dati/fase8_log")
const OUT8 = open(joinpath(LOG8, "02_decisioni.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT8, s); flush(OUT8); flush(stdout))
say("fase8/02_decisioni.jl  ", now(), "  thread: ", Threads.nthreads())

cols = unique(vcat(["tratta", "coppia", "stato", "tipo_esito", "costo", "total_cost_EUR_km", "OPEX_batt_rech_EUR_km_att",
                    "vita_batt_anni", "num_repl_batt", "durata_viaggio_s"], COL_COSTO))
t0 = time(); D = carica_tutto(cols); say(@sprintf("caricate %d righe in %.1f s", length(D["tratta"]), time() - t0))
tr = Int.(D["tratta"]); fatt = D["tipo_esito"] .== 1
E = D["E_ricarica_rete_kWh"]; tot = D["total_cost_EUR_km"]

# migliore fattibile per tratta, dato un vettore di costi
function migliori(c, ammessa)
    best = fill(0, NTRATTE); cb = fill(Inf, NTRATTE)
    for i in eachindex(c)
        ammessa[i] || continue
        r = tr[i]; c[i] < cb[r] && (cb[r] = c[i]; best[r] = i)
    end
    return best, cb
end
b0, c0 = migliori(tot, fatt)
say("tratte con almeno una coppia fattibile: ", count(>(0), b0), " / ", NTRATTE)

# ── 1 ──
say("\n[1] tratte segnalate")
gr = Dict(1:16 .=> ["addestramento", "addestramento", "addestramento", "addestramento", "addestramento", "addestramento", "validazione",
                    "addestramento", "addestramento", "addestramento", "addestramento", "validazione", "addestramento", "addestramento", "test", "test"])
for r in (2366, 14664, 13258)
    s = tr .== r
    i = b0[r]
    say(@sprintf("  route %5d (%s): righe %d, errori %d, fattibili %d; migliore coppia %d (m %.4f, n %.4f) costo %.4f €/km, durata %.2f h",
                 r, gr[cld(r, 1024)], count(s), count(s .& (D["stato"] .== 3)), count(s .& fatt), D["coppia"][i], D["m"][i], D["n"][i],
                 c0[r], D["durata_viaggio_s"][i] / 3600))
end
let s = (tr .== 13258) .& fatt, d = D["durata_viaggio_s"]
    say(@sprintf("  13258: fattibili oltre 12 h %d su %d; la migliore è oltre 12 h: %s", count(s .& (d .> 43200)), count(s), d[b0[13258]] > 43200))
end
let s = tr .== 14664, cop = Set(Int.(D["coppia"][s .& (D["stato"] .== 3)]))
    # la migliore delle 288 potrebbe essere tra le coppie in errore? confronto con la migliore di tutte le tratte su quelle coppie
    say("  14664: coppie in errore ", length(cop), "; fra le migliori di tutte le tratte, quante cadono su quelle coppie: ",
        count(r -> b0[r] > 0 && Int(D["coppia"][b0[r]]) in cop, 1:NTRATTE), " / ", NTRATTE)
end

# ── 2 ──
say("\n[2] energia di ricarica negativa (SOC finale oltre lo 0,8 iniziale): credito nel costo")
neg = fatt .& (E .< 0)
say(@sprintf("  righe fattibili con E_ricarica < 0: %d (%.1f%% delle fattibili)", count(neg), 100count(neg) / count(fatt)))
bn = [r for r in 1:NTRATTE if b0[r] > 0 && E[b0[r]] < 0]
cred = [-D["OPEX_batt_rech_EUR_km_att"][b0[r]] / c0[r] for r in bn]
say(@sprintf("  tratte con la migliore a E_ricarica < 0: %d; credito sul costo della migliore: mediana %.2f%%, p95 %.2f%%, max %.2f%%",
             length(bn), 100median(cred), 100quantile(cred, 0.95), 100maximum(cred)))
# costo con il credito azzerato (solo le righe con E < 0 cambiano)
c1 = copy(tot)
idx = findall(neg)
Threads.@threads :dynamic for k in eachindex(idx)
    i = idx[k]
    g = Dict(c => D[c][i] for c in COL_COSTO); g["E_ricarica_rete_kWh"] = 0.0
    c1[i] = costo_da_grandezze(g, ParametriCosto(); cfg = CFG).costo_totale
end
# controllo: con E invariata costo_da_grandezze ridà total_cost (entro pochi ULP, fase 4)
let i = idx[1], g = Dict(c => D[c][idx[1]] for c in COL_COSTO)
    say(@sprintf("  controllo su una riga: costo_da_grandezze %.15g, registro %.15g", costo_da_grandezze(g, ParametriCosto(); cfg = CFG).costo_totale, tot[i]))
end
b1, cb1 = migliori(c1, fatt)
camb = [r for r in 1:NTRATTE if b0[r] > 0 && b1[r] != b0[r]]
dc = [100 * (cb1[r] - c0[r]) / c0[r] for r in 1:NTRATTE if b0[r] > 0]
say(@sprintf("  azzerando il credito: la migliore cambia in %d tratte; il costo della migliore sale in %d tratte, di al più %.2f%% (mediana fra quelle %.2f%%)",
             length(camb), count(>(1e-12), dc), maximum(dc), median(filter(>(1e-12), dc))))
if !isempty(camb)
    dm = [abs(D["m"][b1[r]] - D["m"][b0[r]]) for r in camb]; dn = [abs(D["n"][b1[r]] - D["n"][b0[r]]) for r in camb]
    say(@sprintf("    dove cambia: |Δm| mediana %.3f, |Δn| mediana %.3f; cambi di regime %d", median(dm), median(dn),
                 count(r -> (D["m"][b1[r]] == 0) != (D["m"][b0[r]] == 0), camb)))
end

# ── 3 ──
say("\n[3] batterie che durano poco")
va = D["vita_batt_anni"]; nr = D["num_repl_batt"]
vb = [va[b0[r]] for r in 1:NTRATTE if b0[r] > 0]
say(@sprintf("  vita della batteria nella migliore: < 1 anno %d tratte, < 2 anni %d, < 5 anni %d; mediana %.1f anni; sostituzioni nella migliore: max %d",
             count(<(1), vb), count(<(2), vb), count(<(5), vb), median(vb), maximum(nr[b0[r]] for r in 1:NTRATTE if b0[r] > 0)))
say(@sprintf("  righe fattibili con vita < 1 anno: %d (%.2f%% delle fattibili)", count(fatt .& (va .< 1)), 100count(fatt .& (va .< 1)) / count(fatt)))
for soglia in (1.0, 2.0)
    b2, cb2 = migliori(tot, fatt .& (va .>= soglia))
    senza = count(r -> b0[r] > 0 && b2[r] == 0, 1:NTRATTE)
    ch = [r for r in 1:NTRATTE if b0[r] > 0 && b2[r] > 0 && b2[r] != b0[r]]
    d = [100 * (cb2[r] - c0[r]) / c0[r] for r in ch]
    say(@sprintf("  escludendo i progetti con vita < %.0f anni: tratte senza più coppie fattibili %d; la migliore cambia in %d tratte (costo +%.2f%% di mediana, max +%.2f%%)",
                 soglia, senza, length(ch), isempty(d) ? 0.0 : median(d), isempty(d) ? 0.0 : maximum(d)))
end
close(OUT8)
