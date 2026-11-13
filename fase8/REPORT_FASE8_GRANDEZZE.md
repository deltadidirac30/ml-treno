# Fase 8: le altre grandezze (passo 4 del surrogato)

13/11/2026. Tabella della fase 6, ricetta della fase 7. Julia 1.12.5, EvoTrees 0.19.0, 8 thread. Il test non è stato toccato.

## In breve

Per ogni grandezza:
- un obiettivo con la sua scala fisica;
- gradient boosting su tutto l'addestramento (12 288 tratte), con arresto anticipato sulla validazione;
- un confronto con la **mediana della coppia (m, n)** nell'addestramento, che vede m e n ma non la tratta.

Errori sulla validazione (2048 tratte mai viste):

| grandezza | obiettivo, righe | confronto semplice: mediana / p95 / max | **boosting: mediana / p95 / max** | boosting sulle tratte viste (mediana) |
|---|---|---|---|---|
| massa del serbatoio | kg per km, ibridi simulati | 19,8% / 78% / 1624% | **3,3% / 14,6% / 601%** | 2,8% |
| idrogeno consumato | kg per km, ibridi completati | 19,8% / 78% / 1622% | **3,4% / 14,5% / 562%** | 2,8% |
| SOC finale | valore (errore assoluto), tutti | 0,142 / 0,50 / 0,89 | **0,031 / 0,156 / 0,58** | 0,029 |
| scarica totale (sì/no) | classe, tutti | accuratezza 82,6% | **accuratezza 98,8%**, Brier 0,009 | 99,4% |
| vita della batteria (cicli) | logaritmo, tutti | 42% / 113% / 522% | **3,7% / 14,4% / 205%** | 3,0% |
| vita della fuel cell (`f1_ore`) | logaritmo, ibridi simulati | 14,4% / 83% / 495% | **2,5% / 8,3% / 44%** | 1,9% |
| C-rate di scarica | logaritmo, tutti | 0,42% / 15,0% / 99% | **0,68% / 4,3% / 85%** | 0,66% |

La durata (fase 7, modello E, sul rapporto) è a 0,25% / 1,3% / 4,9%.

