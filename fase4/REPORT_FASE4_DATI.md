# Fase 4: dati della campagna P9_D28_16384 (controllo e formato compatto)

13/11/2026. TrainPowertrain al commit 7c9115a di `feat/align-matlab-doe`, senza modifiche in `julia/src`; Julia 1.12.5 su Mac M4. Nessun addestramento, nessuna simulazione, nessuna modifica a train-powertrain. Al più 8 thread.
Dati fuori da Google Drive, in `~/Documents/lavoro/ml_treno_dati/P9_D28_16384/`:
- `raw/`: CSV estratti;
- `arrow/`: formato compatto;
- `log/`: log e cache.

Codice, risultati testuali e figure in `fase4/`. La scheda del dataset è `SCHEDA_DATASET_P9_D28.md`.

## In breve

- **Zip integro:** 129 voci, CRC tutti OK. SHA-256 `e8adba51005f9cb144803d63b255fa8809c6a729d1315dba796c9bee6b771167`.
- **Struttura perfetta:**
  - 64 registri × 73 728 righe, 95 colonne, intestazione = `INTESTAZIONE_REGISTRO`; config.txt identici e uguali a `ConfigModello()`;
  - ogni (tratta, coppia) una e una sola volta;
  - (m, n) uguali al bit alle 288 coppie, m_richiesta = m sempre;
  - il blocco k ha le route (k−1)·256+1 … k·256.
- **Conteggi come attesi:**
  - 4 620 434 completed (97,920%);
  - 98 089 rejected, tutti D3, costo 20000;
  - 69 error (`DOE:D26FrenataImpossibile`, route 2366 e 14664), identici campo per campo a `errori_P9_D28_16384.csv`.
- **Penalità:** coerenti al bit con i vincoli, con le grandezze fisiche e con `tipo_esito`, su tutte le completed.
- **Costo ricostruito (controllo non superato al bit):** `costo_da_grandezze` dà `total_cost_EUR_km` al bit in 4 616 060 righe completed su 4 620 434.
  - Le altre **4374** differiscono di 1–3 ULP (scarto massimo 3,6·10⁻¹⁵ €/km, relativo 4·10⁻¹⁶).
  - **Causa trovata e verificata, non corretta.** In Julia 1.12 `x^y` con esponente intero (qui `1,04^15`, la batteria limitata dalla vita calendariale di 15 anni) passa per `Base.Math.pow_body(x, n)`, che finisce con `muladd`: su questo Mac (Apple M4) è fuso (FMA), sul PC Windows della campagna evidentemente no.
  - Ridefinendo `pow_body` con i `muladd` non fusi, solo in un processo di diagnostica, `costo_da_grandezze` ridà **tutte** le 4 620 434 righe al bit (`05_ultimo_bit.jl`).
  - I dati sono giusti; il bit dipende dalla macchina che ricalcola.
- **Arrow senza perdita:**
  - 64 blocchi zstd, 1,64 GiB contro 6,11 GiB di CSV;
  - riletti, coincidono con il CSV su tutte le colonne (===, NaN compresi), e il testo di ogni numero si rigenera uguale;
  - tutto il dataset si carica in 4 s e occupa 3,1 GiB in memoria.
- **Prezzi:** nessuna colonna fisica dipende dai prezzi. Gli scenari si fanno solo con `costo_da_grandezze`; la prova sul blocco 1 funziona (§3.1).
- **Insieme minimo da imparare:** 7 grandezze per (tratta, coppia), più l'esito D3 (§3.3). Tutto il resto di ciò che il costo legge è costante, funzione esatta di m o di n, della sola tratta, o formula esatta delle 7.
- **Anomalie da discutere (§5):**
  - `E_ricarica_rete_kWh` negativa (SOC finale fino a 0,9 > 0,8 iniziale) in 289 813 righe fattibili, che il costo accredita;
  - batterie con vita sotto l'anno in 19 752 righe fattibili (fino a 191 sostituzioni in 20 anni);
  - durata non monotona con la massa nell'1,13% delle coppie confrontabili: il controllo chiedeva il 99%, qui si arriva al 98,87%;
  - una tratta (13258) oltre le 12 h con i treni più pesanti;
  - `storage_iterazioni` fino a 14 nei casi che convergono (D28 diceva al più 9).

## Comandi per rifare tutto

Dalla cartella `ml_treno`. I log vanno scritti fuori da Google Drive: due volte un log scritto dentro `fase4/risultati` è rimasto vuoto, con il processo uscito subito, probabilmente per la sincronizzazione. Per questo i log sono in `…/P9_D28_16384/log`, copiati poi in `fase4/risultati`.

```zsh
L=~/Documents/lavoro/ml_treno_dati/P9_D28_16384/log
julia --project=fase4 -e 'using Pkg; Pkg.instantiate()'    # TrainPowertrain in sviluppo da ~/Documents/lavoro/train-powertrain/julia, Arrow 2.8.1
zsh fase4/00_zip.sh                                         # passo 0: unzip -t, sha256, estrazione in raw/ (≈ 1 min)
julia -t 8 --project=fase4 fase4/01_integrita.jl > $L/log_01.txt 2>&1   # passo 1 (≈ 2 min)
julia -t 8 --project=fase4 fase4/02_arrow.jl     > $L/log_02.txt 2>&1   # passo 2 (≈ 2,5 min)
julia -t 8 --project=fase4 fase4/03_contenuto.jl > $L/log_03.txt 2>&1   # passo 3 (≈ 40 s)
julia -t 8 --project=fase4 fase4/04_figure.jl    > $L/log_04.txt 2>&1   # figure (≈ 20 s)
julia -t 8 --project=fase4 fase4/05_ultimo_bit.jl > $L/log_05.txt 2>&1  # diagnostica dell'ultimo bit (≈ 10 s)
```

Per rifare solo il testo del passo 1 senza rileggere i CSV: `julia --project=fase4 fase4/01_integrita.jl solo_report`.

| file | cosa fa |
|---|---|
| `comune.jl` | percorsi, schema, lettura del testo e dell'Arrow, `carica_tutto`, colonne di `costo_da_grandezze` |
| `01_integrita.jl` | passo 1 sul testo (un blocco per thread); ricostruisce il costo con `riga_registro_dict` + `costo_da_grandezze` |
| `02_arrow.jl` | passo 2: conversione, viaggio di ritorno, `coppie.arrow`, `tratte.arrow`, `dizionari.arrow`, tempi |
| `03_contenuto.jl` | passo 3: classi delle colonne, formule esatte, controlli fisici, D28, per tratta, per coppia, regolarità, scenari di prezzo |
| `04_figure.jl` | figure in `figure/` |
| `05_ultimo_bit.jl` | verifica dell'ipotesi sull'ultimo bit (ridefinisce `pow_body` solo nel suo processo) |

