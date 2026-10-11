# Fase 2: modelli

Data: 2026-10-10. Dati: `fase1/dati/dataset_doe.csv`, 1024 tratte DoE con 66 input approvati più le 3 `din_`. Il riferimento è congelato in `fase1/dati/ottimi_riferimento.csv`. Simulatore: train-powertrain `c47dc17`, sola lettura, modello `corretta`, `ConfigModello()` di default, andata e ritorno, 195 t.

**Le tratte reali non sono mai state lette in fase 2.** Nessuno script carica `dataset_reali*.csv` o `tratte_reali`: l'ho controllato con `grep`. Il loro test resta cieco per la fase 3.

## In breve

1. **Il regime si prevede bene:**
   - errore 1,5% con il boosting e le 69 caratteristiche, 2,2% con le 66 (5 ripetizioni × 1024 tratte);
   - gli errori stanno vicino a m_min: lì l'errore di regime sale al 9,5%.
2. **Il costo €/km si prevede direttamente bene.** Con il processo gaussiano e le 69 caratteristiche l'errore è dell'1,15% in mediana, 4,3% al p95 e 20% al massimo. Con le 66 è 1,7% / 6,1% / 35%. Senza simulatore: è già utile nel preconfiguratore.
3. **Il punto (m, n) previsto "secco" non basta: il 55–60% dei progetti è non fattibile.**
   - Non è un limite del modello, è la forma del problema: il 63% degli ottimi ha SOC finale < 0,2005 e il 41% è al limite di massa. Un errore piccolo su n (o su m) supera il vincolo.
   - Sui progetti fattibili il rimpianto è 0,74% in mediana e 7,4% al p95.
4. **Previsione + 100 valutazioni di NOMAD-PB:**

   | | non fattibili | rimpianto mediana | rimpianto p95 | entro lo 0,25% |
   |---|---:|---:|---:|---:|
   | tutte | 0,1% | **0,12%**, al livello del riferimento | 1,8% | 66% |
   | sola batteria | — | 0,009% | 0,10% | 97,5% |
   | ibride | — | 0,28% | 2,5% | — |

   La campagna (972 valutazioni) resta molto meglio sulle code: p95 0,04%. Partendo dalla mediana invece che dal modello, a 100 valutazioni il p95 è 4,1–5,0% (contro 1,8%); a 50 valutazioni il vantaggio del modello è più netto.
5. **Il riferimento congelato non è sempre l'ottimo.** In 104 tratte un punto trovato in fase 2 costa meno: in 22 di oltre lo 0,1%, in 7 di oltre l'1%, al massimo 18,5%. Ci sono anche un errore di regime nel riferimento e isole a sinistra di D20 mancate da entrambe le campagne (§ 6). Le metriche dei modelli cambiano poco se si usa il miglior noto.
6. **Le 3 `din_` migliorano tutti i modelli**, su tutte le metriche, e assorbono quasi tutta l'importanza. Con le sole 66 caratteristiche contano lunghezza, fermate (Σv² alle fermate, densità) e velocità media.
7. **Più tratte aiuterebbero le code** (p95 del rimpianto e del costo), non la quota di non fattibili.

## 1. Metodo

**Validazione.**
- **Partizione:** 5 fold, ripetuti 5 volte (seme 20261012 + ripetizione), stratificati per regime. Ogni riga è una tratta, quindi la divisione è già per tratta.
- **Iperparametri:** scelti con una CV interna a 3 fold sul solo training del fold, su una griglia piccola. Il criterio è l'errore di Brier per la classificazione e l'errore quadratico medio per la regressione.
- **Uso dei fold:** il fold di prova serve solo per le metriche.

**Catena del modello.** Per ogni famiglia:
1. un classificatore del regime, addestrato su tutte le tratte del training;
2. un regressore di m\*, sulle sole ibride;
3. due regressori di n\*, uno sulle ibride e uno sulle sola batteria (si usa quello del regime previsto);
4. un regressore del log del costo, su tutte.

Il punto previsto è:
- **regime:** ibrido se p ≥ 0,5;
- **m:** `clamp(m̂, 0,03, 1)` se ibrido, 0 altrimenti;
- **n:** `clamp(n̂, 0,005, 1)`.

