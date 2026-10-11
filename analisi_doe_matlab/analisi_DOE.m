function [dati, statistiche, cartella_output] = analisi_DOE(file_excel, fogli_excel, mostra_grafici)
% ANALISI_DOE Analisi esplorativa dei risultati delle tratte ottimizzate.
%
% USO PIU' SEMPLICE: scrivere analisi_DOE nella Command Window e selezionare
% uno o piu' Excel. Il programma legge il primo foglio di ciascun file.
% USO CON PERCORSI: analisi_DOE({'Risultati finali.xlsx','TRATTE OTTIMALI.xlsx'})
% Per scegliere i fogli: analisi_DOE(file_excel, {'Foglio1','Fattori DOE'})
% Per ritrovare i dati nel workspace: [dati, statistiche] = analisi_DOE;
%
% Occorre MATLAB R2020b o successivo, senza toolbox aggiuntive.
% Gli Excel originali non vengono mai modificati. Tenere le funzioni
% calcola_correlazioni.m e ranghi_medi.m nella stessa cartella di questo file.

%% 1. IMPOSTAZIONI MODIFICABILI
direzione = 'andata&ritorno'; % Usare 'andata' soltanto per dati di sola andata.
verifica_stabilita = true;   % Ricalcola escludendo una tratta alla volta.
numero_parametri_top = 3;    % Candidati da approfondire per ciascun output.

% SCATTER DI ESEMPIO: ogni riga contiene {asse X, asse Y, colore dei punti}.
% Per un grafico nuovo basta aggiungere una riga con i nomi delle colonne.
grafici_scatter = {
    'L_km',                   'P_nom_fc_kW', 'stop_density_requested';
    'stop_density_requested', 'TCO_EUR_km',  'v_max_kmh';
    'v_max_kmh',              'TCO_EUR_km',  'stop_density_requested';
    'slope_mean',             'SOC_end',     'L_km';
    'L_km',                   'C_batt_kWh',  'P_nom_fc_kW'
};

if nargin < 1, file_excel = {}; end
if nargin < 2, fogli_excel = {}; end
if nargin < 3, mostra_grafici = true; end
if isempty(file_excel)
    [nomi, percorso] = uigetfile('*.xlsx', 'Selezionare gli Excel dei risultati', ...
        'MultiSelect', 'on');
    if isequal(nomi, 0), error('DOE:Annullato', 'Selezione annullata.'); end
    file_excel = fullfile(percorso, cellstr(string(nomi)));
end
file_excel = cellstr(string(file_excel));
fogli_excel = cellstr(string(fogli_excel));
if ~isempty(fogli_excel) && numel(fogli_excel) ~= numel(file_excel)
    error('DOE:Fogli', 'Indicare un foglio per ciascun Excel, oppure nessuno.');
end

%% 2. COLONNE: INPUT DI TRATTA E OUTPUT DELL'OTTIMIZZATORE
% Gli input sono i nove fattori del DoE, non route_id, m o n.
% Non aggiungiamo il numero di fermate: deriva da densita' e lunghezza.
input = {'L_km','slope_mean','slope_std','slope_segment_length_mean_km', ...
    'stop_density_requested','stop_spacing_cv','v_max_kmh', ...
    'speed_restriction_index','speed_change_density_requested'};
etichette_input = {'Lunghezza','Pendenza media','Variabilita pendenza', ...
    'Lunghezza segmenti pendenza','Densita fermate','Irregolarita fermate', ...
    'Velocita massima','Restrizioni velocita','Densita cambi velocita'};
unita_input = {'km','per mille','per mille','km','fermate/km','-', ...
    'km/h','-','cambi/km'};

output = {'P_nom_fc_kW','C_batt_kWh','m','n','H2_cons_kg','H2_kg_km', ...
    'SOC_end','TCO_EUR_km','CAPEX_FC_EUR_km','CAPEX_batt_EUR_km', ...
    'CAPEX_tank_EUR_km','OPEX_batt_rech_EUR_km_att', ...
    'OPEX_H2_rech_EUR_km_att','OPEX_mant_FC_EUR_km_att', ...
    'OPEX_mant_batt_EUR_km_att','OPEX_mant_tank_EUR_km_att', ...
    'cost_repl_FC_EUR_km_att','cost_repl_batt_EUR_km_att', ...
    'num_repl_FC_active','num_repl_batt'};
