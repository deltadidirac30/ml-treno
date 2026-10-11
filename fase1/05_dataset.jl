# Fase 1 e: dataset (una riga per tratta: id, input, output) e scheda delle colonne.
#
# Uso, da ml_treno/fase1 (dopo 01, 02, 03):   julia --project=. 05_dataset.jl
# Scrive in dati/:
#   dataset_doe.csv, dataset_reali.csv                     dataset DI LAVORO: 66 input approvati + 3 din_ (variante),
#                                                          senza i 4 duplicati esatti
#   dataset_doe_completo.csv, dataset_reali_completo.csv   tutte le 73 caratteristiche (con i duplicati)
# e SCHEDA_DATASET.md.
# Colonne: id (tratta, provenienza, semplificata), input con prefisso x_, uscite con prefisso y_, controlli con prefisso c_.
# `semplificata`: true per Calabria (profilo dei tesisti con quota tutta a zero e limite unico a 130 km/h; risultati
# sempre separati), false per le altre e per tutte le DoE.

using CSV, DataFrames, Printf, Statistics
include(joinpath(@__DIR__, "caratteristiche.jl"))
const DATI = joinpath(@__DIR__, "dati")

const DUPLICATI = ["stops_sum_v2_segweighted", "slope_int_abs", "stops_spacing_mean", "cross_int_p_v"]