| modello | regime | m, n | costo |
|---|---|---|---|
| nulla | classe maggioritaria (ibrido) | mediane del training | mediana |
| mediana+gb | boosting | mediane del training per regime previsto | — |
| nn1 | ottimo della tratta di training più vicina (caratteristiche standardizzate) | idem | idem |
| knn | k-NN, k ∈ {3, 5, 7, 10} | k-NN per regime | k-NN |
| rf | foresta casuale, DecisionTree.jl 0.12.4, 300 alberi; caratteristiche per nodo √p o p/3, foglia ≥ 1 o 5 | idem | idem |
| gb | boosting, EvoTrees.jl 0.19.0, eta 0,05, sottocampionamento 0,8, L2 = 1; profondità 3 o 5, 200 o 600 alberi | idem | idem |
| gp | — | — | processo gaussiano ARD, nucleo esponenziale quadratico più rumore, iperparametri a massima verosimiglianza marginale (Optim 2.3.2, gradiente analitico controllato con differenze finite) |

**Perché queste librerie:**
- **EvoTrees e DecisionTree:** sono in puro Julia, senza librerie binarie, deterministiche con il seme e veloci.
- **Processo gaussiano:** è scritto a mano in `comune.jl`, ~40 righe, per non dipendere da pacchetti poco mantenuti.

**Rete piccola: non l'ho addestrata.**
- Il punto debole del punto secco è strutturale (vincoli attivi), non di capacità: la quota di non fattibili non scende con il modello migliore né con più dati (§ 7).
- Sul costo il processo gaussiano batte già il boosting (1,15% contro 2,8% in mediana).
- Non vedo un margine evidente che una rete possa colmare. Se vuoi la provo sul costo e su n\*.

**Simulatore nel punto previsto:** `valuta_progetto`. "Non fattibile" vuol dire penalità > 0 o scartato:
- **SOC:** penalità 5000 (SOC < 0,2) o 3000 (scarica totale);
- **massa:** penalità 1000;
- **D3:** batteria sottodimensionata.

Il rimpianto è (costo nel punto − costo di riferimento) / costo di riferimento, sui soli progetti fattibili.

**Rifinitura** (`03_rifinitura.jl`).
- **Impostazioni:** NOMAD-PB con le stesse uscite e lo stesso seme di `ottimizza_nomad` del runner (NOMAD.jl 3.0.0, libNOMAD 4.5.1). Parte dal punto previsto della ripetizione 1, con limiti m ∈ [0, 1] (sotto 0,03 è sola batteria, quindi può cambiare regime) e n ∈ [0, 1].
- **Budget:** un lancio separato per ciascun budget (20, 50, 100). Il risultato è il miglior fattibile, come `_risultato`.
- **Scorciatoia scartata:** prendere "il migliore delle prime k valutazioni del lancio a 100" non coincide con un lancio a budget k, perché NOMAD cambia comportamento. Nel controllo il punto era diverso in 4 tratte su 12.

## 2. (a) Previsione secca

5 ripetizioni × 1024 tratte, cioè ogni tratta 5 volte. Tra parentesi il campo di variazione della mediana tra le ripetizioni. "Entro 0,25%" = progetti fattibili con rimpianto ≤ 0,25%, in percentuale di tutti. Tabelle complete, per regime e con le 66 caratteristiche, in `risultati/metriche.txt` e `metriche_a.csv`.

| modello (69 caratt.) | errore di regime | non fattibili (SOC / massa) | rimpianto mediana | p90 | p95 | max | entro 0,25% |
|---|---:|---:|---:|---:|---:|---:|---:|
| nulla | 38,5% | 63,7% (53,7 / 31,7) | 58,4% | 86,4% | 95,3% | 121% | 0% |
| mediana+gb | 1,5% | 63,0% (52,5 / 32,3) | 1,22% | 43,5% | 54,4% | 86% | 4,1% |
| nn1 | 12,4% | 62,1% (47,9 / 33,6) | 1,74% | 26,1% | 40,0% | 80% | 3,7% |
| knn | 9,3% | 65,3% (53,6 / 34,1) | 1,34% | 28,6% | 36,3% | 77% | 3,0% |
| rf | 1,6% | 55,8% (43,0 / 23,2) | 1,03% | 7,9% | 11,1% | 29% | 5,3% |
| **gb** | **1,5%** | **54,5%** (40,4 / 25,1) | **0,74%** [0,71–0,77] | **5,1%** | **7,4%** | 26% | **7,8%** |
| gb, 66 caratt. | 2,2% | 58,7% (45,0 / 27,3) | 0,84% | 8,2% | 12,0% | 61% | 5,3% |

