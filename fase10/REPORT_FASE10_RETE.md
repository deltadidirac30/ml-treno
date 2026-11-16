# Fase 10: la rete neurale unica (passo 6 del surrogato)

16/11/2026. Tabella della fase 6, banco di prova della fase 9. Julia 1.12.5, Flux 0.16.12, JLD2 0.6.7, CPU con 8 thread. Il test non viene toccato.

## Il modello (`comune.jl`)

**Ingressi (73):**
- le 66 caratteristiche della tratta, m e n, standardizzati con media e deviazione dell'addestramento. Le 10 caratteristiche con asimmetria |·| > 2 passano prima per un log con segno, log1p(|x|/scala), con scala la mediana dei valori non nulli;
- 5 indicatori esatti: ibrido (m > 0) e le 4 fasce D25 di m. Le soglie sono quelle di `soglie_controllo`: 0,0957355…, 0,1015788…, 0,1195045…; riproducono le fasce di `coppie.arrow`.

**Architettura:** perceptron multistrato, 4 strati da 256 neuroni con attivazione GELU, uscita lineare da 8 valori, uno per testa.

| testa | bersaglio | ultima funzione | righe | perdita |
|---|---|---|---|---|
| durata | r = durata / durata minima | 1 + softplus | tutte | ((p − y)/σ)² |
| serbatoio | log(kg / 2L) | μ + σ·z | ibride | ((p − y)/σ)² |
| idrogeno | log(kg / 2L) | μ + σ·z | ibride completate | ((p − y)/σ)² |
| SOC finale | valore | 0,9·sigmoide | tutte | ((p − y)/σ)² |
| scarica | y > 1e-6 | sigmoide | tutte | entropia incrociata |
| vita della batteria | log(cicli) | μ + σ·z | tutte | ((p − y)/σ)² |
| vita della FC | log(f1_ore) | μ + σ·z | ibride | ((p − y)/σ)² |
| C-rate | log | μ + σ·z | tutte | ((p − y)/σ)² |

- μ e σ sono media e deviazione del bersaglio sulle righe di addestramento della testa.
- La perdita totale è la somma delle perdite delle teste. Ogni perdita è la media sulle sole righe della sua maschera; pesi uguali.

**Addestramento:**
- Adam, passo coseno da 1e-3 a 1e-5 sulle epoche previste;
- lotti di 4096 mescolati con seme fisso;
- arresto anticipato sulla perdita totale di validazione (pazienza 5 epoche), con il modello dell'epoca migliore;
- Float32;
- seme fisso: due esecuzioni danno la stessa perdita al quarto decimale.

## Passo 6a: prova breve (`01_prova.jl`, `risultati/01_prova.txt`)

Comando: `julia -t 8 --project=fase10 fase10/01_prova.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_01.txt 2>&1` (≈ 1 min).

Addestramento sui gruppi Sobol 1 e 2 (2048 tratte, 589 824 righe), 5 epoche; validazione intera (gruppi 7 e 12).

**Controlli, tutti superati:**
- nessun ingresso non finito;
- le 68 continue hanno media in [−0,02; 0,03] e deviazione in [0,96; 1,03];
- ibridi 88,9%; fasce D25 5,2%, 6,2%, 6,9%, 70,5%;
- righe con bersaglio per testa uguali a quelle della fase 8 (idrogeno 516 125, serbatoio e vita FC 524 288 in validazione);
- r × durata minima ridà la durata entro 2,4 ms (arrotondamento a 32 bit);
- la perdita di validazione scende a ogni epoca: 0,774 → 0,463 → 0,390 → 0,369 → 0,366;
- le previsioni rispettano la fisica per costruzione: SOC in [0; 0,9], durata > durata minima, masse e vite positive.

**Tempi:**
- 6–8 s per epoca su 590 mila righe, quindi **circa 45–50 s per epoca** su tutto l'addestramento: 30–35 minuti per 40 epoche;
- previsione: 2,5 µs a caso con 8 thread, contro i 45 µs degli 8 modelli boosting.

