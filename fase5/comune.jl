# fase5/comune.jl: percorsi e lettura a blocchi delle 16384 tratte DoE della campagna P9_D28_16384.
# Incluso da 01_tratte.jl e 02_caratteristiche.jl. Nessuna modifica a TrainPowertrain.

using TrainPowertrain, Printf, Arrow, Dates
const TP = TrainPowertrain

# ── percorsi ─────────────────────────────────────────────────────────────────────
const BASE_DATI   = expanduser("~/Documents/lavoro/ml_treno_dati")
const DIR_TRATTE  = joinpath(BASE_DATI, "tratte_doe_16384")                 # estratte dallo zip (00_zip.sh)
const DIR_ARROW   = joinpath(BASE_DATI, "P9_D28_16384", "arrow")            # fase 4
const RAW_CAMP    = joinpath(BASE_DATI, "P9_D28_16384", "raw", "P9_D28_16384")
const DIR_LOG     = joinpath(BASE_DATI, "fase5_log")                        # log e file di lavoro, fuori da Drive
const DIR_RIVAL   = joinpath(BASE_DATI, "fase5_rivalutazione")              # cartelle di campagna del campione
const FILE_CARATT = joinpath(DIR_ARROW, "caratteristiche.arrow")            # uscita del passo 2
const TP_ROOT     = expanduser("~/Documents/lavoro/train-powertrain")
const FILE_DESIGN = joinpath(TP_ROOT, "train-powertrain-matlab-correzioni-modello", "Codice_PRECONFIGURATORE_generale",
                             "tratte", "tratte_doe", "design_000001_016384.csv")
const FILE_COPPIE = joinpath(TP_ROOT, "julia", "scripts", "coppie", "campionamento_288.csv")
const QUI  = @__DIR__
const RIS  = joinpath(QUI, "risultati")
const FASE1 = joinpath(QUI, "..", "fase1")

const NTRATTE = 16384
const TRATTE_BLOCCO = 256
const NBLOCCHI = NTRATTE ÷ TRATTE_BLOCCO
const ROUTE_D29 = (2366, 14664)          # le due tratte con righe DOE:D26FrenataImpossibile (fase 4)

file_arrow(k) = joinpath(DIR_ARROW, @sprintf("blocco_%02d.arrow", k))
file_config_campagna(k) = joinpath(RAW_CAMP, @sprintf("blocco_%02d", k), "config.txt")
route_blocco(k) = ((k - 1) * TRATTE_BLOCCO + 1):(k * TRATTE_BLOCCO)

"""
    tratte_blocco(k; nthr = Threads.nthreads()) -> Vector{TrattaCampagna}

Le 256 tratte del blocco k, lette con `leggi_tratte_materializzate(DIR_TRATTE; solo = …)` come la
campagna (`esegui_campagna.jl tratte=tratte_doe_16384 solo=a-z`), quindi con il controllo dell'impronta
della pendenza contro il manifest. Lette in `nthr` pezzi in parallelo (ogni pezzo rilegge il manifest);
l'ordine è quello delle route.
"""
function tratte_blocco(k; nthr = Threads.nthreads())
    r = collect(route_blocco(k))
    pezzi = [r[i:nthr:end] for i in 1:nthr]
    out = Vector{Vector{TrattaCampagna}}(undef, nthr)
    Threads.@threads :static for i in 1:nthr
        out[i] = leggi_tratte_materializzate(DIR_TRATTE; solo = Set(pezzi[i]))
    end
    t = reduce(vcat, out)
    sort!(t; by = x -> x.id)
    length(t) == TRATTE_BLOCCO || error("blocco $k: $(length(t)) tratte lette, attese $TRATTE_BLOCCO")
    return t
end

rid_di(id) = parse(Int, match(r"^route_(\d{6})$", id)[1])

# ── design (lettura a mano come in fase 4: Bool, Int, Float64 con parse) ─────────
function leggi_design()
    l = readlines(FILE_DESIGN)
    h = String.(split(l[1], ','))
    righe = [split(x, ',') for x in l[2:end] if !isempty(x)]
    conv(s) = s == "true" ? true : s == "false" ? false : (v = tryparse(Int, s); v === nothing ? parse(Float64, s) : v)
    d = Dict{String,Vector}(c => [conv(r[j]) for r in righe] for (j, c) in enumerate(h))
    return h, d
end

# ── utilità ──────────────────────────────────────────────────────────────────────
"""distanza in ULP tra due Float64 finiti (Inf se uno solo è NaN/Inf o segni diversi e non zero)"""
function ulp_dist(a::Float64, b::Float64)
    a === b && return 0
    (isnan(a) || isnan(b)) && return typemax(Int)
    (isinf(a) || isinf(b)) && return typemax(Int)
    ia = reinterpret(Int64, a); ib = reinterpret(Int64, b)
    ia = ia < 0 ? typemin(Int64) - ia : ia          # ordinamento lessicografico dei Float64
    ib = ib < 0 ? typemin(Int64) - ib : ib
    return Int(abs(Int128(ia) - Int128(ib)))
end
fmt(x::Integer) = replace(string(x), r"(?<=\d)(?=(\d{3})+$)" => ".")
