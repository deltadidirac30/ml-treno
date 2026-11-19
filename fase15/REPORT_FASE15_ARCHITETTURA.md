# Fase 15: quanto contano profondità e larghezza della rete

19–20/11/2026. Tabella della fase 6, banco di prova della fase 9, rete 6b della fase 10. Julia 1.12.5, Flux 0.16.12, TrainPowertrain `7c9115a`, MacBook Air M4, 8 thread. Ambiente uguale a fase10 (`Project.toml` e `Manifest.toml` copiati). Tutte le misure sono sulla validazione (2048 tratte, 589 824 righe): il test non viene toccato.

## Perché

La rete del surrogato (6b: 4 strati × 256, GELU, 8 teste) era stata scelta senza confronti con altre architetture. Questo studio serve a giustificare la scelta nell'articolo, non a cambiarla. La regola decisa prima di partire: **il modello resta la 6b, a meno di differenze molto più grandi della variabilità dovuta al seme.**

## Cosa si fa (`01_architettura.jl`)

Comando (≈ 3 h, dalle 21:23 alle 00:27):
```
cd "$ML" && nohup caffeinate -i julia -t 8 --project=fase15 fase15/01_architettura.jl >> ~/Documents/lavoro/ml_treno_dati/fase15_log/log_01.txt 2>&1 &
```

Le varianti sono addestrate con `costruisci`/`addestra` di `fase10/comune.jl`, con larghezza e strati come parametri. Tutto il resto è identico al 6b:
- dati, normalizzazione e scale. Lo script controlla che siano identiche al bit a quelle salvate nella 6b;
- perdita, 40 epoche, passo coseno da 1e-3 a 1e-5, lotti da 4096, pazienza 5, Float32.

Le varianti:
- **profondità**, larghezza 256: 2, 3 e 6 strati (seme 1);
- **larghezza**, 4 strati: 128 e 512 neuroni (seme 1);
- **seme**: 4 × 256 con semi 2 e 3. Misurano quanto cambia per il solo seme, cioè la soglia sotto cui le differenze non contano.

Il seme cambia sia i pesi iniziali sia l'ordine dei lotti. Il punto 4 × 256 con seme 1 è la 6b: non è stata riaddestrata, ma ricaricata da `fase10/rete_6b.jld2`. Ricaricata ridà al bit le previsioni del passo 6b, e lo script ridà esattamente i numeri dei passi 6b, 6c e 6d.

Lo script addestra le varianti in sequenza e salva dopo ognuna, così se si interrompe riparte da quelle mancanti. Poi misura tutte le 8 reti allo stesso modo:
- numero di parametri, tempo di addestramento, epoca migliore, perdita di validazione;
- errori delle 8 grandezze, come il passo 6b;
- banco di prova come il passo 6c (`valuta` della fase 9): fattibilità, errore del costo sui casi davvero fattibili, scelta fra le 288 coppie (scelta secca e verifica delle prime 5). Nessuna simulazione;
- tempo di previsione a punto sulla griglia fitta (9702 punti, le 12 tratte di `fase10/06_velocita.jl`, 8 thread): sola rete, e rete più vincoli e costo;
- rugosità del costo sulle 4 linee in m del passo 6d. Il costo del simulatore viene dalle simulazioni già salvate dal 6d.

Uscite:
- modelli e previsioni in `~/Documents/lavoro/ml_treno_dati/fase15`;
- in `risultati/`: `01_architettura.txt`, `01_riassunto.csv`, `01_seme.csv`, `01_storia_<rete>.csv`;
- figura: `figure/fig_architettura.png`.

## Risultati

### Costo e addestramento

