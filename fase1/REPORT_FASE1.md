# Fase 1: esplorazione e dataset

Data: 2026-10-10. Simulatore: train-powertrain, branch `feat/align-matlab-doe`, commit `c47dc17` (valutatore identico a `048c268`, codice della campagna del vecchio ottimizzatore: tra i due cambiano solo `OttimizzatoreMN.jl`, `Campagna.jl` e `TrainPowertrain.jl`). Il repo non è stato modificato (`git status` invariato). Nessun addestramento.

## Come si rifà

Da `ml_treno/fase1` (ambiente `Project.toml` con TrainPowertrain in sviluppo dal suo percorso):

| passo | comando | tempo |
|---|---|---|
| ottimizzazione delle tratte reali | `zsh 03_tratte_reali.sh` (runner di train-powertrain, due ottimizzatori) | ~40 s |
| c, d | `julia -t 8 --project=. 01_ottimi_e_uscite.jl` | ~30 s |
| b, f (dominio) | `julia -t 8 --project=. 02_caratteristiche.jl` | ~30 s |
| f (verità) | `julia --project=. 03_tratte_reali.jl` | ~20 s |
| controllo del verso | `julia -t 8 --project=. 04_inversione.jl` | ~20 s |
| e | `julia --project=. 05_dataset.jl` | ~15 s |

Codice: `caratteristiche.jl` (input), `uscite.jl` (uscite e costo ricostruito). Risultati in `dati/`, scheda in `SCHEDA_DATASET.md`.

**File fuori da Drive e da git:** le due campagne sulle tratte reali (registri completi, 14 MB) sono in `/Users/kairos/Documents/lavoro/ml_treno_dati/`. Tutto il resto è piccolo (3,6 MB in `dati/`).

## a) ml_treno

- **Repo git:** sì. Un solo commit (`a009383`, 16/04), remote `github.com/deltadidirac30/ml-treno`. Molte modifiche mai committate: script 07-09, `src/doe_generator.jl`, analisi DoE. `CLAUDE.md` è vuoto.
- **Cosa c'è:**
  - pipeline 01-06: Excel MATLAB → profili sintetici da 6 modelli di tratta → 69 caratteristiche → MLP Flux (128-64-32) → 4 uscite del simulatore (H2, SOC finale, sostituzioni FC e batteria). 3126 campioni da sensitività a un fattore alla volta;
  - generatore DoE Sobol (07-09, `DOE_TRATTE.md`, `METODOLOGIA_DOE_TRATTE_FITTIZIE.md`): ha prodotto il design da cui il MATLAB ha generato le 1024 tratte;
  - `analisi_doe_matlab/`: Spearman e PRCC in MATLAB.
- **Riusabile:**
  - `src/features.jl`, usato così com'è con `include`;
  - i due documenti sul DoE, per la sezione metodi.
- **Da non riusare:** la rete, l'addestramento e l'ingestione degli Excel. L'obiettivo e le uscite sono cambiati.

## b) Caratteristiche della tratta

**Verifica.** `extract_features` usa solo pendenza metro per metro, limiti, fermate e L, più `P_nom_fc` e `C_batt`. Queste due sono variabili di progetto (ora uscite) e le ho tolte: restano 67. Nessun parametro del generatore entra nel calcolo. Le calcolo dalla rappresentazione del simulatore (`PrecalcoloTratta(cp, "andata")`), la stessa per le tratte DoE e per quelle reali. Per le reali la pendenza viene dall'altimetria interpolata, come nel simulatore.

**Controllo con i fattori del design** (solo verifica): L, numero di fermate, v_max e numero di limiti coincidono in 1024/1024. La pendenza media differisce di al più 1e-3 ‰.

**Tutte e 67 si calcolano per le tratte reali.** Ci sono però tre avvertenze:
1. **Calabria è piatta nei dati:** quota 0 in tutti i 17 756 punti di `Calabria_altimetria.txt` (da `variazione_di_quota_CL_RC.txt`), un solo limite a 130 km/h. Il simulatore la vede così. **Va confermato che sia voluto.**
2. **Risoluzione del profilo.** Nel DoE i tratti a pendenza costante sono lunghi almeno 0,5 km (mediana 1,5). Nelle reali sono di 0,08 km (Canavese), 0,30 (Firenze) e 0,42 (Sulmona). Le caratteristiche sensibili alla risoluzione possono spostarsi anche a parità di "forma" della tratta: `slope_sign_changes_per_km`, `slope_max`/`slope_min`, le deviazioni standard.
3. **Firenze e Firenze-BRoute sono identiche** (README di `tratte_reali`). Le tratte reali di test distinte sono quindi 4.

