# Fase 11: rifiniture (passo 7 del surrogato)

16/11/2026. Rete neurale della fase 10 (6b). Julia 1.12.5, Flux 0.16.12, 8 thread. Il test non è stato toccato. Ambiente `fase11` = `fase10`.

## Passo 7a: quanti dati servono (`01_quanti_dati.jl`, `risultati/01_quanti_dati.txt`, `01_curva.csv`)

Comando: `julia -t 8 --project=fase11 fase11/01_quanti_dati.jl > ~/Documents/lavoro/ml_treno_dati/fase11_log/log_01.txt 2>&1` (≈ 38 min).

**Metodo:**
- la rete 6b (stesse impostazioni) riaddestrata su sottoinsiemi annidati dei gruppi Sobol di addestramento: {1, 2}, {1–4}, {1–6, 8, 9}, cioè 2048, 4096 e 8192 tratte;
- normalizzazione e scale dai soli dati usati;
- il punto a 12 288 tratte è la 6b;
- misure sulla validazione come nei passi 6b e 6c.

Modelli in `~/Documents/lavoro/ml_treno_dati/fase11/rete_7a_<tratte>.jld2`.

| tratte di addestramento | 2048 | 4096 | 8192 | 12 288 |
|---|---:|---:|---:|---:|
| durata (mediana) | 0,274% | 0,212% | 0,178% | 0,159% |
| serbatoio | 2,99% | 2,30% | 1,88% | 1,70% |
| idrogeno (mediana; p95) | 2,97%; 13,6% | 2,28%; 10,9% | 1,86%; 9,3% | 1,68%; 8,5% |
| SOC finale (assoluto; p95) | 0,0204; 0,135 | 0,0163; 0,121 | 0,0130; 0,111 | 0,0118; 0,108 |
| vita della batteria | 4,29% | 3,16% | 2,56% | 2,36% |
| vita della FC | 2,58% | 2,15% | 1,83% | 1,73% |
| C-rate | 2,55% | 1,81% | 1,41% | 1,24% |
| scarica (giusta) | 98,54% | 98,77% | 98,94% | 99,00% |
| fattibilità giusta | 98,34% | 98,60% | 98,78% | 98,86% |
| costo (mediana; p95) | 2,08%; 8,9% | 1,65%; 6,8% | 1,38%; 5,8% | 1,26%; 5,2% |
| scelta secca: non fattibili; rimpianto p95 | 13,0%; 8,1% | 13,9%; 6,7% | 15,8%; 4,4% | 14,4%; 4,0% |
| prime 5: non fattibili; rimpianto p95; entro 1% | 0,24%; 6,7%; 77,2% | 0,15%; 5,2%; 83,7% | 0,10%; 3,1%; 88,4% | 0,10%; 2,3%; 90,2% |

L'epoca migliore è sempre la 39 o la 40: nessun sovradattamento, nemmeno con 2048 tratte.