**Risultati in `risultati/`:**
- `01_integrita.txt`, `01_blocchi.csv` (conteggi per blocco);
- `02_arrow.txt`;
- `03_contenuto.txt`, `03_colonne.csv` (classe e variazioni di ogni colonna);
- `coppie_riassunto.csv`;
- `05_ultimo_bit.txt`;
- `motivi.txt` (dizionario di `motivo`);
- i log, `sha256.txt` e `unzip_t.txt`.

**Tempi (Mac M4, 8 thread):**
- unzip -t 28 s, sha256 7 s, estrazione 29 s;
- passo 1: 106 s;
- passo 2: 136 s di conversione e verifica, più le letture di prova;
- passo 3: 28 s, più 7 s di caricamento;
- figure 16 s.

**La campagna:**
- prima riga 12/11 23:17, ultima 13/11 04:14 (circa 5 h di parete sul PC);
- somma di `tempo_s` 68,5 h, media 52,3 ms per valutazione.

## Passo 0: zip

- 2 550 709 218 byte, 129 voci, `unzip -t`: "No errors detected", 129 OK.
- SHA-256 `e8adba51005f9cb144803d63b255fa8809c6a729d1315dba796c9bee6b771167`.
- Estratte solo le voci `./P9_D28_16384/*` dentro `raw/`. La voce `../errori_P9_D28_16384.csv` è scritta esplicitamente in `raw/errori_P9_D28_16384.csv` con `unzip -p`: nulla fuori da `raw/`.
- 6,1 GiB estratti.
- Il file errori ha virgolette e fine riga CRLF; i registri hanno LF e nessuna virgoletta.

## Passo 1: integrità (`risultati/01_integrita.txt`)

**Registri e configurazione:**
- 64 registri, intestazione unica = `INTESTAZIONE_REGISTRO` di Campagna.jl, 95 colonne;
- 73 728 righe ciascuno, totale 4 718 592;
- nessuna riga con un numero di campi diverso da 95, nessun numero illeggibile.

64 config.txt identici, uguali carattere per carattere a `_descrivi(ConfigModello()) * " peso_a_carico=195000"`, quindi `costo_da_grandezze(g; cfg = ConfigModello())` usa le regole della campagna:

```
modello=corretta soglia_cambio_carico=1.0000000000000001e-09 D3=true D4=pnom_dal_picco D5=nessuna D6=true conteggio_carico=cicli_equivalenti ausiliari_fc=sempre_5pc m_min_fc=0.029999999999999999 perdita_fine_vita_fc=0.20000000000000001 tempi_sostituzioni=a_fine_vita soglia_fine_orizzonte=0 valore_residuo=true definizione_n=energia_riferimento sola_batteria=n_libero f_degrado_fc=0.51692531382982454 ore_max_fc=25000 D12=true D26=true D27=true D28=true D18=true massa_molare_H2=2.016 pci_unico=true degrado_batteria=wang T_cella_batteria=30 vita_calendariale_batteria_anni=15 peso_a_carico=195000
```

**Tratte e coppie:**
- ogni (tratta, coppia) compare una e una sola volta: 16384 × 288 celle, tutte con 1 occorrenza;
- `tratta` sempre `route_XXXXXX`; `direzione` sempre `andata&ritorno`;
- `caso` sempre = `<tratta>_ar_m%.6g_n%.6g`: si ricostruisce, e nell'Arrow si toglie;
- m e n uguali **al bit** (Float64 da `parse`) a una delle 288 coppie di `campionamento_288.csv`, in tutte le righe;
- **m_richiesta === m in tutte le righe (D8: nessun caso diverso).** Nessuna coppia cade in 0 < m < 0,03: le 32 coppie Sobol a sola batteria hanno m = 0 esatto;
- **blocco k = route (k−1)·256+1 … k·256: verificato, 64/64** (non presunto).

**Stato, motivo, tipo_esito** (totali; per blocco in `01_blocchi.csv`):

| stato | tipo_esito | costo | righe | quota |
|---|---|---|---:|---:|
| completed | fattibile | — | 2 014 193 | 42,686% |
| completed | piccola | — | 1 797 608 | 38,096% |
| completed | pesante | — | 683 708 | 14,490% |
| completed | mista | — | 124 925 | 2,648% |
| rejected | piccola | 20000 | 98 089 | 2,079% |
| error | errore | 10000 | 69 | 0,001% |
| **completed** | | | **4 620 434** | **97,920%** |

Per blocco:
- completed da 72 132 a 72 200;
- rejected da 1528 a 1536;
- fattibili da 30 811 a 32 495;
- D28 da 169 a 322;
- errori solo nei blocchi 10 (5) e 58 (64).

Motivi:
- 72 distinti: vuoto per le completed, quello di D3 per tutti i rejected;
- nessun D7: n ≥ 0,0134;
- 69 testi di errore diversi, tutti `DOE:D26FrenataImpossibile: D26: fermata … non raggiungibile frenando entro -0.8 m/s^2 e nessun passo precedente da cui frenare (s = … m)`: fermata 13 sulla route 2366 (5 righe), fermata 17 sulla 14664 (tutte le 64 righe di quella tratta che la usano).

**Errori contro `errori_P9_D28_16384.csv`:**
- 69 righe, stessa intestazione;
- stessi casi;
- **righe identiche campo per campo 69/69**.

`storage_non_convergente`:
- true in 15 491 completed;
- false nelle altre completed e in tutti i rejected;
- "NaN" nelle 69 righe di errore.

**Penalità sulle completed:**
- costo − total_cost_EUR_km ∈ {0: 2 014 193, 1000: 683 708, 3000: 435 284, 4000: 43 443, 5000: 77 800, 6000: 16 673, 8000: 1 284 524, 9000: 64 809}: nessun valore fuori dall'insieme;
- `costo === total_cost_EUR_km + 1000·[vincolo_peso_t>0] + 3000·[vincolo_scarica_100s>0] + 5000·[vincolo_soc_pt>0]` in tutte le righe (al bit);
- i vincoli > 0 coincidono con le grandezze fisiche (massa_propulsione > limite, |scarica_s| > 1e-6, SOC_end < 0,2) e `tipo_esito` con i vincoli (fattibile / pesante / piccola / mista): 0 eccezioni.

