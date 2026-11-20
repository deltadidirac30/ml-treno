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

## Passo 6d: la rete sulla griglia fitta

16/11/2026. Report: `fase10/REPORT_FASE10_RETE.md`, sezione "Passo 6d". Figure: `fase10/figure/fig_linee.png` e `fig_griglia_rimpianto.png`.

**Cosa abbiamo fatto.** Come nel passo 5c, ma con la rete neurale: sulle stesse 256 tratte, la rete ha cercato il progetto migliore su una griglia fitta di quasi 10 000 punti (m, n) per tratta, con e senza il margine piccolo (SOC ≥ 0,21, scarica < 0,1). Il simulatore ha verificato le 5 proposte migliori. Un minuto in tutto: la rete valuta 2,5 milioni di punti in 10 secondi, il boosting ne impiegava 250. Poi 2179 simulazioni di verifica in 22 secondi.

**I risultati** (costo vero della scelta rispetto alla migliore delle 288 coppie della campagna; negativo vuol dire che la griglia ha trovato un progetto migliore):

| strategia | scelte non fattibili | mediana | il 10% delle tratte migliori | 95° percentile | tratte con un progetto migliore delle 288 | entro +1% |
|---|---:|---:|---:|---:|---:|---:|
| boosting, griglia + verifica delle prime 5 | 10,5% | 0,0% | −4,3% | +5,6% | 43% | 73% |
| rete, 288 coppie + verifica delle prime 5 | 0% | 0,0% | 0% | +3,3% | — | 88% |
| rete, griglia + verifica delle prime 5 | 6,2% | **−0,3%** | **−7,6%** | **+1,2%** | **62%** | 86% |
| **rete, griglia + margine + verifica delle prime 5** | **1,6%** | −0,2% | −6,8% | +1,7% | 61% | **89%** |

**Cosa ci dicono i numeri:**
1. **Con la rete la ricerca fitta conviene davvero.** In 6 tratte su 10 trova un progetto più economico del migliore fra le 288 coppie simulate nella campagna, e in una tratta su dieci almeno il 7–8% più economico. Il caso peggiore è appena +1,2%.
2. **Con il margine piccolo le scelte non fattibili scendono all'1,6%**, contro il 10,5% del boosting, quasi senza perdere il guadagno.
3. **La rete è liscia e segue il simulatore** (figura delle linee): quasi sovrapposta alla curva vera, compreso lo scalino della soglia D25 a m ≈ 0,1. Gli zig-zag del boosting sono spariti: la rete è 20–40 volte più liscia, e sbaglia il costo lungo le linee dello 0,5–1,4% contro il 2–5% del boosting.
4. **La scelta senza verifica resta rischiosa** (18–41% non fattibile): fra 10 000 punti il più economico sta quasi sempre sul bordo dei vincoli. Servono sempre le poche simulazioni di verifica.

**La strategia di riferimento per il preconfiguratore:** rete neurale sulla griglia fitta + margine piccolo + verifica delle 5 proposte migliori con il simulatore. Costa circa un quarto di secondo per tratta, e trova progetti in media migliori di quelli della campagna da 288 coppie. Va confermata sul test (passo 8).

## Passo 6e: una variante della rete (più epoche e "probabilità di fattibilità")

16/11/2026. Report: `fase10/REPORT_FASE10_RETE.md`, sezione "Passo 6e".

**Cosa abbiamo provato.** Due modifiche insieme alla rete del passo 6b:
- più epoche (60 invece di 40);
- una nona uscita che stima direttamente la probabilità che il progetto sia fattibile, per vedere se aiuta contro la maledizione del vincitore.

32 minuti di addestramento.

