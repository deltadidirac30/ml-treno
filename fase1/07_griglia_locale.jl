# Fase 1 (completamento): griglia locale fitta attorno al miglior punto noto di ogni tratta reale distinta
# (passo 0,0005 in m e n; m* ± 0,01, n* ± 0,02), più il conteggio dei punti a sola batteria valutati dalla forza bruta.
# La rifinitura della forza bruta parte dai 5 migliori punti della griglia a passo 0,01, non dall'ottimo di NOMAD-PB:
# questa griglia controlla l'intorno dell'ottimo attuale (Sulmona: m* = 0,1133, a sinistra della soglia D20 0,1195).
#
# Uso, da ml_treno/fase1:   julia -t 8 --project=. 07_griglia_locale.jl
# Scrive dati/griglia_locale_reali.csv e aggiunge a dati/controlli_forza_bruta.txt.
using CSV, DataFrames, Printf
include(joinpath(@__DIR__, "uscite.jl"))
const TP = "/Users/kairos/Documents/lavoro/train-powertrain"
const DATI = joinpath(@__DIR__, "dati")
const STORIE = "/Users/kairos/Documents/lavoro/ml_treno_dati/forza_bruta_reali"
ott = CSV.read(joinpath(DATI, "ottimi_reali.csv"), DataFrame)
reali = Dict(t.id => t for t in TrainPowertrain.Campagna.leggi_tratte_reali(; cartella = joinpath(TP, "tratte_reali")))
out = open(joinpath(DATI, "controlli_forza_bruta.txt"), "a")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))
say("\n[griglia locale] passo 0,0005, m* ± 0,01 (m ≥ 0,03 se ibrido; m = 0 fisso se sola batteria), n* ± 0,02")
df = DataFrame()
for t in ["Sulmona-Carpinone", "Calabria", "Firenze", "Canavese"]
    r = ott[findfirst(==(t), ott.tratta), :]
    cp = reali[t].cp; pre = PrecalcoloTratta(cp, DIREZIONE)
    ms = r.m_star == 0 ? [0.0] : [m for m in (r.m_star - 0.01):0.0005:(r.m_star + 0.01) if m >= CONFIG.m_min_fc]
    ns = [n for n in (r.n_star - 0.02):0.0005:(r.n_star + 0.02) if 0 < n <= 1]
    pts = [(m, n) for m in ms for n in ns]
    c = fill(Inf, length(pts)); fat = falses(length(pts))
    Threads.@threads :dynamic for i in eachindex(pts)
        e = valuta_progetto(pts[i][1], pts[i][2], PESO_A_CARICO, cp, DIREZIONE; config = CONFIG, precalcolo = pre)
        c[i] = e.costo; fat[i] = e.stato === :completed && e.penalita == 0
    end
    i = argmin([fat[k] ? c[k] : Inf for k in eachindex(c)])
    sc = 100 * (c[i] - r.costo_star) / r.costo_star
    st = CSV.read(joinpath(STORIE, "$(t)_storia.csv"), DataFrame)
    nb = count(==(0.0), st.m); nbf = count(k -> st.m[k] == 0 && st.costo[k] < 1000, 1:nrow(st))
    say(@sprintf("  %-18s %d punti, fattibili %d; migliore m %.5f n %.5f costo %.10f (%+.4f%% sulla verità %.10f). Forza bruta: %d punti a sola batteria valutati, fattibili %d",
                 t, length(pts), count(fat), pts[i]..., c[i], sc, r.costo_star, nb, nbf))
    push!(df, (tratta = t, punti = length(pts), fattibili = count(fat), m = pts[i][1], n = pts[i][2], costo = c[i],
               costo_verita = r.costo_star, scarto_pct = sc, fb_punti_sola_batteria = nb, fb_sola_batteria_fattibili = nbf))
end
CSV.write(joinpath(DATI, "griglia_locale_reali.csv"), df)
close(out)
