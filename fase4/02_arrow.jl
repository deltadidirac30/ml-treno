# fase4/02_arrow.jl: passo 2, formato compatto (Arrow, zstd) senza perdita, con il viaggio di ritorno.
#   julia -t 8 --project=fase4 fase4/02_arrow.jl
# Richiede risultati/motivi.txt (da 01_integrita.jl). Scrive in ~/Documents/lavoro/ml_treno_dati/P9_D28_16384/arrow:
# blocco_01..64.arrow, coppie.arrow, tratte.arrow, dizionari.arrow; e risultati/02_arrow.txt.

include(joinpath(@__DIR__, "comune.jl"))
using Serialization

const COPPIE = leggi_coppie()
const IDX = indice_coppie(COPPIE)
const MOTIVI = readlines(joinpath(RIS, "motivi.txt"); keep = false)
const COD_MOTIVO = Dict(m => Int16(i) for (i, m) in enumerate(MOTIVI))
const COD_STATO = Dict(s => Int8(i) for (i, s) in enumerate(STATI))
const COD_TIPO = Dict(s => Int8(i) for (i, s) in enumerate(TIPI_ESITO))
const SHA_ZIP = strip(split(read(joinpath(DATI, "log", "sha256.txt"), String))[1])
const CONFIG_TXT = strip(read(file_config(1), String))

# schema: le colonne del registro nell'ordine, senza caso, direzione e fine; `coppia` dopo `tratta`
const SCHEMA = let s = String[]
    for c in INTEST
        c in COL_TOLTE && continue
        push!(s, c)
        c == "tratta" && push!(s, "coppia")
    end
    s
end
tipo_colonna(c) = c == "tratta" ? Int32 : c == "coppia" ? Int16 : c in ("stato", "tipo_esito") ? Int8 :
                  c == "motivo" ? Int16 : c == "storage_non_convergente" ? Union{Missing,Bool} : Float64
const META = Dict("sorgente" => "registri_P9_D28_16384.zip (sha256 $SHA_ZIP)", "config" => CONFIG_TXT,
                  "codici" => "stato, tipo_esito, motivo: indici (da 1) nei dizionari di dizionari.arrow; coppia: indice in coppie.arrow",
                  "tolte" => "caso (= tratta_ar_m%.6g_n%.6g), direzione (sempre andata&ritorno), fine (data e ora)")
const COLMETA = Dict(:stato => Dict("dizionario" => join(("$i=$s" for (i, s) in enumerate(STATI)), ";")),
                     :tipo_esito => Dict("dizionario" => join(("$i=$s" for (i, s) in enumerate(TIPI_ESITO)), ";")),
                     :motivo => Dict("dizionario" => "dizionari.arrow, campo motivo ($(length(MOTIVI)) voci, 1 = vuoto)"),
                     :coppia => Dict("dizionario" => "coppie.arrow, colonna coppia (1..288)"),
                     :tratta => Dict("descrizione" => "route_id del design (tratte.arrow)"),
                     :storage_non_convergente => Dict("descrizione" => "D28; missing dove il registro ha NaN (righe non simulate)"))

f17(x) = @sprintf("%.17g", x)

