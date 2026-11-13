# fase4/comune.jl: percorsi, schema e lettura dei registri della campagna P9_D28_16384.
# Incluso da tutti gli script di fase4. Nessuna simulazione: solo lettura dei registri, del design e
# delle coppie, e funzioni pure di TrainPowertrain (costo_da_grandezze, dimensionamento da n e m).

using TrainPowertrain, Printf, Arrow, Dates
const TP = TrainPowertrain

# ── percorsi ─────────────────────────────────────────────────────────────────────
const DATI      = expanduser("~/Documents/lavoro/ml_treno_dati/P9_D28_16384")
const RAW       = joinpath(DATI, "raw", "P9_D28_16384")
const DIR_ARROW = joinpath(DATI, "arrow")
const TP_ROOT   = expanduser("~/Documents/lavoro/train-powertrain")
const FILE_ZIP  = joinpath(TP_ROOT, "campagne", "registri_P9_D28_16384.zip")
const FILE_DESIGN = joinpath(TP_ROOT, "train-powertrain-matlab-correzioni-modello", "Codice_PRECONFIGURATORE_generale",
                             "tratte", "tratte_doe", "design_000001_016384.csv")
const FILE_COPPIE = joinpath(TP_ROOT, "julia", "scripts", "coppie", "campionamento_288.csv")
const FILE_ERRORI = joinpath(DATI, "raw", "errori_P9_D28_16384.csv")
const QUI = @__DIR__
const RIS = joinpath(QUI, "risultati")
const FIG = joinpath(QUI, "figure")

const NBLOCCHI = 64
const TRATTE_BLOCCO = 256
const NCOPPIE = 288
const NTRATTE = NBLOCCHI * TRATTE_BLOCCO
const RIGHE_BLOCCO = TRATTE_BLOCCO * NCOPPIE

file_registro(k) = joinpath(RAW, @sprintf("blocco_%02d", k), "registro.csv")
file_config(k)   = joinpath(RAW, @sprintf("blocco_%02d", k), "config.txt")
file_arrow(k)    = joinpath(DIR_ARROW, @sprintf("blocco_%02d.arrow", k))
const FILE_COPPIE_ARROW = joinpath(DIR_ARROW, "coppie.arrow")
const FILE_TRATTE_ARROW = joinpath(DIR_ARROW, "tratte.arrow")
const FILE_DIZIONARI_ARROW = joinpath(DIR_ARROW, "dizionari.arrow")
const FILE_RIASSUNTO_ARROW = joinpath(DIR_ARROW, "tratte_riassunto.arrow")

# ── schema del registro ──────────────────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
const NCOL = length(INTEST)
const COL = Dict(k => i for (i, k) in enumerate(INTEST))
# colonne di testo del registro; tutte le altre sono numeri (%.17g, "NaN", "Inf", "-Inf"; tempo_s %.6f)
const COL_TESTO = ["caso", "tratta", "direzione", "stato", "motivo", "fine", "tipo_esito", "storage_non_convergente"]
const COL_NUM = [k for k in INTEST if !(k in COL_TESTO)]
# colonne tolte nel formato compatto (ricostruibili o costanti; `fine` è data e ora)
const COL_TOLTE = ["caso", "direzione", "fine"]

# dizionari dei codici (1 = primo elemento). Il dizionario di `motivo` si costruisce dai dati (01_integrita.jl)
const STATI = ["completed", "rejected", "error"]
const TIPI_ESITO = ["fattibile", "piccola", "pesante", "mista", "errore"]
const DIREZIONE = "andata&ritorno"

# ── lettura del testo di un blocco ───────────────────────────────────────────────
"""
    leggi_testo(k) -> (intestazione, colonne, righe_cattive)

Il registro del blocco k come colonne di SubString (una per colonna dell'intestazione). Le righe con un
numero di campi diverso da 95 non entrano nelle colonne: si contano in `righe_cattive` (numero di riga, campi).
"""
function leggi_testo(k)
    s = read(file_registro(k), String)
    righe = split(s, '\n'; keepempty = false)
    intest = String(righe[1])
    nr = length(righe) - 1
    cols = [Vector{SubString{String}}(undef, nr) for _ in 1:NCOL]
    cattive = Tuple{Int,Int}[]
    j = 0
    for i in 2:length(righe)
        c = split(righe[i], ',')
        if length(c) != NCOL
            push!(cattive, (i, length(c))); continue
        end
        j += 1
        for q in 1:NCOL
            cols[q][j] = c[q]
        end
    end
    j < nr && foreach(v -> resize!(v, j), cols)
    return intest, cols, cattive
end

"""numero di route da "route_000241"; `nothing` se il formato non è quello"""
function id_tratta(s)
    m = match(r"^route_(\d{6})$", s)
    m === nothing ? nothing : parse(Int, m[1])
end

# ── coppie ───────────────────────────────────────────────────────────────────────
"""Le 288 coppie (m, n) di campionamento_288.csv, lette con parse(Float64) dal testo a 17 cifre."""
function leggi_coppie()
    l = readlines(FILE_COPPIE)
    l[1] == "m,n" || error("intestazione inattesa in $FILE_COPPIE: $(l[1])")
    v = [(parse(Float64, a), parse(Float64, b)) for (a, b) in (split(x, ',') for x in l[2:end] if !isempty(x))]
    length(v) == NCOPPIE || error("$FILE_COPPIE: $(length(v)) coppie, attese $NCOPPIE")
    return v
end
indice_coppie(cp) = Dict(c => Int16(i) for (i, c) in enumerate(cp))

