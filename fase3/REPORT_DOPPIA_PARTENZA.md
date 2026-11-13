# Doppia partenza: validazione sulle 1024 tratte DoE v2

Data: 2026-10-11. La regola è nata guardando Firenze, quindi la valido solo sul DoE. Le tratte reali non sono state toccate.

**Impostazione.**
- **Previsioni:** gb della ripetizione 1, CV con gli stessi fold della fase 2bis (`fold_esterni`), con 69 e con 66 caratteristiche. Rimpianto contro il riferimento v2.
- **Lanci NOMAD-PB:** impostazioni della fase 2bis, ciascun lancio separato e cronometrato, processi a un thread, 8 in parallelo. Script `04_doppia_partenza.jl`, metriche `05_metriche_doppia.jl`.

**Le tre strategie a confronto:**
- **singola 200:** 200 valutazioni dal punto previsto, su tutte le tratte.
- **doppia 200+200:** nelle tratte incerte (p_ibrido tra le soglie) anche 200 valutazioni dal punto previsto dall'altro ramo, e si tiene il migliore.
  - Se il previsto è ibrido, l'altro ramo parte da (0; n̂ sola batteria).
  - Altrimenti parte da (clamp(m̂, 0,03); n̂ ibride).
- **doppia 100+100:** nelle tratte incerte 100 valutazioni per ramo, cioè lo stesso budget della singola. Altrove singola 200.

**Controllo.** La singola 200 di p69 rifatta coincide con quella della fase 2bis in 1024 tratte su 1024.

**Volume del calcolo:** 2381 lanci e 405 246 valutazioni, in 19 minuti.

## Risultati (soglia 0,1–0,9; le altre soglie nel § "Soglie")

| insieme | strategia | categoria | tratte | non fattibili | errore di regime | rimpianto mediana | p95 | max | entro 0,25% | valutazioni per tratta | secondi per tratta |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| p69 | singola 200 | totale | 1024 | 0,1% | 0,6% | 0,018% | 0,77% | 11,1% | 90,4% | 179 | 4,00 |
| p69 | doppia 200+200 | totale | 1024 | **0,0%** | **0,3%** | 0,018% | 0,72% | 10,8% | 91,0% | 183 | 4,06 |
| p69 | doppia 100+100 | totale | 1024 | 0,0% | 0,4% | 0,018% | 0,73% | 10,8% | 90,6% | 179 | 4,00 |
| p69 | singola 200 | vicino a m_min | 62 | 1,6% | 1,6% | 0,104% | 0,30% | 0,58% | 90,3% | 191 | 3,21 |
| p69 | doppia 200+200 | vicino a m_min | 62 | **0,0%** | **0,0%** | 0,097% | **0,19%** | 0,46% | **96,8%** | 224 | 3,75 |
| p69 | doppia 100+100 | vicino a m_min | 62 | 0,0% | 0,0% | 0,106% | 0,29% | 0,46% | 91,9% | 190 | 3,23 |
| p69 | singola 200 | incerte (attivate) | 23 | 4,3% | 13,0% | 0,056% | 7,39% | 11,1% | 73,9% | 178 | 3,13 |
| p69 | doppia 200+200 | incerte (attivate) | 23 | **0,0%** | **0,0%** | 0,001% | **0,13%** | **0,15%** | **100%** | 356 | 6,13 |
| p69 | doppia 100+100 | incerte (attivate) | 23 | 0,0% | 4,3% | 0,077% | 0,45% | 7,8% | 82,6% | 177 | 3,12 |
| p66 | singola 200 | totale | 1024 | 0,3% | 1,2% | 0,022% | 1,25% | 14,7% | 89,4% | 179 | 3,86 |
| p66 | doppia 200+200 | totale | 1024 | 0,3% | **0,7%** | 0,021% | **0,73%** | 14,7% | 89,9% | 188 | 4,03 |
| p66 | doppia 100+100 | totale | 1024 | 0,3% | 0,7% | 0,023% | 0,78% | 14,7% | 89,0% | 179 | 3,85 |
| p66 | singola 200 | vicino a m_min | 62 | 1,6% | 1,6% | 0,062% | 0,21% | 0,29% | 95,2% | 191 | 3,25 |
| p66 | doppia 200+200 | vicino a m_min | 62 | 1,6% | 1,6% | 0,059% | 0,19% | 0,29% | 96,8% | 249 | 4,22 |
| p66 | doppia 100+100 | vicino a m_min | 62 | 1,6% | 1,6% | 0,118% | 0,34% | 0,65% | 85,5% | 191 | 3,27 |
| p66 | singola 200 | incerte (attivate) | 55 | 0,0% | 14,5% | 0,031% | 10,8% | 12,5% | 83,6% | 175 | 3,16 |
| p66 | doppia 200+200 | incerte (attivate) | 55 | 0,0% | **5,5%** | 0,013% | **2,5%** | 10,8% | **94,5%** | 348 | 6,50 |
| p66 | doppia 100+100 | incerte (attivate) | 55 | 0,0% | 5,5% | 0,090% | 5,0% | 11,0% | 76,4% | 174 | 3,13 |

- Il rimpianto è calcolato sui progetti fattibili.
- "Entro 0,25%" vuol dire fattibile e con rimpianto ≤ 0,25%, sul totale delle tratte.
- "Vicino a m_min" sono le ibride v2 con m\* < 0,04.

## Soglie