D3 mai, altre cause mai.

**Per regime (gb, 69):**
- **ibride:** non fattibili 70,2%, rimpianto mediana 2,7%, p95 8,7%, errore di regime 1,0% (30 ibride previste a sola batteria su 3150);
- **sola batteria:** non fattibili 29,4%, rimpianto mediana 0,42%, p95 1,5%, errore di regime 2,4% (47 su 1970).

## 3. (b) Previsione + rifinitura NOMAD-PB

Ripetizione 1, 69 caratteristiche. Il budget 0 è la previsione secca della stessa ripetizione. File: `risultati/metriche_b_p69.txt`.

| partenza | budget | non fattibili | errore di regime | rimpianto mediana | p90 | p95 | max | entro 0,25% |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| gb | 0 | 55,6% | 1,3% | 0,74% | 5,5% | 7,3% | 21% | 7,8% |
| gb | 20 | 0,4% | 1,6% | 1,69% | 13,1% | 17,5% | 44% | 23,9% |
| gb | 50 | 0,2% | 1,0% | 0,37% | 4,9% | 7,8% | 30% | 43,6% |
| **gb** | **100** | **0,1%** | **0,6%** | **0,12%** | **0,88%** | **1,8%** | 18% | **65,9%** |
| mediana+gb | 50 / 100 | 0,6% / 0,3% | 0,9% / 0,8% | 0,53% / 0,13% | 9,1% / 1,8% | 13,7% / 4,1% | 58% / 52% | 39,7% / 61,7% |
| nulla | 50 / 100 | 0,5% / 0,2% | 2,3% / 1,6% | 0,72% / 0,15% | 10,2% / 2,0% | 15,4% / 5,0% | 67% / 67% | 30,1% / 59,8% |
| campagna NOMAD-PB (972 valutazioni) | — | 0 | 0 | 0,000% | 0,008% | 0,04% | 8,1% | 99,1% |
| campagna vecchio ottimizzatore | — | 0 | 1,4% | 0,002% | 0,11% | 1,0% | 13% | 94,0% |

**Per regime (gb + 100):**

| | rimpianto mediana | p95 | entro 0,25% |
|---|---:|---:|---:|
| sola batteria | 0,009% | 0,10% | 97,5% |
| ibride | 0,28% | 2,5% | 46% |

A 50 valutazioni la sola batteria è già a mediana 0,06% e p95 0,33%.

**Il rimpianto a budget 20 è più alto di quello della previsione secca.** Non è un peggioramento:
- quello secco si calcola solo sul 44% di progetti fattibili, cioè i più facili;
- a budget 20 i fattibili sono il 99,6%.

Il confronto corretto è la colonna "entro 0,25%": 7,8% → 23,9% → 43,6% → 65,9%.

**Costo di calcolo.** 100 valutazioni contro 972 (in media 89 fatte davvero, perché NOMAD si ferma prima) sono circa il 10% del tempo della campagna. Nella campagna 1024 una valutazione richiede in media 17 ms (16 914 s per 995 424 valutazioni, dal registro), quindi ~1,5 s per tratta contro ~17 s, più il caricamento.

## 4. (c) Costo €/km previsto direttamente

Tutte le 1024 tratte × 5 ripetizioni, |errore relativo|. File: `risultati/metriche_c.csv`.

| modello | 66: mediana / p95 / max | 69: mediana / p95 / max |
|---|---|---|
| mediana | 39% / 109% / 171% | uguale |
| nn1 | 15% / 64% / 180% | 14% / 54% / 161% |
| knn | 13% / 40% / 106% | 12% / 35% / 98% |
| rf | 5,2% / 15,9% / 31% | 4,5% / 13,3% / 25% |
| gb | 3,3% / 10,9% / 30% | 2,8% / 9,1% / 29% |
| **gp** | **1,70% / 6,1% / 35%** | **1,15% / 4,3% / 20%** |

**Per regime (gp, 69):**
- **ibride:** 1,27% / 4,5% / 20%;
- **sola batteria:** 0,99% / 4,2% / 7,7%.

La distorsione mediana è sotto lo 0,25%.

**Grandezze fisiche** (ripetizione 1; `risultati/metriche_fisiche.csv`; gb, 69 caratteristiche):

| grandezza | errore mediana | p95 |
|---|---:|---:|
| H2 per viaggio (ibride) | 4,9% | 23% |
| vita FC in ore (ibride) | 3,1% | 14% |
| energia di ricarica per viaggio (rf; escluse 2 ibride con < 10 kWh) | 2,7% | 23% |