**Prime metriche** (validazione; rete con 2048 tratte e 5 epoche, boosting con 12 288 tratte e migliaia di alberi: **non è ancora un confronto alla pari**):

| grandezza | rete (prova) mediana / p95 | boosting mediana / p95 |
|---|---:|---:|
| durata | 0,46% / 2,1% | 0,25% / 1,3% |
| serbatoio | 5,5% / 25,5% | 3,3% / 14,6% |
| idrogeno | 5,4% / 24,6% | 3,4% / 14,5% |
| SOC finale (assoluto) | 0,039 / 0,190 | 0,031 / 0,156 |
| vita della batteria | 8,8% / 38,7% | 3,7% / 14,4% |
| vita della FC | 4,2% / 14,9% | 2,5% / 8,3% |
| C-rate | 6,0% / 24,9% | 0,68% / 4,3% |
| scarica (accuratezza; Brier) | 97,2%; 0,021 | 98,8%; 0,009 |

Con un sesto dei dati e pochissimo addestramento la rete è già dello stesso ordine del boosting sul SOC (0,039 contro 0,031), meno sulle altre. Il C-rate e la vita della batteria sono le più lontane: dipendono soprattutto da n, e dovrebbero migliorare con più epoche. Da guardare nel passo 6b.

## Passo 6b: addestramento completo (`02_addestra.jl`, `risultati/02_addestra.txt`)

Comando: `julia -t 8 --project=fase10 fase10/02_addestra.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_02.txt 2>&1` (≈ 35 min).

**Impostazioni.** Tutto l'addestramento (12 288 tratte, 3 538 939 righe), rete 4 × 256, lotti di 4096, Adam con passo coseno da 1e-3 a 1e-5 in 40 epoche, pesi uguali, seme 1, arresto anticipato con pazienza 5.

**Addestramento:**
- 40 epoche in 33 minuti (50 s per epoca);
- **la migliore è l'ultima** (perdita di validazione 0,0792): l'arresto anticipato non è scattato;
- la perdita di validazione scende sempre, ma dopo l'epoca 25 di pochissimo, mentre quella di addestramento continua (0,054 alla fine);
- per testa, SOC e scarica sono le perdite più grandi e si appiattiscono prima (`figure/fig_curve.png`).

Modello in `~/Documents/lavoro/ml_treno_dati/fase10/rete_6b.jld2`, previsioni sulla validazione in `pred_validazione_6b.arrow`.

**Validazione (2048 tratte mai viste), rete contro boosting:**

| grandezza | rete: mediana / p95 / p99 / max | boosting: mediana / p95 | rete meglio? |
|---|---:|---:|---|
| durata | **0,16% / 0,89%** / 1,6% / 5,0% | 0,25% / 1,28% | sì |
| serbatoio | **1,70% / 8,8%** / 19,5% / 303% | 3,33% / 14,6% | sì, errore dimezzato |
| idrogeno | **1,68% / 8,5%** / 18,3% / 301% | 3,39% / 14,5% | sì, errore dimezzato |
| SOC finale (assoluto) | **0,012 / 0,108** / 0,213 / 0,61 | 0,031 / 0,156 | sì, mediana ridotta di 2,5 volte |
| vita della batteria | **2,36% / 10,8%** / 20,9% / 229% | 3,66% / 14,4% | sì |
| vita della FC | **1,73% / 6,5%** / 10,0% / 31% | 2,48% / 8,3% | sì |
| C-rate | 1,24% / 4,9% / 8,9% / 57% | **0,68% / 4,3%** | no, peggio |
| scarica (accuratezza; Brier) | **99,00%; 0,0072** | 98,81%; 0,0087 | sì |

**Sovradattamento piccolo.** Mediane sulle tratte di addestramento (gruppi 1–2) contro la validazione:

| grandezza | addestramento | validazione |
|---|---:|---:|
| durata | 0,129% | 0,159% |
| serbatoio | 1,47% | 1,70% |
| idrogeno | 1,44% | 1,68% |
| SOC | 0,011 | 0,012 |
| vita della batteria | 2,14% | 2,36% |
| vita della FC | 1,47% | 1,73% |
| C-rate | 1,18% | 1,24% |
| scarica | 99,27% | 99,00% |

**Cosa vuol dire:**
1. **Un unico modello batte gli 8 modelli del boosting su 7 grandezze su 8.** I miglioramenti più grandi sono proprio sulle priorità del passo 5a:
   - idrogeno e serbatoio con l'errore dimezzato;
   - **il SOC finale con un errore mediano di 0,012 invece di 0,031**.
2. **Il C-rate è l'unica grandezza peggiore** (1,2% contro 0,7% in mediana; p95 vicino). Dipende quasi solo da n, e la mediana per coppia del boosting lo indovinava già. Conta solo per la regola D3 (C-rate > 20): lo verifica il passo 6c.
3. **C'è ancora margine:** l'epoca migliore è l'ultima, e il sovradattamento è piccolo. Più epoche, o una rete un po' più grande, possono migliorare ancora (varianti del passo 6e).

## Passo 6c: la rete sul banco di prova (`03_banco.jl`, `risultati/03_banco.txt`, `03_scelta.csv`)

Comando: `julia -t 8 --project=fase10 fase10/03_banco.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_03.txt 2>&1` (≈ 15 s). Nessuna simulazione.

Le grandezze previste dalla rete (`pred_validazione_6b.arrow`) passano per lo stesso banco di prova della fase 9: `valuta`, D3 dalla regola C-rate > 20, nessun margine. Il boosting è misurato allo stesso modo, sugli stessi casi.

**Caso per caso (come il passo 5a):**

| | boosting | **rete** |
|---|---:|---:|
| fattibilità giusta | 98,12% | **98,86%** |
| fattibili scartati per errore | 2,67% | **1,38%** |
| non fattibili promossi per errore | 1,28% | **0,97%** |
| vincolo D3 giusto (mancati / in più) | **99,986% (59 / 22)** | 99,904% (255 / 313) |
| vincolo di massa giusto | 99,62% | **99,79%** |
| vincolo SOC < 0,2 giusto | 97,46% | **98,85%** |
| vincolo di scarica giusto | 98,81% | **99,00%** |
| costo, casi fattibili: mediana / p95 / p99 | 2,44% / 9,9% / 17,8% | **1,26% / 5,2% / 9,3%** |
| … sola batteria | 6,54% / 23,0% / 40,4% | **2,55% / 10,9% / 17,5%** |
| … ibridi | 2,39% / 9,2% / 16,0% | **1,24% / 5,0% / 8,7%** |
| bias del costo (casi fattibili) | +0,54% | **+0,11%** |

**Una sola grandezza prevista dalla rete** (le altre vere):
- il costo degli ibridi sbaglia ancora soprattutto per l'idrogeno (1,34% / 6,2%, contro 2,47% / 9,7% del boosting) e poi per il SOC (0,53% / 3,5%);
- a sola batteria sbaglia per il SOC (2,42% / 10,3%, contro 6,45% / 22,8%).

Il C-rate della rete è un po' meno preciso: la regola D3 perde 255 scarti e ne aggiunge 313, contro 59 e 22. Resta giusta nel 99,9% dei casi, e nessuna scelta non fattibile è dovuta a D3.

**Scelta fra le 288 coppie (come il passo 5b), 2048 tratte:**

