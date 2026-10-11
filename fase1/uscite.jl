# Grandezze di uscita di un progetto (m, n) su una tratta: una valutazione del simulatore (valuta_progetto,
# modello :corretta, configurazione di default = config.txt delle campagne) con la traccia, che dà anche la
# vita della batteria prima dell'arrotondamento. Nessuna modifica al simulatore: si leggono EsitoValutazione,
# diagnostica (cost_details, degrado_fc, coda_fc) e la traccia.
#
# `costo_ricostruito` rifà il costo livellato €/km (D18, sostituzioni a fine vita D14, regola di fine
# orizzonte D15) dalle sole grandezze estratte: serve a controllare che le uscite bastino a ricostruire il
# costo, e in fase 2 a ricostruirlo dalle grandezze previste.

using TrainPowertrain

const PESO_A_CARICO = 195_000.0
const DIREZIONE     = "andata&ritorno"
const CONFIG        = ConfigModello(modello = :corretta)
const DENSITA_GRAV  = 0.055          # kgH2/kg di serbatoio, costante in Sizing.taglia_storage
const VOCI = ["CAPEX_FC_EUR_km", "CAPEX_batt_EUR_km", "CAPEX_tank_EUR_km", "OPEX_batt_rech_EUR_km_att",
              "OPEX_H2_rech_EUR_km_att", "OPEX_mant_FC_EUR_km_att", "OPEX_mant_batt_EUR_km_att",
              "OPEX_mant_tank_EUR_km_att", "cost_repl_FC_EUR_km_att", "cost_repl_batt_EUR_km_att"]

"""
    valuta(cp, m, n; pre) -> (esito, traccia)
"""
function valuta(cp, m, n; pre = PrecalcoloTratta(cp, DIREZIONE))
    tr = Dict{String,Any}()
    e = valuta_progetto(Float64(m), Float64(n), PESO_A_CARICO, cp, DIREZIONE; config = CONFIG, trace = tr, precalcolo = pre)
    return e, tr
end

"""
    grandezze(e, tr, cp) -> Vector{Pair{String,Any}}

Le uscite di una valutazione completata, nell'ordine delle colonne del dataset.
"""
function grandezze(e, tr, cp)
    e.stato === :completed || error("valutazione non completata: $(e.stato) $(e.motivo)")
    cd  = e.diagnostica.cost_details
    dfc = e.diagnostica.degrado_fc
    coda = e.diagnostica.coda_fc
    ps  = e.risultato.propulsion_system
    m   = cd["m"]
    senza_fc = m == 0.0
    durata  = length(e.risultato.SOC_batt)                    # s, come funzione_costo_ga (tempo_tratta)
    v_g     = Int(matlab_round(10 * 3600 / durata))           # viaggi al giorno (10 h di servizio)
    v_a     = v_g * 365
    km_v    = 2 * cp.lunghezza_binario_andata / 1000          # km a viaggio (andata e ritorno)
    km_a    = v_a * km_v
    life_fc = tr["life_FC"];  life_b = tr["life_batt"]
    # degrado FC: perdita di tensione di cella per ora di funzionamento, con f e K (µV/h); Inf/NaN senza FC
    tasso   = senza_fc ? 0.0 : dfc.dV_fine_vita * 1e6 / dfc.vita_FC_ore
    somma_voci = sum(cd[k] for k in VOCI)
    return [
        "regime"                    => senza_fc ? "sola_batteria" : "ibrido",
        "m_star"                    => m,
        "n_star"                    => cd["n"],
        "stato"                     => String(e.stato),
        "penalita"                  => e.penalita,
        # taglie
        "P_nom_FC_kW"               => cd["P_nom_fc_kW"],
        "C_batt_kWh"                => cd["C_batt_kWh"],
        "serbatoio_H2_kg"           => ps.peso_storage_idrogeno * DENSITA_GRAV,
        "serbatoio_massa_kg"        => ps.peso_storage_idrogeno,
        "serbatoio_volume_m3"       => ps.volume_storage_idrogeno,
        "massa_FC_kg"               => ps.peso_totale_FC,
        "massa_batt_kg"             => ps.peso_pacco_batterie,
        "massa_propulsione_kg"      => e.risultato.peso_sistema_propulsione,
        # consumi per viaggio (andata e ritorno)
        "H2_viaggio_kg"             => cd["H2_cons_kg"],
        "E_ricarica_viaggio_kWh"    => tr["Energia_consumata_batteria"],
        "SOC_fine"                  => cd["SOC_end"],
        # servizio
        "durata_viaggio_s"          => Float64(durata),
        "viaggi_giorno"             => Float64(v_g),
        "km_viaggio"                => km_v,
        "km_anno"                   => km_a,
        # fuel cell
        "vita_FC_viaggi"            => life_fc,
        "vita_FC_ore"               => cd["vita_FC_ore"],
        "vita_FC_anni"              => life_fc / v_a,
        "vita_FC_tetto"             => cd["vita_FC_tetto"],
        "dV_FC_viaggio_uV"          => dfc.delta_V,
        "tasso_degrado_FC_uV_h"     => tasso,
        "n_sost_FC"                 => cd["num_repl_FC"],
        # batteria
        "vita_batt_viaggi"          => life_b,
        "vita_batt_anni"            => life_b / v_a,
        "n_sost_batt"               => cd["num_repl_batt"],
        # D15
        "D15_tau_anni"              => cd["tau_FC_anni"],
        "D15_coda_simulata"         => coda === nothing ? 0.0 : 1.0,
        "D15_coda_fattibile"        => coda === nothing ? NaN : (coda.fattibile ? 1.0 : 0.0),
        "D15_sost_saltata"          => cd["sostituzione_FC_saltata"],
        "D15_H2_coda_kg"            => cd["H2_coda_kg"],
        # costi €/km (D18)
        "costo_EUR_km"              => e.costo,
        "costo_totale_EUR_km"       => cd["total_cost_EUR_km"],
        [k => cd[k] for k in VOCI]...,
        "somma_voci_EUR_km"         => somma_voci,
    ]
