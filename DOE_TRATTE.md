# Progettazione del DoE per la generazione delle tratte

## Obiettivo

L'obiettivo è definire un insieme ridotto di parametri indipendenti con cui generare, tramite una sequenza Sobol scrambled, un DoE di tratte ferroviarie plausibili ed estendibile nel tempo.

Per ogni punto del DoE verranno generati:

- il profilo di pendenza \(p(x)\);
- le posizioni delle fermate;
- il profilo dei limiti di velocità;
- gli input completi da fornire al modello analitico.

Gli output prodotti dal modello analitico verranno successivamente utilizzati per addestrare la rete neurale surrogata.

`P_nom_fc` e `C_batt` sono input del powertrain e della rete neurale, ma non sono parametri di tratta. Saranno quindi gestiti separatamente dal DoE geometrico e operativo delle tratte.

## Decisione 1 — Profilo di pendenza

### Parametri indipendenti

Il profilo di pendenza verrà generato utilizzando tre parametri specifici, oltre alla lunghezza generale della tratta:

| Parametro | Simbolo | Significato |
|---|---:|---|
| Lunghezza della tratta | \(L\) | Estensione spaziale complessiva della tratta [km] |
| Pendenza media | \(\mu_p\) | Pendenza media/netta e quindi dislivello complessivo [‰] |
| Deviazione standard | \(\sigma_p\) | Intensità e variabilità delle pendenze [‰] |
| Lunghezza media dei segmenti | \(\bar L_{p,\mathrm{seg}}\) | Lunghezza media/caratteristica dei tratti a pendenza costante [km] |

Il vettore utilizzato per descrivere la componente di pendenza è quindi:

\[
\theta_p =
\left[
L,\,
\mu_p,\,
\sigma_p,\,
\bar L_{p,\mathrm{seg}}
\right]
\]

Poiché \(L\) è un parametro generale della tratta, i fattori specifici della pendenza sono solamente:

\[
\boxed{
\mu_p,\,
\sigma_p,\,
\bar L_{p,\mathrm{seg}}
}
\]

### Interpretazione

#### Pendenza media

La pendenza media controlla il dislivello netto:

\[
\Delta h[\mathrm{m}]
\simeq
\mu_p[\text{‰}]\,L[\mathrm{km}]
\]

Una media positiva rappresenta una tratta complessivamente ascendente; una media negativa una tratta complessivamente discendente.

#### Deviazione standard

La deviazione standard distingue il grado di severità del profilo:

- valori bassi: tratta prevalentemente pianeggiante;
- valori intermedi: tratta collinare;
- valori elevati: tratta montana.

#### Lunghezza media dei segmenti

\(\bar L_{p,\mathrm{seg}}\), salvata nel CSV come
`slope_segment_length_mean_km`, controlla la lunghezza media dei tratti a
pendenza costante:

- valori piccoli: cambi di pendenza più frequenti;
- valori grandi: tratti a pendenza costante mediamente più lunghi.

Non impone la stessa lunghezza a tutti i segmenti. All'interno della stessa
tratta le lunghezze sono estratte casualmente e possono, per esempio, essere
0,5 km, 2 km, 0,8 km e 3 km. Ogni segmento è lungo almeno 0,5 km e la somma
delle lunghezze coincide esattamente con \(L\).

## Generazione del profilo

Per ogni punto del DoE si genera una sequenza di segmenti \(j=1,\ldots,M\).
La pendenza è costante all'interno di ciascun segmento:

\[
p(x)=p_j
\qquad
x\in[x_{j-1},x_j)
\]

Le lunghezze \(L_{p,j}=x_j-x_{j-1}\) sono casuali e differenti, con:

\[
L_{p,j}\geq0{,}5\text{ km},
\qquad
\sum_j L_{p,j}=L,
\qquad
\operatorname{mean}(L_{p,j})
\simeq\bar L_{p,\mathrm{seg}}.
\]

I valori \(p_j\) sono poi centrati e scalati sull'intero profilo affinché la
pendenza metro per metro abbia esattamente media \(\mu_p\) e deviazione
standard \(\sigma_p\), rispettando il limite assoluto di ±35‰.

Il coefficiente di variazione usato internamente per le lunghezze è fissato a
0,60: non è una dimensione aggiuntiva del DoE. Il parametro `profile_seed`
determina sia le lunghezze sia i valori dei segmenti, ma non è un fattore
fisico del DoE.

