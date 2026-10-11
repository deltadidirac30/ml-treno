# Fase 2bis: riferimento v2 e riesecuzione della fase 2

Data: 2026-10-11. Simulatore: train-powertrain `c47dc17`, sola lettura (nessuna modifica tracciata, controllato a fine lavoro). Modello `corretta`, `ConfigModello()` di default, andata e ritorno, 195 t. Al massimo 8 processi o thread alla volta.

- **Riferimento v1 intatto.** `fase1/dati/ottimi_riferimento.csv` e `fase1/dati/dataset_doe.csv` non sono stati toccati. La v2 sta in `fase2bis/dati/`.
- **Tratte reali e insieme di prova ancora ciechi.** Nessuno script di `fase2bis/` legge `dataset_reali*`, `tratte_reali` o tratte oltre la 1024 (controllato con `grep`).
- **Il punto 3 (insieme di prova) non è partito.** Aspetta il tuo ok.

## In breve

1. **Commit.** Fatti i primi due:
   - `f3c2537`: DoE e pipeline precedente;
   - `53ca6b1`: fase 1.

   L'elenco del terzo (fase 2) è in `PROPOSTA_COMMIT.md` ed è riassunto nel § 0. Non è eseguito. Nessun push.
2. **Riferimento v2: cambiano 163 tratte su 1024.**

   | miglioramento sulla v1 | tratte |
   |---|---:|
   | oltre lo 0,1% | 35 |
   | oltre l'1% | 18 |
   | oltre il 5% | 7 |
   | massimo | 18,5% (route 801) |

   - **Cambi di regime:** uno solo, la route 477, da ibrido a m = 0,0301 a sola batteria (−5,6%).
   - **Dove stanno:** delle 18 tratte sopra l'1%, 13 sono isole fattibili a sinistra di D20 (0,1095 ≤ m\* < 0,1195).
   - **Senza i punti della fase 2:** le sole partenze P1–P4 trovano 30 delle 35 migliorie oltre lo 0,1% e 16 delle 18 oltre l'1%.
3. **La v2 è solida.**
   - **Controlli della fase 1:** superati in tutte le 1024 tratte. Penalità 0, costo uguale al candidato, costo ricostruito dalle grandezze con scarto 2e-16.
   - **Griglia su 30 tratte prese a caso tra quelle non toccate:** non trova niente oltre lo 0,1% (massimo 0,001%).
   - **Rifinitura gb + NOMAD-PB a 200 valutazioni:** non batte mai la v2 di oltre lo 0,1% (massimo 0,086%).
4. **Le metriche dei modelli cambiano poco tra v1 e v2** (tabella completa nel § 3).
   - **Previsione secca gb p69:** errore di regime 1,35% (era 1,50%), non fattibili 55,8% (era 54,5%), rimpianto mediano 0,75% (0,74%), p95 6,3% (7,5%).
   - **Rifinitura a 100 valutazioni:** mediana 0,12% (invariata), p95 2,3% (era 1,8%). La v2 è più difficile proprio dove la v1 sbagliava: le isole di D20.
5. **Il budget 200 cambia il quadro.**

   | gb p69 + NOMAD-PB 200 | valore |
   |---|---:|
   | rimpianto mediano | **0,018%** |
   | rimpianto p95 | 0,77% |
   | tratte fattibili ed entro lo 0,25% | 90% (con 100 valutazioni erano il 66%) |
   | rimpianto p95, ibride | 1,7% |
   | rimpianto p95, sola batteria | 0,07% |

   La campagna (972 valutazioni) ha p95 0,11% contro la v2. Ciò che resta nella coda sono le isole di D20 e m_min.
6. **La rete piccola sul costo è peggio del processo gaussiano.**

   | caratteristiche | rete: mediana / p95 / max | processo gaussiano: mediana / p95 / max |
   |---|---|---|
   | 69 | 2,19% / 7,4% / 27% | **1,09% / 4,2% / 9,6%** |
   | 66 | 2,56% / 9,1% | 1,68% / 6,0% |

   La rete batte il boosting (2,85%) ma non il processo gaussiano, nemmeno con 15 ricette di addestramento provate (§ 2).

