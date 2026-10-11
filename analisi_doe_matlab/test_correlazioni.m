function test_correlazioni
% TEST_CORRELAZIONI Controllo facoltativo dell'implementazione statistica.
% Nella Command Window scrivere: test_correlazioni
% Usa valori attesi e, se disponibili, corr e partialcorr ufficiali di MATLAB.
% Non legge o modifica i risultati delle simulazioni.

% Primo controllo: ranghi e coefficienti su un piccolo esempio con pareggi.
assert(isequal(ranghi_medi([10;30;20;20]), [1;4;2.5;2.5]));
X = [1 8 3; 2 4 3; 2 6 1; 4 2 7; 5 9 5; ...
    6 1 4; 6 3 2; 8 7 8; 9 5 6; 10 10 9];
y = [3;1;2;7;4;8;5;6;10;9];
[r, p] = calcola_correlazioni(X, y);
r_attesi = [0.8353813836471727; -0.09090909090909088; 0.6990913752320743];
p_attesi = [0.7238717804972106; -0.5128429903623107; 0.5004666291642546];
assert(max(abs(r-r_attesi)) < 1e-10);
assert(max(abs(p-p_attesi)) < 1e-10);

rng(42); % Dati di prova riproducibili.
X = randn(80, 9);
y = 2 * X(:,1) - X(:,3) + 0.2 * randn(80,1);
verifica_riferimento(X, y);

% Verifica anche valori ripetuti: i ranghi devono gestire i pareggi.
X = round(2 * randn(80, 9));
y = round(2 * X(:,2) + X(:,4) + randn(80,1));
verifica_riferimento(X, y);

% Output costante: la correlazione non esiste, non vale zero.
[r, p] = calcola_correlazioni(X, ones(80,1));
assert(all(isnan(r)) && all(isnan(p)));

% Un input costante non deve impedire l'analisi degli altri input.
X(:,9) = 7;
[r, p] = calcola_correlazioni(X, y);
assert(isnan(r(9)) && isnan(p(9)));
[r8, p8] = calcola_correlazioni(X(:,1:8), y);
assert(max(abs(r(1:8)-r8)) < 1e-10);
assert(max(abs(p(1:8)-p8)) < 1e-10);

% Pochi casi rispetto ai controlli: Spearman disponibile, PRCC non stimabile.
[r, p] = calcola_correlazioni(randn(4,9), randn(4,1));
assert(all(isfinite(r)) && all(isnan(p)));

% Input duplicati: niente PRCC arbitraria per i fattori indistinguibili.
X = randn(80,9); X(:,2) = X(:,1);
[~, p] = calcola_correlazioni(X, randn(80,1));
assert(all(isnan(p)));

% Nessun caso disponibile: restituisce NaN senza interrompere l'analisi.
[r, p] = calcola_correlazioni(zeros(0,9), zeros(0,1));
assert(all(isnan(r)) && all(isnan(p)));

fprintf('Tutti i test delle correlazioni sono superati.\n');
end

function verifica_riferimento(X, y)
% Questa parte aggiuntiva richiede la toolbox statistica, non il programma.
if isempty(ver('stats')) || ~license('test','Statistics_Toolbox')
    return
end
[r, p] = calcola_correlazioni(X, y);
r_matlab = corr(X, y, 'Type','Spearman');
assert(max(abs(r-r_matlab)) < 1e-10, 'Spearman diverso dal riferimento MATLAB.');
for i = 1:size(X,2)
    altri = setdiff(1:size(X,2), i);
    p_matlab = partialcorr(X(:,i), y, X(:,altri), 'Type','Spearman');
    assert(abs(p(i)-p_matlab) < 1e-10, 'PRCC diversa dal riferimento MATLAB.');
end
end