# descrizione, unità, gruppo di ogni input (p = pendenza in ‰ metro per metro in andata, v = limite di velocità)
const DESCR_X = Dict(
    "L_km" => ("lunghezza della tratta (andata)", "km"),
    "slope_int_pos" => ("salita totale in andata, ∫max(p,0)dx", "m"),
    "slope_int_neg" => ("discesa totale in andata, ∫max(-p,0)dx", "m"),
    "slope_int_abs" => ("salita + discesa, ∫|p|dx", "m"),
    "slope_rms" => ("radice della media di p²", "‰"),
    "slope_mean_pos" => ("media di p sui metri in salita", "‰"),
    "slope_std_pos" => ("deviazione standard di p sui metri in salita", "‰"),
    "slope_mean_neg" => ("media di p sui metri in discesa (negativa)", "‰"),
    "slope_std_neg" => ("deviazione standard di p sui metri in discesa", "‰"),
    "slope_max" => ("pendenza massima", "‰"),
    "slope_min" => ("pendenza minima", "‰"),
    "slope_std_all" => ("deviazione standard di p", "‰"),
    "slope_std_sq_pos" => ("deviazione standard di p² sui metri in salita", "‰²"),
    "slope_L_up_frac" => ("frazione della lunghezza in salita", "-"),
    "slope_sign_changes_per_km" => ("cambi di segno di p per km (zeri ignorati)", "1/km"),
    "slope_max_run_up_km" => ("salita continua più lunga", "km"),
    "vlim_mean" => ("limite medio pesato sulla lunghezza", "km/h"),
    "vlim_std" => ("deviazione standard del limite, pesata", "km/h"),
    "vlim_max" => ("limite massimo", "km/h"),
    "vlim_min" => ("limite minimo", "km/h"),
    "vlim_sum_abs_dv2" => ("Σ|Δ(v²)| tra tratti di limite consecutivi", "(km/h)²"),
    "vlim_changes_per_km" => ("(numero di tratti di limite − 1)/L", "1/km"),
    "vlim_sum_dv_pos_sq" => ("Σ(Δv)² sugli aumenti di limite", "(km/h)²"),
    "vlim_sum_dv_neg_sq" => ("Σ(Δv)² sulle diminuzioni di limite", "(km/h)²"),
    "vlim_frac_low" => ("frazione della lunghezza con limite < 80 km/h", "-"),
    "vlim_frac_mid" => ("frazione con 80 ≤ limite < 100 km/h", "-"),
    "vlim_frac_high" => ("frazione con limite ≥ 100 km/h", "-"),
    "stops_density" => ("fermate intermedie per km", "1/km"),
    "stops_spacing_mean" => ("distanza media tra stazioni consecutive (capolinea compresi) = L/(n_fermate+1)", "km"),
    "stops_spacing_std" => ("deviazione standard della distanza tra stazioni", "km"),
    "stops_sum_v2" => ("Σ v² del limite nelle fermate intermedie", "(km/h)²"),
    "stops_mean_v" => ("limite medio nelle fermate", "km/h"),
    "stops_std_v" => ("deviazione standard del limite nelle fermate", "km/h"),
    "stops_sum_v2_segweighted" => ("Σ v_i² × fermate nel tratto i: identica a stops_sum_v2", "(km/h)²"),
    "stops_mean_p" => ("pendenza media nelle fermate", "‰"),
    "stops_sum_abs_p" => ("Σ|p| nelle fermate", "‰"),
    "stops_frac_on_slope" => ("frazione di fermate con |p| > 5‰", "-"),
    "cross_Lup_v" => ("Σ sui tratti di limite di L_i × (p media positiva) × v_i", "km·‰·km/h"),
    "cross_Ldn_v" => ("Σ sui tratti di limite di L_i × (p media negativa) × v_i", "km·‰·km/h"),
    "cross_brake_energy_signed" => ("Σ nelle fermate di v² × segno(p)", "(km/h)²"),
    "cross_thermal_fatigue" => ("Σ sui tratti di limite di L_i × var(p nel tratto) × v_i", "km·‰²·km/h"),
    "cross_stops_v_seg" => ("Σ sui tratti di limite di L_i × v_i × fermate nel tratto", "km·km/h"),
    "cross_abs_p_highv" => ("Σ sui tratti con limite > 100 km/h di L_i × media|p|", "km·‰"),
    "cross_up_lowv" => ("Σ sui tratti con limite < 80 km/h di L_i × (p media positiva)", "km·‰"),
    "cross_mean_p_v" => ("media lungo la tratta di p × v(x)", "‰·km/h"),
    "cross_int_p_v" => ("∫ p × v(x) dx = cross_mean_p_v × L", "km·‰·km/h"),
    "cross_var_p_v" => ("varianza lungo la tratta di p × v(x)", "(‰·km/h)²"),
    "n_fermate" => ("NUOVA: numero di fermate intermedie", "-"),
    "dislivello_m" => ("NUOVA: quota massima − quota minima lungo la tratta", "m"),
    "tempo_limiti_ar_s" => ("NUOVA: limite inferiore della durata A/R: ogni tratto al suo limite + soste (120 s per fermata intermedia nei due versi, 300 s al capolinea)", "s"),
    "din_durata_ar_s" => ("DINAMICA: durata della missione A/R del treno di riferimento con massa del sistema di propulsione nulla (prima dinamica del valutatore)", "s"),
    "din_E_trazione_ar_kWh" => ("DINAMICA: ∫ P_tot⁺ dt alle ruote, stessa dinamica", "kWh"),
    "din_E_frenatura_ar_kWh" => ("DINAMICA: ∫ P_tot⁻ dt alle ruote (frenatura), stessa dinamica", "kWh"),
)
for k in 1:10
    DESCR_X["bin_p_$k"] = ("pendenza media nel $(k)° decimo della tratta (andata)", "‰")
    DESCR_X["bin_v_$k"] = ("limite medio nel $(k)° decimo della tratta (andata)", "km/h")
end