| insieme | soglia | tratte attivate | totale: errore di regime | totale: p95 | totale: entro 0,25% | m_min: non fattibili / entro 0,25% | incerte: entro 0,25% (singola → doppia) | valutazioni per tratta |
|---|---|---:|---:|---:|---:|---|---|---:|
| p69 | 0,05–0,95 | 35 | 0,3% | 0,72% | 91,0% | 0% / 96,8% | 80,0% → 97,1% | 185 |
| p69 | 0,1–0,9 | 23 | 0,3% | 0,72% | 91,0% | 0% / 96,8% | 73,9% → 100% | 183 |
| p69 | 0,2–0,8 | 14 | 0,4% | 0,72% | 90,8% | 1,6% / 93,5% | 71,4% → 100% | 181 |
| p66 | 0,05–0,95 | 76 | 0,6% | 0,73% | 90,1% | 0% / 98,4% | 85,5% → 96,1% | 192 |
| p66 | 0,1–0,9 | 55 | 0,7% | 0,73% | 89,9% | 1,6% / 96,8% | 83,6% → 94,5% | 188 |
| p66 | 0,2–0,8 | 29 | 0,7% | 0,73% | 89,8% | 1,6% / 95,2% | 75,9% → 93,1% | 184 |

Tutti i valori sono della doppia 200+200; con la singola 200 il totale è quello della tabella precedente (p69: 0,6% / 0,77% / 90,4%; p66: 1,2% / 1,25% / 89,4%).

## Costo, confrontato con la campagna NOMAD-PB completa

| | valutazioni per tratta | secondi per tratta |
|---|---:|---:|
| singola 200 | 179 | 4,0 |
| doppia 200+200, p69 0,1–0,9 | 183 | 4,1 |
| doppia 200+200, p66 0,05–0,95 | 192 | 4,1 |
| campagna NOMAD-PB (`conclusi.csv`; 1000 di budget) | 972 | 16,5 come somma dei tempi di valutazione (`registro.csv`); 28,2 come tempo di parete (3608 s × 8 processi / 1024) |

**Le due colonne dei secondi non si misurano allo stesso modo.**
- I miei secondi includono il costo di NOMAD: 21,9 ms per valutazione.
- I 16,5 s della campagna sono solo il tempo delle valutazioni: 17,0 ms ciascuna.
- Il confronto più pulito è sulle valutazioni: il surrogato con la doppia partenza ne usa circa 5,3 volte meno della campagna.

## Lettura

1. **La doppia partenza corregge i guasti grossolani nelle tratte incerte.**
   - p69, soglia 0,1–0,9: le 23 tratte attivate passano da 74% a 100% entro lo 0,25%; errore di regime da 13% a 0, p95 da 7,4% a 0,13%, nessun non fattibile.
   - Vicino a m_min (p69): da 90% a 97% entro lo 0,25%, regime e fattibilità perfetti.
   - Sul totale l'effetto è piccolo, perché le tratte attivate sono il 2–7%. Costa +2–7% di valutazioni medie.
2. **Il miglioramento viene dalla seconda partenza, non dal budget in più.** A parità di budget (100+100), nelle tratte attivate spariscono comunque i non fattibili e la coda si accorcia (p69: p95 da 7,4% a 0,45%). Con soli 100 per ramo però la convergenza fine si perde: mediana 0,08% contro 0,001%, entro lo 0,25% 83% contro 100%. Servono tutti e due: la seconda partenza per il regime, il budget pieno per la precisione.
3. **Soglia:** propongo 0,05–0,95.
   - Con p69, 0,1–0,9 e 0,05–0,95 danno lo stesso totale.
   - Con p66, solo 0,05–0,95 elimina i non fattibili vicino a m_min, con 192 valutazioni medie invece di 188.
   - 0,2–0,8 lascia fuori casi a m_min in tutti e due gli insiemi.
   - Attenzione: soglia e regola sono scelte sulle stesse previsioni su cui le misuro. Va confermata su un insieme nuovo (le 256 tratte, quando le faremo) o su un'altra ripetizione della CV.
4. **Cosa resta nella coda** (p69, max 10,8%): non dipende dal classificatore incerto.
   - **Tratte a sola batteria in cui NOMAD finisce ibrido a m = 0,03 anche partendo dalla sola batteria** (893, 134, 580). La finestra fattibile in n è stretta: la ricerca esce verso m = 0,03 e non torna.
   - **Isole a sinistra di D20 con classificatore sicuro** (259, 989, 533, 443).
   - **p66:** due tratte restano non fattibili.
     - **548:** il classificatore è sicuro e sbagliato (p 0,015; il vero è ibrido a m 0,081).
     - **342:** il regime è giusto (p 0,999), ma la rifinitura scivola a m = 0.

   Per questi casi la seconda partenza non serve; servirebbe un'altra regola, per esempio una partenza fissa a sinistra di D20 come P1 della v2. Non l'ho provata.
5. **Firenze**, lato reale: la regola non è stata scelta né misurata lì. Con soglia 0,05–0,95 si attiverebbe (p_ibrido 0,25 con p69), ma con p66 (0,004) no.

**File.**
- in `fase3/`: `04_doppia_partenza.jl`, `05_metriche_doppia.jl`;
- in `fase3/risultati/`: `doppia_lanci.csv` (tutti i 2381 lanci), `doppia_metriche.csv` e `.txt`;
- fuori da Drive: un file per tratta in `~/Documents/lavoro/ml_treno_dati/fase3/doppia/`.
