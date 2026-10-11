# Valutazione del simulatore (train-powertrain, sola lettura) in punti (m, n) sulle tratte DoE, in thread, con cache.
# Modello corretta, ConfigModello di default (= config.txt delle campagne), andata e ritorno, 195 t.

using TrainPowertrain

const TP_RADICE = "/Users/kairos/Documents/lavoro/train-powertrain"
const CFG       = ConfigModello()
const PESO      = 195_000.0
const DIREZIONE = "andata&ritorno"

const _TRATTE = Ref{Dict{String,Any}}()
function tratte_doe()
    isassigned(_TRATTE) && return _TRATTE[]
    T = leggi_tratte_materializzate(joinpath(TP_RADICE, "tratte_doe_matlab"))
    _TRATTE[] = Dict(t.id => (cp = t.cp, pre = PrecalcoloTratta(t.cp, DIREZIONE)) for t in T)
    return _TRATTE[]
end

"""
    esito_punto(e) -> NamedTuple

Esito di una valutazione: costo (obiettivo, con penalità), fattibile (completed e penalità 0) e la causa della non
fattibilità: SOC (SOC finale < 0,2 o scarica totale: penalità 5000 e 3000), massa (penalità 1000), D3 (scartato,
batteria sottodimensionata), altro (errore o n = 0).
"""
function esito_punto(e)
    pen = round(Int, e.penalita)
    massa = e.stato === :completed && pen in (1000, 4000, 6000, 9000)
    soc   = e.stato === :completed && (pen % 1000 == 0) && (pen - (massa ? 1000 : 0)) > 0
    d3    = e.stato === :rejected && occursin("sottodimensionata", e.motivo)
    fatt  = e.stato === :completed && pen == 0
    return (costo = e.costo, stato = String(e.stato), penalita = e.penalita, fattibile = fatt,
            viol_SOC = soc, viol_massa = massa, viol_D3 = d3, viol_altro = !fatt && !soc && !massa && !d3,
            SOC_fine = e.risultato === nothing ? NaN : e.risultato.SOC_batt[end],
            massa_kg = e.risultato === nothing ? NaN : e.risultato.peso_sistema_propulsione)
end

"Valuta i punti (tratta, m, n) in thread; i punti ripetuti si valutano una volta."
function valuta_punti(tratte, ms, ns)
    T = tratte_doe()
    chiavi = collect(zip(tratte, ms, ns))
    unici = unique(chiavi)
    ris = Vector{Any}(undef, length(unici))
    Threads.@threads :dynamic for i in eachindex(unici)
        t, m, n = unici[i]; x = T[t]
        ris[i] = esito_punto(valuta_progetto(Float64(m), Float64(n), PESO, x.cp, DIREZIONE; config = CFG, precalcolo = x.pre))
    end
    pos = Dict(k => i for (i, k) in enumerate(unici))
    return DataFrame([ris[pos[k]] for k in chiavi])
end
