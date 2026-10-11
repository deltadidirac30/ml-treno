# Fase 1 c-d: ottimo di riferimento di ogni tratta (il migliore tra le due campagne) e grandezze di uscita
# dalla rivalutazione del simulatore nell'ottimo.
#
# Uso, da ml_treno/fase1:   julia -t 8 --project=. 01_ottimi_e_uscite.jl
#
# Fonti (repo train-powertrain, solo lettura, commit c47dc17; valutatore identico a 048c268):
#   NOMAD-PB  campagne/2026-10-08_ottimizza_ar_1024tratte/ottimi.csv (config.txt: ottimizzatore=nomad_pb;
#             comando.txt la chiama 2026-10-08_ottimizza_nomad_corretta_ar_1024tratte: la cartella è stata
#             rinominata). m, n, costo a 17 cifre.
#   vecchio   la cartella campagne/2026-10-08_ottimizza_corretta_ar_1024tratte non c'è più; i suoi ottimi sono
#             in analisi/2026-10-08_confronto_campagne_f/confronto_ottimi.csv, colonne m_N, n_N, costo_N
#             (NUOVA = f 0.5169…), A 12 CIFRE.
# Entrambi gli ottimi si rivalutano; il riferimento è quello di costo rivalutato minore (a pari costo NOMAD-PB).
#
# Scrive in dati/: ottimi_riferimento.csv (c), uscite_doe.csv (d), controlli_uscite.txt.

using CSV, DataFrames, Printf
include(joinpath(@__DIR__, "uscite.jl"))

const TP     = "/Users/kairos/Documents/lavoro/train-powertrain"
const NOMAD  = joinpath(TP, "campagne", "2026-10-08_ottimizza_ar_1024tratte")
const VECCHIO_CSV = joinpath(TP, "analisi", "2026-10-08_confronto_campagne_f", "confronto_ottimi.csv")
const DATI   = joinpath(@__DIR__, "dati")
mkpath(DATI)