Hanno code lunghe. Non le userei per ricostruire il costo: il costo diretto con il processo gaussiano è più preciso.

## 5. Con e senza le 3 `din_`

Le `din_` migliorano ogni modello: errore di regime, non fattibili, rimpianto e costo (tabelle sopra). Costano una dinamica del treno di riferimento per tratta, circa 5 ms, e dipendono solo da tratta e treno.

**Importanza per permutazione (gb, 69):**
- `din_E_trazione_ar_kWh` domina regime, m\*, n\* delle ibride e costo, ed è seguita da `L_km`;
- per n\* delle sola batteria conta di più `din_durata_ar_s`.

**Senza `din_` (gb, 66), per gruppi:**

| bersaglio | caratteristiche che contano di più |
|---|---|
| regime | lunghezza (+10,8), fermate (+7,9: `stops_sum_v2`, cioè Σ v² del limite alle fermate, energia cinetica persa a ogni sosta), `tempo_limiti_ar_s` (+3,0) |
| m\* (ibride) | fermate (`stops_sum_v2` +5,7), lunghezza (+3,1), velocità media |
| n\* (ibride) | `stops_sum_v2` (+12,3), lunghezza, numero di fermate |
| n\* (sola batteria) | lunghezza, `tempo_limiti_ar_s`, `slope_rms` |
| costo | densità di fermate, `stops_sum_v2`, velocità media, lunghezza |

La pendenza conta poco nel DoE. Questo potrebbe cambiare sulle tratte reali molto ripide come Sulmona, fuori dal dominio. File: `risultati/importanza*_gb_p66.csv` e `_p69.csv`.

Le caratteristiche correlate si dividono l'importanza; i gruppi permutati insieme sono la lettura più robusta.

## 6. Il riferimento non è sempre l'ottimo

In fase 2 il simulatore ha valutato 38 245 punti previsti distinti e 471 235 punti di rifinitura. Il miglior costo fattibile noto è sotto il riferimento congelato in **104 tratte**: in 22 di oltre lo 0,1%, in 7 di oltre l'1% (`risultati/riferimento_noto.csv`, `riferimento_migliorabile.csv`). I casi sopra lo 0,1%:

| tratta | riferimento (m\*, n\*, €/km) | trovato | differenza | tipo |
|---|---|---|---:|---|
| 801 | 0,695; 0,009; 2,361 (vecchio) | 0,111; 0,988; 1,925 | −18,5% | regione mancata (il riferimento ha quasi zero batteria) |
| 477 | 0,0301; 0,947; 1,840 (NOMAD) | **0** (sola batteria); 0,748; 1,737 | −5,6% | **regime sbagliato** nel riferimento, ibrido su m_min |
| 620, 388, 120 | m\* 0,125–0,141 | m 0,109–0,113 | −3,1%, −2,7%, −1,4% | isola a sinistra di D20 (0,1195), come Sulmona |
| 1008, 376 | m\* 0,58–0,63, n\* ≈ 0,05 | m 0,31–0,41, n 0,23–0,33 | −0,4%, −0,3% | altra regione |
| 536 | | | −0,1% | |
| 10 tratte a sola batteria | | n diverso di 0,01–0,04 | da −0,1% a −0,25% | il minimo in n non risolto fino in fondo |

- **Rispetto al miglior noto le metriche dei modelli cambiano di poco.** Per gb + 100: mediana 0,12%, p95 1,89% invece di 1,79% (`risultati/sensibilita_riferimento.txt`).
- **Sulle campagne l'effetto è forte:** la campagna NOMAD-PB ha rimpianto massimo 32,6%, contro l'8,1% rispetto al riferimento congelato, e 98,1% delle tratte entro lo 0,25%.
- **Non ho modificato il riferimento.** È una tua scelta: lo tengo congelato oppure creo un "riferimento v2" = miglior noto, con gli stessi controlli della fase 1, rivalutato e poi rieseguendo la fase 2.
- **Per l'articolo** è un risultato in sé: il surrogato più una rifinitura locale trova ottimi migliori di due ottimizzatori globali in alcune tratte, tipicamente sulle discontinuità D20 e m_min.

## 7. Curva di apprendimento

Ripetizione 1, stessi fold di prova, gb più processo gaussiano per il costo, training stratificato:

