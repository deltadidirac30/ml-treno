# Fase 1 f (seconda parte): verità del test finale sulle 5 tratte reali in andata e ritorno.
#
# Le due ottimizzazioni sono state fatte con il runner di train-powertrain (comandi in 03_tratte_reali.sh), con
# uscita fuori dal repo e da Google Drive, in /Users/kairos/Documents/lavoro/ml_treno_dati/:
#   2026-10-10_ottimizza_corretta_ar_reali        ottimizzatore vecchio (attuale, default del runner)
#   2026-10-10_ottimizza_nomad_corretta_ar_reali  NOMAD-PB
# Qui: si rivalutano i due ottimi e quello della forza bruta (06_forza_bruta.jl, se già fatto), si prende il
# migliore e si estraggono le uscite come per le DoE. Colonna `semplificata`: Calabria (profilo dei tesisti).
#
# Uso, da ml_treno/fase1:   julia --project=. 03_tratte_reali.jl
# Scrive in dati/: ottimi_reali.csv, uscite_reali.csv, controlli_reali.txt.

using CSV, DataFrames, Printf
include(joinpath(@__DIR__, "uscite.jl"))

const TP   = "/Users/kairos/Documents/lavoro/train-powertrain"
const FUORI = "/Users/kairos/Documents/lavoro/ml_treno_dati"
const CV = joinpath(FUORI, "2026-10-10_ottimizza_corretta_ar_reali")
const CN = joinpath(FUORI, "2026-10-10_ottimizza_nomad_corretta_ar_reali")
const DATI = joinpath(@__DIR__, "dati")
out = open(joinpath(DATI, "controlli_reali.txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))

# stessa configurazione del modello delle campagne DoE (parte di config.txt prima delle opzioni dell'ottimizzatore)
modello_di(c) = split(read(joinpath(c, "config.txt"), String), " modalita=")[1]
ref = modello_di(joinpath(TP, "campagne", "2026-10-08_ottimizza_ar_1024tratte"))
for c in (CV, CN)
    modello_di(c) == ref || error("$c: configurazione del modello diversa dalle campagne DoE")
end
say("configurazione del modello identica alle campagne DoE: ", ref)

leggi(c) = CSV.read(joinpath(c, "ottimi.csv"), DataFrame; types = Dict(:m => Float64, :n => Float64, :costo => Float64))
ov, on = leggi(CV), leggi(CN)
reali = Dict(t.id => t for t in TrainPowertrain.Campagna.leggi_tratte_reali(; cartella = joinpath(TP, "tratte_reali")))
rel(a, b) = abs(a - b) / abs(b)
# forza bruta (06_forza_bruta.jl), se c'è: terzo candidato. Firenze-BRoute è identica a Firenze e usa il suo punto.
fb = isfile(joinpath(DATI, "forza_bruta_reali.csv")) ? CSV.read(joinpath(DATI, "forza_bruta_reali.csv"), DataFrame) : nothing
fb === nothing && say("forza_bruta_reali.csv assente: verità = migliore dei due ottimizzatori")
# Calabria: profilo semplificato dei tesisti (quota tutta a zero, limite unico a 130 km/h); risultati sempre a parte
const SEMPLIFICATE = ["Calabria"]
ott = DataFrame(); usc = DataFrame()
for r in eachrow(on)
    v = ov[findfirst(==(r.tratta), ov.tratta), :]
    cp = reali[r.tratta].cp
    eN, trN = valuta(cp, r.m, r.n); eV, trV = valuta(cp, v.m, v.n)
    for (nome, e, c) in (("NOMAD", eN, r.costo), ("vecchio", eV, v.costo))
        say(@sprintf("  %-18s %-11s rivalutato %.17g campagna %.17g rel %.2e %s", r.tratta, nome, e.costo, c, rel(e.costo, c), e.stato))
        rel(e.costo, c) <= 1e-9 || error("costo rivalutato diverso")
    end
    cand = [("nomad_pb", eN, trN), ("vecchio", eV, trV)]
    due = min(eN.costo, eV.costo)
    mF, nF, cF = NaN, NaN, NaN
    if fb !== nothing
        idf = r.tratta == "Firenze-BRoute" ? "Firenze" : r.tratta
        x = fb[findfirst(==(idf), fb.tratta), :]
        eF, trF = valuta(cp, x.m, x.n)
        mF, nF, cF = x.m, x.n, eF.costo
        r.tratta == idf && (rel(eF.costo, x.costo) <= 1e-9 || error("forza bruta: costo rivalutato diverso"))
        say(@sprintf("  %-18s %-11s rivalutato %.17g (forza bruta %.17g) %s", r.tratta, "forza_bruta", eF.costo, x.costo, eF.stato))
        eF.stato === :completed && eF.penalita == 0 && push!(cand, ("forza_bruta", eF, trF))
    end
    k = argmin([c[2].costo for c in cand])          # a pari costo vince il primo: nomad_pb, vecchio, forza_bruta
    prov, e, tr = cand[k]
    best = e.costo
    count(c -> c[2].costo == best, cand) > 1 && (prov = join([c[1] for c in cand if c[2].costo == best], "="))
    push!(ott, (tratta = r.tratta, semplificata = r.tratta in SEMPLIFICATE, provenienza = prov,
                m_nomad = r.m, n_nomad = r.n, costo_nomad = eN.costo,
                m_vecchio = v.m, n_vecchio = v.n, costo_vecchio = eV.costo,
                m_forza_bruta = mF, n_forza_bruta = nF, costo_forza_bruta = cF,
                costo_migliore_due_ottimizzatori = due,
                m_star = e.diagnostica.cost_details["m"], n_star = e.diagnostica.cost_details["n"], costo_star = best,
                guadagno_forza_bruta_pct = 100 * (due - best) / due,
                scarto_nomad_pct = 100 * (eN.costo - best) / best, scarto_vecchio_pct = 100 * (eV.costo - best) / best,
                valutazioni_nomad = r.valutazioni, valutazioni_vecchio = v.valutazioni))
    g = grandezze(e, tr, cp)
    c, _ = costo_ricostruito(Dict(g))
    say(@sprintf("  %-18s costo ricostruito dalle grandezze: rel %.2e", r.tratta, rel(c, e.costo)))
    push!(usc, merge((tratta = r.tratta, provenienza = prov, semplificata = r.tratta in SEMPLIFICATE),
                     NamedTuple(Symbol(k) => x for (k, x) in g)))
end
say("\n", ott[:, [:tratta, :semplificata, :provenienza, :m_star, :n_star, :costo_star, :guadagno_forza_bruta_pct, :scarto_nomad_pct, :scarto_vecchio_pct]])
CSV.write(joinpath(DATI, "ottimi_reali.csv"), ott)
CSV.write(joinpath(DATI, "uscite_reali.csv"), usc)
close(out)
