# Fase 7: primo modello, la durata del viaggio (passo 3 del surrogato)

13/11/2026. Tabella della fase 6. Julia 1.12.5, EvoTrees 0.19.0, 8 thread. Il test non è stato toccato. Due esecuzioni danno numeri identici (il modello è deterministico con il seme).

**Cosa si impara:** la durata del viaggio di andata e ritorno, `y_durata_viaggio_s`, su tutti i casi simulati (completati e scartati da D3), dagli ingressi: le 66 caratteristiche della tratta più m e n.

## In breve

| modello | errore % mediano | p95 | p99 | massimo | errore medio [s] |
|---|---:|---:|---:|---:|---:|
| A: costante × durata minima teorica | 4,12 | 17,4 | 23,8 | 29,9 | 919 |
| B: lineare su durata minima, m, n | 4,25 | 29,2 | 70,7 | 137 | 866 |
| C: boosting, 2048 tratte di addestramento | 1,37 | 5,3 | 8,6 | 23,2 | 278 |
| **D: boosting, 12 288 tratte di addestramento** | **0,65** | **2,8** | **4,9** | **21,0** | **134** |
| rumore della durata (pavimento) | 0,010 | 0,048 | — | — | RMSE 3,5 |

Tutti gli errori sono misurati sulla validazione: 2048 tratte mai viste, 589 824 casi.

- **Il boosting aggiunge molto.** L'errore mediano passa dal 4% allo 0,65%, il p95 dal 17% al 2,8%.
- **Il numero di tratte conta più delle impostazioni.** Passando da 2048 a 12 288 tratte l'errore si dimezza. La scelta di profondità ed eta sposta molto meno.
- **Siamo lontani dal pavimento.** Il rumore della durata dentro la tratta è lo 0,01%, il modello sbaglia dello 0,65%: c'è margine per migliorare.
- **L'errore non dipende da m e n, ma dalla tratta.** È piatto in m e in n, e dentro una tratta è quasi costante: errore medio sulle 288 coppie 0,64% in mediana, errore massimo nella tratta 0,90%. Il modello impara bene l'effetto del peso del treno, e sbaglia la "durata di base" della tratta.
- **Le tratte corte sono le più difficili.** Sotto i 25 km l'errore mediano è il 2,1%, con un massimo del 21%; sopra i 200 km è lo 0,46%.
- **Velocità:** 8,7 µs a caso con 8 thread (circa 70 µs su un thread), contro i 25–50 ms di una simulazione.

## Come si rifà

```zsh
L=~/Documents/lavoro/ml_treno_dati/fase7_log; mkdir -p $L
julia -t 8 --project=fase7 fase7/01_durata.jl > $L/log_01.txt 2>&1     # ≈ 11 min
/bin/cp $L/log_01.txt $L/01_*.txt $L/01_*.csv fase7/risultati/; /bin/cp $L/fig_*.png fase7/figure/
```

Ambiente `fase7`: quello della fase 6 più EvoTrees 0.19.0, la stessa versione della fase 2.

Predizioni sulla validazione e modello D sono in `~/Documents/lavoro/ml_treno_dati/fase7/` (`durata_validazione.arrow`, `durata_D.bson`).

## Metodo

**Dati:**
- **Sviluppo:** gruppi 1 e 2 dell'addestramento (2048 tratte, 589 824 righe), per la griglia.
- **Addestramento completo:** 12 gruppi (12 288 tratte, 3 538 939 righe).
- **Validazione:** gruppi 7 e 12. Serve a fermare l'aggiunta di alberi e a scegliere le impostazioni.
- **Test:** gruppi 15 e 16, non usati.

