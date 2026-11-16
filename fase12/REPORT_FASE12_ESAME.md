# Fase 12: l'esame finale (passo 8 del surrogato)

## Piano, fissato prima di guardare il test (16/11/2026)

Il test (gruppi Sobol 15 e 16, 2048 tratte, 589 760 casi) non è mai stato usato: né per addestrare, né per scegliere impostazioni, margini o strategie. Si guarda **una volta sola**, con quello che è stato deciso sulla validazione.

**Modello:** la rete neurale `rete_6b.jld2` (fase 10, passo 6b: 8 teste, 4 × 256, 40 epoche). Nessun riaddestramento. Il boosting delle fasi 7–8 solo come confronto.

**Regole:** il banco di prova della fase 9 (`valuta`), con D3 dalla regola C-rate > 20. Credito della ricarica e vita della batteria come nel simulatore (decisioni del 13/11).

**Cosa si misura sul test (8a):**
1. errori per grandezza (come i passi 4 e 6b), rete e boosting;
2. fattibilità e costo caso per caso (come 5a e 6c);
3. scelta fra le 288 coppie di ogni tratta (come 5b e 6c): scelta secca e verifica delle prime 3 e 5, senza margini. La tratta 14664 è esclusa da questo confronto (decisione del 13/11: 64 coppie su 288 in errore nel simulatore);
4. griglia fitta con verifica al simulatore (come 5c e 6d) su 256 tratte del test scelte a caso con seme fisso (20261117), escludendo la 14664. Due varianti, come nel 6d:
   - senza margini;
   - con il margine piccolo (SOC ≥ 0,21, scarica < 0,1).

**Strategie di riferimento, decise sulla validazione:**
- **fra le 288 coppie:** rete + verifica delle 5 migliori, senza margini (validazione: 0,1% di scelte non fattibili, rimpianto p95 2,3%, 90% delle tratte entro l'1%);
- **sulla griglia fitta:** rete + margine piccolo + verifica delle 5 migliori (validazione: 1,6% non fattibili, mediana −0,21% rispetto alla migliore delle 288, p95 +1,7%).

Il test conferma il surrogato se i suoi numeri sono vicini a quelli della validazione.

**Poi:** 8b, tratte reali (Calabria, Canavese, Firenze), con riferimento la griglia fitta simulata per intero; 8c, le 166 linee della rete (versione del 10/11, quella su cui è stato rivisto il DoE), con riferimento la migliore delle 288 coppie simulate.

## Passo 8a: il test (`01_test.jl`, `risultati/01_test.txt`, `01_griglia_tratte.csv`)

Comando: `julia -t 8 --project=fase12 fase12/01_test.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_01.txt 2>&1` (≈ 1,2 min). Eseguito una volta, il 16/11/2026 alle 14:03, dopo il commit del piano (50e5132, 14:02). Tra parentesi i valori sulla validazione.

**Collaudo.** Sul test le grandezze vere ridanno la fattibilità del simulatore in 589 760 casi su 589 760.

**Errori per grandezza** (mediana / p95):

| grandezza | rete: test (validazione) | boosting: test |
|---|---|---|
| durata | 0,161% / 0,82% (0,159% / 0,89%) | 0,251% / 1,22% |
| serbatoio | 1,67% / 8,2% (1,70% / 8,8%) | 3,32% / 13,8% |
| idrogeno | 1,65% / 7,9% (1,68% / 8,5%) | 3,32% / 13,7% |
| SOC finale (assoluto) | 0,012 / 0,106 (0,012 / 0,108) | 0,029 / 0,156 |
| vita della batteria | 2,36% / 10,9% (2,36% / 10,8%) | 3,68% / 14,5% |
| vita della FC | 1,76% / 6,6% (1,73% / 6,5%) | 2,55% / 8,4% |
| C-rate | 1,23% / 5,0% (1,24% / 4,9%) | 0,67% / 4,3% |
| scarica (giusta) | 98,97% (99,00%) | 98,77% |

**Fattibilità e costo:**
- rete: fattibilità giusta 98,83% (98,86%), costo 1,24% / 4,87% (1,26% / 5,21%);
- boosting: 98,07%, costo 2,38% / 9,52%.

**Scelta fra le 288 coppie** (2047 tratte, senza la 14664):

| | non fattibili | rimpianto mediano | p95 | entro l'1% |
|---|---:|---:|---:|---:|
| rete, scelta secca | 16,7% (14,4%) | 0,00% (0,00%) | 4,1% (4,0%) | 67,1% (70,4%) |
| rete, verifica delle prime 3 | 0,98% (1,03%) | 0,00% | 3,4% (2,8%) | 85,6% (86,8%) |
| **rete, verifica delle prime 5** (riferimento) | **0,34% (0,10%)** | **0,00%** | **3,3% (2,3%)** | **88,5% (90,2%)** |
| boosting, scelta secca | 21,4% (18,2%) | 0,89% (1,01%) | 15,4% (14,7%) | 40,6% (40,7%) |
| boosting, verifica delle prime 5 | 0,73% (0,29%) | 0,00% (0,09%) | 12,4% (12,7%) | 66,0% (65,3%) |

**Griglia fitta con verifica al simulatore** (256 tratte, 2163 simulazioni; rispetto alla migliore delle 288):

| | non fattibili | mediana | p10 | p95 | più economica della migliore delle 288 | entro +1% |
|---|---:|---:|---:|---:|---:|---:|
| scelta secca, senza margini | 38,7% (41,0%) | −0,94% | −6,5% | +1,6% | 44,1% (37,1%) | 56,2% |
| verifica delle prime 5, senza margini | 7,0% (6,2%) | −0,77% | −6,6% | +1,4% | 67,6% (62,1%) | 85,2% |
| scelta secca, margine piccolo | 20,3% (18,0%) | −0,56% | −6,7% | +2,3% | 48,0% (48,0%) | 71,1% |
| **margine + verifica delle prime 5** (riferimento) | **1,6% (1,6%)** | **−0,55% (−0,21%)** | **−6,8%** | **+1,9% (+1,7%)** | **65,6% (60,9%)** | **90,2% (88,7%)** |

**Esito.** Il test conferma la validazione: errori per grandezza uguali entro pochi centesimi, fattibilità e costo uguali, scelte praticamente uguali. Le differenze sono quelle attese fra due campioni di 2048 tratte, in alcuni casi a favore del test (griglia), in altri della validazione (scelta fra le 288: non fattibili 0,34% contro 0,10%, p95 3,3% contro 2,3%). Il surrogato non è stato "aggiustato" sulla validazione.

**La strategia sulla griglia** (rete + margine piccolo + verifica di 5 progetti al simulatore), sul test:
- progetto fattibile nel 98,4% delle tratte;
- in 2 tratte su 3 trova un progetto più economico della migliore delle 288 coppie della campagna: −0,55% in mediana, −6,8% o meglio in una tratta su dieci;
- nel 90% delle tratte è entro l'1% dalla migliore delle 288 o meglio.
