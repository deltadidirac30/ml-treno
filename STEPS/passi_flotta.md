# Diario: dai 146 ottimi a pochi treni standard (fase 14)

Obiettivo: oggi ogni linea ha il suo treno ottimo (146 linee non elettrificate oltre il 70%, 97 progetti diversi). Si vuole un numero realistico di treni standard: ogni linea usa uno dei treni della flotta, il più economico fra quelli che funzionano su di essa, e paga un **extra-costo** rispetto al suo ottimo.

## Decisioni (17–18/11/2026)

- **Metodo: ottimizzazione diretta (p-mediana)**: si scelgono i K treni fra i 9702 progetti della griglia, risolto in modo esatto (JuMP + HiGHS).
- **Criterio: extra-costo medio** sulle linee, con **lo stesso peso per ogni linea** (nello studio ogni linea ha le stesse ipotesi di servizio; i km/anno sono già nel costo €/km).
- **K da 1 a 15.**
- **Due versioni:** senza tetto, e con un tetto all'extra-costo di ogni singola linea (+10%; se a K piccoli non si riesce, anche +15%).
- **Prima K coppie (m, n) libere, poi treni modulari:** poche taglie di fuel cell combinate con poche taglie di batteria.
- **Criterio geografico (a):** due linee che hanno in comune almeno il 25% della più lunga devono usare lo stesso treno. È un vincolo sulla p-mediana; i km in comune vengono dalle sezioni della mappa.
- **Confronto con le fasce di m/n** (la prima proposta): per ogni fascia, il treno che funziona su tutte le linee della fascia.
- Dati: la griglia fitta simulata di fase13/02 (linee del 17/11). Tutti i costi vengono dal simulatore, niente surrogato.

## Piano

1. Tabella dell'extra-costo e riduzione dei treni inutili. **Fatto il 18/11.**
2. p-mediana per K = 1…15, senza e con tetto. **Fatto il 18/11.**
3. Grafici (curva extra-costo contro K, piano (m, n)) e confronto con le fasce. **Fatto il 18/11.**
4. Treni modulari. **Fatto il 18/11.**
5. Criterio geografico.
6. Report finale.

A ogni passo: questo diario, i risultati in `fase14/risultati/` e un commit.

## Passo 1: la tabella (18/11/2026)

Script `fase14/01_tabella.jl` (10 s; riassunto in `fase14/risultati/01_tabella.txt`). Scrive `ml_treno_dati/fase14/tabella.jld2` con:
- C: costo di ogni treno su ogni linea (146 × 9702), infinito dove non funziona;
- R: l'extra-costo relativo all'ottimo della linea;
- S: la massa del serbatoio;
- le taglie e l'elenco dei treni tenuti.

L'ambiente `fase14/` è quello di fase13 più JuMP 1.32 e HiGHS 1.27.

- **Taglie**: la potenza della fuel cell e la capacità della batteria dipendono solo da (m, n), non dalla linea (controllato: differenza 0). Un "treno" è quindi la coppia (m, n).
- **Treni universali**: 2318 progetti funzionano su tutte le 146 linee, 1071 su nessuna. Il miglior treno unico (K = 1) è un ibrido (m 0,42, n 0,67: FC 827 kW, batteria 2127 kWh), ma costa in media **+95%** rispetto all'ottimo di ogni linea, al peggio +180% (Capistrello–Avezzano). Un treno solo non basta.
- **Riduzione**: da 9702 progetti restano 8631 fattibili su almeno una linea, e di questi **1985 non dominati**. Un treno è dominato quando un altro funziona almeno sulle stesse linee e costa al più quanto lui su ognuna: non serve mai. Restano 76 a sola batteria, 30 ibridi con FC piccola e 1879 ibridi. Controllato che l'ottimo di ogni linea resti fra i tenuti. La riduzione vale anche con il tetto e con il vincolo geografico, non per i treni modulari: lì si userà la tabella intera.
- **Il serbatoio, una questione da decidere.** Il simulatore dimensiona il serbatoio dell'idrogeno linea per linea. Per lo stesso treno ibrido, il serbatoio sulla linea più esigente è in mediana 56 volte quello sulla linea più leggera. Quindi oggi il costo di un treno standard su una linea assume un serbatoio adatto a quella linea, come se fosse un modulo (pacchi di bombole) da montare secondo il servizio. L'alternativa è un serbatoio fisso, il più grande delle linee servite: costerebbe di più sulle linee corte e richiederebbe nuove simulazioni. Per ora si tiene il serbatoio adattato alla linea; da discutere.

