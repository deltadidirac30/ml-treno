# fase13/03_confronto_surrogato.py: le proposte del surrogato (strategia G con il bordo, il default) sulle 146 linee non elettrificate,
# dati del 17/11 (fase13/01_linee.jl) contro dati dell'11/11 (stesso comando, 16/11).
#
#   surrogato cartella=~/Documents/lavoro/train-powertrain/dati_rete/tratte_rete_rinf/tutto_rinf tratta=<le 146 di linee_non_el_70.txt>
#   python3 fase13/03_confronto_surrogato.py > fase13/risultati/03_confronto_surrogato.txt

import csv, os, statistics as st

S = os.path.expanduser('~/Documents/lavoro/ml_treno_dati/surrogato/')
VECCHIO = 'riepilogo_20261116_213611.csv'   # dati 11/11, G + bordo (fase12/17)
NUOVO = 'riepilogo_20261117_230954.csv'     # dati 17/11, G + bordo
o = {r['tratta']: r for r in csv.DictReader(open(S + VECCHIO))}
n = {r['tratta']: r for r in csv.DictReader(open(S + NUOVO))}
print(f'surrogato (G + bordo): dati 17/11 ({NUOVO}) contro dati 11/11 ({VECCHIO})')
d = []; uguali = 0; reg = 0; cambiate = []
for l, r in n.items():
    a = o[l]
    c = 100 * (float(r['costo_simulatore_EUR_km']) / float(a['costo_simulatore_EUR_km']) - 1); d.append(c)
    s = (r['m'], r['n']) == (a['m'], a['n']); uguali += s; reg += r['regime'] == a['regime']
    if abs(c) > 1e-3 or not s:
        cambiate.append((l, c, a['m'], a['n'], r['m'], r['n'], a['regime'], r['regime']))
d.sort(); N = len(d)
print(f'{N} linee; stesso progetto (m, n): {uguali}; stesso regime: {reg}')
print(f'costo verificato col simulatore: mediana {st.median(d):+.2f}%, 10° {d[N // 10]:+.2f}%, 90° {d[9 * N // 10]:+.2f}%, '
      f'min {d[0]:+.2f}%, max {d[-1]:+.2f}%; oltre ±1%: {sum(abs(x) > 1 for x in d)}')
print('\nlinee con il progetto o il costo cambiati (ordinate per variazione del costo):')
for x in sorted(cambiate, key=lambda x: -abs(x[1])):
    print(f'  {x[0]:42s} {x[1]:+6.2f}%   ({x[2]}, {x[3]}) -> ({x[4]}, {x[5]})' + ('' if x[6] == x[7] else f'   {x[6]} -> {x[7]}'))
