# Fase 2bis, passo 1: partenze sistematiche per il riferimento v2. Su TUTTE le 1024 tratte DoE, NOMAD-PB con le stesse
# impostazioni della rifinitura di fase 2 (= ottimizza_nomad del runner: uscite di _uscite(:progressiva), tipi
# OBJ + 4 PB, seme 20261010, valutatore _Valutatore con D8 e D7) e limiti m ∈ [0, 1], n ∈ [0, 1] (sotto m_min = 0,03
# è la sola batteria), budget 100 per partenza, un lancio separato per partenza:
#   P1  (0,11; n_rif)                 isola a sinistra di D20 (m ≈ 0,1195)
#   P2  (0,11; 0,95)                  isola tipo route 801 (batteria grande)
#   P3  (0; max(n_rif; 0,5))          sola batteria
#   P4  (m_rif; 0,05), m = 0,2 se m_rif = 0   batteria piccola
# (m_rif, n_rif) = ottimo del riferimento congelato v1 (fase1/dati/ottimi_riferimento.csv).
#
# Uso, da ml_treno/fase2bis:   julia -t 1 --project=. 01_partenze.jl
# 8 processi a un thread. Storia completa di ogni lancio in STORIE/<tratta>.csv (fuori da Google Drive, con ripresa);
# riassunto (miglior punto di ogni lancio) in risultati/partenze.csv.

using Distributed, CSV, DataFrames, Printf
const NPROC = 8
const QUI = @__DIR__
const BUDGET = 100
const STORIE = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis/partenze"
mkpath(STORIE)

nprocs() < NPROC + 1 && addprocs(NPROC + 1 - nprocs(); exeflags = `--project=$QUI -t 1`)
@everywhere begin
    using TrainPowertrain, NOMAD, CSV, DataFrames
    const OM  = TrainPowertrain.OttimizzatoreMN
    const EXT = Base.get_extension(TrainPowertrain, :TrainPowertrainNOMADExt)
    include(joinpath($QUI, "simulatore.jl"))
    const SEME_NOMAD = OpzioniNomad().seme
    function lancio(t, m0, n0, budget)
        x = tratte_doe()[t]
        f(m, n) = esito_ottimizzatore(valuta_progetto(m, n, PESO, x.cp, DIREZIONE; config = CFG, precalcolo = x.pre), PESO)
        V = OM._Valutatore(f, CFG.m_min_fc, budget)
        V.fase = "partenza"
        bb(z) = EXT._uscite(V(z[1], z[2]), :progressiva)
        p = NomadProblem(2, 5, ["OBJ", "PB", "PB", "PB", "PB"], bb; lower_bound = [0.0, 0.0], upper_bound = [1.0, 1.0])
        p.options.max_bb_eval = budget
        p.options.seed = SEME_NOMAD
        p.options.display_degree = 0
        solve(p, [m0, n0])
        isempty(V.storia) && V(m0, n0)
        return V
    end
    function lavoro(t, partenze)
        file = joinpath($STORIE, "$t.csv"); isfile(file) && return nothing
        righe = DataFrame()
        for (nome, m0, n0) in partenze
            V = lancio(t, m0, n0, $BUDGET)
            for (k, s) in enumerate(V.storia)
                push!(righe, (tratta = t, partenza = nome, m0 = m0, n0 = n0, k = k, m = s[1], n = s[2], costo = s[3],
                              tipo = String(s[5])))
            end
        end
        CSV.write(file * ".tmp", righe); mv(file * ".tmp", file; force = true)
        return nothing
    end
end

rif = CSV.read(joinpath(QUI, "..", "fase1", "dati", "ottimi_riferimento.csv"), DataFrame)
d = CSV.read(joinpath(QUI, "..", "fase1", "dati", "dataset_doe.csv"), DataFrame)
L = Dict(zip(d.tratta, d.x_L_km))
partenze(r) = [("P1", 0.11, r.n_star), ("P2", 0.11, 0.95), ("P3", 0.0, max(r.n_star, 0.5)),
               ("P4", r.m_star == 0 ? 0.2 : r.m_star, 0.05)]
lav = sort([(r.tratta, partenze(r)) for r in eachrow(rif)]; by = x -> -L[x[1]])     # le più lunghe prima
t0 = time()
pmap(x -> lavoro(x...), lav)
@printf("partenze P1–P4 su 1024 tratte in %.0f s\n", time() - t0)

st = reduce(vcat, [CSV.read(joinpath(STORIE, "$t.csv"), DataFrame) for t in rif.tratta])
# miglior punto di ogni lancio (regola di _risultato: fattibile di costo minimo, altrimenti costo minimo)
ris = combine(groupby(st, [:tratta, :partenza])) do g
    f = g.tipo .== "fattibile"
    i = any(f) ? findall(f)[argmin(g.costo[f])] : argmin(g.costo)
    (m0 = g.m0[1], n0 = g.n0[1], m = g.m[i], n = g.n[i], costo = g.costo[i], fattibile = f[i], valutazioni = nrow(g))
end
CSV.write(joinpath(QUI, "risultati", "partenze.csv"), ris)
@printf("valutazioni totali %d\n", nrow(st))