**Cosa è successo:**
1. **L'addestramento si è fermato prima, all'epoca 39.** Con 60 epoche in programma il passo di apprendimento resta più alto più a lungo, la misura sulla validazione oscilla di più, e l'arresto anticipato è scattato su un'oscillazione. La prova "più epoche" quindi non è riuscita davvero.
2. **La variante è un po' peggiore della rete 6b su tutte le grandezze** (per esempio idrogeno 1,9% contro 1,7%).
3. **La "probabilità di fattibilità" funziona bene (98,8% giusta) ma non aggiunge nulla:** è giusta quanto i vincoli calcolati dalle grandezze previste, e i due sono d'accordo nel 99,5% dei casi.
4. **Contro la maledizione del vincitore non esiste un rimedio gratuito senza simulazioni.** Con una soglia severa (probabilità ≥ 0,95) la scelta del surrogato da solo è quasi sempre fattibile (98%), ma costa di più: rimpianto mediano 0,5%, casi peggiori +9%. Lo stesso vale per i margini: anche il margine piccolo fa salire i casi peggiori (95° percentile dal 4% al 6%).
5. **La soluzione migliore resta quella del passo 6d:** la rete 6b e poche simulazioni di verifica (5 verifiche, nessun margine: 0,1% di scelte non fattibili, 90% delle tratte entro l'1%).

**Decisione proposta:** il modello di riferimento resta la rete 6b. La testa di fattibilità non serve. Più epoche si potrebbero riprovare con un arresto anticipato più paziente (circa 50 minuti), ma dalle curve il guadagno atteso è piccolo.

## Quanto è più veloce la rete del simulatore

16/11/2026. Report: `fase10/REPORT_FASE10_RETE.md`, sezione "Velocità".

Misurato sul Mac (M4), alla pari, su un solo core: simulatore vero contro rete 6b. Per la rete è incluso il calcolo di costo e vincoli dalle grandezze previste, cioè lo stesso risultato utile.

| | tempo per progetto | quante volte più veloce |
|---|---:|---:|
| simulatore (media su 12 tratte × 24 coppie; da 0,6 a 44 ms) | 12 ms | — |
| rete, un progetto da solo | 40 µs | ~300× |
| rete, le 288 coppie di una tratta insieme | 6 µs a progetto | ~1900× |
| rete, la griglia fitta di una tratta (9702 punti) | 5 µs a progetto | ~2400× (4100× con 8 core) |

**Esempi:**
- **Le 288 coppie di una tratta:** simulatore ≈ 3,5 s, rete ≈ 2 ms.
- **La griglia fitta di una tratta (quasi 10 000 progetti):** simulatore ≈ 2 minuti, rete ≈ 0,05 s.
- **La griglia fitta su tutte le 166 linee della rete ferroviaria:** simulatore ≈ 5 ore e mezza su un core, rete ≈ 8 secondi.
- **Tutta la campagna (4,7 milioni di progetti):** sul PC con 16 core ci sono volute circa 5 ore; la rete la rifarebbe in circa 25 secondi su un core.
- **Nel preconfiguratore:** griglia fitta con la rete (0,05 s) + 5 simulazioni di verifica (≈ 0,06 s) = circa un decimo di secondo per tratta, contro 2 minuti per la sola griglia simulata.

Il prezzo si paga una volta sola: la campagna (5 ore sul PC) e l'addestramento (35 minuti). Il guadagno è più piccolo sulle tratte corte e semplici (~100×) e più grande su quelle lunghe e difficili (oltre 9000×), perché il tempo della rete non dipende dalla tratta.

## Passo 7: rifiniture (quanti dati servono, dove sbaglia la rete)

16/11/2026. Report: `fase11/REPORT_FASE11_RIFINITURE.md`. Figure: `fase11/figure/`.

### 7a: quanti dati servono

**Cosa abbiamo fatto.** Abbiamo riaddestrato la rete con 2048, 4096 e 8192 tratte (sottoinsiemi annidati dei gruppi di addestramento), con le stesse impostazioni, e l'abbiamo confrontata con quella da 12 288 tratte. 38 minuti di calcolo.

| tratte di addestramento | 2048 | 4096 | 8192 | 12 288 |
|---|---:|---:|---:|---:|
| idrogeno (errore mediano) | 3,0% | 2,3% | 1,9% | 1,7% |
| SOC finale (errore assoluto) | 0,020 | 0,016 | 0,013 | 0,012 |
| costo (errore mediano) | 2,1% | 1,7% | 1,4% | 1,3% |
| con 5 verifiche: tratte entro l'1% dalla migliore | 77% | 84% | 88% | 90% |
| surrogato da solo: scelte non fattibili | 13% | 14% | 16% | 14% |

**Cosa ci dicono i numeri:**
1. **Più tratte migliorano ancora tutto, senza segni di saturazione.** Ogni raddoppio riduce gli errori di circa il 20%. Con altre 16 384 tratte (una nuova campagna, circa 5 ore sul PC) ci si può aspettare un altro 20% in meno.
2. **La scelta del surrogato da solo resta non fattibile nel 13–16% delle tratte, qualunque sia la quantità di dati.** La maledizione del vincitore non dipende dalla precisione media, ma da quella proprio sul bordo dei vincoli.

### 7b: dove sbaglia la rete

**Cosa abbiamo fatto.** Abbiamo guardato gli errori della rete per tipo di tratta, per zona di (m, n), vicino ai limiti, e in funzione della distanza dalle tratte di addestramento. Pochi secondi.

**Cosa ci dicono i numeri:**
1. **Le tratte "piccole" sono le più difficili** (corte, senza fermate, piatte): idrogeno 3% contro 1,3% delle tratte lunghe. Consumano poco, quindi lo stesso errore pesa di più. Le 10 tratte peggiori sono quasi tutte sotto i 18 km.
2. **Il SOC è più difficile con una fuel cell grande e una batteria piccola** (m alto, n basso): errore fino a 0,06 contro 0,004 a sola batteria.
3. **Sul limite del SOC la rete sbaglia lato una volta su cinque.** Quando il SOC vero è fra 0,15 e 0,25, la rete lo mette dalla parte sbagliata di 0,2 nel 20% dei casi; altrove quasi mai. È la maledizione del vincitore vista da vicino.
4. **Le tratte lontane dai dati di addestramento sbagliano di più:** il 10% più lontano ha l'errore del costo doppio (1,8% contro 1,0%) e i casi peggiori della scelta quasi tripli. Da tenere d'occhio per le linee reali ai bordi del dominio.

**Cosa conviene fare:**
- più tratte per la precisione media;
- più tratte corte per i casi peggiori;
- per la maledizione del vincitore, le verifiche al simulatore oppure più coppie (m, n) proprio vicino al limite del SOC (campionamento adattivo).

**Prossimo: passo 8**, l'esame finale sul test e l'applicazione a tratte reali e linee della rete.

## Passo 8a: l'esame finale sul test

16/11/2026. Report: `fase12/REPORT_FASE12_ESAME.md`.

**Come.** Il test (2048 tratte mai usate per nulla) si guarda una volta sola. Per questo abbiamo prima scritto e committato il piano, con le regole e le strategie scelte sulla validazione (commit 50e5132, alle 14:02). Poi abbiamo fatto la misura (alle 14:03), con la rete 6b così com'è e il boosting come confronto. Poco più di un minuto, comprese 2163 simulazioni di verifica.

**I risultati** (test; fra parentesi la validazione):

| | rete neurale | boosting |
|---|---:|---:|
| idrogeno (errore mediano) | 1,65% (1,68%) | 3,32% |
| SOC finale (errore assoluto) | 0,012 (0,012) | 0,029 |
| fattibilità giusta | 98,8% (98,9%) | 98,1% |
| costo (errore mediano) | 1,24% (1,26%) | 2,38% |
| scelta fra le 288 + 5 verifiche: tratte entro l'1% | 88,5% (90,2%) | 66,0% |

**La strategia per il preconfiguratore** (griglia fitta con la rete + margine piccolo + 5 simulazioni di verifica), sul test:
- progetto fattibile nel **98,4%** delle tratte (validazione 98,4%);
- in **2 tratte su 3** trova un progetto **più economico** della migliore delle 288 coppie della campagna: −0,55% in mediana, almeno −6,8% in una tratta su dieci;
- nel **90%** delle tratte è entro l'1% dalla migliore delle 288, o meglio.

**Cosa ci dice:** il test conferma la validazione quasi alla cifra. Il surrogato non è stato "aggiustato" sulla validazione: funziona allo stesso modo su tratte davvero nuove.

**Prossimo: 8b e 8c**, le tratte reali (Calabria, Canavese, Firenze) e le 166 linee della rete ferroviaria.

## Passi 8b e 8c: il surrogato su tratte vere

16/11/2026. Report: `fase12/REPORT_FASE12_ESAME.md`. Figure: `fase12/figure/fig_reali_mappe.png` e `fig_rete_scelta.png`.

**Cosa abbiamo fatto.** Abbiamo usato la rete, con la sua strategia (griglia fitta + margine piccolo + 5 simulazioni di verifica), su tratte vere, e l'abbiamo confrontata con il simulatore:
- **le 3 tratte reali storiche** (Calabria, Canavese, Firenze): qui abbiamo simulato l'intera griglia fitta, quasi 10 000 progetti per tratta, per avere il vero ottimo;
- **le 166 linee della rete ferroviaria** (versione del 10/11): abbiamo simulato le 288 coppie per linea, come nella campagna.

4 minuti in tutto, circa 78 000 simulazioni.

**Le tratte reali:**

| tratta | la scelta della rete rispetto all'ottimo vero | la migliore delle 288 coppie rispetto all'ottimo vero |
|---|---:|---:|
| Calabria (semplificata) | **+0,00%** (trova l'ottimo) | +2,8% |
| Canavese | +0,02% | +0,06% |
| Firenze | +0,13% | +2,1% |

La rete trova l'ottimo vero, o quasi, su tutte e tre, con il regime giusto: ibrido, sola batteria, ibrido con fuel cell minima.

**Le 166 linee della rete** (rispetto alla migliore delle 288 coppie simulate):

| linee | errore del costo (mediana) | scelte non fattibili | tratte con un progetto più economico | entro +1% |
|---|---:|---:|---:|---:|
| tutte | 2,7% | 3,0% | 45% | 86% |
| dentro il dominio del DoE (123) | 2,5% | 2,4% | 46% | 88% |
| fuori dal dominio (43) | 3,2% | 4,7% | 42% | 79% |
| il 10% più lontano dai dati di addestramento (17) | 3,0% | 12% | 24% | 59% |

**Cosa ci dicono i numeri:**
1. **Sulle linee reali la rete sbaglia circa il doppio che sulle tratte del DoE** (costo 2,7% contro 1,2%). Le linee reali sono più "lontane" dai dati di addestramento: anche quando ogni caratteristica è dentro gli intervalli, le combinazioni sono diverse da quelle delle tratte sintetiche.
2. **La scelta del progetto resta buona.** In 86 linee su 100 la rete con 5 verifiche arriva entro l'1% dalla migliore delle 288, e in quasi metà delle linee trova un progetto più economico (fino all'11% in meno). Anche dove l'errore del costo è alto (7–11%, per esempio le linee della Sicilia occidentale), la scelta è buona: l'errore sposta tutti i progetti della linea allo stesso modo e non cambia la classifica.
3. **La distanza dai dati di addestramento è il miglior segnale di allarme.** Per il 10% di linee più lontane conviene fare più di 5 verifiche, o una breve ricerca con il simulatore.
4. **Per migliorare sulle linee reali**, una nuova campagna dovrebbe aggiungere tratte più simili a quelle reali: un DoE "ancorato" alle linee della rete, oltre a quello uniforme.

## Come si usa il surrogato

16/11/2026. Istruzioni complete in `surrogato/LEGGIMI.md`.

1. **Preparare la tratta**: una cartella con i 4 file di progressiva, altimetria, stazioni e limiti, come quelle di `tratte_reali` e `tratte_rete`.
2. **Lanciare**, dalla cartella `ml_treno`:

   ```
   julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=<cartella> tratta=<nome>
   ```

3. **In circa 10–15 secondi lo script:**
   - dice quanto la tratta è diversa da quelle di addestramento;
   - fa valutare alla rete quasi 10 000 progetti (m, n);
   - fa verificare i 5 migliori al simulatore vero;
   - propone il più economico davvero fattibile, con la potenza della fuel cell e la capacità della batteria.

**Il comando più semplice è l'alias `surrogato`** (in `~/.zshrc`), da qualunque cartella: `surrogato doe=15000`, oppure `surrogato cartella=… tratta=…`. Senza alias, il comando con `julia` va lanciato dalla cartella `ml_treno`.

**Più tratte in un solo lancio** costano molto meno: l'avvio (circa 10 s) si paga una volta, poi ~0,1 s a tratta. Per esempio `surrogato doe=15000-15100` (101 tratte in 12,5 s) o `surrogato cartella=… tratta=tutte` (le 166 linee della rete in 14 s), con un riepilogo in un file CSV.

**Per le tratte DoE** della campagna basta il numero: `julia -t 8 --project=surrogato surrogato/usa_surrogato.jl doe=15000`. Lo script dice anche se la rete l'ha vista in addestramento, e la confronta con la migliore delle 288 coppie simulate.

Esempio, Firenze: m = 0,03, n = 0,96 (fuel cell da 59 kW, batteria da 3049 kWh), 2,407 €/km. È lo 0,13% dall'ottimo vero della griglia, e la migliore delle 288 coppie della campagna costava il 2% in più.

### Una coppia (m, n) data

16/11/2026. Con `m=` e `n=` lo script non cerca: la rete e il simulatore valutano solo quella coppia, e le grandezze, l'esito e il costo escono fianco a fianco. Esempi: `surrogato doe=15000 m=0.30 n=0.50`, `surrogato cartella=… tratta=tutte m=0.30 n=0.50`.

Prove:
- Firenze, m = 0,03, n = 0,96: il simulatore dà 2,4070 €/km, come l'esempio sopra; la rete 2,4103 €/km (+0,14%).
- Route 15000, sola batteria, n = 0,31: 2,7924 €/km, uguale alla proposta della modalità ricerca.
- Route 15000–15004, m = 0,30, n = 0,50: rete e simulatore d'accordo sulla fattibilità in 5 tratte su 5; errore del costo mediano 1,6%.

## Quanto sbaglia la rete su ogni grandezza, linea per linea (dopo il passo 8c)

16/11/2026. Script `fase12/03_errori_linee.jl`, risultati `fase12/risultati/03_errori_linee.txt` e `03_errori_linee.csv` (una riga per linea: errore mediano e massimo di ogni grandezza sulle sue 288 coppie). Nessuna simulazione nuova: le 288 coppie × 166 linee simulate nel passo 8c. Un minuto.

| grandezza | validazione DoE (mediana) | 166 linee: mediana | media | 95° percentile | massimo | rete sopra il simulatore |
|---|---:|---:|---:|---:|---:|---:|
| durata | 0,16% | 0,36% | 0,49% | 1,3% | 4,0% | 68% dei casi |
| serbatoio | 1,7% | 3,1% | 4,2% | 11,5% | 70% | 58% |
| idrogeno | 1,7% | 3,0% | 4,0% | 11,0% | 70% | 59% |
| SOC finale (assoluto) | 0,012 | 0,014 | 0,027 | 0,100 | 0,51 | 49% |
| vita della batteria | 2,4% | 3,5% | 4,7% | 12,9% | 64% | 47% |
| **vita della fuel cell** | **1,7%** | **15,7%** | **21,9%** | **64%** | **188%** | **87%** |
| C-rate di scarica | 1,2% | 1,6% | 2,2% | 6,1% | 37% | 54% |
| costo | 1,3% | 2,8% | 3,6% | 9,5% | 28% | **28%** |
| scarica giusta / fattibilità giusta | 99,0% / 98,9% | 98,7% / 98,4% | | | | |

**Cosa ci dicono i numeri:**
1. Su quasi tutte le grandezze la rete sbaglia sulle linee reali 1,2–2 volte più che sulla validazione DoE, come già visto nel passo 8c.
2. **La vita della fuel cell è l'eccezione:** errore mediano 16% invece di 1,7%, e quasi sempre per eccesso (la rete la dà più lunga nell'87% dei casi). In 67 linee su 166 l'errore mediano supera il 20%.
3. **È probabilmente la causa principale dell'errore del costo sulle linee reali.** La rete sottostima il costo nel 72% dei casi, e le linee con il costo più sbagliato (Sicilia occidentale, Siena, Lecce: 7–11%) hanno la vita della FC sbagliata del 30–85%, mentre l'idrogeno è giusto entro il 2–4%. Fra le linee, l'errore del costo va insieme a quello della vita della FC (correlazione di rango 0,49) più che a quello dell'idrogeno (0,18) o del SOC (0,17).
4. Da capire: cosa hanno le linee reali che consuma la fuel cell più delle tratte DoE (accensioni, minimo, cambi di carico). Una campagna ancorata alle linee reali (opzione c) dovrebbe correggerlo.

