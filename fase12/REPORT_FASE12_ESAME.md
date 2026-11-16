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