| strategia | modello | scelte non fattibili | rimpianto mediano | p90 | p95 | tratte entro l'1% |
|---|---|---:|---:|---:|---:|---:|
| scelta secca | boosting | 18,2% | 1,01% | 9,6% | 14,7% | 40,7% |
| scelta secca | **rete** | **14,4%** | **0,00%** | **2,0%** | **4,0%** | **70,4%** |
| verifica delle prime 3 | boosting | 2,5% | 0,35% | 8,0% | 12,9% | 60,1% |
| verifica delle prime 3 | **rete** | **1,0%** | **0,00%** | **1,4%** | **2,8%** | **86,8%** |
| verifica delle prime 5 | boosting | 0,3% | 0,09% | 7,6% | 12,7% | 65,3% |
| verifica delle prime 5 | **rete** | **0,1%** | **0,00%** | **0,9%** | **2,3%** | **90,2%** |
| verifica delle prime 10 | boosting | 0% | 0,00% | 6,9% | 12,7% | 69,4% |
| verifica delle prime 10 | **rete** | **0%** | **0,00%** | **0,5%** | **1,9%** | **92,7%** |

Rimpianto mediano 0,00% vuol dire che in più di metà delle tratte la rete sceglie esattamente la coppia migliore.

Le 295 scelte secche non fattibili della rete violano davvero:
- il SOC in 216 casi, con SOC vero 0,196 in mediana e previsto 0,213: il SOC sbaglia di poco, ma sul bordo;
- la scarica in 69;
- la massa in 12;
- D3 mai.

**Margini con la rete** (tutte le combinazioni in `risultati/03_banco.txt`):

| margini | scelta secca: non fattibili / rimpianto mediano | verifica delle prime 3 | verifica delle prime 5 |
|---|---:|---:|---:|
| nessuno | 14,4% / 0,00% | 1,03% / 0,00% | 0,10% / 0,00% |
| scarica < 0,1 | 12,1% / 0,00% | 0,59% / 0,00% | 0% / 0,00% |
| SOC + 0,01, scarica < 0,1 | 6,8% / 0,00% | 0,20% / 0,00% | 0% / 0,00% |
| SOC + 0,02, scarica < 0,1 | 4,2% / 0,11% | 0,20% / 0,00% | 0% / 0,00% |
| SOC + 0,03, scarica < 0,1 | 2,9% / 0,46% | 0,15% / 0,22% | 0% / 0,14% |

Con il boosting, per scendere sotto il 3% di scelte non fattibili il rimpianto mediano saliva al 3%; con la rete basta lo 0,5%.

**Cosa vuol dire:**
1. **La rete sceglie molto meglio del boosting.** In più di metà delle tratte sceglie proprio la migliore delle 288 coppie, e il 95° percentile del rimpianto passa dal 14,7% al 4,0%. Con 5 verifiche: 0,1% di scelte non fattibili, 90% delle tratte entro l'1%, p95 2,3%, contro 12,7% del boosting.
2. **La maledizione del vincitore resta, ma si governa.** La scelta secca è ancora non fattibile nel 14% delle tratte, per un SOC sbagliato di poco proprio sul limite. Ora però un margine piccolo funziona, perché il SOC della rete è preciso: SOC + 0,01 e scarica < 0,1 portano le scelte non fattibili al 6,8% senza perdere nulla in mediana. Con 3 verifiche, allo 0,2%.
3. **Per il preconfiguratore la strategia candidata è: rete + margine piccolo (SOC + 0,01, scarica < 0,1) + verifica delle prime 3–5 coppie con il simulatore.** I margini sono scelti sulla validazione: vanno confermati sul test.
4. **Il costo** sbaglia ora dell'1,3% in mediana (contro 2,4%), e a sola batteria del 2,6% (contro 6,5%). Il resto dell'errore viene ancora soprattutto dall'idrogeno negli ibridi.

## Passo 6d: la rete sulla griglia fitta (`04_griglia_fitta.jl`, `risultati/04_griglia.txt`, `04_tratte.csv`)

Comando: `julia -t 8 --project=fase10 fase10/04_griglia_fitta.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_04.txt 2>&1` (≈ 1 min).

