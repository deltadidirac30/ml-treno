# Fase 2bis, passo 2: candidati al riferimento v2. Per ogni tratta il miglior punto fattibile di ogni fonte:
#   v1_nomad, v1_vecchio   le due campagne del riferimento congelato v1 (fase1/dati/ottimi_riferimento.csv, rivalutate)
#   P1..P4                 le partenze sistematiche di 01_partenze.jl (tutte le valutazioni fattibili dei lanci)
#   fase2                  tutti i punti fattibili valutati in fase 2: previsioni secche (fase2/risultati/sim_cv.csv) e
#                          rifiniture (fase2/risultati/rifinitura_p69.csv)
# Il candidato v2 è il costo minimo; a pari costo vince la fonte che viene prima nell'elenco (v1 prima di tutto).
# Si calcola anche la variante "senza fase 2" (v1 e P1–P4 soltanto), per contare le migliorie trovate dalle sole
# partenze sistematiche. Il riferimento v1 non cambia.
#
# Uso, da ml_treno/fase2bis (dopo 01_partenze.jl):   julia --project=. 02_candidati.jl
# Scrive risultati/candidati_v2.csv (una riga per tratta: miglior costo e punto di ogni fonte, scelta v2 e senza fase 2).

using CSV, DataFrames, Printf
const STORIE = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis/partenze"
const FONTI = ["v1_nomad", "v1_vecchio", "P1", "P2", "P3", "P4", "fase2"]
v1  = CSV.read(joinpath(@__DIR__, "..", "fase1", "dati", "ottimi_riferimento.csv"), DataFrame)
sim = CSV.read(joinpath(@__DIR__, "..", "fase2", "risultati", "sim_cv.csv"), DataFrame)
rif = CSV.read(joinpath(@__DIR__, "..", "fase2", "risultati", "rifinitura_p69.csv"), DataFrame)

best = Dict{Tuple{String,String},Tuple{Float64,Float64,Float64}}()      # (tratta, fonte) => (costo, m, n)
proponi!(t, fonte, c, m, n) = (c < get(best, (t, fonte), (Inf,))[1]) && (best[(t, fonte)] = (c, m, n))
for r in eachrow(v1)
    proponi!(r.tratta, "v1_nomad", r.costo_nomad_rivalutato, r.m_nomad, r.n_nomad)
    proponi!(r.tratta, "v1_vecchio", r.costo_vecchio_rivalutato, r.m_vecchio, r.n_vecchio)
    st = CSV.read(joinpath(STORIE, "$(r.tratta).csv"), DataFrame)
    for s in eachrow(st)
        s.tipo == "fattibile" && proponi!(r.tratta, s.partenza, s.costo, s.m, s.n)
    end
end
for s in eachrow(sim); s.fattibile && proponi!(s.tratta, "fase2", s.costo, s.m, s.n); end
for s in eachrow(rif); s.fattibile && proponi!(s.tratta, "fase2", s.costo, s.m, s.n); end

function scelta(t, fonti)
    b = (Inf, NaN, NaN); f = ""
    for x in fonti
        c = get(best, (t, x), (Inf, NaN, NaN))
        c[1] < b[1] && (b = c; f = x)          # stretto: a pari costo resta la fonte precedente
    end
    return f, b
end
out = DataFrame()
for r in eachrow(v1)
    t = r.tratta
    f2, b2 = scelta(t, FONTI)
    fs, bs = scelta(t, FONTI[1:6])
    riga = Dict{Symbol,Any}(:tratta => t, :costo_v1 => r.costo_star, :m_v1 => r.m_star, :n_v1 => r.n_star,
                            :provenienza_v1 => r.provenienza,
                            :provenienza => f2, :m => b2[2], :n => b2[3], :costo => b2[1],
                            :miglioramento_pct => 100 * (r.costo_star - b2[1]) / r.costo_star,
                            :provenienza_senza_fase2 => fs, :m_senza_fase2 => bs[2], :n_senza_fase2 => bs[3],
                            :costo_senza_fase2 => bs[1], :miglioramento_senza_fase2_pct => 100 * (r.costo_star - bs[1]) / r.costo_star)
    for x in FONTI
        c = get(best, (t, x), (Inf, NaN, NaN))
        riga[Symbol("costo_" * x)] = c[1]; riga[Symbol("m_" * x)] = c[2]; riga[Symbol("n_" * x)] = c[3]
    end
    push!(out, NamedTuple(riga); cols = :union)
end
abs(minimum(out.miglioramento_pct)) < 1e-9 || @warn "v2 peggiore della v1?" minimum(out.miglioramento_pct)
CSV.write(joinpath(@__DIR__, "risultati", "candidati_v2.csv"), select(out, :tratta, :provenienza, :m, :n, :costo, :miglioramento_pct,
          :costo_v1, :m_v1, :n_v1, :provenienza_v1, :provenienza_senza_fase2, :m_senza_fase2, :n_senza_fase2, :costo_senza_fase2,
          :miglioramento_senza_fase2_pct, [Symbol(p * x) for x in FONTI for p in ("costo_", "m_", "n_")]...))
for (nome, col, pc) in (("v2", :miglioramento_pct, :provenienza), ("senza fase 2", :miglioramento_senza_fase2_pct, :provenienza_senza_fase2))
    m = out[!, col]
    @printf("%-13s migliora: %d tratte; > 0,1%%: %d; > 1%%: %d; > 5%%: %d; massimo %.2f%%\n", nome, count(>(1e-10), m),
            count(>(0.1), m), count(>(1), m), count(>(5), m), maximum(m))
    println("   provenienza: ", sort(collect(Dict(p => count(==(p), out[!, pc]) for p in unique(out[!, pc])))))
end