**Cosa vuol dire:**
1. **Più tratte migliorano ancora tutto**, senza segni di saturazione. Ogni raddoppio riduce gli errori di circa il 18–23%: l'idrogeno passa da 2,97% a 2,28% a 1,86%, e da 8192 a 12 288 (×1,5) a 1,68%. È una legge di potenza con esponente ~0,3: con 24 576 tratte ci si può aspettare idrogeno ~1,4%, SOC ~0,010, costo ~1,05%.
2. **Il rimpianto con 5 verifiche migliora molto con i dati** (p95 da 6,7% a 2,3%; tratte entro l'1% da 77% a 90%).
3. **La scelta secca non fattibile non migliora con i dati** (13–16% a tutte le taglie). La maledizione del vincitore non dipende dalla precisione media del modello, ma dalla precisione proprio sul bordo dei vincoli. Lì un errore anche piccolo basta: vedi 7b.
4. **Una nuova campagna** (altre 16 384 tratte × 288 coppie, ≈ 5 h sul PC) ridurrebbe gli errori di un altro ~20%. Conviene se serve un surrogato più preciso da solo. Con le verifiche al simulatore il guadagno pratico è più piccolo.

## Passo 7b: dove sbaglia la rete (`02_dove_sbaglia.jl`, `risultati/02_dove_sbaglia.txt`, `02_tratte.csv`)

Comando: `julia -t 8 --project=fase11 fase11/02_dove_sbaglia.jl > ~/Documents/lavoro/ml_treno_dati/fase11_log/log_02.txt 2>&1` (≈ 10 s). Previsioni della rete 6b sulla validazione.

**Per tipo di tratta** (mediane; fasce a quantili delle 2048 tratte):

| | peggio | meglio |
|---|---|---|
| lunghezza | 5–64 km: idrogeno 2,95%, costo 1,81% | 237–300 km: idrogeno 1,31%, costo 0,96% |
| fermate intermedie | 0–2: idrogeno 2,39%, costo 1,85% | 21–28: idrogeno 1,43%, costo 1,01% |
| dislivello | 0–212 m: idrogeno 2,31%, costo 1,56% | 2470–5960 m: idrogeno 1,29%, costo 1,00% |
| pendenza, limite medio | effetto piccolo | |

Le tratte "piccole" (corte, senza fermate, piatte) hanno l'errore relativo più alto: consumano poco, quindi lo stesso errore assoluto pesa di più. Il SOC invece è quasi uguale su tutti i tipi di tratta (0,010–0,014).

**Per zona di (m, n)** (`figure/fig_errori_mn.png`):
- l'errore del SOC cresce con m e cala con n: 0,004 a sola batteria, 0,021 con m ≥ 0,7, fino a ~0,06 con m vicino a 1 e n < 0,1. Fuel cell grande e batteria piccola danno un SOC molto mobile;
- la fattibilità è giusta al 99,7% a sola batteria, al 98,0% per 0,4 ≤ m < 0,7;
- con n < 0,05: SOC 0,030, vita della batteria 5,8%.

**Il SOC vicino al limite di 0,2:**
- quando il SOC vero è fra 0,15 e 0,25, la rete lo mette **dalla parte sbagliata di 0,2 nel 20% dei casi**, con un errore mediano di 0,016;
- fuori da quella fascia succede in meno dello 0,5% dei casi.

È esattamente la maledizione del vincitore: un errore normale, ma sul bordo.

**Distanza dall'addestramento.** È la distanza dalla tratta di addestramento più vicina, nelle 66 caratteristiche standardizzate: mediana 2,9, max 6,6.
- Correlazione con l'errore del costo della tratta: 0,29.
- Per quinti di distanza, l'errore mediano del costo passa da 0,96% (le più vicine) a 1,84% (il 10% più lontano), e il rimpianto p95 della scelta secca da 2,9% a 7,8%.
- **Le tratte lontane dai dati di addestramento sono le più difficili.** Vale anche per le linee della rete ferroviaria ai bordi del dominio.

**Le 10 tratte peggiori** (errore del costo 6–9%): quasi tutte corte (5–18 km), con 0–3 fermate, spesso lontane dall'addestramento (distanza 3–6). Fanno eccezione la 12069 (152 km, dislivello 2788 m) e la 11873 (57 km, pendenza rms 16,8‰), dove sbaglia il SOC.

## Cosa fare

1. **Per la precisione media:** più tratte (legge di potenza, nessuna saturazione); altre 16 384 tratte darebbero ~20% di errore in meno.
2. **Per le tratte corte:** sono poche nel DoE (L uniforme fra 5 e 300 km). Più tratte corte, o un peso maggiore nell'addestramento, ridurrebbero il loro errore.
3. **Per la maledizione del vincitore:** più dati non bastano. Servono le verifiche al simulatore (strategia del 6d), oppure più coppie (m, n) vicino al limite del SOC (per esempio coppie scelte dove il SOC previsto è fra 0,15 e 0,25), cioè un campionamento adattivo.
4. **Per le linee reali:** guardare la distanza dall'addestramento, perché oltre il 90° percentile l'errore raddoppia.
