# Dati delle 146 linee per la presentazione

Prodotti da `fase12/18_dati_presentazione.py` il 16/11/2026. Le 146 linee sono quelle non elettrificate oltre il 70%, ricostruite dai dati RINF (`train-powertrain/dati_rete/tratte_rete_rinf/tutto_rinf`). Treno di 195 t, andata e ritorno. Il surrogato usa la strategia G con il bordo, cioè il default del comando `surrogato`.

## linee_146.csv (una riga per linea)

| colonna | significato |
|---|---|
| linea, regione, L_km | nome, regione (della prima sezione), lunghezza [km] |
| quota_non_elettrificata | quota della lunghezza non elettrificata (0–1), calcolata dalle sezioni della mappa |
| lat, lon | baricentro del tracciato (gradi) |
| m, n | progetto proposto dal surrogato: m = taglia della fuel cell, n = taglia della batteria (0–1) |
| regime | sola batteria (m = 0), ibrido FC piccola (m < 0,1), ibrido |
| P_FC_kW, C_batt_kWh | potenza nominale della fuel cell e capacità della batteria del progetto proposto |
| costo_EUR_km | costo del progetto proposto, dal simulatore [€/km] |
| costo_rete_EUR_km, errore_rete_costo_pct | il costo che prevedeva la rete e il suo errore rispetto al simulatore |
| simulazioni_surrogato | simulazioni fatte dal surrogato per quella linea (invece di 9702) |
| distanza_addestramento, giudizio_distanza | quanto la linea è diversa dalle tratte di addestramento (vicina ≤ 2,9, nella norma ≤ 4,7, LONTANA) |
| ottimo_m, ottimo_n, ottimo_regime, ottimo_costo_EUR_km | l'ottimo vero: il progetto fattibile più economico fra tutti i 9702 simulati |
| scarto_surrogato_pct | costo della proposta rispetto all'ottimo vero (0 = trovato l'ottimo) |
| scarto_semplice_pct, scarto_migliore288_pct | lo stesso per la strategia semplice (vecchio default) e per la migliore delle 288 coppie della campagna |
| progetti_fattibili | quanti dei 9702 progetti sono fattibili per il simulatore |
| fattibilita_rete_giusta_pct | su quanti dei 9702 progetti la rete indovina fattibile / non fattibile |
| tempo_griglia_cpu_s | tempo di calcolo della griglia fitta, sommando i singoli progetti [s] |

## linee_146.geojson

Il tracciato di ogni linea (MultiLineString, longitudine e latitudine), preso dalle sezioni di `train-powertrain/dati_rete/mappa_rete_completa.html`, con le stesse proprietà del CSV.

## heatmap_<linea>.csv

Tutti i 9702 progetti (m = 0 e 0,03–0,99; n = 0,01–0,99, a passo 0,01) di tre linee d'esempio, con simulatore e rete affiancati. Colonne: m, n, esito_simulatore (fattibile; piccola = batteria/serbatoio insufficienti; pesante = troppo pesante; mista), costo_simulatore_EUR_km, fattibile_rete, costo_rete_EUR_km, SOC_rete.

| linea | regime | proposta = ottimo vero | costo |
|---|---|---|---|
| Brescia-Iseo (23,6 km, Lombardia) | sola batteria | m 0, n 0,32 | 2,669 €/km |
| Grosseto-Siena (100,6 km, Toscana) | ibrido FC piccola | m 0,06, n 0,97 (ottimo isolato sul bordo) | 2,721 €/km |
| Cagliari-Olbia_Terranova (276,1 km, Sardegna) | ibrido | m 0,36, n 0,68 | 3,726 €/km |

## riassunto.txt

I numeri aggregati: regimi, costi e taglie per regime, per regione e per lunghezza, rete contro simulatore su tutti i 1,4 milioni di progetti, tempi.
