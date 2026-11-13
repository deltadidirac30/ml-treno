# Il surrogato, passo per passo

Il surrogato è un modello che impara dagli esempi. Gli mostriamo milioni di casi già simulati (tratta, m, n → risultati del simulatore), e lui impara a indovinare i risultati di casi nuovi in una frazione di millisecondo invece che in decine di millisecondi.

Dati: campagna P9_D28_16384, cioè 16384 tratte DoE × 288 coppie (m, n), andata e ritorno: 4,7 milioni di casi simulati sul PC Windows.

## Passo 1: descrivere le tratte con dei numeri (gli ingressi)

13/11/2026. Report: `fase5/REPORT_FASE5_INGRESSI.md`.

- **Le tratte sono quelle della campagna.** Lo zip copiato dal PC è integro. Su tutte le 16384 tratte tornano l'impronta della pendenza, la lunghezza, le fermate, la velocità massima e il numero di limiti.
- **Rivalutazione sul Mac.** 256 casi rifatti sul Mac con lo stesso percorso della campagna danno gli stessi esiti. Le grandezze continue differiscono al più di 3·10⁻¹² della loro scala: è la differenza di macchina tra PC e Mac (FMA). Tolleranza relativa accettata il 13/11.
- **Gli ingressi.** Su ogni tratta ci sono le 66 caratteristiche della fase 1, con lo stesso codice: lunghezza, salite, limiti, fermate, durata minima teorica… Nessun valore mancante.
- **Il DoE nuovo è molto più largo della fase 1:** pendenze fino a ±40‰, lunghezze da 5 a 300 km, limiti da 30 km/h.
- **Dominio.** Le tratte reali (Calabria, Canavese, Firenze) sono tutte dentro il campo coperto dalle tratte DoE. Delle 166 linee della rete, 123 sono dentro e 43 escono di poco: al più 2 caratteristiche su 66, soprattutto pendenze massime e numero di fermate.
- **Decisioni:**
  - Sulmona–Carpinone resta in `tratte_reali` ma non si usa;
  - `vlim_mean` (che è la media dei 10 `bin_v`) si tiene;
  - `fc_non_erogata_kWh` è uno zero numerico e non serve al surrogato.

## Passo 2: la tabella di addestramento

13/11/2026. Report: `fase6/REPORT_FASE6_TABELLA.md`.

- **Una riga per caso simulato:** 4 718 523 righe, cioè tutti i casi meno le 69 righe in errore del simulatore. Ogni riga ha le 66 caratteristiche della tratta, m e n, le grandezze da indovinare, l'esito e il costo veri.
- **Divisione per tratta**, sui 16 gruppi Sobol da 1024 tratte:
  - addestramento: 12 gruppi, 12 288 tratte;
  - validazione: 2 gruppi, 2048 tratte;
  - test: 2 gruppi, 2048 tratte, da guardare una sola volta alla fine.

  Nessuna tratta sta in due gruppi, e i tre gruppi si somigliano in tutto (esiti, caratteristiche, grandezze).
- **Tratte segnalate:** 2366, 14664 (righe in errore) e 13258 (oltre 12 h). Restano nella tabella, segnate da una colonna, per poterle escludere dopo.
- **Regola D3 a posteriori**, idea del 13/11: il surrogato prevede tutto su ogni caso, e lo scarto si decide dopo con "C-rate di scarica > 20 → scartato". La regola ritrova il 99,56% degli scarti e non scarta mai un caso buono.
- Il consumo di idrogeno manca nei casi scartati, quindi si impara solo sui casi completati.

## Passo 3: primo modello su una sola grandezza (la durata del viaggio)

13/11/2026. Report: `fase7/REPORT_FASE7_DURATA.md`.

Il passo 3 è fatto: il boosting impara la durata del viaggio con un errore mediano dello 0,65% su 2048 tratte mai viste, contro il 4% del modello più semplice. In tutto sono serviti circa 11 minuti di calcolo.

I risultati sulla validazione (589 824 casi):

| modello | errore mediano | 95° percentile | caso peggiore |
|---|---:|---:|---:|
| A: costante × durata minima teorica | 4,1% | 17% | 30% |
| B: lineare (durata minima, m, n) | 4,2% | 29% | 137% |
| C: boosting, 2048 tratte di addestramento | 1,37% | 5,3% | 23% |
| D: boosting, 12 288 tratte di addestramento | 0,65% | 2,8% | 21% |