Lo stesso insieme
\((L,\mu_p,\sigma_p,\bar L_{p,\mathrm{seg}})\) può quindi produrre profili
differenti con caratteristiche statistiche equivalenti:

```text
L, μp, σp, Lseg medio, seed=1  → profilo A
L, μp, σp, Lseg medio, seed=2  → profilo B
L, μp, σp, Lseg medio, seed=3  → profilo C
```

In una prima campagna si potrà utilizzare un solo seed per punto del DoE. Realizzazioni aggiuntive potranno essere generate successivamente su un sottoinsieme di punti per quantificare l'effetto della disposizione spaziale.

## Vincoli fissi del generatore

I seguenti elementi non vengono trattati come dimensioni aggiuntive del DoE:

- pendenza minima e massima ammissibile;
- forma della distribuzione casuale;
- discretizzazione spaziale;
- coefficiente di variazione interno delle lunghezze dei segmenti;
- lunghezza minima dei segmenti, fissata a 0,5 km;
- soglie usate per distinguere salita, pianura e discesa.

Come limite preliminare si può utilizzare:

\[
-35\text{ ‰}
\leq
p(x)
\leq
35\text{ ‰}
\]

I valori definitivi e i range dei tre fattori saranno calibrati sui profili reali disponibili.

## Metriche derivate di validazione

Le seguenti quantità non saranno campionate direttamente:

- lunghezza media delle salite `Lup`;
- lunghezza media delle discese `Ldown`;
- frazione della tratta in salita;
- frazione della tratta in discesa;
- frazione pianeggiante;
- numero di cambi di segno;
- pendenza massima e minima effettive.

Saranno calcolate dopo la generazione e utilizzate per verificare la plausibilità del profilo.

Un profilo potrà essere rigenerato o scartato quando:

- supera i limiti fisici;
- presenta un dislivello incompatibile con la lunghezza;
- contiene variazioni spaziali non realistiche;
- presenta salite o discese con lunghezze non plausibili.

## Motivazione della scelta minimale

L'obiettivo non è ricostruire esattamente una tratta reale a partire da poche statistiche, ma generare una popolazione sufficientemente varia e plausibile di nuove tratte.

L'aggiunta di `Lup`, `Ldown`, coefficienti di variazione, frazione pianeggiante e parametri delle code renderebbe il generatore più dettagliato, ma aumenterebbe inutilmente la dimensionalità iniziale del DoE.

La scelta corrente mantiene quindi soltanto:

1. livello medio della pendenza;
2. intensità delle variazioni;
3. lunghezza media dei segmenti a pendenza costante.

Gli eventuali parametri aggiuntivi verranno introdotti solo se una successiva analisi di sensitività dimostrerà che i tre fattori non sono sufficienti.

## Algoritmo di campionamento — Sobol scrambled

Il DoE definitivo utilizza una sequenza **Sobol scrambled** a nove dimensioni. La sequenza Sobol distribuisce i punti in modo uniforme nello spazio dei fattori; lo scramble binario evita una struttura completamente deterministica e permette di fissare una realizzazione riproducibile mediante un seed globale.

Questa scelta sostituisce il Latin Hypercube Sampling per la campagna definitiva. Il pilot LHS già generato viene conservato come verifica storica del generatore dei profili, ma non determina l'ordine delle future simulazioni.

### Motivo della scelta

Le simulazioni saranno eseguite in più momenti e da tesisti diversi. Con Sobol scrambled è possibile aggiungere nuovi punti senza alterare quelli esistenti:

```text
prima campagna       route_id 1–256
seconda campagna     route_id 257–512
terza campagna       route_id 513–1024
```

Il blocco 257–512, generato separatamente, coincide esattamente con le stesse righe della sequenza 1–512. Non è quindi necessario rigenerare né scartare le simulazioni precedenti.

Per mantenere questa proprietà devono rimanere invariati:

1. seed globale dello scramble;
2. ordine delle nove variabili;
3. range e trasformazioni dei fattori;
4. regole dei vincoli condizionati;
5. corrispondenza tra `route_id` e indice Sobol.

Se uno di questi elementi viene modificato, deve essere creata una nuova versione del DoE, senza mescolarla con la sequenza precedente.

### Dimensione delle campagne

Per sfruttare la struttura base 2 della sequenza, i checkpoint principali saranno potenze di due:

\[
N=64,\ 128,\ 256,\ 512,\ 1024,\ldots
\]

Non è obbligatorio che ogni singolo tesista simuli una potenza di due punti. È però opportuno valutare copertura e prestazioni del modello quando il totale cumulativo raggiunge uno di questi checkpoint.

