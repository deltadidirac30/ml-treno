# Prompt per Cowork: aggiornare la presentazione con la classificazione dei treni

Copia tutto il testo sotto la riga e incollalo in Cowork.

---

Devi aggiornare la mia presentazione `ml_treno/presentazione_surrogato.html`, quella che mi hai fatto il 16/11 e aggiornato il 18/11. Ora si aggiunge una seconda parte: **la classificazione degli ottimi in pochi treni standard**.

La presentazione serve a me per **capire bene il lavoro fatto** e poi spiegarlo, anche nell'articolo. Quindi:
- spiega i concetti in parole semplici;
- usa **grafici interattivi** fatti con i dati veri (non disegni approssimativi);
- dove c'è un termine tecnico di ottimizzazione, aggiungi un riquadro "Termine" come i riquadri "Termine ML" già presenti.

Tieni lo stesso stile grafico, gli stessi colori, gli stessi componenti e la stessa navigazione della presentazione attuale. Scrivi in italiano, frasi brevi, senza gergo non spiegato.

## 0. Prima di iniziare

1. Salva una copia della versione attuale come `presentazione_surrogato_1811.html` e lavora sul file originale.
2. **Controllo della prima parte.** Il 18/11 le linee sono state corrette e tutti i numeri della prima parte rifatti. Le istruzioni sono in `ml_treno/STEPS/prompt_cowork_aggiorna_presentazione.md`, e la presentazione attuale le contiene solo in parte. Per esempio:
   - nella slide "Ogni ingrediente di G…" deve esserci "ottimo esatto da 126 a 139 linee, peggiore da +4,6% a +3,1%";
   - nella slide "Sulle 146 linee reali…" deve esserci "1 su 90" coppie con errore di costo oltre il 10%.

   Ripassa quel file slide per slide e correggi ogni numero rimasto vecchio. Alla fine dimmi cosa hai dovuto correggere.
3. Leggi questi file, nell'ordine:
   - `ml_treno/STEPS/passi_flotta.md`: il diario della classificazione, con decisioni, metodo, numeri e conclusioni di ogni passo. È la fonte principale per il testo;
   - `ml_treno/fase14/presentazione/LEGGIMI.md`: cosa c'è nei file di dati e cosa significa ogni colonna;
   - i dati per i grafici, in `ml_treno/fase14/presentazione/`: `curve.csv`, `flotte_scelte.csv`, `linee.csv`, `fasce.csv`, `modulari.csv`, `km_in_comune.csv`, `riduzione.csv`;
   - i tracciati delle linee per le mappe: `ml_treno/fase13/presentazione_146/linee_146.geojson`. I nomi delle linee coincidono con `linee.csv`;
   - le figure statiche di riferimento: `ml_treno/fase14/presentazione/fig_*.png`. Sono solo un riferimento: i grafici della presentazione vanno rifatti interattivi dai CSV;
   - per i dettagli: `ml_treno/fase14/risultati/*.txt` (riassunti di ogni passo) e gli script `ml_treno/fase14/0*.jl`.

**Regola sui numeri:** ogni numero nelle slide deve venire da questi file. Se trovi una differenza fra questo prompt e i file, vale il file e me lo segnali.

## 1. Il filo del racconto

La prima parte finisce con "un surrogato che trova l'ottimo di ogni linea". La seconda parte parte da lì:

> Oggi abbiamo **un treno diverso per ogni linea**: 146 linee, 97 progetti ottimi diversi. Nessun costruttore e nessun operatore può gestire 97 treni. Quanti treni standard bastano, e quanto si paga rispetto all'ottimo di ogni linea?

Poi le strade provate, una per una, ognuna con il suo grafico:
1. **fasce di m e n**, la prima idea;
2. **ottimizzazione diretta (p-mediana)**, senza e con tetto;
3. **treni modulari**;
4. **criterio geografico**.

Alla fine il confronto fra tutte, le flotte migliori e i limiti.