## Da dove viene l'errore sulla vita della fuel cell

16/11/2026. Script `fase12/04_vita_fc.jl` e `05_ruvidezza.jl`; risultati in `fase12/risultati/04_*` e `05_*`. Nessuna simulazione nuova, un paio di minuti.

**Come.** Il simulatore calcola la vita della fuel cell da quattro voci di degrado per viaggio: accensioni, ore al minimo, cicli di carico (quanto la potenza della FC sale e scende, Σ|ΔP|) e ore ad alto carico. Le abbiamo confrontate fra le linee della rete e le tratte DoE di validazione, alla stessa coppia (m, n).

**Cosa abbiamo trovato:**
1. **La voce che cambia è quella dei cicli di carico.** Sulle linee è 2,3 volte quella delle tratte DoE alla stessa coppia; minimo e alto carico sono uguali. Caso per caso, l'errore della rete va insieme all'eccesso dei cicli di carico (correlazione di rango 0,81), non alle altre voci. Anche le accensioni per ora sono il doppio, ma solo perché i viaggi sono più corti (una accensione per viaggio in entrambi): la rete lo vede.
2. **I cicli di carico vengono dal profilo "ruvido" delle linee.** La pendenza delle linee cambia 23 volte per km, contro 0,7 delle tratte DoE; la variazione totale della pendenza a corto raggio è 5 volte quella del DoE, mentre sulla scala del km le linee sono anzi più dolci (0,75 volte). Nessuna delle 66 caratteristiche lo misura, quindi la rete non può saperlo.
3. **Questa ruvidezza sembra in gran parte un artefatto dei dati.** Le quote della mappa sono prese "senza filtri" ogni 50 m e sono arrotondate a 0,1 m: il 39% dei salti di pendenza fra punti vicini vale esattamente 2‰ (0,1 m su 50 m). Una livelletta vera dell'1‰ diventa una scala 0‰, 2‰, 0‰, 2‰… e il simulatore fa salire e scendere la fuel cell a ogni gradino.

**Cosa vuol dire.** Più che la rete che sbaglia, è il simulatore che sulle linee reali "vede" un degrado della fuel cell che probabilmente non c'è, perché il profilo è rumoroso. Riguarda quindi anche i risultati del simulatore sulle linee reali, non solo il surrogato. Da decidere, anche con il relatore: lisciare l'altimetria delle linee (per esempio ricostruendo le livellette) prima di simularle, oppure considerare il rumore reale e insegnarlo alla rete (una caratteristica di ruvidezza e tratte DoE ruvide nella nuova campagna).

**E le tratte reali storiche?** (`fase12/06_ruvidezza_reali.jl`, stesse misure, 288 coppie già simulate nel passo 8b)

| tratta | cambi di pendenza per km | Σ\|Δp\| per km (1 m / 100 m / 1 km) | cicli di carico / DoE | errore della rete sulla vita FC |
|---|---:|---:|---:|---:|
| Calabria (semplificata, piatta) | 0 | 0 / 0 / 0 | 0,47 | −0,1% |
| Firenze (livellette) | 3,3 | 4,7 / 4,6 / 1,8 | 1,24 | −0,6% |
| Canavese (livellette corte, 100–150 m) | 13,1 | 25,7 / 24,9 / 4,3 | 2,42 | +6,4% |
| *DoE di validazione* | 0,7 | 5,5 / 5,5 / 4,4 | 1,01 | (1,7% in valore assoluto) |
| *linee della rete* | 23,4 | 28,6 / 13,1 / 3,3 | 2,39 | +15,9% |

