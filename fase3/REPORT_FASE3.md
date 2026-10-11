# Fase 3: surrogato sulle tratte reali Calabria, Canavese, Firenze

Data: 2026-10-11. Simulatore: train-powertrain `c47dc17`, sola lettura. Modello `corretta`, configurazione di default, andata e ritorno, 195 t. Al massimo 8 processi.

**Calabria ha il profilo semplificato** dei tesisti: quota tutta a zero e un unico limite di velocità a 130 km/h. I suoi risultati vanno letti a parte: non dicono come si comporta il surrogato su una tratta reale con pendenze e limiti veri.

## In breve

**(a) Surrogato puro.**
- **Regime:** giusto per Calabria e Canavese. A Firenze prevede la sola batteria (p_ibrido 0,25), ma l'ottimo vero è ibrido a m_min (m = 0,0301) e lì la sola batteria non è mai fattibile.
- **Costo €/km del processo gaussiano:** errori di −0,9%, −0,8% e −1,5%, in linea con la CV (mediana 1,1%, p95 4,2%).
- **Costo ricostruito dalle grandezze previste:** sbaglia di più (+8,2%, −3,3%, −16,3%). Somma l'errore sul punto (m, n) a quello sulle grandezze, e a Firenze anche l'errore di regime.

**(b) Surrogato + simulatore.**
- **Punto previsto:** è fattibile solo per Calabria p69.
- **Dopo NOMAD-PB a 200 valutazioni:**

  | tratta | scarto dall'ottimo vero | note |
  |---|---:|---|
  | Calabria | +0,11% | |
  | Canavese | +0,001% | |
  | Firenze | — | partendo dalla sola batteria, nessun punto fattibile in 200 valutazioni |

- **Firenze, variante:** ripartendo dal ramo ibrido del surrogato (§ 3) si arriva a +0,05%.
- Dove (b) converge, regime, taglie, voci e sostituzioni coincidono con l'ottimo vero entro lo 0,3%.

**66 caratteristiche (senza `din_`).** Prevedono la sola batteria a Firenze con molta più sicurezza (p_ibrido 0,004), eppure la rifinitura trova lo stesso l'ibrido a m_min (+0,28%). Il costo diretto del processo gaussiano sbaglia di più: −2,3%, +0,8%, −4,6%.

## 1. Metodo

**Modelli finali** (`01_surrogato.jl`):
- **Dati:** addestrati su tutte le 1024 tratte del riferimento v2, con le 69 caratteristiche e, come confronto, con le 66.
- **Iperparametri:** scelti con la stessa CV interna a 3 fold della fase 2, sulla stessa griglia (`risultati/iperparametri.csv`). Quasi sempre profondità 5 e 600 alberi.
- **Boosting (EvoTrees):**
  - regime;
  - m\* (ibride);
  - n\* (ibride; sola batteria);
  - in log: H2 per viaggio e H2 del serbatoio (ibride), energia di ricarica e durata del viaggio, vita della batteria in viaggi (tutte), vita della FC in viaggi (ibride).
- **D15:** la sostituzione FC saltata vale 0 in tutte le 1024 tratte e nei tre ottimi veri, quindi il modello è la costante 0 e la coda D15 non entra nel costo.
- **Processo gaussiano:** log del costo €/km.

**Punto previsto**, come in fase 2:
- ibrido se p_ibrido ≥ 0,5;
- m = clamp(m̂, 0,03, 1), oppure 0;
- n = clamp(n̂ del regime previsto, 0,005, 1).

**(a) Surrogato puro.** Nessuna valutazione del progetto.
- **P_nom_FC e C_batt** vengono dalle formule di dimensionamento del simulatore (`reali.jl: taglie`), chiamando le sue funzioni (`taglia_FC_2`, `taglia_solo_batteria`, `_compute_P_demand`, costanti di `Objective`):
  - P_nom = m · P_max / 1,111;
  - C_batt = n · E_tot / 0,5. Per le ibride, E_tot è l'energia che la batteria fornisce sul profilo di potenza della dinamica a massa nulla, la stessa delle `din_`. Per la sola batteria il simulatore itera sulla massa della batteria rifacendo la dinamica del treno (non valuta il progetto): ripeto la stessa iterazione.
- **Controllo delle formule:** riproducono le taglie del simulatore negli ottimi delle 1024 tratte v2 (scarto massimo 3e-13) e delle tre reali (uguali al bit).
- **Il resto:**
  - viaggi al giorno = round(36 000 / durata prevista);
  - km all'anno dalla lunghezza;
  - vite in anni = vite in viaggi previste / viaggi all'anno;
  - 10 voci, costo e sostituzioni con `costo_ricostruito` (fase 1).