Metti la seconda parte dopo la slide "La mappa: dove serve l'idrogeno" e prima di "Dove siamo e cosa manca". Aggiungi una slide divisoria con il titolo della seconda parte e aggiorna l'eventuale indice.

## 2. Le slide da aggiungere (circa 15)

Per ogni slide: titolo, cosa dire, grafico e dati. Tutti i grafici interattivi: al passaggio del mouse mostrano i valori (nome della linea, m, n, kW, kWh, extra-costo). Le scale logaritmiche hanno tacche leggibili (1, 2, 3, 5, 10, 20, 50, 100%).

### 2.1 "Da 146 treni a pochi: il problema"
- **Testo:**
  - ogni linea ha il suo ottimo; i progetti ottimi diversi sono 97;
  - per tipo: 99 linee a sola batteria, 20 ibride con fuel cell piccola (m < 0,1), 27 ibride;
  - per produrre, omologare e mantenere i treni servono pochi modelli;
  - se una linea usa un treno che non è il suo ottimo, paga un **extra-costo**.
- **Grafico:** piano (m, n), un punto per linea nel suo ottimo (`linee.csv`: `ottimo_m`, `ottimo_n`), colorato per regime.
  - Asse x: m (taglia della fuel cell), con una seconda etichetta in kW (P_FC ≈ m × 1970 kW).
  - Asse y: n (taglia della batteria), con una seconda etichetta in kWh.
  - Molti punti cadono su m = 0: allargali un poco in orizzontale perché si vedano.
  - Al passaggio del mouse: linea, lunghezza, ottimo, costo €/km.

### 2.2 "Cos'è l'extra-costo"
- **Definizione:** extra-costo = costo del treno sulla linea ÷ costo del treno ottimo della linea − 1.
  - Il treno deve funzionare sulla linea (fattibile per il simulatore); se non funziona, quella linea non può usarlo.
  - Tutti i costi vengono dal simulatore (griglia fitta di 9702 progetti per linea), non dal surrogato: i numeri sono esatti.
- **Criterio scelto: l'extra-costo medio sulle 146 linee, con lo stesso peso per ogni linea.**
  - Peso uguale: nello studio ogni linea ha le stesse ipotesi di servizio, e i km/anno sono già nel costo €/km.
  - Dillo come una scelta fatta, con il motivo.
- **Grafico:** un esempio concreto. Scegli da `linee.csv` una linea a sola batteria corta (per esempio Adria–Rovigo) e mostra il suo extra-costo con il treno di ognuna delle flotte scelte (colonne `<flotta>_extra_pct`), come barre orizzontali. Si vede che lo stesso treno costa poco su una linea e molto su un'altra.

### 2.3 "Le strade provate"
- Uno schema (diagramma a blocchi o a schede) con le 4 strade:
  - **fasce:** si raggruppano gli ottimi per intervalli di m e n, un treno per fascia;
  - **p-mediana:** il computer sceglie i K treni migliori fra tutti;
  - **modulari:** si scelgono poche taglie di fuel cell e di batteria e si combinano;
  - **geografico:** linee che condividono binari usano lo stesso treno.
- Per ogni strada una riga con il risultato in breve; i numeri sono nelle slide seguenti.
- È la mappa del resto della parte.

### 2.4 "Prima di scegliere: tolgo i treni che non servono"
- **Testo:**
  - dalla griglia di 9702 progetti, 8631 funzionano su almeno una linea;
  - un treno è **dominato** se un altro funziona almeno sulle stesse linee e costa al più quanto lui su ognuna: non verrebbe mai scelto. Restano **1985 candidati**;
  - 2318 progetti funzionano su tutte le 146 linee, ma il migliore di loro, usato come treno unico, costa in media **+95%** (al peggio +180%). Un treno solo non basta.
- **Grafico:** imbuto o barre orizzontali da `riduzione.csv`.
- **Riquadro "Termine · dominanza".**

