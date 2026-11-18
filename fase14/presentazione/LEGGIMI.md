# Dati della classificazione dei treni, per la presentazione

Prodotti da `fase14/06_dati_presentazione.jl` il 18/11/2026, rileggendo i risultati dei passi 1–5 di `fase14/`; il diario è `STEPS/passi_flotta.md`.

Contesto:
- 146 linee non elettrificate oltre il 70%, con i dati del 17/11;
- ogni linea ha il suo treno ottimo, il progetto (m, n) più economico fra i 9702 simulati sulla griglia fitta (fase13/02);
- l'**extra-costo** di un treno su una linea è quanto costa in più del suo ottimo: (costo / costo ottimo − 1), in %.

Tutti i costi vengono dal simulatore (niente surrogato).

## curve.csv: tutte le flotte calcolate, una riga per flotta

| colonna | significato |
|---|---|
| strada | `p-mediana` (K treni liberi, ottimizzazione esatta), `fasce` (metodo delle fasce di m e n), `modulare` (a taglie di FC × b taglie di batteria), `geografico` (p-mediana con "stesso treno se le linee hanno in comune ≥ soglia della più lunga") |
| variante | senza tetto / tetto +10% / +15% / +20% (nessuna linea oltre quell'extra-costo); per le fasce, le larghezze Δm e Δn; per il geografico, la soglia |
| K_treni | quanti treni diversi usa la flotta (per i modulari: le combinazioni effettivamente usate) |
| taglie_FC, taglie_batteria, taglie_componenti | quante taglie diverse di fuel cell e di batteria servono per costruire la flotta, e la loro somma (per le fasce solo la somma) |
| extra_medio_pct | extra-costo medio sulle 146 linee (stesso peso per ogni linea): **il criterio che si minimizza** |
| extra_mediano_pct, extra_peggiore_pct | mediana e linea peggiore |
| linee_oltre_5pct, linee_oltre_10pct | quante linee pagano oltre il 5% / 10% |

Per le fasce ci sono tutti i 22 schemi provati; per il confronto con la p-mediana si usa, per ogni K, lo schema migliore.

## flotte_scelte.csv: i treni di 9 flotte rappresentative

`pm_K3`, `pm_K5`, `pm_K8`, `pm_K8_tetto10` (la consigliata), `pm_K15`, `mod_3x3`, `mod_6x5_tetto10`, `geo25_K8`, `geo50_K8`. Per ogni treno:
- m, n, regime, potenza della fuel cell [kW], capacità della batteria [kWh];
- quante linee lo usano;
- extra-costo medio e peggiore su quelle linee, e la linea peggiore.

## linee.csv: una riga per linea

- nome, regione, lunghezza, coordinate del baricentro;
- l'ottimo (m, n, regime, kW, kWh, costo €/km);
- il gruppo geografico al 25% e al 50%: numerati dal più grande; le linee con lo stesso numero devono usare lo stesso treno;
- per ognuna delle 9 flotte scelte, il treno assegnato (`<flotta>_m`, `<flotta>_n`) e l'extra-costo della linea (`<flotta>_extra_pct`).

I tracciati per le mappe sono in `fase13/presentazione_146/linee_146.geojson` (stessi nomi di linea).

## Gli altri file

- **fasce.csv**: i 22 schemi a fasce con:
  - K e taglie;
  - extra-costo medio, mediano e peggiore;
  - linee oltre 5% e 10%;
  - la variante "scelta libera" (stessi treni, ma ogni linea prende il più economico);
  - la p-mediana con lo stesso K;
  - i treni (m/n).
- **modulari.csv**: le flotte modulari (a, b, treni usati, extra-costo, taglie scelte come valori di m e n).
- **km_in_comune.csv**: le coppie di linee con sezioni RINF in comune: km in comune, lunghezze, quota della più lunga.
- **riduzione.csv**: quanti treni restano a ogni passo della riduzione (9702 → 8631 → 1985), quanti funzionano su tutte le linee (2318) e quanti progetti ottimi distinti ci sono (97).
- **fig_*.png**: le figure statiche dei passi 3 e 5, utili come riferimento:
  - `fig_curva.png`: extra-costo contro K;
  - `fig_piano_mn.png`: le flotte nel piano (m, n);
  - `fig_mappa_K8.png`: la mappa della flotta consigliata;
  - `fig_geografico_curva.png` e `fig_geografico_mappa_K8.png`: le stesse cose con il criterio geografico.