- **Costo in (a):** riporto sia il costo ricostruito (la somma delle voci) sia il costo previsto direttamente dal processo gaussiano.

**(b) Surrogato + simulatore** (`02_simulatore.jl`):
1. una valutazione nel punto previsto, con la causa dell'eventuale non fattibilità;
2. NOMAD-PB da 200 valutazioni dal punto previsto, con le stesse impostazioni della fase 2bis;
3. il miglior punto fattibile, rivalutato con `grandezze` per taglie, voci e sostituzioni.

Le storie sono in `~/Documents/lavoro/ml_treno_dati/fase3/`.

**Valore vero:** l'ottimo della fase 1 (`fase1/dati/dataset_reali.csv`), confermato con la forza bruta e la griglia locale.

**Errore % nelle tabelle:** previsto / vero − 1. "—" quando il vero è 0 o (b) non ha un punto fattibile; ✓ e ✗ per il regime.

## 2. Tabelle per tratta (69 caratteristiche)

### Calabria: profilo SEMPLIFICATO (quota tutta a zero, limite unico 130 km/h), da leggere a parte

| grandezza | unità | vero | (a) surrogato | errore (a) | (b) + simulatore | errore (b) |
|---|---|---:|---:|---:|---:|---:|
| regime | — | ibrido | ibrido | ✓ | ibrido | ✓ |
| m | — | 0,3221 | 0,3630 | +12,7% | 0,3226 | +0,2% |
| n | — | 0,7652 | 0,6684 | -12,6% | 0,7674 | +0,3% |
| P_nom FC | kW | 634,1 | 714,7 | +12,7% | 635,1 | +0,2% |
| C_batt | kWh | 2640,2 | 1988,8 | -24,7% | 2643,3 | +0,1% |
| serbatoio H2 | kg | 178,7 | 191,7 | +7,2% | 179,1 | +0,2% |
| costo totale | €/km | 3,956 | 4,280 | +8,2% | 3,960 | +0,1% |
| CAPEX_FC_EUR_km | €/km | 0,0540 | 0,0609 | +12,7% | 0,0541 | +0,2% |
| CAPEX_batt_EUR_km | €/km | 0,0749 | 0,0565 | -24,7% | 0,0750 | +0,1% |
| CAPEX_tank_EUR_km | €/km | 0,0271 | 0,0291 | +7,2% | 0,0272 | +0,2% |
| OPEX_batt_rech_EUR_km_att | €/km | 0,8476 | 0,8592 | +1,4% | 0,8469 | -0,1% |
| OPEX_H2_rech_EUR_km_att | €/km | 2,655 | 2,957 | +11,3% | 2,660 | +0,2% |
| OPEX_mant_FC_EUR_km_att | €/km | 0,0147 | 0,0165 | +12,7% | 0,0147 | +0,2% |
| OPEX_mant_batt_EUR_km_att | €/km | 0,0204 | 0,0153 | -24,7% | 0,0204 | +0,1% |
| OPEX_mant_tank_EUR_km_att | €/km | 0,0074 | 0,0079 | +7,2% | 0,0074 | +0,2% |
| cost_repl_FC_EUR_km_att | €/km | 0,2168 | 0,2490 | +14,8% | 0,2172 | +0,2% |
| cost_repl_batt_EUR_km_att | €/km | 0,0374 | 0,0293 | -21,6% | 0,0374 | -0,0% |
| sostituzioni FC | — | 6,000 | 6,000 | +0,0% | 6,000 | +0,0% |
| sostituzioni batteria | — | 1,000 | 1,000 | +0,0% | 1,000 | +0,0% |
| costo previsto dal processo gaussiano | €/km | 3,956 | 3,920 | -0,9% |  |  |

### Canavese