## Passo 2: la p-mediana per K = 1…15 (18/11/2026)

Script `fase14/02_pmediana.jl` (10 min, quasi tutti per K = 1; gli altri K si risolvono in 1–30 s). Risultati in `fase14/risultati/`:
- `02_pmediana.txt`: riassunto e flotte;
- `02_flotte.csv`: i treni di ogni flotta;
- `02_assegnazioni.csv`: per ogni versione e ogni K, il treno di ogni linea e il suo extra-costo.

Le flotte sono anche in `ml_treno_dati/fase14/pmediana.jld2`. Tutti i problemi sono risolti all'ottimo, senza scarto (gap) residuo. Controllo: ricalcolando a mano il treno più economico della flotta per ogni linea, l'extra-costo medio torna con quello del modello.

**Il modello in parole semplici.** Per ogni K, fra i 1985 treni tenuti si scelgono i K della flotta. Ogni linea usa il treno della flotta che le costa meno fra quelli che funzionano su di essa (e, con il tetto, che non le costano più del +10% o +15%). Si minimizza l'extra-costo medio delle 146 linee.

| K | senza tetto: medio | mediana | peggiore | linee > 10% | tetto +10%: medio | peggiore |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | +95,4% | +104% | +180% | 138 | — | — |
| 2 | +17,1% | +7,9% | +101% | 43 | — | — |
| 3 | +9,0% | +6,9% | +44,7% | 35 | — | — |
| 4 | +6,9% | +3,5% | +44,7% | 31 | — | — |
| 5 | +4,7% | +3,4% | +21,1% | 20 | — | — |
| 6 | +3,9% | +1,6% | +21,1% | 20 | — (+15%: +5,6%, peggiore +14,8%) | |
| 7 | +3,2% | +1,5% | +26,0% | 14 | — (+15%: +3,4%) | |
| 8 | +2,6% | +1,5% | +11,6% | 6 | **+3,1%** | +9,6% |
| 10 | +1,9% | +0,9% | +11,6% | 3 | +2,0% | +9,6% |
| 12 | +1,5% | +0,8% | +9,5% | 0 | +1,5% | +9,5% |
| 15 | +1,1% | +0,5% | +8,6% | 0 | +1,1% | +8,6% |

Cosa si vede:
- **Il guadagno è grande fino a 5–6 treni, poi piccolo.** Da 1 a 3 treni l'extra-costo medio scende da +95% a +9%; a 5 treni è +4,7%, a 8 +2,6%, a 15 +1,1%. Ogni treno in più dopo l'ottavo vale meno di 0,3 punti.
- **Il tetto.** Per tenere ogni linea entro +10% servono almeno **8 treni**; entro +15% almeno 6. Il tetto costa poco: a K = 8 la media sale da +2,6% a +3,1%, a K = 10 da +1,9% a +2,0%; da K = 12 le flotte coincidono (lì nessuna linea supera già il 10%).
- **Ottimizzare solo la media lascia linee lontane.** Senza tetto, con 5–7 treni il caso peggiore è ancora +21–26% e 14–20 linee pagano oltre il 10%. Con K = 7 il peggiore è più alto che con K = 6: la media scende, ma una linea viene sacrificata.
- **Com'è fatta una flotta.** I treni a sola batteria (99 linee) si coprono bene con 2–3 taglie di batteria (per esempio 1273, 2289 e 3113 kWh, extra-costo medio sotto il 2%). Gli ibridi (47 linee) chiedono più treni: con 5–8 treni di flotta sono gli ibridi a pagare l'extra-costo maggiore (+4–10% in media). Il treno ibrido più grande (m 0,42, n 0,68: FC 827 kW, batteria 2161 kWh) c'è in quasi tutte le flotte.
- Esempio, **tetto +10%, K = 8** (medio +3,1%, peggiore +9,6%): 2 a sola batteria (1779 e 3113 kWh, 99 linee), 2 ibridi con FC piccola (98 e 177 kW, 20 linee), 4 ibridi (FC 315, 413, 571, 827 kW, 27 linee).

