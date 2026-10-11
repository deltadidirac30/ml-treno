# Fase 3: tratte reali e taglie dalle formule del simulatore (train-powertrain, sola lettura).
# Si include dopo fase1/uscite.jl (CONFIG, DIREZIONE, PESO_A_CARICO, valuta, grandezze, costo_ricostruito).

const TP     = "/Users/kairos/Documents/lavoro/train-powertrain"
const TRATTE = ["Calabria", "Canavese", "Firenze"]
const OB = TrainPowertrain.Objective
const SZ = TrainPowertrain.Sizing

"Tratte reali (cp e precalcolo per andata e ritorno), per nome."
function tratte_reali()
    T = TrainPowertrain.Campagna.leggi_tratte_reali(; cartella = joinpath(TP, "tratte_reali"))
    return Dict(t.id => (cp = t.cp, pre = PrecalcoloTratta(t.cp, DIREZIONE)) for t in T if t.id in TRATTE)
end

"""
    taglie(cp, pre, m, n) -> (P_nom_FC_kW, C_batt_kWh)

Potenza nominale della FC e capacità della batteria del progetto (m, n) con le formule di dimensionamento del
simulatore (Objective._valuta, fase di pre-dimensionamento), SENZA valutare il progetto:
- ibrido (m ≥ m_min): P_nom = m · P_max / r (taglia_FC_2, D4); C_batt = n · E_tot_batteria / (0,8 − 0,3)
  (taglia_solo_batteria), con E_tot_batteria = energia che la batteria fornisce sul profilo di potenza della
  dinamica a massa di propulsione nulla (la stessa delle caratteristiche din_), ripartito con i limiti della FC;
- sola batteria (m < m_min): il simulatore itera la taglia sulla massa della batteria (dinamica del treno con
  quella massa, fino a 10 kg di tolleranza): la stessa iterazione qui.
"""
function taglie(cp, pre, m, n)
    m = m < CONFIG.m_min_fc ? 0.0 : Float64(m)
    if m == 0.0
        w = 0.1 * PESO_A_CARICO; sb = nothing
        for _ in 1:OB.BATTERY_ITER_MAX
            dyn = train_dynamics(structure_caratteristiche_treno(0.0, w, 0.0, PESO_A_CARICO), cp, DIREZIONE; pre, d6 = CONFIG.D6)
            P = dyn.P_tot
            E = (sum(p -> max(p, 0.0), P) - (max(P[1], 0.0) + max(P[end], 0.0)) * 0.5) / 3600.0
            sb = SZ.taglia_solo_batteria(E / OB.ETA + OB.P_AUSILIARI_DEF * ceil(length(dyn.t) / 3600.0), OB.V_NOMINALE, n)
            abs(sb.peso_totale_batteria - w) < OB.BATTERY_TOL && break
            w = sb.peso_totale_batteria
        end
        return (P_nom_FC_kW = 0.0, C_batt_kWh = sb.E_batteria)
    end
    dyn0 = train_dynamics(structure_caratteristiche_treno(0.0, 0.0, 0.0, PESO_A_CARICO), cp, DIREZIONE; pre, d6 = CONFIG.D6)
    Pd = OB._compute_P_demand(dyn0.P_tot, OB.ETA, OB.P_AUSILIARI_DEF)
    P_max_FC = OB.P_MAX_DEF * m
    sz = SZ.taglia_FC_2(P_max_FC, OB.V_NOMINALE; r = CONFIG.D4 === :pnom_dal_picco ? SZ.rapporto_picco_fc() : 1.2)
    aux = CONFIG.ausiliari_fc === :sempre_5pc ? sz.P_idling_FC : 0.0
    PL = sz.P_Lower_FC - aux; PM = P_max_FC - aux
    pb(pd) = (p = max(pd, 0.0); p < PL ? p : p > PM ? p - PM : 0.0)
    E = (sum(pb, Pd) - (pb(Pd[1]) + pb(Pd[end])) * 0.5) / 3600.0
    return (P_nom_FC_kW = sz.P_nom_FC, C_batt_kWh = SZ.taglia_solo_batteria(E, OB.V_NOMINALE, n).E_batteria)
end
