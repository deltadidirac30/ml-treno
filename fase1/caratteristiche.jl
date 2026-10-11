# Caratteristiche della tratta (input del surrogato), calcolate SOLO dal profilo della tratta così come lo
# vede il simulatore: `PrecalcoloTratta(cp, "andata")` di TrainPowertrain dà, sia per le tratte DoE sia per
# quelle reali, la pendenza metro per metro [m/m] (L+1 valori), le stazioni (0 e capolinea compresi), gli
# inizi dei limiti `s_max_l` (più la fine dell'ultimo) e le velocità `v_max_l`.
#
# Tre gruppi:
#   ORIG  le 69 caratteristiche di ml_treno/src/features.jl SENZA P_nom_fc e C_batt (variabili di progetto,
#         ora uscite): 67. Il codice è lo stesso di features.jl (copiato qui sotto, invariato nei calcoli),
#         cambia solo da dove arrivano p, limiti e fermate.
#   NUOVE proposte (solo profilo): n_fermate, dislivello (quota massima - minima), tempo minimo di
#         percorrenza ai limiti con le soste.
#   DIN   facoltative, da UNA dinamica del treno di riferimento (stessa del valutatore, massa del sistema di
#         propulsione nulla, andata e ritorno): durata, energia di trazione e di frenatura alle ruote.
#         Dipendono solo dalla tratta e dal treno fisso, non dal progetto (m, n).

using TrainPowertrain
using Statistics

include(joinpath(@__DIR__, "..", "src", "features.jl"))   # extract_features e FEATURE_NAMES (69) di ml_treno

const NOMI_ORIG  = [f for f in FEATURE_NAMES if !(f in ("P_nom_fc", "C_batt"))]   # 67
const NOMI_NUOVE = ["n_fermate", "dislivello_m", "tempo_limiti_ar_s"]
const NOMI_DIN   = ["din_durata_ar_s", "din_E_trazione_ar_kWh", "din_E_frenatura_ar_kWh"]

const TEMPO_FERMATA   = 120.0   # s, fissato nel simulatore (tratta_scalari.csv e tratte_reali/README.md)
const TEMPO_CAPOLINEA = 300.0   # s

"""
    profilo_tratta(cp) -> NamedTuple

Profilo in andata come lo usa il simulatore: L [km], p [‰] un valore per metro (i primi L), limiti come
segmenti (inizio_km, fine_km, v_kmh), fermate intermedie [km], quota h [m] relativa al primo punto.
"""
function profilo_tratta(cp)
    pre = PrecalcoloTratta(cp, "andata")
    Lm  = round(Int, cp.lunghezza_binario_andata)
    pend = pre.pendenze                                  # m/m, Lm+1 valori (punti 0..Lm)
    length(pend) == Lm + 1 || error("pendenza con $(length(pend)) valori, attesi $(Lm + 1)")
    p   = 1000.0 .* pend[1:Lm]                           # ‰, un valore per metro
    h   = vcat(0.0, cumsum(pend[1:Lm]))                  # m (1 m per passo)
    s, v = pre.s_max_l, pre.v_max_l
    length(s) == length(v) + 1 || error("s_max_l e v_max_l incoerenti")
    seg = [(s[i] / 1000, s[i+1] / 1000, v[i]) for i in eachindex(v)]
    staz = pre.posizione_stazioni
    fermate = staz[2:end-1] ./ 1000
    return (L = Lm / 1000, p = p, h = h, seg = seg, fermate = fermate, stazioni = staz)
end

"""Le 67 caratteristiche originali (ordine di NOMI_ORIG)."""
function caratteristiche_orig(pr)
    f = extract_features(; p = pr.p, vlim_segments = pr.seg, stops = collect(pr.fermate), L = pr.L,
                           P_nom_fc = 0.0, C_batt = 0.0)
    keep = [i for (i, n) in enumerate(FEATURE_NAMES) if !(n in ("P_nom_fc", "C_batt"))]
    return f[keep]
end

"""Le caratteristiche nuove proposte (ordine di NOMI_NUOVE)."""
function caratteristiche_nuove(pr)
    n_f   = length(pr.fermate)
    disl  = maximum(pr.h) - minimum(pr.h)
    # limite inferiore della durata in andata e ritorno: ogni tratto alla sua velocità limite, più le soste
    # (fermate intermedie in andata e in ritorno, capolinea una volta, come nella missione simulata)
    t_marcia = sum((b - a) * 1000 / (v / 3.6) for (a, b, v) in pr.seg)
    t_lim = 2 * t_marcia + 2 * n_f * TEMPO_FERMATA + TEMPO_CAPOLINEA
    return [Float64(n_f), disl, t_lim]
end

"""Caratteristiche dalla dinamica del treno di riferimento in andata e ritorno (ordine di NOMI_DIN)."""
function caratteristiche_dinamica(cp; peso_a_carico = 195_000.0, d6 = true)
    pre = PrecalcoloTratta(cp, "andata&ritorno")
    tp0 = TrainPowertrain.Routes.structure_caratteristiche_treno(0.0, 0.0, 0.0, peso_a_carico)
    dyn = train_dynamics(tp0, cp, "andata&ritorno"; pre, d6)
    P = dyn.P_tot                                  # kW, passo 1 s
    return [Float64(length(dyn.t)), sum(x -> max(x, 0.0), P) / 3600, sum(x -> max(-x, 0.0), P) / 3600]
end

const NOMI_CARATTERISTICHE = vcat(NOMI_ORIG, NOMI_NUOVE, NOMI_DIN)

function tutte_le_caratteristiche(cp)
    pr = profilo_tratta(cp)
    return vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr), caratteristiche_dinamica(cp))
end