# ── formato compatto ─────────────────────────────────────────────────────────────
"""Lettura di un blocco Arrow (colonne in memoria, copiate dal file mappato)."""
leggi_blocco(k; copia = true) = (t = Arrow.Table(file_arrow(k)); copia ? Dict(String(c) => collect(getproperty(t, c)) for c in Arrow.names(t)) : t)
"""
    carica_tutto(colonne = nothing) -> Dict{String,Vector}

Tutti i 64 blocchi concatenati (blocco 1, 2, …; dentro il blocco l'ordine del registro), solo le
`colonne` date (default tutte). In parallelo sui thread.
"""
function carica_tutto(colonne = nothing)
    parti = Vector{Dict{String,Any}}(undef, NBLOCCHI)
    Threads.@threads :dynamic for k in 1:NBLOCCHI
        t = Arrow.Table(file_arrow(k))
        nomi = colonne === nothing ? String.(Arrow.names(t)) : colonne
        parti[k] = Dict{String,Any}(c => collect(getproperty(t, Symbol(c))) for c in nomi)
    end
    return Dict{String,Any}(c => reduce(vcat, (p[c] for p in parti)) for c in keys(parti[1]))
end
leggi_dizionari() =(t = Arrow.Table(FILE_DIZIONARI_ARROW); d = Dict{String,Vector{String}}();
    for (c, i, s) in zip(t.campo, t.codice, t.testo); v = get!(d, c, String[]); length(v) < i && resize!(v, i); v[i] = s; end; d)

# ── costo ────────────────────────────────────────────────────────────────────────
# le grandezze che costo_da_grandezze legge (Objective.jl, docstring e corpo)
const COL_COSTO = ["m", "n", "P_nom_fc_kW", "C_batt_kWh", "H2_serbatoio_kg", "km_viaggio", "n_viaggi_giorno",
                   "E_ricarica_rete_kWh", "H2_cons_kg", "SOC_end", "vita_batt_cicli_viaggi", "vita_FC_viaggi",
                   "vita_FC_f1_ore", "durata_viaggio_s", "f_degrado_FC", "ore_max_FC",
                   "massa_propulsione_kg", "limite_massa_propulsione_kg", "scarica_s"]
# voci di cost_details (costo_ciclo_vita, details) che il registro ha anche come colonne
const VOCI_REGISTRO = ["P_nom_fc_kW", "C_batt_kWh", "H2_cons_kg", "SOC_end", "CAPEX_FC_EUR_km", "CAPEX_batt_EUR_km",
    "CAPEX_tank_EUR_km", "OPEX_batt_rech_EUR_km_att", "OPEX_H2_rech_EUR_km_att", "OPEX_mant_FC_EUR_km_att",
    "OPEX_mant_batt_EUR_km_att", "OPEX_mant_tank_EUR_km_att", "cost_repl_FC_EUR_km_att", "cost_repl_batt_EUR_km_att",
    "total_cost_EUR_km", "num_repl_FC", "num_repl_batt", "sostituzione_FC_saltata", "tau_FC_anni", "H2_coda_kg",
    "vita_batt_cicli_anni", "vita_batt_limite_calendario", "valore_residuo_FC_EUR_km", "valore_residuo_batt_EUR_km"]

const CFG = TP.ConfigModello()          # = config.txt della campagna (controllato in 01_integrita.jl)

# ── diagnostica dell'ultimo bit (vedi REPORT_FASE4_DATI.md, §costo ricostruito) ───────────────────────
# In Julia 1.12 x^y con y intero (|y| piccolo) passa per Base.Math.pow_body(x, n), che usa muladd: fuso (FMA)
# o no a seconda della macchina. Questa è pow_body con i muladd NON fusi (a*b + c), per confronto.
function pow_int_nofma(x::Float64, n::Int)
    y = 1.0; xnlo = -0.0; ynlo = 0.0
    n == 3 && return x * x * x
    tm(a, b) = (p = a * b; (p, fma(a, b, -p)))
    while n > 1
        if n & 1 > 0
            err = y * xnlo + x * ynlo
            y, ynlo = tm(x, y); ynlo += err
        end
        err = x * 2 * xnlo
        x, xnlo = tm(x, x); xnlo += err
        n >>>= 1
    end
    err = y * xnlo + x * ynlo
    return isfinite(x) & isfinite(err) ? x * y + err : x * y
end
_pot(x, t, fuso) = (fuso || !isinteger(t) || !(1 <= t <= 3 * 2^13)) ? x^t : pow_int_nofma(x, Int(t))
"""
cost_repl_batt_EUR_km_att dalle colonne della riga (prezzi di default, D18 + D14 come in costo_ciclo_vita),
con la potenza di questa macchina (`fuso = true`) o con pow_body a muladd non fusi (`fuso = false`).
"""
function repl_batt(g; fuso::Bool)
    i = 0.04; n_anni = 20.0
    cs = 100.0 * Float64(g["C_batt_kWh"])
    R = 0.0
    for j in 1.0:Float64(g["num_repl_batt"])
        R += cs / _pot(1.0 + i, j * Float64(g["vita_batt_anni"]), fuso)
    end
    A = (1.0 - (1.0 + i)^(-n_anni)) / i
    return R * (1.0 / A) / Float64(g["km_anno"])
end

# ── utilità ──────────────────────────────────────────────────────────────────────
fmt(x::Integer) = replace(string(x), r"(?<=\d)(?=(\d{3})+$)" => ".")
pct(a, b) = b == 0 ? "—" : @sprintf("%.3f%%", 100a / b)
function log_su(f, io_file)
    open(io_file, "w") do io
        f(io)
    end
    print(read(io_file, String))
end