### Seed e gestione operativa

Il seed globale fissato per questa versione è:

```text
20260723
```

Ogni riga riceve inoltre un `profile_seed` deterministico, calcolato dal seed globale e dal proprio `route_id`. Di conseguenza la stessa tratta viene ricostruita identicamente anche quando è generata come parte di un blocco diverso.

Ogni campagna deve avere un registro centrale con almeno:

| Campo | Uso |
|---|---|
| `route_id` | Indice globale Sobol, univoco |
| `status` | `pending`, `running`, `completed`, `failed` |
| `assignee` | Tesista responsabile |
| `result_path` | Posizione degli output del modello analitico |
| `notes` | Errori o anomalie |

Non deve essere assegnata una nuova simulazione prima di avere verificato che il relativo `route_id` non risulti già completato o in esecuzione.

## Decisione 2 — Fermate

### Parametri indipendenti

La distribuzione delle fermate verrà descritta mediante due parametri:

| Parametro | Simbolo | Significato |
|---|---:|---|
| Densità delle fermate | \(d_{\mathrm{stop}}\) | Numero di fermate intermedie per chilometro [km⁻¹] |
| Irregolarità delle distanze | \(CV_{\Delta x}\) | Coefficiente di variazione delle distanze tra fermate |

Il vettore relativo alle fermate è quindi:

\[
\boxed{
d_{\mathrm{stop}},\,
CV_{\Delta x}
}
\]

### Numero di fermate

Poiché la lunghezza \(L\) è già un parametro generale della tratta, il numero di fermate non verrà campionato indipendentemente. Verrà ricavato dalla densità:

\[
n_{\mathrm{stops}}
=
\operatorname{round}
\left(
d_{\mathrm{stop}}L
\right)
\]

Questa scelta evita combinazioni poco plausibili tra lunghezza della tratta e numero assoluto di fermate.

`n_stops` indica solamente le fermate intermedie. La partenza \(x=0\) e l'arrivo \(x=L\) non vengono conteggiati.

### Distribuzione spaziale

Con \(n_{\mathrm{stops}}\) fermate intermedie, la tratta contiene:

\[
K=n_{\mathrm{stops}}+1
\]

intervalli:

\[
\Delta x_1,\Delta x_2,\ldots,\Delta x_K
\]

che devono soddisfare:

\[
\sum_{j=1}^{K}\Delta x_j=L
\]

La regolarità della loro distribuzione viene descritta da:

\[
CV_{\Delta x}
=
\frac{
\operatorname{std}(\Delta x)
}{
\operatorname{mean}(\Delta x)
}
\]

L'interpretazione preliminare è:

| \(CV_{\Delta x}\) | Distribuzione delle fermate |
|---:|---|
| 0 | Fermate equidistanti |
| 0,1–0,3 | Abbastanza regolare |
| 0,3–0,7 | Moderatamente irregolare |
| 0,7–1,0 | Molto irregolare |
| \(>1\) | Fermate raggruppate e presenza di lunghi intervalli |

### Generazione delle posizioni

Per ogni punto del DoE, le lunghezze non normalizzate degli intervalli possono essere generate mediante:

\[
u_j\sim\operatorname{Gamma}(k,1)
\]

con:

\[
k=\frac{1}{CV_{\Delta x}^2}
\]

e successivamente normalizzate:

\[
\Delta x_j
=
L\frac{u_j}{\sum_h u_h}
\]

Le posizioni delle fermate risultano:

\[
x_{\mathrm{stop},j}
=
\sum_{h=1}^{j}\Delta x_h,
\qquad
j=1,\ldots,n_{\mathrm{stops}}
\]

Quando \(CV_{\Delta x}=0\), le fermate vengono disposte in modo equidistante:

\[
\Delta x_j
=
\frac{L}{n_{\mathrm{stops}}+1}
\]

### Vincoli fissi

La distanza minima tra due punti di arresto consecutivi viene trattata come un vincolo del generatore:

\[
\Delta x_j\geq d_{\min}
\]

Un valore preliminare è:

\[
d_{\min}=1\text{ km}
\]

Il numero di fermate deve quindi rispettare:

\[
n_{\mathrm{stops}}
\leq
\left\lfloor
\frac{L}{d_{\min}}
\right\rfloor-1
\]

Il valore definitivo di \(d_{\min}\) e i range di \(d_{\mathrm{stop}}\) e \(CV_{\Delta x}\) verranno calibrati sui dati reali disponibili.

