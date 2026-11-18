Aggiorna la presentazione `ml_treno/presentazione_surrogato.html` (quella che mi hai fatto il 16/11) con le linee nuove. Prima di modificarla, salva una copia della versione attuale come `presentazione_surrogato_1611.html`. Non cambiare grafica, struttura e ordine delle slide: cambia solo i numeri, i dati dei grafici e le frasi indicate sotto.

## Cosa è cambiato

Un collega ha corretto le linee nel Drive condiviso SurrogateTrains (dati del 17/11/2026):
- nuova livellazione dell'altimetria;
- le 6 linee del bacino di Iseo ora finiscono a Brescia Borgo San Giovanni, 2,2 km prima di Brescia.

Fermate, limiti di velocità e lunghezze sono gli stessi. Ho rifatto tutto sulle 146 linee non elettrificate oltre il 70%:
- la griglia fitta simulata (ottimo vero);
- le 288 coppie per linea;
- tutte le strategie del surrogato;
- i dati per mappe e grafici.

Ora **tutti** i numeri della presentazione si possono prendere dai dati nuovi. Non devono restare numeri delle linee vecchie.

**Messaggio da aggiungere:** le correzioni spostano pochissimo gli ottimi.
- Il tipo di treno resta lo stesso in tutte le 146 linee: 99 sola batteria, 20 ibrido FC piccola, 27 ibrido.
- Stesso progetto (m, n) in 121 linee.
- Costo dell'ottimo: in mediana 0,00%, al più −1,6% (Sassari–Oristano).

Il surrogato si comporta come prima.

## Fonti (cartella `ml_treno/fase13/`)

- `presentazione_146/`: sostituisce `fase12/presentazione_146`, stesso formato (leggi il `LEGGIMI.md`):
  - `linee_146.csv` e `linee_146.geojson`: una riga o un tracciato per linea;
  - `heatmap_<linea>.csv`: Brescia–Iseo, Grosseto–Siena, Cagliari–Olbia;
  - `riassunto.txt`.

  Rigenera da questi file **tutti i dati incorporati nei grafici**: l'elenco delle linee con m, n, regime, kW, kWh; la mappa; le heatmap; il grafico per fascia di lunghezza.
- `risultati/08_ottimo_vero.txt`: tabella delle strategie contro l'ottimo vero. Per linea: `risultati/08_ottimo_vero_linee.csv`.
- `risultati/06_riassunto_non_el.txt`: errori della rete sulle 288 coppie (42 048 casi), sezione 2a.
- `risultati/02_griglia_fitta.txt`: ottimo nuovo contro vecchio.
- Il percorso della ricerca su Grosseto–Siena: `~/Documents/lavoro/ml_treno_dati/surrogato/Grosseto-Siena/candidati.csv`, colonna `origine`.
- Il diario: `ml_treno/STEPS/passi_surrogato.md`, sezione "Fase 13".

## Modifiche slide per slide (prima → adesso)

**4. "Perché serve un surrogato"**
- ~26 s per linea → **~24 s**;
- da 1,7 a 88 s → **da 1,6 a 85 s**;
- 63 min per le 146 linee → **58 min**.

**10. "Sulle 146 linee reali: rete contro simulatore, 42 048 casi"** (sezione 2a di `06_riassunto_non_el.txt`):
- mediana / 95° percentile / massimo per grandezza:

  | grandezza | mediana | 95° percentile | massimo |
  |---|---:|---:|---:|
  | durata | 0,36% | 1,28% | 3,50% |
  | serbatoio | 3,03% | 11,76% | 51,1% |
  | idrogeno | 2,98% | 10,98% | 49,2% |
  | vita batteria | 3,73% | 14,54% | 92,2% |
  | vita FC | 3,74% | 14,11% | 45,3% |
  | C-rate | 1,64% | 6,36% | 43,4% |
  | costo | 1,99% | 6,78% | 21,7% |

- SOC: mediana 0,014, 95° 0,096, massimo 0,48;
- errore di costo oltre il 10%: 1/100 → **1 su 90**; oltre il 20%: 1/25 000 → **1 su 25 730** (1 caso);
- "2,0% contro 1,24%" resta;
- distanza dall'addestramento: mediana 3,8 resta; 20 linee oltre 4,7 → **21**.

**13. "Ogni ingrediente di G toglie un modo di sbagliare"**
- G + bordo rispetto alla migliore delle 288: peggiore +0,25% → **+0,20%**, sempre 146/146 entro +1%;
- più economico della migliore delle 288 in 130 → **126** linee (fino a −15% resta);
- "+0,58% → +0,25%" → **"+0,45% → +0,20%"**;
- contro l'ottimo vero: "ottimo esatto da 127 a 141 linee, peggiore da +4,5% a +3,0%" → **"da 126 a 139 linee, peggiore da +4,6% a +3,1%"**.
- Se il grafico del caso peggiore per ingrediente usa i valori di fase12/13, aggiornalo con `risultati/07_verifica_locale.txt`.

