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

## Passo 5a: dal surrogato al costo, caso per caso

16/11/2026. Report: `fase9/REPORT_FASE9_COSTO.md`.

**Cosa abbiamo fatto.** Abbiamo costruito il "banco di prova": dalle 8 grandezze di un caso calcola vincoli, fattibilità e costo con le stesse regole del simulatore. Il collaudo è perfetto: con le grandezze vere ridà il simulatore su tutti i 589 824 casi della validazione. Poi lo abbiamo usato con le grandezze previste dal boosting. Meno di un minuto di calcolo.

**I risultati:**

| | risultato |
|---|---|
| fattibilità giusta | 98,1% dei casi |
| fattibili scartati per errore | 2,7% |
| non fattibili promossi per errore | 1,3% |
| errore del costo (casi fattibili): mediana / 95° percentile | 2,4% / 9,9% |
| … negli ibridi | 2,4% / 9,2% |
| … a sola batteria | 6,5% / 23% |

**Cosa ci dicono i numeri:**
1. **Il costo sbaglia per due sole grandezze:** l'idrogeno negli ibridi, che è la voce di costo più grande, e il SOC finale a sola batteria, dove l'energia di ricarica è quasi tutto il costo. Durata, serbatoio e vite pesano pochissimo.
2. **La fattibilità sbaglia soprattutto per il SOC** (metà degli errori), poi la scarica e la massa. La tua regola D3 non sbaglia quasi mai.
3. **Il credito dell'energia di ricarica amplifica gli errori sul SOC.** Su una tratta di 5 km il surrogato prevede un SOC finale sopra lo 0,8 e il costo diventa addirittura negativo.
4. **Per la rete neurale le priorità sono idrogeno e SOC finale.**

**Prossimo: passo 5b**, la scelta della coppia migliore fra le 288 di ogni tratta.

## Passo 5b: la scelta della coppia migliore fra le 288

16/11/2026. Report: `fase9/REPORT_FASE9_COSTO.md`, sezione "Passo 5b". Figura: `fase9/figure/fig_rimpianto.png`.

**Cosa abbiamo fatto.** Per ognuna delle 2048 tratte di validazione abbiamo confrontato la coppia (m, n) migliore secondo il simulatore con quella scelta dal surrogato (il boosting), fra le 288 coppie simulate. Due misure: quanto costa di più la scelta del surrogato (il "rimpianto") e quante volte è in realtà non fattibile. Pochi secondi di calcolo.

**Il risultato principale:** usato da solo, il surrogato sceglie un progetto in realtà non fattibile nel **18% delle tratte**. Con 5 simulazioni di verifica questa quota scende allo 0,3%.

**Le strategie a confronto** (2048 tratte di validazione):

| strategia | scelte non fattibili | rimpianto mediano | 95° percentile | tratte entro l'1% |
|---|---:|---:|---:|---:|
| **surrogato da solo** | **18,2%** | 1,0% | 14,7% | 41% |
| surrogato + verifica delle prime 3 | 2,5% | 0,35% | 12,9% | 60% |
| surrogato + verifica delle prime 5 | 0,3% | 0,09% | 12,7% | 65% |
| surrogato + verifica delle prime 10 | 0% | 0,00% | 12,7% | 69% |
| migliore della tratta di addestramento più simile | 36% | 2,6% | 40% | 22% |
| coppia fissa più frequente | 60% | 40% | 71% | 7% |

"Verifica delle prime k" vuol dire che il simulatore controlla le k coppie migliori secondo il surrogato, circa k × 50 ms, e si tiene la migliore davvero fattibile. Il rimpianto è quanto costa di più la scelta rispetto alla migliore vera.

**Cosa ci dicono i numeri:**
1. **Il surrogato sceglie quasi sempre vicino alla migliore.** Indovina il regime (sola batteria o ibrido) nel 97% delle tratte, e la sua scelta è in mediana la seconda migliore fra le fattibili. Copiare la tratta più simile, senza surrogato, fa molto peggio.
2. **Ma una volta su cinque la sua scelta viola di poco un vincolo, ed è la "maledizione del vincitore".** L'ottimo sta sul bordo dei vincoli, e cercando la coppia più economica il surrogato finisce proprio dove un piccolo errore sbaglia la fattibilità. Delle 373 scelte non fattibili:
   - 255 violano il SOC finale, con un SOC previsto di 0,211 contro 0,173 vero;
   - 106 violano la scarica, con una probabilità prevista appena sotto 0,5;
   - 34 violano la massa.
3. **Bastano poche simulazioni per rimediare.** Con 5 verifiche, circa un quarto di secondo per tratta, le scelte non fattibili scendono allo 0,3% e il rimpianto mediano allo 0,09%.
4. **Resta una coda** (95° percentile intorno al 13%, anche con 10 verifiche). Sono tratte in cui la migliore è a sola batteria e il surrogato preferisce un ibrido con m ≈ 0,1, oppure in cui gli errori di costo spostano molto la classifica.

