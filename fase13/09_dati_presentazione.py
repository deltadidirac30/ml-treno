# fase13/09: come fase12/18, sulle linee con i dati del 17/11 (fase13/01). I dati per la presentazione in fase13/presentazione_146/:
#   linee_146.csv       una riga per linea: proposta del surrogato (G + bordo), ottimo vero, regione, coordinate
#   linee_146.geojson   il tracciato di ogni linea (dalle sezioni di dati_rete/mappa_rete_completa.html) con le stesse proprietà
#   heatmap_<linea>.csv il costo su tutti i 9702 progetti (m, n), simulatore e rete affiancati, per 3 linee d'esempio
#   riassunto.txt       i numeri aggregati (regimi, costi, taglie, rete contro simulatore sulla griglia, tempi)
# Ingressi: fase13/02 (griglia fitta simulata), fase13/08 (ottimo vero e confronti), il comando `surrogato … tratta=<le 146> griglia=si`
# (riepilogo e griglia della rete, 18/11). Uso, dalla cartella ml_treno: python3 fase13/09_dati_presentazione.py
import csv, json, math, os, statistics as st
import numpy as np

H = os.path.expanduser("~")
DATI = os.path.join(H, "Documents/lavoro/ml_treno_dati")
MAPPA = os.path.join(H, "Documents/lavoro/train-powertrain/dati_rete/mappa_rete_completa.html")
RIEP = os.path.join(DATI, "surrogato/riepilogo_20261118_085353.csv")       # surrogato G + bordo, griglia=si, dati 17/11
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "presentazione_146")
ESEMPI = ["Grosseto-Siena", "Cagliari-Olbia_Terranova", "Brescia-Iseo"]
os.makedirs(OUT, exist_ok=True)

O = {r["linea"]: r for r in csv.DictReader(open(os.path.join(DATI, "fase13_log/08_ottimo_vero_linee.csv")))}
R = {r["tratta"]: r for r in csv.DictReader(open(RIEP))}

# sezioni della mappa, raggruppate per tronco (= linea)
s = open(MAPPA).read()
a = s.find("/*__SEZIONI__*/") + len("/*__SEZIONI__*/")
sez, _ = json.JSONDecoder().raw_decode(s[a:].lstrip())
tronchi = {}
for f in sez["features"]:
    tronchi.setdefault(f["properties"]["tronco"], []).append(f)
def sezioni(linea):
    if linea in tronchi: return tronchi[linea]
    alt = linea[::-1].replace("_", "+", 1)[::-1]        # GAGLIANO-GALLIPOLI-L4_3 → …-L4+3
    return tronchi[alt]

def regime(m): return "sola batteria" if m == 0 else ("ibrido FC piccola" if m < 0.1 else "ibrido")

def leggi_registro(linea):
    d = {}
    for r in csv.DictReader(open(os.path.join(DATI, "fase13/griglia_rinf", linea, "registro.csv"))):
        d[(round(float(r["m"]), 2), round(float(r["n"]), 2))] = (r["tipo_esito"], float(r["total_cost_EUR_km"]) if r["total_cost_EUR_km"] not in ("", "NaN") else math.nan)
    return d
def leggi_rete(linea):
    d = {}
    for r in csv.DictReader(open(os.path.join(DATI, "surrogato", linea, "griglia_rete.csv"))):
        d[(round(float(r["m"]), 2), round(float(r["n"]), 2))] = (float(r["costo_rete_EUR_km"]), r["fattibile_rete"] == "true", float(r["SOC_rete"]))
    return d

