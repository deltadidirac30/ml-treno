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

## Passo 5b: la scelta della coppia migliore (`02_scelta.jl`, `risultati/02_scelta.txt`)

Comando: `julia -t 8 --project=fase9 fase9/02_scelta.jl > $L/log_02.txt 2>&1` (≈ 10 s). Usa `surrogato_validazione.arrow` del passo 5a; nessuna simulazione. Una riga per tratta in `risultati/02_tratte.csv`.

**Per ogni tratta di validazione** (2048; nessuna delle tratte segnalate):
- la **migliore vera** è la coppia fattibile più economica secondo il simulatore, fra le 288;
- la **scelta del surrogato** è la coppia che il surrogato dice fattibile e più economica;
- il **rimpianto** è il costo vero della scelta diviso il costo della migliore, meno 1;
- una scelta in realtà **non fattibile** è l'errore grave.

| strategia | scelte non fattibili | rimpianto: mediana | p90 | p95 | tratte entro l'1% |
|---|---:|---:|---:|---:|---:|
| **surrogato, scelta secca** | **373 (18,2%)** | 1,01% | 9,6% | 14,7% | 40,7% |
| surrogato + verifica delle prime 2 | 131 (6,4%) | 0,58% | 8,6% | 13,8% | 53,7% |
| surrogato + verifica delle prime 3 | 51 (2,5%) | 0,35% | 8,0% | 12,9% | 60,1% |
| surrogato + verifica delle prime 5 | 6 (0,3%) | 0,09% | 7,6% | 12,7% | 65,3% |
| surrogato + verifica delle prime 10 | 0 | 0,00% | 6,9% | 12,7% | 69,4% |
| migliore della tratta di addestramento più vicina | 739 (36,1%) | 2,6% | 27,5% | 40,0% | 21,5% |
| coppia fissa più frequente (la 286) | 1234 (60,3%) | 40,0% | 64,3% | 71,3% | 7,0% |

"Surrogato + verifica delle prime k": il simulatore verifica le k coppie migliori secondo il surrogato e si tiene la migliore davvero fattibile. Costa k simulazioni, circa k × 50 ms. Il rimpianto è sulle scelte fattibili; "entro l'1%" è su tutte le tratte.

**La scelta secca nel dettaglio:**
- stessa coppia della migliore vera in 513 tratte (25%);
- regime giusto (sola batteria o ibrido) nel 97,3% delle tratte;
- posto della scelta fra le coppie davvero fattibili: mediana 2°, p90 11°; fra le prime tre nel 52,7%;
- il costo previsto della scelta è quasi senza distorsione in mediana (−0,16%), ma va da −10,8% a +7,1% (p5–p95);
- per regime della migliore vera:
  - sola batteria (526 tratte): 89 scelte non fattibili, 48 regimi sbagliati, rimpianto mediana 0,77%, p95 25%;
  - ibrida (1522 tratte): 284 non fattibili, 7 regimi sbagliati, rimpianto mediana 1,18%, p95 13,7%;
- i rimpianti più grandi (38–115%) sono tratte la cui migliore è a sola batteria, dove il surrogato sceglie un ibrido con m ≈ 0,1: 11896 (5 km), 6424 (21 km), 12233 (12 km), 11701, 7037.

**Perché il 18% delle scelte non è fattibile: la "maledizione del vincitore".** Il surrogato sceglie la coppia più economica fra quelle che crede fattibili. Spesso è proprio sul bordo di un vincolo, dove un piccolo errore cambia la fattibilità. Delle 373 scelte non fattibili:
- **255 violano il SOC finale:** SOC vero 0,173 in mediana, previsto 0,211, cioè appena sopra il limite di 0,2;
- **106 violano la scarica:** probabilità prevista 0,375 in mediana e al più 0,497, appena sotto la soglia di 0,5;
- **34 violano la massa:** oltre il limite di 126 kg in mediana;
- nessuna viola D3.

**Cosa vuol dire.** Usato da solo, il surrogato sceglie quasi sempre "vicino" alla migliore. Ma una volta su cinque la sua scelta viola di poco un vincolo, quasi sempre il SOC.

Due rimedi possibili, che si possono anche combinare:
- **verificare poche coppie con il simulatore:** con le prime 5 le scelte non fattibili scendono allo 0,3% e il rimpianto mediano allo 0,09%;
- **un margine di sicurezza sui vincoli:** per esempio SOC previsto ≥ 0,2 + δ, e probabilità di scarica sotto una soglia più bassa di 0,5.

La rete neurale dovrà essere misurata anche su questo.