| training | errore di regime 69 / 66 | non fattibili 69 / 66 | rimpianto mediana 69 / 66 | rimpianto p95 69 / 66 | costo mediana 69 / 66 | costo p95 69 / 66 |
|---:|---|---|---|---|---|---|
| 256 | 3,0 / 3,6% | 58,8 / 59,7% | 0,92 / 1,10% | 13,2 / 18,4% | 1,64 / 2,46% | 6,1 / 10,1% |
| 512 | 2,0 / 2,9% | 57,6 / 59,1% | 0,78 / 0,97% | 8,9 / 13,6% | 1,27 / 1,95% | 5,4 / 7,4% |
| 768 | 1,4 / 2,1% | 56,3 / 58,9% | 0,72 / 0,88% | 7,1 / 12,1% | 1,13 / 1,74% | 4,4 / 6,0% |
| 819 (tutto il fold) | 1,2 / 2,1% | 55,4 / 60,1% | 0,68 / 0,80% | 6,7 / 12,4% | 1,13 / 1,77% | 4,3 / 6,0% |

- **Regime, rimpianto e costo** migliorano ancora da 512 a 768; tra 768 e 819 la differenza è piccola, perché il passo è piccolo.
- **Più tratte** migliorerebbero soprattutto le code (p95), più con le 66 che con le 69 caratteristiche.
- **La quota di non fattibili non scende:** non è un problema di dati.

## 8. Dove si concentrano gli errori

gb, 69 caratteristiche, previsione secca, 5 ripetizioni; categorie sull'ottimo vero (`risultati/errori_categorie_gb_p69.csv`).

| categoria | tratte | errore di regime | non fattibili (SOC / massa) | rimpianto mediana | p95 |
|---|---:|---:|---:|---:|---:|
| ottimo al limite di massa | 419 | 0% | 75% (51 / 45) | 3,1% | 8,6% |
| ottimo al limite di SOC | 648 | 1,1% | 65% (45 / 36) | 1,6% | 8,4% |
| lontano da entrambi i limiti | 337 | 2,4% | 33% (30 / 4) | 0,49% | 4,0% |
| vicino a D20 (\|m\* − 0,1195\| < 0,01) | 17 | 0% | **85%** | **5,0%** | **23,7%** |
| vicino a m_min (m\* < 0,04) | 63 | **9,5%** | 44% | 2,6% | 9,2% |
| vicino a un salto dei viaggi al giorno | 115 | 0,9% | 56% | 0,58% | 6,2% |

- **Le ibride al limite di massa sono le più difficili.** Lì l'ottimo sta all'incrocio dei due vincoli, nell'angolo della regione fattibile.
- **D20 e m_min:** sono le due discontinuità del modello, e lì sbagliano anche le campagne (§ 6).
- **Salti dei viaggi al giorno:** non peggiorano in modo evidente.

## 9. Insieme di prova indipendente (solo verifica, niente lanciato)

**Il generatore c'è, ma solo in parte in Julia.**
- **Design (Julia):** `ml_treno/scripts/09_generate_doe_sobol.jl <n> <start_index> <seed>` chiama `sample_doe_sobol` in `src/doe_generator.jl`: Sobol a 9 dimensioni con scramble e shift, seme 20260723. Gli intervalli dei fattori sono tutti in `DOEConfig`, righe 13-41.
  - Il metadata dice: "per estendere il DoE non modificare il seed e usare come `start_index` il valore 1025". Lo script controlla che il nuovo blocco prosegua la stessa sequenza.
  - Un seme diverso darebbe un DoE nuovo, sconsigliato da `DOE_TRATTE.md`. I nuovi punti Sobol con lo stesso seme sono la scelta corretta: stessi intervalli, punti nuovi.
- **Tratte (serve MATLAB):** le 1024 sono state costruite dal MATLAB (`build_doe_route` e funzioni collegate in `train-powertrain-matlab-optmz-doe-NEW`), esportate con `julia/test/parity/matlab/pt_esporta_tratte_doe.m` (`PT_DESIGN`, `PT_ROUTE`, `PT_USCITA`). Il generatore Julia (`Routes.tratta_da_generatore`) **non** riproduce le tratte MATLAB: il DIARIO, riga 265, cita la prima fermata della route 1 a 2491 m in MATLAB contro 2763 m in Julia. Per tratte compatibili con le 1024 serve quindi MATLAB, solo base, senza toolbox.

