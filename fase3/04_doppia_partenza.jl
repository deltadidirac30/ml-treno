# Fase 3, validazione della doppia partenza sulle 1024 tratte DoE v2 (MAI sulle tratte reali), in CV: previsioni gb
# della ripetizione 1 (stessi fold della fase 2bis, fold_esterni), insiemi p69 e p66.
# Lanci NOMAD-PB (stesse impostazioni della fase 2bis: _uscite :progressiva, seme 20261010, _Valutatore con D7 e D8,
# m, n ∈ [0, 1]), ciascuno separato, con il tempo misurato (processo a un thread, 8 processi come la campagna):
#   S200  dal punto previsto, 200 valutazioni, su tutte le tratte (rifinitura singola; per p69 rifà quella della
#         fase 2bis, per misurarne il tempo e controllare che coincida);
#   A200  dal punto previsto dall'ALTRO ramo, 200 valutazioni, sulle tratte incerte (0,05 < p_ibrido < 0,95, la soglia
#         più larga: le altre soglie sono sottoinsiemi);
#   S100, A100  come sopra con 100 valutazioni, sulle stesse tratte (variante a parità di budget).
# Altro ramo: se il previsto è ibrido, (0, clamp(n̂ sola batteria, 0,005, 1)); se è sola batteria,
# (clamp(m̂, 0,03, 1), clamp(n̂ ibride, 0,005, 1)).
#
# Uso, da ml_treno/fase3:   julia -t 1 --project=. 04_doppia_partenza.jl
# Un file per insieme e tratta in LANCI/<insieme>/<tratta>.csv (ripresa); tutti i lanci in risultati/doppia_lanci.csv.

using Distributed, CSV, DataFrames, Printf
const QUI = @__DIR__
const LANCI = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase3/doppia"
const G2B = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis"
nprocs() < 9 && addprocs(9 - nprocs(); exeflags = `--project=$QUI -t 1`)
@everywhere begin
    using TrainPowertrain, NOMAD, CSV, DataFrames
    const OM  = TrainPowertrain.OttimizzatoreMN
    const EXT = Base.get_extension(TrainPowertrain, :TrainPowertrainNOMADExt)
    include(joinpath($QUI, "..", "fase2bis", "simulatore.jl"))
    function lancio(t, m0, n0, budget)
        x = tratte_doe()[t]
        f(m, n) = esito_ottimizzatore(valuta_progetto(m, n, PESO, x.cp, DIREZIONE; config = CFG, precalcolo = x.pre), PESO)
        V = OM._Valutatore(f, CFG.m_min_fc, budget); V.fase = "rifinitura"
        bb(z) = EXT._uscite(V(z[1], z[2]), :progressiva)
        p = NomadProblem(2, 5, ["OBJ", "PB", "PB", "PB", "PB"], bb; lower_bound = [0.0, 0.0], upper_bound = [1.0, 1.0])
        p.options.max_bb_eval = budget; p.options.seed = OpzioniNomad().seme; p.options.display_degree = 0
        t0 = time(); solve(p, [m0, n0]); isempty(V.storia) && V(m0, n0); dt = time() - t0
        st = V.storia; fz = [s for s in st if s[5] === :fattibile]
        s = isempty(fz) ? st[argmin([y[3] for y in st])] : fz[argmin([y[3] for y in fz])]
        return (m = s[1], n = s[2], costo = s[3], fattibile = s[5] === :fattibile, valutazioni = length(st), secondi = dt)
    end
    function lavoro(ins, t, lanci)
        file = joinpath($LANCI, ins, "$t.csv"); isfile(file) && return nothing
        df = DataFrame()
        for (nome, m0, n0, b) in lanci
            r = lancio(t, m0, n0, b)
            push!(df, merge((insieme = ins, tratta = t, lancio = nome, m0 = m0, n0 = n0, budget = b), r))
        end
        CSV.write(file * ".tmp", df); mv(file * ".tmp", file; force = true)
        return nothing
    end
end

d = CSV.read(joinpath(QUI, "..", "fase2bis", "dati", "dataset_doe_v2.csv"), DataFrame)
L = Dict(zip(d.tratta, d.x_L_km))
sim = CSV.read(joinpath(G2B, "sim_cv.csv"), DataFrame)
lav = []
for ins in ("p69", "p66")
    mkpath(joinpath(LANCI, ins))
    p = CSV.read(joinpath(G2B, "cv", "pred_r1_$(ins).csv"), DataFrame); p = p[p.famiglia .== "gb", :]
    s = sim[(sim.rip .== 1) .& (sim.insieme .== ins) .& (sim.modello .== "gb"), :]
    P = Dict(r.tratta => r for r in eachrow(p))
    for r in eachrow(s)
        q = P[r.tratta]
        (r.ibrido_prev == (q.p_ibrido >= 0.5)) || error("regime previsto incoerente")
        l = [("S200", r.m, r.n, 200)]
        if 0.05 < q.p_ibrido < 0.95
            ma, na = r.ibrido_prev ? (0.0, clamp(q.n_batt_prev, 0.005, 1.0)) : (clamp(q.m_prev, 0.03, 1.0), clamp(q.n_ibr_prev, 0.005, 1.0))
            append!(l, [("A200", ma, na, 200), ("S100", r.m, r.n, 100), ("A100", ma, na, 100)])
        end
        push!(lav, (ins, String(r.tratta), l))
    end
end
sort!(lav; by = x -> -L[x[2]])
t0 = time()
pmap(x -> lavoro(x...), lav)
@printf("lanci finiti in %.0f s\n", time() - t0)
tutti = reduce(vcat, [CSV.read(joinpath(LANCI, ins, f), DataFrame) for ins in ("p69", "p66") for f in readdir(joinpath(LANCI, ins)) if endswith(f, ".csv")])
CSV.write(joinpath(QUI, "risultati", "doppia_lanci.csv"), tutti)
println(nrow(tutti), " lanci, ", sum(tutti.valutazioni), " valutazioni")
