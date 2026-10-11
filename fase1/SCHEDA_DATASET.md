# Scheda del dataset (fase 1)

Generata da `fase1/05_dataset.jl`. File di lavoro: `fase1/dati/dataset_doe.csv` (1024 tratte DoE) e `fase1/dati/dataset_reali.csv` (5 tratte reali), stesse colonne, **senza i 4 duplicati** (66 input approvati + 3 `din_`). Le versioni `_completo.csv` hanno anche i 4 duplicati. Una riga per tratta, missione in **andata e ritorno**, modello `corretta` con f = 0,51692531382982454 (configurazione di `config.txt` delle campagne).

- **id:** `tratta`; `provenienza` (DoE: `nomad_pb`, `vecchio` o `pari` = stesso costo al bit; reali anche `forza_bruta`); `semplificata` (true solo per Calabria: profilo dei tesisti con quota tutta a zero e limite unico a 130 km/h, risultati sempre separati).
- **input `x_`:** caratteristiche della tratta, calcolate solo dal profilo come lo legge il simulatore (`PrecalcoloTratta(cp, "andata")`): pendenza metro per metro p [‰], stazioni, limiti. Le `din_` vengono da una sola dinamica del treno di riferimento (non dipendono da m, n).
- **uscite `y_`:** dalla rivalutazione del simulatore nell'ottimo di riferimento.
- **controlli `c_`:** non sono né input né uscite.

Input approvati (decisione del 10/10): i 66 marcati `tenere`; le 3 `din_` sono una variante da confrontare in fase 2; i 4 `togliere: duplicato` sono solo nei file `_completo.csv`. Statistiche: min / mediana / max sulle 1024 tratte DoE (uscite FC sulle sole ibride).

## Input