Il gradino di quota a 0,1 m ogni 50 m è solo delle linee della rete (dalla mappa HTML). Firenze e Calabria sono lisce e la rete sbaglia pochissimo. Canavese è ruvida in un altro modo: livellette vere, con pendenze continue, lunghe 100–150 m. Anche lì i cicli di carico sono il doppio del DoE, e la rete sottostima il degrado (+6,4%). Quindi le linee della rete hanno un artefatto, ma anche una ruvidezza vera a corto raggio che il DoE non contiene.

## Le linee della rete con l'altimetria lisciata

16/11/2026. Script `fase12/07_lisciatura.jl`, risultati in `fase12/risultati/07_lisciatura.txt` e `07_lisciatura_linee.csv`. Le linee lisciate sono in `train-powertrain/dati_rete/tratte_rete_attenuate/` (`media_200m`, `media_500m`, `media_1km`): cambia solo la quota, che diventa la media mobile su 200 m, 500 m o 1 km; le originali non sono toccate. 288 coppie × 166 linee × 3 varianti simulate, circa 6 minuti.

| | originale | 200 m | 500 m | 1 km |
|---|---:|---:|---:|---:|
| Σ\|Δp\| per km a 1 m / su 1 km [‰/km] (DoE: 5,5 / 4,4) | 28,6 / 3,28 | 9,7 / 3,26 | 7,6 / 3,07 | 5,1 / 2,72 |
| dislivello mediano [m] | 197,3 | 196,9 | 196,1 | 194,8 |
| cicli di carico / DoE alla stessa coppia | 2,31 | 1,54 | 1,39 | 1,26 |
| simulatore: vita FC rispetto all'originale | — | +13% | +18% | +22% |
| simulatore: costo della migliore delle 288, mediana / 10% delle linee | — | −0,3% / −2,0% | −0,6% / −2,7% | −1,0% / −3,6% |
| linee con un'altra coppia migliore / un altro regime | — | 14 / 0 | 21 / 0 | 27 / 0 |
| rete: errore vita FC (con il segno) | 15,7% (+15,7%) | 4,2% (+1,7%) | 3,4% (+0,5%) | 3,0% (−0,4%) |
| rete: errore idrogeno / SOC / costo | 3,0% / 0,014 / 2,8% | 2,6% / 0,013 / 1,8% | 2,5% / 0,012 / 1,8% | 2,6% / 0,013 / 1,9% |
| rete: costo con il segno, 95° percentile | −2,0%, 9,5% | +0,1%, 6,2% | +0,6%, 5,9% | +0,8%, 6,0% |

**Cosa ci dicono i numeri:**
1. **Già 200 m tolgono quasi tutto l'artefatto.** La variazione della pendenza a corto raggio scende da 28,6 a 9,7 ‰/km, mentre il profilo sulla scala del km e il dislivello restano uguali. 500 m e 1 km cominciano a cancellare anche pendenze vere (−17% sulla scala del km, −2,5 m di dislivello con 1 km).
2. **La rete torna a sbagliare come sul DoE, o quasi.** Vita FC dal 15,7% al 4,2%, senza più la tendenza a stare sopra; costo dal 2,8% all'1,8%, senza più sottostima, e 95° percentile dal 9,5% al 6,2%. Idrogeno e SOC migliorano un po'. Oltre i 200 m la rete migliora poco.
3. **Per il simulatore la fuel cell dura il 13% in più** e il progetto migliore costa in mediana lo 0,3% in meno (2% o più nel 10% delle linee). In 14 linee cambia la coppia migliore, in nessuna il regime.
4. Rovigo–Verona sembra peggiorare del 10%, ma è un caso al limite: la migliore dell'originale aveva SOC finale 0,2019, con 200 m scende a 0,1990 e diventa non fattibile per 0,001.

**Proposta:** usare le linee lisciate a 200 m come versione di riferimento della rete, sia per il simulatore sia per il surrogato. È la finestra più piccola che toglie il gradino di 0,1 m, e non tocca il profilo vero. Da confermare con il relatore.

## Il surrogato sulle linee non elettrificate (oltre il 70%), lisciate a 200 m

16/11/2026. Script `fase12/08_non_elettrificate.jl`, risultati in `fase12/risultati/08_non_elettrificate.txt` e `.csv`. 146 linee su 166 (108 totalmente non elettrificate), con la quota non elettrificata = `km_non_el` / lunghezza dal `riepilogo.csv` (la colonna `perc_non_el` vale 0 ovunque: è rotta). Riferimento: il simulatore sulle 288 coppie. 30 secondi.

**Le grandezze, sulle 288 coppie** (42 048 casi; errore mediano / 95° percentile): durata 0,33% / 1,4%; serbatoio 2,7% / 10%; idrogeno 2,7% / 9,7%; SOC 0,013 / 0,096; vita batteria 3,3% / 12%; vita FC 4,4% / 21%; C-rate 1,5% / 5,9%; costo 1,9% / 6,3%; scarica giusta 98,8%, fattibilità giusta 98,5%.

**La scelta del progetto** (griglia fitta + margine + 5 verifiche):
- progetto fattibile in 146 linee su 146 (più di 5 verifiche in 3);
- costo vero rispetto alla migliore delle 288: mediana 0,00%, più economico in 75 linee (51%, fino a −16%), entro +1% in 134 (92%), oltre +3% in 3;
- regime: lo stesso in 136 linee su 146. Le 10 diverse sono tutte linee dove la migliore delle 288 è (0,11, 0,84), un ibrido appena sopra la soglia D25, e il surrogato trova un ibrido con fuel cell piccola (m 0,04–0,09, n 0,92–0,98) più economico del 3–16%: è la griglia delle 288 che non ha coppie in quella zona, non un errore del surrogato;
- i casi peggiori sono linee corte a sola batteria (Cagliari Elmas–Cagliari 7,9 km, +6,5%; Marradi–Borgo S. Lorenzo, +4,2%): la rete sottostima il costo di una batteria grande e propone n ≈ 0,9 invece di 0,3–0,4.

**Nel progetto proposto** la rete sbaglia il costo del 2% in mediana (95° percentile 7%). La vita della fuel cell è sovrastimata del 9% in mediana: fra 10 000 progetti la ricerca sceglie quelli dove la rete è ottimista (maledizione del vincitore), anche se sulle 288 coppie l'errore è solo del 4%.

**Il riferimento è debole:** la migliore delle 288 non è l'ottimo vero, e nella zona m 0,03–0,11 con batteria grande le 288 hanno solo 6 coppie. Per un confronto con il modello vero serve l'ottimo del simulatore sulla griglia fitta.

## Effetto della lisciatura sull'ottimo del simulatore vero: Trapani–Alcamo

16/11/2026. Script `fase12/09_ottimo_lisciatura.jl`, risultati in `fase12/risultati/09_ottimo_lisciatura_Trapani-Alcamo_Diramazione.txt`, figura `fase12/figure/fig_ottimo_lisciatura_Trapani-Alcamo_Diramazione.png`. Solo simulatore, niente surrogato: griglia fitta intera (9702 progetti) in 5 versioni del profilo, circa 4 minuti. Aggiunta anche la versione `media_100m` in `tratte_rete_attenuate`.

| | originale | 100 m | 200 m | 500 m | 1 km |
|---|---:|---:|---:|---:|---:|
| Σ\|Δp\| per km a 1 m / su 1 km | 39,0 / 3,78 | 19,2 / 3,77 | 12,4 / 3,75 | 8,1 / 3,62 | 5,4 / 3,27 |
| ottimo (m, n) | 0,17, 0,92 | uguale | uguale | uguale | uguale |
| costo dell'ottimo [€/km] | 3,672 | 3,599 (−2,0%) | 3,585 (−2,4%) | 3,558 (−3,1%) | 3,528 (−3,9%) |
| cicli di carico [µV/h] | 18,5 | 11,6 | 10,0 | 8,5 | 6,6 |
| vita FC f1 [h] / sostituzioni FC | 2298 / 17 | 2926 / 13 | 3125 / 13 | 3342 / 12 | 3661 / 11 |
| sostituzioni FC [€/km] | 0,340 | 0,261 | 0,255 | 0,236 | 0,215 |

