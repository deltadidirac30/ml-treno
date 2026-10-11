function [rho, prcc, note, n_controlli] = calcola_correlazioni(X, y)
% CALCOLA_CORRELAZIONI Spearman e PRCC tra tutti gli input X e un output y.
% Ogni riga e' una tratta. Ogni colonna di X e' un parametro della tratta.
% Passare soltanto righe senza NaN o Inf: la selezione avviene nel programma
% principale, sullo stesso campione per Spearman e PRCC.
%
% PRCC = correlazione parziale sui ranghi. I passaggi sono scritti qui
% esplicitamente per capire il metodo, senza nasconderli in partialcorr.
% Il test allegato verifica valori attesi e, se disponibile, partialcorr.

y = y(:);
[N, P] = size(X);
assert(size(y, 1) == N, 'X e y devono avere lo stesso numero di righe.');
assert(all(isfinite(X(:))) && all(isfinite(y)), ...
    'Prima del calcolo bisogna escludere le righe con NaN o Inf.');

rho = NaN(P, 1);
prcc = NaN(P, 1);
note = repmat("OK", P, 1);
n_controlli = NaN(P, 1);
if N < 3
    note(:) = "Meno di 3 casi disponibili";
    return
end
if all(y == y(1))
    note(:) = "Output costante: correlazione non definita";
    return
end

% 1. Trasformazione in ranghi: il valore piu' piccolo ha rango 1, ecc.
%    Ai valori uguali viene assegnata la media delle posizioni occupate.
R = ranghi_medi(X);
Ry = ranghi_medi(y);
variabili = any(X ~= X(1, :), 1);

for i = 1:P
    if ~variabili(i)
        note(i) = "Input costante: correlazione non definita";
        continue
    end

    % Spearman e' la correlazione di Pearson tra i ranghi originali.
    C = corrcoef(R(:, i), Ry);
    rho(i) = C(1, 2);

    % 2. Gli altri input sono i controlli. Un input costante non aggiunge
    %    informazione e viene escluso dai controlli, non dai dati originali.
    altri = variabili;
    altri(i) = false;
    n_controlli(i) = sum(altri);
    Z = [ones(N, 1), R(:, altri)]; % La prima colonna e' l'intercetta.

    % Servono osservazioni sufficienti e controlli non collineari.
    % Se il calcolo non e' identificabile, lasciamo NaN: NON mettiamo zero.
    if N <= size(Z, 2) + 1
        note(i) = "Troppi controlli rispetto ai casi per calcolare PRCC";
        continue
    end
    if rank(Z) < size(Z, 2)
        note(i) = "Controlli collineari: PRCC non identificabile";
        continue
    end

    % 3. Due regressioni sui ranghi. Z\R trova i coefficienti della
    %    regressione. Il residuo e' valore osservato meno valore previsto.
    residuo_input = R(:, i) - Z * (Z \ R(:, i));
    residuo_output = Ry - Z * (Z \ Ry);

    % Un residuo praticamente nullo non consente una correlazione.
    scala_input = norm(R(:, i) - mean(R(:, i)));
    scala_output = norm(Ry - mean(Ry));
    if norm(residuo_input) <= 1e-10 * scala_input || ...
            norm(residuo_output) <= 1e-10 * scala_output
        note(i) = "Residuo nullo: PRCC non identificabile";
        continue
    end

    % 4. PRCC: Pearson tra i due residui. Non bisogna applicare di nuovo
    %    Spearman ai residui, perche' abbiamo gia' trasformato i dati in ranghi.
    C = corrcoef(residuo_input, residuo_output);
    prcc(i) = C(1, 2);
end
end
