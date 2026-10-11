# Fase 3, passo 2: surrogato + simulatore sulle tratte reali. Per ogni insieme di input (p69, p66) e tratta:
#   (1) una valutazione nel punto previsto da 01_surrogato.jl: fattibile o no, e perché (SOC, massa, D3, altro);
#   (2) rifinitura NOMAD-PB da 200 valutazioni dal punto previsto (stesse impostazioni della fase 2bis: _uscite
#       :progressiva, seme 20261010, _Valutatore con D7 e D8, m ∈ [0, 1], n ∈ [0, 1]); punto finale = miglior
#       fattibile delle valutazioni (altrimenti il penalizzato di costo minimo);
#   (3) rivalutazione del punto finale con fase1/uscite.jl (grandezze: taglie, voci, sostituzioni).
# Variante (riportata a parte): se il classificatore è incerto (0,1 < p_ibrido < 0,9), una seconda rifinitura dal punto
# previsto dall'altro ramo (ibrido: m = clamp(m̂, 0,03, 1), n = n̂ delle ibride; sola batteria: m = 0, n = n̂ delle sola
# batteria), stesso budget; righe con partenza = "altro_regime".
# Un processo per lancio (NOMAD non regge più thread), 6 processi. Storie in STORIE (fuori da Google Drive).
#
# Uso, da ml_treno/fase3 (dopo 01_surrogato.jl):   julia -t 1 --project=. 02_simulatore.jl
# Scrive risultati/simulatore_reali.csv.

using Distributed, CSV, DataFrames
const QUI = @__DIR__
const STORIE = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase3"
mkpath(STORIE)
addprocs(6; exeflags = `--project=$QUI -t 1`)
@everywhere begin
    using NOMAD, CSV, DataFrames
    include(joinpath($QUI, "..", "fase1", "uscite.jl"))
    include(joinpath($QUI, "reali.jl"))
    const OM  = TrainPowertrain.OttimizzatoreMN
    const EXT = Base.get_extension(TrainPowertrain, :TrainPowertrainNOMADExt)
    const BUDGET = 200
    # causa della non fattibilità (come fase2/simulatore.jl: esito_punto)
    function causa(e)
        pen = round(Int, e.penalita)
        massa = e.stato === :completed && pen in (1000, 4000, 6000, 9000)
        soc   = e.stato === :completed && (pen % 1000 == 0) && (pen - (massa ? 1000 : 0)) > 0
        d3    = e.stato === :rejected && occursin("sottodimensionata", e.motivo)
        fatt  = e.stato === :completed && pen == 0
        return (fattibile = fatt, causa = fatt ? "" : join([s for (s, b) in (("SOC", soc), ("massa", massa), ("D3", d3)) if b], "+") |>
                                             x -> isempty(x) ? "altro: $(e.stato) $(e.motivo)" : x,
                costo = e.costo, penalita = e.penalita,
                SOC_fine = e.risultato === nothing ? NaN : e.risultato.SOC_batt[end],
                massa_kg = e.risultato === nothing ? NaN : e.risultato.peso_sistema_propulsione)
    end
    function lavoro(ins, t, m0, n0, partenza)
        x = tratte_reali()[t]
        c0 = causa(valuta(x.cp, m0, n0; pre = x.pre)[1])
        f(m, n) = esito_ottimizzatore(valuta_progetto(m, n, PESO_A_CARICO, x.cp, DIREZIONE; config = CONFIG, precalcolo = x.pre), PESO_A_CARICO)
        V = OM._Valutatore(f, CONFIG.m_min_fc, BUDGET); V.fase = "rifinitura"
        bb(z) = EXT._uscite(V(z[1], z[2]), :progressiva)
        p = NomadProblem(2, 5, ["OBJ", "PB", "PB", "PB", "PB"], bb; lower_bound = [0.0, 0.0], upper_bound = [1.0, 1.0])
        p.options.max_bb_eval = BUDGET; p.options.seed = OpzioniNomad().seme; p.options.display_degree = 0
        solve(p, [m0, n0])
        st = DataFrame(k = 1:length(V.storia), m = [s[1] for s in V.storia], n = [s[2] for s in V.storia],
                       costo = [s[3] for s in V.storia], tipo = [String(s[5]) for s in V.storia])
        CSV.write(joinpath($STORIE, "$(ins)_$(t)_$(partenza).csv"), st)
        fz = findall(st.tipo .== "fattibile")
        i = isempty(fz) ? argmin(st.costo) : fz[argmin(st.costo[fz])]
        e, tr = valuta(x.cp, st.m[i], st.n[i]; pre = x.pre)
        cf = causa(e)
        g = cf.fattibile ? Dict(grandezze(e, tr, x.cp)) : Dict{String,Any}()
        riga = Dict{Symbol,Any}(:insieme => ins, :tratta => t, :partenza => partenza, :m0 => m0, :n0 => n0, :fattibile0 => c0.fattibile, :causa0 => c0.causa,
                                :costo0 => c0.costo, :SOC_fine0 => c0.SOC_fine, :massa0_kg => c0.massa_kg,
                                :valutazioni => nrow(st), :fattibili_storia => length(fz), :prima_fattibile => isempty(fz) ? 0 : first(fz),
                                :m_fin => st.m[i], :n_fin => st.n[i], :fattibile_fin => cf.fattibile, :costo_fin => cf.costo)
        for (a, b) in g; riga[Symbol(a)] = b; end
        return NamedTuple(riga)
    end
end
s = CSV.read(joinpath(QUI, "risultati", "surrogato_reali.csv"), DataFrame)
t0 = time()
lav = [(String(r.insieme), String(r.tratta), r.m_star, r.n_star, "previsto") for r in eachrow(s)]
for r in eachrow(s)
    0.1 < r.p_ibrido < 0.9 || continue
    push!(lav, r.regime == "ibrido" ? (String(r.insieme), String(r.tratta), 0.0, clamp(r.n_prev_batteria, 0.005, 1.0), "altro_regime") :
                                      (String(r.insieme), String(r.tratta), clamp(r.m_prev_ibrido, 0.03, 1.0), clamp(r.n_prev_ibrido, 0.005, 1.0), "altro_regime"))
end
out = pmap(x -> lavoro(x...), lav)
println(length(lav), " rifiniture in ", round(time() - t0), " s")
df = DataFrame(); foreach(r -> push!(df, r; cols = :union), out)
CSV.write(joinpath(QUI, "risultati", "simulatore_reali.csv"), df)
show(select(df, :insieme, :tratta, :partenza, :m0, :n0, :fattibile0, :causa0, :prima_fattibile, :m_fin, :n_fin, :fattibile_fin, :costo_fin), allcols = true)