**Come continuare.** Prima di passare a 5c o alla rete neurale, una piccola prova: un **margine di sicurezza sui vincoli**. Il surrogato considera fattibile un progetto solo se il SOC previsto è almeno 0,2 + δ e la probabilità di scarica è sotto una soglia più bassa di 0,5. Si provano alcuni margini e si misurano scelte non fattibili e rimpianto, con e senza le verifiche. Ci dice se il problema si risolve con una regola semplice, e quale margine usare poi anche con la rete neurale.

## Prova dei margini di sicurezza (dopo il passo 5b)

16/11/2026. Report: `fase9/REPORT_FASE9_COSTO.md`, sezione "Prova dei margini di sicurezza". Figura: `fase9/figure/fig_margini.png`.

**L'idea.** Per evitare che il surrogato scelga progetti al limite dei vincoli, gli chiediamo un margine di sicurezza: considera fattibile un progetto solo se il SOC previsto è almeno 0,2 + δ, la probabilità di scarica è sotto una soglia più bassa di 0,5, e la massa prevista sta qualche centinaio di kg sotto il limite. Abbiamo provato 96 combinazioni di margini, con e senza le simulazioni di verifica. 7 secondi di calcolo, nessuna simulazione nuova. I margini sono scelti sulla validazione: il giudizio finale andrà confermato sul test.

**I risultati principali:**

| strategia | scelte non fattibili | rimpianto mediano | 95° percentile |
|---|---:|---:|---:|
| surrogato da solo, nessun margine | 18,2% | 1,0% | 14,7% |
| surrogato da solo, margini medi (SOC + 0,03, scarica < 0,2, massa − 200 kg) | 4,5% | 2,1% | 22% |
| surrogato da solo, margini forti (SOC + 0,05, scarica < 0,1, massa − 200 kg) | 1,9% | 3,2% | 25% |
| **surrogato + verifica delle prime 5, nessun margine** | **0,3%** | **0,09%** | **12,7%** |
| surrogato + verifica delle prime 5, scarica < 0,1 | 0,05% | 0,37% | 13,6% |