**Ridondanze** (identità esatte sulle 1024):

| caratteristica | è uguale a | proposta |
|---|---|---|
| `stops_sum_v2_segweighted` | `stops_sum_v2` (identica al bit) | togliere |
| `slope_int_abs` | `slope_int_pos + slope_int_neg` | togliere |
| `stops_spacing_mean` | `L/(n_fermate+1)` | togliere |
| `cross_int_p_v` | `cross_mean_p_v × L` | togliere |
| `vlim_frac_low + mid + high` | 1 | tenere (composizione) |

Fortemente correlate, ma non identiche: `slope_std_pos` e `slope_std_sq_pos` (Spearman 0,99).

**Il verso conta, e le caratteristiche che ne dipendono vanno tenute.** All'inizio pensavo il contrario: in andata e ritorno la tratta si percorre nei due versi. Prima di proporre di togliere le caratteristiche che dipendono dal verso l'ho verificato (`04_inversione.jl`): ho invertito ogni tratta DoE e l'ho rivalutata nel suo ottimo.
- Solo 401 su 1024 restano fattibili. Le altre prendono penalità di SOC finale (anche 0,2 → 0,004) e di massa.
- Sulle fattibili il costo cambia fino all'8,5% (p95 1,5%), l'H2 fino al 20%.

Il motivo è che l'ordine salita/discesa cambia la traiettoria del SOC, che è limitata. Quindi salita e discesa separate, `bin_p_k` e così via portano informazione.