**14. "La mossa lungo il bordo" (Grosseto–Siena)**
- la ricerca senza bordo si ferma ancora a (0,08; 0,91): +4,51% → **+4,58%**;
- arriva all'ottimo (0,06; 0,97) con **13** simulazioni lungo il bordo (prima 14), −4,3% → **−4,4%**;
- ricalcola i numeri della griglia disegnata (percentuali sopra l'ottimo) da `heatmap_Grosseto-Siena.csv`.

**15. "Risultati: il surrogato contro l'ottimo vero"**: sostituisci tutta la tabella con questa (da `08_ottimo_vero.txt`).

| | migliore 288 | semplice | C | G senza bordo | G + bordo |
|---|---:|---:|---:|---:|---:|
| scarto medio | +2,19% | +1,13% | +0,83% | +0,31% | +0,07% |
| scarto mediano | +0,23% | +0,29% | +0,18% | 0,00% | 0,00% |
| 90° percentile | +7,5% | +3,2% | +2,8% | +1,2% | 0,00% |
| caso peggiore | +18,0% | +13,0% | +7,0% | +4,6% | +3,1% |
| proprio l'ottimo | 20 | 14 | 33 | 126 | 139 |
| entro 1% / oltre 2% | 102 / 40 | 100 / 32 | 109 / 25 | 129 / 13 | 141 / 3 |

Nel testo della slide:
- "in 39 linee costano oltre il 2%" → **40**;
- "solo 4 progetti su circa 6800 fattibili entro lo 0,5%" resta vero;
- regime giusto: resta 144 su 146;
- le linee non all'ottimo passano da 5 a **7**: Olbia–Golfo Aranci +0,06%, Breno–Pisogne +0,05%, Cagliari–Macomer +1,01%, Cagliari–Olbia +1,12%, Buonconvento–Empoli +2,05%, Crotone–Lamezia +2,75%, Rovigo–Verona +3,08%.

**16. "Quanto tempo si risparmia"**
- ~26 s → **~24 s** per linea;
- "circa 130 volte" → **"circa 120 volte"**;
- 141 → **139** linee su 146;
- aggiorna anche le barre del grafico.

**17. "Il conto completo"**: simulatore ~26 s → **~24 s** per linea; ricalcola i tre scenari.

**21. "Simulatore e surrogato a confronto: la mappa dei costi"**
- le tre heatmap dai nuovi `heatmap_*.csv`;
- fattibilità giusta 98,3% resta, linea peggiore 92,1% → **92,0%**;
- progetti fattibili 948 642 → **948 792**;
- errore sul costo 1,9% → **2,0%** in mediana, 6,5% al 95° resta;
- nel progetto proposto 2,0% in mediana e massimo 16,3% restano.
- **Attenzione: su Cagliari–Olbia ora la proposta non coincide più con l'ottimo.** La proposta è (0,37; 0,75), 3,765 €/km; l'ottimo è (0,36; 0,69), 3,724 €/km, cioè +1,12%. Brescia–Iseo e Grosseto–Siena restano proposta = ottimo.

**22. "Cosa conviene, linea per linea"**
- tabella dei regimi:
  - sola batteria: costo 2,52 (1,52–4,34) → **2,52 (1,53–4,34)**;
  - ibrido: costo mediano 3,83 → **3,85**;
  - tutto il resto resta: 99|99, 18|20, 29|27, kW, kWh, lunghezze, 144 su 146.
- Il grafico dei punti e quello per fascia di lunghezza vanno rigenerati da `linee_146.csv`. Per fascia, sola batteria / FC piccola / ibrido:

  | fascia | linee | sola batteria | FC piccola | ibrido |
  |---|---:|---:|---:|---:|
  | 0–30 km | 30 | 30 | 0 | 0 |
  | 30–60 km | 48 | 48 | 0 | 0 |
  | 60–90 km | 27 | 19 | 7 | 1 |
  | 90–150 km | 25 | 2 | 11 | 12 |
  | oltre 150 km | 16 | 0 | 0 | 16 |

**23. "La mappa"**: rigenerala da `linee_146.geojson`.

**24. "Dove siamo e cosa manca"**
- nel riquadro "Deciso: non complicare oltre": Buonconvento–Empoli +2,05% · Crotone–Lamezia +2,75% · Rovigo–Verona +3,08% (G nel regime ibrido con m 0,12–0,15, l'ottimo ha la fuel cell più piccola di 0,03–0,04: resta vero);
- fra le cose fatte aggiungi: "linee corrette dal collega (17/11): ottimi quasi invariati, tutto rifatto sui dati nuovi";
- fra le cose aperte aggiungi: "classificazione degli ottimi in pochi treni standard (p-mediana sull'extra-costo medio)".

**25. "Verifica: 5 domande"**: controlla che le domande e le risposte non citino numeri cambiati, per esempio 141, 127, +3,0%, 26 s o 63 min.

Le slide 5–9, 11–12, 18–20 non dipendono dalle linee: lasciale come sono. Fanno eccezione i punti in cui citano numeri delle 146 linee che ho elencato sopra.

Alla fine dimmi quali numeri hai cambiato, slide per slide. Segnalami ogni altro punto che cita numeri delle 146 linee e che non è in questo elenco.