**Rejected:**
- tutti D3, costo 20000, tipo `piccola`, `vincolo_d3` > 0;
- le 17 colonne di `cost_details` e `vita_FC_ore`/`vita_FC_tetto` sono NaN, come prima del P9;
- **le colonne P9 e del bilancio sono piene** (il progetto è simulato): per esempio durata, masse, `SOC_minimo`, `vincolo_soc_pt` (da cui SOC_end).

**Costo ricostruito** (`riga_registro_dict` + `costo_da_grandezze(…; cfg = ConfigModello())`, tutte le 4 620 434 completed):
- `costo_totale !== total_cost_EUR_km` in **4374 righe** (0,095%): scarto massimo 3,55·10⁻¹⁵ €/km, relativo 4,1·10⁻¹⁶, al più 3 ULP; `costo` diverso in 1241 righe.
- Delle 24 voci di `cost_details` confrontabili con una colonna, solo `cost_repl_batt_EUR_km_att` differisce (238 323 righe, al più 5,6·10⁻¹⁷), oltre al totale.
- Le 238 323 righe sono tutte tra le 377 094 con la batteria limitata dalla vita calendariale e almeno una sostituzione: t = 15,0 anni e `(1+i)^t` a esponente intero. In tutte, il ricalcolo a mano con la potenza di questo Mac ridà la voce del Mac, e quello con `pow_body` a muladd non fusi ridà la colonna del registro.
- `1,04^5`, `^13`, `^15` cambiano di 1 ULP tra fuso e non fuso.
- **Verifica completa (`05_ultimo_bit.jl`):** con `pow_body(::Float64, ::Integer)` ridefinita senza FMA, `costo_da_grandezze` dà `total_cost_EUR_km` e `costo` al bit in **tutte** le 4 620 434 righe (0 diverse).
- Non ho corretto nulla. È una differenza di macchina, non dei dati: vedi le domande aperte.
- Il testo del registro è scritto con %.17g e si rilegge esatto (passo 2), quindi il CSV non perde bit.

**NaN e Inf per colonna e gruppo** (tabella completa in `01_integrita.txt`), come attesi:
- completed a sola batteria: `vita_FC_ore`, `vita_FC_f1_ore`, `vita_FC_viaggi`, `vita_FC_anni` = +Inf; `tau_FC_anni` NaN;
- completed ibride: nessun NaN né Inf, tranne `H2_coda_kg`;
- rejected: `cost_details` e vita D16 NaN; vite FC +Inf a m = 0; `tau_FC_anni` NaN a m = 0;
- error: tutto NaN tranne m, n, costo, tempo_s, m_richiesta;
- `H2_coda_kg` è NaN ovunque (D15 spenta).
- Fuori dalle colonne della vita FC, gli unici NaN nelle completed sono `tau_FC_anni` a m = 0 (nessuna sostituzione FC) e `H2_coda_kg`. Le completed ibride hanno tutte almeno una sostituzione della FC: `tau_FC_anni` mai NaN.

## Passo 2: formato compatto (`risultati/02_arrow.txt`)

**Blocchi.** Una tabella per blocco, `arrow/blocco_XX.arrow`, stesso schema (93 colonne), zstd:
- `tratta::Int32`, `coppia::Int16` (indice in `coppie.arrow`);
- `stato::Int8`, `motivo::Int16`, `tipo_esito::Int8` (codici da 1, dizionari in `dizionari.arrow` e nei metadati di colonna);
- `storage_non_convergente::Union{Missing,Bool}` (missing dove il registro ha "NaN", cioè nelle 69 righe di errore);
- tutte le altre 86 colonne `Float64`, compresi m, n, m_richiesta, costo, tempo_s.
- Tolte solo `caso` (ricostruibile), `direzione` (costante) e `fine` (data e ora).
- Metadati del file: sorgente con lo sha256 dello zip, config.txt, blocco e route, codici.

**Viaggio di ritorno**, riletto ogni file dal disco:
- ogni colonna numerica === `parse(Float64, campo)` del CSV, NaN compresi;
- ogni campo numerico si rigenera **uguale come testo** (`%.17g`; `tempo_s` `%.6f`);
- codici decodificati = testo; `tratta` riformattata = testo; `caso` ricostruito = testo; `direzione` costante;
- metadati riletti uguali 64/64.
- `costo_da_grandezze` dall'Arrow: le stesse 4374 righe del passo 1, blocco per blocco (e 1241 per `costo`). Il formato non cambia nulla.

**Gli altri file:**
- `coppie.arrow` (288 righe):
  - colonne: `coppia`, `m`, `n`, `origine` (sobol/soglie), `sola_batteria`, `intervallo_D25` (0: m = 0, 1: [0,03; 0,0957), 2: [0,0957; 0,1016), 3: [0,1016; 0,1195), 4: [0,1195; 1]);
  - righe 1–256 = `coppie_campionamento(256)`, 257–288 = `coppie_soglie(16)` di TrainPowertrain: verificato;
  - coppie per intervallo: 32, 15, 18, 20, 203.
- `tratte.arrow`: le 16384 righe del design (21 colonne, lette a mano: Bool, Int64, Float64 con `parse`), più:
  - `blocco`;
  - `errore_D29` (route 2366 e 14664);
  - `senza_coppie_fattibili` (nessuna).
- `dizionari.arrow`: (campo, codice, testo).
- `tratte_riassunto.arrow` (dal passo 3).

**Dimensioni e tempi:**

| | dimensione |
|---|---:|
| zip | 2,38 GiB |
| CSV (64 registri) | 6,11 GiB |
| Arrow zstd (64 blocchi) | 1,64 GiB (26,8%), 26,1–26,2 MiB a blocco |
| coppie / tratte / dizionari .arrow | 10 KiB / 2,2 MiB / 13 KiB |

| lettura | tempo | memoria |
|---|---:|---:|
| un blocco, tutte le colonne in memoria | 0,08 s (0,34 s la prima, con la compilazione) | 49,8 MiB |
| tutti i 64 blocchi | 4,1 s (un thread) | 3,11 GiB |
| solo `Arrow.Table` dei 64 blocchi | 2,6 s | — |

Nota: `Arrow.Table` decomprime subito tutte le colonne compresse, anche se se ne usa una sola. Per leggere poche colonne di tutto il dataset si paga comunque la decompressione (≈ 6 s, 3,7 GiB allocati in transito).