### 2.5 "La p-mediana: scegliere K treni in modo ottimo"
- **Testo, in parole semplici:**
  - si fissa K, il numero di treni della flotta;
  - il computer sceglie i K treni fra i 1985 candidati e assegna a ogni linea il treno della flotta che le costa meno;
  - fra tutte le flotte possibili tiene quella con l'extra-costo medio più basso;
  - è un problema di ottimizzazione lineare intera (MILP), risolto **in modo esatto** (non per tentativi) con JuMP + HiGHS, in pochi secondi per ogni K.
- **Grafico, uno schema piccolo e animato o a passi:**
  - 6 linee (punti) e 4 treni candidati (stelle) nel piano (m, n);
  - con K = 2 si accendono 2 stelle, ogni linea si collega alla stella che le costa meno, e si mostra la somma degli extra-costi;
  - si prova un'altra coppia di stelle e si vede che la somma cambia;
  - il computer trova la coppia migliore.
  - Può essere un esempio inventato, ma dichiaralo come "esempio".
- **Riquadri "Termine":**
  - **p-mediana**: viene dalla logistica, "dove aprire K magazzini per servire i clienti";
  - **MILP**: variabili sì/no ("questo treno è nella flotta?") più vincoli lineari;
  - **ottimo esatto**: il risolutore dimostra che non esiste una flotta migliore.

### 2.6 "Quanti treni servono? La curva"
- **Grafico principale** da `curve.csv`, strada `p-mediana`, variante `senza tetto`, K da 1 a 15:
  - extra-costo medio contro K, scala logaritmica;
  - a fianco (o con un interruttore) l'extra-costo della **linea peggiore** e il **numero di linee oltre il 10%**.
- **Numeri da evidenziare:**

  | K | medio | peggiore | linee oltre il 10% |
  |---:|---:|---:|---:|
  | 1 | +95% | +180% | 138 |
  | 2 | +17,1% | +101% | 43 |
  | 3 | +9,0% | +45% | 35 |
  | 5 | +4,7% | +21% | 20 |
  | 8 | +2,6% | +11,6% | 6 |
  | 10 | +1,9% | +11,6% | 3 |
  | 15 | +1,1% | +8,6% | 0 |

- **Messaggio:**
  - il grosso del guadagno arriva entro 5–6 treni; dopo l'ottavo, ogni treno in più vale meno di 0,3 punti;
  - guardare solo la media lascia qualche linea molto indietro: con 5–7 treni ci sono ancora 14–20 linee oltre il 10%, fino a +26%;
  - con 7 treni il caso peggiore è perfino più alto che con 6: la media scende, ma una linea viene sacrificata.

### 2.7 "Il tetto: nessuna linea troppo penalizzata"
- **Testo:**
  - si aggiunge un vincolo: nessuna linea può pagare più del +10% (o del +15%);
  - per il +10% servono **almeno 8 treni**, per il +15% almeno 6;
  - il tetto costa poco:

    | K | senza tetto | con tetto +10% |
    |---:|---:|---:|
    | 8 | +2,6% | +3,1% |
    | 10 | +1,9% | +2,0% |
    | 12 e oltre | uguale | uguale |

- **Grafico:** le tre curve (senza tetto, +15%, +10%) da `curve.csv`, medio e peggiore, con la soglia del 10% tratteggiata.
- **Riquadro "Termine · vincolo"**: la differenza fra ottimizzare la media e imporre un limite al caso peggiore.

### 2.8 "La flotta consigliata: 8 treni, nessuna linea oltre il +10%"
- **Testo:** extra-costo medio **+3,1%**, linea peggiore **+9,6%**. La flotta:
  - 2 treni a sola batteria (1779 e 3113 kWh) per 99 linee;
  - 2 ibridi con fuel cell piccola (98 e 177 kW, batteria ~3000 kWh) per 20 linee;
  - 4 ibridi (fuel cell 315, 413, 571, 827 kW; batteria da 2900 a 2160 kWh) per 27 linee.
- **Tabella** da `flotte_scelte.csv`, flotta `pm_K8_tetto10`:
  - colonne: treno, m, n, kW, kWh, linee servite, extra-costo medio e peggiore, linea peggiore;
  - colora ogni riga con il colore del treno usato nei grafici.
