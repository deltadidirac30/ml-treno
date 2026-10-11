# Analisi dei risultati del DoE in MATLAB

Questo programma legge gli Excel delle ottimizzazioni, unisce le tratte e produce correlazioni di Spearman, PRCC, classifiche per output e grafici di esempio. Non esegue nuove simulazioni e non modifica i file originali.

## Avvio in pochi passaggi

1. Copiare questa cartella sul proprio computer e aprirla come **Current Folder** in MATLAB.
2. Usare MATLAB **R2020b o successivo**. Non servono toolbox aggiuntive.
3. Scrivere nella Command Window:

   ```matlab
   analisi_DOE
   ```

4. Selezionare uno o piu' Excel, tenendo premuto Ctrl o Cmd per selezionarne diversi. La selezione multipla riguarda file nella stessa cartella. Il programma legge **il primo foglio di ciascun file**.
5. Attendere il messaggio finale: riporta il percorso della cartella con le tabelle e i grafici. La cartella viene creata accanto al codice con un nome univoco, diverso a ogni esecuzione.

I file `analisi_DOE.m`, `calcola_correlazioni.m` e `ranghi_medi.m` devono restare insieme. Il primo contiene il programma, il secondo i passaggi statistici commentati, il terzo la gestione dei ranghi con valori uguali. `test_correlazioni.m` e' un controllo facoltativo: eseguirlo scrivendo `test_correlazioni`.

Per indicare file e fogli senza la finestra di selezione:

```matlab
file_excel = {'Risultati finali.xlsx', 'TRATTE OTTIMALI.xlsx'};
fogli_excel = {'Foglio1', 'Fattori DOE'};
[dati, statistiche, cartella_output] = analisi_DOE(file_excel, fogli_excel);
```

I percorsi possono essere assoluti o relativi alla Current Folder. Il terzo argomento, facoltativo, puo' essere `false` per salvare i grafici senza aprirne le finestre:

```matlab
[dati, statistiche, cartella_output] = analisi_DOE(file_excel, fogli_excel, false);
```

## Preparare gli Excel

La prima riga deve contenere le intestazioni, dalla cella A1, e ogni riga successiva deve descrivere una tratta. I nomi delle colonne devono coincidere con quelli degli Excel gia' prodotti. L'ordine delle colonne non e' importante. L'ID puo' chiamarsi `route_id` oppure `Tratta`.

I nove input obbligatori sono:

| Colonna | Significato | Unita' |
|---|---|---|
| `L_km` | Lunghezza della sola andata | km |
| `slope_mean` | Pendenza media della sola andata | per mille |
| `slope_std` | Variabilita' della pendenza | per mille |
| `slope_segment_length_mean_km` | Lunghezza media richiesta dei segmenti a pendenza costante | km |
| `stop_density_requested` | Densita' richiesta di fermate | fermate/km |
| `stop_spacing_cv` | Irregolarita' degli intervalli tra fermate | adimensionale |
| `v_max_kmh` | Velocita' massima consentita | km/h |
| `speed_restriction_index` | Intensita' delle riduzioni dei limiti rispetto al massimo | adimensionale |
| `speed_change_density_requested` | Densita' richiesta dei cambi di limite | cambi/km |

`route_id` e' un identificativo e non viene correlato con gli output. `m` e `n` sono risultati dell'ottimizzazione. Non aggiungiamo come input il numero di fermate, derivato da lunghezza e densita'. I parametri richiesti al generatore non sono necessariamente identici ai descrittori misurati sul profilo realizzato.

Il programma analizza le taglie FC/batteria, m, n, consumi H2, SOC finale, TCO, le dieci componenti di costo e i numeri di sostituzioni. Se una colonna di output manca, segnala un avviso e la lascia non disponibile. Non converte risultati mancanti in zeri. Non usa `total_cost_EUR_km` come secondo output di costo totale: sarebbe ridondante con il TCO negli Excel attuali.