### Seed

Il `profile_seed` determina la disposizione effettiva delle fermate a parità di densità e coefficiente di variazione. Non viene trattato come fattore fisico del DoE.

In una prima campagna si potrà usare una sola realizzazione per punto del DoE. Realizzazioni aggiuntive potranno essere generate successivamente su un sottoinsieme di punti.

## Decisione 3 — Limiti di velocità

### Parametri indipendenti

Il profilo dei limiti di velocità verrà descritto mediante tre parametri:

| Parametro | Simbolo | Significato |
|---|---:|---|
| Velocità massima | \(v_{\max}\) | Massimo limite di velocità presente sulla tratta [km/h] |
| Indice di restrizione | \(r_v\) | Riduzione complessiva rispetto a \(v_{\max}\) |
| Densità dei cambi | \(\lambda_v\) | Numero di cambi di limite per chilometro [km⁻¹] |

Il vettore relativo ai limiti di velocità è quindi:

\[
\boxed{
v_{\max},\,
r_v,\,
\lambda_v
}
\]

### Velocità massima

\(v_{\max}\) rappresenta il massimo limite presente sulla tratta.

Il parametro potrà essere campionato in un intervallo continuo e successivamente quantizzato alla risoluzione ammessa, per esempio a multipli di 5 o 10 km/h.

La risoluzione di quantizzazione è una regola fissa del generatore e non una dimensione aggiuntiva del DoE.

### Indice di restrizione

La velocità media obiettivo viene definita mediante:

\[
\overline v_{\mathrm{target}}
=
v_{\max}
-
r_v
\left(
v_{\max}-v_{\min}
\right)
\]

con:

\[
r_v\in[0,1]
\]

e \(v_{\min}\) fissata dal generatore.

L'interpretazione preliminare è:

| \(r_v\) | Profilo dei limiti |
|---:|---|
| 0 | Tutta o quasi tutta la tratta a \(v_{\max}\) |
| 0,25 | Presenza moderata di sezioni limitate |
| 0,50 | Presenza importante di sezioni lente |
| 1 | Velocità media vicina a \(v_{\min}\) |

Come valore preliminare si può utilizzare:

\[
v_{\min}=60\text{ km/h}
\]

Il range effettivo di \(r_v\) verrà calibrato sui profili reali disponibili.

### Densità dei cambi di velocità

Con \(M\) segmenti a velocità costante:

\[
\lambda_v
=
\frac{M-1}{L}
\]

Il numero di segmenti viene ricavato mediante:

\[
M
=
1
+
\operatorname{round}
\left(
\lambda_vL
\right)
\]

Questa parametrizzazione permette di controllare la frequenza dei cambi senza dipendere direttamente dalla lunghezza della tratta:

- \(\lambda_v=0\): limite costante;
- \(\lambda_v\) piccola: pochi segmenti lunghi;
- \(\lambda_v\) grande: numerosi cambi di limite.

### Generazione del profilo

Per ogni punto del DoE:

1. si ricava il numero di segmenti \(M\);
2. si generano \(M\) lunghezze positive;
3. si normalizzano le lunghezze affinché la loro somma sia \(L\);
4. si assegna a ciascun segmento un limite compreso tra \(v_{\min}\) e \(v_{\max}\);
5. si regolano le probabilità dei limiti per avvicinare la velocità media spaziale a \(\overline v_{\mathrm{target}}\);
6. si quantizzano i limiti alla risoluzione ammessa;
7. si uniscono i segmenti adiacenti con lo stesso limite.

La velocità media spaziale viene calcolata come:

\[
\overline v
=
\frac{1}{L}
\sum_{j=1}^{M}
v_j\Delta x_j
\]

### Vincoli fissi

I seguenti elementi non saranno trattati come dimensioni aggiuntive del DoE:

- limite minimo \(v_{\min}\);
- risoluzione di quantizzazione dei limiti;
- lunghezza minima dei segmenti;
- distribuzione delle lunghezze dei segmenti;
- presenza di almeno un segmento a \(v_{\max}\);
- fusione dei segmenti consecutivi con lo stesso limite.

Come valore preliminare si può imporre:

\[
\Delta x_j\geq1\text{ km}
\]

I valori definitivi verranno calibrati sui dati reali.

### Relazione con pendenza e fermate

Nella prima versione del generatore:

- una fermata non impone \(v_{\lim}=0\), perché le fermate sono descritte separatamente;
- pendenza e limiti di velocità vengono generati indipendentemente;
- eventuali combinazioni estreme vengono gestite mediante controlli di plausibilità, non introducendo ulteriori fattori.

### Metriche derivate di validazione

Le seguenti quantità verranno calcolate dopo la generazione, ma non saranno campionate direttamente:

- velocità media effettiva;
- deviazione standard dei limiti;
- lunghezza media dei segmenti;
- numero effettivo di cambi;
- frazione della tratta a bassa, media e alta velocità;
- massimo salto di velocità;
- differenza tra velocità media richiesta e ottenuta.

Il `profile_seed` determina le lunghezze e l'ordine effettivo dei segmenti a parità di parametri. Non viene trattato come fattore fisico del DoE.

## Vettore DoE definito finora

Combinando lunghezza, pendenza, fermate e limiti di velocità, i fattori stabiliti finora sono:

\[
\boxed{
L,\,
\mu_p,\,
\sigma_p,\,
\bar L_{p,\mathrm{seg}},\,
d_{\mathrm{stop}},\,
CV_{\Delta x},\,
v_{\max},\,
r_v,\,
\lambda_v
}
\]

Il DoE contiene quindi, allo stato attuale, nove dimensioni:

1. una dimensione generale di tratta;
2. tre dimensioni relative alla pendenza;
3. due dimensioni relative alle fermate;
4. tre dimensioni relative ai limiti di velocità.

## Calibrazione preliminare sulle tratte reali

I range iniziali sono stati calibrati sui profili presenti in:

```text
data_profiles/real_routes/1
data_profiles/real_routes/2
data_profiles/real_routes/3
```

Le metriche osservate sono:

| Tratta | \(L\) [km] | \(\mu_p\) [‰] | \(\sigma_p\) [‰] | media segmenti di pendenza [km] | \(d_{\mathrm{stop}}\) [km⁻¹] | \(CV_{\Delta x}\) | \(v_{\max}\) [km/h] | \(r_v\) | \(\lambda_v\) [km⁻¹] |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 16,500 | 9,115 | 7,428 | 0,300 | 0,3030 | 0,248 | 90 | 0,527 | 0,0606 |
| 2 | 93,559 | 2,455 | 4,960 | 0,600 | 0,0641 | 0,611 | 140 | 0,384 | 0,1283 |
| 3 | 177,550 | 0 | 0 | — (pianeggiante) | 0,0676 | 0,614 | 130 | 0 | 0 |

Per la tratta 2 è stato escluso dal calcolo un segmento finale di velocità di lunghezza nulla. Il generatore non ammetterà segmenti con \(x_{\mathrm{end}}\leq x_{\mathrm{start}}\).

I profili reali contengono anche segmenti inferiori a 500 m. Per il DoE è
stata adottata deliberatamente una parametrizzazione più semplice e
conservativa, imponendo 500 m come lunghezza minima.

### Range del DoE pilota

| Parametro | Range preliminare | Campionamento |
|---|---:|---|
| \(L\) | 15–200 km | uniforme |
| \(\mu_p\) | −10–+10‰ | uniforme condizionato |
| \(\sigma_p\) | 0–8‰ | uniforme, con scenario pianeggiante separato |
| \(\bar L_{p,\mathrm{seg}}\) | 0,5–3,5 km | log-uniforme; lunghezza media, non identica per tutti i segmenti |
| \(d_{\mathrm{stop}}\) | 0–0,32 km⁻¹ | uniforme, con scenario senza fermate separato |
| \(CV_{\Delta x}\) | 0–0,70 | uniforme |
| \(v_{\max}\) | 80–160 km/h | classi discrete bilanciate a passo 10 km/h |
| \(r_v\) | 0–0,60 | uniforme |
| \(\lambda_v\) | 0–0,15 km⁻¹ | uniforme, con scenario a limite costante separato |

I range sono adatti a una campagna pilota. Dovranno essere rivalutati quando saranno disponibili ulteriori tratte reali.

## Vincoli del DoE pilota

### Pendenza

Il profilo deve rispettare:

\[
-35\text{ ‰}\leq p(x)\leq35\text{ ‰}
\]

\[
|\mu_p|+3\sigma_p\leq35\text{ ‰}
\]

Il dislivello netto è:

\[
\Delta h=\mu_pL
\]

Il massimo geometrico compatibile con i limiti generali del DoE è:

\[
|\Delta h|_{\max}
=
35\text{ ‰}\cdot200\text{ km}
=
7000\text{ m}.
\]