**Cosa si fa:**
- come il passo 5c, sulle **stesse 256 tratte** e con la **stessa griglia** (9702 punti per tratta), ma con la rete (`rete_6b.jld2`; ricaricata, ridà le previsioni del passo 6b);
- due varianti di fattibilità per il surrogato:
  - senza margini;
  - con il margine piccolo del passo 6c (SOC previsto ≥ 0,21, scarica < 0,1);
- per ognuna, la scelta secca e 5 candidati distanti almeno 0,03, simulati con il percorso della campagna (2179 simulazioni distinte in 22 s; `config.txt` uguale a quello della campagna);
- **velocità:** la rete valuta i 2,5 milioni di punti della griglia in **10 s**, il boosting in 251 s.

**Risultati** (costo vero della scelta rispetto alla migliore delle 288 coppie; negativo = più economica):

| strategia | scelte non fattibili | mediana | p10 | p90 | p95 | più economica della migliore delle 288 | entro +1% |
|---|---:|---:|---:|---:|---:|---:|---:|
| boosting, griglia, scelta secca (5c) | 48,4% | +0,36% | −2,6% | +5,6% | +8,2% | 15,6% | 34,0% |
| boosting, griglia, verifica delle prime 5 (5c) | 10,5% | +0,00% | −4,3% | +3,7% | +5,6% | 43,4% | 72,7% |
| rete, 288 coppie, scelta secca (6c) | 14,1% | 0,00% | 0,00% | +2,3% | +4,4% | — | 68,0% |
| rete, 288 coppie, verifica delle prime 5 (6c) | 0,0% | 0,00% | 0,00% | +1,2% | +3,3% | — | 88,3% |
| rete, griglia, scelta secca | 41,0% | −0,23% | −8,7% | +1,5% | +2,3% | 37,1% | 50,0% |
| **rete, griglia, verifica delle prime 5** | 6,2% | **−0,30%** | **−7,6%** | +0,75% | **+1,15%** | **62,1%** | 85,9% |
| rete, griglia, margine, scelta secca | 18,0% | −0,15% | −7,1% | +1,6% | +2,3% | 48,0% | 69,9% |
| **rete, griglia, margine, verifica delle prime 5** | **1,6%** | −0,21% | −6,8% | +1,0% | +1,7% | 60,9% | **88,7%** |

Il costo previsto della scelta secca fattibile è quasi esatto: contro il vero, mediana +0,1%, p5–p95 da −3,5% a +2,8%. Con il boosting era da −22% a +7%.

**Linee in m** (le stesse 4 tratte del 5c, n fissa; `figure/fig_linee.png`). La "rugosità" è lo scarto mediano di ogni punto dalla media dei due vicini.

| tratta | rugosità: simulatore | rete | boosting | errore mediano del costo: rete | boosting |
|---|---:|---:|---:|---:|---:|
| 6146 | 0,41% | 0,010% | 0,59% | 1,4% | 3,4% |
| 6876 | 0,22% | 0,018% | 0,42% | 1,0% | 3,7% |
| 11610 | 0,11% | 0,020% | 0,29% | 0,9% | 1,8% |
| 12285 | 0,14% | 0,021% | 0,48% | 0,5% | 4,9% |

La rete segue il simulatore quasi sovrapposta, anche lo scalino della soglia D25 a m ≈ 0,1 sulla tratta 12285. È liscia, più del simulatore stesso, che ha un piccolo rumore suo. Si stacca solo dove il simulatore ha un salto netto (tratta 6876, m ≈ 0,85).

**Cosa vuol dire:**
1. **Con la rete la ricerca fitta conviene davvero.** Con 5 verifiche, in **6 tratte su 10 trova un progetto più economico della migliore delle 288 coppie** della campagna: −0,3% in mediana, almeno −7,6% in una tratta su dieci. E il caso peggiore è appena +1,2% (p95).
2. **Con il margine piccolo, le scelte non fattibili scendono all'1,6%** (dal 10,5% del boosting e dal 6,2% senza margine), con quasi lo stesso guadagno (−0,2% in mediana, 61% delle tratte migliorate, 89% entro +1%).
3. **La maledizione del vincitore resta nella scelta secca** (41% senza margine, 18% con): fra 10 000 punti il più economico sta quasi sempre sul bordo. Le verifiche al simulatore restano necessarie.
4. **Gli zig-zag sono spariti:** la rete è 20–40 volte più liscia del boosting. È anche 25 volte più veloce sulla griglia (10 s contro 251 s per 2,5 milioni di punti).