- **Grafico 1:** piano (m, n) con gli ottimi delle linee colorati secondo il treno assegnato, e i treni della flotta come stelle grandi dello stesso colore. Dati: `linee.csv` (`pm_K8_tetto10_m`, `pm_K8_tetto10_n`) e `flotte_scelte.csv`.
- **Grafico 2:** la mappa delle 146 linee (`linee_146.geojson`) colorate secondo il treno, con legenda; al passaggio del mouse: linea, treno, extra-costo.
- **Interattività:** un selettore della flotta (K = 3, 5, 8, 8 con tetto, 15, colonne `pm_*` di `linee.csv`) che aggiorna insieme piano, mappa e tabella. Fa vedere come la flotta si divide al crescere di K.
- **Da far notare:**
  - le linee a batteria si dividono solo per taglia di batteria;
  - gli ibridi stanno lungo una **curva** che va da "fuel cell piccola + batteria piena" a "fuel cell grande + batteria più piccola", e i treni della flotta si dispongono lungo questa curva;
  - il treno ibrido più grande (m 0,42, n 0,68: 827 kW, 2161 kWh) c'è in quasi tutte le flotte.

### 2.9 "Le fasce: la prima idea, messa alla prova"
- **Testo:**
  - le linee si dividono in fasce secondo il loro ottimo: in m per regime (sola batteria, FC piccola, ibrido) e poi a passi Δm; in n a passi Δn;
  - per ogni fascia si prende il treno migliore fra quelli che funzionano su **tutte** le linee della fascia: è la versione più favorevole possibile del metodo;
  - provati 22 schemi.
- **Grafico:** extra-costo medio contro K, linea della p-mediana più tutti gli schemi a fasce come punti (`fasce.csv` o `curve.csv` con strada = `fasce`); al passaggio del mouse lo schema (Δm, Δn). Un secondo pannello con la linea peggiore.
- **Numeri:**

  | K | fasce migliori | p-mediana | quanto costano in più le fasce |
  |---:|---:|---:|---|
  | 3 | +9,1% | +9,0% | uguale |
  | 5 | +5,0% | +4,7% | uguale |
  | 6 | +4,2% | +3,9% | 1,1 volte |
  | 8 | +3,4% | +2,6% | 1,3 volte |
  | 10 | +3,0% | +1,9% | 1,6 volte |
  | 13 | +2,5% | +1,3% | 1,9 volte |

- **Messaggio:**
  - con pochi treni le fasce vanno bene: con 3 fasce "per regime" si ottiene quasi la flotta della p-mediana;
  - con più treni perdono: i confini delle fasce sono arbitrari (due ottimi vicini ai due lati del confine prendono treni diversi) e una fascia larga deve accontentare la linea più esigente;
  - con le fasce la linea peggiore non scende mai sotto il +21%: **nessuno schema a fasce rispetta il tetto del +10%**;
  - lasciare a ogni linea la scelta libera fra i treni delle fasce migliora al più di 0,2 punti: il problema sono i treni scelti, non l'assegnazione.

### 2.10 "Treni modulari: poche taglie di componenti"
- **Testo:**
  - invece di K coppie libere si sceglie un catalogo di **a taglie di fuel cell** e **b taglie di batteria**; i treni possibili sono tutte le combinazioni, più quelli senza fuel cell;
  - ogni linea usa la combinazione che le costa meno;
  - stesso metodo esatto.
- **Grafico** con due pannelli affiancati, stessa scala y (extra-costo medio), dati da `curve.csv`:
  - **sinistra**, x = numero di treni diversi: p-mediana contro modulari. I modulari stanno sopra, costano circa il doppio;
  - **destra**, x = numero di taglie di componenti (colonna `taglie_componenti`): p-mediana contro modulari. I modulari stanno sotto.

  È la slide chiave di questa strada: il giudizio dipende da cosa si conta.
- **Numeri a parità di taglie:**

  | taglie | p-mediana libera | modulare |
  |---:|---:|---:|
  | 6 | +6,9% (4 treni) | +5,2% (3 FC × 3 batterie) |
  | 8 | +4,7% (5 treni) | +3,7% (3 × 5) |
  | 9 | +3,9% (6 treni) | +2,8% (4 × 5) |