## Passo 3: contenuto (`risultati/03_contenuto.txt`, `03_colonne.csv`)

### 3.1 Costo e prezzi

**Dal codice.** `costo_da_grandezze(g, prezzi; cfg, limite_massa, vita_fc_da_f1, tasso_attualizzazione)` chiama `costo_ciclo_vita`, che usa **tutti i 7 campi di `ParametriCosto`**:

| parametro | default | dove entra |
|---|---:|---|
| `costo_specifico_FC` | 300 €/kW | CAPEX, manutenzione e sostituzioni FC (su P_nom_fc_kW), valore residuo FC |
| `costo_specifico_batteria` | 100 €/kWh | CAPEX, manutenzione e sostituzioni batteria (su C_batt_kWh), valore residuo batteria |
| `costo_specifico_serbatoio` | 535 €/kg H2 | CAPEX e manutenzione del serbatoio (su H2_serbatoio_kg) |
| `costo_fisso_manutenzione` | 0,02 /anno | manutenzione di FC, batteria e serbatoio |
| `costo_energia_elettrica` | 0,19 €/kWh | OPEX elettrico (su E_ricarica_rete_kWh) |
| `costo_H2` | 6,6 €/kg | OPEX idrogeno (su H2_cons_kg) |
| `n_anni` | 20 | orizzonte: numero e date delle sostituzioni, annualità, valore residuo |

Altri parametri del costo che non sono prezzi:
- `tasso_attualizzazione` (argomento, 0,04);
- dalla `cfg`: `vita_calendariale_batteria_anni` (15), `f_degrado_fc` e `ore_max_fc` (solo per ricalcolare la vita FC con f diverso), `tempi_sostituzioni`, `D18`, `valore_residuo`, `modello` (sola batteria senza FC), `soglia_fine_orizzonte` (deve essere 0: con D15 errore);
- `limite_massa` (default la colonna `limite_massa_propulsione_kg`).

**Nessuna colonna fisica dipende dai prezzi.** Nel codice `cfg.costi` compare solo in `_valuta` (Objective.jl:738), passato a `funzione_costo_ga` dopo la simulazione, e `costi.` solo dentro `costo_ciclo_vita`.
- Le grandezze che `costo_ciclo_vita` scrive in `grandezze` (n_viaggi_giorno/anno, km_viaggio, km_anno, vite di batteria e FC in viaggi e anni) vengono da durata, lunghezza e vite, e non usano né i prezzi né `n_anni`.
- **Dipendono dai prezzi o dall'orizzonte**, e si ricalcolano con `costo_da_grandezze`, solo le uscite del costo: `costo`, `total_cost_EUR_km`, le 10 voci, `valore_residuo_*`, `num_repl_FC`, `num_repl_batt` e `tau_FC_anni` (da `n_anni`). Restano `sostituzione_FC_saltata` e `H2_coda_kg` (D15, spenta).
- Le penalità dipendono solo da massa, scarica e SOC: la fattibilità non cambia con i prezzi. Sul blocco 1 penalità identiche in tutti gli scenari: verificato.

**Prova sull'Arrow** (blocco 1, 256 tratte, migliore coppia fattibile delle 288 per tratta; solo prova del percorso):

| scenario | tratte con migliore coppia diversa | cambi di regime | Δm mediano | Δn mediano | costo della migliore (mediana) |
|---|---:|---|---:|---:|---:|
| H2 × 0,5 (3,3 €/kg) | 83 / 256 | nessuno (ibrido → ibrido) | +0,011 | −0,145 | −31,3% |
| H2 × 2 (13,2 €/kg) | 46 / 256 | nessuno | +0,098 | −0,007 | +61,8% |
| FC × 0,5 (150 €/kW) | 39 / 256 | nessuno | +0,161 | −0,159 | −3,5% |

### 3.2 Da cosa dipende ogni colonna (completed, tolleranza relativa 1e-12)

