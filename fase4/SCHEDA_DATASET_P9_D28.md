# Scheda del dataset P9_D28_16384

**Cos'è.** Campagna del campionatore fisico P9 con D28: 16384 tratte DoE (`design_000001_016384.csv`) × 288 coppie (m, n) di `campionamento_288.csv`, in andata e ritorno.
- Modello `:corretta`, configurazione = `ConfigModello()` di TrainPowertrain, peso a carico 195 t.
- 4 718 592 righe, una per (tratta, coppia).
- Eseguita sul PC Windows il 12–13/11/2026.
- Controlli e conversione: `REPORT_FASE4_DATI.md`.

## File

In `~/Documents/lavoro/ml_treno_dati/P9_D28_16384/`, fuori da Google Drive:

| file | contenuto |
|---|---|
| `arrow/blocco_01.arrow` … `blocco_64.arrow` | il registro, una tabella per blocco (route (k−1)·256+1 … k·256, 73 728 righe), zstd, 26 MiB l'una |
| `arrow/coppie.arrow` | le 288 coppie |
| `arrow/tratte.arrow` | le 16384 righe del design, più blocco e flag |
| `arrow/tratte_riassunto.arrow` | per tratta: fattibili, migliore delle 288, quote |
| `arrow/dizionari.arrow` | codici di `stato`, `tipo_esito`, `motivo` |
| `raw/P9_D28_16384/blocco_XX/{registro.csv,config.txt}`, `raw/errori_P9_D28_16384.csv` | i CSV originali, estratti dallo zip (sha256 `e8adba51…771167`) |

## Schema dei blocchi (93 colonne)

È il registro di `Campagna.INTESTAZIONE_REGISTRO`, con queste differenze:
- **tolte** `caso` (= `route_%06d_ar_m%.6g_n%.6g`), `direzione` (sempre `andata&ritorno`) e `fine` (data e ora);
- **aggiunta** `coppia` dopo `tratta`.

Tipi:
- `tratta::Int32`: route_id;
- `coppia::Int16`: 1..288, indice in `coppie.arrow`;
- `stato::Int8`: 1 completed, 2 rejected, 3 error;
- `motivo::Int16`: 1 = vuoto, 2 = D3 "batteria sottodimensionata…", 3 = D7 (mai presente), 4..72 = i 69 testi `DOE:D26FrenataImpossibile…`;
- `tipo_esito::Int8`: 1 fattibile, 2 piccola, 3 pesante, 4 mista, 5 errore;
- `storage_non_convergente::Union{Missing,Bool}`: D28; missing nelle 69 righe di errore;
- **tutte le altre 86 colonne `Float64`**, uguali al bit al testo del CSV (`%.17g`). Anche gli indicatori 0/1 (`vita_FC_tetto`, `vita_batt_limite_calendario`, `sostituzione_FC_saltata`) e i conteggi (`num_repl_*`, `n_viaggi_giorno`, `storage_iterazioni`, …) sono Float64.

Definizioni delle colonne P9: `report_natanti/P9.md` §2 (train-powertrain). Le colonne di costo e di bilancio sono quelle di prima del P9.

**Quando le colonne sono piene:**
- **completed:** tutte. A m = 0 le vite della FC sono +Inf e `tau_FC_anni` NaN; `H2_coda_kg` è sempre NaN (D15 spenta).
- **rejected (D3, costo 20000):** NaN le 17 colonne di costo (`P_nom_fc_kW` … `num_repl_batt`) e `vita_FC_ore`/`vita_FC_tetto`. Piene le colonne P9 e del bilancio; SOC_end si ricava da `vincolo_soc_pt`.
- **error (costo 10000):** tutto NaN tranne m, n, m_richiesta, costo, tempo_s.

**Fattibile** = `tipo_esito == 1`, cioè completed senza penalità (costo == total_cost_EUR_km).

**Codici e metadati.** I dizionari sono anche nei metadati di colonna (`Arrow.getmetadata(t.stato)`). I metadati del file contengono config.txt e lo sha256 dello zip.

## coppie.arrow, tratte.arrow, tratte_riassunto.arrow

- **`coppie.arrow`:**
  - `coppia`, `m`, `n` (Float64, al bit come nel CSV);
  - `origine` (`sobol` righe 1–256, `soglie` righe 257–288);
  - `sola_batteria` (m = 0: 32 coppie);
  - `intervallo_D25`: 0 se m = 0; 1..4 tra m_min = 0,03, le soglie 0,0957 / 0,1016 / 0,1195 e 1.
- **`tratte.arrow`:**
  - le 21 colonne del design (`route_id`, `L_km`, `slope_mean`, `stop_density`, …);
  - `blocco`;
  - `errore_D29` (route 2366 e 14664, con righe `DOE:D26FrenataImpossibile`);
  - `senza_coppie_fattibili` (sempre false).
- **`tratte_riassunto.arrow`:**
  - `n_fattibili` (anche `_sola_batteria` e `_ibride`);
  - la migliore fattibile delle 288: `costo_migliore`, `coppia_migliore`, `m_migliore`, `n_migliore`, `regime_migliore` (0 nessuna, 1 sola batteria, 2 ibrido), `migliore_D28`;
  - `costo_migliore_sola_batteria`, `costo_migliore_ibrido`;
  - quote per `tipo_esito`, `quota_rejected_D3`, `quota_D28`.