Unire soltanto simulazioni confrontabili: stessa direzione, modello, peso del treno, ipotesi economiche e procedura/budget di ottimizzazione. Il programma **non puo' verificare queste condizioni dagli Excel** e non certifica convergenza o fattibilita' delle ottimizzazioni. Eventuali casi falliti o non validati vanno lasciati senza output oppure esclusi motivatamente prima dell'analisi. Non caricare due volte la stessa tratta: gli ID duplicati provocano un errore per evitare di contarla due volte.

La configurazione iniziale e' **andata e ritorno**: `H2_kg_km = H2_cons_kg / (2 * L_km)`. Per dati tutti di sola andata, cambiare `direzione` nella sezione 1. Non mescolare le due direzioni nella stessa analisi.

## Spearman e PRCC, in parole semplici

**Spearman** misura se un output tende a crescere o diminuire quando cresce un input. Usa l'ordine dei valori, detto rango, invece dei valori direttamente.

La **PRCC** cerca la relazione che rimane dopo aver tenuto conto degli altri input. Per ogni parametro:

1. Trasforma input e output in ranghi. Ai valori uguali assegna il rango medio.
2. Stima con due regressioni la parte del rango dell'input e dell'output associata agli altri input.
3. Sottrae queste parti, ottenendo due residui.
4. Calcola Pearson tra i residui. Non applica nuovamente Spearman ai residui.

