> **Nota (10/11/2026).** Questo documento descrive il DoE precedente (1024 tratte, seed 20260723), usato nelle fasi 1–3. I limiti attuali del generatore (`src/doe_generator.jl`) sono cambiati: vedi `METODOLOGIA_DOE.md` nella cartella `tratte/tratte_doe` del preconfiguratore MATLAB.

# Generazione del DoE di tratte ferroviarie fittizie

## Obiettivo

Il Design of Experiments (DoE) è stato costruito per generare un insieme di tratte ferroviarie artificiali, ma plausibili, da simulare con il modello analitico del treno ibrido idrogeno–batteria. I risultati delle simulazioni saranno poi utilizzati per ampliare il dataset destinato all'addestramento della rete neurale.

La parametrizzazione riguarda soltanto la tratta: lunghezza, pendenza, fermate e limiti di velocità. Le variabili del sistema di propulsione, come `m`, `n`, potenza nominale della fuel cell e capacità della batteria, non fanno parte di questo DoE e vengono gestite separatamente durante la simulazione o l'ottimizzazione.

I valori limite sono stati scelti prendendo come riferimento tre tratte reali già disponibili nel progetto e ampliandone gli intervalli, in modo da ottenere casi diversi senza perdere la plausibilità fisica.

## I nove fattori del DoE

Ogni riga del file CSV identifica una tratta ed è definita da nove fattori indipendenti.

| N. | Fattore nel CSV | Significato | Intervallo e campionamento |
|---:|---|---|---|
| 1 | `L_km` | Lunghezza complessiva della tratta | 15–200 km, uniforme |
| 2 | `slope_mean` | Pendenza media, legata al dislivello netto | da −10 a +10 ‰, con limite condizionato |
| 3 | `slope_std` | Variabilità della pendenza lungo la tratta | 0–8 ‰, uniforme |
| 4 | `slope_segment_length_mean_km` | Lunghezza media dei tratti a pendenza costante | 0,5–3,5 km, log-uniforme |
| 5 | `stop_density_requested` | Densità richiesta delle fermate intermedie | 0–0,32 fermate/km, uniforme |
| 6 | `stop_spacing_cv` | Irregolarità delle distanze tra fermate | 0–0,70, uniforme e ridotta se necessario |
| 7 | `v_max_kmh` | Massimo limite di velocità della tratta | classi da 80 a 160 km/h, a passi di 10 km/h |
| 8 | `speed_restriction_index` | Intensità complessiva delle limitazioni rispetto a `v_max_kmh` | 0–0,60, uniforme |
| 9 | `speed_change_density_requested` | Numero richiesto di cambi di limite per chilometro | 0–0,15 cambi/km, uniforme |

Il campionamento log-uniforme del quarto fattore permette di rappresentare meglio sia tratte con cambi di pendenza frequenti sia tratte con segmenti più lunghi, evitando di concentrare troppi casi sui valori elevati.

## Generazione del profilo di pendenza

La pendenza viene fornita al modello metro per metro, ma non cambia a ogni metro. La tratta viene divisa in segmenti, all'interno dei quali la pendenza rimane costante. Le lunghezze dei segmenti sono casuali e riproducibili, possono essere diverse anche all'interno della stessa tratta e rispettano le seguenti regole:

- ogni segmento è lungo almeno 500 m;
- la loro somma coincide esattamente con la lunghezza della tratta;
- la loro lunghezza media è vicina a `slope_segment_length_mean_km`;
- la variabilità interna delle lunghezze è fissata dal generatore e non costituisce un ulteriore fattore del DoE.

I valori dei diversi segmenti vengono poi corretti affinché l'intero profilo abbia la media `slope_mean` e la deviazione standard `slope_std` richieste. Ogni valore deve rispettare:

\[
-35\text{ ‰}\leq p(x)\leq35\text{ ‰}.
\]

Per limitare le combinazioni estreme viene inoltre imposto:

\[
|\mu_p|+3\sigma_p\leq35\text{ ‰},
\]

dove \(\mu_p\) e \(\sigma_p\) sono rispettivamente media e deviazione standard della pendenza.

Il dislivello netto è calcolato approssimativamente come:

\[
\Delta h[\mathrm{m}]=\mu_p[\text{‰}]\,L[\mathrm{km}].
\]

Il limite geometrico generale è pari a ±7000 m, ottenuto combinando la pendenza assoluta massima di 35 ‰ con la lunghezza massima di 200 km. Tuttavia, poiché la pendenza media è limitata a ±10 ‰, nel DoE corrente il massimo dislivello netto effettivamente campionabile è ±2000 m. L'altimetria non è un fattore indipendente: viene ricavata integrando il profilo di pendenza.

## Generazione delle fermate

Il numero di fermate non viene campionato direttamente, perché deve essere coerente con la lunghezza della tratta. Viene calcolato mediante:

\[
n_{\mathrm{stops}}=\operatorname{round}(d_{\mathrm{stop}}L),
\]

dove `stop_density_requested` è la densità richiesta. `n_stops` conta soltanto le fermate intermedie; partenza e arrivo sono aggiunti separatamente.

