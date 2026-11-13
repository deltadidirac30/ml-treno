# Fase 5: gli ingressi del surrogato sulle 16384 tratte della campagna P9_D28_16384

13/11/2026. TrainPowertrain al commit `7c9115a` di `feat/align-matlab-doe`, senza modifiche. Julia 1.12.5 su Mac M4, al più 8 thread.

Vincoli rispettati:
- nessun addestramento;
- nessuna modifica al simulatore né al generatore MATLAB, nessuna riesportazione delle tratte.

Dati fuori da Google Drive e dai repo, in `~/Documents/lavoro/ml_treno_dati/`:
- `tratte_doe_16384/`: le tratte estratte;
- `P9_D28_16384/arrow/caratteristiche.arrow`: l'uscita;
- `fase5_log/`: log e file di lavoro;
- `fase5_rivalutazione/`: le 64 cartelle di campagna del campione.

Codice e risultati testuali in `fase5/`.

## In breve

- **Zip integro.** 81 921 file e 65 943 374 byte non compressi, come sul PC; CRC tutti OK.
  - SHA-256 `121ec556beebb529b3763d0c344e43ad72ee1cc32879338150ebe73874c1dbb1`.
  - Le voci usano `\` come separatore. `unzip` li converte in `/`, e dopo l'estrazione nessun nome contiene `\`.
- **Sono le tratte della campagna:** 16384/16384 in ogni controllo:
  - impronta della pendenza = manifest;
  - 2·L/1000 === `km_viaggio` del registro;
  - fermate, v_max e numero di limiti = design e manifest.
- **Rivalutazione del campione** (64 tratte × 4 coppie, stesso percorso e stesso `config.txt` della campagna):
  - stato, tipo_esito e motivo uguali in 256/256 righe;
  - grandezze discrete al bit;
  - colonne continue non al bit (scarti di macchina PC/Mac, ≤ 3·10⁻¹² della scala della colonna). **Criterio con tolleranza relativa accettato da te il 13/11.**
  - Una colonna è fuori dal criterio: `fc_non_erogata_kWh`, che vale al più 1,2·10⁻¹² kWh, cioè è zero numerico (§1b).
- **Le 66 caratteristiche** sono in `caratteristiche.arrow`: 16384 righe, `route_id` più le 66 colonne `x_` con i nomi e l'ordine della fase 1.
  - Nessun NaN né Inf.
  - Il codice della fase 1 ridà al bit le caratteristiche delle 1024 tratte di allora.
- **Il DoE nuovo è molto più largo della fase 1:** 58 caratteristiche su 66 e 15 395 tratte su 16384 escono dagli intervalli delle 1024 tratte della fase 1. Pendenze fino a ±40‰ (prima circa ±28‰), L da 5 a 300 km, limiti da 30 km/h.
- **Coerenza con il design:** L, fermate, v_max e numero di limiti 16384/16384; pendenza media entro 6·10⁻³ ‰.
- **Ridondanze:** oltre a `vlim_frac_low + mid + high = 1` (nota in fase 1) c'è una seconda identità lineare esatta: **`vlim_mean` = media dei 10 `bin_v`**. Vale anche sulle tratte della fase 1, ma allora non era stata vista (domanda 3).
- **Tempo:** 5,0 ms per tratta su un thread (mediana; media 9,5 ms, massimo 75 ms). Con 8 thread il calcolo di tutte le 16384 tratte richiede 21 s, più 21 s di lettura.

## Comandi per rifare tutto

Dalla cartella `ml_treno`. I log vanno fuori da Drive (in fase 4 i log scritti dentro Drive restavano vuoti) e si copiano poi in `fase5/risultati`.

```zsh
L=~/Documents/lavoro/ml_treno_dati/fase5_log; mkdir -p $L
julia --project=fase5 -e 'using Pkg; Pkg.instantiate()'     # stesso ambiente della fase 4 (TrainPowertrain in sviluppo, Arrow, SHA)
zsh fase5/00_zip.sh > $L/log_00.txt 2>&1                     # passo 0 (≈ 13 s); si ferma se tratte_doe_16384/ esiste già
julia -t 8 --project=fase5 fase5/01_tratte.jl > $L/log_01.txt 2>&1           # passo 1 (≈ 100 s)
julia -t 8 --project=fase5 fase5/02_caratteristiche.jl > $L/log_02.txt 2>&1  # passo 2 (≈ 65 s)
cp $L/log_0*.txt $L/0[12]_*.txt $L/0[12]_*.csv $L/sha256.txt $L/unzip_estrazione.txt fase5/risultati/   # tranne 01_tratte.csv (1,4 MB, resta in $L)
```

| file | cosa fa |
|---|---|
| `00_zip.sh` | `unzip -t`, conteggi e byte da `zipinfo`, sha256, estrazione e controlli dei nomi |
| `comune.jl` | percorsi; `tratte_blocco(k)`: le 256 tratte del blocco k con `leggi_tratte_materializzate(…; solo = …)`, in 8 pezzi paralleli; lettura del design; distanza in ULP |
| `01_tratte.jl` | passo 1: manifest, design, controlli per tratta a blocchi di 256, rivalutazione del campione e confronto con il registro |
| `02_caratteristiche.jl` | passo 2: controllo del codice sulla fase 1, calcolo, Arrow, statistiche, confronto con la fase 1, design, ridondanze |

**Risultati in `risultati/`:**
- `01_tratte.txt`, `01_campione.csv` (route, coppie, m, n), `01_confronto.csv` (una riga per caso rivalutato), `01_criterio.csv` (per colonna: righe diverse, |Δ| massimo, scala, esito);
- `02_caratteristiche.txt`, `02_statistiche.csv`, `02_confronto_fase1.csv`, `02_ridondanze.csv`;
- i log, `sha256.txt`, `unzip_estrazione.txt`.

**Tempi (Mac M4, 8 thread):**

| passo | tempo |
|---|---:|
| 0: `unzip -t`, sha256, estrazione | 13 s |
| 1a: manifest, design, 16384 tratte | 88 s (lettura con l'impronta 18 s, 1,1 ms/tratta; il resto è la lettura dei 64 blocchi Arrow e i controlli) |
| 1b: 256 valutazioni | 2,5 s di valutazione, 7 s con letture e scritture |
| 2: compilazione e controllo sulla fase 1 | ≈ 2 s |
| 2: lettura 16384 tratte | 21 s (1,26 ms/tratta di parete) |
| 2: calcolo 16384 tratte | 21 s (1,28 ms/tratta di parete con 8 thread) |
| 2: totale del processo | 64 s |

**Tempo per tratta, un thread** (solo `profilo_tratta` più le caratteristiche, senza la lettura):
- mediana 4,96 ms, media 9,50 ms, p99 44 ms, massimo 75 ms;
- cresce con L (correlazione 0,56; mediana 0,034 ms/km);
- la lettura con l'impronta costa circa altri 8 ms per tratta su un thread.

## Passo 0: zip (`risultati/log_00.txt`)

- 47 398 236 byte; `unzip -t`: "No errors detected", 81 921 voci OK.
- `zipinfo`: **81 921 file, 65 943 374 byte non compressi**, come sul PC. Ci sono 16384 × 5 file di tratta più `manifest.csv`, nessuna voce di cartella e nessuna voce con `..`.
- SHA-256 `121ec556beebb529b3763d0c344e43ad72ee1cc32879338150ebe73874c1dbb1`.
- **Separatore.** Le voci hanno host `fat` e separatore `\` (`tratte_doe_16384\route_000001\…`): `ZipFile.CreateFromDirectory` di .NET Framework scrive così. `unzip` (Info-ZIP 6.00) avvisa ("appears to use backslashes as path separators") e li converte in `/`.
  - Dopo l'estrazione in `~/Documents/lavoro/ml_treno_dati/tratte_doe_16384/`: 81 921 file, 65 943 374 byte, 16384 cartelle `route_*`, nessun nome con `\`.

## Passo 1: sono le tratte della campagna? (`risultati/01_tratte.txt`)

### 1a. Manifest, design, tratte

**Manifest:**
- un'intestazione sola (`route_id,L_m,n_fermate_intermedie,n_limiti,v_max_kmh,generatore,sha256_pendenza`);
- 16384 righe con route 1..16384 nell'ordine, tutte `doe-matlab-v3`;
- 3 righe di commento: righe 1 e 2 (esportazione delle prime 10240, 12/11 22:12) e riga 10244 (route 10241–16384 accodate alle 22:39), come previsto da `DOE_16384.md`.

**Impronte dei design nel manifest.** Sono quelle dei file con **fine riga CRLF**:

| design | sha256 sul Mac (LF) | con CRLF | nel manifest |
|---|---|---|---|
| `design_000001_010240.csv` | `b73b689a…cdbc` | `92c475cf…f102` | `92c475cf…f102` |
| `design_000001_016384.csv` | `e00a742c…043c` | `777c2b18…2a27` | `777c2b18…2a27` |

Il contenuto è lo stesso. Il MATLAB sul PC ha calcolato l'impronta sul file con i fine riga di Windows (checkout di git con `autocrlf`). Le prime 10241 righe del design da 16384 sono uguali al design da 10240.

**Design** (`design_000001_016384.csv` di `correzioni-modello`):
- 16384 righe;
- le 21 colonne uguali al bit a `tratte.arrow` della fase 4.

**Le tratte**, lette a blocchi di 256 con `leggi_tratte_materializzate(…; solo = …)` come la campagna: la lettura controlla l'impronta della pendenza contro il manifest e si ferma se è diversa.

| controllo | esito |
|---|---|
| tratte lette, impronta della pendenza = manifest | 16384 / 16384 |
| `lunghezza_binario_andata * 2.0 / 1000.0` === `km_viaggio` del registro (un solo valore per tratta) | 16384 / 16384 |
| fermate intermedie, v_max, numero di limiti = design (`n_stops`, `v_max_kmh`, `n_vlim_segments`) | 16384 / 16384 |
| L, fermate, limiti, v_max, impronta = manifest | 16384 / 16384 |
| struttura: L intero, pendenza con L+1 valori, stazioni da 0 a L, limiti da 0 a L, soste 120 s e 300 s, `route_id` di `tratta_scalari.csv` = cartella | 16384 / 16384 |
| L − 1000·`L_km` del design | da −0,5 a +0,5 m (L è arrotondato al metro) |

Le righe del registro con `km_viaggio` sono 288 per tratta, tranne 2366 (283) e 14664 (224), cioè le righe di errore D29 della fase 4.

### 1b. Rivalutazione di un campione

**Campione** (`01_campione.csv`, seme 20261113, `Xoshiro`):
- 4 tratte a caso per ognuno dei 16 gruppi di 1024 route, escluse la 2366 e la 14664;
- per ogni tratta 4 coppie di `campionamento_288.csv`: una a m = 0 (32 candidate), una nella prima fascia D25 [0,03; 0,0957) (15 candidate), due a caso tra le altre.

**Stesso percorso della campagna** (`DOE_16384.md` §3.4):
- `leggi_tratte_materializzate(tratte_doe_16384; solo = [route])`;
- `ConfigModello` costruito come `esegui_campagna.jl` senza chiavi in più;
- `CampagnaSpec(modalita = :griglia, direzioni = ["andata&ritorno"], peso_a_carico = 195000)` con le 4 coppie lette dal testo di `campionamento_288.csv`, e `esegui_campagna`.
- `config.txt` è **uguale carattere per carattere** a quello dei 64 blocchi della campagna (`modello=corretta … D26=true D27=true D28=true … peso_a_carico=195000`).

**Confronto con il registro** (Arrow della fase 4), 256 righe, 86 colonne numeriche (tutte tranne `tempo_s`):

| | esito |
|---|---|
| stato, tipo_esito, motivo, `storage_non_convergente`, `caso` | uguali 256 / 256 (245 completed, 11 rejected; 61 fattibili, 169 piccola, 21 pesante, 5 mista) |
| righe con tutte le 86 colonne al bit | **0 / 256** |
| colonne al bit in tutte le righe | 42 / 86: tutte quelle discrete (durata, n_viaggi, num_repl, scarica_s, storage_iterazioni, …), quelle di sola coppia o di sola tratta, i dV della FC tranne `dV_cicli_carico_uV` |
| colonne non al bit | 44: le energie (E_trazione in 256 righe, fino a 2902 ULP) e tutto ciò che ne deriva (SOC, vite, C-rate, H2, serbatoio, costi) |
| NaN e Inf | negli stessi posti in tutte le 86 colonne |

**Prima esecuzione e criterio.**
- Con la tolleranza di qualche ULP il controllo non passava, e mi sono fermato.
- Misurati sulla scala della colonna, gli scarti sono al più **3,2·10⁻¹² della scala** (`C_rate_carica_max`); per E_trazione 1,8·10⁻¹³ e per total_cost_EUR_km 4·10⁻¹⁴.
- Gli ULP enormi (fino a ~10¹⁸) vengono da colonne vicine a zero (`residuo_kWh`, `batt_non_erogata_kWh`).
- **Criterio accettato il 13/11** (in `01_tratte.jl`):
  - testo uguale;
  - 18 colonne discrete al bit;
  - NaN e Inf negli stessi posti;
  - colonne continue con |Δ| / scala ≤ 10⁻¹⁰, dove la scala è il massimo |valore| della colonna nelle 256 righe del registro.

**Esito con il criterio.** Tutto passa tranne una colonna: **`fc_non_erogata_kWh`**.
- Nelle 256 righe vale al più 1,2·10⁻¹² kWh, cioè è uno zero numerico.
- In 51 righe differisce di al più 2,8·10⁻¹⁵ kWh: relativo alla sua "scala" fa 2,3·10⁻³.
- Non ho cambiato il criterio da solo. Lo considero uno scarto di macchina su una grandezza nulla, ma va deciso (domanda 1).

**Causa probabile.** È la stessa differenza di macchina della fase 4 (FMA fuso sul Mac, non sul PC), che qui tocca tutta la dinamica e non solo `1,04^15`. Non l'ho dimostrata come in fase 4 (con `pow_body` ridefinita), ma tutto il resto la indica:
- `config.txt` è uguale;
- l'impronta della pendenza è uguale;
- `km_viaggio` è al bit;
- la durata della missione, che dipende da tutta la dinamica a passo di 1 s, è al bit;
- stati ed esiti sono uguali.

## Passo 2: le 66 caratteristiche (`risultati/02_caratteristiche.txt`)

**Codice.** `fase1/caratteristiche.jl` (sha256 `87f52744…`), che include `src/features.jl` (sha256 `75ab72e7…`), senza modifiche. Per ogni tratta: `profilo_tratta(cp)` (da `PrecalcoloTratta(cp, "andata")`), poi `caratteristiche_orig` (67) e `caratteristiche_nuove` (3).
- Si tengono le **66 approvate il 10/10**: le 67 meno i 4 duplicati, più `n_fermate`, `dislivello_m` e `tempo_limiti_ar_s`.
- Nomi e ordine sono uguali alle colonne `x_` di `fase1/dati/dataset_doe.csv`, senza le `din_`: controllato dallo script.
- Le 3 `din_` (variante facoltativa della fase 1) non si calcolano.

**Controllo del codice.** Sulle 1024 tratte della fase 1 (`tratte_doe_matlab`), le 70 caratteristiche ricalcolate coincidono **al bit** con `fase1/dati/caratteristiche_doe.csv` (0 valori diversi su 71 680).

**Uscita.** `~/Documents/lavoro/ml_treno_dati/P9_D28_16384/arrow/caratteristiche.arrow`, 8,7 MB:
- 16384 righe, `route_id::Int32` (1..16384) più 66 colonne `x_…::Float64`;
- metadati del file: script e data, sha256 dello zip, sha256 del codice, commit di TrainPowertrain;
- riletto, uguale a quanto calcolato.

```julia
using Arrow
c = Arrow.Table(expanduser("~/Documents/lavoro/ml_treno_dati/P9_D28_16384/arrow/caratteristiche.arrow"))
c.route_id, c.x_L_km, c.x_slope_rms   # c.route_id[i] == i; si unisce ai blocchi con tratta == route_id
```

### Controlli

**NaN e Inf:** nessuno su 1 081 344 valori. Nessuna caratteristica è costante sulle 16384 tratte.

**Statistiche e confronto con la fase 1** (`02_statistiche.csv`, `02_confronto_fase1.csv`). Nella tabella:
- min, mediana e max sono sulle 16384 tratte;
- "fase 1" è l'intervallo delle 1024 tratte di allora;
- "fuori di" è quanto il nuovo minimo o massimo supera quell'intervallo, in percentuale della sua ampiezza.

| caratteristica | min | mediana | max | fase 1: min | fase 1: max | tratte sotto / sopra | fuori di (% intervallo fase 1) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `x_L_km` | 5.01 | 152.5 | 300 | 15.02 | 199.9 | 556 / 5504 | −5% / +54% |
| `x_slope_int_pos` | 0 | 392.4 | 6528 | 0 | 1922 | 0 / 2894 | +240% |
| `x_slope_int_neg` | 0 | 395.5 | 6517 | 0 | 1951 | 0 / 2837 | +234% |
| `x_slope_rms` | 0 | 15.03 | 28.13 | 0 | 12.55 | 0 / 10196 | +124% |
| `x_slope_mean_pos` | 0 | 9.026 | 36.46 | 0 | 12.09 | 0 / 6058 | +202% |
| `x_slope_std_pos` | 0 | 4.593 | 16.25 | 0 | 6.844 | 0 / 5720 | +137% |
| `x_slope_mean_neg` | -33.65 | -9.039 | 0 | -11.44 | 0 | 6517 / 0 | −194% |
| `x_slope_std_neg` | 0 | 4.61 | 17.26 | 0 | 7.419 | 0 / 5038 | +133% |
| `x_slope_max` | -19.47 | 19.44 | 40 | -9.531 | 28.4 | 499 / 5157 | −26% / +31% |
| `x_slope_min` | -40 | -19.39 | 19.73 | -27.98 | 9.242 | 5311 / 515 | −32% / +28% |
| `x_slope_std_all` | 0 | 8.872 | 20 | 0 | 7.997 | 0 / 8841 | +150% |
| `x_slope_std_sq_pos` | 0 | 90.67 | 666.2 | 0 | 186.7 | 0 / 5650 | +257% |
| `x_slope_L_up_frac` | 0 | 0.4204 | 1 | 0 | 1 | 0 / 0 | — |
| `x_slope_sign_changes_per_km` | 0 | 0.1181 | 0.9862 | 0 | 0.8031 | 0 / 33 | +23% |
| `x_slope_max_run_up_km` | 0 | 7.934 | 299.6 | 0 | 199.9 | 0 / 574 | +50% |
| `x_vlim_mean` | 40.76 | 84.36 | 160 | 67.17 | 160 | 4291 / 1 | −28% / +0% |
| `x_vlim_std` | 0 | 8.377 | 59.95 | 0 | 43.16 | 0 / 58 | +39% |
| `x_vlim_max` | 60 | 110 | 160 | 80 | 160 | 3121 / 0 | −25% |
| `x_vlim_min` | 30 | 65 | 160 | 60 | 160 | 6676 / 0 | −30% |
| `x_vlim_sum_abs_dv2` | 0 | 2.531e4 | 5.022e5 | 0 | 2.207e5 | 0 / 119 | +128% |
| `x_vlim_changes_per_km` | 0 | 0.1159 | 0.3137 | 0 | 0.1616 | 0 / 5395 | +94% |
| `x_vlim_sum_dv_pos_sq` | 0 | 1300 | 7.38e4 | 0 | 2.25e4 | 0 / 166 | +228% |
| `x_vlim_sum_dv_neg_sq` | 0 | 1300 | 8.165e4 | 0 | 2.2e4 | 0 / 179 | +271% |
| `x_vlim_frac_low` | 0 | 0.2838 | 1 | 0 | 0.8718 | 0 / 4349 | +15% |
| `x_vlim_frac_mid` | 0 | 0.05978 | 1 | 0 | 1 | 0 / 0 | — |
| `x_vlim_frac_high` | 0 | 0.1068 | 1 | 0 | 1 | 0 / 0 | — |
| `x_stops_density` | 0 | 0.07931 | 0.5575 | 0 | 0.3262 | 0 / 1078 | +71% |
| `x_stops_spacing_std` | 0 | 4.6 | 142.5 | 0 | 31.46 | 0 / 947 | +353% |
| `x_stops_sum_v2` | 0 | 6.86e4 | 6.912e5 | 0 | 1.176e6 | 0 / 0 | — |
| `x_stops_mean_v` | 0 | 79.44 | 160 | 0 | 160 | 0 / 0 | — |
| `x_stops_std_v` | 0 | 6.124 | 74.25 | 0 | 49.3 | 0 / 38 | +51% |
| `x_stops_mean_p` | -39.34 | 0 | 38.39 | -16 | 18.66 | 1490 / 721 | −67% / +57% |
| `x_stops_sum_abs_p` | 0 | 101.3 | 779.6 | 0 | 525.8 | 0 / 180 | +48% |
| `x_stops_frac_on_slope` | 0 | 0.7778 | 1 | 0 | 1 | 0 / 0 | — |
| `x_cross_Lup_v` | 0 | 6.488e4 | 1.086e6 | 0 | 2.974e5 | 0 / 1753 | +265% |
| `x_cross_Ldn_v` | -1.057e6 | -6.521e4 | 0 | -2.786e5 | 0 | 1993 / 0 | −279% |
| `x_cross_brake_energy_signed` | -6.338e5 | 0 | 6.539e5 | -8.063e5 | 1.008e6 | 0 / 0 | — |
| `x_cross_thermal_fatigue` | 0 | 4.721e5 | 1.561e7 | 0 | 1.768e6 | 0 / 3864 | +783% |
| `x_cross_stops_v_seg` | 0 | 8138 | 1.183e6 | 0 | 1.171e6 | 0 / 1 | +1% |
| `x_cross_abs_p_highv` | 0 | 16.5 | 7135 | 0 | 2066 | 0 / 1670 | +245% |
| `x_cross_up_lowv` | 0 | 0 | 7196 | 0 | 975.2 | 0 / 3064 | +638% |
| `x_cross_mean_p_v` | -3171 | 0 | 3135 | -1508 | 1503 | 1149 / 1166 | −55% / +54% |
| `x_cross_var_p_v` | 0 | 5.493e5 | 1.021e7 | 0 | 1.528e6 | 0 / 3994 | +568% |
| `x_bin_p_1` | -39.96 | 0 | 39.9 | -14.38 | 18.11 | 2280 / 1147 | −79% / +67% |
| `x_bin_p_2` | -38.58 | 0 | 39.01 | -17.08 | 18.35 | 1429 / 1105 | −61% / +58% |
| `x_bin_p_3` | -38.13 | 0 | 36.06 | -18.68 | 18.22 | 1001 / 1113 | −53% / +48% |
| `x_bin_p_4` | -36.67 | 0 | 38.76 | -16.52 | 21.61 | 1615 / 455 | −53% / +45% |
| `x_bin_p_5` | -39.23 | 0 | 39.66 | -17.28 | 18.06 | 1420 / 1140 | −62% / +61% |
| `x_bin_p_6` | -39.23 | 0 | 39.58 | -17.47 | 17.17 | 1341 / 1395 | −63% / +65% |
| `x_bin_p_7` | -39.98 | 0 | 39.12 | -21.86 | 15.17 | 465 / 2025 | −49% / +65% |
| `x_bin_p_8` | -39.98 | 0 | 36.83 | -18.09 | 19.31 | 1139 / 852 | −59% / +47% |
| `x_bin_p_9` | -39.74 | 0 | 39.35 | -17.38 | 15.86 | 1360 / 1804 | −67% / +71% |
| `x_bin_p_10` | -39.74 | 0 | 39.38 | -17.56 | 21 | 1321 / 544 | −58% / +48% |
| `x_bin_v_1` | 30 | 85 | 160 | 60 | 160 | 2684 / 0 | −30% |
| `x_bin_v_2` | 30 | 85 | 160 | 60 | 160 | 2844 / 0 | −30% |
| `x_bin_v_3` | 30 | 84.71 | 160 | 60 | 160 | 2789 / 3 | −30% / +0% |
| `x_bin_v_4` | 30 | 84.63 | 160 | 60 | 160 | 2854 / 0 | −30% |
| `x_bin_v_5` | 30 | 84.98 | 160 | 60 | 160 | 2878 / 0 | −30% |
| `x_bin_v_6` | 30 | 84.16 | 160 | 60 | 160 | 2877 / 0 | −30% |
| `x_bin_v_7` | 30 | 84.67 | 160 | 60 | 160 | 2839 / 0 | −30% |
| `x_bin_v_8` | 30 | 84.57 | 160 | 60 | 160 | 2843 / 0 | −30% |
| `x_bin_v_9` | 30 | 85 | 160 | 60 | 160 | 2802 / 0 | −30% |
| `x_bin_v_10` | 30 | 85 | 160 | 60 | 160 | 2673 / 0 | −30% |
| `x_n_fermate` | 0 | 11 | 28 | 0 | 62 | 0 / 0 | — |
| `x_dislivello_m` | 0 | 1001 | 5963 | 0 | 1919 | 0 / 4736 | +211% |
| `x_tempo_limiti_ar_s` | 560.3 | 1.604e4 | 4.268e4 | 1091 | 3.342e4 | 117 / 1130 | −2% / +29% |

**Cosa esce dagli intervalli della fase 1, e perché.** Il DoE è cambiato (`08f287d`: limiti allargati sulle linee reali, fermate condizionate, A/R entro 12 h), quindi l'uscita è attesa.
- **58 caratteristiche su 66** hanno almeno una tratta fuori, e **15 395 tratte su 16384** hanno almeno una caratteristica fuori.
- Restano dentro solo 8 caratteristiche: `slope_L_up_frac`, `vlim_frac_mid`, `vlim_frac_high`, `stops_sum_v2`, `stops_mean_v`, `stops_frac_on_slope`, `cross_brake_energy_signed`, `n_fermate` (ora fino a 28, prima fino a 62).
- **Pendenze.** Pendenze massima e minima fino a ±40‰ (prima +28/−28), deviazioni standard e medie per verso circa tre volte quelle di prima, `dislivello_m` fino a 5963 m (prima 1919). Le caratteristiche "cross" che moltiplicano pendenza e lunghezza o velocità escono di più: `cross_thermal_fatigue` fino a 8 volte l'intervallo di prima, `cross_var_p_v` e `cross_up_lowv` 6 volte.
- **Lunghezza.** L da 5,0 a 300 km (prima da 15 a 200).
- **Limiti.** `vlim_min` e `bin_v` scendono fino a 30 km/h (prima 60), `vlim_max` a 60 (prima 80), e la densità dei cambi di limite raddoppia.
- **Fermate.** Densità fino a 0,56/km (prima 0,33).
- La parte larga del nuovo dominio è popolata: per esempio `slope_rms` supera il vecchio massimo in 10 196 tratte.

**Coerenza con il design** (solo verifica: i fattori non sono ingressi):

| fattore | esito |
|---|---|
| L | \|`x_L_km` − `L_km`\| ≤ 0,0005 km; **2·`x_L_km` === `km_viaggio` del registro in 16384/16384** (`x_L_km` è la lunghezza esportata, come chiede la fase 4) |
| fermate | `x_n_fermate` = `n_stops` 16384/16384 |
| v_max | `x_vlim_max` = `v_max_kmh` 16384/16384 |
| numero di limiti | `vlim_changes_per_km`·L + 1 = `n_vlim_segments` 16384/16384 |
| pendenza media | (`slope_int_pos` − `slope_int_neg`)/L contro `slope_mean`: mediana dello scarto 3,6·10⁻⁵ ‰, massimo **6,1·10⁻³ ‰** (route 3977, L = 6,1 km, −9,0371 contro −9,0310 ‰); in fase 1 il massimo era 1·10⁻³ ‰. Con L del design al posto di quella esportata resta 5,5·10⁻³: lo scarto viene dal profilo metro per metro, non dall'arrotondamento di L. È più grande sulle tratte corte, che in fase 1 non c'erano (L ≥ 15 km) |
| densità delle fermate | `x_stops_density` contro `stop_density`: scarto ≤ 1,8·10⁻⁵ /km (L in metri interi contro `L_km`) |

**Identità esatte** (come la fase 1 [b2], sulle 16384):

| identità | max \|scarto\| | scala |
|---|---:|---:|
| `slope_int_abs` = `slope_int_pos` + `slope_int_neg` (duplicato tolto) | 1,8·10⁻¹² | 7278 |
| `stops_sum_v2_segweighted` = `stops_sum_v2` (duplicato tolto) | 0 | 6,9·10⁵ |
| `stops_spacing_mean` = L/(n_fermate+1) (duplicato tolto) | 1,4·10⁻¹⁴ | 300 |
| `cross_int_p_v` = `cross_mean_p_v`·L (duplicato tolto) | 1,2·10⁻¹⁰ | 8,9·10⁵ |
| `stops_density` = n_fermate/L | 0 | 0,56 |
| `slope_int_pos` − `slope_int_neg` = quota(L) − quota(0) | 5,0·10⁻¹² | 6528 |
| `vlim_frac_low` + `mid` + `high` = 1 | 2,2·10⁻¹⁶ | 1 |

**Tra le 66:**
- nessuna coppia di colonne identica;
- una sola coppia con |correlazione| ≥ 0,98: `slope_std_pos` e `slope_std_sq_pos` (Pearson 0,954, Spearman 0,990), come in fase 1.
- La matrice standardizzata 16384 × 66 ha **2 valori singolari nulli** (8,8·10⁻¹³ e 1,3·10⁻¹³ contro 500), cioè 2 dipendenze lineari esatte:
  1. `vlim_frac_low + vlim_frac_mid + vlim_frac_high = 1`, già nota e tenuta come composizione;
  2. **`vlim_mean` = (`bin_v_1` + … + `bin_v_10`)/10**, con scarto massimo 8,5·10⁻¹⁴: i 10 decimi hanno la stessa lunghezza e la media pesata sulla lunghezza è la media dei decimi. **Vale anche sulle 1024 tratte della fase 1** (5,7·10⁻¹⁴), ma lì non era stata segnalata (domanda 3).

**Tratte con errore D29 in fase 4** (2366 e 14664): le caratteristiche sono calcolate come per le altre.
- 2366: L 224,1 km, 13 fermate, v_max 100 km/h, dislivello 3734 m;
- 14664: L 37,1 km, 9 fermate, v_max 70 km/h.

## Anomalie e domande aperte

1. **`fc_non_erogata_kWh` fuori dal criterio accettato.** È uno zero numerico: al più 1,2·10⁻¹² kWh, scarto 2,8·10⁻¹⁵ kWh in 51 righe su 256. Rapportato al massimo della colonna fa 2·10⁻³. Per chiudere il controllo serve una tolleranza assoluta sulle colonne che sono zero numerico, oppure una scala fisica (per esempio l'energia della missione). Non l'ho cambiata. Il surrogato comunque non usa questa colonna (fase 4, §3.3).
2. **Rivalutazione non al bit tra PC e Mac.** 44 colonne su 86 differiscono, fino a 3·10⁻¹² della scala. Non ho verificato la causa (FMA) come in fase 4. Per la conferma al bit si può rivalutare lo stesso campione (`01_campione.csv`) sul PC Windows e confrontare i registri: con gli stessi bit dimostrerebbe che la differenza è solo di macchina.
3. **`vlim_mean` è combinazione lineare esatta dei 10 `bin_v`**, anche in fase 1. Che cosa fare:
   - tenerla, se il modello regge le colinearità (alberi, reti con regolarizzazione);
   - toglierla, e allora gli input sono 65;
   - oppure togliere un `bin_v`.

   Non ho tolto nulla: `caratteristiche.arrow` ha le 66 approvate.
4. **Il dominio è cambiato molto rispetto alla fase 1.** Le statistiche e le soglie della fase 1 (normalizzazioni, dominio delle tratte reali, distanze dal vicino) non valgono più. Sulmona-Carpinone era fuori dominio in 12 caratteristiche (pendenze fino a 21,9‰): con pendenze DoE fino a ±40‰ è probabilmente dentro. Il controllo di dominio delle 5 tratte reali va rifatto sulle 16384 (non fatto qui).
5. **Impronte del design nel manifest calcolate sul file CRLF.** Non è un errore, ma chi confronta l'impronta del manifest con il file sul Mac trova un valore diverso. Conviene scriverlo nella documentazione del DoE, o calcolare l'impronta sul testo normalizzato a LF.
6. **Zip con `\` come separatore.** `unzip` (Info-ZIP) lo riconosce e converte. Non è detto che altri strumenti facciano lo stesso: alcuni estraggono file piatti con `\` nel nome. Per i prossimi zip dal PC conviene `tar -a -cf archivio.zip cartella` (il `tar` di Windows), e in ogni caso ricontrollare i nomi con `zipinfo -1` prima di estrarre, come fa `00_zip.sh`.
7. **Pendenza media e design:** scarto fino a 6·10⁻³ ‰ sulle tratte corte (in fase 1 al più 10⁻³). È trascurabile, ma il controllo della fase 1 ("≤ 1e-3") qui non passerebbe. Nello script la soglia di anomalia è 10⁻² ‰, scelta da me.
8. **Le 3 `din_`** (variante della fase 1) non sono calcolate. Servono la dinamica di riferimento, circa 5 ms per tratta; si possono aggiungere se si vuole confrontare la variante.
9. **Tratte 2366 e 14664** (errori D29 in fase 4): hanno le caratteristiche come le altre. Resta aperta la decisione della fase 4 (domanda 6): escluderle dall'addestramento, o escludere solo le righe in errore.
10. **`ml_treno` ha modifiche non committate** estranee alla fase 5 (`results/plots`, `fase3/…`, `PROPOSTA_COMMIT.md`): non le ho toccate. Il commit contiene solo i file di `fase5/`.