const DESCR_Y = Dict(
    "regime" => ("ibrido (m* > 0) o sola_batteria (m* = 0)", "-"),
    "ibrido" => ("1 se ibrido, 0 se sola batteria", "-"),
    "m_star" => ("quota della fuel cell nell'ottimo (m effettiva: 0 se sotto m_min_fc = 0,03)", "-"),
    "n_star" => ("quota della batteria nell'ottimo", "-"),
    "P_nom_FC_kW" => ("potenza nominale della fuel cell (0 a sola batteria)", "kW"),
    "C_batt_kWh" => ("capacità della batteria (E_batteria)", "kWh"),
    "serbatoio_H2_kg" => ("H2 stoccabile nel serbatoio = massa serbatoio × 0,055 (quello del CAPEX)", "kg"),
    "serbatoio_massa_kg" => ("massa del serbatoio (con il margine del 25%)", "kg"),
    "serbatoio_volume_m3" => ("volume del serbatoio", "m³"),
    "massa_FC_kg" => ("massa della fuel cell", "kg"),
    "massa_batt_kg" => ("massa della batteria", "kg"),
    "massa_propulsione_kg" => ("massa del sistema di propulsione (FC + batteria + serbatoio); vincolo ≤ 0,15 × 195 t", "kg"),
    "H2_viaggio_kg" => ("idrogeno consumato in un viaggio A/R", "kg"),
    "E_ricarica_viaggio_kWh" => ("energia di ricarica della batteria per viaggio = (SOC iniziale − finale) × capacità × 1500 V (quella dell'OPEX elettrico)", "kWh"),
    "SOC_fine" => ("SOC a fine viaggio; vincolo ≥ 0,2", "-"),
    "durata_viaggio_s" => ("durata del viaggio A/R usata nel costo (length(SOC_batt) = passi + 1)", "s"),
    "viaggi_giorno" => ("round(36000 / durata): 10 h di servizio al giorno", "-"),
    "km_viaggio" => ("2 L", "km"),
    "km_anno" => ("viaggi_giorno × 365 × km_viaggio", "km"),
    "vita_FC_viaggi" => ("vita della fuel cell in viaggi (continua, con il tetto di 25 000 h); Inf a sola batteria", "viaggi"),
    "vita_FC_ore" => ("vita della fuel cell in ore di funzionamento; Inf a sola batteria", "h"),
    "vita_FC_anni" => ("vita_FC_viaggi / (viaggi_giorno × 365), quella del costo", "anni"),
    "vita_FC_tetto" => ("1 se la vita è limitata dal tetto di 25 000 h", "-"),
    "dV_FC_viaggio_uV" => ("perdita di tensione di cella per viaggio (somma dei 4 termini, prima di K e f)", "µV"),
    "tasso_degrado_FC_uV_h" => ("perdita di tensione di cella per ora di funzionamento, con K = 1,72 e f: dV_fine_vita / vita_FC_ore; 0 a sola batteria", "µV/h"),
    "n_sost_FC" => ("sostituzioni della fuel cell in 20 anni (dopo D15)", "-"),
    "vita_batt_viaggi" => ("vita della batteria in viaggi, continua (prima dell'arrotondamento)", "viaggi"),
    "vita_batt_anni" => ("vita_batt_viaggi / (viaggi_giorno × 365)", "anni"),
    "n_sost_batt" => ("sostituzioni della batteria in 20 anni", "-"),
    "D15_tau_anni" => ("D15: anni tra l'ultima sostituzione FC prevista e i 20 anni (NaN senza sostituzioni)", "anni"),
    "D15_coda_simulata" => ("D15: 1 se la regola si applica (tau < 1 anno) e la coda con la FC degradata è stata simulata", "-"),
    "D15_coda_fattibile" => ("D15: 1 se la coda è fattibile, 0 se no, NaN se non simulata", "-"),
    "D15_sost_saltata" => ("D15: 1 se l'ultima sostituzione FC è saltata", "-"),
    "D15_H2_coda_kg" => ("D15: H2 per viaggio con la FC degradata nella coda (NaN se non simulata)", "kg"),
    "costo_EUR_km" => ("costo livellato totale (obiettivo dell'ottimizzazione; penalità nulla)", "€/km"),
)
for v in ["CAPEX_FC_EUR_km", "CAPEX_batt_EUR_km", "CAPEX_tank_EUR_km", "OPEX_batt_rech_EUR_km_att", "OPEX_H2_rech_EUR_km_att",
          "OPEX_mant_FC_EUR_km_att", "OPEX_mant_batt_EUR_km_att", "OPEX_mant_tank_EUR_km_att", "cost_repl_FC_EUR_km_att",
          "cost_repl_batt_EUR_km_att"]
    DESCR_Y[v] = ("voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km", "€/km")
end
const DESCR_C = Dict(
    "stato" => "esito della valutazione nell'ottimo (sempre completed)",
    "penalita" => "penalità nell'ottimo (sempre 0)",
    "costo_totale_EUR_km" => "total_cost_EUR_km del simulatore (= costo_EUR_km senza penalità)",
    "somma_voci_EUR_km" => "somma delle 10 voci (controllo)")