| rete | parametri | epoche (migliore) | addestramento | s per epoca | previsione: rete / rete + costo [µs a punto] | perdita di validazione |
|---|---:|---:|---:|---:|---:|---:|
| 2 × 256 | 86 792 | 40 (40) | 11,6 min | 17,4 | 1,27 / 1,88 | 0,0961 |
| 3 × 256 | 152 584 | 40 (40) | 18,7 min | 28,0 | 1,79 / 2,46 | 0,0827 |
| **4 × 256 (6b)** | **218 376** | 40 (40) | 33,1 min | 49,7 | **2,34 / 3,05** | **0,0792** |
| 6 × 256 | 349 960 | 40 (40) | 38,5 min | 57,7 | 3,42 / 4,15 | 0,0783 |
| 4 × 128 | 60 040 | 40 (40) | 10,7 min | 16,0 | 1,19 / 1,83 | 0,0853 |
| 4 × 512 | 829 960 | **24 (19)** | 39,2 min | 98,1 | 6,03 / 6,88 | 0,0833 |
| 4 × 256, seme 2 | 218 376 | 40 (38) | 31,7 min | 47,6 | 2,35 / 3,06 | 0,0798 |
| 4 × 256, seme 3 | 218 376 | 40 (40) | 25,8 min | 38,7 | 2,36 / 3,15 | 0,0788 |

- **I tempi di addestramento sono indicativi.** La stessa rete 4 × 256 ha preso fra 38,7 e 49,7 s per epoca. Il MacBook Air non ha ventola e rallenta quando si scalda, e la 6b è stata addestrata in un altro giorno. I tempi di previsione invece sono stabili: 3,05–3,15 µs per i tre semi.
- Tutte le reti hanno la migliore all'ultima epoca o quasi, tranne la 4 × 512 (vedi sotto).

### Le 8 grandezze (mediana / p95; SOC assoluto, le altre in %)

| rete | durata | serbatoio | idrogeno | SOC finale | vita batteria | vita FC | C-rate | scarica (accuratezza) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2 × 256 | 0,162 / 0,91 | 2,11 / 10,4 | 2,09 / 10,1 | 0,0169 / 0,124 | 2,99 / 13,7 | 1,97 / 7,1 | 1,42 / 5,8 | 98,92 |
| 3 × 256 | 0,161 / 0,88 | 1,81 / 9,2 | 1,78 / 8,9 | 0,0129 / 0,112 | 2,43 / 11,4 | 1,81 / 6,6 | 1,28 / 5,2 | 98,99 |
| **4 × 256 (6b)** | 0,159 / 0,89 | 1,70 / 8,8 | 1,68 / 8,5 | 0,0118 / 0,108 | 2,36 / 10,8 | 1,73 / 6,5 | 1,24 / 4,9 | 99,00 |
| 6 × 256 | 0,161 / 0,92 | 1,61 / 8,5 | 1,60 / 8,4 | 0,0102 / 0,105 | 2,18 / 10,3 | 1,68 / 6,4 | 1,22 / 4,8 | 98,99 |
| 4 × 128 | 0,187 / 0,89 | 1,86 / 9,3 | 1,84 / 9,0 | 0,0136 / 0,114 | 2,73 / 12,2 | 1,89 / 6,8 | 1,46 / 5,7 | 98,95 |
| 4 × 512 | 0,173 / 0,94 | 1,91 / 9,0 | 1,91 / 8,9 | 0,0118 / 0,109 | 2,74 / 12,3 | 1,76 / 6,7 | 1,51 / 6,5 | 98,96 |
| 4 × 256, seme 2 | 0,165 / 0,90 | 1,71 / 8,9 | 1,69 / 8,6 | 0,0118 / 0,107 | 2,30 / 10,7 | 1,76 / 6,5 | 1,25 / 5,1 | 98,99 |
| 4 × 256, seme 3 | 0,164 / 0,91 | 1,68 / 8,8 | 1,65 / 8,6 | 0,0115 / 0,107 | 2,27 / 10,8 | 1,74 / 6,5 | 1,22 / 5,0 | 99,02 |

### Banco di prova: fattibilità, costo, scelta fra le 288 coppie (2048 tratte)