**Cosa ci dicono i numeri:**
1. **L'ottimo non si muove**: stesso progetto (m 0,17, n 0,92) in tutte le versioni, primo anche nella classifica dell'originale. Qui l'ottimo sta sul bordo della fattibilità: è la fuel cell più piccola che tiene il SOC finale sopra 0,2 (0,2001), e la lisciatura non cambia energia e idrogeno (±0,5%).
2. **Cambia il costo**: −2% già con 100 m, quasi tutto dalle sostituzioni della fuel cell (da 17 a 13). Con 500 m e 1 km si aggiunge un salto discreto delle sostituzioni della batteria (da 3 a 2).
3. **Con i cicli equivalenti l'effetto sull'ottimo è piccolo, ma non sul degrado**: la vita della fuel cell sale del 27% con 100 m e del 36% con 200 m. Per progetti con fuel cell più grandi il costo scende di più (fino a −8–10% per m ≈ 0,5, figura).

## La stessa linea dai dati sorgente RINF (Trapani–Alcamo)

16/11/2026. Script `fase12/10_profilo_rinf.jl`, risultati in `fase12/risultati/10_profilo_rinf_Trapani-Alcamo_Diramazione.txt`. Le linee della rete che usiamo vengono dalla mappa HTML (quota arrotondata a 0,1 m ogni 50 m). Nel Drive condiviso SurrogateTrains ci sono i dati sorgente di ogni linea: livellette RINF a piena precisione, fermate del servizio con le soste, velocità. Gli Excel sono solo l'elenco dei servizi. Due versioni nuove in `train-powertrain/dati_rete/tratte_rete_rinf/`: `profilo_rinf` (solo la quota dal RINF, fermate e limiti della mappa) e `tutto_rinf` (anche fermate e limiti dal Drive). Griglia fitta simulata, 1,4 minuti.

| | mappa | mappa 100 m | mappa 200 m | profilo RINF | tutto RINF |
|---|---:|---:|---:|---:|---:|
| Σ\|Δp\| per km a 1 m / su 1 km | 39,0 / 3,78 | 19,2 / 3,77 | 12,4 / 3,75 | 13,8 / 3,77 | 13,8 / 3,77 |
| fermate intermedie | 13 | 13 | 13 | 13 | 11 |
| ottimo (m, n) | 0,17, 0,92 | uguale | uguale | uguale | **0,11, 0,94** |
| costo dell'ottimo [€/km] | 3,672 | 3,599 (−2,0%) | 3,585 (−2,4%) | 3,583 (−2,4%) | **3,124 (−15%)** |
| cicli di carico [µV/h] | 18,5 | 11,6 | 10,0 | 8,8 | 9,4 |
| vita FC f1 [h] / sostituzioni FC | 2298 / 17 | 2926 / 13 | 3125 / 13 | 3299 / 12 | 3680 / 10 |
| idrogeno [kg/viaggio] / durata A/R [s] | 57,2 / 13 020 | 57,5 | 57,6 | 58,0 | 45,1 / 12 310 |

**Cosa ci dicono i numeri:**
1. **I salti vengono dalla mappa HTML.** Con le livellette vere del RINF i cicli di carico scendono da 18,5 a 8,8 µV/h e il costo del 2,4%, esattamente come con la mappa lisciata a 200 m (−2,4%). L'ottimo non cambia. Le livellette RINF sono corte (mediana 180 m, 81 sotto i 100 m) ma non hanno il gradino di 0,1 m.
2. **La lisciatura a 200 m riproduce bene il profilo vero** (stesso costo entro lo 0,05%).
3. **Le fermate contano molto di più del profilo.** La versione dalla mappa ha 2 fermate in più del servizio reale (a 60,5 e 100,8 km). Con le fermate dell'orario l'idrogeno scende del 21%, l'ottimo passa a una fuel cell più piccola (217 kW invece di 335) e il costo scende del 15%.
4. Le soste reali (60 s per fermata, 300–600 s in alcune) non sono rappresentabili nel formato a 4 file: il simulatore usa 120 s per fermata.

