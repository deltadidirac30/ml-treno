# Fase 9: dal surrogato al costo (passo 5a)

16/11/2026. Modelli boosting delle fasi 7 (durata, modello E) e 8 (le altre 7 grandezze). Validazione: 2048 tratte, 589 824 casi. Nessuna simulazione. Julia 1.12.5, EvoTrees 0.19.0, TrainPowertrain `7c9115a`, 8 thread.

## In breve

**Il banco di prova** (`comune.jl`, funzione `valuta`). Dalle 8 grandezze di un caso, vere o previste, calcola con le regole del simulatore:
- le taglie esatte da m e n;
- viaggi al giorno, massa di propulsione, energia di ricarica;
- i quattro vincoli (D3, massa, SOC, scarica) e la fattibilità;
- il costo, con `costo_da_grandezze`.

**Collaudo:** con le grandezze vere ridà il simulatore.
- La fattibilità è uguale in 589 824 casi su 589 824.
- Il costo è uguale al bit in 546 898 casi su 577 569 completati. Gli altri differiscono al più di 5·10⁻¹⁶ relativo, perché la vita della FC passa per `vita_FC_f1_ore`.

**Il surrogato** (boosting, D3 dalla regola C-rate > 20):

| | risultato |
|---|---|
| fattibilità giusta | **98,1%** dei casi |
| fattibili scartati per errore | 6780 su 253 798 (2,7%) |
| non fattibili promossi per errore | 4291 su 336 026 (1,3%) |
| casi detti fattibili che lo sono davvero | 98,3% |
| errore del costo, casi davvero fattibili: mediana / p95 / p99 | **2,4% / 9,9% / 17,8%** |
| ibridi | 2,4% / 9,2% / 16,0% |
| sola batteria | **6,5% / 23,0% / 40,4%** |

**Da dove viene l'errore** (una sola grandezza prevista, le altre vere):

| grandezza prevista | fattibilità giusta | costo, ibridi: mediana / p95 | costo, sola batteria: mediana / p95 |
|---|---:|---:|---:|
| durata | 99,99% | 0,04% / 0,31% | 0,00% / 0,07% |
| serbatoio | 99,67% | 0,02% / 0,12% | — |
| **idrogeno** | 99,99% | **2,47% / 9,70%** | — |
| **SOC finale** | **99,04%** | **0,99% / 7,42%** | **6,45% / 22,8%** |
| scarica | 99,40% | — | — |
| vita della batteria | 99,99% | 0,08% / 0,37% | 0,34% / 1,13% |
| vita della FC | 99,99% | 0,43% / 1,76% | — |
| C-rate (D3) | 99,99% | — | — |

- **Il costo** sbaglia per due sole grandezze: l'idrogeno negli ibridi (è la voce di costo più grande) e il SOC finale, soprattutto a sola batteria, dove l'energia di ricarica è quasi tutto il costo. Le altre contano poco.
- **La fattibilità** sbaglia soprattutto per il SOC (52% degli errori), la scarica (35%) e la massa, cioè il serbatoio (17%). D3 non conta (0,6%).

**Per migliorare il surrogato bisogna lavorare su idrogeno e SOC finale.** È la priorità per la rete neurale (passo 6).

## Come si rifà

```zsh
L=~/Documents/lavoro/ml_treno_dati/fase9_log; mkdir -p $L
julia -t 8 --project=fase9 fase9/01_costo.jl > $L/log_01.txt 2>&1      # ≈ 55 s
/bin/cp $L/log_01.txt $L/01_*.txt $L/01_*.csv fase9/risultati/; /bin/cp $L/fig_*.png fase9/figure/
```

Ambiente `fase9` = `fase8`. Le previsioni del surrogato e il suo costo, caso per caso, sono in `~/Documents/lavoro/ml_treno_dati/fase9/surrogato_validazione.arrow`, per il passo 5b.

## Metodo

**Le grandezze del surrogato:**
- durata = r̂ × durata minima teorica;
- serbatoio e idrogeno = previsione per km × 2L, e 0 a sola batteria;
- SOC finale tagliato a [0; 0,9]: senza taglio 67 149 casi uscivano dall'intervallo;
- scarica = probabilità ≥ 0,5;
- vite e C-rate dall'esponenziale del logaritmo previsto;
- vita della FC infinita a sola batteria.

I modelli sono quelli salvati nelle fasi 7 e 8, con lo stesso numero di alberi delle loro metriche: il SOC previsto è identico a quello della fase 8.

**Le regole** (le stesse del simulatore, `ConfigModello()`):
- taglie di FC e batteria con `taglia_FC_2` e `taglia_batteria_da_n`, verificate al bit in fase 4;
- n_viaggi_giorno = round(36 000 / (durata + 1));
- E_ricarica = (0,8 − SOC) × capacità × 1500 / 1000;
- massa di propulsione = batteria + FC + serbatoio, contro il limite di 29 250 kg;
- penalità di massa, scarica e SOC come in `costo_da_grandezze`;
- D3: costo 20 000.

Decisioni del 13/11: il credito dell'energia di ricarica negativa resta, e non c'è nessun vincolo sulla vita della batteria.

**Due prove sull'origine dell'errore:**
- una grandezza **vera** alla volta al posto della prevista (`01_ablazione.csv`);
- una sola grandezza **prevista**, le altre vere (`01_una_prevista.csv`, `figure/fig_una_prevista.png`).

La seconda è più chiara. Con la prima nessuna grandezza da sola fa crollare l'errore: idrogeno e SOC sbagliano in casi diversi, quindi correggerne una lascia l'errore dell'altra.

## Dettagli

**Vincolo per vincolo:**

| vincolo | violato davvero | surrogato giusto | mancati | in più |
|---|---:|---:|---:|---:|
| D3 (C-rate > 20) | 12 255 | 99,986% | 59 | 22 |
| massa > 29 250 kg | 100 936 | 99,62% | 1105 | 1160 |
| SOC finale < 0,2 | 189 646 | 97,46% | 8481 | 6492 |
| scarica totale | 238 383 | 98,81% | 3371 | 3667 |

**Errore del costo per lunghezza** (casi davvero fattibili, mediana / p95):

| L | mediana | p95 |
|---|---:|---:|
| 5–25 km | 4,7% | 18,5% |
| 25–100 km | 2,8% | 10,1% |
| 100–200 km | 2,1% | 6,9% |
| 200–300 km | 1,9% | 5,7% |

**Bias:** in media il costo previsto è più alto dello 0,5% sui casi fattibili, del 3,5% a sola batteria.

**Costi negativi.** 8 casi su 577 606, tutti della tratta 11896, la più corta (5 km). Il surrogato prevede un SOC finale di 0,87 contro 0,785 vero, cioè sopra lo 0,8 iniziale. Scatta così il credito dell'energia di ricarica, che diviso per 10 km di viaggio supera tutto il resto del costo. Il credito (decisione 2) amplifica gli errori sul SOC sulle tratte corte.

## Per il passo 5b e la rete neurale

1. Gli errori di costo di qualche percento contano per la scelta dell'ottimo solo se cambiano l'ordine tra le coppie della stessa tratta: lo dirà il passo 5b.
2. Le priorità per la rete neurale sono **idrogeno** e **SOC finale** (anche la scarica per la fattibilità). Le altre grandezze sono già abbastanza buone per il costo.
3. Il SOC vicino allo 0,8 (credito) e vicino allo 0,2 (vincolo) è dove un errore pesa di più: si può pesare di più quella zona nell'addestramento.
