# Fase 2bis, controllo in più (non cambia la v2): la procedura della v2 fa la griglia locale solo dove il candidato
# migliora la v1 di oltre lo 0,1%. Per stimare quanto la v2 sia ancora migliorabile nelle ALTRE tratte, stessa griglia
# (passo 0,0005, ±0,02, ricentrata se il migliore sta sul bordo, al massimo 10 giri) su 30 tratte estratte a caso
# (seme 20261011) tra le 989 non confermate con la griglia.
# Uso, da ml_treno/fase2bis:   julia -t 8 --project=. 12_controllo_campione.jl. Scrive risultati/controllo_campione.csv.
using CSV, DataFrames, Printf, Statistics, Random
include(joinpath(@__DIR__, "simulatore.jl"))
o = CSV.read(joinpath(@__DIR__, "dati", "ottimi_riferimento_v2.csv"), DataFrame)
g = CSV.read(joinpath(@__DIR__, "risultati", "griglia_v2.csv"), DataFrame)
pool = sort(setdiff(o.tratta, g.tratta))
camp = sort(shuffle(MersenneTwister(20261011), pool)[1:30])
griglia(m, n) = [(mm, nn) for mm in (m == 0 ? [0.0] : [m + 0.0005k for k in -40:40 if m + 0.0005k >= 0.03 - 1e-12])
                           for nn in [n + 0.0005k for k in -40:40 if 0 < n + 0.0005k <= 1]]
R = Dict(r.tratta => r for r in eachrow(o))
centro = Dict(t => (R[t].m_star, R[t].n_star, R[t].costo_star) for t in camp); giri = Dict(t => 0 for t in camp)
attive = copy(camp); t0 = time()
while !isempty(attive)
    lista = [(t, p...) for t in attive for p in griglia(centro[t][1], centro[t][2])]
    es = hcat(DataFrame(tratta = getindex.(lista, 1), m = getindex.(lista, 2), n = getindex.(lista, 3)),
              valuta_punti(getindex.(lista, 1), getindex.(lista, 2), getindex.(lista, 3)))
    ancora = String[]
    for t in attive
        giri[t] += 1; s = es[(es.tratta .== t) .& es.fattibile, :]; nrow(s) == 0 && continue
        i = argmin(s.costo); m0, n0, c0 = centro[t]
        if s.costo[i] < c0
            centro[t] = (s.m[i], s.n[i], s.costo[i])
            ((m0 > 0 && abs(abs(s.m[i] - m0) - 0.02) < 1e-9) || abs(abs(s.n[i] - n0) - 0.02) < 1e-9) && giri[t] < 10 && push!(ancora, t)
        end
    end
    global attive = ancora
end
res = DataFrame(tratta = camp, regime = [R[t].regime for t in camp], m = [R[t].m_star for t in camp], n = [R[t].n_star for t in camp],
                costo_v2 = [R[t].costo_star for t in camp], giri = [giri[t] for t in camp], m_griglia = [centro[t][1] for t in camp],
                n_griglia = [centro[t][2] for t in camp], costo_griglia = [centro[t][3] for t in camp])
res.griglia_meglio_pct = 100 .* (res.costo_v2 .- res.costo_griglia) ./ res.costo_v2
CSV.write(joinpath(@__DIR__, "risultati", "controllo_campione.csv"), res)
@printf("%.0f s. Griglia meglio della v2 in %d/30 tratte; > 0,1%%: %d; > 1%%: %d; massimo %.3f%%; mediana %.4f%%\n", time() - t0,
        count(>(1e-10), res.griglia_meglio_pct), count(>(0.1), res.griglia_meglio_pct), count(>(1), res.griglia_meglio_pct),
        maximum(res.griglia_meglio_pct), median(res.griglia_meglio_pct))
for r in eachrow(res); @printf("  %s %-13s m %.4f n %.4f  %+.4f%% (%d giri)\n", r.tratta, r.regime, r.m, r.n, r.griglia_meglio_pct, r.giri); end