etichette_output = {'Potenza FC','Capacita batteria','m ottimizzato', ...
    'n ottimizzato','H2 per viaggio','H2 per km','SOC finale','TCO', ...
    'CAPEX FC','CAPEX batteria','CAPEX serbatoio','Ricarica elettrica', ...
    'Ricarica H2','Manutenzione FC','Manutenzione batteria', ...
    'Manutenzione serbatoio','Costo sostituzioni FC', ...
    'Costo sostituzioni batteria','Sostituzioni FC (presente)', ...
    'Sostituzioni batteria'};
unita_output = [{'kW','kWh','-','-','kg','kg/km','-'}, ...
    repmat({'EUR/km'}, 1, 11), {'numero nei 20 anni','numero nei 20 anni'}];
nomi = [input, output];
etichette = [etichette_input, etichette_output];
unita = [unita_input, unita_output];

%% 3. IMPORTAZIONE E PREPARAZIONE DEI DATI
% H2_kg_km e num_repl_FC_active sono derivati, non colonne richieste negli Excel.
originali_output = output(~ismember(output, {'H2_kg_km','num_repl_FC_active'}));
originali_output = [originali_output, {'num_repl_FC','total_cost_EUR_km'}];
colonne = [{'route_id'}, input, originali_output];
dati = table();
for f = 1:numel(file_excel)
    if isempty(fogli_excel)
        elenco = sheetnames(file_excel{f});
        foglio = char(elenco(1));
    else
        foglio = fogli_excel{f};
    end
    T = leggi_excel(file_excel{f}, foglio, colonne, input);
    dati = [dati; T]; %#ok<AGROW>
    fprintf('Letto %s, foglio %s: %d righe.\n', file_excel{f}, foglio, height(T));
end
if isempty(dati), error('DOE:Vuoto', 'Nessuna tratta trovata.'); end
if any(~isfinite(dati.route_id)) || any(dati.route_id ~= round(dati.route_id))
    error('DOE:ID', 'Ogni riga deve avere un route_id numerico intero.');
end
if numel(unique(dati.route_id)) ~= height(dati)
    error('DOE:Duplicati', ['Ci sono route_id duplicati. Scegliere una sola ' ...
        'ottimizzazione per tratta prima di unire gli Excel.']);
end
dati = sortrows(dati, 'route_id');
if any(isfinite(dati.L_km) & dati.L_km <= 0)
    error('DOE:Lunghezza', 'La lunghezza deve essere positiva.');
end
switch direzione
    case 'andata&ritorno', fattore_distanza = 2;
    case 'andata', fattore_distanza = 1;
    otherwise, error('DOE:Direzione', 'Usare andata oppure andata&ritorno.');
end
dati.distance_simulated_km = fattore_distanza * dati.L_km;
dati.H2_kg_km = dati.H2_cons_kg ./ dati.distance_simulated_km;

% Manteniamo i contatori originali. Per la sola analisi delle sostituzioni
% FC, un componente assente non e' applicabile: non sostituiamo NaN con zero.
dati.num_repl_FC_active = dati.num_repl_FC;
dati.num_repl_FC_active(~isfinite(dati.P_nom_fc_kW) | dati.P_nom_fc_kW <= 0) = NaN;
X = dati{:, input};
dati.input_completi = all(isfinite(X), 2);
dati.output_presente = any(isfinite(dati{:, originali_output}), 2);
fprintf('\nTratte importate: %d. Righe senza alcun output: %d.\n', ...
    height(dati), sum(~dati.output_presente));

% Una cartella nuova per ogni esecuzione: non sovrascriviamo analisi precedenti.
base = fileparts(mfilename('fullpath'));
[~, nome_univoco] = fileparts(tempname(base));
cartella_output = fullfile(base, ['risultati_',nome_univoco]);
mkdir(cartella_output);
cartella_grafici = fullfile(cartella_output, 'grafici');
mkdir(cartella_grafici);
visibilita = 'on';
if ~mostra_grafici, visibilita = 'off'; end