## 0. Commit

**Commit fatti** su `main` in ml_treno, nessun push:
- `f3c2537` DoE Sobol delle tratte (generatore, script 07–09, design) e modifiche alla pipeline precedente. 35 file. `.gitignore` esclude `data_profiles/`, `outputs/`, `info_tratta/`, `train-powertrain-matlab-optmz/` e `conversazione chat.md`.
- `53ca6b1` fase 1. 31 file: codice, Project/Manifest, report, scheda, `ottimi_riferimento.csv`, dataset, controlli. Esclusi `caratteristiche_*` e `uscite_*`, che restano non tracciati.

**Commit 3 (fase 2), proposto e non eseguito.** Elenco completo in `PROPOSTA_COMMIT.md`, circa 1,3 MB.

Si includono:
- codice (9 file), Project/Manifest, `REPORT_FASE2.md`;
- in `risultati/`:
  - metriche: `metriche*.txt/csv`, `metriche_b_p69.*`, `metriche_fisiche.csv`;
  - analisi: `analisi_*`, `importanza*`, `curva_apprendimento_*`, `errori_categorie_*`;
  - riferimento: `riferimento_noto.csv`, `riferimento_migliorabile.csv`, `sensibilita_riferimento.txt`;
  - altro: `controllo_rifinitura_p69.txt`, `log_01_cv.txt`;
- `rifinitura_p69.csv`: 961 KB, sotto la soglia di 1 MB, e rigenerarlo costa circa mezz'ora.

Si escludono:
- `sim_cv.csv`, 13,8 MB;
- `cv/pred_r*.csv` e `cv/fisiche_r1_*.csv`: sono previsioni e non metriche. Ogni file sta sotto 1 MB, ma insieme fanno 10,6 MB;
- i log duplicati.

Con il commit si aggiungono a `.gitignore` le righe per tutto questo e per `fase1/dati/{caratteristiche,uscite}_*`.

## 1. Riferimento v2

### Procedura (`01_partenze.jl` … `04_v2.jl`)

**Partenze sistematiche** su tutte le 1024 tratte. NOMAD-PB ha le stesse impostazioni del runner: `_uscite(:progressiva)`, tipi OBJ + 4 PB, seme 20261010, valutatore `_Valutatore` con D7 e D8. I limiti sono m ∈ [0, 1] e n ∈ [0, 1], come nella rifinitura della fase 2. Budget 100 per partenza, lanci separati, 8 processi. In tutto 4096 lanci e 366 629 valutazioni, in 20 minuti. Le storie complete sono salvate.

| partenza | (m, n) iniziale | scopo |
|---|---|---|
| P1 | (0,11; n_rif) | isola a sinistra di D20 |
| P2 | (0,11; 0,95) | isola tipo 801 |
| P3 | (0; max(n_rif; 0,5)) | sola batteria |
| P4 | (m_rif; 0,05); m = 0,2 se m_rif = 0 | batteria piccola |

**Candidato v2.** È il costo fattibile minimo tra:
- `v1_nomad` e `v1_vecchio`;
- P1–P4, con tutte le valutazioni fattibili dei lanci;
- `fase2`: tutti i punti fattibili valutati in fase 2, cioè previsioni secche e rifiniture.

A pari costo resta la fonte che viene prima nell'elenco (prima la v1). Calcolo anche la variante "senza fase 2" (v1 + P1–P4).

