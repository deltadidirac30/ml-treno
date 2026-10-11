# Fase 2bis, passo 7 (= fase2/03_rifinitura.jl sul riferimento v2, budget 50, 100, 200; metrica b): previsione + rifinitura. NOMAD-PB (barriera progressiva sulle violazioni di
# esito_ottimizzatore, stesse uscite e stesso seme 20261010 di ottimizza_nomad nel runner) parte dal punto previsto,
# con limiti m ∈ [0, 1] (sotto m_min = 0,03 è la sola batteria, D8: la rifinitura può cambiare regime) e n ∈ [0, 1].
# Un lancio SEPARATO per ogni budget (50, 100, 200); il risultato è il migliore delle valutazioni fatte (regola di
# _risultato: miglior fattibile, altrimenti il penalizzato di costo minimo). La scorciatoia "migliore tra le prime k
# valutazioni del lancio a 100" non coincide con il lancio a budget k (NOMAD si comporta diversamente con un budget
# minore: in 4 tratte su 12 del controllo il punto finale era diverso), quindi non si usa.
#
# Partenze: i punti previsti nella ripetizione 1 da MODELLI_PARTENZA (insieme di input in INSIEME).
# Uso, da ml_treno/fase2bis (dopo 06_simula.jl):   julia -t 1 --project=. 07_rifinitura.jl <insieme> <modello> [<modello> ...]
# 8 processi a un thread (NOMAD non regge più thread nello stesso processo). Ripresa per (modello, tratta) in
# PER_TRATTA/<insieme>_<modello>/<tratta>.csv, fuori da Google Drive (migliaia di file piccoli). Scrive
# risultati/rifinitura_<insieme>.csv.

using Distributed, CSV, DataFrames, Printf
const NPROC = 8
const QUI = @__DIR__
const INSIEME = ARGS[1]
const MODELLI_PARTENZA = ARGS[2:end]
const TAGLI = (50, 100, 200)
const PER_TRATTA = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis/rifinitura"

nprocs() < NPROC + 1 && addprocs(NPROC + 1 - nprocs(); exeflags = `--project=$QUI -t 1`)
@everywhere begin
    using TrainPowertrain, NOMAD, CSV, DataFrames, Printf
    const OM  = TrainPowertrain.OttimizzatoreMN
    const EXT = Base.get_extension(TrainPowertrain, :TrainPowertrainNOMADExt)
    include(joinpath($QUI, "simulatore.jl"))
    const SEME_NOMAD = OpzioniNomad().seme
    # una rifinitura: storia delle valutazioni nuove (m, n, costo, tipo) nell'ordine
    function rifinisci(t, m0, n0, budget)
        x = tratte_doe()[t]
        f(m, n) = esito_ottimizzatore(valuta_progetto(m, n, PESO, x.cp, DIREZIONE; config = CFG, precalcolo = x.pre), PESO)
        V = OM._Valutatore(f, CFG.m_min_fc, budget)
        V.fase = "rifinitura"
        bb(z) = EXT._uscite(V(z[1], z[2]), :progressiva)
        p = NomadProblem(2, 5, ["OBJ", "PB", "PB", "PB", "PB"], bb; lower_bound = [0.0, 0.0], upper_bound = [1.0, 1.0])
        p.options.max_bb_eval = budget
        p.options.seed = SEME_NOMAD
        p.options.display_degree = 0
        solve(p, [m0, n0])
        isempty(V.storia) && V(m0, n0)
        return V
    end
    # migliore tra le prime k valutazioni (regola di _risultato: fattibile di costo minimo, altrimenti costo minimo)
    function migliore(V, k)
        st = V.storia[1:min(k, length(V.storia))]
        fz = [s for s in st if s[5] === :fattibile]
        s = isempty(fz) ? st[argmin([x[3] for x in st])] : fz[argmin([x[3] for x in fz])]
        return (m = s[1], n = s[2], costo = s[3], fattibile = s[5] === :fattibile, valutazioni = length(st))
    end
    function lavoro(dir, t, m0, n0)
        file = joinpath(dir, "$t.csv"); isfile(file) && return nothing
        righe = DataFrame()
        for k in $TAGLI
            V = rifinisci(t, m0, n0, k)
            b = migliore(V, k)
            push!(righe, (tratta = t, budget = k, m0 = m0, n0 = n0, m = b.m, n = b.n, costo = b.costo, fattibile = b.fattibile,
                          valutazioni = b.valutazioni))
        end
        CSV.write(file * ".tmp", righe); mv(file * ".tmp", file; force = true)
        return nothing
    end
end

sim = CSV.read("/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis/sim_cv.csv", DataFrame)
d = CSV.read(joinpath(QUI, "dati", "dataset_doe_v2.csv"), DataFrame)
L = Dict(zip(d.tratta, d.x_L_km))
for mod in MODELLI_PARTENZA
    s = sim[(sim.rip .== 1) .& (sim.insieme .== INSIEME) .& (sim.modello .== mod), :]
    nrow(s) == 1024 || error("$mod: $(nrow(s)) partenze")
    dir = joinpath(PER_TRATTA, "$(INSIEME)_$(mod)"); mkpath(dir)
    lav = sort([(r.tratta, r.m, r.n) for r in eachrow(s)]; by = x -> -L[x[1]])     # le più lunghe prima
    t0 = time()
    pmap(x -> lavoro(dir, x...), lav)
    @printf("%s %s: rifinitura di 1024 tratte in %.0f s\n", INSIEME, mod, time() - t0)
end
tutte = reduce(vcat, [begin
    dir = joinpath(PER_TRATTA, "$(INSIEME)_$(mod)")
    x = reduce(vcat, [CSV.read(joinpath(dir, f), DataFrame) for f in readdir(dir) if endswith(f, ".csv")])
    x.modello .= mod; x
end for mod in MODELLI_PARTENZA])
CSV.write(joinpath(QUI, "risultati", "rifinitura_$(INSIEME).csv"), tutte)