Tabella completa delle 87 colonne numeriche in `03_colonne.csv`, con la variazione relativa massima entro la coppia e massima, mediana e 99° percentile entro la tratta. Per classe:
- **costante (9):** E_ref_kWh, limite_massa_propulsione_kg, SOC_iniziale (0,8), vita_batt_calendario_anni, f_degrado_FC, ore_max_FC, vincolo_d3 (0 sulle completed), sostituzione_FC_saltata (0), H2_coda_kg (NaN);
- **solo coppia (13):** m, n, m_richiesta, P_nom_fc_kW, C_batt_kWh, P_max_FC_kW, n_celle_FC, n_stringhe_batteria, massa_FC_kg, massa_batteria_kg, accensioni_FC (1 se c'è la FC), dV_accensioni_uV, delta_V_max_V;
- **solo tratta (1):** km_viaggio;
- **entrambe (64):** tutto il resto.

Le grandezze chieste:

| colonna | classe | note |
|---|---|---|
| P_nom_fc_kW, massa_FC_kg | solo coppia, **solo m** | = `taglia_FC_2(m·P_max; r = rapporto_picco_fc())`, al bit; 0 a m = 0 |
| C_batt_kWh, massa_batteria_kg | solo coppia, **solo n** | = `taglia_batteria_da_n(n, riferimento_batteria(195 t), 1500)`, al bit |
| E_ref_kWh, limite_massa_propulsione_kg | costanti | 3176,4 kWh; 29 250 kg |
| massa_serbatoio_kg | entrambe | 0 a m = 0 |
| km_viaggio | solo tratta | ≠ 2·L_km del design: scarto relativo fino a 9,8·10⁻⁵ in tutte le righe. È la lunghezza del binario della tratta esportata, non il valore del design |
| durata_viaggio_s | entrambe, **quasi solo tratta** | variazione entro la tratta: mediana 1,0%, 99° perc. 5,7%, massima 8,3% |
| E_trazione_kWh | entrambe | entro la tratta: mediana 13%, massima 17% (cresce con la massa) |
| E_frenatura_disponibile_kWh | entrambe | entro la tratta: mediana 9,6%, massima 17% |
| n_viaggi_giorno | entrambe | costante nella tratta per la mediana delle tratte; cambia di un'unità in alcune (massima variazione 50%: 1 ↔ 2) |
| km_anno | entrambe | come n_viaggi_giorno |

### 3.3 Le colonne di costo_da_grandezze e l'insieme minimo da imparare

**Quante colonne legge.** `costo_da_grandezze` legge **19** colonne, non 60: le 58+2 sono `COLONNE_P9`, cioè le colonne aggiunte in P9 e D28. Le 19, nelle quattro classi:

| classe | colonne lette dal costo |
|---|---|
| costanti (3) | f_degrado_FC, ore_max_FC, limite_massa_propulsione_kg |
| solo coppia (4) | m, n, P_nom_fc_kW (= f(m)), C_batt_kWh (= f(n)) |
| solo tratta (1) | km_viaggio (= 2 × lunghezza del binario) |
| entrambe (11) | durata_viaggio_s, n_viaggi_giorno, massa_propulsione_kg, H2_serbatoio_kg, H2_cons_kg, SOC_end, E_ricarica_rete_kWh, scarica_s, vita_batt_cicli_viaggi, vita_FC_viaggi, vita_FC_f1_ore |

Le 60 `COLONNE_P9`:
- **costanti (9):** E_ref_kWh, limite_massa_propulsione_kg, SOC_iniziale, vita_batt_calendario_anni, f_degrado_FC, ore_max_FC, vincolo_d3, sostituzione_FC_saltata, H2_coda_kg;
- **solo coppia (9):** m_richiesta, P_max_FC_kW, n_celle_FC, n_stringhe_batteria, massa_FC_kg, massa_batteria_kg, accensioni_FC, dV_accensioni_uV, delta_V_max_V;
- **solo tratta (1):** km_viaggio;
- **entrambe (39):** le altre;
- **testo (2):** tipo_esito, storage_non_convergente.

**Formule esatte verificate al bit** (=== su tutte le righe simulate o completed, 0 eccezioni salvo dove detto):
- `n_viaggi_giorno = matlab_round(36000/(durata_viaggio_s + 1))`; `n_viaggi_anno = 365·n_viaggi_giorno`; `km_anno = n_viaggi_anno·km_viaggio`;
- `massa_propulsione = massa_batteria + massa_FC + massa_serbatoio`; `massa_treno = 195000 + massa_FC + massa_batteria + massa_serbatoio`;
- `H2_serbatoio_kg = massa_serbatoio_kg·0,055`;
- `P_max_FC_kW = P_max·m`; P_nom_fc_kW, massa_FC_kg, n_celle_FC da `taglia_FC_2(m·P_max; r = rapporto_picco_fc())`; C_batt_kWh, massa_batteria_kg, n_stringhe_batteria da `taglia_batteria_da_n(n, riferimento_batteria(195000, 1500), 1500)`;
- `E_ricarica_rete_kWh = ((SOC_iniziale − SOC_end)·Capacita_batteria(n)·1500)/1000`, con SOC_iniziale = 0,8 e Capacita_batteria da `taglia_batteria_da_n`;
- `vincolo_soc_pt = 100·(0,2 − SOC_end)`; `vincolo_peso_t = (massa_propulsione − 29250)/1000`; `vincolo_scarica_100s = |scarica_s|/100`;
- `vita_batt_viaggi = min(vita_batt_cicli_viaggi, 15·n_viaggi_anno)`; `vita_batt_anni = vita_batt_viaggi/n_viaggi_anno`; `vita_batt_cicli_anni = vita_batt_cicli_viaggi/n_viaggi_anno`; `vita_FC_anni = vita_FC_viaggi/n_viaggi_anno`;
- `E_frenatura_recuperata = E_frenatura_disponibile − frenata_dissipata_kWh`; `ore_FC_viaggio_h = durata/3600` (0 a m = 0); `I_stringa_scarica_max_A = 2,5·C_rate_scarica_max`.
- **Non al bit**:
  - `vita_FC_viaggi = min((vita_FC_f1_ore/ore)/f, 25000/ore)`, con ore = durata/3600: diversa in 1,9 milioni di righe, al più 5,8·10⁻¹⁶ relativo, come già scritto in P9;
  - la stessa vita via `vita_FC_ore`;
  - E_ricarica dei rejected ricavata da `vincolo_soc_pt` (3,7·10⁻¹¹).
- Il tetto delle 25 000 h è attivo in 66 righe ibride completed. La vita calendariale della batteria vince in 377 094 completed.

**Dal codice:** `structure_caratteristiche_treno(FC, batteria, serbatoio, carico)` passa alla dinamica solo la somma M. Quindi **durata, E_trazione, E_frenatura_disponibile dipendono solo da (tratta, massa_treno)**.

**Insieme minimo da imparare** per (tratta, coppia), dato che m, n e la tratta sono gli ingressi:

| # | grandezza | note |
|---|---|---|
| 1 | `durata_viaggio_s` | funzione di (tratta, massa del treno), quasi lineare con un rumore di pochi secondi (§3.4); da lì `n_viaggi_giorno` con la formula, che è a gradini |
| 2 | `massa_serbatoio_kg` | 0 a m = 0; da lì `H2_serbatoio_kg`, `massa_propulsione_kg` (con masse FC e batteria esatte da m e n), il vincolo di peso e la massa del treno |
| 3 | `H2_cons_kg` | 0 a m = 0 |
| 4 | `SOC_end` | da lì `E_ricarica_rete_kWh` (formula esatta) e il vincolo SOC |
| 5 | `scarica_s` | serve solo per la penalità (> 0): basta un classificatore |
| 6 | `vita_batt_cicli_viaggi` | può essere molto grande (fino a 5,4·10⁵): meglio in scala logaritmica |
| 7 | `vita_FC_viaggi` (o `vita_FC_f1_ore`) | solo ibrido; la prima per il costo al bit con f di default, la seconda per f diverso |

In più l'**esito D3**: un classificatore rejected/completed, 2,1% delle righe. I rejected non hanno costo, e il surrogato deve sapere che il progetto è escluso.

Il resto di ciò che il costo legge è derivabile:
- costanti: f, ore_max, limite;
- da m: P_nom_fc_kW;
- da n: C_batt_kWh;
- dalla tratta: km_viaggio;
- con le formule sopra: n_viaggi_giorno, H2_serbatoio_kg, massa_propulsione_kg, E_ricarica_rete_kWh.

### 3.4 Controlli fisici (completed)

- **Durata A/R ≤ 12 h: 282 violazioni su 4 620 434**, tutte sulla **route 13258**:
  - L = 255,4 km, 22 fermate, v_max 125 km/h, `round_trip_estimate_h` 11,996;
  - con i treni più pesanti arriva a 12,39 h (44 596 s);
  - 82 di queste righe sono fattibili.
  - La durata minima è 740 s.
- **n_viaggi_giorno ≥ 1**: nessuna violazione; valori da 1 a 49 (1: 1,29 M righe, 2: 1,62 M, 3: 0,66 M, …).
- **SOC** in [0, 1] (SOC_iniziale, SOC_minimo, SOC_massimo, SOC_end) e SOC_minimo ≤ SOC_end ≤ SOC_massimo: nessuna violazione.
- **Masse > 0** (batteria, propulsione, treno; FC e serbatoio sugli ibridi), ed esattamente 0 per FC, serbatoio e H2 a sola batteria: nessuna violazione.
- **Costi:**
  - total_cost_EUR_km > 0 sempre (0,133–18,5 €/km sulle completed, 1,13–9,0 sulle fattibili);
  - valore_residuo ≤ 0 sempre;
  - **le voci di costo ≥ 0: 694 030 violazioni, tutte di `OPEX_batt_rech_EUR_km_att` < 0**, perché `E_ricarica_rete_kWh` < 0: SOC finale sopra lo 0,8 iniziale, fino a 0,9;
  - sulle fattibili sono 289 813, tutte ibride;
  - in 1706 tratte la migliore fattibile ha E_ricarica < 0. Domanda aperta 2.
- **Sostituzioni:**
  - num_repl_batt fino a 515 sulle completed e **191 sulle fattibili**;
  - 19 752 righe fattibili hanno la batteria che dura meno di un anno, 83 967 meno di due;
  - num_repl_FC fino a 210 sulle completed e 48 sulle fattibili; 89 932 fattibili con più di 20 sostituzioni FC.
  - Domanda aperta 3.
- **Durata e massa a tratta fissa (D27)**, su 649 milioni di coppie di righe confrontabili (stessa tratta, completed, massa del treno diversa):
  - durata non decrescente con la massa nel **98,868%** e strettamente crescente nel 96,4%;
  - **cala nell'1,132%**: controllo del 99% non superato, di poco;
  - il calo massimo è 40 s; tra righe consecutive in massa i cali sono l'11,8%;
  - 16 381 tratte su 16 384 hanno almeno un calo, 6756 più dell'1%;
  - E_trazione è non decrescente nel 99,76%.
  - In `figure/durata_massa.png`: la durata è quasi lineare nella massa, con un rumore di pochi secondi (gradini da 1 s sulle tratte corte, come la route 1929). Non è un errore della dinamica, ma il surrogato vedrà un segnale con un rumore di 1–40 s.

### 3.5 D28

- **Righe:** 15 491 con `storage_non_convergente = true`, lo 0,369% delle righe ibride simulate. Tutte completed, tutte con m > 0, tutte con `storage_iterazioni = 50`.
- **Esiti:** fattibili 11 019; pesante 4348, piccola 120, mista 4.
- **Coinvolte:** 4309 tratte e 191 coppie.
- **In m:** crescono con m; nessuna sotto 0,1195.

  | m | righe D28 | quota |
  |---|---:|---:|
  | [0,12; 0,15) | 4 | 0,004% |
  | [0,15; 0,2) | 15 | 0,008% |
  | [0,2; 0,3) | 96 | 0,025% |
  | [0,3; 0,5) | 963 | 0,125% |
  | [0,5; 0,75) | 5146 | 0,551% |
  | [0,75; 1] | 9267 | 0,975% |

- **In n:** massimo tra 0,3 e 0,5 (0,5%), minimo sotto 0,1 (0,03%). Coppie con più righe D28: 54 (m 0,963, n 0,476) con 257 tratte, 198, 230, 158, 102. Figura `figure/d28_coppie.png`.
- **storage_iterazioni sulle righe ibride:**

  | iterazioni | righe |
  |---|---:|
  | 1 | 12 614 |
  | 2 | 2 720 638 |
  | 3 | 1 413 610 |
  | 4 | 29 033 |
  | 5 | 2291 |
  | 6 | 364 |
  | 7 | 120 |
  | 8 | 44 |
  | 9 | 21 |
  | 10–14 | 15 |
  | 50 (D28) | 15 491 |

  A sola batteria è sempre 0. Il commento di D28 diceva "i casi che convergono ne usano al più 9": qui 15 righe ne usano da 10 a 14 (convergono, quindi non è un errore).
- **La migliore fattibile della tratta è D28 in 13 tratte.**

### 3.6 Per tratta (`arrow/tratte_riassunto.arrow`)

**Colonne:**
- `tratta`, `n_righe`;
- `n_fattibili` (anche `_sola_batteria` e `_ibride`);
- la migliore fattibile delle 288: `costo_migliore`, `coppia_migliore`, `m_migliore`, `n_migliore`, `regime_migliore` (0 nessuna, 1 sola batteria, 2 ibrido);
- `costo_migliore_sola_batteria`, `costo_migliore_ibrido`, `migliore_D28`;
- quote per `tipo_esito`, `quota_rejected_D3`, `quota_D28`, `senza_coppie_fattibili`.

**Risultati:**
- **Nessuna tratta senza coppie fattibili.**
  - Coppie fattibili per tratta: minimo 7, mediana 114, massimo 265.
  - Quantili 1%, 10% e 90%: 22, 48, 216.
- **Regime della migliore:**
  - sola batteria in 4208 tratte, ibrido in 12 176;
  - per intervallo di m: m = 0: 4208; [0,03; 0,0957): 850; [0,0957; 0,1016): 723; [0,1016; 0,1195): 1200; [0,1195; 1]: 9403.
  - **In tutte le 4208 tratte in cui almeno una coppia a sola batteria è fattibile, la migliore è a sola batteria.** L'ibrido migliore costa in mediana 0,47 €/km in più.
  - La sola batteria vince fino a L = 165 km; l'ibrido compare da L = 39 km (`figure/regime_migliore.png`).
- **Costo della migliore:** da 1,13 a 8,58 €/km, mediana 3,73.
- **Coppie migliori:** 177 coppie su 288 sono la migliore in almeno una tratta. Le più frequenti:

  | coppia | m | n | tratte |
  |---:|---:|---:|---:|
  | 183 | 0,295 | 0,804 | 727 |
  | 286 (tra le soglie) | 0,105 | 0,842 | 722 |
  | 9 | 0,039 | 0,919 | 604 |

### 3.7 Per coppia (`risultati/coppie_riassunto.csv`, `figure/coppie_quote.png`, `figure/d28_coppie.png`)

- **23 coppie mai fattibili** su nessuna tratta. Quasi tutte hanno n alto e m medio-alto (troppo pesanti), più due con n bassissima: la 69 (0; 0,015) e la 137 (0,034; 0,032).
- **14 coppie oltre il limite di peso in tutte le tratte.**
- **2 coppie fattibili in tutte le tratte.**
- **Quota di fattibili per coppia:** mediana 0,36. È alta per m ≳ 0,4 e n intermedia, e bassa a m piccola (batteria troppo piccola: SOC finale e scarica totale) e a n alta con m alta (troppo pesante); vedi `figure/coppie_quote.png`.
- **Rejected D3:** sopra il 50% solo in 6 coppie, tutte con n < 0,05.
- **Scarica totale:** sopra il 50% in 117 coppie, a m piccola.

### 3.8 Regolarità in (m, n) (20 tratte a caso, seme 20261113)

Figure `figure/regolarita_<grandezza>.png` per H2_cons_kg, E_ricarica_rete_kWh, SOC_end, num_repl_FC, num_repl_batt e total_cost_EUR_km (log10): 20 pannelli in (m, n), con le soglie D25 tratteggiate.

**Metodo.** Ho preso il grafo dei 6 vicini più prossimi tra le 288 coppie (1001 archi), e per ogni tratta il salto tra coppie vicine relativo all'ampiezza della grandezza nella tratta.

| grandezza | archi con salto > 10% | > 25% | dei salti > 25%: attraversano D25 / cambio di regime / num_repl_FC diverso / num_repl_batt diverso / n_viaggi diverso / tipo_esito diverso |
|---|---:|---:|---|
| H2_cons_kg | 16,6% | 1,5% | 86 / 219 / 237 / 205 / 0 / 45 su 287 |
| E_ricarica_rete_kWh | 12,4% | 0,9% | 51 / 46 / 89 / 66 / 0 / 53 su 167 |
| SOC_end | 21,1% | 4,8% | 164 / 70 / 467 / 555 / 2 / 324 su 917 |
| num_repl_FC | 15,4% | 5,6% | 67 / 980 / 1061 / 623 / 17 / 84 su 1061 |
| num_repl_batt | 5,1% | 2,7% | 121 / 18 / 254 / 510 / 3 / 52 su 510 |
| total_cost_EUR_km | 9,0% | 0,4% | 20 / 79 / 79 / 60 / 0 / 16 su 80 |
| durata_viaggio_s | 6,8% | 0,1% | — |
| massa_serbatoio_kg | 17,2% | 1,8% | 94 / 243 / 267 / 224 / 0 / 55 su 334 |
| vita_batt_cicli_viaggi | 7,2% | 0,6% | — |
| vita_FC_f1_ore | 20,2% | 6,1% | **599** / 0 / 998 / 453 / 1 / 139 su 1012 |

**Cosa si vede.** Le cause non sono esclusive: un arco ne può avere più d'una, e "num_repl diverso" è quasi sempre vero tra coppie lontane.
- **Salti in m a m = 0 (regime).** Tra la sola batteria e m ≥ 0,03 cambiano di colpo H2, il serbatoio e le sostituzioni FC: la fascia 0 < m < 0,03 non esiste.
- **Soglie D25.** Il 60% dei salti grandi di `vita_FC_f1_ore` attraversa una soglia D25; anche SOC_end e H2 saltano lì. Nelle mappe la colonna di coppie tra 0,0957 e 0,1195 ha colori diversi dalle vicine.
- **Gradini interi.** `num_repl_FC` ha in mediana 7 valori distinti per tratta, `num_repl_batt` 31,5. Il costo li eredita come piccoli gradini: con il valore residuo (D23) il costo è continuo alla sostituzione che esce dall'orizzonte, ma non alle altre. `n_viaggi_giorno` è in mediana costante nella tratta (1 valore distinto), ma dove cambia è un gradino del 50–100% su km_anno.
- **Confine di fattibilità.** SOC_end e scarica hanno un bordo netto: SOC_end è basso (fino a 0) a m piccola, quasi per ogni n.

**Zone rade delle 288 coppie**, nel dominio ibrido m ∈ [0,03; 1], n ∈ [0,01; 0,99914], con 256 coppie:
- **Distanze:** distanza media dal punto più vicino 0,027, 95° percentile 0,047, massima 0,074.
- **Cerchi vuoti più grandi** (raggio 0,065–0,074), tutti sui bordi:

  | m | n |
  |---:|---:|
  | 0,53 | 0,01 |
  | 0,03 | 0,11 |
  | 1,0 | 0,38 |
  | 0,51 | 0,88 |
  | 1,0 | 0,01 |
  | 0,59 | 1,0 |

- **Coppie ai bordi:** 11 con m > 0,95; 10 con n < 0,05; 14 con n > 0,95.
- **Densità per intervallo D25:**

  | m | coppie | per unità di m |
  |---|---:|---:|
  | [0,03; 0,0957) | 15 | 228 |
  | [0,0957; 0,1016) | 18 | 3080 |
  | [0,1016; 0,1195) | 20 | 1116 |
  | [0,1195; 1] | 203 | 231 |

  Il primo intervallo, dove sta la migliore di 850 tratte, ha solo 15 coppie.
- **Distanza dalle soglie:**
  - a destra di 0,0957 la prima coppia è a 1,2·10⁻⁴;
  - a sinistra di 0,0957 la più vicina è a 3,8·10⁻³;
  - a destra di 0,1195 la più vicina è a 3,3·10⁻³.
- **Sola batteria:** 32 valori di n tra 0,015 e 0,985, passo mediano 0,029, massimo 0,058.

### 3.9 Distribuzioni (figure)

- `costo_fattibili.png`: total_cost_EUR_km delle 2 014 193 righe fattibili, in scala lineare e log10.
- `distribuzioni.png`: SOC_end, H2_cons_kg e E_ricarica_rete_kWh, completed contro fattibili. Si vedono il picco di SOC_end a 0,2, la coda di SOC_end > 0,8 e E_ricarica negativa.
- `migliore_vs_design.png`: costo della migliore per tratta contro L_km e 11 fattori del design, colorato per regime.
  - La sola batteria sta sotto un confine netto in L (circa 165 km a costo basso, meno a costo alto).
  - Il costo cresce con |slope_mean| (a V) e con stop_density per la sola batteria.
  - È quasi piatto in slope_std, stop_spacing_cv e speed_restriction_index.
- `regime_migliore.png`: regime della migliore in (L_km, stop_density) e quota di ibride per fascia di 10 km.
- `durata_massa.png`: durata contro massa del treno su 6 tratte (D27).
- `coppie_quote.png`, `d28_coppie.png`, `regolarita_*.png`: vedi sopra.

## 4. Risposte puntuali

| controllo | esito |
|---|---|
| zip integro, CRC | sì, 129/129; SHA-256 sopra |
| 64 registri, 95 colonne, 73 728 righe; config identici | sì |
| ogni (tratta, coppia) una volta, 16384 × 288 | sì |
| m, n = campionamento_288.csv al bit | sì |
| m == m_richiesta (D8) | sì, in tutte le righe |
| blocco k = route (k−1)·256+1…k·256 | sì, verificato |
| ≈ 97,9% completed, 98 089 rejected, 69 error | 97,920%, 98 089, 69 (route 2366: 5, route 14664: 64), uguali al file errori |
| penalità ∈ {0, 1000, 3000, …, 9000} e coerenti con vincoli e tipo_esito | sì, al bit |
| rejected: costo 20000 (D3) o 4000 (D7), grandezze NaN? | tutti D3 a 20000, nessun D7; NaN le colonne di costo, piene le colonne P9 e del bilancio |
| costo_da_grandezze = total_cost_EUR_km al bit su tutte le completed | **no: 4374 righe diverse, al più 3 ULP (3,6·10⁻¹⁵)**; causa verificata (FMA in `pow_body`), con `pow_body` senza FMA 0 righe diverse |
| NaN/Inf solo nella vita FC delle righe senza FC | sì, più `tau_FC_anni` (NaN senza sostituzioni FC, cioè a m = 0) e `H2_coda_kg` (NaN ovunque, D15 spenta); nelle error tutto NaN |
| Arrow senza perdita, ritorno ===, costo ancora al bit | sì; il costo dall'Arrow dà le stesse 4374 righe del CSV |
| colonne fisiche indipendenti dai prezzi | sì (codice); penalità uguali negli scenari (dati) |
| durata ≤ 12 h | **no: 282 righe della route 13258** (fino a 12,39 h) |
| n_viaggi_giorno ≥ 1, SOC in [0, 1], masse > 0, costi > 0 | sì; però OPEX elettrico < 0 in 694 030 completed (E_ricarica < 0) |
| durata crescente con la massa ≥ 99% | **98,87%: non superato di poco** (cali fino a 40 s) |
| D28 | 15 491 righe, 4309 tratte, 191 coppie, 11 019 fattibili, migliore D28 in 13 tratte |
| tratte senza coppie fattibili | nessuna |

## 5. Anomalie e domande aperte

1. **Ultimo bit del costo (4374 righe).** Il registro è stato calcolato su una macchina dove il `muladd` di `pow_body` non è fuso; qui sì. Che cosa fare:
   - accettare una tolleranza di qualche ULP nei controlli di `costo_da_grandezze`, oppure confrontare sulla stessa macchina della campagna;
   - oppure, in train-powertrain, rendere `(1+i)^t` indipendente dalla macchina (per esempio `exp(t·log1p(i))`, o una potenza intera scritta a mano). Cambierebbe però i bit dei registri vecchi.

   Non ho toccato nulla. Va anche controllato che i test al bit di P9/D28 girino sulla stessa macchina dei riferimenti.
2. **E_ricarica_rete_kWh negativa.** In 289 813 righe fattibili, tutte ibride, il SOC finale supera lo 0,8 iniziale (fino a 0,9): la FC ricarica la batteria oltre il punto di partenza, e il costo **accredita** l'energia elettrica al prezzo di acquisto. In 1706 tratte la migliore coppia ha questo credito. È voluto (il viaggio successivo partirebbe da SOC più alto), o va vincolato o azzerato?
3. **Batterie che durano mesi.** 19 752 righe fattibili con vita della batteria sotto un anno, fino a 191 sostituzioni in 20 anni; 3407 tratte hanno la migliore con vita della batteria sotto 5 anni. È coerente con Wang a C-rate alti, ma è un regime poco credibile da far imparare al surrogato (vita su 5 ordini di grandezza).
4. **Route 13258 oltre le 12 h** (282 righe, 82 fattibili): il DoE garantisce le 12 h alla massa di riferimento, non con i treni più pesanti. Va esclusa, o tenuta?
5. **Durata non monotona con la massa** (1,13% delle coppie, fino a 40 s): è rumore della dinamica a passo di 1 s, D27 compresa. Per il surrogato conviene imparare la durata come funzione liscia di (tratta, massa del treno) e accettare l'errore, oppure imparare direttamente `n_viaggi_giorno`, che però è a gradini.
6. **Righe di errore (D29?).** 69 righe su 2 tratte: la 14664 ha 64 coppie su 288 in errore, la 2366 ne ha 5. Escludere le due tratte dall'addestramento, o solo le righe? In `tratte.arrow` sono segnate con `errore_D29`.
7. **`km_viaggio` ≠ 2·L_km del design** (fino a 10⁻⁴ relativo): come ingresso del surrogato va usata la lunghezza della tratta esportata (km_viaggio/2), non `L_km` del design.
8. **Copertura delle 288 coppie.**
   - Il primo intervallo [0,03; 0,0957) ha solo 15 coppie, ma contiene la migliore di 850 tratte.
   - I bordi (n < 0,05, m ≈ 1, n ≈ 1) sono radi.
   - 23 coppie non sono mai fattibili.
   - Per le griglie fitte serve sapere dove il surrogato estrapola.
9. **Regime.** In tutte le 4208 tratte con almeno una sola batteria fattibile, la migliore è a sola batteria. Il regime dell'ottimo è quindi "la sola batteria è fattibile?", una classificazione più semplice del confronto dei costi. Da confermare con la ricerca fitta in n a m = 0, perché qui sono solo 32 valori di n.
10. **`storage_iterazioni` da 10 a 14** in 15 righe che convergono: il commento di D28 ("al più 9") va aggiornato.
11. **`ml_treno/CLAUDE.md` è vuoto** (0 byte, anche nel commit iniziale): non c'erano istruzioni da leggere.
12. `num_repl_*` e `tau_FC_anni` dipendono da `n_anni`, che è un campo di `ParametriCosto`: sono uscite del costo, non grandezze fisiche, e non vanno imparate.