**La strategia di riferimento per il preconfiguratore:** rete neurale sulla griglia fitta + margine piccolo (SOC ≥ 0,21, scarica < 0,1) + verifica delle 5 proposte migliori con il simulatore. Costa circa 0,04 s di rete più 5 simulazioni (circa un quarto di secondo) per tratta. I margini e la strategia sono scelti sulla validazione: vanno confermati sul test.

## Passo 6e: variante con 60 epoche e testa di fattibilità (`05_variante.jl`, `risultati/05_variante.txt`, `05_scelta.csv`)

Comando: `julia -t 8 --project=fase10 fase10/05_variante.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_05.txt 2>&1` (≈ 32 min).

**Cosa cambia rispetto al 6b:**
- passo coseno su 60 epoche invece di 40;
- una nona testa: la probabilità che il progetto sia fattibile (sigmoide, entropia incrociata, tutte le righe; bersaglio `fattibile` della tabella).

Tutto il resto è uguale, compreso il seme. `comune.jl` ora ha il numero di teste come parametro; ricaricato con il codice nuovo, il modello 6b ridà al bit le sue previsioni.

**L'addestramento si è fermato all'epoca 39**, con la migliore alla 34 (perdita di validazione 0,1145, 9 teste).
- Con il passo coseno su 60 epoche, a metà strada il passo di apprendimento è più alto che nel 6b (0,0004 invece di 0,0001 all'epoca 35). La perdita di validazione oscilla di più, soprattutto per C-rate e vita della batteria (`figure/fig_curve_6e.png`), e l'arresto anticipato (pazienza 5) è scattato su un'oscillazione.
- **La parte "più epoche" quindi non è stata davvero provata.** Il modello ha visto 34 epoche con un passo ancora alto.

**Metriche per grandezza** (validazione, mediana / p95):

| grandezza | 6e | 6b | boosting |
|---|---:|---:|---:|
| durata | 0,181% / 0,94% | **0,159% / 0,89%** | 0,245% / 1,28% |
| serbatoio | 1,89% / 9,4% | **1,70% / 8,8%** | 3,33% / 14,6% |
| idrogeno | 1,87% / 9,2% | **1,68% / 8,5%** | 3,39% / 14,5% |
| SOC finale (assoluto) | 0,012 / 0,110 | **0,012 / 0,108** | 0,031 / 0,156 |
| vita della batteria | 2,73% / 12,1% | **2,36% / 10,8%** | 3,66% / 14,4% |
| vita della FC | 1,81% / 6,6% | **1,73% / 6,5%** | 2,48% / 8,3% |
| C-rate | 1,51% / 5,8% | 1,24% / 4,9% | **0,68% / 4,3%** |
| scarica (accuratezza) | 98,96% | **99,00%** | 98,81% |

La variante è un po' peggiore del 6b su tutte le grandezze.

**La testa di fattibilità:**
- giusta nel 98,78% dei casi (p ≥ 0,5), Brier 0,0088: come i vincoli calcolati dalle grandezze previste (98,83%);
- testa e vincoli sono d'accordo nel 99,5% dei casi;
- è ragionevolmente calibrata: nella fascia [0,8; 0,9) è fattibile l'80,5%.

**Scelta fra le 288 coppie** (2048 tratte; tutte le regole in `risultati/05_variante.txt`):

| regola di ammissione | scelta secca: non fattibili / rimpianto p95 | prime 5: non fattibili / rimpianto p95 / entro 1% |
|---|---:|---:|
| 6b, vincoli (6c) | 14,4% / 4,0% | 0,10% / 2,3% / 90,2% |
| 6b, vincoli + margine (SOC ≥ 0,21, scarica < 0,1) | 6,8% / 6,1% | 0% / 4,9% / 84,6% |
| 6e, vincoli | 12,8% / 4,9% | 0,15% / 3,0% / 88,3% |
| 6e, solo probabilità ≥ 0,7 | 7,2% / 6,2% | 0,10% / 5,2% / 83,3% |
| 6e, solo probabilità ≥ 0,9 | 2,8% / 8,1% | 0% / 7,4% / 74,0% |
| 6e, solo probabilità ≥ 0,95 | 1,8% / 8,8% | 0% / 8,3% / 68,8% |

**Cosa vuol dire:**
1. **La testa di fattibilità non aggiunge nulla** rispetto ai vincoli calcolati dalle grandezze previste: stessa accuratezza, stesso compromesso fra scelte non fattibili e rimpianto. Con una soglia alta (0,9–0,95) la scelta secca diventa quasi sempre fattibile (1,8–2,8%), ma il progetto scelto costa di più: rimpianto mediano 0,3–0,5%, p95 8–9%.
2. **Ogni margine sposta lo stesso compromesso.** Meno scelte non fattibili si pagano con un rimpianto più alto nei casi peggiori. Anche il margine piccolo del 6b fa salire il p95 del rimpianto dal 4,0% al 6,1% (scelta secca) e dal 2,3% al 4,9% (con 5 verifiche). Senza simulazioni non c'è un modo gratuito per evitare la maledizione del vincitore; con 5 verifiche e nessun margine il problema è già quasi risolto (0,1% di scelte non fattibili, p95 2,3%).
3. **Il modello di riferimento resta il 6b** (8 teste, 40 epoche). Più epoche andrebbero provate con un arresto anticipato più paziente: costerebbe circa 50 minuti, e dalle curve il guadagno atteso è piccolo.

## Velocità: rete contro simulatore (`06_velocita.jl`, `risultati/06_velocita_t1.txt`, `06_velocita_t8.txt`)

Comandi: `julia -t 1 --project=fase10 fase10/06_velocita.jl` (tutto su un core, anche BLAS) e `julia -t 8 …` (rete su 8 thread; il simulatore resta su un core). Mac M4, ≈ 1 min ciascuno.

**Cosa si misura:**
- **simulatore:** `valuta_progetto` (TrainPowertrain invariato, configurazione della campagna) su 12 tratte di validazione (4 corte, 4 medie, 4 lunghe) × 24 coppie scelte a caso fra le 288, dopo un riscaldamento; il precalcolo della tratta a parte;
- **rete:** le 8 grandezze più vincoli e costo (`valuta` della fase 9), cioè lo stesso risultato utile, per 1 punto, per le 288 coppie e per la griglia fitta (9702 punti).

| | un core | 8 thread (solo la rete) |
|---|---:|---:|
| simulatore, per progetto (media; da 0,6 a 44 ms secondo tratta e progetto) | 12 ms | — |
| simulatore nella campagna sul PC (16 thread; 294 912 valutazioni) | mediana 26 ms, media 51 ms, p95 179 ms | — |
| rete + costo, un punto da solo | 40 µs (**300×**) | 35 µs |
| rete + costo, a punto sulle 288 coppie di una tratta | 6,3 µs (**1900×**) | 4,4 µs (2600×) |
| rete + costo, a punto sulla griglia fitta | 5,1 µs (**2400×**) | 2,8 µs (4100×) |

- Il tempo della rete non dipende dalla tratta né dal progetto. Quello del simulatore cresce con la lunghezza e con le iterazioni di dimensionamento del serbatoio.
- Sulle tratte corte e facili il rapporto scende a ~100×; sulle lunghe e difficili sale oltre 9000×.
- Il costo una tantum per ottenere la rete è la campagna (≈ 5 h di parete sul PC, 68,5 h di CPU) più l'addestramento (≈ 35 min).