| grandezza | unità | vero | (a) surrogato | errore (a) | (b) + simulatore | errore (b) |
|---|---|---:|---:|---:|---:|---:|
| regime | — | sola batteria | sola batteria | ✓ | sola batteria | ✓ |
| m | — | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| n | — | 0,6821 | 0,6205 | -9,0% | 0,6821 | +0,0% |
| P_nom FC | kW | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| C_batt | kWh | 768,8 | 698,2 | -9,2% | 768,8 | +0,0% |
| serbatoio H2 | kg | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| costo totale | €/km | 2,830 | 2,737 | -3,3% | 2,830 | +0,0% |
| CAPEX_FC_EUR_km | €/km | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| CAPEX_batt_EUR_km | €/km | 0,0470 | 0,0427 | -9,2% | 0,0470 | +0,0% |
| CAPEX_tank_EUR_km | €/km | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| OPEX_batt_rech_EUR_km_att | €/km | 2,644 | 2,570 | -2,8% | 2,645 | +0,0% |
| OPEX_H2_rech_EUR_km_att | €/km | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| OPEX_mant_FC_EUR_km_att | €/km | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| OPEX_mant_batt_EUR_km_att | €/km | 0,0128 | 0,0116 | -9,2% | 0,0128 | +0,0% |
| OPEX_mant_tank_EUR_km_att | €/km | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| cost_repl_FC_EUR_km_att | €/km | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| cost_repl_batt_EUR_km_att | €/km | 0,1257 | 0,1124 | -10,5% | 0,1257 | +0,0% |
| sostituzioni FC | — | 0,0000 | 0,0000 | 0 | 0,0000 | 0 |
| sostituzioni batteria | — | 4,000 | 4,000 | +0,0% | 4,000 | +0,0% |
| costo previsto dal processo gaussiano | €/km | 2,830 | 2,806 | -0,8% |  |  |

### Firenze

| grandezza | unità | vero | (a) surrogato | errore (a) | (b) + simulatore | errore (b) |
|---|---|---:|---:|---:|---:|---:|
| regime | — | ibrido | sola batteria | ✗ | non fattibile | ✗ |
| m | — | 0,0301 | 0,0000 | -100,0% | — | — |
| n | — | 0,8725 | 0,7199 | -17,5% | — | — |
| P_nom FC | kW | 59,220 | 0,0000 | -100,0% | — | — |
| C_batt | kWh | 3033,8 | 3261,6 | +7,5% | — | — |
| serbatoio H2 | kg | 11,597 | 0,0000 | -100,0% | — | — |
| costo totale | €/km | 2,365 | 1,981 | -16,3% | — | — |
| CAPEX_FC_EUR_km | €/km | 0,0048 | 0,0000 | -100,0% | — | — |
| CAPEX_batt_EUR_km | €/km | 0,0817 | 0,0878 | +7,5% | — | — |
| CAPEX_tank_EUR_km | €/km | 0,0017 | 0,0000 | -100,0% | — | — |
| OPEX_batt_rech_EUR_km_att | €/km | 1,848 | 1,813 | -1,9% | — | — |
| OPEX_H2_rech_EUR_km_att | €/km | 0,3272 | 0,0000 | -100,0% | — | — |
| OPEX_mant_FC_EUR_km_att | €/km | 0,0013 | 0,0000 | -100,0% | — | — |
| OPEX_mant_batt_EUR_km_att | €/km | 0,0222 | 0,0239 | +7,5% | — | — |
| OPEX_mant_tank_EUR_km_att | €/km | 0,0005 | 0,0000 | -100,0% | — | — |
| cost_repl_FC_EUR_km_att | €/km | 0,0258 | 0,0000 | -100,0% | — | — |
| cost_repl_batt_EUR_km_att | €/km | 0,0522 | 0,0559 | +7,0% | — | — |
| sostituzioni FC | — | 8,000 | 0,0000 | -100,0% | — | — |
| sostituzioni batteria | — | 1,000 | 1,000 | +0,0% | — | — |
| costo previsto dal processo gaussiano | €/km | 2,365 | 2,330 | -1,5% |  |  |

## Confronto con le 66 caratteristiche

| tratta | regime vero / (a) / (b) | m vero / (a) / (b) | n vero / (a) / (b) | costo vero | (a) processo gaussiano | (a) ricostruito | (b) |
|---|---|---|---|---:|---:|---:|---:|
| Calabria | ibrido / ibrido / ibrido | 0,3221 / 0,3370 / 0,3222 | 0,7652 / 0,6907 / 0,7664 | 3,956 | 3,864 (-2,3%) | 3,899 (-1,4%) | 3,957 (+0,0%) |
| Canavese | sola batteria / sola batteria / sola batteria | 0,0000 / 0,0000 / 0,0000 | 0,6821 / 0,6623 / 0,6821 | 2,830 | 2,853 (+0,8%) | 2,752 (-2,7%) | 2,830 (+0,0%) |
| Firenze | ibrido / sola batteria / ibrido | 0,0301 / 0,0000 / 0,0301 | 0,8725 / 0,7292 / 0,8932 | 2,365 | 2,258 (-4,6%) | 1,841 (-22,2%) | 2,372 (+0,3%) |

## 3. Punto previsto, rifinitura e variante per Firenze