function converti_blocco(k)
    t0 = time()
    _, cols, cattive = leggi_testo(k)
    isempty(cattive) || error("blocco $k: righe con campi ≠ 95")
    nr = length(cols[1]); S(c) = cols[COL[c]]
    out = Dict{String,Any}()
    for c in SCHEMA
        c in ("tratta", "coppia", "stato", "motivo", "tipo_esito", "storage_non_convergente") && continue
        out[c] = parse.(Float64, S(c))
    end
    out["tratta"] = Int32[id_tratta(s) for s in S("tratta")]
    out["coppia"] = Int16[IDX[(m, n)] for (m, n) in zip(out["m"], out["n"])]
    out["stato"] = Int8[COD_STATO[s] for s in S("stato")]
    out["tipo_esito"] = Int8[COD_TIPO[s] for s in S("tipo_esito")]
    out["motivo"] = Int16[COD_MOTIVO[s] for s in S("motivo")]
    out["storage_non_convergente"] = Union{Missing,Bool}[s == "true" ? true : s == "false" ? false :
                                     s == "NaN" ? missing : error("storage_non_convergente = $s") for s in S("storage_non_convergente")]
    tab = NamedTuple{Tuple(Symbol.(SCHEMA))}(Tuple(convert(Vector{tipo_colonna(c)}, out[c]) for c in SCHEMA))
    meta = merge(META, Dict("blocco" => string(k), "route" => "$((k - 1) * TRATTE_BLOCCO + 1)-$(k * TRATTE_BLOCCO)"))
    Arrow.write(file_arrow(k), tab; compress = :zstd, metadata = meta, colmetadata = COLMETA)
    t_scr = time() - t0
    # ── viaggio di ritorno: rilettura dal file e confronto con il testo del CSV ──
    t1 = time()
    a = Arrow.Table(file_arrow(k))
    diversi = Dict{String,Int}()
    D(c, x) = (diversi[c] = get(diversi, c, 0) + x)
    for c in SCHEMA
        v = getproperty(a, Symbol(c))
        length(v) == nr || D(c, 10^9)
        if tipo_colonna(c) === Float64
            eltype(v) === Float64 || D(c, 10^9)
            txt = S(c)
            ne = 0; nt = 0
            for i in 1:nr
                v[i] === parse(Float64, txt[i]) || (ne += 1)
                # il testo si rigenera uguale (17 cifre; tempo_s con 6 decimali)
                (c == "tempo_s" ? @sprintf("%.6f", v[i]) : f17(v[i])) == txt[i] || (nt += 1)
            end
            D(c, ne); D(c * " (testo)", nt)
        end
    end
    D("tratta", count(i -> @sprintf("route_%06d", a.tratta[i]) != S("tratta")[i], 1:nr))
    D("coppia", count(i -> COPPIE[a.coppia[i]] !== (a.m[i], a.n[i]), 1:nr))
    D("stato", count(i -> STATI[a.stato[i]] != S("stato")[i], 1:nr))
    D("tipo_esito", count(i -> TIPI_ESITO[a.tipo_esito[i]] != S("tipo_esito")[i], 1:nr))
    D("motivo", count(i -> MOTIVI[a.motivo[i]] != S("motivo")[i], 1:nr))
    D("storage_non_convergente", count(i -> (x = a.storage_non_convergente[i]; ismissing(x) ? "NaN" : string(x)) != S("storage_non_convergente")[i], 1:nr))
    D("caso (ricostruito)", count(i -> @sprintf("route_%06d_ar_m%.6g_n%.6g", a.tratta[i], a.m[i], a.n[i]) != S("caso")[i], 1:nr))
    D("direzione (costante)", count(!=(DIREZIONE), S("direzione")))
    meta_ok = Dict(Arrow.getmetadata(a)) == meta
    # costo_da_grandezze dall'Arrow
    g = Dict{String,Float64}()
    ncomp = 0; tot_div = 0; costo_div = 0
    colc = [getproperty(a, Symbol(c)) for c in COL_COSTO]
    for i in 1:nr
        a.stato[i] == 1 || continue
        ncomp += 1
        for (c, v) in zip(COL_COSTO, colc); g[c] = v[i]; end
        r = TP.costo_da_grandezze(g; cfg = CFG)
        r.costo_totale === a.total_cost_EUR_km[i] || (tot_div += 1)
        r.costo === a.costo[i] || (costo_div += 1)
    end
    # per tratta: righe fattibili (per tratte.arrow) e righe di errore
    fatt = Dict{Int32,Int}(); err = Dict{Int32,Int}()
    for i in 1:nr
        a.tipo_esito[i] == 1 && (fatt[a.tratta[i]] = get(fatt, a.tratta[i], 0) + 1)
        a.stato[i] == 3 && (err[a.tratta[i]] = get(err, a.tratta[i], 0) + 1)
    end
    return (k = k, nr = nr, diversi = filter(x -> x[2] != 0, diversi), meta_ok, ncomp, tot_div, costo_div, fatt, err,
            bytes_csv = filesize(file_registro(k)), bytes_arrow = filesize(file_arrow(k)), t_scr, t_ver = time() - t1)
end

# design delle tratte, letto a mano: Bool ("true"/"false"), Int64, altrimenti Float64 con parse (al bit)
function leggi_design()
    l = readlines(FILE_DESIGN)
    h = split(l[1], ','); r = [split(x, ',') for x in l[2:end] if !isempty(x)]
    cols = Pair{Symbol,Any}[]
    for (j, c) in enumerate(h)
        v = [x[j] for x in r]
        col = all(s -> s in ("true", "false"), v) ? [s == "true" for s in v] :
              all(s -> tryparse(Int64, s) !== nothing, v) ? parse.(Int64, v) : parse.(Float64, v)
        push!(cols, Symbol(c) => col)
    end
    return (; cols...)
