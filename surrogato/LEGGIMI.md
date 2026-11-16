# Il surrogato: come si usa

Data una tratta, propone il progetto (m, n) più economico del treno idrogeno–batteria e lo verifica con il simulatore. Una tratta sola richiede circa 10–15 secondi, quasi tutti di avvio e compilazione di Julia. Il lavoro vero per tratta è circa 0,1 s: la rete su 9702 progetti ~20 ms, 5 simulazioni di verifica ~5–20 ms. Con più tratte in un solo lancio l'avvio si paga una volta: 166 tratte in circa 20 s.

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

**Il modo più semplice: il comando `surrogato`**, da qualunque cartella. È un alias nel file `~/.zshrc` (aggiunto il 16/11/2026); funziona in ogni terminale aperto dopo, oppure dopo `source ~/.zshrc`.

```zsh
surrogato doe=15000
surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze
surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze verifiche=10
```

La riga dell'alias, da aggiungere a `~/.zshrc` su un altro computer (cambiando il percorso di `ml_treno`):

```zsh
alias surrogato='julia -t 8 --project="$HOME/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno/surrogato" "$HOME/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno/surrogato/usa_surrogato.jl"'
```

**Senza alias**, il comando va lanciato **dalla cartella `ml_treno`**, non da `train-powertrain`: da un'altra cartella il percorso `surrogato/...` non si trova. Le virgolette servono perché il percorso contiene spazi.

```zsh
cd "$HOME/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno"
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl doe=15000
```

Oppure, da qualunque cartella, con i percorsi completi:

```zsh
ML="$HOME/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno"
julia -t 8 --project="$ML/surrogato" "$ML/surrogato/usa_surrogato.jl" doe=15000
```

Altri esempi, dalla cartella `ml_treno`:

```zsh
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=<cartella che contiene la tratta> tratta=<nome>
```

Esempi:

```zsh
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=~/Documents/lavoro/train-powertrain/dati_rete/archivio/tratte_rete_20261110 tratta=Trapani-Alcamo_Diramazione
```

**Tratte DoE** (le 16 384 della campagna, nel formato `route_XXXXXX/tratta_*.csv` con il manifest):

```zsh
julia -t 8 --project=surrogato surrogato/usa_surrogato.jl doe=15000
```

- La tratta si legge da `~/Documents/lavoro/ml_treno_dati/tratte_doe_16384` (o da `cartella=…`), con `leggi_tratte_materializzate` come la campagna.
- Lo script dice se la tratta era nell'**addestramento** (gruppi 1–6, 8–11, 13, 14: la rete l'ha vista, quindi il risultato è ottimista), nella **validazione** (gruppi 7, 12) o nel **test** (gruppi 15, 16).
- Alla fine mostra la migliore delle 288 coppie della campagna per confronto. Per esempio, la route 15000 (test): sola batteria, n = 0,31, 2,792 €/km, cioè +0,26% rispetto alla migliore della campagna.

**Più tratte in un solo lancio** (molto più veloce: l'avvio e la compilazione, circa 10 s, si pagano una volta sola; poi ogni tratta costa circa 0,1 s):

```zsh
surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Calabria,Canavese,Firenze
surrogato cartella=~/Documents/lavoro/train-powertrain/dati_rete/archivio/tratte_rete_20261110 tratta=tutte
surrogato doe=15000,15001,15002
surrogato doe=15000-15100
```

- Con più tratte lo script stampa una riga per tratta (lunghezza, distanza dall'addestramento, m, n, costo verificato, candidati verificati e, per le DoE, il confronto con la campagna).
- Scrive il riepilogo in `~/Documents/lavoro/ml_treno_dati/surrogato/riepilogo_<data e ora>.csv`, con regime, potenza della fuel cell e capacità della batteria.
- Una tratta che dà errore non ferma le altre.
- Tempi misurati il 16/11/2026: 101 tratte DoE in 12,5 s, le 166 linee della rete in 14 s (più ~5 s di avvio).

**Opzioni:**
- `verifiche=5`: quanti candidati far verificare al simulatore (default 5). Con una tratta "lontana" meglio 10.
- `margine=si`: chiede alla rete un SOC finale previsto ≥ 0,21 e una probabilità di scarica < 0,1 (default sì). Con `margine=no` si trovano progetti a volte un po' più economici, ma più spesso non fattibili.
- `strategia=G`: una verifica più robusta (fase12/13), per ora un'opzione; il default resta `strategia=semplice`. La rete indica dove cercare e il simulatore decide:
  1. il simulatore valuta le 5 migliori della rete, il migliore per la rete di ogni regime (sola batteria, ibrido con fuel cell piccola m < 0,1, ibrido) e di ogni fascia di batteria (n < 0,25, 0,25–0,5, 0,5–0,75, ≥ 0,75), scelti con un margine largo (SOC previsto ≥ 0,18), e 5 progetti a sola batteria (n 0,2, 0,4, 0,6, 0,8, 0,99);
  2. poi fa una ricerca locale dal migliore fattibile e dal migliore fattibile di ogni regime: prova i vicini in m e in n con passi da 0,16 a 0,01 e si sposta finché trova di meglio, al più 40 simulazioni per partenza;
  3. la proposta è il progetto più economico fra tutti quelli simulati e fattibili.

  Costa circa 50 simulazioni per tratta, 0,1–0,3 s. Sulle 166 linee della rete ricostruite dai dati RINF tutte le proposte sono entro +1% dalla migliore delle 288 coppie della campagna (la peggiore +0,58%), e in 143 linee più economiche; con la strategia semplice erano 151 su 166, la peggiore +12,9%. Nell'uscita dettagliata compaiono l'origine di ogni candidato e il percorso della ricerca locale; `candidati.csv` contiene tutti i progetti simulati. `verifiche=` vale solo per la strategia semplice.

  ```zsh
  surrogato cartella=~/Documents/lavoro/train-powertrain/dati_rete/tratte_rete_rinf/tutto_rinf tratta=tutte strategia=G
  ```

**Una coppia (m, n) data, senza ricerca**: si aggiungono `m=` e `n=`, con il punto o la virgola decimale. La rete e il simulatore valutano solo quella coppia, e lo script mette fianco a fianco:
- le grandezze: durata, idrogeno, serbatoio, SOC finale, scarica, C-rate, vite, massa della propulsione;
- l'esito, con i vincoli violati, e il costo in €/km;
- le taglie: potenza della fuel cell e capacità della batteria.

```zsh
surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze m=0.03 n=0.96
surrogato doe=15000-15100 m=0.30 n=0.50
surrogato cartella=~/Documents/lavoro/train-powertrain/dati_rete/archivio/tratte_rete_20261110 tratta=tutte m=0.30 n=0.50
```

- Con più tratte stampa una riga per tratta: costo della rete e del simulatore, SOC, i due esiti.
- In fondo dice in quante tratte rete e simulatore sono d'accordo sulla fattibilità.
- Scrive tutto in `~/Documents/lavoro/ml_treno_dati/surrogato/coppia_m<m>_n<n>_<data e ora>.csv`.
- Con 0 < m < 0,03 il simulatore non mette la fuel cell (D8): il progetto è a sola batteria e lo script lo dice.
- Una coppia fuori dal campo di addestramento (m oltre 0,996, n fuori da 0,013–0,996) dà un avviso: lì la rete estrapola.
- `verifiche` e `margine` qui non servono.

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