**Le fermate su tutte le 166 linee** (stazioni nella versione dalla mappa contro fermate dell'orario nel Drive): uguali in 53 linee; la mappa ne ha di più in 113, mai di meno: 1–2 in più in 47 linee, 3 o più in 66, fino a 28–29 in più (Aulla–Pisa 29 contro 26, Buonconvento–Firenze 20 contro 6, Cagliari–Macomer 24 contro 11, Biella–Novara 12 contro 5). Era una scelta documentata nel README delle linee ("un servizio che ferma ovunque"), ma su Trapani–Alcamo 2 fermate in più valgono il 15% del costo: da rivedere prima di usare le linee per la tesi.

## Il surrogato sulle 166 linee ricostruite dai dati sorgente RINF

16/11/2026. Script `fase12/11_rete_rinf.jl`, risultati in `fase12/risultati/11_rete_rinf.txt` e `11_rete_rinf_linee.csv`. Linee in `train-powertrain/dati_rete/tratte_rete_rinf/` (non in git): `profilo_rinf` (quota dalle livellette RINF, fermate e limiti della mappa) e `tutto_rinf` (quota, fermate dell'orario e limiti dal Drive), costruite dalla copia locale del Drive (`ml_treno_dati/linee_rinf_sorgente`). 166 linee su 166; in Edolo–Brescia e Sale Marasino–Brescia le fermate dell'orario finiscono a Iseo, e il capolinea è stato aggiunto a fine linea (Brescia). 288 coppie × 166 linee × 2 versioni simulate, 4,5 minuti in tutto.

| tutte le 166 linee | mappa | mappa 200 m | profilo RINF | **tutto RINF** |
|---|---:|---:|---:|---:|
| errore idrogeno, mediana / 95° perc. | 3,0% / 11,0% | 2,6% / 9,4% | 2,8% / 9,8% | 3,0% / 10,9% |
| errore SOC finale | 0,014 | 0,013 | 0,013 | 0,014 |
| errore vita FC (con il segno) | 15,7% (+15,7%) | 4,2% (+1,7%) | 3,4% (−1,0%) | 3,8% (−0,6%) |
| errore costo, mediana / 95° perc. | 2,8% / 9,5% | 1,8% / 6,2% | 2,0% / 6,3% | 2,0% / 6,7% |
| fattibilità giusta | 98,4% | 98,5% | 98,4% | 98,4% |
| scelta: entro +1% dalla migliore 288 / più economica | 86% / 45% | 91% / 52% | 89% / 49% | 91% / 55% |
| scelta: oltre +3% / massimo | 11 / +11,8% | 3 / +6,5% | 8 / +8,1% | 5 / +12,9% |
| nel progetto proposto: errore costo / vita FC | 2,2% / +27% | 1,9% / +6% | 2,3% / −0,8% | 2,0% / −0,5% |

Sulle 146 linee non elettrificate oltre il 70% i numeri sono quasi uguali (tutto RINF: costo 2,0%, vita FC 3,8%, entro +1% nel 90%).

**Cosa ci dicono i numeri:**
1. **Con i dati corretti la rete sbaglia come sulla mappa lisciata**: costo 2,0% invece di 2,8%, vita FC 3,8% e senza più sovrastima (prima +16%). Il divario residuo con il DoE (costo 1,3%) viene dalla distanza delle linee vere dai dati di addestramento.
2. **Con le fermate dell'orario cambia molto il simulatore**: la migliore delle 288 costa l'8,6% in meno in mediana, e il 35% o più in meno in una linea su dieci (quelle con molte fermate in più nella mappa). Ci sono più linee a sola batteria (109 contro 101).
3. **Un nuovo caso difficile**: 3 linee dove l'ottimo è a sola batteria con la batteria più grande (n 0,98) e il surrogato propone una fuel cell minima (m 0,03): Edolo–Brescia +12,9%, Corteolona–Cremona +8,1%, Roccella J.–Catanzaro +6,6%. Probabilmente il margine sul SOC esclude la sola batteria al limite e le 5 verifiche restano tutte sugli ibridi. Rimedio possibile: verificare sempre anche il migliore candidato di ogni regime.
4. Le altre 17 differenze di regime sono a favore del surrogato (ibrido con fuel cell piccola più economico della migliore delle 288, fino al −15%).

## Un candidato per regime, e il riassunto sulle linee non elettrificate

16/11/2026. Script `fase12/12_riassunto_non_el.jl`, risultati in `fase12/risultati/12_riassunto_non_el.txt` e `_linee.csv`. Linee "tutto RINF". Nessuna simulazione nuova oltre alle verifiche, 30 secondi.

**La strategia con un candidato per regime.** Oltre ai 5 progetti più economici per la rete, il simulatore verifica anche il migliore per la rete di ogni regime (sola batteria, ibrido con FC piccola, ibrido), scelto con un margine largo (SOC previsto ≥ 0,18 invece di 0,21). Sulle 166 linee: caso peggiore da +12,9% a +8,1%, entro +1% in 153 linee invece di 151, più economico della migliore delle 288 in 100 invece di 91, al prezzo di 7,2 simulazioni per linea invece di 5. Con il margine normale (variante B) non cambia nulla. Edolo–Brescia passa da +12,9% a −0,05% (la rete prevedeva SOC 0,182 per la sola batteria con n 0,98). Restano Corteolona–Cremona (+8,1%) e Roccella J.–Catanzaro (+6,6%): qui la rete sceglie per la sola batteria un altro progetto, che il simulatore boccia.

**Riassunto sulle 146 linee non elettrificate oltre il 70%** (95 totalmente; da 6,9 a 276 km):

| grandezza (288 coppie × 146 linee) | media | mediana | 95° perc. | massimo | linea migliore / peggiore (mediana) |
|---|---:|---:|---:|---:|---|
| durata del viaggio | 0,47% | 0,35% | 1,3% | 4,2% | 0,09% / 2,8% |
| massa del serbatoio | 4,2% | 3,0% | 11,9% | 51% | 1,4% / 13,7% |
| idrogeno consumato | 4,0% | 3,0% | 11,1% | 49% | 1,2% / 10,2% |
| SOC finale (assoluto) | 0,027 | 0,014 | 0,095 | 0,47 | 0,005 / 0,035 |
| vita della batteria | 5,1% | 3,7% | 14,3% | 92% | 1,5% / 14,6% |
| vita della fuel cell | 5,1% | 3,8% | 14,2% | 43% | 1,2% / 19,4% |
| C-rate di scarica | 2,3% | 1,6% | 6,3% | 41% | 0,8% / 4,3% |
| costo [€/km] | 2,5% | 2,0% | 6,7% | 22% | 0,5% / 6,2% |

Scarica giusta nel 98,7% dei casi, fattibilità giusta nel 98,4% (minimo per linea 93,8%). Nessuna grandezza ha più una tendenza sistematica (errore con il segno entro ±0,7%).

**La scelta del progetto** (variante C): fattibile in 146 linee su 146; costo vero rispetto alla migliore delle 288 in media −1,3%, mediana −0,07%, da −15,2% a +7,2%; più economico in 86 linee (59%), entro +1% in 134 (92%), oltre +3% in 3. Regime uguale in 133 linee; le differenze sono quasi tutte ibridi con fuel cell piccola più economici. Nel progetto proposto la rete sbaglia il costo del 2,1% in mediana (95° percentile 7%).

**I tempi**, sul Mac M4 a 8 core, a parità di macchina: la griglia fitta tutta simulata costa 20 s per linea in media (da 1,4 a 71 s), 48 minuti per le 146 linee; il surrogato 0,05 s per linea (rete 31 ms, 7 verifiche 15 ms), 7 secondi per tutte. Circa **400 volte più veloce** (per linea da 30× a 1000×; il guadagno cresce con la lunghezza della linea). Rispetto alle sole 288 coppie: 12 volte più veloce, e con un progetto più economico nel 59% delle linee. Il tempo del registro (8 simulazioni in parallelo) è da 1,2 a 3 volte quello su un core libero: per questo il confronto è a parità di macchina.

## Una verifica più robusta: candidati sparsi e ricerca locale con il simulatore

16/11/2026. Script `fase12/13_verifica_locale.jl`, risultati in `fase12/risultati/13_verifica_locale.txt` e `_linee.csv`. Linee "tutto RINF", riferimento la migliore delle 288 coppie simulate. Un minuto.

Varianti, tutte partendo dalla rete sulla griglia fitta: **C** (fase12/12: 5 migliori + il migliore di ogni regime); **D** = C + il migliore in ogni fascia di n; **E** = C + ricerca locale con il simulatore dal migliore verificato (vicini in m e n, passi da 0,16 a 0,01, al più 40 simulazioni); **F** = D + E; **G** = F + 5 progetti a sola batteria simulati (n 0,2–0,99) e ricerca locale anche dal migliore fattibile di ogni regime. Corretto anche il ripiego: si continua finché è fattibile uno dei candidati principali, non uno "extra" (prima un candidato sparso mediocre poteva fermarlo: Schio–Venezia +28%).

| 146 linee non elettrificate oltre il 70% | C | D | E | F | **G** |
|---|---:|---:|---:|---:|---:|
| costo vs migliore 288: media / mediana | −1,3 / −0,08% | −1,4 / −0,08% | −1,7 / −0,23% | −1,8 / −0,24% | **−1,8 / −0,24%** |
| caso peggiore | +7,2% | +6,6% | +6,4% | +6,4% | **+0,58%** |
| più economico / entro +1% / oltre +2% | 87 / 134 / 6 | 93 / 138 / 3 | 123 / 144 / 1 | 125 / 145 / 1 | **126 / 146 / 0** |
| simulazioni per linea: media / max | 7 / 8 | 10 / 11 | 23 / 33 | 26 / 36 | 50 / 80 |
| tempo per linea | 0,05 s | 0,06 s | 0,08 s | 0,09 s | 0,13 s |

Su tutte le 166 linee G è entro +1% dalla migliore delle 288 in **166 linee su 166** (peggiore +0,58%) e più economica in 143.

**Cosa ci dicono i numeri:**
1. **La ricerca locale con il simulatore corregge i casi "regime giusto, batteria sbagliata"**: Rutigliano da +7,2% a 0,00%, Mortara–Pavia da +2,1% a 0,00%, Cagliari–Oristano da +2,8% a −1,4%.
2. **I casi "sola batteria al limite" richiedono di simulare anche qualche progetto a sola batteria**, perché per arrivarci bisogna cambiare m e n insieme: Corteolona–Cremona da +8,1% a +0,06%, Roccella–Catanzaro da +6,6% a −0,11%.
3. **Il prezzo è piccolo**: 50 simulazioni per linea invece di 7, 0,13 s per linea, 18 s per tutte le 146 linee. Resta circa 150 volte più veloce della griglia fitta simulata (20 s per linea su 8 core).
4. La rete ora serve a "puntare" la zona giusta, e il simulatore rifinisce. Il confronto con la migliore delle 288 non basta più (il surrogato la batte nell'86% delle linee): per misurare la distanza dall'ottimo vero serve la griglia fitta simulata.

**Nel progetto scelto da G, rete contro simulatore** (`fase12/14_errori_ottimo.jl`, 146 linee non elettrificate): costo |errore| mediano 2,0%, 90° percentile 5,8%, massimo 16% (Cagliari Elmas–Cagliari, 7,9 km), oltre il 10% in 3 linee; SOC finale 0,016 (massimo 0,11); idrogeno 2,1% (massimo 8%); vita FC 2,9% (massimo 25%, Trapani–Alcamo); durata 0,35%. **La rete dice fattibile il progetto scelto solo in 86 linee su 146**: l'ottimo vero sta quasi sempre sul limite del SOC, dove la rete è meno sicura, e la ricerca con il simulatore ci arriva. Per questo i numeri finali del progetto vanno sempre presi dal simulatore (una simulazione in più), non dalla rete.

### La strategia G nel comando `surrogato`

16/11/2026. In `surrogato/usa_surrogato.jl` c'è l'opzione `strategia=G` (default ancora `strategia=semplice`), descritta nel LEGGIMI. Prove: Rutigliano–Putignano arriva a (0, 0,29), 2,2088 €/km, come la migliore delle 288 (la semplice faceva +7,2%); su tutte le 166 linee "tutto RINF" il comando dà esattamente le stesse proposte di `fase12/13` (166 su 166), 50 simulazioni per linea, 27 s in tutto; la strategia semplice è invariata (route 15000: +0,26% come prima). Da rendere default dopo il confronto con l'ottimo vero (griglia fitta simulata sulle 146 linee, da fare).

## Il confronto con l'ottimo vero (griglia fitta simulata)

16/11/2026. Script `fase12/15_ottimo_vero.jl`, risultati in `fase12/risultati/15_ottimo_vero.txt` e `_linee.csv`, figura `fase12/figure/fig_ottimo_vero.png`. Le 146 linee "tutto RINF" non elettrificate oltre il 70%, ognuna simulata su tutti i 9702 progetti della griglia (m 0 e 0,03–0,99, n 0,01–0,99, passo 0,01): 1,4 milioni di simulazioni, 63 minuti sul Mac a 8 core (5,5 ore sommando i singoli progetti). L'ottimo vero è il progetto fattibile più economico della griglia. Simulazioni in `ml_treno_dati/fase12/griglia_rinf/<linea>` (~3 GB). Controllo: i costi delle proposte C e G riletti dalla griglia coincidono con quelli delle verifiche (scarto 3e-5).

| costo rispetto all'ottimo vero | migliore delle 288 | surrogato semplice | surrogato C | **surrogato G** |
|---|---:|---:|---:|---:|
| media / mediana | +2,29 / +0,24% | +1,15 / +0,29% | +0,83 / +0,19% | **+0,30 / 0,00%** |
| 90° percentile / massimo | +8,2 / +18,0% | +3,3 / +13,0% | +2,9 / +7,2% | **+1,1 / +4,5%** |
| proprio l'ottimo | 15 | 11 | 31 | **127** |
| entro 0,5% / 1% | 94 / 102 | 94 / 100 | 103 / 109 | **128 / 131** |
| oltre 2% / 5% | 39 / 24 | 32 / 6 | 25 / 3 | **12 / 0** |

- **G trova esattamente l'ottimo vero in 127 linee su 146**, e il regime giusto in 144. Fra i 6782 progetti fattibili (mediana per linea) la proposta G è 1ª in mediana, 2ª al 90° percentile, 12ª nel caso peggiore.
- **Il costo non è piatto vicino all'ottimo**: entro lo 0,5% dall'ottimo ci sono in mediana solo 4 progetti. Quindi trovare il punto esatto conta.
- **Le 18 linee in cui G resta oltre lo 0,5% sono tutte dello stesso tipo**: ibridi con fuel cell piccola e batteria grande (n 0,85–0,97). Lì l'ottimo sta sul bordo della fattibilità, spesso è un progetto fattibile isolato. Per esempio Grosseto–Siena: l'ottimo (0,06, 0,97) è l'unico fattibile intorno: con n = 0,96 la batteria non basta, con n = 0,98 il treno è troppo pesante. Ogni 0,01 di m in più costa circa +2,3%. La ricerca locale di G si muove o in m o in n, mai insieme: dalla proposta (0,08, 0,91), diminuire m da solo dà un progetto non fattibile, e la ricerca si ferma (+4,5%).

### Mosse "lungo il bordo" (emulazione, nessuna simulazione nuova)

Script `fase12/16_mosse_bordo.jl`, risultati in `fase12/risultati/16_mosse_bordo.txt`. Sulla griglia già simulata si prova un'aggiunta alla ricerca locale di G: dalla proposta si toglie 0,01 o 0,02 di fuel cell e si sale in n (al più +0,12) finché il progetto torna fattibile; si accetta se costa meno, e si ripete (insieme ai vicini a passo 0,01).

| 146 linee | G | G + bordo |
|---|---:|---:|
| media / massimo | +0,30 / +4,5% | **+0,06 / +3,0%** |
| entro 0,01% / 0,5% / 1% dall'ottimo | 127 / 128 / 131 | **141 / 142 / 143** |
| oltre 2% | 12 | 3 |
| simulazioni in più per linea | — | 9 in media, al più 43 |

Restano lontane 3 linee (Rovigo–Verona +3,0%, Crotone–Lamezia +2,8%, Buonconvento–Empoli +2,1%), dove G è nel regime ibrido (m 0,12–0,16) e l'ottimo ha la fuel cell piccola con m più basso di 0,03–0,05: servirebbe un passo più lungo in m. L'emulazione parte dalla proposta finale di G; nel comando la mossa andrebbe dentro la ricerca locale. Da decidere: inserirla in `usa_surrogato.jl` e rendere G (con il bordo) la strategia di default.

### Il bordo nel comando e G come default

16/11/2026. In `surrogato/usa_surrogato.jl` la strategia G ora finisce con le mosse lungo il bordo (dal migliore fattibile: m − 0,01 o − 0,02 salendo in n finché il progetto è fattibile, al più +0,12, più i vicini a passo 0,01; al più 60 simulazioni), e **G è la strategia di default**; la vecchia resta con `strategia=semplice` (`verifiche=` vale solo lì). Aggiornati il commento in testa e il LEGGIMI.

Prove:
- tutte le 166 linee "tutto RINF" con il comando: 166 proposte, 31 s (0,19 s per linea), 55 simulazioni per linea in media, al più 80;
- sulle 146 non elettrificate, contro l'ottimo vero (`fase12/risultati/17_g_bordo_comando.txt`): esattamente i numeri dell'emulazione: ottimo in 141, media +0,06%, peggiore +2,99%; fuori restano Breno–Pisogne +0,05%, Cagliari–Macomer +0,81%, Buonconvento–Empoli +2,08%, Crotone–Lamezia +2,84%, Rovigo–Verona +2,99%. Deciso di non complicare oltre;
- Grosseto–Siena (dettaglio): il bordo porta da (0,08, 0,91) all'ottimo (0,06, 0,97) in 14 simulazioni, −4,3%;
- route DoE 15000: G 2,7851 €/km, come la migliore della campagna; `strategia=semplice` invariata (+0,26%).

### I dati per la presentazione

16/11/2026. Opzione `griglia=si` nel comando (scrive `<tratta>/griglia_rete.csv`, la rete su tutti i 9702 progetti). Script `fase12/18_dati_presentazione.py` → `fase12/presentazione_146/` (con LEGGIMI): tabella e tracciati GeoJSON delle 146 linee, heatmap simulatore/rete per Brescia–Iseo, Grosseto–Siena e Cagliari–Olbia, `riassunto.txt`. Numeri principali:
- regimi della proposta: 99 sola batteria, 18 ibrido FC piccola, 29 ibrido (ottimo vero 99 / 20 / 27). Sotto i 60 km tutte a sola batteria (78 linee); oltre i 150 km tutte ibride; la Lombardia è tutta a sola batteria (28 linee);
- costo mediano 2,52 €/km a sola batteria, 2,75 ibrido FC piccola, 3,83 ibrido (in tutto da 1,52 a 5,58);
- rete contro simulatore su 1,4 milioni di progetti: fattibilità giusta 98,3% (linea peggiore 92,1%), errore sul costo nei progetti fattibili 1,9% in mediana, 6,5% al 95° percentile.

## Fase 13: le linee corrette dal collega (dati del 17/11) e la nuova griglia fitta

17–18/11/2026. Cartella `fase13/`. Prima di classificare gli ottimi in pochi treni standard, si rifà tutto sulle linee corrette nel Drive condiviso SurrogateTrains (`Linee Ferroviarie/01 - Italia/Linee`). Le correzioni sono due: la nuova livellazione dello script v45a e le 6 linee del bacino di Iseo, che ora finiscono a Brescia Borgo San Giovanni, 2,2 km prima di Brescia. La cartella NUOVE è stata verificata, messa in Lombardia e cancellata. Una prima versione serale della Lombardia, con il profilo decimato, era stata scartata.

- **Cosa cambia nei dati**: sulle 146 linee cambia solo l'altimetria. Fermate (solo `fermate.csv`, non le stazioni), limiti e lunghezze sono uguali. Sulle 6 linee di Brescia le fermate aggiunte coincidono con il ripiego che lo script già usava (fermata a 0, capolinea a BBG). Su Brescia–Marone–Zone, Edolo–Brescia e Sale Marasino–Brescia non ci sono fermate fra BBG e Iseo (23,6 km senza fermate, fonte "orario").
- **`01_linee.jl`**: ricostruisce le 166 linee dalla copia locale `ml_treno_dati/linee_rinf_sorgente` (versione del 17/11, uguale al Drive) in `train-powertrain/dati_rete/tratte_rete_rinf/tutto_rinf`, più `linee_non_el_70.txt` (146 linee, le stesse di prima). Nessun avviso. Le vecchie `profilo_rinf` e `tutto_rinf` e la copia dell'11/11 sono state cancellate.
- **Surrogato** (G + bordo, 47 s, `03_confronto_surrogato.py` → `risultati/03_confronto_surrogato.txt`): rispetto ai dati dell'11/11, stesso progetto su 123 linee e stesso regime su 146. Il costo cambia in mediana dello 0,00% (fra −0,22% e +0,05% per l'80% delle linee). Oltre l'1% solo Sassari–Oristano (−1,6%), Trapani–Piraineto (−1,1%) e Cagliari–Olbia (+1,0%).
- **Griglia fitta** (`02_griglia_fitta.jl`, 146 linee × 9702 progetti, 58 min sul Mac a 8 core; simulazioni in `ml_treno_dati/fase13/griglia_rinf`, 2,9 GB; `risultati/02_griglia_fitta.txt` e `02_ottimo_linee.csv`). È la tabella su cui si farà la classificazione. Rispetto alla griglia del 16/11:
  - l'ottimo vero ha lo stesso progetto su 121 linee e lo stesso regime su tutte (99 sola batteria, 20 ibrido FC piccola, 27 ibrido);
  - il costo dell'ottimo cambia in mediana dello 0,00% (10° −0,22%, 90° +0,04%, min −1,58% Sassari–Oristano, max +0,35% Faenza–Firenze);
  - i 25 progetti che cambiano si spostano di 0,01–0,04, quasi sempre solo in n.
  - Avvisi: i soliti 10 del ciclo dello storage che non converge (D28, peso massimo del ciclo).
- **Surrogato contro il nuovo ottimo vero** (`04_surrogato_vs_vero.py` → `risultati/04_surrogato_vs_vero.txt`): la proposta è proprio l'ottimo su 139 linee e ha il regime giusto su 144. Media +0,07%, massimo +3,08%. Oltre il 2% restano le 3 di prima (Rovigo–Verona, Crotone–Lamezia, Buonconvento–Empoli), poi Cagliari–Olbia +1,1% e Cagliari–Macomer +1,0%. È lo stesso quadro dei dati vecchi (141 linee, +0,06%, +2,99%).

Conclusione: le correzioni del collega spostano pochissimo gli ottimi. La classificazione (p-mediana, extra-costo medio, peso uguale per linea) si fa sulla nuova griglia `fase13/griglia_rinf`.

### Tutti i confronti sui dati nuovi (per la presentazione)

18/11/2026. Rifatti sulle linee del 17/11 i confronti della fase 12 che la presentazione usa. Il codice è lo stesso, cambiano solo i percorsi.
- `fase13/05_coppie_288.jl`: le 288 coppie della campagna sulle 146 linee (1 min; `ml_treno_dati/fase13/sim_288`).
- `06_riassunto_non_el.jl` (= fase12/12): errori della rete sulle 42 048 coppie, quasi identici a prima. Costo 1,99% in mediana, 6,78% al 95°; SOC 0,014 / 0,096; errore di costo oltre il 10% in 1 caso su 89, oltre il 20% in 1 su 25 730; 21 linee "lontane" (prima 20).
- `07_verifica_locale.jl` (= fase12/13): le varianti C…G.
- `08_ottimo_vero.jl` (= fase12/15, solo il confronto; aggiunta la colonna G + bordo):

  | | migliore 288 | semplice | C | G senza bordo | G + bordo |
  |---|---:|---:|---:|---:|---:|
  | media | +2,19% | +1,13% | +0,83% | +0,31% | +0,07% |
  | massimo | +18,0% | +13,0% | +7,0% | +4,6% | +3,1% |
  | proprio l'ottimo | 20 | 14 | 33 | 126 | 139 |
  | entro 1% / oltre 2% | 102 / 40 | 100 / 32 | 109 / 25 | 129 / 13 | 141 / 3 |

- `09_dati_presentazione.py` (= fase12/18) → `fase13/presentazione_146/`. Surrogato rilanciato con `griglia=si`: stesse proposte del 17/11. Unico cambiamento visibile negli esempi: su Cagliari–Olbia la proposta (0,37; 0,75) è a +1,12% dall'ottimo (0,36; 0,69), prima coincidevano.
- Prompt per far aggiornare la presentazione da Cowork: `STEPS/prompt_cowork_aggiorna_presentazione.md`.

## Fase 15: quanto contano profondità e larghezza della rete

19–20/11/2026. Cartella `fase15/`, report `fase15/REPORT_FASE15_ARCHITETTURA.md`. Serve a giustificare nell'articolo la scelta della rete 6b (4 strati × 256), non a cambiarla. Regola decisa prima: si resta sulla 6b, a meno di differenze molto più grandi della variabilità del seme.

- **Cosa si è fatto** (`01_architettura.jl`, 3 h sul Mac): stesse impostazioni del 6b, cambiano solo strati e neuroni. Profondità 2, 3, 6 strati da 256; larghezza 128 e 512 con 4 strati; la 4 × 256 con semi 2 e 3 per misurare la variabilità. Tutto sulla validazione, come i passi 6b e 6c; nessuna simulazione.
- **Il seme** sposta pochissimo gli errori (perdita ±0,6%, costo 1,26–1,28%), ma molto la scelta secca (14–16% di scelte non fattibili, rimpianto p95 3,4–4,0%).
- **Profondità:** 2 strati sono nettamente peggio (costo 1,64% / 7,0% contro 1,26% / 5,2%; con 5 verifiche 79% di tratte entro l'1% contro 90%). 3 strati sono un po' peggio. 6 strati sono un po' meglio: perdita −1,2%, sul bordo del seme; costo 1,19%; scelta uguale entro il rumore. Costano però il 36% in più di tempo di previsione.
- **Larghezza:** 128 è peggio (costo 1,40%, prime 5 entro l'1% 86%). 512 si ferma presto (epoca 24, migliore 19): passo ancora alto e adattamento eccessivo ai dati di addestramento. Grandezze peggiori, scelta pari. Con la stessa ricetta non conviene.
- **Rugosità:** tutte le reti sono 6–30 volte più lisce del simulatore, senza differenze oltre il seme.

Conclusione: 4 × 256 sta al ginocchio fra precisione e costo. **Il modello resta la 6b.** Nel report c'è una frase in inglese pronta da adattare per l'articolo.

## Fase 16: la strategia G sulle tratte del test, contro l'ottimo vero

20/11/2026. Cartella `fase16/`, report `fase16/REPORT_FASE16_G_TEST.md`. Serve a vedere se il risultato di G + bordo sulle 146 linee (fase13/08) regge su tratte mai usate per svilupparla. `usa_surrogato.jl` non è stato toccato.

- **Tratte:** le 256 del test DoE del passo 8a della fase 12 (gruppi 15 e 16, seme 20261117, senza la 14664). Sono più lunghe e più spesso ibride delle linee: L mediana 147 km contro 56.
- **Ottimo vero:** griglia fitta di 9702 progetti simulata per ogni tratta (`02_griglia.jl`, 4 h sul Mac, 56 s a tratta con 8 thread).
- **G + bordo**:
  - esattamente l'ottimo in 230 tratte su 256 (linee: 139 su 146), entro l'1% in 249;
  - media +0,055% (linee +0,069%), massimo +1,74% (linee +3,08%), nessuna oltre il 2% (linee 3);
  - regime giusto 256 su 256; 56 simulazioni a tratta, 0,39 s.
- **I riferimenti peggiorano sul test:** la migliore delle 288 sale a +1,87% di mediana, la semplice a +0,57%.
- **Gli scarti di G** sono 9 ibridi lunghi (170–295 km), fra +0,56% e +1,74%. G si ferma in un'altra valle del costo, con n lontana ma costo quasi uguale.

Conclusione: **il risultato delle linee si conferma su tratte indipendenti.**