| insieme | tratta | punto previsto (m, n) | valutazione nel punto previsto | prima valutazione fattibile | punto finale (m, n) | scarto dall'ottimo vero |
|---|---|---|---|---:|---|---:|
| p69 | Calabria | (0,3630; 0,6684) | fattibile, 4,170 €/km (+5,4%), SOC 0,209 | 1 | (0,3226; 0,7674) | +0,11% |
| p69 | Canavese | (0; 0,6205) | non fattibile: SOC 0,141 < 0,2 | 2 | (0; 0,6821) | +0,001% |
| p69 | Firenze | (0; 0,7199) | non fattibile: SOC 0,192 e massa 30 018 kg > 29 250 | — | nessun punto fattibile (165 valutazioni, NOMAD si ferma) | — |
| p66 | Calabria | (0,3370; 0,6907) | non fattibile: SOC 0,185 | 2 | (0,3222; 0,7664) | +0,04% |
| p66 | Canavese | (0; 0,6623) | non fattibile: SOC 0,181 | 2 | (0; 0,6821) | +0,001% |
| p66 | Firenze | (0; 0,7292) | non fattibile: SOC 0,1997 e massa 30 467 kg | 17 | (0,0301; 0,8932) | +0,28% |
| p69, variante | Firenze | ramo ibrido: (0,0467; 0,8775) | fattibile, 2,472 €/km (+4,5%) | 1 | (0,0302; 0,8729) | +0,05% |

**Calabria p69.** Il punto previsto è fattibile, ma costa il 5,4% più dell'ottimo. Il surrogato puro lo stima al +8,2%: in quel punto la ricostruzione dalle grandezze sbaglia di circa il 2,6%. Il resto dell'errore viene dal punto: n è sottostimato del 13%, quindi la batteria è più piccola del 25% e serve più idrogeno.

**Firenze, rifinitura.** Lì la sola batteria non è mai fattibile: in fase 1 nessuno dei 151 punti della forza bruta a m = 0 lo era. NOMAD-PB, partendo da m = 0, ha valutato solo 8 punti con m > 0 e si è fermato dopo 165 valutazioni senza trovare un punto fattibile. È lo stesso modo di guasto delle tratte a m_min nel DoE (fase 2bis, coda a budget 200).

**Firenze, variante** (non richiesta, riportata a parte). Quando il classificatore è incerto (0,1 < p_ibrido < 0,9), lancio una seconda rifinitura dal punto previsto dall'altro ramo. A Firenze p69 (p = 0,25) parte da un punto già fattibile e arriva a +0,05% dall'ottimo. Raddoppia il costo solo nei casi incerti. Nelle 1024 tratte non l'ho ancora provata.

## 4. Commento

1. **Il costo €/km previsto direttamente è affidabile anche fuori dal DoE.** Il processo gaussiano p69 sbaglia dello 0,8–1,5%, anche su Canavese e Firenze, che in fase 1 erano ai margini del dominio: distanza dal vicino più prossimo al 90° e 96° percentile del DoE (Canavese è lunga 16,5 km, quasi il minimo del DoE).
2. **La progettazione "secca" no.** Il punto (m, n) previsto è quasi sempre non fattibile (5 casi su 6), come in fase 2. La ricostruzione delle voci dal punto previsto eredita quell'errore: −25% su C_batt a Calabria, voci FC a zero a Firenze.
3. **Surrogato + 200 valutazioni restituisce il progetto ottimo e le sue voci:**
   - Calabria +0,11%, Canavese +0,001%;
   - Firenze solo con la partenza dal ramo ibrido (+0,05%, oppure +0,28% da p66).
   - Per il preconfiguratore propongo di adottare la doppia partenza nei casi incerti, dopo averla provata nella CV delle 1024 tratte.
4. **Le `din_` aiutano anche qui sul costo**, ma rendono il classificatore incerto proprio su Firenze, mentre le 66 sbagliano con sicurezza. Tre tratte sono poche per dire quale insieme generalizzi meglio. Calabria, semplificata, è la tratta più vicina al DoE ed è quella dove tutto funziona meglio.

## 5. File

**In `fase3/`:**
- codice: `reali.jl`, `01_surrogato.jl`, `02_simulatore.jl`, `03_tabelle.jl`;
- Project/Manifest, copiati da fase2bis;
- `risultati/`: `surrogato_reali.csv`, `simulatore_reali.csv`, `confronto_reali.csv`, `tabelle_fase3.md`, `iperparametri.csv`, log.

**Fuori da Drive:** le storie NOMAD-PB in `~/Documents/lavoro/ml_treno_dati/fase3/`. Il primo lancio, identico, è in `primo_lancio/`.