- **Con il tetto +10%:**
  - il catalogo minimo è **6 fuel cell × 5 batterie** (11 taglie, 16 versioni di treno usate): medio +2,8%, peggiore +10,0%;
  - la flotta consigliata della p-mediana usa invece 8 versioni ma 14 taglie (6 FC e 8 batterie): +3,1%.
- **Messaggio:**
  - se costa di più omologare e gestire tante **versioni di treno**, conviene la flotta libera;
  - se costa di più produrre e tenere a magazzino tante **taglie di componenti**, conviene il catalogo modulare;
  - una sola taglia di fuel cell non basta (alcune linee pagano +90–100%): ne servono almeno 2–3, una piccola (60–220 kW, "range extender") e una o due grandi (500–890 kW).
- **Tabella piccola** con il catalogo minimo per tetto: +10% → 6 × 5; +15% → 5 × 3; +20% → 4 × 3 (da `modulari.csv`).

### 2.11 "Il criterio geografico: linee che condividono i binari"
- **Testo:**
  - regola: due linee che hanno in comune almeno il 25% della lunghezza della più lunga devono usare lo stesso treno;
  - i km in comune vengono dalle sezioni RINF (ogni sezione va da una località a un'altra, con un codice): 346 coppie di linee condividono qualche sezione, 270 oltre il 25%, 128 oltre il 50%.
- **Il punto chiave, la transitività:** se A deve avere il treno di B e B quello di C, anche A e C hanno lo stesso treno. Le linee si uniscono in **gruppi**:
  - al 25%: 40 gruppi;
  - il più grande è tutta la Sardegna, 18 linee da 8 a 276 km (8 ottimi a batteria e 8 ibridi);
  - poi il Sud-Est siciliano (12), il bacino di Iseo (11), Siena–Empoli–Chiusi (11), Lecco–Monza (10).
- **Grafico 1:** mappa con le linee colorate per **gruppo** (`gruppo_geo25` di `linee.csv`); i gruppi con una sola linea in grigio; selettore 25% / 50%.
- **Grafico 2:** la curva extra-costo medio contro K per "senza criterio", "≥ 50%", "≥ 25%" (da `curve.csv`).
- **Numeri:**

  | | 5 treni | 8 treni | 15 treni | un treno per gruppo (minimo possibile) |
  |---|---:|---:|---:|---:|
  | senza criterio | +4,7% | +2,6% | +1,1% | — |
  | ≥ 50% | +19,0% | +16,8% | +15,2% | +14,6% |
  | ≥ 25% | +31,6% | +29,3% | +27,6% | +27,2% |

  Nessun tetto (+10%, +15%, +20%) è rispettabile.
- **Esempio:** Porto Torres–Sassari (19 km) deve usare l'ibrido da 827 kW delle linee lunghe sarde e paga **+152%**.
- **Messaggio:**
  - il costo viene dai gruppi stessi, non dal numero di treni;
  - così com'è, il vincolo è troppo forte, perché mette insieme linee corte, che vorrebbero la sola batteria, e linee lunghe, che vorrebbero un ibrido grande;
  - versioni più morbide possibili (non provate): al più 2 tipi di treno per gruppo, soglia alta solo per servizi quasi identici, criterio come penalità invece che come vincolo.
- **Riquadro "Termine · transitività".**

### 2.12 "Tutte le strade a confronto"
- **Grafico riassuntivo:** extra-costo medio contro numero di treni con tutte le strade insieme (p-mediana senza tetto, con tetto +10%, fasce migliori, modulari, geografico 25% e 50%), colori distinti e legenda cliccabile per accendere e spegnere le serie.
- **Tabella finale:**

  | strada | treni | taglie | medio | peggiore | giudizio |
  |---|---:|---:|---:|---:|---|
  | p-mediana senza tetto, K = 5 | 5 | 8 | +4,7% | +21% | la più semplice con un buon medio, ma alcune linee penalizzate |
  | **p-mediana con tetto +10%, K = 8** | 8 | 14 | **+3,1%** | **+9,6%** | **consigliata**: nessuna linea oltre il 10% |
  | p-mediana senza tetto, K = 15 | 15 | 20 | +1,1% | +8,6% | quasi l'ottimo, ma troppi treni |
  | fasce (Δm 0,1, Δn 0,34), K = 8 | 8 | 12 | +3,4% | +21% | buona solo con pochi treni |
  | modulare 6 × 5, tetto +10% | 16 | 11 | +2,8% | +10,0% | la migliore se contano le taglie di componenti |
  | geografico ≥ 25%, K = 8 | 8 | 14 | +29% | +152% | troppo vincolante così com'è |

  Verifica le taglie di ogni riga in `curve.csv`.

### 2.13 "Limiti e domande aperte"
- **Il serbatoio:** il simulatore lo dimensiona linea per linea. Per lo stesso treno ibrido, sulla linea più esigente è in mediana 56 volte quello sulla linea più leggera. Oggi il costo assume un serbatoio adattato alla linea (pacchi di bombole montati secondo il servizio). Con un serbatoio fisso (il più grande delle linee servite) i costi sulle linee corte salirebbero, e servirebbero nuove simulazioni.
- **Cosa conta di più:** versioni di treno oppure taglie di componenti? Decide quale flotta scegliere.
- **Il criterio geografico morbido** non è ancora provato.
- **Il peso:** uguale per ogni linea. Un peso per traffico (treni-km) cambierebbe le flotte; non è usato per scelta.

### 2.14 "Cosa ho imparato" (lezioni della seconda parte, come la slide "Lezioni imparate" della prima)
- Il metodo intuitivo (fasce) va bene finché i treni sono pochi; poi conviene ottimizzare direttamente.
- Guardare la media non basta: serve un vincolo sul caso peggiore, e costa poco.
- Il numero di "treni" dipende da cosa si conta: versioni o componenti.
- Un vincolo che sembra ragionevole (stesso treno sui binari in comune) può diventare fortissimo per transitività: va controllato con i numeri prima di adottarlo.

## 3. Slide da modificare

- **"Dove siamo e cosa manca":**
  - fra le cose fatte: le linee corrette (17/11) e la classificazione (fase 14) con la flotta consigliata;
  - fra le cose aperte: serbatoio fisso o adattato, versioni o componenti, criterio geografico morbido, l'articolo.
- **"Verifica: 5 domande":** aggiungi 3–4 domande sulla seconda parte. Per esempio:
  - perché con le fasce il caso peggiore non scende sotto il +21%?
  - perché il criterio geografico costa così tanto?
  - quanti treni servono per tenere ogni linea entro il +10%?
  - quando conviene il catalogo modulare?

  Con la risposta e la spiegazione, come le domande esistenti.
- **Slide del titolo:** sottotitolo che comprenda le due parti, cioè il surrogato e la flotta.

## 4. Come lavorare e cosa consegnare

- Tutti i grafici in SVG (o canvas) generati dai dati dei CSV incorporati nel file HTML, come quelli che ci sono già: il file deve funzionare da solo, senza caricare file esterni.
- Le mappe usano lo stesso disegno della mappa esistente.
- Colori:
  - i colori dei treni restano gli stessi in tutti i grafici di una stessa flotta;
  - le strade hanno colori fissi in tutta la seconda parte: p-mediana nero, tetto +10% rosso scuro, tetto +15% arancio, fasce blu, modulari verde, geografico viola.
- Ogni slide ha in piccolo la fonte dei dati (nome del file).
- Controlla che il file si apra senza errori nella console e che la navigazione funzioni dalla prima all'ultima slide.

**Alla fine dimmi:**
1. quali numeri della prima parte hai corretto (punto 0.2);
2. l'elenco delle slide nuove e modificate;
3. ogni numero che non tornava fra questo prompt e i file;
4. eventuali dati che ti sono mancati per un grafico.