## Passo 3: grafici e confronto con le fasce (18/11/2026)

Script `fase14/03_grafici_fasce.jl` (meno di 1 min); risultati in `fase14/risultati/03_grafici_fasce.txt`. Figure in `fase14/figure/`:
- `fig_curva.png`: extra-costo medio e della linea peggiore contro K, per la p-mediana (senza tetto, +10%, +15%) e per le fasce;
- `fig_piano_mn.png`: nel piano (m, n) l'ottimo di ogni linea, colorato secondo il treno assegnato, e i treni della flotta (stelle), per K = 5, K = 8 con tetto +10%, e K = 15;
- `fig_mappa_K8.png`: la mappa delle 146 linee colorate secondo il treno, flotta di 8 treni con tetto +10%.

**Il metodo delle fasce.** Le linee si dividono in fasce secondo il loro ottimo (m, n):
- in m: sola batteria, FC piccola (m < 0,1), poi fasce larghe Δm;
- in n: fasce larghe Δn.

Per ogni fascia si prende il treno che funziona su tutte le sue linee con l'extra-costo medio più basso sulla fascia: è la versione migliore possibile del metodo. Ogni linea usa il treno della sua fascia. Provati 24 schemi (Δm: nessuna, 0,2, 0,1, 0,05; Δn da 1 a 0,1); tutti hanno, per ogni fascia, almeno un treno che funziona su tutte le linee.

| K | migliori fasce | p-mediana | rapporto |
|---:|---:|---:|---:|
| 3 | +9,1% | +9,0% | 1,0 |
| 5 | +5,0% | +4,7% | 1,0 |
| 6 | +4,2% | +3,9% | 1,1 |
| 8 | +3,4% | +2,6% | 1,3 |
| 10 | +3,0% | +1,9% | 1,6 |
| 13 | +2,5% | +1,3% | 1,9 |

- **Con pochi treni (3–6) le fasce sono buone quasi quanto la p-mediana.** Con 3 treni le fasce "per regime" (sola batteria / FC piccola / ibrido) danno praticamente la stessa flotta.
- **Con più treni le fasce perdono**: da 8 treni in su l'extra-costo medio è 1,3–1,9 volte quello della p-mediana. Il confine di una fascia è arbitrario: due linee con ottimi vicini ma ai due lati del confine prendono treni diversi, e una fascia larga deve prendere il treno che va bene per la linea più esigente.
- **Il caso peggiore non scende mai sotto il +21%**: nessuno schema a fasce rispetta il tetto del +10%. Con 9–25 linee oltre il 10% sono molto lontane dalla p-mediana con tetto, che a 8 treni tiene tutte le linee sotto il +9,6%.
- Lasciare a ogni linea la scelta libera fra i treni delle fasce migliora poco (al più 0,2 punti). Il problema sono i treni scelti, non l'assegnazione.

**Dal piano (m, n) e dalla mappa.**
- Le linee a sola batteria si dividono semplicemente per taglia di batteria.
- Gli ibridi stanno lungo una curva, da "FC piccola + batteria piena" a "FC grande + batteria più piccola". I treni della flotta si dispongono lungo questa curva.
- Sulla mappa, linee vicine o che condividono binari spesso hanno treni diversi (per esempio nel nodo di Firenze, in Sardegna e in Sicilia): è il motivo del criterio geografico del passo 5.