out = open(joinpath(DATI, "controlli_uscite.txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))

# configurazione: deve coincidere con config.txt della campagna NOMAD (parte del modello)
cfgtxt = read(joinpath(NOMAD, "config.txt"), String)
say("config.txt NOMAD: ", strip(cfgtxt)[1:400], " …")
say("ConfigModello usata: ", CONFIG)
for (k, v) in [("modello", "corretta"), ("f_degrado_fc", "0.51692531382982454"), ("ore_max_fc", "25000"),
               ("m_min_fc", "0.029999999999999999"), ("soglia_fine_orizzonte", "1"), ("peso_a_carico", "195000")]
    occursin("$k=$v", cfgtxt) || error("config.txt: $k=$v non trovato")
end
CONFIG.f_degrado_fc == 0.51692531382982454 || error("f diverso")

on = CSV.read(joinpath(NOMAD, "ottimi.csv"), DataFrame; types = Dict(:m => Float64, :n => Float64, :costo => Float64))
ov = CSV.read(VECCHIO_CSV, DataFrame)[:, [:tratta, :m_N, :n_N, :costo_N]]
all(on.esito .== "fattibile") || error("ottimi NOMAD non tutti fattibili")
d = innerjoin(on[:, [:tratta, :m, :n, :costo]], ov, on = :tratta)
nrow(d) == 1024 || error("tratte: $(nrow(d))")
sort!(d, :tratta)

tratte = Dict(t.id => t for t in leggi_tratte_materializzate(joinpath(TP, "tratte_doe_matlab")))   # controlla le impronte
length(tratte) == 1024 || error("tratte lette: $(length(tratte))")

N = nrow(d)
ris = Vector{Any}(undef, N)
t0 = time()
Threads.@threads :dynamic for k in 1:N
    r = d[k, :]
    cp = tratte[r.tratta].cp
    pre = PrecalcoloTratta(cp, DIREZIONE)
    eN, trN = valuta(cp, r.m, r.n; pre)
    eV, trV = valuta(cp, r.m_N, r.n_N; pre)
    ris[k] = (eN = eN, trN = trN, eV = eV, trV = trV)
end
say(@sprintf("2048 valutazioni in %.1f s con %d thread", time() - t0, Threads.nthreads()))

rel(a, b) = abs(a - b) / abs(b)
righe_ott = DataFrame()
righe_usc = DataFrame()
viol = String[]
for k in 1:N
    r = d[k, :]; x = ris[k]
    cN, cV = x.eN.costo, x.eV.costo
    rN, rV = rel(cN, r.costo), rel(cV, r.costo_N)
    rN <= 1e-9 || push!(viol, @sprintf("%s NOMAD: rivalutato %.17g campagna %.17g rel %.3e", r.tratta, cN, r.costo, rN))
    rV <= 1e-9 || push!(viol, @sprintf("%s vecchio: rivalutato %.17g campagna(12 cifre) %.17g rel %.3e", r.tratta, cV, r.costo_N, rV))
    nomad_meglio = cN <= cV
    prov = cN == cV ? "pari" : (nomad_meglio ? "nomad_pb" : "vecchio")
    e, tr = nomad_meglio ? (x.eN, x.trN) : (x.eV, x.trV)
    best = min(cN, cV)
    push!(righe_ott, (tratta = r.tratta, provenienza = prov,
                      m_nomad = x.eN.diagnostica.cost_details["m"], n_nomad = r.n, costo_nomad_campagna = r.costo, costo_nomad_rivalutato = cN,
                      m_vecchio = x.eV.diagnostica.cost_details["m"], n_vecchio = r.n_N, costo_vecchio_campagna_12cifre = r.costo_N, costo_vecchio_rivalutato = cV,
                      m_star = e.diagnostica.cost_details["m"], n_star = e.diagnostica.cost_details["n"], costo_star = best,
                      scarto_altro_pct = 100 * (max(cN, cV) - best) / best,
                      regime_nomad = x.eN.diagnostica.cost_details["m"] == 0 ? "sola_batteria" : "ibrido",
                      regime_vecchio = x.eV.diagnostica.cost_details["m"] == 0 ? "sola_batteria" : "ibrido"))
    g = grandezze(e, tr, tratte[r.tratta].cp)
    push!(righe_usc, merge((tratta = r.tratta, provenienza = prov), NamedTuple(Symbol(k) => v for (k, v) in g)))
end

say("\n[c] ottimi di riferimento")
say("  provenienza: ", Dict(p => count(==(p), righe_ott.provenienza) for p in unique(righe_ott.provenienza)))
s = righe_ott.scarto_altro_pct
say("  NOMAD meglio del vecchio di oltre lo 0,1%: ", count(i -> righe_ott.provenienza[i] == "nomad_pb" && s[i] > 0.1, 1:N),
    "; peggio di oltre lo 0,1%: ", count(i -> righe_ott.provenienza[i] == "vecchio" && s[i] > 0.1, 1:N))
say("  regime del riferimento: ", Dict(g => count(==(g), righe_usc.regime) for g in unique(righe_usc.regime)))
say("  cambi di regime tra le due campagne: ", count(righe_ott.regime_nomad .!= righe_ott.regime_vecchio))

say("\n[d] verifica del costo rivalutato contro le campagne (soglia 1e-9 relativo)")
say("  violazioni: ", length(viol)); foreach(v -> say("    ", v), viol)
rn = [rel(x.eN.costo, d.costo[k]) for (k, x) in enumerate(ris)]
rv = [rel(x.eV.costo, d.costo_N[k]) for (k, x) in enumerate(ris)]
say(@sprintf("  NOMAD: scarto relativo massimo %.3e (uguali al bit: %d/1024)", maximum(rn), count(==(0.0), rn)))
say(@sprintf("  vecchio (costo di campagna a 12 cifre, punto a 12 cifre): scarto relativo massimo %.3e", maximum(rv)))
say("  stato nell'ottimo: ", unique(righe_usc.stato), "  penalità: ", unique(righe_usc.penalita))

# costo dalle sole grandezze estratte
rc = Float64[]; dsost = 0
for r in eachrow(righe_usc)
    g = Dict(String(k) => r[k] for k in propertynames(r))
    c, v = costo_ricostruito(g)
    push!(rc, rel(c, r.costo_EUR_km))
    (v["n_sost_FC"] != r.n_sost_FC || v["n_sost_batt"] != r.n_sost_batt) && (global dsost += 1)
end
say(@sprintf("  costo ricostruito dalle grandezze: scarto relativo massimo %.3e; sostituzioni diverse: %d", maximum(rc), dsost))
say(@sprintf("  somma delle voci contro il costo: scarto relativo massimo %.3e",
             maximum(rel.(righe_usc.somma_voci_EUR_km, righe_usc.costo_EUR_km))))
say("  D15: coda simulata ", count(==(1.0), righe_usc.D15_coda_simulata), ", fattibile ", count(==(1.0), righe_usc.D15_coda_fattibile),
    ", sostituzione saltata ", count(==(1.0), righe_usc.D15_sost_saltata))
say("  vita FC al tetto di 25000 h: ", count(==(1.0), righe_usc.vita_FC_tetto))

CSV.write(joinpath(DATI, "ottimi_riferimento.csv"), righe_ott)
CSV.write(joinpath(DATI, "uscite_doe.csv"), righe_usc)
close(out)
