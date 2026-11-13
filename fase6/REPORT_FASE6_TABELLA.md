# Fase 6: la tabella di addestramento (passo 2 del surrogato)

13/11/2026. Nessun addestramento. Dati: campagna P9_D28_16384 (fase 4) e le 66 caratteristiche (fase 5). Julia 1.12.5, 8 thread.

## In breve

- **Una riga per caso simulato:** 4 718 523 righe = 16384 tratte × 288 coppie, meno le 69 righe in errore del simulatore (route 2366 e 14664).
- **Ogni riga contiene:**
  - le 66 caratteristiche della tratta, m e n (gli ingressi);
  - le 9 grandezze `y_` da imparare;
  - l'esito vero e il costo vero, che servono ai passi successivi.
- **Divisione per tratta**, sui 16 gruppi Sobol da 1024 route, con seme 20261113:

  | insieme | gruppi | tratte | righe | file |
  |---|---|---:|---:|---:|
  | addestramento | 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14 | 12 288 | 3 538 939 | 473 MiB |
  | validazione | 7, 12 | 2048 | 589 824 | 79 MiB |
  | test | 15, 16 | 2048 | 589 760 | 79 MiB |

- **Controlli superati:**
  - nessuna tratta in due insiemi;
  - ogni (tratta, coppia) una volta sola;
  - caratteristiche uguali al bit a `caratteristiche.arrow`;
  - NaN e Inf solo dove previsto;
  - i tre insiemi si somigliano (sotto).
- **Regola D3 a posteriori:** "C-rate di scarica > 20 → scartato" ritrova il 99,56% degli scarti D3 in ogni insieme, e non scarta mai un caso completato.

## Come si rifà

Da `ml_treno`, con l'ambiente di `fase6` (quello della fase 5 più Tables):

```zsh
L=~/Documents/lavoro/ml_treno_dati/fase6_log; mkdir -p $L
julia -t 8 --project=fase6 fase6/01_tabella.jl > $L/log_01.txt 2>&1     # ≈ 30 s
/bin/cp $L/log_01.txt $L/01_*.txt $L/01_*.csv fase6/risultati/
```

## Dove sono i file e come si leggono

In `~/Documents/lavoro/ml_treno_dati/P9_D28_16384/tabella/` (fuori da Drive e dai repo) ci sono `addestramento.arrow`, `validazione.arrow` e `test.arrow`. Sono compressi zstd, con un blocco interno per gruppo Sobol. Caricato in memoria, l'insieme di addestramento occupa circa 2,5 GiB.

```julia
using Arrow
t = Arrow.Table(expanduser("~/Documents/lavoro/ml_treno_dati/P9_D28_16384/tabella/addestramento.arrow"))
t.x_L_km, t.m, t.n, t.y_durata_viaggio_s, t.d3     # colonne
```

## Colonne

| colonne | tipo | contenuto |
|---|---|---|
| `tratta`, `coppia` | Int32, Int16 | route_id e indice della coppia in `coppie.arrow` |
| `gruppo`, `insieme` | Int8 | gruppo Sobol (1–16); 1 addestramento, 2 validazione, 3 test |
| `segnalata` | Int8 | 0 no; 1 route con righe in errore D29 (2366 nell'addestramento, 14664 nel test; restano le altre righe); 2 route 13258, oltre 12 h con i treni più pesanti (addestramento) |
| `m`, `n` | Float64 | la coppia |
| `x_…` (66) | Float64 | le caratteristiche della tratta, uguali per le 288 righe della tratta |
| `y_durata_viaggio_s`, `y_massa_serbatoio_kg`, `y_H2_cons_kg`, `y_SOC_end`, `y_scarica_s`, `y_vita_batt_cicli_viaggi`, `y_vita_FC_viaggi`, `y_vita_FC_f1_ore` | Float64 | le grandezze da imparare (fase 4, §3.3) |
| `y_C_rate_scarica_max` | Float64 | C-rate massimo di scarica, per la regola D3 a posteriori |
| `stato`, `d3` | Int8, Bool | 1 completed, 2 rejected (D3); `d3` = rejected |
| `tipo_esito`, `fattibile` | Int8, Bool | 1 fattibile, 2 piccola, 3 pesante, 4 mista; `fattibile` = completed senza penalità |
| `D28` | Bool | storage non convergente |
| `SOC_end_ricavato` | Bool | true nei rejected: SOC_end = 0,2 − `vincolo_soc_pt`/100 (sulle completed la formula ridà la colonna entro 2,2·10⁻¹⁶) |
| `costo`, `total_cost_EUR_km` | Float64 | costo vero con e senza penalità (per il passo "dal surrogato al costo"; non si imparano) |

**NaN e Inf, come attesi:**
- `y_H2_cons_kg` è NaN nei 98 089 rejected: il registro non lo salva per gli scartati, quindi si impara solo sui completati;
- le vite FC sono +Inf a m = 0 (sola batteria), anche in 32 755 rejected a m = 0;
- nient'altro.

## I tre insiemi si somigliano?

| | completed | rejected D3 | fattibili | D28 | tratte con la migliore a sola batteria |
|---|---:|---:|---:|---:|---:|
| addestramento | 97,92% | 2,08% | 42,67% | 0,325% | 25,8% |
| validazione | 97,92% | 2,08% | 43,03% | 0,358% | 25,7% |
| test | 97,92% | 2,08% | 42,43% | 0,318% | 24,9% |

**Caratteristiche.** Per ognuna delle 66 ho confrontato la distribuzione tra le tratte di validazione (o di test) e quelle di addestramento, con la distanza di Kolmogorov-Smirnov.
- La differenza massima è 0,029 in validazione (`x_stops_std_v`) e 0,024 nel test.
- Sono tutte sotto 0,039, la soglia oltre la quale due campioni casuali di queste dimensioni differirebbero solo nell'1% dei casi.
- Le mediane di lunghezza, pendenza, fermate e velocità media coincidono quasi.

**Grandezze da imparare** (righe completed): distanze KS tra 0,0005 e 0,012, mediane quasi uguali. Dettagli in `risultati/01_confronto_gruppi.csv`.

## Note

- **Tratte segnalate.** Le route 2366 e 13258 sono nell'addestramento, la 14664 nel test. Hanno solo la colonna `segnalata`: escluderle o no si decide quando si addestra.
- **D3: classificatore o regola a posteriori.** La tabella tiene sia l'esito vero sia il C-rate, quindi la scelta resta aperta. Con la regola sfuggono 432 scarti su 98 089 (lo 0,009% delle righe): quelli dovuti alla potenza oltre il massimo fisico o ai cicli di dimensionamento.