**Conferma con la griglia.** Riguarda le 35 tratte migliorate di oltre lo 0,1%.
- **Passo e finestra:** passo 0,0005 e ±0,02 in m e n attorno al nuovo ottimo. Per le tratte a sola batteria m resta fisso a 0.
- **Ricentramento (aggiunta mia):** se il miglior punto della griglia è più economico e sta sul bordo della finestra, la griglia si ricentra e si ripete, al massimo 10 giri. Senza questa regola la route 240 si sarebbe fermata sul bordo con il 4,1% di miglioramento ancora in corso. È servito un secondo giro solo lì.
- **Peso nella v2:** se la griglia trova di meglio, entra nella v2 con provenienza `griglia_locale`. È successo in 15 tratte su 35: in 10 di meno dello 0,15%, in 4 tra 0,74% e 4,3%.

**Larghezza dell'isola.** Per le ibride con l'ottimo finale entro 0,01 da D20, misuro l'isola a n\* fisso con passo 0,0001 su m\* ± 0,05. La larghezza è quella del tratto contiguo di punti fattibili che contiene m\*.

**Rivalutazione** con `fase1/uscite.jl`, gli stessi controlli della fase 1:
- stato `completed` e penalità 0 in 1024 tratte su 1024;
- costo uguale al candidato (scarto relativo ≤ 1e-9): 0 violazioni;
- costo ricostruito dalle grandezze: scarto massimo 2,2e-16, nessuna differenza nelle sostituzioni;
- somma delle voci: scarto 6,4e-16.

**Dataset v2** (`dati/dataset_doe_v2.csv`): stesse colonne e stessi `x_` del dataset di lavoro v1 (controllato), uscite `y_` e controlli `c_` nell'ottimo v2.

### Quante tratte cambiano

| | cambiano | > 0,1% | > 1% | > 5% | massimo |
|---|---:|---:|---:|---:|---:|
| v2 (v1 + P1–P4 + fase 2 + griglia) | 163 | 35 | 18 | 7 | 18,50% (801) |
| senza fase 2 (v1 + P1–P4, prima della griglia) | 140 | 30 | 16 | 6 | 18,38% (801) |

Il miglioramento mediano tra le 163 tratte è 0,02%: la maggior parte dei cambi è rumore del riferimento.

**Provenienza della v2.**

| provenienza | tutte le tratte | migliorate di oltre lo 0,1% | migliorate di oltre l'1% |
|---|---:|---:|---:|
| v1_nomad | 654 | — | — |
| v1_vecchio | 207 | — | — |
| fase2 | 55 | 8 | 1 |
| P3 | 48 | 8 | 4 |
| P1 | 29 | 4 | — |
| griglia_locale | 15 | 15 | 13 |
| P2 | 8 | — | — |
| P4 | 8 | — | — |

**Quale partenza trova la miglioria da sola**, prima della griglia:

| fonte | tratte oltre lo 0,1% | tratte oltre l'1% |
|---|---:|---:|
| P3 | 21 | 11 |
| P2 | 16 | 12 |
| P1 | 10 | 1 |
| P4 | 1 | 0 |
| punti della fase 2 | 22 | 7 |

P4, la batteria piccola, non serve: ci sono 7 ibride v1 con n < 0,1, le 4 migliorate le trovano altre fonti e le altre 3 (272, 816, 992) non migliorano.

**Il peso dei punti della fase 2 è piccolo.**
- Solo 5 tratte superano lo 0,1% grazie ai punti della fase 2: 240, 376, 386, 402 e 536. Solo due superano l'1%: 240 e 1008.
- In quelle due il punto della fase 2 ha solo indicato la zona; l'ottimo v2 l'ha trovato la griglia.
- Nelle 55 tratte con provenienza `fase2` il vantaggio sul migliore senza fase 2 è 0,01% in mediana e 0,28% al massimo.
- Contro la variante senza fase 2 le metriche cambiano di ≤ 0,01 punti in mediana e ≤ 0,03 al p95. Esempi: gb p69 secca 0,744% contro 0,753% in mediana; gb + 100 p95 2,26% contro 2,29%.

**Cambi di regime:** uno solo. La route 477 passa da ibrido (m 0,0301, n 0,947) a sola batteria (n 0,748), −5,58%. L'aveva già trovata la fase 2.

