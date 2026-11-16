# Il surrogato: come si usa

Data una tratta, propone il progetto (m, n) più economico del treno idrogeno–batteria e lo verifica con il simulatore. Circa 10–15 secondi, quasi tutti di caricamento di Julia: la rete valuta 9702 progetti in 1,4 s, e 5 simulazioni di verifica richiedono 2 s.

## 1. Preparare la tratta

Una cartella `<nome>/` con 4 file di testo, nel formato di `train-powertrain/tratte_reali/README.md`:

| file | contenuto |
|---|---|
| `<nome>_progressiva.txt` | progressiva dei punti del profilo [m], un valore per riga |
| `<nome>_altimetria.txt` | quota negli stessi punti [m] |
| `<nome>_stazioni.txt` | posizione delle stazioni [m], compresi 0 e il capolinea |
| `<nome>_limiti.txt` | una riga per limite: inizio [m], fine [m], velocità [km/h] |

Vanno bene così come sono le tratte di `train-powertrain/tratte_reali` e le linee di `tratte_rete`. Dai CSV del portale si convertono con `julia/scripts/converti_tratta_portale.jl`.

## 2. Lanciare

Dalla cartella `ml_treno`:

```zsh
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=<cartella che contiene la tratta> tratta=<nome>
```

Esempi:

```zsh
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=~/Documents/lavoro/train-powertrain/dati_rete/archivio/tratte_rete_20261110 tratta=Trapani-Alcamo_Diramazione
```

**Opzioni:**
- `verifiche=5`: quanti candidati far verificare al simulatore (default 5). Con una tratta "lontana" meglio 10.
- `margine=si`: chiede alla rete un SOC finale previsto ≥ 0,21 e una probabilità di scarica < 0,1 (default sì). Con `margine=no` si trovano progetti a volte un po' più economici, ma più spesso non fattibili.

## 3. Leggere il risultato

- **Distanza dalla tratta di addestramento più vicina:** quanto la tratta è diversa da quelle su cui la rete ha imparato. Fino a ~4,7 è nella norma; oltre, la rete sbaglia di più e conviene `verifiche=10`.
- **La tabella dei candidati:** m, n, il costo previsto dalla rete, il costo vero del simulatore, l'esito ("fattibile" o la penalità).
- **Il progetto proposto:** il candidato più economico **davvero fattibile secondo il simulatore**, con la potenza della fuel cell, la capacità della batteria e le principali grandezze previste. Se nessuno dei primi candidati è fattibile, lo script ne verifica altri, fino a 20.

I candidati sono salvati anche in `~/Documents/lavoro/ml_treno_dati/surrogato/<nome>/candidati.csv`.

## Limiti

- Treno di riferimento da 195 t, andata e ritorno, modello e prezzi del simulatore di oggi (`ConfigModello()`, commit `7c9115a`). Con un altro treno, altri prezzi o un modello cambiato la rete va riaddestrata.
- m e n su una griglia a passo 0,01.
- Affidabilità misurata: sul test (2048 tratte nuove) il progetto proposto è fattibile nel 98,4% dei casi ed è entro l'1% dalla migliore delle 288 coppie della campagna, o meglio, nel 90%. Sulle 166 linee reali: 97% e 86% (fase 12).

Il modello è `~/Documents/lavoro/ml_treno_dati/fase10/rete_6b.jld2` (fuori da Drive e da git); i dati per la distanza vengono da `…/P9_D28_16384/arrow/caratteristiche.arrow`.