righe, feats = [], []
acc_fatt, err_costo, n_punti = [], [], 0
for linea, o in O.items():
    r = R[linea]; ss = sezioni(linea); p0 = ss[0]["properties"]
    L_sez = sum(f["properties"]["L_km"] for f in ss); L_ne = sum(f["properties"]["L_km"] for f in ss if not f["properties"]["elettrificata"])
    coords = [c for f in ss for c in f["geometry"]["coordinates"]]
    lon = st.mean(c[0] for c in coords); lat = st.mean(c[1] for c in coords)
    m, n = float(r["m"]), float(r["n"])
    cs, cr, co = float(r["costo_simulatore_EUR_km"]), float(r["costo_rete_EUR_km"]), float(o["ottimo_costo"])
    # rete contro simulatore su tutta la griglia
    G, N = leggi_registro(linea), leggi_rete(linea)
    ok_s = np.array([G[k][0] == "fattibile" for k in G]); ok_r = np.array([N[k][1] for k in G])
    acc_fatt.append(float(np.mean(ok_s == ok_r)))
    e = [abs(N[k][0] / G[k][1] - 1) for k in G if G[k][0] == "fattibile" and math.isfinite(N[k][0])]
    err_costo.extend(e); n_punti += len(G)
    riga = dict(linea=linea, regione=p0["regione"], L_km=round(float(r["L_km"]), 1), quota_non_elettrificata=round(L_ne / L_sez, 3),
                lat=round(lat, 4), lon=round(lon, 4),
                m=m, n=n, regime=regime(m), P_FC_kW=round(float(r["P_nom_FC_kW"])), C_batt_kWh=round(float(r["C_batt_kWh"])),
                costo_EUR_km=round(cs, 4), costo_rete_EUR_km=round(cr, 4), errore_rete_costo_pct=round(100 * (cr / cs - 1), 2),
                simulazioni_surrogato=int(r["candidati_verificati"]), distanza_addestramento=float(r["distanza"]), giudizio_distanza=r["giudizio"],
                ottimo_m=float(o["ottimo_m"]), ottimo_n=float(o["ottimo_n"]), ottimo_regime=o["ottimo_regime"], ottimo_costo_EUR_km=round(co, 4),
                scarto_surrogato_pct=round(100 * (cs / co - 1), 3), scarto_semplice_pct=float(o["semplice_vs_ottimo_pct"]),
                scarto_migliore288_pct=float(o["migliore288_vs_ottimo_pct"]), progetti_fattibili=int(o["fattibili"]),
                fattibilita_rete_giusta_pct=round(100 * acc_fatt[-1], 1), tempo_griglia_cpu_s=float(o["t_griglia_cpu_s"]))
    righe.append(riga)
    geom = {"type": "MultiLineString", "coordinates": [f["geometry"]["coordinates"] for f in ss]}
    feats.append({"type": "Feature", "geometry": geom, "properties": riga})
    if linea in ESEMPI:
        with open(os.path.join(OUT, f"heatmap_{linea}.csv"), "w", newline="") as io:
            w = csv.writer(io); w.writerow(["m", "n", "esito_simulatore", "costo_simulatore_EUR_km", "fattibile_rete", "costo_rete_EUR_km", "SOC_rete"])
            for k in sorted(G):
                w.writerow([k[0], k[1], G[k][0], G[k][1], N[k][1], N[k][0], round(N[k][2], 4)])

with open(os.path.join(OUT, "linee_146.csv"), "w", newline="") as io:
    w = csv.DictWriter(io, fieldnames=list(righe[0])); w.writeheader(); w.writerows(righe)
json.dump({"type": "FeatureCollection", "features": feats}, open(os.path.join(OUT, "linee_146.geojson"), "w"), ensure_ascii=False)