Il parametro `stop_spacing_cv` è il coefficiente di variazione delle distanze tra due punti di arresto consecutivi:

\[
CV_{\Delta x}=\frac{\operatorname{std}(\Delta x)}{\operatorname{mean}(\Delta x)}.
\]

Un valore vicino a zero produce fermate quasi equidistanti; valori più alti producono una distribuzione più irregolare. La distanza tra due punti di arresto, considerando anche partenza e arrivo, non può essere inferiore a 1,5 km. Se il numero richiesto di fermate o il coefficiente di variazione non sono compatibili con questo vincolo, il generatore li riduce al massimo valore realizzabile.

## Generazione dei limiti di velocità

Il limite massimo `v_max_kmh` viene scelto tra 80, 90, …, 160 km/h. I limiti presenti nei singoli segmenti possono assumere valori a passi di 10 km/h, da un minimo fissato di 60 km/h fino al massimo scelto.

L'indice di restrizione definisce la velocità media spaziale desiderata:

\[
\bar v_{\mathrm{target}}
=v_{\max}-r_v(v_{\max}-60).
\]

Con \(r_v=0\), il profilo è interamente o quasi interamente alla velocità massima; aumentando \(r_v\), aumentano l'estensione o l'intensità delle sezioni a velocità ridotta.

Il numero dei segmenti a limite costante viene ricavato dalla densità dei cambi:

\[
M=1+\operatorname{round}(\lambda_v L).
\]

Per questi segmenti valgono i seguenti vincoli:

- lunghezza minima di 2 km;
- almeno un segmento alla velocità massima selezionata;
- nessun segmento adiacente con lo stesso limite;
- velocità media effettiva entro 5 km/h dal valore obiettivo;
- almeno un cambio per le tratte non classificate a velocità costante.

Le fermate e i limiti di velocità sono generati separatamente: una fermata non corrisponde a un segmento con limite pari a zero, perché l'arresto viene gestito direttamente dalla dinamica del treno.

## Scenari speciali

Una sequenza Sobol genera normalmente valori interni agli intervalli e difficilmente produce casi esattamente nulli. Per includere anche condizioni operative importanti, il generatore assegna quindi una probabilità deterministica del 10% a ciascuno dei seguenti scenari:

- tratta completamente pianeggiante: `slope_mean = 0` e `slope_std = 0`;
- tratta senza fermate intermedie;
- tratta con un unico limite di velocità costante.

Gli scenari possono sovrapporsi. Nel primo blocco di 256 tratte sono presenti 30 tratte pianeggianti, 27 senza fermate e 29 a velocità costante.

## Algoritmo Sobol scrambled

I 256 punti sono stati generati con una sequenza **Sobol scrambled** a nove dimensioni, usando il seed globale `20260723`.

Sobol è un metodo quasi-casuale a bassa discrepanza: i punti non vengono scelti come estrazioni casuali indipendenti, ma vengono distribuiti in modo da coprire in maniera regolare lo spazio dei fattori. Lo *scrambling* introduce una randomizzazione controllata, mantenendo sia la buona copertura sia la riproducibilità tramite il seed.

Questo metodo è stato preferito al Latin Hypercube Sampling soprattutto perché il DoE può essere esteso progressivamente. Per esempio, dopo avere simulato le tratte 1–256 si possono aggiungere le tratte 257–512 senza modificare le prime 256. Questa proprietà è utile quando le simulazioni vengono svolte in momenti diversi o distribuite tra più tesisti.

Per conservare tale proprietà devono rimanere invariati il seed globale, l'ordine dei nove fattori, i loro intervalli, le trasformazioni e i vincoli. I checkpoint con copertura migliore sono le potenze di due, ad esempio 64, 128, 256 e 512 casi.

Ogni riga possiede:

- un `route_id`, cioè l'indice univoco della tratta nella sequenza;
- un `profile_seed`, usato per rendere riproducibile la disposizione concreta di pendenze, fermate e limiti di velocità.

Pertanto, usando lo stesso CSV e lo stesso codice, un determinato `route_id` genera sempre la stessa tratta.

## Parametri derivati e controllo finale

Nel CSV sono presenti anche colonne derivate, tra cui `n_stops`, `stop_density`, `n_vlim_segments` e `speed_change_density`. Queste non sono ulteriori dimensioni del DoE, ma valori ottenuti dai nove fattori dopo l'applicazione dei vincoli. Anche i profili metro per metro e l'altimetria sono risultati del generatore, non variabili campionate.

Prima della simulazione, MATLAB controlla automaticamente lunghezza e completezza dei vettori, limiti della pendenza, statistiche del profilo, numero e distanza delle fermate, numero e lunghezza dei segmenti di velocità e corrispondenza con la velocità media richiesta. La validazione preventiva dell'intero blocco ha dato esito positivo per tutte le 256 tratte.

Il blocco utilizzato nella campagna corrente è quindi identificato da:

```text
metodo: Sobol scrambled
seed globale: 20260723
route_id: 1–256
numero di fattori indipendenti: 9
```