**Cosa ci dicono i numeri:**
1. **I margini riducono le scelte sbagliate, ma costano caro.** Per scendere sotto il 2% di scelte non fattibili senza simulazioni, il rimpianto mediano triplica (dall'1% al 3,2%) e il 95° percentile passa dal 15% al 25%. Il margine allontana la scelta dal bordo dei vincoli, ed è proprio lì che sta l'ottimo.
2. **Il margine sulla scarica è il più conveniente** (scelte sbagliate dal 18% al 12% quasi gratis). Quello sul SOC è il più efficace ma il più caro. Quello sulla massa serve poco.
3. **Poche simulazioni di verifica battono qualunque margine.** Con 5 verifiche e nessun margine le scelte non fattibili sono lo 0,3% e il rimpianto mediano lo 0,09%. Aggiungere margini alla verifica peggiora: toglie dai candidati proprio le coppie migliori.
4. **Il vero problema è la precisione del SOC finale** (errore tipico 0,03): troppo grande perché un margine piccolo basti.

**Conclusione:**
- per ora nessun margine;
- la strategia di riferimento è il **surrogato + verifica delle prime 5 coppie** con il simulatore (circa un quarto di secondo per tratta);
- per usare il surrogato da solo serve un modello del SOC più preciso: è la priorità della rete neurale;
- con la rete proveremo anche a stimare direttamente la probabilità che un progetto sia fattibile, al posto della soglia secca.

## Passo 5c: l'ottimo cercato su una griglia fitta di (m, n)

16/11/2026. Report: `fase9/REPORT_FASE9_COSTO.md`, sezione "Passo 5c". Figure: `fase9/figure/fig_griglia_rimpianto.png` e `fig_linee.png`.

**Cosa abbiamo fatto.** Su 256 tratte di validazione il surrogato (il boosting) ha cercato il progetto migliore su una griglia fitta di quasi 10 000 punti (m, n) per tratta, invece che fra le sole 288 coppie della campagna. Il simulatore vero, invariato e con la stessa configurazione della campagna, ha poi verificato le 5 proposte migliori del surrogato, scelte distanti fra loro. È la prima volta dal passo 1 che usiamo di nuovo il simulatore: 1280 simulazioni in 18 secondi. Circa 5 minuti in tutto.

**A cosa serve, con il boosting:** soprattutto come confronto. Prepara il "motore" di ricerca che userà il surrogato finale, e dà alla rete neurale il riferimento da battere.

**I risultati** (costo vero della scelta rispetto alla migliore delle 288 coppie: un numero negativo vuol dire che la griglia fitta ha trovato di meglio):

| strategia | scelte non fattibili | costo, mediana | 10% delle tratte migliori | 95° percentile | tratte con un progetto migliore delle 288 |
|---|---:|---:|---:|---:|---:|
| 288 coppie, surrogato da solo | 22% | +0,9% | 0% | +12% | — |
| 288 coppie + verifica delle prime 5 | 0,8% | 0,0% | 0% | +9,2% | — |
| griglia fitta, surrogato da solo | **48%** | +0,4% | −2,6% | +8,2% | 16% |
| **griglia fitta + verifica delle prime 5** | **10,5%** | 0,0% | **−4,3%** | **+5,6%** | **43%** |

**Cosa ci dicono i numeri:**
1. **La ricerca fitta trova progetti migliori di quelli della campagna.** Con 5 verifiche, in quasi metà delle tratte il progetto scelto costa meno della migliore delle 288 coppie simulate, e in un decimo delle tratte almeno il 4% in meno. Anche i casi peggiori migliorano (95° percentile +5,6% contro +9,2%).
2. **Ma la maledizione del vincitore peggiora.** Fra quasi 10 000 punti il surrogato trova punti ancora più vicini al bordo dei vincoli, e punti dove i suoi errori lo rendono troppo ottimista. Da solo sceglie un progetto non fattibile in quasi metà delle tratte, e anche con 5 verifiche nel 10,5%.
3. **I gradini del boosting.** Lungo una linea in m il costo previsto non ha tratti piatti, ma fa piccoli zig-zag dell'1–3% fra punti vicini, che il simulatore non ha. In qualche zona sta sistematicamente sopra o sotto il vero. Una ricerca fitta "sfrutta" proprio queste oscillazioni.
4. **Per il preconfiguratore** la ricerca fitta conviene, ma con una verifica più robusta: più candidati, un ripiego sulle migliori fra le 288 coppie, o una breve ricerca locale con il simulatore attorno alla proposta del surrogato.
5. **Per la rete neurale:** previsioni lisce in (m, n) e un SOC più preciso dovrebbero ridurre proprio questi due problemi. Questi numeri sono il riferimento da battere.

**Prossimo: passo 6**, la rete neurale unica.

## Passo 6a: la rete neurale, prova breve

16/11/2026. Report: `fase10/REPORT_FASE10_RETE.md`.

**Cosa abbiamo fatto.** Abbiamo preparato la rete neurale unica, così come proposta:
- 73 ingressi: le 66 caratteristiche, m, n, più gli indicatori esatti di ibrido e delle fasce D25;
- 4 strati da 256 neuroni;
- 8 uscite con le funzioni "fisiche".

Poi l'abbiamo addestrata per prova su una piccola parte dei dati: 2048 tratte, 5 epoche, circa un minuto.

**Cosa ci dice la prova:**
1. **Tutto funziona:** dati e maschere sono giusti, la perdita scende a ogni epoca, e le previsioni rispettano la fisica per costruzione (SOC tra 0 e 0,9, durata sopra la minima, masse e vite positive). Due lanci danno lo stesso risultato.
2. **I tempi:** l'addestramento completo richiederà circa 45–50 secondi per epoca, cioè 30–35 minuti per 40 epoche.
3. **La rete è velocissima a prevedere:** 2,5 µs a caso, contro 45 µs degli 8 modelli del boosting.
4. **Prime metriche**, non ancora alla pari con il boosting, perché la rete ha visto un sesto dei dati per poche epoche: già vicina sul SOC finale (0,039 contro 0,031), più lontana su C-rate e vita della batteria, che dovrebbero migliorare con l'addestramento completo.

**Prossimo: passo 6b**, l'addestramento completo.

## Passo 6b: la rete neurale, addestramento completo

16/11/2026. Report: `fase10/REPORT_FASE10_RETE.md`, sezione "Passo 6b". Figura: `fase10/figure/fig_curve.png`.

**Cosa abbiamo fatto.** Abbiamo addestrato la rete neurale unica su tutte le 12 288 tratte di addestramento: 40 epoche, 35 minuti. Poi l'abbiamo misurata sulle 2048 tratte di validazione, grandezza per grandezza, accanto al boosting.

**I risultati** (errori su tratte mai viste):

| grandezza | rete neurale: mediana / 95° percentile | boosting: mediana / 95° percentile |
|---|---:|---:|
| durata | **0,16% / 0,9%** | 0,25% / 1,3% |
| serbatoio | **1,7% / 8,8%** | 3,3% / 14,6% |
| idrogeno | **1,7% / 8,5%** | 3,4% / 14,5% |
| SOC finale (errore assoluto) | **0,012 / 0,108** | 0,031 / 0,156 |
| vita della batteria | **2,4% / 10,8%** | 3,7% / 14,4% |
| vita della fuel cell | **1,7% / 6,5%** | 2,5% / 8,3% |
| C-rate di scarica | 1,2% / 4,9% | **0,7% / 4,3%** |
| scarica (giusta) | **99,0%** | 98,8% |

**Cosa ci dicono i numeri:**
1. **Un unico modello batte gli 8 modelli del boosting su 7 grandezze su 8.**
2. **Migliora proprio dove serviva:** idrogeno e serbatoio con l'errore dimezzato, e soprattutto il **SOC finale, con un errore mediano 2,5 volte più piccolo** (0,012 invece di 0,031). Era la causa principale degli errori di fattibilità e della maledizione del vincitore.
3. **Il C-rate è l'unica grandezza un po' peggiore.** Serve solo per la regola D3: vedremo nel passo 6c se cambia qualcosa.
4. **La rete non "impara a memoria":** sulle tratte che ha visto sbaglia quasi come su quelle nuove.
5. **C'è ancora margine:** l'ultima epoca è stata la migliore, quindi più epoche o una rete un po' più grande potrebbero migliorare ancora.

**Prossimo: passo 6c**, la rete sul banco di prova: costo, fattibilità e scelta della coppia migliore, contro il boosting.

## Passo 6c: la rete sul banco di prova (costo, fattibilità, scelta)

16/11/2026. Report: `fase10/REPORT_FASE10_RETE.md`, sezione "Passo 6c".

**Cosa abbiamo fatto.** Abbiamo passato le previsioni della rete neurale per lo stesso banco di prova usato con il boosting nei passi 5a e 5b: fattibilità e costo caso per caso, e scelta della coppia migliore fra le 288 di ogni tratta. Abbiamo anche riprovato i margini di sicurezza. 15 secondi di calcolo, nessuna simulazione nuova.

**Caso per caso:**

| | boosting | rete neurale |
|---|---:|---:|
| fattibilità giusta | 98,1% | **98,9%** |
| errore del costo (casi fattibili): mediana / 95° percentile | 2,4% / 9,9% | **1,3% / 5,2%** |
| … a sola batteria | 6,5% / 23% | **2,6% / 10,9%** |

**La scelta del progetto migliore fra le 288 coppie** (2048 tratte):

| strategia | modello | scelte non fattibili | rimpianto mediano | 95° percentile | tratte entro l'1% |
|---|---|---:|---:|---:|---:|
| surrogato da solo | boosting | 18% | 1,0% | 14,7% | 41% |
| surrogato da solo | **rete** | **14%** | **0,0%** | **4,0%** | **70%** |
| + verifica delle prime 3 | boosting | 2,5% | 0,35% | 12,9% | 60% |
| + verifica delle prime 3 | **rete** | **1,0%** | **0,0%** | **2,8%** | **87%** |
| + verifica delle prime 5 | boosting | 0,3% | 0,09% | 12,7% | 65% |
| + verifica delle prime 5 | **rete** | **0,1%** | **0,0%** | **2,3%** | **90%** |

**Cosa ci dicono i numeri:**
1. **La rete sceglie molto meglio del boosting.** In più di metà delle tratte sceglie esattamente la coppia migliore, e i casi peggiori passano da 15% a 4% di costo in più. Con 5 verifiche al simulatore, 9 tratte su 10 sono entro l'1% dalla migliore.
2. **La maledizione del vincitore resta, ma ora si governa.** Da sola la rete sceglie ancora un progetto non fattibile nel 14% delle tratte, quasi sempre per un SOC finale sbagliato di poco proprio sul limite (vero 0,196, previsto 0,213). Ma il suo SOC è preciso, quindi ora un margine piccolo funziona: chiedendo SOC ≥ 0,21 e probabilità di scarica sotto 0,1, le scelte non fattibili scendono al 6,8% senza perdere nulla in costo. Con 3 verifiche, allo 0,2%. Con il boosting un margine utile costava il triplo in rimpianto.
3. **Il costo è più preciso** (1,3% in mediana, contro 2,4%), soprattutto a sola batteria (2,6% contro 6,5%). L'errore che resta viene soprattutto dall'idrogeno negli ibridi.
4. **Il C-rate un po' meno preciso pesa pochissimo:** la regola D3 resta giusta nel 99,9% dei casi, e nessuna scelta sbagliata è dovuta a D3.

**La strategia candidata per il preconfiguratore:** rete neurale + margine piccolo (SOC ≥ 0,21, scarica < 0,1) + verifica delle 3–5 proposte migliori con il simulatore, circa un quarto di secondo per tratta. I margini sono scelti sulla validazione: vanno confermati sul test.

**Prossimo: passo 6d**, la griglia fitta con la rete e le simulazioni di verifica, per vedere se spariscono gli zig-zag e quanto si guadagna rispetto alle 288 coppie.
