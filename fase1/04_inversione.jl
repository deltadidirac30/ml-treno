# Fase 1 b (controllo): in andata e ritorno la missione percorre la tratta nei due versi. Se il risultato del
# simulatore non cambia invertendo la tratta, le caratteristiche che dipendono dal verso (salita/discesa,
# bin spaziali, ...) non portano informazione. Qui ogni tratta DoE si inverte (stazioni, limiti e pendenza
# specchiati, pendenza col segno cambiato) e si rivaluta nel suo ottimo di riferimento (m*, n*).
#
# Uso, da ml_treno/fase1:   julia -t 8 --project=. 04_inversione.jl
# Scrive dati/inversione.csv e dati/controlli_inversione.txt.

using CSV, DataFrames, Printf, Statistics
include(joinpath(@__DIR__, "uscite.jl"))
const TP = "/Users/kairos/Documents/lavoro/train-powertrain"
const DATI = joinpath(@__DIR__, "dati")

function inverti(cp)
    L = cp.lunghezza_binario_andata
    p = cp.pendenze_note
    tratta_pendenza_metro(L, L .- reverse(cp.posizione_stazioni), L .- reverse(cp.s_max_l), reverse(cp.v_max_l), -reverse(p);
                          tempo_fermata = cp.tempo_fermata, tempo_capolinea = cp.tempo_capolinea)
end

ott = CSV.read(joinpath(DATI, "ottimi_riferimento.csv"), DataFrame)
usc = CSV.read(joinpath(DATI, "uscite_doe.csv"), DataFrame)
tratte = Dict(t.id => t for t in leggi_tratte_materializzate(joinpath(TP, "tratte_doe_matlab")))
N = nrow(ott); ris = Vector{Any}(undef, N)
Threads.@threads :dynamic for k in 1:N
    r = ott[k, :]
    cpi = inverti(tratte[r.tratta].cp)
    e, tr = valuta(cpi, r.m_star, r.n_star)
    ris[k] = (stato = e.stato, costo = e.costo, pen = e.penalita,
              H2 = e.stato === :completed ? e.diagnostica.cost_details["H2_cons_kg"] : NaN,
              durata = e.stato === :completed ? length(e.risultato.SOC_batt) : 0,
              SOC = e.stato === :completed ? e.diagnostica.cost_details["SOC_end"] : NaN)
end
df = DataFrame(tratta = ott.tratta, regime = usc.regime, costo = ott.costo_star,
               stato_inv = [String(x.stato) for x in ris], penalita_inv = [x.pen for x in ris],
               costo_inv = [x.costo for x in ris], scarto_pct = [100 * (x.costo - c) / c for (x, c) in zip(ris, ott.costo_star)],
               H2_scarto_pct = [100 * (x.H2 - h) / max(h, eps()) for (x, h) in zip(ris, usc.H2_viaggio_kg)],
               durata_scarto_s = [x.durata - d for (x, d) in zip(ris, usc.durata_viaggio_s)],
               SOC_fine = usc.SOC_fine, SOC_fine_inv = [x.SOC for x in ris])
CSV.write(joinpath(DATI, "inversione.csv"), df)
open(joinpath(DATI, "controlli_inversione.txt"), "w") do io
    for o in (stdout, io)
        ok = df.penalita_inv .== 0 .&& df.stato_inv .== "completed"
        println(o, "tratte invertite valutate nell'ottimo: ", N, "; completate senza penalità: ", count(ok))
        println(o, "stato/penalità nell'invertita: ", Dict(k => count(==(k), zip(df.stato_inv, df.penalita_inv)) for k in unique(zip(df.stato_inv, df.penalita_inv))))
        s = abs.(df.scarto_pct[ok])
        println(o, @sprintf("|scarto del costo| (senza penalità): mediana %.4f%%, p95 %.4f%%, p99 %.4f%%, max %.4f%%",
                            median(s), quantile(s, 0.95), quantile(s, 0.99), maximum(s)))
        h = abs.(df.H2_scarto_pct[ok .&& df.regime .== "ibrido"])
        println(o, @sprintf("|scarto H2| (ibride): mediana %.4f%%, p95 %.4f%%, max %.4f%%", median(h), quantile(h, 0.95), maximum(h)))
        println(o, "durata: scarto massimo ", maximum(abs.(df.durata_scarto_s[ok])), " s")
        bad = df[.!ok, :]
        println(o, "penalizzate nell'invertita: SOC finale nell'ottimo (vicino al vincolo 0,2?): ",
                join([@sprintf("%s %.4f→%.4f", r.tratta, r.SOC_fine, r.SOC_fine_inv) for r in eachrow(first(bad, 15))], "; "))
    end
end