function assembla(fx, fy)
    x = CSV.read(fx, DataFrame); y = CSV.read(fy, DataFrame)
    x.tratta == y.tratta || error("ordine delle tratte diverso")
    d = DataFrame(tratta = y.tratta, provenienza = y.provenienza,
                  semplificata = hasproperty(y, :semplificata) ? y.semplificata : falses(nrow(y)))
    for n in NOMI_CARATTERISTICHE; d[!, "x_" * n] = x[!, n]; end
    d[!, "y_regime"] = y.regime
    d[!, "y_ibrido"] = Int.(y.regime .== "ibrido")
    for n in names(y)
        n in ("tratta", "provenienza", "semplificata", "regime") && continue
        haskey(DESCR_C, n) ? (d[!, "c_" * n] = y[!, n]) : (d[!, "y_" * n] = y[!, n])
    end
    return d
end
doe   = assembla(joinpath(DATI, "caratteristiche_doe.csv"), joinpath(DATI, "uscite_doe.csv"))
reali = assembla(joinpath(DATI, "caratteristiche_reali.csv"), joinpath(DATI, "uscite_reali.csv"))
names(doe) == names(reali) || error("colonne diverse")
CSV.write(joinpath(DATI, "dataset_doe_completo.csv"), doe)
CSV.write(joinpath(DATI, "dataset_reali_completo.csv"), reali)
lavoro(d) = select(d, Not(["x_" * n for n in DUPLICATI]))
CSV.write(joinpath(DATI, "dataset_doe.csv"), lavoro(doe))
CSV.write(joinpath(DATI, "dataset_reali.csv"), lavoro(reali))

# ── scheda ───────────────────────────────────────────────────────────────────
fmt(x) = x isa AbstractString ? x : isnan(x) ? "NaN" : isinf(x) ? string(x) : @sprintf("%.4g", x)
function stat(v, maschera)
    w = [x for (x, k) in zip(v, maschera) if k && x isa Real && isfinite(x)]
    isempty(w) && return ("—", "—", "—")
    return (fmt(minimum(w)), fmt(median(w)), fmt(maximum(w)))
end
ibr = doe.y_ibrido .== 1
io = IOBuffer()
println(io, "# Scheda del dataset (fase 1)\n")
println(io, "Generata da `fase1/05_dataset.jl`. File di lavoro: `fase1/dati/dataset_doe.csv` (1024 tratte DoE) e `fase1/dati/dataset_reali.csv` (5 tratte reali), stesse colonne, **senza i 4 duplicati** (66 input approvati + 3 `din_`). Le versioni `_completo.csv` hanno anche i 4 duplicati. Una riga per tratta, missione in **andata e ritorno**, modello `corretta` con f = 0,51692531382982454 (configurazione di `config.txt` delle campagne).\n")
println(io, "- **id:** `tratta`; `provenienza` (DoE: `nomad_pb`, `vecchio` o `pari` = stesso costo al bit; reali anche `forza_bruta`); `semplificata` (true solo per Calabria: profilo dei tesisti con quota tutta a zero e limite unico a 130 km/h, risultati sempre separati).")
println(io, "- **input `x_`:** caratteristiche della tratta, calcolate solo dal profilo come lo legge il simulatore (`PrecalcoloTratta(cp, \"andata\")`): pendenza metro per metro p [‰], stazioni, limiti. Le `din_` vengono da una sola dinamica del treno di riferimento (non dipendono da m, n).")
println(io, "- **uscite `y_`:** dalla rivalutazione del simulatore nell'ottimo di riferimento.")
println(io, "- **controlli `c_`:** non sono né input né uscite.\n")
println(io, "Input approvati (decisione del 10/10): i 66 marcati `tenere`; le 3 `din_` sono una variante da confrontare in fase 2; i 4 `togliere: duplicato` sono solo nei file `_completo.csv`. Statistiche: min / mediana / max sulle 1024 tratte DoE (uscite FC sulle sole ibride).\n")
println(io, "## Input\n")
println(io, "| colonna | descrizione | unità | gruppo | raccomandazione | min | mediana | max |")
println(io, "|---|---|---|---|---|---:|---:|---:|")
for n in NOMI_CARATTERISTICHE
    haskey(DESCR_X, n) || error("manca la descrizione di $n")
    d, u = DESCR_X[n]; d = replace(d, "|" => "\\|")
    g = n in NOMI_DIN ? "dinamica" : n in NOMI_NUOVE ? "nuova" : "originale ml_treno"
    r = n in DUPLICATI ? "togliere: duplicato" : n in NOMI_DIN ? "facoltativa" : "tenere"
    s = stat(doe[!, "x_" * n], trues(nrow(doe)))
    println(io, "| `x_$n` | $d | $u | $g | $r | $(s[1]) | $(s[2]) | $(s[3]) |")