**Vincoli e regole a posteriori dalle grandezze previste:**
- **SOC finale ≥ 0,2:** giusto nel 97,5% dei casi. Sbaglia 8481 casi dati fattibili ma sotto 0,2, e 6492 dati sotto ma fattibili, su 189 646 casi davvero sotto. Lontano dal limite (|SOC − 0,2| > 0,02) è giusto nel 98,2%.
- **Regola D3** (C-rate previsto > 20): **giusta nel 99,986% dei casi**. Su 12 255 scarti D3 veri ne perde 59 e ne aggiunge 22. Con il C-rate vero la regola sbaglierebbe già 54 casi (i D3 per l'altra condizione): l'errore del modello è quasi nullo.
- **Scarica:** 98,8% giusta, probabilità ben calibrate (`figure/fig_scarica_calibrazione.png`).

**Cosa ci dicono i numeri:**
1. **Il boosting aggiunge molto su tutte le grandezze:** errori 5–10 volte più piccoli del confronto semplice. Fa eccezione la mediana del C-rate, che dipende quasi solo da n e che la mediana della coppia indovina già.
2. **Tutte le grandezze arrivano al tetto di 3000 alberi.** L'errore sulle tratte viste è vicino a quello sulle nuove (per esempio 2,8% contro 3,3%). I modelli sono limitati dalla capacità, non dai dati: più alberi, eta più piccolo o alberi più profondi possono ancora migliorare.
3. **Qui l'errore dipende da m e n**, al contrario della durata: la parte costante nella tratta è tra l'1% (C-rate) e il 30% (vita FC). Queste grandezze cambiano a scatti in (m, n), soprattutto alle soglie D25 e al passaggio m = 0 → ibrido (fase 4, §3.8), e gli alberi seguono gli scatti solo in parte.
4. **Il SOC finale è la grandezza più difficile.** Ha valori accumulati a 0 (batteria scarica) e a 0,9 (massimo), e uno scalino visibile intorno a 0,3 (`figure/fig_previsto_vero.png`). Le previsioni escono anche dai limiti fisici (sotto 0 e sopra 0,9).
5. **Le tratte corte restano le più difficili** per serbatoio e idrogeno (6–7% di mediana sotto i 25 km, contro 2,7% sopra i 200 km). Per la vita della FC non c'è differenza.
6. **Le caratteristiche più usate:**
   - serbatoio e idrogeno: m (0,55), poi la densità delle fermate;
   - SOC: m, poi pendenza × velocità, n e lunghezza;
   - scarica: m, n, dislivello, lunghezza;
   - vita della batteria: n (0,55), lunghezza, m;
   - vita FC: durata minima (0,50), lunghezza, m;
   - C-rate: n (0,89).

## Come si rifà

```zsh
L=~/Documents/lavoro/ml_treno_dati/fase8_log; mkdir -p $L
julia -t 8 --project=fase8 fase8/01_grandezze.jl > $L/log_01.txt 2>&1     # ≈ 49 min (7 grandezze da circa 7 min)
julia -t 8 --project=fase8 fase8/01_grandezze.jl SOC_end vita_FC          # solo alcune grandezze
/bin/cp $L/log_01.txt $L/01_*.txt $L/01_*.csv fase8/risultati/; /bin/cp $L/fig_*.png fase8/figure/
```

Predizioni sulla validazione (`pred_<grandezza>.arrow`: vero, boosting, mediana della coppia) e modelli (`modello_<grandezza>.bson`) sono in `~/Documents/lavoro/ml_treno_dati/fase8/`.

**Impostazioni**, uguali per tutte: profondità 6, eta 0,1, 255 classi, 80% di righe e di caratteristiche, L2 = 1, fino a 3000 alberi, arresto dopo 50. Sulla durata questa combinazione era quasi pari alla migliore (fase 7, passo 3b) e più veloce.

**Obiettivi.** Gli obiettivi seguono la lezione della durata: una scala fisica dove c'è.
- **Per km** (÷ 2L): serbatoio e idrogeno, che crescono con la lunghezza.
- **Logaritmo:** vite e C-rate, che vanno su 2–5 ordini di grandezza.
- **Valore:** il SOC, già adimensionale.
- **Classe:** la scarica, dove serve solo sapere se è > 0, cioè la penalità.

**Righe:**
- **Serbatoio e vita FC:** solo m > 0. A m = 0 il serbatoio vale 0 e la vita FC è infinita, per definizione.
- **Idrogeno:** solo i completati, perché negli scartati il registro non lo salva.
- **Tutte le altre:** tutti i casi simulati, completati e scartati da D3.

## Un incidente

Il primo lancio è rimasto 20 minuti su un solo core, dentro la prima grandezza. Era un errore dello script: il valore di riserva del confronto semplice, la mediana di 3,1 milioni di valori, veniva ricalcolato per ognuna delle 524 288 righe di validazione. In più il ciclo principale, a livello di script, era interpretato invece che compilato.

L'ho fermato e corretto: riserva calcolata una volta sola, corpo del ciclo in una funzione, dati costanti. Il secondo lancio è quello dei risultati. Nessun risultato del primo lancio è stato usato.

## Da discutere

1. **Più capacità.** Tutti i modelli si fermano al tetto. Si può alzare a 6000–10 000 alberi, o usare eta 0,05 con alberi più profondi, sulle grandezze più importanti per il costo e i vincoli (SOC, serbatoio, idrogeno, vite). Costa circa 15–25 minuti a grandezza.
2. **SOC finale:**
   - limitare la previsione all'intervallo fisico [0; 0,9];
   - addestrarlo solo dove non c'è scarica: quando la batteria si scarica del tutto il progetto è comunque non fattibile, e lo dice già il classificatore della scarica.
3. **Scalini in m e n** (soglie D25, sola batteria contro ibrido). Una variabile in più che dica in quale fascia D25 cade m (0–4, già in `coppie.arrow`) può aiutare gli alberi a "vedere" gli scalini.
4. **Rete neurale.** Per il passo 5 (ottimo su una griglia fitta) servono previsioni lisce in (m, n) dentro ogni fascia. Gli alberi danno gradini: il confronto con una rete neurale resta da fare.
