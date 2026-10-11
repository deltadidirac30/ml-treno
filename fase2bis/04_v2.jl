# Fase 2bis, passo 4: riferimento v2, rivalutazione con i controlli della fase 1 e dataset v2.
# v2 = candidato di 02_candidati.jl; se la griglia locale di 03_griglia.jl trova un punto fattibile più economico,
# quello (provenienza "griglia_locale"). Ogni punto v2 si rivaluta con fase1/uscite.jl (valuta + grandezze): stato
# completed, penalità 0, costo uguale al candidato (1e-9 relativo), costo ricostruito dalle grandezze, somma delle voci.
# Il riferimento congelato v1 (fase1/dati/ottimi_riferimento.csv) e il dataset v1 non si toccano.
#
# Uso, da ml_treno/fase2bis (dopo 03_griglia.jl):   julia -t 8 --project=. 04_v2.jl
# Scrive dati/ottimi_riferimento_v2.csv, dati/uscite_doe_v2.csv, dati/dataset_doe_v2.csv (stessi x_ del dataset di
# lavoro v1, uscite y_ e controlli c_ nell'ottimo v2) e risultati/controlli_v2.txt.

using CSV, DataFrames, Printf, Statistics
include(joinpath(@__DIR__, "..", "fase1", "uscite.jl"))
const TP = "/Users/kairos/Documents/lavoro/train-powertrain"
const DATI = joinpath(@__DIR__, "dati")
const D20 = 0.1195
cand = CSV.read(joinpath(@__DIR__, "risultati", "candidati_v2.csv"), DataFrame)
gr   = CSV.read(joinpath(@__DIR__, "risultati", "griglia_v2.csv"), DataFrame)
v1d  = CSV.read(joinpath(@__DIR__, "..", "fase1", "dati", "dataset_doe.csv"), DataFrame)
out = open(joinpath(@__DIR__, "risultati", "controlli_v2.txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))

v2 = select(cand, :tratta, :provenienza, :m, :n, :costo, :costo_v1, :m_v1, :n_v1, :provenienza_v1, :costo_senza_fase2,
            :provenienza_senza_fase2)
G = Dict(r.tratta => r for r in eachrow(gr))
for r in eachrow(v2)
    g = get(G, r.tratta, nothing)
    g !== nothing && g.costo_griglia < r.costo && (r.provenienza = "griglia_locale"; r.m = g.m_griglia; r.n = g.n_griglia; r.costo = g.costo_griglia)
end

tratte = Dict(t.id => t for t in leggi_tratte_materializzate(joinpath(TP, "tratte_doe_matlab")))
N = nrow(v2); ris = Vector{Any}(undef, N)
t0 = time()
Threads.@threads :dynamic for k in 1:N
    cp = tratte[v2.tratta[k]].cp
    ris[k] = valuta(cp, v2.m[k], v2.n[k]; pre = PrecalcoloTratta(cp, DIREZIONE))
end
say(@sprintf("rivalutazione dei 1024 punti v2 in %.0f s", time() - t0))

rel(a, b) = abs(a - b) / abs(b)
usc = DataFrame(); viol = String[]; rc = Float64[]; dsost = 0
for k in 1:N
    e, tr = ris[k]; r = v2[k, :]
    rel(e.costo, r.costo) <= 1e-9 || push!(viol, @sprintf("%s: rivalutato %.17g candidato %.17g (%s)", r.tratta, e.costo, r.costo, r.provenienza))
    (e.stato === :completed && e.penalita == 0) || push!(viol, "$(r.tratta): stato $(e.stato) penalità $(e.penalita)")
    g = grandezze(e, tr, tratte[r.tratta].cp)
    nt = merge((tratta = r.tratta, provenienza = r.provenienza), NamedTuple(Symbol(a) => b for (a, b) in g))
    push!(usc, nt)
    c, v = costo_ricostruito(Dict(String(a) => b for (a, b) in pairs(nt)))
    push!(rc, rel(c, nt.costo_EUR_km))
    (v["n_sost_FC"] != nt.n_sost_FC || v["n_sost_batt"] != nt.n_sost_batt) && (global dsost += 1)
end
say("violazioni (costo diverso dal candidato, stato o penalità): ", length(viol)); foreach(v -> say("  ", v), viol)
say("stato: ", unique(usc.stato), "  penalità: ", unique(usc.penalita))
say(@sprintf("costo ricostruito dalle grandezze: scarto relativo massimo %.3e; sostituzioni diverse: %d", maximum(rc), dsost))
say(@sprintf("somma delle voci contro il costo: scarto relativo massimo %.3e", maximum(rel.(usc.somma_voci_EUR_km, usc.costo_EUR_km))))

# riferimento v2
ott = DataFrame(tratta = v2.tratta, provenienza = v2.provenienza, m_star = usc.m_star, n_star = usc.n_star, costo_star = usc.costo_EUR_km,
                regime = usc.regime, m_v1 = v2.m_v1, n_v1 = v2.n_v1, costo_v1 = v2.costo_v1, provenienza_v1 = v2.provenienza_v1,
                regime_v1 = ifelse.(v2.m_v1 .== 0, "sola_batteria", "ibrido"),
                miglioramento_pct = 100 .* (v2.costo_v1 .- usc.costo_EUR_km) ./ v2.costo_v1,
                provenienza_senza_fase2 = v2.provenienza_senza_fase2,
                miglioramento_senza_fase2_pct = 100 .* (v2.costo_v1 .- v2.costo_senza_fase2) ./ v2.costo_v1)
CSV.write(joinpath(DATI, "ottimi_riferimento_v2.csv"), ott)
CSV.write(joinpath(DATI, "uscite_doe_v2.csv"), usc)

# dataset v2: stessi x_ del dataset di lavoro v1; uscite e controlli dall'ottimo v2
usc.tratta == v1d.tratta || error("ordine delle tratte")
d2 = select(v1d, :tratta, :semplificata, [c for c in names(v1d) if startswith(c, "x_")])
insertcols!(d2, 2, :provenienza => usc.provenienza)
for c in names(v1d)
    (startswith(c, "y_") || startswith(c, "c_")) || continue
    n = c[3:end]
    d2[!, c] = n == "ibrido" ? Int.(usc.regime .== "ibrido") : usc[!, n]
end
names(d2) == names(v1d) || error("colonne diverse dal dataset v1")
CSV.write(joinpath(DATI, "dataset_doe_v2.csv"), d2)

# riassunto
m = ott.miglioramento_pct; ms = ott.miglioramento_senza_fase2_pct
say("\ntratte che cambiano (v2 contro v1): ", count(>(1e-10), m), "; > 0,1%: ", count(>(0.1), m), "; > 1%: ", count(>(1), m),
    "; > 5%: ", count(>(5), m), @sprintf("; massimo %.2f%% (%s)", maximum(m), ott.tratta[argmax(m)]))
say("senza i punti della fase 2 (v1 + P1–P4): ", count(>(1e-10), ms), "; > 0,1%: ", count(>(0.1), ms), "; > 1%: ", count(>(1), ms),
    "; > 5%: ", count(>(5), ms), @sprintf("; massimo %.2f%%", maximum(ms)))
say("provenienza v2: ", sort(collect(Dict(p => count(==(p), ott.provenienza) for p in unique(ott.provenienza)))))
for s in (0.1, 1.0)
    k = m .> s
    say("provenienza delle tratte migliorate di oltre lo $(s == 0.1 ? "0,1" : "1")%: ", sort(collect(Dict(p => count(==(p), ott.provenienza[k]) for p in unique(ott.provenienza[k])))))
end
cambi = ott[ott.regime .!= ott.regime_v1, :]
say("cambi di regime: ", nrow(cambi), " (ibrido → sola batteria ", count(cambi.regime .== "sola_batteria"), ", sola batteria → ibrido ",
    count(cambi.regime .== "ibrido"), ")")
for r in eachrow(cambi)
    say(@sprintf("  %s %s → %s: m %.4f → %.4f, n %.4f → %.4f, %.3f%% (%s)", r.tratta, r.regime_v1, r.regime, r.m_v1, r.m_star, r.n_v1, r.n_star,
                 r.miglioramento_pct, r.provenienza))
end
dove(m) = m == 0 ? "sola batteria" : m < 0.04 ? "vicino a m_min (0,03 ≤ m < 0,04)" : abs(m - D20) < 0.01 ? (m < D20 ? "a sinistra di D20 (entro 0,01)" : "a destra di D20 (entro 0,01)") : "altrove"
for s in (0.1, 1.0)
    k = findall(m .> s)
    say("posizione del nuovo ottimo nelle tratte migliorate di oltre lo $(s == 0.1 ? "0,1" : "1")%:")
    for p in unique(dove.(ott.m_star[k])); say("  ", p, ": ", count(==(p), dove.(ott.m_star[k]))); end
end
say("\ntratte migliorate di oltre lo 0,1% (ordinate):")
for r in eachrow(sort(ott[m .> 0.1, :], :miglioramento_pct, rev = true))
    say(@sprintf("  %s %6.3f%% %-14s v1 (%s) m %.4f n %.4f → v2 m %.4f n %.4f [%s]", r.tratta, r.miglioramento_pct, r.provenienza, r.regime_v1,
                 r.m_v1, r.n_v1, r.m_star, r.n_star, dove(r.m_star)))
end
close(out)