## Passo 4: treni modulari (18/11/2026)

Script `fase14/04_modulari.jl` (20 min); risultati in `fase14/risultati/04_modulari.txt` e `04_modulari.csv`.

**Il modello.** Si sceglie un catalogo di **a taglie di fuel cell** e **b taglie di batteria**. I treni disponibili sono tutte le combinazioni, più i treni a sola batteria con le stesse b batterie ("nessuna fuel cell" è sempre possibile). Ogni linea usa la combinazione che le costa meno fra quelle che funzionano, e si minimizza l'extra-costo medio.

Qui la riduzione ai treni non dominati del passo 1 non vale, perché un treno dominato può servire a completare il catalogo: si usa la tabella intera. Per tenere il modello piccolo una linea considera solo i treni entro +50% dal suo ottimo. Controllo: con 2 × 3 il risultato è identico senza soglia (949 085 variabili, 94 s); dove la soglia lascia una linea senza scelta (a = 1) si rifà senza soglia.

**Senza tetto** (extra-costo medio; tra parentesi la p-mediana libera con lo stesso numero di treni usati):

| FC × batterie | taglie | treni usati | medio | peggiore |
|---|---:|---:|---:|---:|
| 1 × 3 | 4 | 5 | +13,2% (+4,7%) | +93% |
| 2 × 3 | 5 | 7 | +6,9% (+3,2%) | +42% |
| 3 × 3 | 6 | 8 | +5,2% (+2,6%) | +33% |
| 3 × 5 | 8 | 10 | +3,7% (+1,9%) | +21% |
| 4 × 5 | 9 | 12 | +2,8% (+1,5%) | +17% |

**Con il tetto**, il catalogo più piccolo che tiene ogni linea entro il tetto:

| tetto | catalogo minimo | treni usati | medio | peggiore |
|---|---|---:|---:|---:|
| +10% | 6 FC × 5 batterie (11 taglie) | 16 | +2,8% | +10,0% |
| +15% | 5 FC × 3 batterie (8 taglie) | 11 | +4,1% | +14,9% |
| +20% | 4 FC × 3 batterie (7 taglie) | 10 | +4,6% | +19,6% |

**Cosa si vede: dipende da cosa si conta.**
- **A parità di treni diversi, i modulari costano di più**: circa il doppio dell'extra-costo della p-mediana libera. Le combinazioni non sono scelte una per una: per servire bene gli ibridi servono coppie (m, n) precise lungo la curva del passo 3, e un catalogo a griglia ne copre poche.
- **A parità di taglie di componenti, i modulari costano di meno.** Le flotte libere usano molte taglie diverse: per esempio K = 8 con tetto +10% ha 6 fuel cell e 8 batterie diverse, cioè 14 taglie, per +3,1%. Il catalogo modulare minimo con lo stesso tetto ha 11 taglie e fa +2,8%, ma con 16 versioni di treno.

  | taglie di componenti | p-mediana libera (K) | modulare |
  |---:|---:|---:|
  | 6 | +6,9% (K = 4) | +5,2% (3 × 3) |
  | 8 | +4,7% (K = 5) | +3,7% (3 × 5) |
  | 9 | +3,9% (K = 6) | +2,8% (4 × 5) |

- Quindi la scelta dipende da cosa costa di più nella realtà: omologare e gestire tante **versioni di treno** (allora flotta libera) oppure produrre e tenere a magazzino tante **taglie di componenti** (allora modulare). Da discutere con il relatore.
- Un catalogo con **1 sola fuel cell** non funziona: le linee con l'ottimo a FC piccola o grande pagano fino al +90–100%. Servono almeno 2–3 taglie di FC: una piccola (60–220 kW, "range extender") e una o due grandi (500–890 kW).