end
println(io, "\n## Uscite\n")
println(io, "| colonna | descrizione | unità | min | mediana | max |")
println(io, "|---|---|---|---:|---:|---:|")
const SOLO_IBRIDE = ["P_nom_FC_kW", "serbatoio_H2_kg", "serbatoio_massa_kg", "serbatoio_volume_m3", "massa_FC_kg", "H2_viaggio_kg",
                     "vita_FC_viaggi", "vita_FC_ore", "vita_FC_anni", "vita_FC_tetto", "dV_FC_viaggio_uV", "tasso_degrado_FC_uV_h",
                     "n_sost_FC", "D15_tau_anni", "m_star"]
for c in names(doe)
    startswith(c, "y_") || continue
    n = c[3:end]
    haskey(DESCR_Y, n) || error("manca la descrizione di $n")
    d, u = DESCR_Y[n]; d = replace(d, "|" => "\\|")
    s = n == "regime" ? ("—", "—", "—") : stat(doe[!, c], n in SOLO_IBRIDE ? ibr : trues(nrow(doe)))
    println(io, "| `$c` | $d$(n in SOLO_IBRIDE ? " *(statistiche sulle ibride)*" : "") | $u | $(s[1]) | $(s[2]) | $(s[3]) |")
end
println(io, "\n## Controlli\n")
println(io, "| colonna | descrizione |")
println(io, "|---|---|")
for c in names(doe)
    startswith(c, "c_") && println(io, "| `$c` | $(DESCR_C[c[3:end]]) |")
end
write(joinpath(@__DIR__, "SCHEDA_DATASET.md"), take!(io))

# numeri per il report
println("dataset_doe_completo: ", size(doe), "  dataset_doe (lavoro): ", size(lavoro(doe)), "  dataset_reali: ", size(lavoro(reali)))
println("x_ (lavoro): ", count(startswith("x_"), names(lavoro(doe))), "  y_: ", count(startswith("y_"), names(doe)), "  c_: ", count(startswith("c_"), names(doe)))
s = doe.y_SOC_fine
println(@sprintf("SOC finale nell'ottimo: < 0,2005 in %d/1024 (ibride %d/630, batteria %d/394); < 0,201 in %d",
                 count(<(0.2005), s), count(<(0.2005), s[ibr]), count(<(0.2005), s[.!ibr]), count(<(0.201), s)))
mp = doe.y_massa_propulsione_kg
println(@sprintf("massa propulsione oltre il 99,9%% del limite (29 250 kg): %d", count(>(0.999 * 29250), mp)))
println("viaggi al giorno: ", sort(collect(Dict(v => count(==(v), doe.y_viaggi_giorno) for v in unique(doe.y_viaggi_giorno)))))
println("n_sost_FC (ibride): ", sort(collect(Dict(v => count(==(v), doe.y_n_sost_FC[ibr]) for v in unique(doe.y_n_sost_FC[ibr])))))
println("n_sost_batt: ", sort(collect(Dict(v => count(==(v), doe.y_n_sost_batt) for v in unique(doe.y_n_sost_batt)))))
println("m* ibride: ", extrema(doe.y_m_star[ibr]), "  m* = 0,03 esatto: ", count(==(0.03), doe.y_m_star))
println("n* : ", extrema(doe.y_n_star), "  costo: ", extrema(doe.y_costo_EUR_km))