**Dove stanno le 35 tratte migliorate di oltre lo 0,1%:**

| posizione | tratte |
|---|---:|
| sola batteria | 15. Tutte tra 0,10% e 0,26%: n si sposta di 0,01–0,04 nella stessa valle |
| a sinistra di D20, entro 0,01 | 13. Tutte oltre l'1% |
| altrove | 7: route 240 (4,7%), 388 (3,0%), 211 (1,7%), 1008 (1,3%), 376, 80 e 536 |
| vicino a m_min | nessuna |

- **Route 240.** La v1 era a (0,50; 0,05); l'ottimo v2 è a (0,227; 0,526). Lungo m il costo scende in modo monotono e ripido fino al limite di SOC, con 6562 punti fattibili su 13 122 nella griglia. È una valle larga che nessuna delle due campagne ha seguito.
- **Route 1008:** stessa forma della 240.

**Isole a sinistra di D20** (13 tratte), con la larghezza in m a n\* fisso:

| route | m\* | n\* | isola in m | larghezza | fattibili nella griglia ±0,02 | miglioramento sulla v1 | provenienza |
|---|---:|---:|---|---:|---:|---:|---|
| 120 | 0,1136 | 0,7437 | 0,1136–0,1136 | 0,0001 | 376/6561 | 1,47% | griglia_locale |
| 262 | 0,1150 | 0,7244 | 0,1150–0,1150 | 0,0001 | 129/6561 | 4,55% | P3 |
| 654 | 0,1145 | 0,7660 | 0,1145–0,1145 | 0,0001 | 152/6561 | 2,56% | griglia_locale |
| 801 | 0,1111 | 0,9871 | 0,1111–0,1112 | 0,0002 | 727/5265 | 18,50% | griglia_locale |
| 86 | 0,1192 | 0,7189 | 0,1192–0,1195 | 0,0004 | 2/6561 | 4,87% | griglia_locale |
| 620 | 0,1107 | 0,7503 | 0,1107–0,1112 | 0,0006 | 139/6561 | 3,17% | griglia_locale |
| 259 | 0,1186 | 0,7286 | 0,1186–0,1195 | 0,0010 | 8/6561 | 7,23% | griglia_locale |
| 20 | 0,1161 | 0,7285 | 0,1161–0,1195 | 0,0035 | 174/6561 | 5,11% | griglia_locale |
| 939 | 0,1160 | 0,7475 | 0,1159–0,1195 | 0,0037 | 115/6561 | 5,11% | griglia_locale |
| 668 | 0,1157 | 0,6769 | 0,1157–0,1195 | 0,0039 | 190/6561 | 3,23% | P3 |
| 614 | 0,1151 | 0,7010 | 0,1151–0,1194 | 0,0044 | 100/6561 | 3,58% | P3 |
| 443 | 0,1146 | 0,7201 | 0,1144–0,1194 | 0,0051 | 139/6561 | 5,51% | P3 |
| 989 | 0,1095 | 0,7397 | 0,1095–0,1195 | 0,0101 | 657/6561 | 6,13% | griglia_locale |

Come leggere la tabella:
- **Forma dell'isola.** L'ottimo sta quasi sempre sul bordo sinistro: scendendo con m il costo cala fino al limite di SOC, e a destra l'isola finisce a D20 (0,1195).
- **Isole di 0,0001–0,0002.** Lì, a n fisso, è fattibile solo il punto ottimo: l'ottimo è un angolo tra due vincoli. In due dimensioni l'isola è più ampia; nella griglia ±0,02 sono fattibili tra 2 e 727 punti.
- **Perché le campagne le mancano:** sono strette in m (≤ 0,01) e attaccate a una discontinuità.

### Controlli in più sulla v2 (non la cambiano)