**Modelli semplici** (stimati su tutto l'addestramento):
- A: durata = 1,0626 × `x_tempo_limiti_ar_s` (la durata minima teorica: ogni tratto al limite più le soste);
- B: minimi quadrati su [1, T, T·m, T·n, m, n], con T la durata minima teorica. m e n rappresentano il peso del treno.

**Boosting** (EvoTrees, perdita quadratica):
- valori fissi: 255 classi per gli istogrammi (così m e n non perdono risoluzione), 80% delle righe e 80% delle caratteristiche per albero, L2 = 1;
- fino a 4000 alberi, con arresto dopo 50 alberi senza miglioramenti sulla validazione;
- griglia: profondità 6, 8, 10 × eta 0,05 e 0,1.

**Rumore.** Per ogni tratta di validazione ho approssimato la durata con un polinomio di 2° grado in (m, n). Lo scarto è il rumore della dinamica a passo di 1 s (fase 4: la durata non è monotona con la massa), più la parte non quadratica.

## Risultati

**Griglia** sullo sviluppo (2048 tratte), errori sulla validazione:

| profondità | eta | alberi | tempo | RMSE [s] | errore % mediano | p95 |
|---:|---:|---:|---:|---:|---:|---:|
| **6** | **0,05** | 1216 | 23–29 s | **374** | **1,37** | **5,3** |
| 6 | 0,1 | 551 | 11 s | 457 | 1,69 | 6,6 |
| 8 | 0,05 | 644 | 20 s | 443 | 1,51 | 6,3 |
| 8 | 0,1 | 583 | 18 s | 544 | 1,92 | 7,5 |
| 10 | 0,05 | 520 | 25 s | 525 | 1,84 | 7,5 |
| 10 | 0,1 | 361 | 19 s | 622 | 2,12 | 9,3 |

- Alberi più bassi e passi più piccoli generalizzano meglio.
- La migliore è sul bordo della griglia: profondità 4 o eta 0,02 potrebbero fare ancora meglio.

**Addestramento completo** (profondità 6, eta 0,05): 3055 alberi in 6–7 minuti. La curva di apprendimento (`figure/fig_curve_apprendimento.png`) scende fino a circa 1500 alberi, poi quasi piatta.

**Sovradattamento.** Sulle tratte che ha visto, D sbaglia dello 0,135% in mediana; su quelle nuove dello 0,65%, cinque volte tanto. Il modello impara in parte le singole tratte. Il limite è generalizzare a tratte nuove, non adattarsi ai dati.

**Errore per lunghezza** (D):

| L | casi | mediana | p95 | max |
|---|---:|---:|---:|---:|
| 5–25 km | 40 032 | 2,06% | 7,1% | 21,0% |
| 25–50 km | 50 112 | 1,14% | 3,7% | 8,7% |
| 50–100 km | 99 648 | 0,78% | 2,7% | 5,5% |
| 100–200 km | 202 176 | 0,65% | 2,2% | 3,8% |
| 200–300 km | 197 856 | 0,46% | 1,7% | 5,0% |

Le 5 tratte con l'errore medio più alto sono tutte corte (5–21 km): 11849 (18%, 12 km), 11384 (14%, 6 km), 6665, 6537, 12009.

**Per regime:** sola batteria 0,65% mediana, p95 2,8%; ibride 0,65%, p95 2,8%. Nessuna differenza.

**Importanza** (guadagno):
- `x_tempo_limiti_ar_s` 0,77, `x_L_km` 0,15, `x_vlim_mean` 0,03, `x_n_fermate` 0,02, `x_dislivello_m` 0,01;
- le altre sotto 0,01;
- m e n hanno importanza piccola perché l'effetto del peso sulla durata è di pochi punti percentuali.

**Figure** (`figure/`):
- `fig_previsto_vero.png`: A a sinistra (le righe orizzontali sono le 288 coppie di una tratta: A non vede il peso), D a destra, sulla diagonale;
- `fig_errore_fasce.png`: errore di D contro lunghezza, m e n;
- `fig_distribuzione_errore.png`: quota dei casi sotto un certo errore, per i quattro modelli;
- `fig_curve_apprendimento.png`: errore sulla validazione contro il numero di alberi;
- `fig_importanza.png`: ridisegnata con `02_figura_importanza.jl` da `01_importanza.csv`, perché il primo disegno a barre aveva le etichette sull'asse sbagliato. Ora `01_durata.jl` usa lo stesso script.

## Da discutere

1. **L'errore è "di tratta".** Si può ridurre con un obiettivo più adatto agli alberi. Per esempio il rapporto durata / durata minima teorica (circa 1,06, dipende meno dalla scala): gli alberi devono imparare una correzione invece di tutta la durata, e l'errore relativo pesa uguale su tratte corte e lunghe. Oppure il logaritmo della durata.
2. **Le tratte corte** pesano poco nella perdita quadratica in secondi: per questo hanno l'errore relativo più alto. L'obiettivo relativo del punto 1 aiuterebbe anche qui.
3. **La griglia va allargata verso alberi più bassi e passi più piccoli** (profondità 4, eta 0,02), sui dati completi.
4. **Gradini in m e n.** Qui non si vedono, perché l'errore è piatto in m e n, ma vanno controllati quando cercheremo l'ottimo su una griglia fitta.
