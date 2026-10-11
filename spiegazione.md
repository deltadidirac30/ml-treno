# Surrogate Model per Treno Ibrido Idrogeno-Batteria

## Contesto

Il sistema in esame è un treno ibrido con sistema di propulsione composto da una **fuel cell a idrogeno** (FC) e un **pacco batteria** (BESS). Il comportamento energetico del sistema — consumi, stato di carica, degrado dei componenti — è simulato tramite un **modello fisico implementato in MATLAB**, che replica fedelmente la dinamica del veicolo lungo una tratta ferroviaria.

Il modello MATLAB riceve in ingresso:
- il **profilo della tratta** (pendenza metro per metro, limiti di velocità per segmento, posizione delle fermate, lunghezza totale);
- i **parametri del powertrain** (potenza nominale della fuel cell P_nom_fc, capacità della batteria C_batt).

E produce in uscita quattro grandezze di interesse ingegneristico:

| Output | Significato |
|---|---|
| `H2_cons` | Consumo totale di idrogeno [kg] |
| `SOC_end` | Stato di carica della batteria a fine missione [-] |
| `num_repl_FC` | Numero di sostituzioni della fuel cell nel ciclo di vita |
| `num_repl_batt` | Numero di sostituzioni della batteria nel ciclo di vita |

## Il problema

Il modello MATLAB, pur essendo accurato, ha un **costo computazionale elevato**: ogni singola simulazione richiede alcuni minuti. Questo lo rende impraticabile per attività che richiedono migliaia di valutazioni, come:
- ottimizzazione del powertrain (trovare la coppia P_nom_fc, C_batt ottimale);
- analisi di sensitività su parametri di tratta e sistema;
- design space exploration su tratte nuove.

## Obiettivo

L'obiettivo è addestrare un **modello surrogato** — una rete neurale artificiale (ANN) — capace di **approssimare la funzione input-output del simulatore MATLAB** con un errore accettabile, riducendo il tempo di inferenza da minuti a millisecondi.

## Architettura della rete

Il surrogate è un **Multi-Layer Perceptron (MLP)** con la seguente struttura:

```
Input (69 feature) → Dense(128, ReLU) → Dense(64, ReLU) → Dense(32, ReLU) → Output (4)
```

Le **69 feature di ingresso** sono calcolate a partire dal profilo grezzo della tratta e dai parametri del powertrain. Includono:
- statistiche del profilo di pendenza (integrale, RMS, asimmetria, variazioni di segno, …);
- statistiche dei limiti di velocità (media, varianza, energia cinetica associata, …);
- densità e distribuzione spaziale delle fermate;
- feature incrociate fisicamente motivate (es. correlazione pendenza–velocità);
- istogrammi spaziali di pendenza e velocità (binning a 10 celle ciascuno);
- parametri scalari del powertrain (P_nom_fc, C_batt).

## Dati di training

I dati di addestramento provengono da simulazioni MATLAB organizzate come **analisi di sensitività**: per ogni configurazione di tratta (lunghezza, pendenza, numero di fermate, velocità massima) sono state eseguite centinaia di simulazioni variando sistematicamente (P_nom_fc, C_batt). Il dataset finale conta **3126 campioni** distribuiti su 5 gruppi di tratta (sensitività su L, pendenza, fermate, velocità, tratte reali italiane).

Il modello è addestrato con **AdamW** (lr = 3×10⁻⁴, weight decay = 10⁻⁴), loss MSE pesata per output, early stopping con patience = 75 epoche.

## Risultati attuali

Valutati su un test set indipendente (625 campioni):

| Output | R² | MAE |
|---|---|---|
| H2_cons | 0.995 | — |
| SOC_end | 0.916 | 0.029 |
| num_repl_FC | 0.974 | accuracy 60% |
| num_repl_batt | 0.956 | accuracy 91% |

## Utilizzo previsto

Una volta validato, il surrogate sostituisce il simulatore MATLAB nelle fasi di:
1. **ottimizzazione del powertrain** — ricerca della coppia (P_nom_fc, C_batt) che minimizza il costo totale di proprietà (TCO) su una data tratta;
2. **design space exploration** — mappatura rapida degli output su tutto lo spazio ammissibile dei parametri;
3. **analisi di sensitività globale** — quantificazione dell'impatto relativo di ciascun parametro di tratta e di sistema sulle prestazioni.

Il surrogate è pensato come strumento di **primo livello**: screening rapido e ottimizzazione, con validazione finale dei candidati ottimali tramite il simulatore fisico completo.
