function R = ranghi_medi(X)
% RANGHI_MEDI Sostituisce i valori di ogni colonna con le loro posizioni.
% Usa soltanto MATLAB base. X deve avere una tratta per riga, senza NaN/Inf.
% Esempio: [10; 30; 20; 20] diventa [1; 4; 2.5; 2.5].
% I due 20 occupano le posizioni 2 e 3: ricevono la loro media, 2.5.

assert(all(isfinite(X(:))), 'Passare ai ranghi soltanto valori finiti.');
[N, P] = size(X);
R = zeros(N, P);
for j = 1:P
    [valori, ordine] = sort(X(:,j));
    inizio = 1;
    while inizio <= N
        fine = inizio;
        % Cerchiamo l'ultima posizione dello stesso valore ordinato.
        while fine < N && valori(fine+1) == valori(inizio)
            fine = fine + 1;
        end
        % Assegniamo il rango medio, poi torniamo all'ordine delle tratte.
        R(ordine(inizio:fine),j) = (inizio + fine) / 2;
        inizio = fine + 1;
    end
end
end
