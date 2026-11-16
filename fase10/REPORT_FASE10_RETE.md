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