%% 4. SPEARMAN, PRCC E CONTROLLO DI STABILITA'
P = numel(input); Q = numel(output);
rho = NaN(P, Q); prcc = NaN(P, Q); n_casi = zeros(Q, 1);
note = strings(P, Q); n_controlli = NaN(P, Q);
rho_min = NaN(P, Q); rho_max = NaN(P, Q);
prcc_min = NaN(P, Q); prcc_max = NaN(P, Q);
n_loo_rho = zeros(P, Q); n_loo_prcc = zeros(P, Q);
campioni = dati(:, {'route_id','source_file','source_sheet'});

for j = 1:Q
    y = dati.(output{j});
    % Per ciascun output usiamo tutte le righe con nove input e quell'output.
    % Un risultato mancante non elimina la tratta dalle analisi degli altri output.
    usa = dati.input_completi & isfinite(y);
    campioni.(output{j}) = usa;
    Xj = X(usa, :); yj = y(usa);
    n_casi(j) = sum(usa);
    [rho(:,j), prcc(:,j), note(:,j), n_controlli(:,j)] = calcola_correlazioni(Xj, yj);

    if verifica_stabilita && n_casi(j) >= 4
        % Leave-one-out: togliamo un caso, ricalcolando anche i ranghi.
        % Minimo/massimo NON sono intervalli di confidenza.
        r_loo = NaN(P, n_casi(j)); p_loo = r_loo;
        for k = 1:n_casi(j)
            tieni = true(n_casi(j), 1); tieni(k) = false;
            [r_loo(:,k), p_loo(:,k)] = calcola_correlazioni(Xj(tieni,:), yj(tieni));
        end
        rho_min(:,j) = min(r_loo, [], 2, 'omitnan');
        rho_max(:,j) = max(r_loo, [], 2, 'omitnan');
        prcc_min(:,j) = min(p_loo, [], 2, 'omitnan');
        prcc_max(:,j) = max(p_loo, [], 2, 'omitnan');
        n_loo_rho(:,j) = sum(isfinite(r_loo), 2);
        n_loo_prcc(:,j) = sum(isfinite(p_loo), 2);
    end
end

% Classifiche SEPARATE per output e per metodo, ordinate per valore assoluto.
% Essere primi non implica avere un'associazione forte o causale.
pos_rho = classifica(rho); pos_prcc = classifica(prcc);
statistiche = table(repmat(string(input(:)), Q, 1), ...
    repelem(string(output(:)), P), repelem(n_casi, P), rho(:), prcc(:), ...
    pos_rho(:), pos_prcc(:), rho_min(:), rho_max(:), prcc_min(:), prcc_max(:), ...
    n_loo_rho(:), n_loo_prcc(:), n_controlli(:), note(:), ...
    'VariableNames', {'Input','Output','N_casi','Spearman','PRCC', ...
    'Posizione_Spearman','Posizione_PRCC','Spearman_LOO_min','Spearman_LOO_max', ...
    'PRCC_LOO_min','PRCC_LOO_max','N_LOO_validi_Spearman','N_LOO_validi_PRCC', ...
    'N_controlli_PRCC','Nota'});
top = statistiche(statistiche.Posizione_Spearman <= numero_parametri_top | ...
    statistiche.Posizione_PRCC <= numero_parametri_top, :);

%% 5. SALVATAGGIO DELLE TABELLE, LEGGIBILI ANCHE IN EXCEL
writetable(dati, fullfile(cartella_output, 'dati_importati.csv'));
writetable(campioni, fullfile(cartella_output, 'campioni_utilizzati.csv'));
writetable(statistiche, fullfile(cartella_output, 'statistiche_complete.csv'));
writetable(top, fullfile(cartella_output, 'parametri_da_approfondire.csv'));
salva_matrice(rho, input, output, fullfile(cartella_output, 'matrice_spearman.csv'));
salva_matrice(prcc, input, output, fullfile(cartella_output, 'matrice_prcc.csv'));
xc = X(dati.input_completi & dati.output_presente, :);
if size(xc, 1) >= 3
    salva_matrice(corrcoef(ranghi_medi(xc)), input, input, ...
        fullfile(cartella_output, 'correlazioni_tra_input.csv'));
end
dizionario = table(string(nomi(:)), string(etichette(:)), string(unita(:)), ...
    'VariableNames', {'Colonna','Significato','Unita'});