## Come si legge

Con l'ambiente di `fase4` (`julia --project=fase4`), che ha TrainPowertrain in sviluppo e Arrow.jl:

```julia
using Arrow, TrainPowertrain
const D = expanduser("~/Documents/lavoro/ml_treno_dati/P9_D28_16384/arrow")
t = Arrow.Table(joinpath(D, "blocco_01.arrow"))          # colonne: t.tratta, t.m, t.SOC_end, …
fatt = t.tipo_esito .== 1
coppie = Arrow.Table(joinpath(D, "coppie.arrow"))         # coppie.m[t.coppia[i]] == t.m[i]

# costo con altri prezzi, senza simulare (stesse regole della campagna: cfg = ConfigModello())
cols = ["m","n","P_nom_fc_kW","C_batt_kWh","H2_serbatoio_kg","km_viaggio","n_viaggi_giorno","E_ricarica_rete_kWh",
        "H2_cons_kg","SOC_end","vita_batt_cicli_viaggi","vita_FC_viaggi","vita_FC_f1_ore","durata_viaggio_s",
        "f_degrado_FC","ore_max_FC","massa_propulsione_kg","limite_massa_propulsione_kg","scarica_s"]
i = findfirst(==(1), t.stato)
g = Dict(c => getproperty(t, Symbol(c))[i] for c in cols)
r = costo_da_grandezze(g, ParametriCosto(costo_H2 = 3.3); cfg = ConfigModello())   # r.costo, r.costo_totale, r.voci
```

**Tutto il dataset.** `include("fase4/comune.jl"); D = carica_tutto()` carica le 93 colonne in un `Dict` in circa 4–7 s (3,1 GiB). `carica_tutto(["tratta", "m", "SOC_end"])` tiene solo quelle, ma `Arrow.Table` decomprime comunque tutte le colonne del blocco.

**Al bit sul costo.** Su questo Mac `costo_da_grandezze` ridà `total_cost_EUR_km` al bit in tutte le completed tranne 4374, che differiscono al più di 3 ULP. La causa è `1,04^15` con o senza FMA (`REPORT_FASE4_DATI.md`).

## Insieme minimo da imparare

Ingressi: la tratta (caratteristiche del profilo, e la lunghezza `km_viaggio/2`, non `L_km` del design), m e n.

| # | grandezza | regime | note |
|---|---|---|---|
| 1 | `durata_viaggio_s` | tutti | dipende solo da (tratta, massa del treno); quasi lineare nella massa, rumore 1–40 s |
| 2 | `massa_serbatoio_kg` | ibrido (0 a m = 0) | |
| 3 | `H2_cons_kg` | ibrido (0 a m = 0) | |
| 4 | `SOC_end` | tutti | in [0; 0,9]; vincolo a 0,2 |
| 5 | `scarica_s` | tutti | serve solo > 0 (penalità 3000): classificatore |
| 6 | `vita_batt_cicli_viaggi` | tutti | 26 … 5,4·10⁵: scala log |
| 7 | `vita_FC_viaggi` (o `vita_FC_f1_ore` per f diverso) | ibrido (+Inf a m = 0) | |
| + | esito D3 (`stato == 2`) | tutti | classificatore: 2,1% delle righe; sopra il 50% solo nelle 6 coppie con n < 0,05 |

**Grandezze esatte, da non imparare** (verificate al bit su tutte le righe simulate):
- da m: `P_nom_fc_kW`, `massa_FC_kg`, `n_celle_FC` (`taglia_FC_2(m·P_max; r = rapporto_picco_fc())`), `P_max_FC_kW = P_max·m`;
- da n: `C_batt_kWh`, `massa_batteria_kg`, `n_stringhe_batteria` e la capacità in Ah (`taglia_batteria_da_n(n, riferimento_batteria(195000, 1500), 1500)`);
- costanti: `E_ref_kWh`, `limite_massa_propulsione_kg = 29250`, `SOC_iniziale = 0,8`, `f_degrado_FC`, `ore_max_FC = 25000`, `vita_batt_calendario_anni = 15`;
- dalla tratta: `km_viaggio`.

**Formule dalle 7 grandezze:**
- `n_viaggi_giorno = matlab_round(36000/(durata+1))`;
- `H2_serbatoio_kg = 0,055·massa_serbatoio`;
- `massa_propulsione = massa_batteria + massa_FC + massa_serbatoio`;
- `E_ricarica_rete_kWh = ((0,8 − SOC_end)·Capacita_batteria(n)·1500)/1000`;
- `vincolo_*` e la penalità;
- poi tutto il costo con `costo_da_grandezze`.

**Da non imparare** (dipendono da prezzi od orizzonte): costo, total_cost_EUR_km, le voci, `num_repl_*`, `tau_FC_anni`, `valore_residuo_*`.

## Numeri

| quantità | valore |
|---|---|
| completed | 4 620 434 (97,92%), di cui fattibili 2 014 193 |
| rejected | 98 089 (D3) |
| error | 69 (2 tratte) |
| D28 | 15 491 righe |
| fattibili per tratta | da 7 a 265, mediana 114 |
| migliore a sola batteria | 4208 tratte |
| migliore ibrida | 12 176 tratte |
| costo della migliore | da 1,13 a 8,58 €/km, mediana 3,73 |
| coppie mai fattibili | 23 |