Il vincolo sul dislivello netto viene quindi posto a:

\[
|\Delta h|\leq7000\text{ m}.
\]

Il limite usato nel campionamento della pendenza media è:

\[
|\mu_p|
\leq
\min
\left(
10,\frac{7000}{L},
35-3\sigma_p
\right)
\]

Con \(L\leq200\) km e \(|\mu_p|\leq10\)‰, il termine \(7000/L\)
non restringe ulteriormente il DoE: il massimo dislivello netto
effettivamente campionabile rimane 2000 m. Il valore di 7000 m rappresenta
il limite geometrico estremo richiesto, non un nuovo fattore.

La lunghezza media dei segmenti deve rispettare:

\[
0.5
\leq
\bar L_{p,\mathrm{seg}}
\leq
3.5\text{ km}
\]

mentre ogni lunghezza effettivamente generata deve rispettare:

\[
L_{p,j}\geq0.5\text{ km},
\qquad
\sum_j L_{p,j}=L.
\]

Quando viene selezionato lo scenario pianeggiante:

\[
\mu_p=0,\qquad\sigma_p=0,
\qquad
\bar L_{p,\mathrm{seg}}\text{ non viene utilizzata.}
\]

### Fermate

La distanza minima preliminare è:

\[
d_{\min,\mathrm{stop}}=1.5\text{ km}
\]

Il numero di fermate viene calcolato come:

\[
n_{\mathrm{stops}}
=
\operatorname{round}
\left(
d_{\mathrm{stop}}L
\right)
\]

e deve soddisfare:

\[
(n_{\mathrm{stops}}+1)d_{\min,\mathrm{stop}}\leq L
\]

Se \(n_{\mathrm{stops}}=0\), \(CV_{\Delta x}\) viene ignorato. Con una sola fermata non viene imposto come target rigido.

### Limiti di velocità

Si assume preliminarmente:

\[
v_{\min}=60\text{ km/h}
\]

e:

\[
d_{\min,v}=2\text{ km}
\]

Il numero di segmenti:

\[
M
=
1
+
\operatorname{round}
\left(
\lambda_vL
\right)
\]

deve rispettare:

\[
M
\leq
\left\lfloor
\frac{L}{d_{\min,v}}
\right\rfloor
\]

Quando \(r_v>0\), il profilo deve contenere almeno due segmenti. Segmenti adiacenti con lo stesso limite vengono uniti.

## Scenari speciali

Poiché la sequenza Sobol trasformata non genera normalmente valori esattamente nulli, il DoE riserva esplicitamente una parte dei campioni a:

- tratte pianeggianti: \(\mu_p=\sigma_p=0\);
- tratte senza fermate: \(d_{\mathrm{stop}}=0\);
- tratte con limite costante: \(\lambda_v=r_v=0\).

Viene utilizzata una probabilità deterministica del 10% per ciascuno scenario. Le categorie possono sovrapporsi. L'assegnazione dipende solo dal seed globale e dal `route_id`, quindi non cambia quando la sequenza viene estesa. Nei singoli blocchi il numero non è imposto esattamente al 10%, ma converge a tale quota con l'aumentare del DoE.

## Tolleranze di accettazione

| Quantità | Tolleranza preliminare |
|---|---:|
| Lunghezza | esatta rispetto alla discretizzazione di 1 m |
| Pendenza media | ±0,1‰ |
| Deviazione standard della pendenza | ±5% |
| Lunghezza media dei segmenti di pendenza | ±15% |
| Lunghezza minima dei segmenti di pendenza | sempre ≥500 m |
| Numero di fermate | esatto |
| \(CV_{\Delta x}\) | ±20% quando statisticamente significativo |
| \(v_{\max}\) | esatto |
| Velocità media | ±5 km/h |
| Numero di cambi di velocità | target ±1 |
| Distanza minima tra fermate | sempre rispettata |
| Lunghezza minima dei segmenti di velocità | sempre rispettata |

## Stato delle decisioni

| Componente della tratta | Stato |
|---|---|
| Lunghezza | Inclusa come parametro generale |
| Pendenza | Definizione preliminare completata |
| Fermate (`n_stops` e distribuzione) | Definizione preliminare completata |
| Limiti di velocità | Definizione preliminare completata |
| Campionamento | Sobol scrambled progressivo, seed `20260723` |
| Powertrain (`P_nom_fc`, `C_batt`) | Separato dal DoE di tratta |