Cosa ci dicono i numeri:
1. Il boosting aggiunge molto. Nel grafico "previsto contro vero" il modello semplice fa delle righe orizzontali, perché non vede che il treno pesa di più con m e n. Il boosting sta sulla diagonale.
2. Il numero di tratte conta più delle impostazioni. Con 6 volte più tratte l'errore si dimezza. Cambiare profondità degli alberi e velocità di apprendimento sposta molto meno.
3. Il modello sbaglia la tratta, non m e n. L'errore è piatto in m e in n e quasi costante dentro una tratta. Il modello impara bene l'effetto del peso del treno, ma stima male la durata di base di alcune tratte nuove.
4. Le tratte corte sono le più difficili. Sotto i 25 km l'errore mediano è il 2%, con un massimo del 21%. Sopra i 200 km è lo 0,46%.
5. C'è margine per migliorare. Il rumore numerico della durata vale lo 0,01%, quindi il modello è 65 volte sopra il minimo possibile. Sulle tratte che ha già visto sbaglia lo 0,13%, su quelle nuove lo 0,65%: il limite è generalizzare a tratte nuove.
6. È veloce: circa 70 µs a caso su un thread, contro 25–50 ms di una simulazione, quindi circa 500 volte più veloce.

Le importanze: il modello usa soprattutto la durata minima teorica (77%) e la lunghezza (15%), poi velocità media, fermate e dislivello.

Il grafico dell'importanza era uscito con le etichette sull'asse sbagliato. L'ho ridisegnato dai dati salvati, senza rifare il calcolo. Ho anche rilanciato tutto una seconda volta: i numeri sono identici, perché il modello è deterministico con il seme.

Per il confronto con quello che stai studiando:
- la combinazione migliore ha alberi bassi (profondità 6) e passo piccolo (0,05), ed è sul bordo della griglia provata: valori ancora più piccoli potrebbero andare meglio;
- l'arresto anticipato si è fermato a 3055 alberi, ma la curva era già quasi piatta da 1500.

Prima di passare alle altre grandezze proporrei una piccola prova. Invece della durata in secondi, il modello impara il rapporto durata / durata minima teorica, che vale circa 1,06. Agli alberi resta da imparare solo una correzione, e tratte corte e lunghe pesano allo stesso modo. È il rimedio più probabile ai punti 3 e 4, e costa circa 10 minuti di calcolo.

Figure e scheda sono in ml_treno/fase7 (REPORT_FASE7_DURATA.md, figure/). Ho fatto il commit locale (ace10fc): ml_treno ha 2 commit da pushare, quando me lo dici.

## Passo 3b: la durata come rapporto durata / durata minima

13/11/2026. Report: `fase7/REPORT_FASE7_DURATA.md`, sezione "Passo 3b".

**L'idea.** Invece della durata in secondi, il modello impara il rapporto r = durata / durata minima teorica, cioè di quanto la durata vera supera quella con il treno sempre ai limiti di velocità. r vale da 1,00 a 1,52, tipicamente 1,07. La durata si ricava moltiplicando r̂ per la durata minima.

**Il risultato:** un grande miglioramento, a parità di dati e di algoritmo.

| modello | errore mediano | 95° percentile | caso peggiore |
|---|---:|---:|---:|
| D: boosting sulla durata in secondi | 0,65% | 2,8% | 21% |
| E: boosting sul rapporto | **0,25%** | **1,3%** | **4,9%** |

**Cosa ci dicono i numeri:**
1. **L'obiettivo giusto conta più dei dati.** Con solo 2048 tratte il rapporto (0,36%) fa già meglio della durata in secondi con 12 288 tratte (0,65%).
2. **Le tratte corte migliorano di più:** sotto i 25 km l'errore mediano passa dal 2,1% allo 0,5%, il caso peggiore dal 21% al 4,4%. Con il rapporto tutte le tratte pesano allo stesso modo nell'addestramento.
3. **Il modello generalizza meglio:** sulle tratte viste sbaglia lo 0,16%, su quelle nuove lo 0,25%. Con D la differenza era molto più grande (0,13% contro 0,65%).
4. **Il modello ora "guarda" la fisica giusta.** Le caratteristiche più usate sono la velocità alle fermate, la velocità media e la densità delle fermate: il tempo perso rispetto alla durata minima viene da accelerazioni e frenate.
5. **L'errore resta soprattutto "di tratta"** (96%): dentro una tratta il modello segue bene l'effetto di m e n.
6. **C'è ancora un po' di margine:** la combinazione migliore (alberi di profondità 4) è di nuovo sul bordo della griglia, e il modello si è fermato al tetto di 4000 alberi con l'errore che scendeva ancora piano.