I passaggi sono visibili in `calcola_correlazioni.m`. `ranghi_medi.m` gestisce i pareggi assegnando il rango medio, secondo la stessa convenzione di [`tiedrank`](https://www.mathworks.com/help/stats/tiedrank.html). I test verificano valori attesi e, se la toolbox statistica e' disponibile, confrontano anche i risultati con [`partialcorr` di MATLAB, tipo Spearman](https://www.mathworks.com/help/stats/partialcorr.html).

Un coefficiente positivo indica un'associazione crescente, uno negativo un'associazione decrescente. Il valore assoluto esprime l'intensita' dell'associazione monotona. **0,8 non significa 80% di influenza.** La PRCC e' un aggiustamento statistico, non una prova causale e non una simulazione con gli altri input realmente fissi. Relazioni a U, interazioni e regimi diversi possono sfuggire a entrambi i coefficienti.

Per ogni output vengono utilizzate tutte le tratte con nove input finiti e quell'output disponibile, sullo stesso campione per entrambi i metodi. Una tratta con un output mancante puo' rimanere nelle analisi degli altri output. Gli input costanti hanno coefficiente non definito e sono esclusi dai controlli degli altri input. Se ci sono troppi controlli rispetto ai casi, controlli collineari o residui nulli, la PRCC resta `NaN` con una nota: non e' una correlazione zero.

La verifica **leave-one-out** toglie una tratta alla volta e ricalcola anche i ranghi. Minimo e massimo mostrano la sensibilita' ai singoli casi, **non intervalli di confidenza**. Il numero di ricalcoli validi aiuta a riconoscere una PRCC non sempre stimabile. Con circa 40 casi e nove input, le graduatorie rimangono esplorative. Non si calcolano p-value o indici di sensibilita' di Sobol: il campionamento Sobol del DoE e' un'altra cosa.

## Cosa viene salvato

- `statistiche_complete.csv`: coefficienti, numero di casi, posizioni nelle classifiche, intervalli leave-one-out e note per ogni coppia input-output.
- `parametri_da_approfondire.csv`: unione dei primi tre input secondo ciascun metodo, per ogni output. Non e' una selezione definitiva e non garantisce coefficienti elevati.
- `matrice_spearman.csv` e `matrice_prcc.csv`: righe = input, colonne = output.
- `correlazioni_tra_input.csv`: associazioni tra i fattori, sul campione con input completi e almeno un output.
- `dati_importati.csv`: dati unificati, colonne derivate e provenienza dei file/fogli.
- `campioni_utilizzati.csv`: per ogni tratta, indica se viene usata per ciascun output.
- `dizionario_variabili.csv` e `impostazioni.csv`: significati, unita', direzione e configurazione dell'analisi.
- `grafici/`: sei mappe di coefficienti, cinque scatter e una mappa a due input. Ogni figura viene salvata come PNG a 300 dpi e FIG modificabile in MATLAB. I file `*_punti.csv` conservano i punti degli scatter con i loro ID.

I CSV si aprono con Excel. Se Excel non separa automaticamente le colonne, usare **Dati > Da testo/CSV**, separatore virgola e riconoscimento dei numeri con punto decimale. Le tabelle salvate non si aggiornano da sole: dopo l'aggiunta di risultati bisogna rilanciare il programma.

### Attenzione ai sostituti del degrado

Negli Excel disponibili il degrado e' rappresentato indirettamente dal numero di sostituzioni nei 20 anni. Questo dipende anche dall'utilizzo annuo e non misura il degrado fisico per singolo viaggio. Per analizzare direttamente il degrado servirebbero, per esempio, perdita di SOH e perdita di tensione FC per viaggio.

Gli Excel possono contenere contatori FC anche con potenza FC nulla. `num_repl_FC_active` conserva i contatori soltanto quando `P_nom_fc_kW > 0`; altrimenti e' non applicabile. Il contatore originale `num_repl_FC` resta intatto. Non vengono esclusi i casi con FC positiva ma piccola sulla base di una soglia arbitraria.

## Modificare e aggiungere gli scatter

Nella sezione 1 di `analisi_DOE.m` modificare la lista `grafici_scatter`. Ogni riga contiene **asse X, asse Y, colore**. Per esempio, aggiungere prima della parentesi finale:

```matlab
'slope_std', 'H2_kg_km', 'L_km';
'stop_density_requested', 'num_repl_batt', 'L_km';
```

Usare i nomi esatti elencati nelle liste `input` e `output`. I grafici mostrano i valori originali con le loro unita', non ranghi o residui. I colori aiutano a vedere se la relazione cambia insieme a un terzo parametro, ma **non dimostrano da soli un'interazione**. Il campione del grafico puo' essere piu' piccolo del campione della correlazione se la variabile scelta come colore ha dati mancanti.

La sezione 7 contiene anche una mappa con velocita' e densita' di fermate sugli assi e TCO come colore. Per crearne una diversa, duplicare la chiamata `crea_scatter`, sostituire i tre nomi delle colonne e assegnare un nome di salvataggio diverso. Nessuna superficie viene interpolata: gli altri input variano tra i punti, quindi la mappa e' una proiezione del dataset.

Per costruire liberamente un grafico dalla Command Window, recuperare prima `dati` come nell'esempio di avvio, poi usare questo modello:

```matlab
x = dati.slope_std;
y = dati.H2_kg_km;
colore = dati.L_km;
usa = dati.input_completi & isfinite(x) & isfinite(y) & isfinite(colore);
figure;
scatter(x(usa), y(usa), 65, colore(usa), 'filled');
xlabel('Variabilita pendenza [per mille]');
ylabel('Consumo H2 [kg/km]');
cb = colorbar;
cb.Label.String = 'Lunghezza della sola andata [km]';
title(sprintf('Pendenza e consumo H2 (N=%d)', sum(usa)));
grid on;
```

## Come usarlo nel lavoro di tesi

Lavorare sul dataset condiviso completo, non soltanto sulle proprie simulazioni. Per ogni output scegliere due o tre input da approfondire, confrontando coefficienti, stabilita' e ragionamento fisico. Verificare gli scatter, discutere casi particolari e possibili regimi diversi. Non scartare un parametro fisicamente importante soltanto perche' la sua correlazione monotona e' bassa.

Alcuni output sono legati dalle formule del modello: manutenzioni proporzionali ai CAPEX, costo H2 proporzionale al consumo specifico, ecc. Coefficienti identici non sono conferme indipendenti. Inoltre, i risultati riguardano **configurazioni ottimizzate**: cambiano insieme sia la tratta sia il powertrain. Non descrivono automaticamente la risposta di un treno con m e n fissati.
