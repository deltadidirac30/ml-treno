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
2. p-mediana per K = 1…15, senza e con tetto.
3. Grafici (curva extra-costo contro K, piano (m, n)) e confronto con le fasce.
4. Treni modulari.
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
