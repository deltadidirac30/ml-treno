# fase13/04_surrogato_vs_vero.py: le proposte del surrogato (strategia G con il bordo, dati del 17/11) contro l'ottimo vero
# della griglia fitta simulata sugli stessi dati (fase13/02_griglia_fitta.jl). Come fase12/17, sui dati nuovi.
#
#   python3 fase13/04_surrogato_vs_vero.py > fase13/risultati/04_surrogato_vs_vero.txt

import csv, os, statistics as st

B = os.path.expanduser('~/Documents/lavoro/ml_treno_dati/')
SURR = 'surrogato/riepilogo_20261117_230954.csv'
VERO = 'fase13_log/02_ottimo_linee.csv'
s = {r['tratta']: r for r in csv.DictReader(open(B + SURR))}
v = {r['linea']: r for r in csv.DictReader(open(B + VERO))}
# il riepilogo del surrogato non distingue la FC piccola: il regime si ricava da m, come in fase13/02
regime = lambda m: 'sola batteria' if float(m) == 0 else 'ibrido FC piccola' if float(m) < 0.1 else 'ibrido'
print(f'surrogato G + bordo ({SURR}) contro ottimo vero della griglia fitta ({VERO}), dati 17/11')
d = []; ottimo = 0; reg = 0; fuori = []
for l, o in v.items():
    p = s[l]
    c = 100 * (float(p['costo_simulatore_EUR_km']) / float(o['costo']) - 1); d.append(c)
    same = abs(float(p['m']) - float(o['m'])) < 1e-9 and abs(float(p['n']) - float(o['n'])) < 1e-9
    ottimo += same; reg += regime(p['m']) == regime(o['m'])
    if not same: fuori.append((l, c, p['m'], p['n'], o['m'], o['n'], regime(p['m']), regime(o['m'])))
d.sort(); N = len(d)
print(f'{N} linee; proprio l\'ottimo: {ottimo}; stesso regime: {reg}')
print(f'costo rispetto all\'ottimo vero: media {st.mean(d):+.2f}%, mediana {st.median(d):+.2f}%, 90° {d[9 * N // 10]:+.2f}%, max {d[-1]:+.2f}%')
print(f'entro 0,01% / 0,5% / 1%: {sum(x <= 0.01 for x in d)} / {sum(x <= 0.5 for x in d)} / {sum(x <= 1 for x in d)}; oltre 2%: {sum(x > 2 for x in d)}')
if d[0] < -1e-3: print(f'ATTENZIONE: proposta più economica dell\'ottimo vero ({d[0]:+.4f}%)')
print('\nlinee in cui la proposta non è l\'ottimo (ordinate per scarto):')
for x in sorted(fuori, key=lambda x: -x[1]):
    print(f'  {x[0]:42s} {x[1]:+6.2f}%   proposta ({x[2]}, {x[3]})  ottimo ({x[4]}, {x[5]})' + ('' if x[6] == x[7] else f'   {x[6]} / {x[7]}'))