# riassunto
q = lambda v, p: float(np.percentile(v, p))
out = []
P = lambda *x: out.append(" ".join(str(y) for y in x))
P("146 linee non elettrificate oltre il 70% (dati RINF del 17/11), treno di 195 t, andata e ritorno. Surrogato = strategia G con il bordo (default).")
P("")
P("REGIMI (proposta del surrogato | ottimo vero)")
for g in ("sola batteria", "ibrido FC piccola", "ibrido"):
    v = [x for x in righe if x["regime"] == g]
    c = [x["costo_EUR_km"] for x in v]; Lk = [x["L_km"] for x in v]
    P(f"  {g:18s} {len(v):3d} | {sum(x['ottimo_regime'] == g for x in righe):3d}   costo €/km min {min(c):.2f} mediana {st.median(c):.2f} max {max(c):.2f}"
      f"   lunghezza km mediana {st.median(Lk):.0f} ({min(Lk):.0f}–{max(Lk):.0f})"
      f"   FC kW {min(x['P_FC_kW'] for x in v)}–{max(x['P_FC_kW'] for x in v)}   batteria kWh {min(x['C_batt_kWh'] for x in v)}–{max(x['C_batt_kWh'] for x in v)}")
c = [x["costo_EUR_km"] for x in righe]
P(f"  costo di tutte: min {min(c):.2f}, mediana {st.median(c):.2f}, max {max(c):.2f} €/km")
P("")
P("PER REGIONE (sola batteria / ibrido FC piccola / ibrido)")
for reg in sorted({x["regione"] for x in righe}):
    v = [x for x in righe if x["regione"] == reg]
    P(f"  {reg:22s} {len(v):3d}:  {sum(x['regime']=='sola batteria' for x in v)} / {sum(x['regime']=='ibrido FC piccola' for x in v)} / {sum(x['regime']=='ibrido' for x in v)}")
P("")
P("PER LUNGHEZZA (sola batteria / ibrido FC piccola / ibrido)")
for a_, b_ in ((0, 30), (30, 60), (60, 90), (90, 150), (150, 1000)):
    v = [x for x in righe if a_ <= x["L_km"] < b_]
    P(f"  {a_:3d}–{b_ if b_ < 1000 else '':>3} km {len(v):3d}:  {sum(x['regime']=='sola batteria' for x in v)} / {sum(x['regime']=='ibrido FC piccola' for x in v)} / {sum(x['regime']=='ibrido' for x in v)}")
P("")
sc = [x["scarto_surrogato_pct"] for x in righe]
P("SCELTA RISPETTO ALL'OTTIMO VERO (griglia fitta simulata)")
P(f"  surrogato: ottimo in {sum(v <= 0.01 for v in sc)}, media {st.mean(sc):+.2f}%, peggiore {max(sc):+.2f}%, stesso regime {sum(x['regime'] == x['ottimo_regime'] for x in righe)}")
P("")
P("RETE CONTRO SIMULATORE SU TUTTA LA GRIGLIA (146 linee × 9702 progetti = %d progetti)" % n_punti)
P(f"  fattibilità giusta: {100 * sum(acc_fatt) / len(acc_fatt):.1f}% in media (linea peggiore {100 * min(acc_fatt):.1f}%)")
P(f"  errore sul costo nei progetti fattibili ({len(err_costo)}): mediana {100 * st.median(err_costo):.1f}%, 90° percentile {100 * q(err_costo, 90):.1f}%, 95° {100 * q(err_costo, 95):.1f}%")
er = [abs(x["errore_rete_costo_pct"]) for x in righe]
P(f"  nel progetto proposto: |errore| della rete sul costo mediana {st.median(er):.1f}%, 90° percentile {q(er, 90):.1f}%, massimo {max(er):.1f}%"
  f" (per questo il costo finale viene sempre dal simulatore)")
P("")
tg = [x["tempo_griglia_cpu_s"] for x in righe]
P("TEMPI (Mac M4, 8 core)")
P(f"  griglia fitta simulata: 57,5 min per le 146 linee (23,6 s per linea); somma dei tempi dei singoli progetti {sum(tg) / 3600:.1f} h")
P(f"  surrogato: ~0,2 s per linea, 146 linee in 29 s + 5 s di avvio; {st.mean(x['simulazioni_surrogato'] for x in righe):.0f} simulazioni per linea invece di 9702")
open(os.path.join(OUT, "riassunto.txt"), "w").write("\n".join(out) + "\n")
print("\n".join(out))