| controllo | risultato |
|---|---|
| Griglia su un campione casuale di 30 tratte non segnalate (`12_controllo_campione.jl`, seme 20261011) | Migliora 1 tratta su 30, dello 0,001%. Con 0 tratte su 30 oltre lo 0,1%, la quota di tratte ancora migliorabili oltre lo 0,1% è sotto il 10% con il 95% di confidenza (regola del tre) |
| Rifinitura gb p69 con budget 200, dal § 2 | Batte la v2 in 200 tratte (164 a sola batteria), ma di 0,0002% in mediana e 0,086% al massimo. Nessuna oltre lo 0,1%. È il pavimento numerico di NOMAD sulle valli piatte |

## 2. Riesecuzione della fase 2 sulla v2

**Stessa impostazione.**
- **Codice:** copiato in `fase2bis/` con i numeri 05–10. Cambiano solo il dataset (v2), le cartelle e il budget della rifinitura (50/100/200 invece di 20/50/100).
- **Fold di prova:** sono gli stessi della fase 2, stratificati sul regime v1 (`fold_esterni`; l'uguaglianza è controllata). Stratificando sul regime v2 la partizione sarebbe cambiata, perché la route 477 cambia regime.
- **Il resto:** stessi semi, griglie di iperparametri e CV interna. Durata: CV 55 minuti, simulazione 44 s, rifinitura 19 minuti, analisi circa 8 minuti ciascuna.

**Rete piccola, solo sul costo** (`comune.jl`, `adatta_nn`):
- **Struttura:** Flux 0.16.12; input e uscita (log del costo) standardizzati; 1 o 2 strati nascosti gelu.
- **Addestramento:** a lotto intero, Adam con passo 1e-3, decadimento dei pesi 1e-3.
- **Arresto anticipato:** su un fold interno, il 20% del training estratto con il seme. Pazienza 1000 epoche, al massimo 20 000; si tiene la rete con l'errore di validazione minimo.
- **Iperparametri:** strati ∈ {1, 2} × larghezza ∈ {16, 32}, scelti con la stessa CV interna a 3 fold degli altri modelli.
- **Ricetta:** attivazione, passo, decadimento e pazienza li ho scelti provandone 15. Le prove le ho fatte solo su una divisione 80/20 del training del fold 1 della ripetizione 1, mai sul fold di prova. Su quella divisione:
  - la rete stava tra 2,65% e 5,5% di errore mediano;
  - il processo gaussiano era all'1,25%;
  - la prima ricetta (tanh, passo 3e-3, decadimento 1e-4) dava 3,2–3,6%.
- **Scelte della CV interna:** sempre 2 strati, larghezza 32 in 18 fold su 25 (p69); arresto in mediana a ~4700 epoche.

### (a) Previsione secca, 5 ripetizioni × 1024 tratte

| modello | errore di regime | non fattibili | rimpianto mediana | rimpianto p95 |
|---|---:|---:|---:|---:|
| gb p69 | 1,3% | 55,8% | 0,75% | 6,3% |
| gb p66 | 1,8% | 59,2% | 0,92% | 11,1% |
| rf p69 | 1,5% | 56,6% | 1,03% | 10,3% |
| knn p69 | 9,1% | 65,2% | 1,36% | 36,2% |
| nn1 p69 | 12,3% | 62,2% | 1,71% | 39,9% |
| mediana+gb p69 | 1,3% | 62,9% | 1,25% | 54,0% |
| nulla | 38,6% | 62,5% | 57,4% | 95,0% |

L'ordine dei modelli è quello della fase 2.

**gb p69 per regime:**

| regime | non fattibili | rimpianto mediana | rimpianto p95 |
|---|---:|---:|---:|
| ibride | 71,6% | 2,52% | 6,9% |
| sola batteria | 30,7% | 0,44% | 1,45% |

**Cause della non fattibilità** (tutte le tratte): SOC 41,2%, massa 27,7%, D3 0.

### (b) Previsione gb p69 + NOMAD-PB, ripetizione 1, contro la v2

| budget | non fattibili | errore di regime | rimpianto mediana | p90 | p95 | max | fattibili entro 0,25% |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 (secca) | 57,0% | 1,4% | 0,665% | 4,16% | 5,83% | 17,8% | 6,9% |
| 50 | 0,1% | 1,0% | 0,361% | 5,03% | 8,09% | 33,7% | 43,7% |
| 100 | 0,1% | 0,6% | 0,121% | 1,12% | 2,29% | 13,5% | 66,1% |
| **200** | 0,1% | 0,6% | **0,018%** | 0,24% | **0,77%** | 11,1% | **90,4%** |
| campagna NOMAD-PB (972 valutazioni) | 0 | 0,1% | 0,000% | 0,05% | 0,11% | 32,7% (801) | 97,2% |
| campagna del vecchio ottimizzatore | 0 | 1,5% | 0,010% | 0,16% | 2,50% | 22,7% | 91,9% |
| riferimento v1 | 0 | 0,1% | 0,000% | 0,01% | 0,05% | 22,7% | 97,9% |

**Per regime, budget 200:**

| regime | rimpianto mediana | p95 | max |
|---|---:|---:|---:|
| ibride | 0,051% | 1,70% | 7,9% |
| sola batteria | 0,000% | 0,07% | 11,1% (errore di regime) |

**La coda a budget 200** (17 tratte oltre il 5%) ha due cause:
- **isole a sinistra di D20:** l'ottimo sta a m\* tra 0,10 e 0,119 e NOMAD finisce a destra della soglia, a m ≈ 0,15–0,20. Sono le route 20, 86, 259, 443, 939 e 989 (isole nuove della v2) e 109, 533 e 675 (isole già nella v1, a m\* ≈ 0,10–0,107);
- **regime a m_min:** la rifinitura finisce ibrida a m ≈ 0,03 quando la verità è sola batteria. Sono le route 134, 187, 580, 796 e 893.

Ci sono poi:
- la 240 e la 912, nella valle larga;
- la 491: la verità è ibrida a m = 0,0301, la rifinitura resta a sola batteria e non trova un punto fattibile.

Con budget 50 la rifinitura peggiora il p95 rispetto alla previsione secca (8,1% contro 5,8%). È lo stesso effetto della fase 2: la secca conta solo il 43% di punti fattibili, che sono i casi facili.

### (c) Costo €/km previsto direttamente, 5 ripetizioni

| caratteristiche | modello | errore mediano | p95 | max |
|---|---|---:|---:|---:|
| 69 | **processo gaussiano** | **1,09%** | **4,18%** | **9,6%** |
| 69 | rete | 2,19% | 7,36% | 27,5% |
| 69 | gb | 2,85% | 8,86% | 23,6% |
| 69 | rf | 4,43% | 13,3% | 24,2% |
| 66 | processo gaussiano | 1,68% | 6,02% | 31,5% |
| 66 | rete | 2,56% | 9,05% | 34,5% |
| 66 | gb | 3,22% | 10,6% | 30,4% |

Il massimo del processo gaussiano p69 scende dal 20% della v1 al 9,6%: la peggiore era la route 801, il cui riferimento v1 era sbagliato.

**Grandezze fisiche, gb p69, errore mediano:** H2 per viaggio 4,8%, vita FC 2,8%, energia di ricarica 2,1%. Con p66: 7,3%, 3,6%, 4,0%.

### Importanza, curva di apprendimento, categorie di errore (gb, costo con il processo gaussiano)

**Importanza** (`analisi_gb_p69.txt`, `analisi_gb_p66.txt`). Il quadro è lo stesso della fase 2.
- **Con le 69:** `din_E_trazione` domina regime, m\*, n\* delle ibride e costo. Per n\* delle ibride pesa anche `din_E_frenatura`. Per n\* delle sola batteria contano `din_durata` e L.
- **Con le 66:** contano L, `stops_sum_v2`, `tempo_limiti_ar_s`, la densità delle fermate e `vlim_mean`. La pendenza pesa poco.

**Curva di apprendimento** (ripetizione 1, stessi fold di prova):

| training | errore di regime p69 / p66 | non fattibili p69 | rimpianto p95 p69 / p66 | costo processo gaussiano mediana p69 / p66 |
|---:|---:|---:|---:|---:|
| 256 | 3,1% / 3,8% | 57,7% | 12,7% / 15,6% | 1,52% / 2,55% |
| 512 | 1,8% / 2,4% | 59,7% | 8,7% / 12,8% | 1,22% / 1,99% |
| 768 | 1,4% / 1,8% | 57,1% | 6,1% / 10,6% | 1,12% / 1,73% |
| 819 (tutto) | 1,2% / 2,0% | 55,4% | 6,3% / 12,1% | 1,10% / 1,70% |

Come in fase 2, con più dati migliorano regime, code e costo. La quota di non fattibili resta piatta.

**Categorie dell'ottimo vero** (gb p69, 5 ripetizioni, previsione secca):

| categoria | tratte | errore di regime | non fattibili | rimpianto mediana | p95 |
|---|---:|---:|---:|---:|---:|
| limite di massa | 417 | 0,0% | 77,6% | 2,81% | 7,1% |
| limite di SOC | 645 | 0,8% | 66,4% | 1,45% | 6,7% |
| lontano da entrambi i limiti | 337 | 2,6% | 32,8% | 0,52% | 4,3% |
| vicino a D20 | 29 (v1: 17) | 0,0% | 91,0% | 1,55% | 4,8% (v1: 23,7%) |
| vicino a m_min | 62 | 8,1% | 39,7% | 2,46% | 8,5% |
| vicino a un salto dei viaggi al giorno | 115 | 0,9% | 58,4% | 0,72% | 5,5% |

Vicino a D20 ci sono ora 29 tratte, 12 in più della v1: sono le nuove isole. Il p95 di quella categoria scende dal 23,7% al 4,8%: sulla v1 alcune "verità" vicino a D20 erano punti sbagliati.

## 3. Tabella v1 contro v2

Stessi fold, stesse impostazioni, ripetizione 1 per la rifinitura. Per la v1 il budget 200 non è stato fatto. Tabella completa in `risultati/confronto_v1_v2.md`.

| metrica | v1 | v2 |
|---|---:|---:|
| gb p69 secca: errore di regime | 1,50% | 1,35% |
| gb p69 secca: non fattibili | 54,5% | 55,8% |
| gb p69 secca: rimpianto mediana / p95 | 0,74% / 7,45% | 0,75% / 6,25% |
| gb p69 secca, ibride: rimpianto mediana / p95 | 2,72% / 8,65% | 2,52% / 6,93% |
| gb p69 secca, sola batteria: rimpianto mediana / p95 | 0,42% / 1,49% | 0,44% / 1,45% |
| gb p66 secca: errore di regime | 2,21% | 1,84% |
| gb p66 secca: rimpianto mediana / p95 | 0,84% / 11,98% | 0,92% / 11,08% |
| gb p69 + 50: rimpianto mediana / p95 / entro 0,25% | 0,37% / 7,77% / 43,6% | 0,36% / 8,09% / 43,7% |
| gb p69 + 100: rimpianto mediana / p95 / entro 0,25% | 0,12% / 1,79% / 65,9% | 0,12% / 2,29% / 66,1% |
| gb p69 + 100, ibride: rimpianto p95 | 2,48% | 2,87% |
| gb p69 + 100, sola batteria: rimpianto p95 | 0,10% | 0,13% |
| gb p69 + 200: rimpianto mediana / p95 / entro 0,25% | — | 0,018% / 0,77% / 90,4% |
| campagna NOMAD-PB: rimpianto p95 | 0,04% | 0,11% |
| campagna del vecchio ottimizzatore: rimpianto p95 | 1,03% | 2,50% |
| costo, processo gaussiano p69: mediana / p95 | 1,15% / 4,31% | 1,09% / 4,18% |
| costo, processo gaussiano p66: mediana / p95 | 1,70% / 6,06% | 1,68% / 6,02% |
| costo, rete p69: mediana / p95 | — | 2,19% / 7,36% |
| costo, rete p66: mediana / p95 | — | 2,56% / 9,05% |
| costo, gb p69: mediana / p95 | 2,84% / 9,07% | 2,85% / 8,86% |
| H2 per viaggio, gb p69: mediana | 4,90% | 4,81% |
| vita FC, gb p69: mediana | 3,14% | 2,75% |
| energia di ricarica, gb p69: mediana | 3,42% | 2,14% |

**Lettura.**
- Le metriche della previsione secca e del costo diretto restano uguali o migliorano un po'. Il riferimento più coerente aiuta i modelli: le uscite v2 sono "più lisce" nelle isole e nei casi corretti.
- La rifinitura a 100 valutazioni peggiora sul p95 (1,8% → 2,3%), e così le campagne. La v2 ha abbassato la verità proprio nelle tratte difficili, dove NOMAD con poche valutazioni non arriva.
- Le conclusioni della fase 2 non cambiano. Se la fase 3 usa la rifinitura, conviene il budget 200 invece di 100: costa due volte tanto, circa 3,5 s per tratta a 17 ms per valutazione, e porta il p95 da 2,3% a 0,8%.

## 4. File

**In `fase2bis/` (Drive):**
- **codice:**
  - `01_partenze.jl`, `02_candidati.jl`, `03_griglia.jl`, `04_v2.jl`;
  - da `05_cv.jl` a `10_metriche_b.jl`;
  - `11_confronto_v1_v2.jl`, `12_controllo_campione.jl`;
  - `comune.jl`, `simulatore.jl`;
  - Project/Manifest, con Flux 0.16.12 aggiunto preservando le versioni già fissate (EvoTrees, DecisionTree, NOMAD, Optim, CSV e DataFrames invariati);
- **`dati/`:** `ottimi_riferimento_v2.csv` (160 KB), `uscite_doe_v2.csv` (640 KB), `dataset_doe_v2.csv` (1,6 MB);
- **`risultati/`:** metriche, analisi, `candidati_v2.csv` (450 KB), `partenze.csv` (300 KB), `griglia_v2.csv`, `controlli_v2.txt`, `controllo_campione.csv`, `rifinitura_p69.csv` (320 KB), `confronto_v1_v2.{csv,md}`, log.

**Fuori da Drive, in `~/Documents/lavoro/ml_treno_dati/fase2bis/` (78 MB):**

| percorso | contenuto | dimensione |
|---|---|---:|
| `partenze/` | storie P1–P4, 1024 file | 29 MB |
| `griglia/` | punti delle griglie e delle isole | 21 MB |
| `sim_cv.csv` | | 13 MB |
| `cv/` | previsioni della CV | 11 MB |
| `rifinitura/` | | 4 MB |

## 5. Decisioni per te

1. **Riferimento per la fase 3 e per l'articolo.** Propongo la v2: le metriche sono al livello della v1, la verità è più corretta e ha una procedura sistematica da descrivere. Teniamo la v1 come confronto nel materiale supplementare?
2. **Rete neurale.** Propongo di chiuderla qui, come riga di confronto: con le 69 caratteristiche il processo gaussiano ha metà del suo errore mediano sul costo (1,09% contro 2,19%) e con le 66 un terzo in meno (1,68% contro 2,56%).
3. **Budget di rifinitura per la fase 3.** Propongo 200 invece di 100.
4. **Commit 3.** L'elenco è in `PROPOSTA_COMMIT.md`. Vuoi un commit 4 analogo per `fase2bis/`, escluso ciò che è già fuori da Drive?
5. **Punto 3, insieme di prova indipendente.** Aspetto il tuo ok per lanciare MATLAB. Prima verificherò se `matlab -batch` è disponibile; se non lo è, ti darò i comandi.