end

"""
    costo_ricostruito(g) -> (costo, voci::Dict)

Costo livellato €/km dalle grandezze `g` (Dict colonna => valore): taglie, consumi per viaggio, viaggi
all'anno, km all'anno, vite (in anni) di FC e batteria, D15 (sostituzione saltata e H2 della coda).
Stesse formule e stesso ordine delle operazioni di `funzione_costo_ga` (livellato, a fine vita).
"""
function costo_ricostruito(g)
    i, n_anni = 0.04, 20
    P, E, H2s = g["P_nom_FC_kW"], g["C_batt_kWh"], g["serbatoio_H2_kg"]
    v_a  = g["viaggi_giorno"] * 365
    km_a = g["km_anno"]
    senza_fc = g["m_star"] == 0.0
    vfa, vba = g["vita_FC_anni"], g["vita_batt_anni"]
    N_fc = senza_fc ? 0.0 : ceil(n_anni / vfa - 1.0)
    N_b  = ceil(n_anni / vba - 1.0)
    while N_fc >= 1 && N_fc * vfa >= n_anni - 1e-9; N_fc -= 1.0; end
    while N_b  >= 1 && N_b  * vba >= n_anni - 1e-9; N_b  -= 1.0; end
    CAPEX_FC, CAPEX_b, CAPEX_s = 300.0 * P, 100.0 * E, 535.0 * H2s
    OPEX_mFC, OPEX_mb, OPEX_ms = 0.02 * 300.0 * P, 0.02 * 100.0 * E, 0.02 * 535.0 * H2s
    OPEX_el = 0.19 * g["E_ricarica_viaggio_kWh"] * v_a
    OPEX_H2 = 6.6 * g["H2_viaggio_kg"] * v_a
    costo_coda = 0.0
    saltata = g["D15_sost_saltata"]
    if saltata == 1.0
        t_N = N_fc * vfa
        for y in ceil(t_N):Float64(n_anni)
            fr = min(y, Float64(n_anni)) - max(y - 1.0, t_N)
            fr > 0.0 && (costo_coda += (g["D15_H2_coda_kg"] - g["H2_viaggio_kg"]) * 6.6 * v_a * fr / (1.0 + i)^y)
        end
    end
    N_fc -= saltata
    REPEX_FC = 0.0; REPEX_b = 0.0
    if !senza_fc
        for j in 1.0:N_fc; REPEX_FC += 300.0 * P / (1.0 + i)^(j * vfa); end
    end
    for j in 1.0:N_b; REPEX_b += 100.0 * E / (1.0 + i)^(j * vba); end
    A = (1.0 - (1.0 + i)^(-n_anni)) / i
    CRF = 1.0 / A
    OPEX_annuo = OPEX_mFC + OPEX_mb + OPEX_ms + OPEX_el + OPEX_H2
    EAC = (CAPEX_FC + CAPEX_b + CAPEX_s + REPEX_FC + REPEX_b + costo_coda) * CRF + OPEX_annuo
    voci = Dict("CAPEX_FC_EUR_km" => CAPEX_FC * CRF / km_a, "CAPEX_batt_EUR_km" => CAPEX_b * CRF / km_a,
                "CAPEX_tank_EUR_km" => CAPEX_s * CRF / km_a, "OPEX_batt_rech_EUR_km_att" => OPEX_el / km_a,
                "OPEX_H2_rech_EUR_km_att" => (OPEX_H2 + costo_coda * CRF) / km_a,
                "OPEX_mant_FC_EUR_km_att" => OPEX_mFC / km_a, "OPEX_mant_batt_EUR_km_att" => OPEX_mb / km_a,
                "OPEX_mant_tank_EUR_km_att" => OPEX_ms / km_a, "cost_repl_FC_EUR_km_att" => REPEX_FC * CRF / km_a,
                "cost_repl_batt_EUR_km_att" => REPEX_b * CRF / km_a,
                "n_sost_FC" => N_fc, "n_sost_batt" => N_b)
    return EAC / km_a, voci
end