**Proposta di insieme di input:**
- le 67 meno i 4 duplicati = 63;
- 3 nuove dal solo profilo:
  - `n_fermate`;
  - `dislivello_m` (quota massima − minima, legata all'energia da accumulare);
  - `tempo_limiti_ar_s` (durata minima ai limiti con le soste, legata a viaggi al giorno e km all'anno);
- in totale **66**.

Facoltative, **3 caratteristiche `din_`** da UNA dinamica del treno di riferimento (durata A/R, energia di trazione e di frenatura alle ruote). Dipendono solo dalla tratta, ma richiedono la dinamica del simulatore (~5 ms). Propongo di confrontare in fase 2 il modello con e senza.

## c) Ottimi di riferimento

**La cartella del vecchio ottimizzatore non c'è.** Delle due cartelle che mi hai indicato:
- `campagne/2026-10-08_ottimizza_nomad_corretta_ar_1024tratte` è stata rinominata `campagne/2026-10-08_ottimizza_ar_1024tratte` (lo dicono `config.txt` e `comando.txt`);
- `campagne/2026-10-08_ottimizza_corretta_ar_1024tratte` non esiste più, né sul disco né sul Drive condiviso.

I suoi ottimi sono in `analisi/2026-10-08_confronto_campagne_f/confronto_ottimi.csv`, colonne `m_N, n_N, costo_N`, **a 12 cifre**. Li ho rivalutati entrambi e ho preso il costo rivalutato minore (`dati/ottimi_riferimento.csv`, colonna `provenienza`).

| | tratte |
|---|---:|
| riferimento da NOMAD-PB / dal vecchio / stesso costo al bit | 687 / 251 / 86 |
| NOMAD-PB migliore / peggiore di oltre lo 0,1% | **113 / 23** |
| regime: ibride / sola batteria | **630 / 394** |
| cambio di regime tra le due campagne | 14 |

## d) Uscite nell'ottimo

Le ho estratte con una valutazione per tratta (`valuta_progetto`, `config` di default = `config.txt`, più `trace`). Elenco completo, unità e statistiche in `SCHEDA_DATASET.md`.

**Verifica del costo:**
- NOMAD-PB: identico al bit in 1024 su 1024;
- vecchio: scarto relativo massimo 3,9e-12 (punto e costo a 12 cifre);
- tutte le tratte sono `completed` con penalità 0;
- **il costo ricostruito dalle sole grandezze estratte** (`costo_ricostruito`, stesse formule di `funzione_costo_ga`) coincide fino a 2e-16, con le stesse sostituzioni. Le grandezze bastano quindi per ricostruire il costo in fase 2.

**Si legge tutto senza modificare il simulatore:**
- **Vita della batteria continua:** non è in `cost_details` né in `diagnostica`; si legge solo dalla traccia (`trace["life_batt"]`).
- **Tasso di degrado FC orario:** non è un campo, ma si ricava esattamente: `dV_fine_vita / vita_FC_ore`, perdita di cella in µV/h con K e f.
- **Durata del viaggio:** quella del costo è `length(SOC_batt)` = passi + 1, mentre la vita FC in ore usa i passi. La differenza è di 1 s e la riporto com'è.

**Fatti utili per la fase 2:**
- **Gli ottimi stanno sui vincoli:**
  - SOC finale < 0,2005 in 648 su 1024 (516 delle 630 ibride);
  - massa del sistema di propulsione ≥ 99,9% del limite in 419.

  Un piccolo errore su (m, n) porterà spesso a progetti non fattibili: la percentuale di punti non fattibili sarà una metrica importante.
- **Gradini:** viaggi al giorno interi (da 1 a 29), sostituzioni intere (FC da 2 a 13, batteria da 0 a 11).
- **Tetto di 25 000 h e D15:**
  - il tetto non è mai attivo: vita FC tra 5037 e 24 791 h;
  - D15 si applica a 227 tratte e la sostituzione salta in 2.
- **m\* nelle ibride:** tra 0,0301 e 0,695, mai esattamente 0,03.

## e) Dataset

`dati/dataset_doe.csv` (1024 × 124) e `dati/dataset_reali.csv` (5 × 124). Le colonne sono:
- `tratta` e `provenienza`;
- 69 input `x_` (63 + 3 nuove + 3 `din_`) più i 4 duplicati, con la raccomandazione nella scheda;
- 45 uscite `y_`;
- 4 controlli `c_`.

## f) Tratte reali

**Dominio** (`dati/dominio_reali.csv`, `dati/dominio_reali_vicino.csv`):

| tratta | caratteristiche fuori dall'intervallo DoE | distanza dal vicino DoE più prossimo, percentile delle distanze tra DoE (66 input) |
|---|---:|---:|
| Calabria | 0 | 15 |
| Canavese | 0 | 90 |
| Firenze (= Firenze-BRoute) | 0 | 97 |
| **Sulmona-Carpinone** | **12** | **oltre il massimo** (15,4 contro 9,3) |

- **Sulmona-Carpinone è fuori dal dominio.** Le pendenze sono molto più forti e variabili del DoE:

  | caratteristica | Sulmona | massimo DoE | fuori di |
  |---|---:|---:|---:|
  | `slope_std_all` | 19,4‰ | 8,0‰ | 142% dell'intervallo |
  | `slope_mean_pos` | 21,9‰ | 12,1‰ | 81% |
  | `slope_rms` | 19,5‰ | 12,6‰ | 56% |

  Fuori dall'intervallo ci sono anche `slope_mean_neg`, `cross_var_p_v` e quattro `bin_p`. Lì il surrogato estrapola.
- **Firenze e Canavese** sono dentro gli intervalli carattere per carattere, ma ai margini della nuvola DoE.

**Ottimi** (runner, due ottimizzatori, poi il migliore rivalutato; costi identici al bit a quelli del runner):

| tratta | provenienza | regime | m\* | n\* | costo €/km | scarto dell'altro | note |
|---|---|---|---:|---:|---:|---:|---|
| Calabria | NOMAD-PB | ibrido | 0,3221 | 0,7652 | 3,9557 | 0,003% | |
| Canavese | vecchio | sola batteria | 0 | 0,6821 | 2,8299 | 0,0001% | |
| Firenze | NOMAD-PB | ibrido | 0,0301 | 0,8725 | 2,3654 | 0,07% | m\* a ridosso di m_min = 0,03 |
| Firenze-BRoute | NOMAD-PB | ibrido | 0,0301 | 0,8725 | 2,3654 | 0,07% | identica a Firenze |
| Sulmona-Carpinone | NOMAD-PB | ibrido | 0,1133 | 0,6181 | 3,6034 | **4,6%** | fuori dominio |

Su Sulmona-Carpinone i due ottimizzatori differiscono del 4,6%. La verità è il migliore dei due, ma non è garantito che sia l'ottimo globale. Se vuoi una verità più solida, posso fare una verifica a forza bruta come in `analisi/2026-10-11_verifica_nomad` (griglia fitta più rifinitura): pochi minuti.

## Decisioni per te

1. **Calabria piatta:** è voluto?
2. **Insieme di input:** va bene la proposta (66, più 3 `din_` da confrontare in fase 2)?
3. **Sulmona-Carpinone:** verifica a forza bruta dell'ottimo prima del test finale?

## Aggiornamento dopo le decisioni del 10/10

**Decisioni applicate.**
1. **Calabria** resta nel test con `semplificata = true`, colonna in `ottimi_reali.csv`, `uscite_reali.csv` e `dataset_reali*.csv`. Nel dataset DoE vale `false`. I suoi risultati si riportano sempre a parte.
2. **Input approvati: 66, più le 3 `din_` come variante.**
   - `dati/dataset_doe.csv` e `dati/dataset_reali.csv` sono i file di lavoro: 69 colonne `x_`, senza i 4 duplicati.
   - I duplicati restano solo in `dati/dataset_doe_completo.csv` e `dati/dataset_reali_completo.csv`.
3. **Forza bruta sulle 4 tratte reali distinte** (`06_forza_bruta.jl`). È la `verita` di `analisi/2026-10-11_verifica_nomad/verifica_c.jl`, ricopiata con le stesse chiamate a `OttimizzatoreMN`: griglia m = 0:0,01:1 più m_log e n = 0:0,01:1, rifinitura con pattern e confine da 5 semi, sola batteria migliorata. Ho aggiunto `07_griglia_locale.jl`, una griglia a passo 0,0005 attorno al miglior punto noto (m\* ± 0,01, n\* ± 0,02): la rifinitura della forza bruta non parte dall'ottimo di NOMAD-PB.

| tratta | forza bruta: costo €/km (valutazioni) | verità | scarto della forza bruta | griglia locale (punti, fattibili) | sola batteria: fattibili tra i punti m = 0 della forza bruta |
|---|---|---:|---:|---|---|
| Sulmona-Carpinone | 3,77034 (11 724) | 3,60344 (NOMAD-PB) | **+4,63%** | 3240, 193: niente di meglio | 0 su 104 |
| Calabria | 3,95588 (12 636) | 3,95574 (NOMAD-PB) | +0,0035% | 3321, 768: niente di meglio | 0 su 104 |
| Firenze | 2,36712 (10 284) | 2,36542 (NOMAD-PB) | +0,072% | 1701, 909: niente di meglio | **0 su 151** |
| Canavese | 2,82990 (10 184) | 2,82990 (vecchio = forza bruta) | 0 | 81, 41: niente di meglio | 204 su 300 |

- **La verità non cambia.** La forza bruta non trova niente di meglio, e neanche la griglia locale attorno all'ottimo.
- **Sulmona-Carpinone:** la forza bruta trova lo stesso punto del vecchio ottimizzatore (m = 0,1469). L'ottimo di NOMAD-PB (m = 0,1133) è in un'isola stretta a sinistra della soglia D20 (0,1195): nell'intorno sono fattibili 193 punti su 3240, e la griglia a passo 0,01 non la vede. È il caso tipico già descritto nelle verifiche (tratte 253 e 340).
- **Firenze:** nessun progetto a sola batteria è fattibile (0 su 151 punti con m = 0). Il regime ibrido con m\* = 0,0301, a ridosso di m_min, non è quindi ambiguo.
- I file sono `dati/forza_bruta_reali.csv`, `dati/griglia_locale_reali.csv` e `dati/controlli_forza_bruta.txt`. Le storie complete sono in `~/Documents/lavoro/ml_treno_dati/forza_bruta_reali/`. `ottimi_reali.csv` ha in più le colonne della forza bruta, `guadagno_forza_bruta_pct` (0 su tutte) e lo scarto di ciascun metodo.

Comandi in più: `julia -t 4 --project=. 06_forza_bruta.jl` (~4 min), `julia -t 8 --project=. 07_griglia_locale.jl` (~1 min), poi di nuovo `03_tratte_reali.jl` e `05_dataset.jl`.