writetable(dizionario, fullfile(cartella_output, 'dizionario_variabili.csv'));
impostazioni = table(string(direzione), fattore_distanza, verifica_stabilita, ...
    numero_parametri_top, string(version), 'VariableNames', ...
    {'Direzione','Fattore_distanza','Verifica_stabilita','Numero_top','Versione_MATLAB'});
writetable(impostazioni, fullfile(cartella_output, 'impostazioni.csv'));

%% 6. MAPPE DEI COEFFICIENTI, DIVISE IN TRE GRUPPI LEGGIBILI
gruppi = {1:7, 8:18, 19:20};
titoli = {'Sizing e funzionamento','Costi','Indicatori indiretti di degrado'};
for g = 1:3
    indici = gruppi{g};
    % Il numero di casi e' scritto in ciascuna etichetta di colonna.
    label_out = strcat(string(etichette_output(indici)), ...
        " (N=", string(n_casi(indici)'), ")");
    mappa_coefficienti(rho(:,indici), etichette_input, label_out, ...
        ['Spearman - ',titoli{g}], cartella_grafici, ...
        sprintf('spearman_%d',g), visibilita);
    mappa_coefficienti(prcc(:,indici), etichette_input, label_out, ...
        ['PRCC - ',titoli{g}], cartella_grafici, ...
        sprintf('prcc_%d',g), visibilita);
end

%% 7. SCATTER DI ESEMPIO E UNA MAPPA A DUE INPUT
% I grafici mostrano dati osservati: gli altri input NON sono mantenuti fissi.
for g = 1:size(grafici_scatter, 1)
    crea_scatter(dati, grafici_scatter{g,1}, grafici_scatter{g,2}, ...
        grafici_scatter{g,3}, dizionario, cartella_grafici, ...
        sprintf('scatter_%02d',g), visibilita);
end
% Mappa: due input sugli assi, costo come colore. Non viene interpolata.
crea_scatter(dati, 'v_max_kmh', 'stop_density_requested', 'TCO_EUR_km', ...
    dizionario, cartella_grafici, 'mappa_velocita_fermate_costo', visibilita);

fprintf('\nAnalisi salvata in:\n%s\n', cartella_output);
fprintf('I NaN indicano risultati mancanti, non applicabili o non identificabili.\n');
fprintf('I coefficienti descrivono associazioni, non percentuali di influenza.\n');
end

%% PICCOLE FUNZIONI DI SUPPORTO
function T = leggi_excel(file, foglio, colonne, input)
T = readtable(file, 'Sheet',foglio, 'Range','A1', 'VariableNamingRule','preserve');
% I due Excel usano alternativamente Tratta e route_id per lo stesso ID.
if ~ismember('route_id', T.Properties.VariableNames) && ...
        ismember('Tratta', T.Properties.VariableNames)
    T.Properties.VariableNames{strcmp(T.Properties.VariableNames,'Tratta')} = 'route_id';
end
richieste = [{'route_id'}, input];
mancanti = richieste(~ismember(richieste, T.Properties.VariableNames));
if ~isempty(mancanti)
    error('DOE:Colonne', 'In %s mancano gli input: %s', file, strjoin(mancanti,', '));
end
for c = 1:numel(colonne)
    nome = colonne{c};
    if ~ismember(nome, T.Properties.VariableNames)
        warning('DOE:OutputMancante', 'In %s manca %s: lasciato NaN.', file, nome);
        T.(nome) = NaN(height(T), 1);
    elseif ~isnumeric(T.(nome))
        % Consente numeri memorizzati come testo, anche con virgola decimale.
        testo = strtrim(string(T.(nome)));
        valore = str2double(strrep(testo, ',', '.'));
        vuoto = ismissing(testo) | ismember(lower(testo), ["","nan","na","n/a","n.a."]);
        if any(isnan(valore) & ~vuoto)
            error('DOE:Testo', 'Testo non numerico nella colonna %s di %s.', nome, file);
        end
        T.(nome) = valore;
    else
        T.(nome) = double(T.(nome));
    end
end
T = T(:, colonne); % L'ordine dei campi originali nel foglio non e' importante.
T(all(isnan(T{:,:}), 2), :) = []; % Ignora soltanto righe completamente vuote.
T.source_file = repmat(string(file), height(T), 1);
T.source_sheet = repmat(string(foglio), height(T), 1);
end

function posizione = classifica(M)
posizione = NaN(size(M));
for j = 1:size(M, 2)
    disponibili = find(isfinite(M(:,j)));
    [~, ordine] = sort(abs(M(disponibili,j)), 'descend');
    posizione(disponibili(ordine),j) = (1:numel(disponibili))';
end
end

function salva_matrice(M, righe, colonne, file)
T = array2table(M, 'VariableNames',colonne, 'RowNames',righe);
writetable(T, file, 'WriteRowNames',true);
end

function mappa_coefficienti(M, label_in, label_out, titolo, cartella, nome, visibilita)
f = figure('Color','w', 'Visible',visibilita, 'Position',[50 50 1450 650]);
% Scala divergente fissa: blu negativo, bianco zero, rosso positivo.
colori = [linspace(0.15,1,128)', linspace(0.35,1,128)', ones(128,1); ...
    ones(128,1), linspace(1,0.25,128)', linspace(1,0.2,128)'];
h = heatmap(f, label_out, label_in, M, 'Colormap',colori, ...
    'ColorLimits',[-1 1], 'CellLabelFormat','%.2f', 'FontSize',11);
h.Title = titolo;
h.MissingDataLabel = 'n.a.';
h.MissingDataColor = [0.85 0.85 0.85];
salva_figura(f, h, cartella, nome, visibilita);
end

function crea_scatter(dati, nome_x, nome_y, nome_colore, dizionario, cartella, nome, visibilita)
% Questa funzione puo' essere richiamata per nuovi grafici nella sezione 7.
x = dati.(nome_x); y = dati.(nome_y); colore = dati.(nome_colore);
usa = dati.input_completi & isfinite(x) & isfinite(y) & isfinite(colore);
if ~any(usa)
    warning('DOE:GraficoVuoto', 'Nessun dato disponibile per %s.', nome);
    return
end
f = figure('Color','w', 'Visible',visibilita, 'Position',[100 100 850 600]);
scatter(x(usa), y(usa), 65, colore(usa), 'filled', 'MarkerEdgeColor',[0.2 0.2 0.2]);
xlabel(etichetta(nome_x, dizionario), 'Interpreter','none');
ylabel(etichetta(nome_y, dizionario), 'Interpreter','none');
cb = colorbar;
cb.Label.String = etichetta(nome_colore, dizionario);
cb.Label.Interpreter = 'none';
colormap(f, parula);
title(sprintf('%s - %s (N=%d)', ...
    dizionario.Significato(dizionario.Colonna == nome_y), ...
    dizionario.Significato(dizionario.Colonna == nome_x), sum(usa)), 'Interpreter','none');
grid on; box on;
set(gca, 'FontSize',12);
% Un piccolo margine evita di tagliare i punti ai bordi, anche per valori zero.
margine_x = 0.04 * (max(x(usa)) - min(x(usa)));
margine_y = 0.04 * (max(y(usa)) - min(y(usa)));
if margine_x > 0
    xlim([min(x(usa))-margine_x, max(x(usa))+margine_x]);
end
if margine_y > 0
    ylim([min(y(usa))-margine_y, max(y(usa))+margine_y]);
end
% Salviamo anche i punti utilizzati: ogni punto si puo' risalire al route_id.
campione = dati(usa, unique({'route_id',nome_x,nome_y,nome_colore}, 'stable'));
writetable(campione, fullfile(cartella, [nome,'_punti.csv']));
salva_figura(f, gca, cartella, nome, visibilita);
end

function label = etichetta(nome, dizionario)
i = find(dizionario.Colonna == nome, 1);
label = sprintf('%s [%s]', dizionario.Significato(i), dizionario.Unita(i));
end

function salva_figura(f, oggetto, cartella, nome, visibilita)
exportgraphics(oggetto, fullfile(cartella, [nome,'.png']), 'Resolution',300);
savefig(f, fullfile(cartella, [nome,'.fig'])); % Modificabile in MATLAB.
if strcmp(visibilita,'off'), close(f); end
end
