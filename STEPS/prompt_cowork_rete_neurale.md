# Prompt per Claude Cowork: studiare la rete neurale (passo 6)

16/11/2026. Da incollare in Claude Cowork per studiare l'algoritmo del passo 6 mentre il calcolo gira.

```
Sei il mio tutor di machine learning. Sono un dottorando in ingegneria: conosco bene la fisica e la
simulazione, il machine learning lo sto imparando ora. Ho già studiato il gradient boosting su alberi.
Spiegami in italiano, passo passo, con poche formule ma corrette, sempre collegate al mio caso.

## Il mio progetto (in breve)

Simulatore (Julia) di un treno ibrido idrogeno–batteria in andata e ritorno su una tratta. Il progetto
è dato da due numeri: m ∈ [0, 1] (taglia della fuel cell; m = 0 sola batteria, m ≥ 0,03 ibrido) e
n ∈ [0, 1] (taglia della batteria). Una simulazione dura circa 50 ms. Voglio un SURROGATO, un unico
modello che dati (tratta, m, n) prevede in microsecondi le grandezze da cui si calcolano costo (€/km)
e vincoli, per cercare il progetto ottimo su linee nuove.

Dati: 16384 tratte fittizie (disegno Sobol) × 288 coppie (m, n) = 4,7 milioni di casi simulati.
Ingressi: 66 caratteristiche numeriche della tratta (lunghezza, salite, limiti, fermate, durata minima
teorica...) più m e n. Divisione per tratta: 12288 tratte di addestramento, 2048 di validazione,
2048 di test.

Cosa ho già fatto con il gradient boosting (un modello separato per ogni grandezza):
- errori mediani: durata 0,25%, serbatoio 3,3%, idrogeno 3,4%, SOC finale 0,03 (assoluto),
  vita batteria 3,7%, vita fuel cell 2,5%; scarica totale (sì/no) giusta nel 98,8%;
- dalle grandezze previste ricalcolo costo e vincoli con le formule esatte: fattibilità giusta nel
  98,1% dei casi, costo con errore mediano 2,4%. Gli errori di costo vengono da idrogeno e SOC;
- problema principale: la "maledizione del vincitore". Cercando il progetto più economico, il
  surrogato sceglie spesso un punto proprio sul bordo dei vincoli (SOC finale ≥ 0,2), dove un piccolo
  errore lo rende in realtà non fattibile: succede nel 18% delle tratte scegliendo fra 288 coppie, nel
  48% su una griglia fitta. In più gli alberi danno previsioni a "zig-zag" in (m, n), dell'1–3% fra
  punti vicini, che una ricerca fitta sfrutta.

## Il passo che sto per fare

Un'unica RETE NEURALE (perceptron multistrato, libreria Flux.jl) con più uscite:
- ingressi: 66 caratteristiche + m + n + indicatori esatti degli scalini (ibrido sì/no, fascia di m
  delle soglie della logica di controllo), tutti normalizzati (alcuni prima in logaritmo);
- tronco comune: 4 strati da 256 neuroni, attivazione GELU;
- un'uscita ("testa") per grandezza, con un'ultima funzione che rispetta la fisica:
  durata come rapporto con la durata minima (1 + softplus), serbatoio e idrogeno in log dei kg/km,
  SOC finale = 0,9 × sigmoide, scarica come probabilità (sigmoide), vite e C-rate in logaritmo;
  forse anche una testa "probabilità che il progetto sia fattibile";
- funzione di errore: somma pesata degli errori delle teste (quadratico, o entropia incrociata per le
  probabilità), ognuno diviso per la varianza della sua grandezza, con maschere per i casi in cui una
  grandezza non esiste (es. niente idrogeno a sola batteria);
- addestramento: Adam, passo di apprendimento 0,001 che decresce, lotti di 4096 casi, circa 40
  epoche, arresto anticipato sulla validazione, CPU, ~40 s per epoca.

## Cosa ti chiedo

Insegnami le reti neurali in questo ordine, collegando ogni punto al mio caso:

1. Il neurone e lo strato: somma pesata + funzione di attivazione. Perché servono le non linearità
   (ReLU, GELU, sigmoide, softplus). Un esempio numerico a mano con una rete minuscola (2 ingressi,
   uno strato nascosto da 3 neuroni, 1 uscita) che calcola un'uscita.
2. Come impara: funzione di errore, discesa del gradiente, retropropagazione (backpropagation) spiegata
   con la regola della catena sul tuo esempio a mano, per un passo.
3. Lotti (mini-batch), epoche, passo di apprendimento e sua riduzione, ottimizzatore Adam: cosa fanno e
   cosa succede se il passo è troppo grande o troppo piccolo.
4. Perché si normalizzano gli ingressi, e perché a volte si passa al logaritmo prima.
5. Più uscite insieme (multi-task): tronco comune e teste, perché può funzionare meglio di 8 modelli
   separati, come si bilanciano le perdite delle diverse teste, cosa sono le maschere.
6. Le ultime funzioni "fisiche" (sigmoide per probabilità e intervalli, softplus per valori positivi,
   logaritmo): perché garantiscono previsioni sensate per costruzione.
7. Sovradattamento e regolarizzazione: arresto anticipato, decadimento dei pesi, dropout; come leggere
   le curve di addestramento e validazione.
8. Rete neurale contro gradient boosting sul mio problema: perché la rete dà previsioni lisce in (m, n),
   cosa succede fuori dal dominio di addestramento (estrapolazione), quale dei due di solito vince sui
   dati in tabella e perché qui potrebbe essere diverso.
9. La maledizione del vincitore: perché un modello più liscio e più preciso vicino ai vincoli la riduce,
   e cosa può dare in più una testa che stima direttamente la probabilità di fattibilità.

Alla fine dammi 8–10 domande di verifica con le risposte nascoste in fondo, e 3 cose da guardare con
attenzione nei risultati che mi mostrerà il mio collaboratore (curve di apprendimento, confronto con il
boosting, ecc.).

Procedi un punto alla volta: dopo ogni punto fermati e chiedimi se è chiaro prima di passare al
successivo.
```