| rete | fattibilità giusta | costo: mediana / p95 | scelta secca: non fattibili / rimpianto p95 / entro 1% | prime 5: non fattibili / rimpianto p95 / entro 1% | rugosità del costo |
|---|---:|---:|---:|---:|---:|
| 2 × 256 | 98,63% | 1,64% / 7,0% | 11,3% / 6,1% / 58,4% | 0,00% / 4,8% / 78,8% | 0,013% |
| 3 × 256 | 98,80% | 1,37% / 5,5% | 16,6% / 4,0% / 66,4% | 0,05% / 3,1% / 88,6% | 0,015% |
| **4 × 256 (6b)** | 98,86% | 1,26% / 5,2% | 14,4% / 4,0% / 70,4% | 0,10% / 2,3% / 90,2% | 0,017% |
| 6 × 256 | 98,89% | 1,19% / 5,0% | 13,3% / 3,2% / 73,9% | 0,10% / 2,0% / 91,5% | 0,014% |
| 4 × 128 | 98,79% | 1,40% / 5,5% | 14,1% / 4,7% / 65,2% | 0,24% / 3,9% / 85,8% | 0,016% |
| 4 × 512 | 98,80% | 1,41% / 5,3% | 16,9% / 3,8% / 69,4% | 0,05% / 2,0% / 92,0% | 0,018% |
| 4 × 256, seme 2 | 98,86% | 1,27% / 5,3% | 14,1% / 4,0% / 70,8% | 0,15% / 2,6% / 89,7% | 0,016% |
| 4 × 256, seme 3 | 98,86% | 1,28% / 5,2% | 16,4% / 3,4% / 68,9% | 0,20% / 2,4% / 90,5% | 0,016% |

- Il rimpianto mediano è 0,00% per tutte le reti (0,19% per la 2 × 256 nella scelta secca).
- La rugosità è la media sulle 4 linee del 6d. Il simulatore sulle stesse linee ha 0,41%, 0,22%, 0,11% e 0,14%.
- L'errore mediano del costo sulle 4 linee (0,9–1,9%) non è riportato in tabella. Cambia molto anche fra i semi (0,92%, 0,95%, 1,58%), perché sono solo 4 linee e circa 380 punti.

### La variabilità del seme

Con tre semi la stessa rete 4 × 256 dà (minimo – massimo; tutto in `risultati/01_seme.csv`):

| misura | tre semi | ampiezza (= soglia) |
|---|---:|---:|
| perdita di validazione | 0,0788 – 0,0798 | 0,0010 (1,2%) |
| idrogeno, mediana | 1,65 – 1,69% | 0,03 punti |
| SOC, mediana | 0,0115 – 0,0118 | 0,0003 |
| costo, mediana / p95 | 1,26 – 1,28% / 5,21 – 5,26% | 0,02 / 0,06 punti |
| fattibilità giusta | 98,855 – 98,861% | 0,006 punti |
| scelta secca, non fattibili | 14,1 – 16,4% | **2,3 punti** |
| scelta secca, rimpianto p95 | 3,4 – 4,0% | **0,6 punti** |
| scelta secca, entro l'1% | 68,9 – 70,8% | 1,9 punti |
| prime 5, rimpianto p95 / entro l'1% | 2,29 – 2,59% / 89,7 – 90,5% | 0,3 / 0,8 punti |

**Due livelli molto diversi:**
- **Le metriche per grandezza e per caso sono stabilissime.** Il seme sposta l'errore del costo di 2 centesimi di punto e la perdita dell'1%.
- **Le metriche della scelta sono rumorose.** Dipendono da poche tratte in cui il progetto più economico sta sul bordo della fattibilità: il seme sposta del 2% le tratte con scelta secca non fattibile e di mezzo punto il p95 del rimpianto.

Per questo le architetture vanno confrontate soprattutto sulle grandezze, sulla perdita e sul costo. Sulla scelta contano solo differenze di diversi punti.

### Differenze dalla 6b, in multipli della soglia del seme

(Δ = variante − 6b; tra parentesi |Δ| / soglia. Il segno "migliore" o "peggiore" è dal punto di vista della variante.)