| colonna | descrizione | unità | gruppo | raccomandazione | min | mediana | max |
|---|---|---|---|---|---:|---:|---:|
| `x_L_km` | lunghezza della tratta (andata) | km | originale ml_treno | tenere | 15.02 | 107.5 | 199.9 |
| `x_slope_int_pos` | salita totale in andata, ∫max(p,0)dx | m | originale ml_treno | tenere | 0 | 99.99 | 1922 |
| `x_slope_int_neg` | discesa totale in andata, ∫max(-p,0)dx | m | originale ml_treno | tenere | 0 | 98.26 | 1951 |
| `x_slope_int_abs` | salita + discesa, ∫\|p\|dx | m | originale ml_treno | togliere: duplicato | 0 | 495.9 | 2066 |
| `x_slope_rms` | radice della media di p² | ‰ | originale ml_treno | tenere | 0 | 6.629 | 12.55 |
| `x_slope_mean_pos` | media di p sui metri in salita | ‰ | originale ml_treno | tenere | 0 | 3.252 | 12.09 |
| `x_slope_std_pos` | deviazione standard di p sui metri in salita | ‰ | originale ml_treno | tenere | 0 | 1.546 | 6.844 |
| `x_slope_mean_neg` | media di p sui metri in discesa (negativa) | ‰ | originale ml_treno | tenere | -11.44 | -3.133 | 0 |
| `x_slope_std_neg` | deviazione standard di p sui metri in discesa | ‰ | originale ml_treno | tenere | 0 | 1.559 | 7.419 |
| `x_slope_max` | pendenza massima | ‰ | originale ml_treno | tenere | -9.531 | 6.9 | 28.4 |
| `x_slope_min` | pendenza minima | ‰ | originale ml_treno | tenere | -27.98 | -6.812 | 9.242 |
| `x_slope_std_all` | deviazione standard di p | ‰ | originale ml_treno | tenere | 0 | 3.428 | 7.997 |
| `x_slope_std_sq_pos` | deviazione standard di p² sui metri in salita | ‰² | originale ml_treno | tenere | 0 | 11.29 | 186.7 |
| `x_slope_L_up_frac` | frazione della lunghezza in salita | - | originale ml_treno | tenere | 0 | 0.3853 | 1 |
| `x_slope_sign_changes_per_km` | cambi di segno di p per km (zeri ignorati) | 1/km | originale ml_treno | tenere | 0 | 0.07624 | 0.8031 |
| `x_slope_max_run_up_km` | salita continua più lunga | km | originale ml_treno | tenere | 0 | 6.931 | 199.9 |
| `x_vlim_mean` | limite medio pesato sulla lunghezza | km/h | originale ml_treno | tenere | 67.17 | 100 | 160 |
| `x_vlim_std` | deviazione standard del limite, pesata | km/h | originale ml_treno | tenere | 0 | 9.58 | 43.16 |
| `x_vlim_max` | limite massimo | km/h | originale ml_treno | tenere | 80 | 120 | 160 |
| `x_vlim_min` | limite minimo | km/h | originale ml_treno | tenere | 60 | 80 | 160 |
| `x_vlim_sum_abs_dv2` | Σ\|Δ(v²)\| tra tratti di limite consecutivi | (km/h)² | originale ml_treno | tenere | 0 | 1.965e+04 | 2.207e+05 |
| `x_vlim_changes_per_km` | (numero di tratti di limite − 1)/L | 1/km | originale ml_treno | tenere | 0 | 0.06974 | 0.1616 |
| `x_vlim_sum_dv_pos_sq` | Σ(Δv)² sugli aumenti di limite | (km/h)² | originale ml_treno | tenere | 0 | 900 | 2.25e+04 |
| `x_vlim_sum_dv_neg_sq` | Σ(Δv)² sulle diminuzioni di limite | (km/h)² | originale ml_treno | tenere | 0 | 900 | 2.2e+04 |
| `x_vlim_frac_low` | frazione della lunghezza con limite < 80 km/h | - | originale ml_treno | tenere | 0 | 0 | 0.8718 |
| `x_vlim_frac_mid` | frazione con 80 ≤ limite < 100 km/h | - | originale ml_treno | tenere | 0 | 0.2262 | 1 |
| `x_vlim_frac_high` | frazione con limite ≥ 100 km/h | - | originale ml_treno | tenere | 0 | 0.6414 | 1 |
| `x_stops_density` | fermate intermedie per km | 1/km | originale ml_treno | tenere | 0 | 0.1425 | 0.3262 |
| `x_stops_spacing_mean` | distanza media tra stazioni consecutive (capolinea compresi) = L/(n_fermate+1) | km | originale ml_treno | togliere: duplicato | 2.633 | 6.375 | 198.8 |
| `x_stops_spacing_std` | deviazione standard della distanza tra stazioni | km | originale ml_treno | tenere | 0 | 0.9363 | 31.46 |
| `x_stops_sum_v2` | Σ v² del limite nelle fermate intermedie | (km/h)² | originale ml_treno | tenere | 0 | 1.17e+05 | 1.176e+06 |
| `x_stops_mean_v` | limite medio nelle fermate | km/h | originale ml_treno | tenere | 0 | 96.06 | 160 |
| `x_stops_std_v` | deviazione standard del limite nelle fermate | km/h | originale ml_treno | tenere | 0 | 8.165 | 49.3 |
| `x_stops_sum_v2_segweighted` | Σ v_i² × fermate nel tratto i: identica a stops_sum_v2 | (km/h)² | originale ml_treno | togliere: duplicato | 0 | 1.17e+05 | 1.176e+06 |
| `x_stops_mean_p` | pendenza media nelle fermate | ‰ | originale ml_treno | tenere | -16 | 0 | 18.66 |
| `x_stops_sum_abs_p` | Σ\|p\| nelle fermate | ‰ | originale ml_treno | tenere | 0 | 45.46 | 525.8 |
| `x_stops_frac_on_slope` | frazione di fermate con \|p\| > 5‰ | - | originale ml_treno | tenere | 0 | 0.4286 | 1 |
| `x_cross_Lup_v` | Σ sui tratti di limite di L_i × (p media positiva) × v_i | km·‰·km/h | originale ml_treno | tenere | 0 | 2.247e+04 | 2.974e+05 |
| `x_cross_Ldn_v` | Σ sui tratti di limite di L_i × (p media negativa) × v_i | km·‰·km/h | originale ml_treno | tenere | -2.786e+05 | -2.197e+04 | 0 |
| `x_cross_brake_energy_signed` | Σ nelle fermate di v² × segno(p) | (km/h)² | originale ml_treno | tenere | -8.063e+05 | 0 | 1.008e+06 |
| `x_cross_thermal_fatigue` | Σ sui tratti di limite di L_i × var(p nel tratto) × v_i | km·‰²·km/h | originale ml_treno | tenere | 0 | 7.856e+04 | 1.768e+06 |
| `x_cross_stops_v_seg` | Σ sui tratti di limite di L_i × v_i × fermate nel tratto | km·km/h | originale ml_treno | tenere | 0 | 1.688e+04 | 1.171e+06 |
| `x_cross_abs_p_highv` | Σ sui tratti con limite > 100 km/h di L_i × media\|p\| | km·‰ | originale ml_treno | tenere | 0 | 77.99 | 2066 |
| `x_cross_up_lowv` | Σ sui tratti con limite < 80 km/h di L_i × (p media positiva) | km·‰ | originale ml_treno | tenere | 0 | 0 | 975.2 |
| `x_cross_mean_p_v` | media lungo la tratta di p × v(x) | ‰·km/h | originale ml_treno | tenere | -1508 | 0 | 1503 |
| `x_cross_int_p_v` | ∫ p × v(x) dx = cross_mean_p_v × L | km·‰·km/h | originale ml_treno | togliere: duplicato | -2.445e+05 | 0 | 2.893e+05 |
| `x_cross_var_p_v` | varianza lungo la tratta di p × v(x) | (‰·km/h)² | originale ml_treno | tenere | 0 | 1.215e+05 | 1.528e+06 |
| `x_bin_p_1` | pendenza media nel 1° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -14.38 | 0 | 18.11 |
| `x_bin_p_2` | pendenza media nel 2° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -17.08 | 0 | 18.35 |
| `x_bin_p_3` | pendenza media nel 3° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -18.68 | 0 | 18.22 |
| `x_bin_p_4` | pendenza media nel 4° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -16.52 | 0 | 21.61 |
| `x_bin_p_5` | pendenza media nel 5° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -17.28 | 0 | 18.06 |
| `x_bin_p_6` | pendenza media nel 6° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -17.47 | 0 | 17.17 |
| `x_bin_p_7` | pendenza media nel 7° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -21.86 | 0 | 15.17 |
| `x_bin_p_8` | pendenza media nel 8° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -18.09 | 0 | 19.31 |
| `x_bin_p_9` | pendenza media nel 9° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -17.38 | 0 | 15.86 |
| `x_bin_p_10` | pendenza media nel 10° decimo della tratta (andata) | ‰ | originale ml_treno | tenere | -17.56 | 0 | 21 |
| `x_bin_v_1` | limite medio nel 1° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_2` | limite medio nel 2° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_3` | limite medio nel 3° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_4` | limite medio nel 4° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_5` | limite medio nel 5° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_6` | limite medio nel 6° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_7` | limite medio nel 7° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_8` | limite medio nel 8° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_9` | limite medio nel 9° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_bin_v_10` | limite medio nel 10° decimo della tratta (andata) | km/h | originale ml_treno | tenere | 60 | 100 | 160 |
| `x_n_fermate` | NUOVA: numero di fermate intermedie | - | nuova | tenere | 0 | 12 | 62 |
| `x_dislivello_m` | NUOVA: quota massima − quota minima lungo la tratta | m | nuova | tenere | 0 | 348.1 | 1919 |
| `x_tempo_limiti_ar_s` | NUOVA: limite inferiore della durata A/R: ogni tratto al suo limite + soste (120 s per fermata intermedia nei due versi, 300 s al capolinea) | s | nuova | tenere | 1091 | 1.113e+04 | 3.342e+04 |
| `x_din_durata_ar_s` | DINAMICA: durata della missione A/R del treno di riferimento con massa del sistema di propulsione nulla (prima dinamica del valutatore) | s | dinamica | facoltativa | 1246 | 1.256e+04 | 3.679e+04 |
| `x_din_E_trazione_ar_kWh` | DINAMICA: ∫ P_tot⁺ dt alle ruote, stessa dinamica | kWh | dinamica | facoltativa | 106.3 | 1202 | 4936 |
| `x_din_E_frenatura_ar_kWh` | DINAMICA: ∫ P_tot⁻ dt alle ruote (frenatura), stessa dinamica | kWh | dinamica | facoltativa | 20.38 | 470.1 | 2186 |

## Uscite

| colonna | descrizione | unità | min | mediana | max |
|---|---|---|---:|---:|---:|
| `y_regime` | ibrido (m* > 0) o sola_batteria (m* = 0) | - | — | — | — |
| `y_ibrido` | 1 se ibrido, 0 se sola batteria | - | 0 | 1 | 1 |
| `y_m_star` | quota della fuel cell nell'ottimo (m effettiva: 0 se sotto m_min_fc = 0,03) *(statistiche sulle ibride)* | - | 0.03008 | 0.2076 | 0.6953 |
| `y_n_star` | quota della batteria nell'ottimo | - | 0.008666 | 0.686 | 0.9977 |
| `y_P_nom_FC_kW` | potenza nominale della fuel cell (0 a sola batteria) *(statistiche sulle ibride)* | kW | 59.22 | 408.7 | 1369 |
| `y_C_batt_kWh` | capacità della batteria (E_batteria) | kWh | 37.5 | 2642 | 3162 |
| `y_serbatoio_H2_kg` | H2 stoccabile nel serbatoio = massa serbatoio × 0,055 (quello del CAPEX) *(statistiche sulle ibride)* | kg | 9.265 | 115.6 | 551 |
| `y_serbatoio_massa_kg` | massa del serbatoio (con il margine del 25%) *(statistiche sulle ibride)* | kg | 168.5 | 2101 | 1.002e+04 |
| `y_serbatoio_volume_m3` | volume del serbatoio *(statistiche sulle ibride)* | m³ | 0.2316 | 2.889 | 13.78 |
| `y_massa_FC_kg` | massa della fuel cell *(statistiche sulle ibride)* | kg | 153.8 | 1062 | 3556 |
| `y_massa_batt_kg` | massa della batteria | kg | 379.5 | 2.434e+04 | 2.912e+04 |
| `y_massa_propulsione_kg` | massa del sistema di propulsione (FC + batteria + serbatoio); vincolo ≤ 0,15 × 195 t | kg | 3450 | 2.909e+04 | 2.925e+04 |
| `y_H2_viaggio_kg` | idrogeno consumato in un viaggio A/R *(statistiche sulle ibride)* | kg | 7.411 | 92.31 | 441.8 |
| `y_E_ricarica_viaggio_kWh` | energia di ricarica della batteria per viaggio = (SOC iniziale − finale) × capacità × 1500 V (quella dell'OPEX elettrico) | kWh | 0.2085 | 1573 | 1895 |
| `y_SOC_fine` | SOC a fine viaggio; vincolo ≥ 0,2 | - | 0.2 | 0.2003 | 0.7985 |
| `y_durata_viaggio_s` | durata del viaggio A/R usata nel costo (length(SOC_batt) = passi + 1) | s | 1251 | 1.272e+04 | 3.71e+04 |
| `y_viaggi_giorno` | round(36000 / durata): 10 h di servizio al giorno | - | 1 | 3 | 29 |
| `y_km_viaggio` | 2 L | km | 30.03 | 215 | 399.7 |
| `y_km_anno` | viaggi_giorno × 365 × km_viaggio | km | 8.994e+04 | 2.061e+05 | 5.154e+05 |
| `y_vita_FC_viaggi` | vita della fuel cell in viaggi (continua, con il tetto di 25 000 h); Inf a sola batteria *(statistiche sulle ibride)* | viaggi | 744.7 | 1896 | 7888 |
| `y_vita_FC_ore` | vita della fuel cell in ore di funzionamento; Inf a sola batteria *(statistiche sulle ibride)* | h | 5037 | 9195 | 2.479e+04 |
| `y_vita_FC_anni` | vita_FC_viaggi / (viaggi_giorno × 365), quella del costo *(statistiche sulle ibride)* | anni | 1.479 | 2.521 | 7.203 |
| `y_vita_FC_tetto` | 1 se la vita è limitata dal tetto di 25 000 h *(statistiche sulle ibride)* | - | 0 | 0 | 0 |
| `y_dV_FC_viaggio_uV` | perdita di tensione di cella per viaggio (somma dei 4 termini, prima di K e f) *(statistiche sulle ibride)* | µV | 17.97 | 74.73 | 190.3 |
| `y_tasso_degrado_FC_uV_h` | perdita di tensione di cella per ora di funzionamento, con K = 1,72 e f: dV_fine_vita / vita_FC_ore; 0 a sola batteria *(statistiche sulle ibride)* | µV/h | 5.082 | 13.7 | 25.02 |
| `y_n_sost_FC` | sostituzioni della fuel cell in 20 anni (dopo D15) *(statistiche sulle ibride)* | - | 2 | 7 | 13 |
| `y_vita_batt_viaggi` | vita della batteria in viaggi, continua (prima dell'arrotondamento) | viaggi | 1126 | 1.547e+04 | 1.95e+04 |
| `y_vita_batt_anni` | vita_batt_viaggi / (viaggi_giorno × 365) | anni | 1.69 | 11.99 | 41.15 |
| `y_n_sost_batt` | sostituzioni della batteria in 20 anni | - | -0 | 1 | 11 |
| `y_D15_tau_anni` | D15: anni tra l'ultima sostituzione FC prevista e i 20 anni (NaN senza sostituzioni) *(statistiche sulle ibride)* | anni | 0.008692 | 1.358 | 5.593 |
| `y_D15_coda_simulata` | D15: 1 se la regola si applica (tau < 1 anno) e la coda con la FC degradata è stata simulata | - | 0 | 0 | 1 |
| `y_D15_coda_fattibile` | D15: 1 se la coda è fattibile, 0 se no, NaN se non simulata | - | 0 | 0 | 1 |
| `y_D15_sost_saltata` | D15: 1 se l'ultima sostituzione FC è saltata | - | 0 | 0 | 1 |
| `y_D15_H2_coda_kg` | D15: H2 per viaggio con la FC degradata nella coda (NaN se non simulata) | kg | 8.27 | 92.28 | 506 |
| `y_costo_EUR_km` | costo livellato totale (obiettivo dell'ottimizzazione; penalità nulla) | €/km | 1.145 | 3.035 | 8.862 |
| `y_CAPEX_FC_EUR_km` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.01306 | 0.2026 |
| `y_CAPEX_batt_EUR_km` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0.0006941 | 0.08477 | 0.2369 |
| `y_CAPEX_tank_EUR_km` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.00648 | 0.1509 |
| `y_OPEX_batt_rech_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0.0001091 | 1.4 | 3.862 |
| `y_OPEX_H2_rech_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.8569 | 7.406 |
| `y_OPEX_mant_FC_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.00355 | 0.05506 |
| `y_OPEX_mant_batt_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0.0001887 | 0.02304 | 0.06438 |
| `y_OPEX_mant_tank_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.001761 | 0.04103 |
| `y_cost_repl_FC_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.06237 | 0.804 |
| `y_cost_repl_batt_EUR_km_att` | voce del costo livellato (cost_details del simulatore); la somma delle 10 voci è costo_EUR_km | €/km | 0 | 0.05828 | 0.1834 |

## Controlli

| colonna | descrizione |
|---|---|
| `c_stato` | esito della valutazione nell'ottimo (sempre completed) |
| `c_penalita` | penalità nell'ottimo (sempre 0) |
| `c_costo_totale_EUR_km` | total_cost_EUR_km del simulatore (= costo_EUR_km senza penalità) |
| `c_somma_voci_EUR_km` | somma delle 10 voci (controllo) |