## Implementazione del generatore

La prima implementazione è disponibile nei seguenti file:

| File | Contenuto |
|---|---|
| `src/doe_generator.jl` | Campionamento Sobol scrambled progressivo, LHS storico e generatori di profili |
| `scripts/07_generate_doe_pilot.jl` | Generazione del DoE pilota, metriche e validazione |
| `scripts/08_plot_doe_pilot.jl` | Grafici di copertura e confronto con le tratte reali |
| `scripts/09_generate_doe_sobol.jl` | Generazione di blocchi Sobol numerati e registri per le simulazioni |
| `test/test_doe_generator.jl` | Test di prefisso, estensione, stratificazione, vincoli e riproducibilità |

Il generatore utilizza un unico `profile_seed` per tratta e seed separati internamente per pendenza, fermate e velocità. La stessa riga del DoE produce quindi sempre gli stessi profili.

Il primo blocco di 256 righe si genera con:

```bash
julia --project=. scripts/09_generate_doe_sobol.jl 256 1 20260723
```

Il blocco successivo si genera senza ripetere le righe precedenti:

```bash
julia --project=. scripts/09_generate_doe_sobol.jl 256 257 20260723
```

Il quinto argomento opzionale controlla la materializzazione dei profili completi. Per esempio, `true` genera anche il file JLD2 contenente pendenza, fermate e limiti di velocità:

```bash
julia --project=. scripts/09_generate_doe_sobol.jl 256 1 20260723 data_generated/doe_sobol true
```

Per ogni blocco vengono prodotti il design fisico, i nove punti unitari Sobol, un registro delle simulazioni e un file con i metadati. Il registro complessivo deve essere mantenuto centralmente quando i blocchi vengono distribuiti a persone diverse.

### Primo blocco Sobol

È stato generato il blocco iniziale:

```text
route_id = 1–256
seed = 20260723
```

Gli scenari speciali presenti sono:

- 30 tratte pianeggianti;
- 27 tratte senza fermate;
- 29 tratte a velocità costante.

Le quote non sono forzate esattamente al 10% nel singolo blocco, per non perdere la proprietà di estensione. Un sottoinsieme di 32 righe distribuite lungo tutto il blocco è stato materializzato e ha superato tutti i controlli su pendenza, fermate e limiti di velocità: **32/32**.

I file iniziali si trovano in:

```text
data_generated/doe_sobol/
```

Il file dei profili completi non è stato ancora generato, perché occupa molto più spazio del solo design. Potrà essere prodotto quando verrà collegato il flusso delle simulazioni del modello analitico.

### Materializzazione nel modello MATLAB

Il collegamento con il modello del treno utilizza un materializzatore MATLAB deterministico. Ogni riga del design viene trasformata nella struct `caratteristiche_percorso` mediante:

```text
load_doe_row
    → generate_doe_slope
    → generate_doe_stops
    → generate_doe_speed_limits
    → validate_doe_route
    → build_doe_route
```

La pendenza viene prodotta a tratti costanti e poi espansa metro per metro in
forma adimensionale [m/m]. L'altimetria è calcolata successivamente mediante
integrazione ed è conservata nella struct come grandezza derivata.

La versione corrente del generatore MATLAB è identificata da:

```text
doe-matlab-v2
```

La validazione MATLAB dell'intero primo blocco ha dato:

```text
256/256 tratte conformi
```

Nel blocco sono presenti 226 tratte non pianeggianti. Per tutte:

- le lunghezze dei segmenti variano all'interno della tratta;
- il segmento minimo osservato è 501 m;
- il segmento massimo osservato è 12,437 km;
- l'errore massimo tra lunghezza media richiesta e realizzata è 5,2344%.

Il massimo segmento può superare 3,5 km perché 3,5 km è il limite della
lunghezza **media** campionata, non il limite del singolo segmento.

È stato inoltre eseguito un test della dinamica sulla tratta più corta del blocco, verificando il caricamento e l'utilizzo effettivo della pendenza diretta.

Le istruzioni operative sono riportate in `train-powertrain-matlab-optmz/Codice_PRECONFIGURATORE_generale/MATLAB_DOE.md`.

## Risultati del DoE pilota storico LHS

Questa sezione documenta il generatore AR(1) precedente, nel quale la
pendenza poteva variare ogni metro e il quarto fattore era la scala di
correlazione \(\ell_p\). Non descrive l'attuale generatore a segmenti
costanti ed è conservata esclusivamente come tracciabilità storica.