| misura | 2 × 256 | 3 × 256 | 6 × 256 | 4 × 128 | 4 × 512 |
|---|---:|---:|---:|---:|---:|
| perdita di validazione | +21% (17×) | +4,3% (3,5×) | −1,2% (1,0×) | +7,6% (6,2×) | +5,1% (4,1×) |
| idrogeno, mediana | +0,41 pt (13×) | +0,10 (3,2×) | −0,08 (2,6×) | +0,16 (5,2×) | +0,24 (7,6×) |
| SOC, mediana | +0,0051 (17×) | +0,0010 (3,4×) | −0,0016 (5,3×) | +0,0018 (5,9×) | 0,0000 (0×) |
| C-rate, mediana | +0,19 pt (6,7×) | +0,04 (1,5×) | −0,01 (0,5×) | +0,22 (8,0×) | +0,27 (9,7×) |
| costo, mediana | +0,38 pt (21×) | +0,11 (6,1×) | −0,07 (3,8×) | +0,14 (7,7×) | +0,16 (8,6×) |
| costo, p95 | +1,75 pt (30×) | +0,28 (4,9×) | −0,24 (4,1×) | +0,25 (4,3×) | +0,12 (2,1×) |
| scelta secca, rimpianto p95 | +2,2 pt (3,5×) | +0,05 (0,1×) | −0,8 (1,3×) | +0,7 (1,2×) | −0,2 (0,4×) |
| prime 5, rimpianto p95 | +2,5 pt (8,3×) | +0,8 (2,7×) | −0,3 (1,0×) | +1,6 (5,4×) | −0,3 (1,1×) |
| prime 5, entro l'1% | −11,4 pt (15×) | −1,6 (2,0×) | +1,3 (1,6×) | −4,4 (5,6×) | +1,8 (2,3×) |
| rugosità | −0,005 pt (3,3×) | −0,003 (2,0×) | −0,003 (2,0×) | −0,001 (0,9×) | +0,000 (0,3×) |

## Profondità

- **Da 2 a 4 strati il guadagno è grande e netto**, molto oltre il seme:
  - perdita di validazione da 0,0961 a 0,0792 (−18%);
  - errore del costo da 1,64% / 7,0% a 1,26% / 5,2%;
  - con 5 verifiche, tratte entro l'1% dalla migliore da 79% a 90%.
- **3 strati sono ancora un po' peggio di 4.** Perdita +4%, costo +0,11 punti: 3–6 volte la soglia sulle grandezze, ma piccolo in assoluto. Sulla scelta non si distingue dal seme.
- **Da 4 a 6 strati il guadagno è piccolo.**
  - La perdita scende solo dell'1,2% (0,0783 contro 0,0788–0,0798 dei tre semi): sul bordo della variabilità del seme.
  - Le grandezze migliorano poco ma tutte nello stesso verso, 2–5 volte la soglia: SOC 0,0102 contro 0,0118, idrogeno 1,60% contro 1,68%, costo 1,19% / 5,0% contro 1,26% / 5,2%.
  - Sulla scelta la differenza è dentro il rumore del seme (rimpianto p95 3,2% contro 3,4–4,0%; prime 5: 2,0% contro 2,3–2,6%).
  - Costa il 60% di parametri in più e il 36% di tempo di previsione in più (4,2 contro 3,05 µs a punto).
  - Nelle prime due epoche la 6 × 256 parte molto male (perdita di validazione ≈ 2,5), poi si riprende dalla terza (`figure/fig_architettura.png`).
- I rendimenti decrescono: la perdita va da 0,096 a 0,083, poi 0,079 e infine 0,078, passando da 2 a 3, 4 e 6 strati. **4 strati sono il ginocchio della curva.**

## Larghezza

- **128 neuroni sono pochi.** Con 4 strati la 4 × 128 perde rispetto alla 6b su tutto, 4–10 volte la soglia:
  - perdita +7,6%;
  - idrogeno 1,84% contro 1,68%, costo 1,40% contro 1,26%;
  - prime 5: rimpianto p95 3,9% contro 2,3%, entro l'1% 85,8% contro 90,2%.

  È però la più veloce: 1,8 µs a punto contro 3,05.