**Passi:**
1. design 1025-1280 con lo script 09;
2. esportazione MATLAB in coda a `tratte_doe_matlab/`, con manifest e sha256;
3. controllo come `verifica_tratte_1024.jl`.

Attenzione: l'esportazione scrive dentro train-powertrain (`tratte_doe_matlab/`, `data_doe/`). Per non toccare il repo si può usare `PT_USCITA` verso una cartella esterna e leggerla con `leggi_tratte_materializzate`.

**Costo dell'ottimizzazione di 256 tratte con NOMAD-PB a 8 processi.**
- **Riferimento:** la campagna 1024 ha fatto 995 424 valutazioni in 3608 s, cioè 1 h. Il tempo per tratta cresce con L: 3 s sotto i 25 km, 45 s tra 175 e 200 km, mediana 11 s, massimo 338 s.
- **Stima:** **9–15 minuti**, più fino a ~5 minuti di coda per una tratta lunga.
- **Con il vecchio ottimizzatore** (migliore dei due, come il riferimento): probabilmente un tempo simile, con ~1100 valutazioni per tratta in media contro 972; non l'ho misurato.
- **Visti i casi del § 6,** valuterei anche una rifinitura NOMAD-PB da 100 valutazioni partendo dalla previsione: costa poco e migliora il riferimento.

`conclusi.csv` riporta in `tempo_s` la durata dell'ultima valutazione, non della tratta: il tempo per tratta va sommato da `registro.csv`.

## 10. File e comandi

Da `ml_treno/fase2` (ambiente `Project.toml`: TrainPowertrain in sviluppo, CSV, DataFrames, EvoTrees, DecisionTree, Optim, NOMAD 3.0.0 / NOMAD_jll 4.5.1):

| comando | che cosa | tempo |
|---|---|---|
| `julia -t 8 --project=. 01_cv.jl` | previsioni in CV → `risultati/cv/` | ~25 min |
| `julia -t 8 --project=. 02_simula.jl` | simulatore nei punti previsti, metriche (a) e (c) | ~2 min |
| `julia -t 1 --project=. 03_rifinitura.jl p69 gb mediana+gb nulla` | rifinitura NOMAD-PB, 8 processi | ~36 min |
| `julia --project=. 06_metriche_b.jl p69` | metriche (b) | secondi |
| `julia -t 8 --project=. 04_analisi.jl gb p69 gp` (e `gb p66 gp`) | importanza, curva di apprendimento, categorie | ~5 min ciascuno |
| `julia --project=. 05_fisiche.jl` | grandezze fisiche | secondi |
| `julia --project=. 07_riferimento_noto.jl` | sensibilità al riferimento | secondi |

**Codice:** `comune.jl` (dati, fold, modelli, CV interna, processo gaussiano) e `simulatore.jl` (valutazione con cache).

**Spazio:**
- `fase2/risultati/` occupa 24 MB; il file più grande è `sim_cv.csv`, 13 MB.
- I file per tratta della rifinitura (~3000 file per partenza) sono fuori da Drive, in `/Users/kairos/Documents/lavoro/ml_treno_dati/fase2/rifinitura/`. Lì c'è anche `rifinitura_prefisso_scartata/`, il primo tentativo con la scorciatoia del prefisso, da non usare.

## 11. Git

La proposta dei due commit è in `ml_treno/PROPOSTA_COMMIT.md`. Nessun commit fatto.

## Decisioni per te

1. **Riferimento:** lo teniamo congelato, oppure lo aggiorniamo al miglior noto (§ 6) e rieseguiamo la fase 2? L'aggiornamento cambia il regime di 1 tratta (477) e il costo di 22 tratte di oltre lo 0,1%.
2. **Modello per la fase 3:**
   - boosting a 69 caratteristiche per regime e (m, n), con rifinitura NOMAD-PB a 100 valutazioni;
   - processo gaussiano a 69 caratteristiche per il costo diretto;
   - le stesse catene a 66 caratteristiche come confronto.

   Le `din_` richiedono la dinamica del simulatore sulla tratta reale, ma sono un calcolo da 5 ms. Va bene?
3. **Insieme di prova indipendente:** 256 tratte nuove, Sobol 1025-1280. Servono MATLAB per l'esportazione e circa 15–30 minuti di ottimizzazione, se si prende il migliore di NOMAD-PB e vecchio ottimizzatore.
4. **Rete:** non l'ho addestrata (§ 1). Se la vuoi, la provo sul costo e su n\*.