end

function main()
    mkpath(DIR_ARROW)
    t0 = time()
    R = Vector{Any}(undef, NBLOCCHI)
    Threads.@threads :dynamic for k in 1:NBLOCCHI
        R[k] = converti_blocco(k)
        @printf("blocco %02d: scrittura %.1f s, verifica %.1f s, %s → %s\n", k, R[k].t_scr, R[k].t_ver,
                Base.format_bytes(R[k].bytes_csv), Base.format_bytes(R[k].bytes_arrow)); flush(stdout)
    end
    t_conv = time() - t0
    # ── coppie.arrow ──
    sob = TP.coppie_campionamento(256; seme = TP.SEME_CAMPIONAMENTO)
    sog = TP.coppie_soglie(16; seme = TP.SEME_SOGLIE)
    origine_ok = vcat(sob, sog) == COPPIE
    s = [x.m for x in TP.soglie_controllo(CFG)]
    interv(m) = m == 0 ? Int8(0) : m < s[1] ? Int8(1) : m < s[2] ? Int8(2) : m < s[3] ? Int8(3) : Int8(4)
    Arrow.write(FILE_COPPIE_ARROW, (coppia = Int16.(1:NCOPPIE), m = first.(COPPIE), n = last.(COPPIE),
                                    origine = [i <= 256 ? "sobol" : "soglie" for i in 1:NCOPPIE],
                                    sola_batteria = [c[1] == 0.0 for c in COPPIE],
                                    intervallo_D25 = interv.(first.(COPPIE)));
                metadata = Dict("sorgente" => "julia/scripts/coppie/campionamento_288.csv",
                                "intervallo_D25" => @sprintf("0: m = 0; 1: [m_min, %.17g); 2: [%.17g, %.17g); 3: [%.17g, %.17g); 4: [%.17g, 1]", s[1], s[1], s[2], s[2], s[3], s[3])))
    # ── tratte.arrow ──
    des = leggi_design()
    des.route_id == 1:NTRATTE || error("design: route_id non 1..16384")
    fatt = Dict{Int32,Int}(); err = Dict{Int32,Int}()
    for r in R; mergewith!(+, fatt, r.fatt); mergewith!(+, err, r.err); end
    blocco = Int8[(t - 1) ÷ TRATTE_BLOCCO + 1 for t in des.route_id]
    tr = merge(des, (blocco = blocco, errore_D29 = [get(err, Int32(t), 0) > 0 for t in des.route_id],
                     senza_coppie_fattibili = [get(fatt, Int32(t), 0) == 0 for t in des.route_id]))
    Arrow.write(FILE_TRATTE_ARROW, tr; metadata = Dict("sorgente" => "design_000001_016384.csv (train-powertrain-matlab-correzioni-modello)",
                "errore_D29" => "la tratta ha righe in errore (DOE:D26FrenataImpossibile)", "senza_coppie_fattibili" => "nessuna delle 288 coppie con tipo_esito = fattibile"))
    # ── dizionari.arrow ──
    camp = String[]; cod = Int16[]; txt = String[]
    for (nome, v) in (("stato", STATI), ("tipo_esito", TIPI_ESITO), ("motivo", MOTIVI))
        for (i, x) in enumerate(v); push!(camp, nome); push!(cod, i); push!(txt, x); end
    end
    Arrow.write(FILE_DIZIONARI_ARROW, (campo = camp, codice = cod, testo = txt))
    # ── tempi di lettura e memoria ──
    GC.gc()
    t1 = time(); b = leggi_blocco(1); t_uno_primo = time() - t1
    t1 = time(); b = leggi_blocco(2); t_uno = time() - t1
    mem_uno = sum(Base.summarysize(v) for v in values(b))
    b = nothing; GC.gc()
    t1 = time(); tutto = [leggi_blocco(k) for k in 1:NBLOCCHI]; t_tutto = time() - t1
    mem_tutto = sum(sum(Base.summarysize(v) for v in values(x)) for x in tutto)
    t1 = time(); tutti_mappati = [Arrow.Table(file_arrow(k)) for k in 1:NBLOCCHI]; t_map = time() - t1
    tutto = nothing; tutti_mappati = nothing; GC.gc()
    serialize(joinpath(DATI, "log", "02_blocchi.jls"), R)
    r1 = deserialize(joinpath(DATI, "log", "01_blocchi.jls"))[1]
    log_su(joinpath(RIS, "02_arrow.txt")) do io
        p(x...) = println(io, x...)
        p("# Passo 2: formato Arrow (", now(), ", ", Threads.nthreads(), " thread)")
        p()
        p("conversione + verifica dei 64 blocchi: ", @sprintf("%.1f s", t_conv))
        p("schema dei blocchi (", length(SCHEMA), " colonne): ", join(["$c::$(tipo_colonna(c))" for c in SCHEMA], ", "))
        p()
        p("## Viaggio di ritorno (Arrow riletto contro il testo del CSV)")
        p("colonne con valori diversi (=== sul Float64 letto con parse, NaN compresi; codici decodificati): ",
          isempty(mapreduce(r -> r.diversi, (a, b) -> mergewith(+, a, b), R)) ? "nessuna" : mapreduce(r -> r.diversi, (a, b) -> mergewith(+, a, b), R))
        p("(questo comprende: il testo di ogni campo numerico si rigenera uguale con %.17g, tempo_s con %.6f; ",
          "caso si ricostruisce da tratta, m, n; direzione è sempre andata&ritorno)")
        p("metadati del file riletti uguali: ", count(r -> r.meta_ok, R), "/64")
        p("costo_da_grandezze dall'Arrow, completed: ", fmt(sum(r.ncomp for r in R)), " righe; costo_totale !== total_cost_EUR_km: ",
          sum(r.tot_div for r in R), " (dal CSV, passo 1: ", sum(r.costo_tot_div for r in r1), "); costo !== costo: ",
          sum(r.costo_div for r in R), " (passo 1: ", sum(r.costo_div for r in r1), ")")
        p("stesse righe diverse per blocco del passo 1: ", all(R[k].tot_div == r1[k].costo_tot_div for k in 1:NBLOCCHI))
        p()
        p("## coppie.arrow e tratte.arrow")
        p("coppie: righe 1-256 = coppie_campionamento(256), 257-288 = coppie_soglie(16) (TrainPowertrain): ", origine_ok)
        p("coppie per intervallo D25 (0: m=0, 1..4 tra m_min, le soglie e 1): ", [count(==(j), interv.(first.(COPPIE))) for j in 0:4])
        p("tratte.arrow: ", length(des.route_id), " righe, colonne ", join(string.(keys(tr)), ", "))
        p("tratte con errori (errore_D29): ", sort!([Int(t) for (t, c) in err]), "; tratte senza coppie fattibili: ", count(tr.senza_coppie_fattibili))
        p()
        p("## Dimensioni, tempi, memoria")
        bc = sum(r.bytes_csv for r in R); ba = sum(r.bytes_arrow for r in R)
        p("CSV (64 registri): ", Base.format_bytes(bc), "; Arrow zstd (64 blocchi): ", Base.format_bytes(ba), @sprintf(" (%.1f%% del CSV)", 100ba / bc))
        p("blocco Arrow: da ", Base.format_bytes(minimum(r.bytes_arrow for r in R)), " a ", Base.format_bytes(maximum(r.bytes_arrow for r in R)))
        p("coppie.arrow ", Base.format_bytes(filesize(FILE_COPPIE_ARROW)), ", tratte.arrow ", Base.format_bytes(filesize(FILE_TRATTE_ARROW)),
          ", dizionari.arrow ", Base.format_bytes(filesize(FILE_DIZIONARI_ARROW)))
        p("zip di partenza ", Base.format_bytes(filesize(FILE_ZIP)))
        p(@sprintf("lettura di un blocco in memoria (Arrow.Table + collect di tutte le colonne, decompressione zstd): %.2f s (prima lettura, con compilazione: %.2f s)", t_uno, t_uno_primo))
        p(@sprintf("lettura di tutti i 64 blocchi in memoria (un thread): %.1f s; solo Arrow.Table (colonne pigre): %.1f s", t_tutto, t_map))
        p("memoria di un blocco in Julia: ", Base.format_bytes(mem_uno), "; di tutto il dataset: ", Base.format_bytes(mem_tutto))
    end
end

(abspath(PROGRAM_FILE) == @__FILE__) && main()
