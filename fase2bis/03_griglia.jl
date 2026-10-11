# Fase 2bis, passo 3: conferma delle migliorie. Per ogni tratta il cui candidato v2 migliora la v1 di oltre lo 0,1%:
#   (1) griglia locale a passo 0,0005, ±0,02 in m e in n attorno al nuovo ottimo (m ≥ 0,03 se ibrido; m = 0 fisso se
#       sola batteria; 0 < n ≤ 1). Se il miglior punto fattibile della griglia è più economico del centro e sta sul
#       bordo della finestra, la griglia si ricentra lì e si ripete (al massimo 10 giri): l'ottimo può essere oltre;
#   (2) per le ibride il cui ottimo finale è vicino a D20 (|m* − 0,1195| < 0,01): larghezza in m dell'isola fattibile a
#       n = n* fisso, con una scansione a passo 0,0001 su m* ± 0,05 (tratto contiguo di punti fattibili che contiene m*).
#
# Uso, da ml_treno/fase2bis (dopo 02_candidati.jl):   julia -t 8 --project=. 03_griglia.jl
# Punti valutati in PUNTI/<tratta>_{griglia,isola}.csv (fuori da Google Drive); riassunto in risultati/griglia_v2.csv.

using CSV, DataFrames, Printf, Statistics
include(joinpath(@__DIR__, "simulatore.jl"))
const PUNTI = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis/griglia"
mkpath(PUNTI)
const D20 = 0.1195
cand = CSV.read(joinpath(@__DIR__, "risultati", "candidati_v2.csv"), DataFrame)
sel = cand[cand.miglioramento_pct .> 0.1, :]
println("tratte da confermare: ", nrow(sel))

griglia(m, n) = [(mm, nn) for mm in (m == 0 ? [0.0] : [m + 0.0005k for k in -40:40 if m + 0.0005k >= 0.03 - 1e-12])
                           for nn in [n + 0.0005k for k in -40:40 if 0 < n + 0.0005k <= 1]]
centro = Dict(r.tratta => (r.m, r.n, r.costo) for r in eachrow(sel))
giri = Dict(r.tratta => 0 for r in eachrow(sel))
punti = Dict(r.tratta => DataFrame() for r in eachrow(sel))
attive = collect(sel.tratta)
t0 = time()
while !isempty(attive)
    lista = [(t, p...) for t in attive for p in griglia(centro[t][1], centro[t][2])]
    es = hcat(DataFrame(tratta = getindex.(lista, 1), m = getindex.(lista, 2), n = getindex.(lista, 3)),
              valuta_punti(getindex.(lista, 1), getindex.(lista, 2), getindex.(lista, 3)))
    ancora = String[]
    for t in attive
        giri[t] += 1
        g = es[es.tratta .== t, :]; g.giro .= giri[t]; append!(punti[t], g)
        f = g.fattibile; any(f) || continue
        i = findall(f)[argmin(g.costo[f])]
        m0, n0, c0 = centro[t]
        if g.costo[i] < c0
            centro[t] = (g.m[i], g.n[i], g.costo[i])
            bordo = (m0 > 0 && abs(abs(g.m[i] - m0) - 0.02) < 1e-9) || abs(abs(g.n[i] - n0) - 0.02) < 1e-9
            bordo && giri[t] < 10 && push!(ancora, t)
        end
    end
    @printf("giro: %d tratte, %d punti, %.0f s\n", length(attive), length(lista), time() - t0)
    global attive = ancora
end

# isola attorno a D20, sull'ottimo finale
li = [(t, centro[t][1] + 0.0001k, centro[t][2]) for t in sel.tratta if centro[t][1] > 0 && abs(centro[t][1] - D20) < 0.01
      for k in -500:500 if centro[t][1] + 0.0001k >= 0.03 - 1e-12]
isole = hcat(DataFrame(tratta = getindex.(li, 1), m = getindex.(li, 2), n = getindex.(li, 3)),
             valuta_punti(getindex.(li, 1), getindex.(li, 2), getindex.(li, 3)))
@printf("griglie e isole valutate in %.0f s\n", time() - t0)

res = DataFrame()
for r in eachrow(sel)
    g = punti[r.tratta]
    CSV.write(joinpath(PUNTI, "$(r.tratta)_griglia.csv"), g)
    mg, ng, cg = centro[r.tratta]
    cg == r.costo && (mg = NaN; ng = NaN; cg = Inf)       # la griglia non ha trovato di meglio
    riga = (tratta = r.tratta, provenienza = r.provenienza, m = r.m, n = r.n, costo = r.costo, miglioramento_pct = r.miglioramento_pct,
            giri = giri[r.tratta], punti_griglia = nrow(g), fattibili_griglia = count(g.fattibile), m_griglia = mg, n_griglia = ng,
            costo_griglia = cg, griglia_meglio_pct = isinf(cg) ? 0.0 : 100 * (r.costo - cg) / r.costo,
            isola_m = NaN, isola_n = NaN, isola_m_sinistra = NaN, isola_m_destra = NaN, isola_larghezza = NaN, isola_punti = 0)
    s = sort(isole[isole.tratta .== r.tratta, :], :m)
    if nrow(s) > 0
        CSV.write(joinpath(PUNTI, "$(r.tratta)_isola.csv"), s)
        m0 = centro[r.tratta][1]; j0 = argmin(abs.(s.m .- m0))
        if s.fattibile[j0]
            a = j0; while a > 1 && s.fattibile[a-1]; a -= 1; end
            b = j0; while b < nrow(s) && s.fattibile[b+1]; b += 1; end
            riga = merge(riga, (isola_m = m0, isola_n = centro[r.tratta][2], isola_m_sinistra = s.m[a], isola_m_destra = s.m[b],
                                isola_larghezza = s.m[b] - s.m[a] + 0.0001, isola_punti = b - a + 1))
        end
    end
    push!(res, riga)
end
CSV.write(joinpath(@__DIR__, "risultati", "griglia_v2.csv"), res)
@printf("griglia meglio del candidato in %d tratte su %d; massimo %.4f%%; mediana %.4f%%; più di un giro: %d\n",
        count(>(1e-10), res.griglia_meglio_pct), nrow(res), maximum(res.griglia_meglio_pct), median(res.griglia_meglio_pct), count(>(1), res.giri))
for r in eachrow(res)
    @printf("  %s %-6s m %.4f n %.4f  +%.3f%% su v1 | griglia: %d giri, %4d/%5d fattibili, %+.4f%%%s | isola: %s\n", r.tratta, r.provenienza, r.m, r.n,
            r.miglioramento_pct, r.giri, r.fattibili_griglia, r.punti_griglia, r.griglia_meglio_pct,
            isnan(r.m_griglia) ? "" : @sprintf(" in m %.4f n %.4f", r.m_griglia, r.n_griglia),
            isnan(r.isola_larghezza) ? "—" : @sprintf("a n %.4f m %.4f–%.4f, larghezza %.4f", r.isola_n, r.isola_m_sinistra, r.isola_m_destra, r.isola_larghezza))
end