**Lezione per le altre grandezze:** quando c'è una scala fisica naturale, conviene far imparare al modello una grandezza relativa o adimensionale, non il valore assoluto.

## Passo 4: le altre grandezze

13/11/2026. Report: `fase8/REPORT_FASE8_GRANDEZZE.md`.

**Cosa abbiamo fatto.** La stessa ricetta della durata, sulle altre 7 grandezze. Per ognuna il modello impara una versione con la sua scala fisica:
- serbatoio e idrogeno per km;
- vite e C-rate in logaritmo;
- il SOC così com'è;
- la scarica come sì/no.

Il confronto semplice è la mediana di ogni coppia (m, n), che non guarda la tratta. Circa 49 minuti di calcolo.

**I risultati** (errori su 2048 tratte mai viste):

| grandezza | confronto semplice (mediana) | boosting: mediana | boosting: 95° percentile |
|---|---:|---:|---:|
| massa del serbatoio | 19,8% | 3,3% | 14,6% |
| idrogeno consumato | 19,8% | 3,4% | 14,5% |
| SOC finale (errore assoluto) | 0,142 | 0,031 | 0,156 |
| scarica (sì/no) | 82,6% giusta | 98,8% giusta | — |
| vita della batteria | 42% | 3,7% | 14,4% |
| vita della fuel cell | 14,4% | 2,5% | 8,3% |
| C-rate di scarica | 0,42% | 0,68% | 4,3% |

**Cosa ci dicono i numeri:**
1. **Il boosting migliora tutto di 5–10 volte** rispetto al confronto semplice. Fa eccezione il C-rate in mediana: dipende quasi solo da n, e la mediana della coppia lo indovina già. Il boosting migliora però molto i casi difficili (95° percentile: 4,3% contro 15%).
2. **La tua regola D3 a posteriori funziona anche con il C-rate previsto:** è giusta nel 99,986% dei casi. Su 12 255 scarti veri ne perde 59 e ne aggiunge 22.
3. **Il vincolo SOC ≥ 0,2** è previsto giusto nel 97,5% dei casi. Il SOC è la grandezza più difficile: ha scalini e valori accumulati a 0 e a 0,9.
4. **I modelli sono "corti", non "sovradattati".** Tutti si fermano al tetto di 3000 alberi, e sbagliano quasi uguale sulle tratte viste e su quelle nuove. Con più capacità possono migliorare ancora.
5. **Qui l'errore dipende da m e n**, al contrario della durata: queste grandezze cambiano a scatti in (m, n), soprattutto alle soglie della logica di controllo (D25) e tra sola batteria e ibrido.

**Un incidente.** Il primo lancio è rimasto bloccato 20 minuti per un errore nello script (un calcolo ripetuto mezzo milione di volte). L'ho fermato, corretto e rilanciato; i risultati sono del secondo lancio.

## Decisioni prima del passo 5 (13/11/2026)

Numeri in `fase8/risultati/02_decisioni.txt` (script `fase8/02_decisioni.jl`).

**Il surrogato finale sarà un'unica rete neurale con più uscite.** Il boosting resta come riferimento da battere.

1. **Tratte segnalate:**
   - 2366 e 13258 restano nell'addestramento;
   - la 14664 (test) resta per gli errori grandezza per grandezza, ma si esclude dal confronto sull'ottimo: delle sue 288 coppie ne mancano 64, ed è lì che cade spesso la migliore.
2. **Energia di ricarica negativa** (credito nel costo quando il SOC finale supera lo 0,8 iniziale): resta come nel simulatore. Azzerarlo cambierebbe la coppia migliore in 431 tratte su 16 384 (+0,65% di costo in mediana). Se ne riparla dopo, anche con il relatore: la rete non va riaddestrata, perché prevede il SOC finale, non il costo.
3. **Batterie che durano poco:** nessun vincolo, come nel simulatore. La migliore ha la batteria sotto 1 anno in 96 tratte; con un vincolo "≥ 1 anno" cambierebbe in quelle 96 (+1,3% di costo in mediana). Si può aggiungere dopo, sulla vita prevista, senza riaddestrare.

**Prossimo passo: il 5**, il banco di prova del surrogato (costo, fattibilità, ottimo per tratta), collaudato con il boosting.