- **512 neuroni non migliorano, con la stessa ricetta di addestramento.**
  - La 4 × 512 si è fermata all'epoca 24 per l'arresto anticipato, con la migliore alla 19 (perdita 0,0833).
  - Il passo era ancora alto (5,6e-4 all'epoca 19) e la perdita di validazione oscillava (0,083–0,090 fra le epoche 14 e 24).
  - La rete si adatta troppo ai dati di addestramento: all'epoca 24 la perdita di addestramento è già 0,048, più bassa di quella finale della 6b (0,054), mentre la validazione resta a 0,085.
  - Risultato: grandezze peggiori della 6b (idrogeno +0,24 punti, C-rate +0,27, costo +0,16: 4–10 volte la soglia). Sulla scelta invece è pari, dentro il rumore del seme.
  - **Il confronto non è definitivo per la 512.** A parità di epoca (la 19) era davanti alla 4 × 256 (0,0833 contro 0,0848–0,0856). Con un passo più basso o più pazienza potrebbe arrivare alla 6b o poco sotto. Costerebbe però 3,8 volte i parametri, il doppio del tempo per epoca e 2,3 volte il tempo di previsione. Il divario fra addestramento e validazione dice che il guadagno sarebbe comunque piccolo.

## Rugosità

Tutte le reti sono lisce, con rugosità fra 0,013% e 0,018% sulle 4 linee: da 6 a 30 volte meno del simulatore stesso (0,11–0,41%). Le differenze fra architetture sono dello stesso ordine di quelle fra i semi (0,016–0,017%). La regolarità del costo previsto, che rende possibile la ricerca sulla griglia fitta, non dipende dall'architettura.

## Cosa vuol dire

1. **La profondità conta fino a 4 strati, poi poco.** Una rete a 2 strati è nettamente peggiore su tutto: il costo sbaglia del 30% in più, e con 5 verifiche si perde un decimo delle tratte entro l'1%. Oltre 4 strati il guadagno è di qualche percento sulle grandezze, sul bordo della variabilità del seme per la perdita e dentro il rumore per la scelta.
2. **La larghezza giusta è 256.** Con 128 si perde chiaramente. Con 512, con la stessa ricetta, l'addestramento diventa instabile e la rete si adatta troppo ai dati di addestramento.
3. **La 4 × 256 sta al ginocchio fra precisione e costo.** Fra le architetture provate, l'unica migliore è la 6 × 256, di poco: −1,2% di perdita, costo 1,19% contro 1,26%, e nessuna differenza sulla scelta oltre il rumore. Non sono "differenze molto più grandi della variabilità del seme" e costano il 36% in più di tempo di previsione. **Il modello resta la 6b.**
4. **Nell'articolo, la variabilità del seme va dichiarata in due modi:**
   - piccola sugli errori (perdita ±0,6%, costo ±0,01 punti);
   - grande sulla scelta secca (14–16% di scelte non fattibili, p95 del rimpianto 3,4–4,0%).

   I numeri della scelta fra le 288 coppie vanno letti con questa incertezza.

**Una possibile frase per l'articolo** (da adattare):

> An ablation over depth (2–6 hidden layers of 256 units) and width (128–512 units, 4 layers), trained with the same recipe, shows that the 4 × 256 network lies at the knee of the accuracy–cost curve. Shallower or narrower networks increase the validation loss by 4–21% and the median cost error from 1.26% up to 1.64%. The 6-layer network reduces the validation loss by only 1.2%, comparable to the spread across three random seeds (1.2%), at a 36% higher inference cost. The 512-unit network overfits and stops early, without improving on the 256-unit one.

## Limiti

- Un solo seme per ogni variante: la soglia viene dai tre semi della sola 4 × 256, e si assume che la variabilità sia simile per le altre architetture.
- La ricetta di addestramento è quella del 6b, scelta per la 4 × 256. Le reti più grandi (4 × 512, forse 6 × 256) potrebbero guadagnare qualcosa con passo o pazienza adattati: è un confronto "a parità di ricetta", non "a parità di ottimizzazione".
- Tutto è misurato sulla validazione. Il test e le linee reali restano quelli della 6b (fase 12).