È stato generato un pilota con:

```text
60 tratte
seed = 20260723
```

Gli scenari speciali comprendono:

- 6 tratte pianeggianti;
- 6 tratte senza fermate;
- 6 tratte con limite di velocità costante.

Le categorie possono sovrapporsi.

### Esito dei controlli

| Controllo | Superati |
|---|---:|
| Lunghezza | 60/60 |
| Media della pendenza | 60/60 |
| Deviazione standard della pendenza | 60/60 |
| Scala di correlazione | 60/60 |
| Limiti della pendenza | 60/60 |
| Numero di fermate | 60/60 |
| Distribuzione spaziale delle fermate | 60/60 |
| Distanza minima tra fermate | 60/60 |
| Velocità massima | 60/60 |
| Velocità media obiettivo | 60/60 |
| Numero di cambi di velocità | 60/60 |
| Lunghezza minima dei segmenti | 60/60 |
| Conformità complessiva | **60/60** |

La prima versione del pilota aveva evidenziato errori nella correlazione realizzata della pendenza. Il generatore è stato corretto introducendo una calibrazione interna della scala del processo casuale. Dopo la correzione:

- errore relativo mediano di \(\ell_p\): circa 5%;
- errore relativo massimo di \(\ell_p\): 14,7%;
- errore massimo della velocità media: 3,08 km/h;
- media e deviazione standard della pendenza vengono realizzate entro la precisione numerica.

### Copertura ottenuta

| Fattore | Minimo pilota | Massimo pilota |
|---|---:|---:|
| \(L\) [km] | 16,745 | 199,491 |
| \(\mu_p\) [‰] | −7,711 | 9,271 |
| \(\sigma_p\) [‰] | 0 | 7,964 |
| \(\ell_p\) [km] | 0 | 3,407 |
| \(d_{\mathrm{stop}}\) [km⁻¹] | 0 | 0,319 |
| \(CV_{\Delta x}\) | 0 | 0,536 |
| \(v_{\max}\) [km/h] | 80 | 160 |
| \(r_v\) | 0 | 0,595 |
| \(\lambda_v\) [km⁻¹] | 0 | 0,146 |

Il massimo \(CV_{\Delta x}\) del pilota è inferiore al limite teorico 0,70 perché il parametro è condizionato dalla densità delle fermate e dalla distanza minima di 1,5 km. Le tratte reali 2 e 3 raggiungono circa 0,61 con bassa densità. Il range 0–0,70 viene quindi mantenuto; in un DoE più grande dovrà essere verificata esplicitamente la presenza di combinazioni a bassa densità e alto \(CV_{\Delta x}\).

### File prodotti

Gli output si trovano in:

```text
data_generated/doe_pilot/
```

| File | Contenuto |
|---|---|
| `design.csv` | Parametri richiesti dal DoE |
| `metrics.csv` | Parametri misurati sui profili generati |
| `validation.csv` | Errori e controlli di accettazione |
| `reference_metrics.csv` | Metriche delle tre tratte reali |
| `profiles.jld2` | Profili completi delle 60 tratte |
| `pilot_report.md` | Report automatico |
| `factor_coverage.png` | Distribuzioni dei fattori e riferimenti reali |
| `reference_comparison.png` | Confronto tra profili reali e sintetici |

### Verifica automatica

Il test dedicato viene eseguito con:

```bash
julia --project=. test/test_doe_generator.jl
```

e verifica:

- punti Sobol standard noti;
- stratificazione base 2 dopo lo scramble;
- equivalenza tra generazione cumulativa e generazione per blocchi;
- conservazione esatta dei punti quando il DoE viene esteso;
- stratificazione del Latin Hypercube storico;
- rispetto dei range condizionati;
- presenza esatta degli scenari speciali;
- riproducibilità rispetto al seed;
- pendenze entro i limiti fisici;
- distanze minime tra fermate;
- segmenti di velocità positivi e consecutivi;
- presenza di \(v_{\max}\);
- assenza di limiti adiacenti identici.

## Prossimi passi

1. Congelare formalmente la versione dei nove range e dei vincoli.
2. Generare il primo blocco Sobol, preferibilmente fino al checkpoint 256.
3. Assegnare i `route_id` ai tesisti tramite il registro centrale.
4. Definire quante configurazioni di powertrain simulare per ogni tratta.
5. Eseguire il modello analitico e raccogliere gli output.
6. Valutare il modello ai checkpoint cumulativi e, se necessario, estendere la stessa sequenza.
