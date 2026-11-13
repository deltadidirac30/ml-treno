# fase5/01_tratte.jl: passo 1, le 16384 tratte estratte sono quelle della campagna P9_D28_16384?
#
#   julia -t 8 --project=fase5 fase5/01_tratte.jl > ~/Documents/lavoro/ml_treno_dati/fase5_log/log_01.txt 2>&1
#
# 1a  manifest (16384 righe, route 1..16384, impronte dei design), poi a blocchi di 256 tratte lette con
#     leggi_tratte_materializzate (controllo dell'impronta della pendenza): 2·lunghezza del binario == km_viaggio
#     del registro (Arrow della fase 4), fermate, v_max, numero di limiti contro design e manifest, tempi di sosta.
# 1b  rivalutazione di 64 tratte × 4 coppie con lo stesso percorso della campagna (leggi_tratte_materializzate
#     con solo=, CampagnaSpec come esegui_campagna.jl con gli argomenti della campagna, esegui_campagna in
#     modalità griglia, andata&ritorno) e confronto riga per riga con il registro.
# Scrive in DIR_LOG: 01_tratte.txt, 01_tratte.csv (una riga per tratta), 01_campione.csv, 01_confronto.csv.

include(joinpath(@__DIR__, "comune.jl"))
using SHA, Random, Statistics

mkpath(DIR_LOG)
const OUT = open(joinpath(DIR_LOG, "01_tratte.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase5/01_tratte.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION)
say("TrainPowertrain: ", pathof(TP), "  commit ", TP.commit_codice())
anomalie = String[]
nota!(s) = (push!(anomalie, s); say("  ANOMALIA: ", s))

# ═════════════════════════ 1a: manifest ═════════════════════════════════════════
t_inizio = time()
say("\n[1a.1] manifest ", joinpath(DIR_TRATTE, "manifest.csv"))
lm = readlines(joinpath(DIR_TRATTE, "manifest.csv"))
commenti = [(i, l) for (i, l) in enumerate(lm) if startswith(l, '#')]
dati_m = [l for l in lm if !startswith(l, '#') && !isempty(strip(l))]
say("  righe: ", length(lm), "; di commento: ", length(commenti), " (righe ", join(first.(commenti), ", "), "); intestazioni+dati: ", length(dati_m))
for (i, l) in commenti
    say("  #", i, ": ", length(l) > 160 ? l[1:prevind(l, 161)] * " …" : l)
end
hman = split(dati_m[1], ',')
say("  intestazione: ", dati_m[1])
nint = count(l -> startswith(l, "route_id,"), dati_m)
say("  intestazioni nel manifest: ", nint, " (attesa 1)")
nint == 1 || nota!("manifest con $nint intestazioni")
M = [split(l, ',') for l in dati_m[2:end]]
col_m(c) = findfirst(==(c), hman)
man_rid = [parse(Int, r[col_m("route_id")]) for r in M]
say("  righe di dati: ", length(M), "; route_id = 1..16384 nell'ordine: ", man_rid == 1:NTRATTE,
    "; distinti: ", length(unique(man_rid)), "; campi per riga: ", unique(length.(M)))
man_rid == 1:NTRATTE || nota!("manifest: route_id non 1..16384 nell'ordine")
say("  generatore: ", Dict(g => count(r -> r[col_m("generatore")] == g, M) for g in unique(r[col_m("generatore")] for r in M)))
man = Dict(rid => (L_m = parse(Float64, r[col_m("L_m")]), nf = parse(Int, r[col_m("n_fermate_intermedie")]),
                   nl = parse(Int, r[col_m("n_limiti")]), vmax = parse(Float64, r[col_m("v_max_kmh")]),
                   sha = String(r[col_m("sha256_pendenza")])) for (rid, r) in zip(man_rid, M))
# accodamento: le righe prima e dopo il commento della riga 10244
icom = [i for (i, l) in commenti if occursin("accodate", l)]
if !isempty(icom)
    prima = count(l -> !startswith(l, '#') && !startswith(l, "route_id"), lm[1:icom[1]-1])
    say("  righe di dati prima del commento di accodamento: ", prima, " (route 1..", prima, ")")
end

say("\n[1a.2] impronte del design citate nel manifest contro i file del repo MATLAB")
dir_design = dirname(FILE_DESIGN)
for f in ("design_000001_010240.csv", "design_000001_016384.csv")
    b = read(joinpath(dir_design, f))
    s_lf = bytes2hex(sha256(b))
    s_crlf = bytes2hex(sha256(replace(String(copy(b)), "\n" => "\r\n")))
    citata = any(((i, l),) -> occursin(f, l) && (occursin(s_lf, l) || occursin(s_crlf, l)), commenti)
    nel_man = [match(r"sha256 del design = ([0-9a-f]{64})", l) for (i, l) in commenti if occursin(f, l)]
    hs = [m[1] for m in nel_man if m !== nothing]
    say("  ", f, ": sha256 sul Mac (LF) ", s_lf, "; con fine riga CRLF ", s_crlf)
    say("     nel manifest: ", join(hs, ", "), "  → ",
        any(==(s_lf), hs) ? "uguale al file (LF)" : any(==(s_crlf), hs) ? "uguale al file con CRLF (stesso contenuto, fine riga di Windows)" : "DIVERSA")
    any(h -> h == s_lf || h == s_crlf, hs) || nota!("$f: impronta del manifest diversa dal file anche con CRLF")
end
lf16 = readlines(FILE_DESIGN); lf10 = readlines(joinpath(dir_design, "design_000001_010240.csv"))
say("  prime 10241 righe (intestazione + 10240) del design da 16384 == design da 10240: ", lf16[1:10241] == lf10)

say("\n[1a.3] design ", FILE_DESIGN)
hdes, des = leggi_design()
say("  righe: ", length(des["route_id"]), "; route_id = 1..16384: ", des["route_id"] == 1:NTRATTE)
ta = Arrow.Table(joinpath(DIR_ARROW, "tratte.arrow"))
uguali = [c for c in hdes if all(isequal.(collect(getproperty(ta, Symbol(c))), des[c]))]
say("  colonne uguali (isequal, al bit) a tratte.arrow della fase 4: ", length(uguali), " su ", length(hdes))
length(uguali) == length(hdes) || nota!("design diverso da tratte.arrow nelle colonne $(setdiff(hdes, uguali))")
errD29 = collect(ta.errore_D29)
say("  tratte con errore_D29 in tratte.arrow: ", findall(errD29))

# ═════════════════════════ 1a: le tratte, a blocchi di 256 ════════════════════════
say("\n[1a.4] tratte lette a blocchi di 256 con leggi_tratte_materializzate (impronta contro il manifest)")
const COLS = [:route_id, :L_m, :km_viaggio_registro, :km_viaggio_righe, :km_viaggio_valori, :ok_km,
              :n_fermate, :n_limiti, :v_max, :ok_design, :ok_manifest, :ok_struttura, :scarto_L_design_m]
righe_t = Vector{NamedTuple}(undef, NTRATTE)
t_lettura = 0.0
for k in 1:NBLOCCHI
    global t_lettura
    t0 = time()
    tr = tratte_blocco(k)
    t_lettura += time() - t0
    # km_viaggio del registro (fase 4): costante nella tratta, NaN solo nelle righe di errore
    tb = Arrow.Table(file_arrow(k))
    kv = Dict{Int,Vector{Float64}}()
    for (r, x) in zip(tb.tratta, tb.km_viaggio)
        isnan(x) || push!(get!(kv, Int(r), Float64[]), x)
    end
    sort(collect(keys(kv))) == collect(route_blocco(k)) || nota!("blocco $k: route dell'Arrow diverse da $(route_blocco(k))")
    for t in tr
        rid = rid_di(t.id); cp = t.cp
        L = cp.lunghezza_binario_andata
        st = cp.posizione_stazioni
        nf = length(st) - 2; nl = length(cp.v_max_l); vmax = maximum(cp.v_max_l)
        v = kv[rid]; vals = unique(v)
        ok_km = length(vals) == 1 && vals[1] === cp.lunghezza_binario_andata * 2.0 / 1000.0
        i = rid
        ok_des = nf == des["n_stops"][i] && vmax == des["v_max_kmh"][i] && nl == des["n_vlim_segments"][i]
        mm = man[rid]
        ok_man = L == mm.L_m && nf == mm.nf && nl == mm.nl && vmax == mm.vmax && t.sha256 == mm.sha
        scal = Dict(split(l, ',')[1] => split(l, ',')[2] for l in readlines(joinpath(DIR_TRATTE, t.id, "tratta_scalari.csv")))
        ok_str = isinteger(L) && cp.tipo_profilo === :pendenza_metro && length(cp.pendenze_note) == Int(L) + 1 &&
                 st[1] == 0 && st[end] == L && issorted(st) && length(cp.s_max_l) == nl + 1 &&
                 cp.s_max_l[1] == 0 && cp.s_max_l[end] == L && cp.tempo_fermata == 120 && cp.tempo_capolinea == 300 &&
                 parse(Int, scal["route_id"]) == rid
        righe_t[rid] = (route_id = rid, L_m = L, km_viaggio_registro = vals[1], km_viaggio_righe = length(v),
                        km_viaggio_valori = length(vals), ok_km = ok_km, n_fermate = nf, n_limiti = nl, v_max = vmax,
                        ok_design = ok_des, ok_manifest = ok_man, ok_struttura = ok_str,
                        scarto_L_design_m = L - 1000 * des["L_km"][i])
    end
    tr = nothing; tb = nothing
    k % 8 == 0 && say(@sprintf("  blocco %2d/64: lettura cumulata %.1f s", k, t_lettura))
    GC.gc()
end
T = righe_t
say(@sprintf("  lettura delle 16384 tratte (con l'impronta): %.1f s, %.2f ms per tratta", t_lettura, 1000t_lettura / NTRATTE))
say("  tratte lette: ", count(i -> isassigned(T, i), 1:NTRATTE), " (l'impronta della pendenza coincide con il manifest in tutte: altrimenti errore)")
say("  2·L/1000 === km_viaggio del registro (un solo valore per tratta): ", count(r -> r.ok_km, T), " / ", NTRATTE)
say("    righe del registro con km_viaggio per tratta: min ", minimum(r -> r.km_viaggio_righe, T), ", max ", maximum(r -> r.km_viaggio_righe, T),
    "; tratte con < 288 righe: ", [(r.route_id, r.km_viaggio_righe) for r in T if r.km_viaggio_righe < 288])
say("  fermate, v_max, numero di limiti == design: ", count(r -> r.ok_design, T), " / ", NTRATTE)
say("  L, fermate, limiti, v_max, impronta == manifest: ", count(r -> r.ok_manifest, T), " / ", NTRATTE)
say("  struttura (L intero, pendenza L+1 valori, stazioni 0..L, limiti, soste 120/300 s, route_id in tratta_scalari): ",
    count(r -> r.ok_struttura, T), " / ", NTRATTE)
sc = [r.scarto_L_design_m for r in T]
say(@sprintf("  L − 1000·L_km del design: da %.4f a %.4f m (L è intero in metri)", minimum(sc), maximum(sc)))
for (c, s) in ((:ok_km, "km_viaggio"), (:ok_design, "design"), (:ok_manifest, "manifest"), (:ok_struttura, "struttura"))
    bad = [r.route_id for r in T if !getproperty(r, c)]
    isempty(bad) || nota!("$s non coincide in $(length(bad)) tratte: $(first(bad, 20))")
end
open(joinpath(DIR_LOG, "01_tratte.csv"), "w") do io
    println(io, join(COLS, ','))
    for r in T
        println(io, join((r[c] isa Float64 ? @sprintf("%.17g", r[c]) : string(r[c]) for c in COLS), ','))
    end
end
say(@sprintf("  [1a] tempo: %.1f s", time() - t_inizio))

# ═════════════════════════ 1b: rivalutazione del campione ═══════════════════════════
say("\n[1b] rivalutazione di un campione con lo stesso percorso della campagna")
const SEME = 20261113
rng = Xoshiro(SEME)
cop = Arrow.Table(joinpath(DIR_ARROW, "coppie.arrow"))
lc = readlines(FILE_COPPIE); lc[1] == "m,n" || error("intestazione di $FILE_COPPIE")
coppie_csv = [(parse(Float64, split(x, ',')[1]), parse(Float64, split(x, ',')[2])) for x in lc[2:end] if !isempty(x)]
length(coppie_csv) == 288 && all(i -> coppie_csv[i][1] === cop.m[i] && coppie_csv[i][2] === cop.n[i], 1:288) ||
    error("campionamento_288.csv diverso da coppie.arrow")
c_m0 = findall(collect(cop.sola_batteria)); c_d1 = findall(==(1), collect(cop.intervallo_D25))
say("  coppie a m = 0: ", length(c_m0), "; nella prima fascia D25 [0,03; 0,0957): ", length(c_d1))
campione = Tuple{Int,Vector{Int}}[]
for g in 1:16
    pool = [r for r in ((g-1)*1024+1):(g*1024) if !(r in ROUTE_D29)]
    for r in sort(pool[randperm(rng, length(pool))[1:4]])
        a = rand(rng, c_m0); b = rand(rng, c_d1)
        resto = setdiff(1:288, [a, b])
        c, d = resto[randperm(rng, length(resto))[1:2]]
        push!(campione, (r, sort([a, b, c, d])))
    end
end
open(joinpath(DIR_LOG, "01_campione.csv"), "w") do io
    println(io, "route_id,coppia,m,n,sola_batteria,intervallo_D25")
    for (r, cc) in campione, c in cc
        println(io, r, ',', c, ',', lc[c+1], ',', cop.sola_batteria[c], ',', cop.intervallo_D25[c])
    end
end
say("  seme ", SEME, " (Xoshiro): ", length(campione), " tratte × 4 coppie (elenco in 01_campione.csv)")
say("  route: ", join(first.(campione), ' '))

# configurazione: come esegui_campagna.jl con gli argomenti della campagna (DOE_16384.md §3.4: modalita=griglia,
# coppie=campionamento_288.csv, direzioni=andata&ritorno, nessun'altra chiave → i default dello script)
cfg = ConfigModello(; modello = Symbol("corretta"), soglia_cambio_carico = parse(Float64, "1e-9"), D3 = parse(Bool, "true"),
                    D5 = Symbol("nessuna"), costi = ParametriCosto())
isdir(DIR_RIVAL) && rm(DIR_RIVAL; recursive = true)        # cartella di lavoro di questo script
mkpath(DIR_RIVAL)
t0 = time(); t_val = 0.0; nval = 0
dirs = String[]
for (r, cc) in campione
    global t_val, nval
    tr = leggi_tratte_materializzate(DIR_TRATTE; solo = [r])
    spec = CampagnaSpec(tratte = tr, coppie = [coppie_csv[c] for c in cc], cartella = joinpath(DIR_RIVAL, @sprintf("route_%06d", r)),
                        direzioni = String.(split("andata&ritorno", ',')), config = cfg, peso_a_carico = parse(Float64, "195000"),
                        modalita = :griglia)
    res = redirect_stdout(devnull) do
        esegui_campagna(spec)
    end
    t_val += res.tempo_s; nval += res.valutati
    push!(dirs, spec.cartella)
end
say(@sprintf("  %d valutazioni in %.1f s di parete (%.1f s con letture e scritture)", nval, t_val, time() - t0))

# config.txt contro quello della campagna
cfg_camp = Set(strip(read(file_config_campagna(k), String)) for k in 1:NBLOCCHI)
cfg_noi = Set(strip(read(joinpath(d, "config.txt"), String)) for d in dirs)
say("  config.txt: ", length(cfg_camp), " distinto nella campagna, ", length(cfg_noi), " qui; uguali carattere per carattere: ", cfg_camp == cfg_noi)
cfg_camp == cfg_noi || nota!("config.txt diverso da quello della campagna")
say("    ", first(cfg_noi))

# confronto riga per riga con il registro (Arrow della fase 4)
diz = Arrow.Table(joinpath(DIR_ARROW, "dizionari.arrow"))
decod = Dict{String,Dict{Int,String}}()
for (c, i, s) in zip(diz.campo, diz.codice, diz.testo); get!(decod, c, Dict{Int,String}())[Int(i)] = s; end
INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
blocchi = Dict{Int,Any}()
blocco_di(r) = get!(() -> Arrow.Table(file_arrow(cld(r, TRATTE_BLOCCO))), blocchi, cld(r, TRATTE_BLOCCO))
nomi_arrow = nothing
conf = NamedTuple[]
ndiff_testo = 0; nrighe = 0
maxulp = Dict{String,Int}(); nonbit = Dict{String,Int}()
valori = Dict{String,Vector{Tuple{Float64,Float64}}}()     # (registro, rivalutato) per colonna
for (r, cc) in campione
    global nomi_arrow, ndiff_testo, nrighe
    tb = blocco_di(r)
    nomi_arrow === nothing && (nomi_arrow = String.(Arrow.names(tb)))
    reg = readlines(joinpath(DIR_RIVAL, @sprintf("route_%06d", r), "registro.csv"))
    reg[1] == TP.INTESTAZIONE_REGISTRO || error("intestazione del registro rivalutato")
    length(reg) - 1 == 4 || nota!("route $r: $(length(reg)-1) righe nel registro rivalutato")
    tr_col = tb.tratta; cp_col = tb.coppia
    for l in reg[2:end]
        c = split(l, ',')
        length(c) == length(INTEST) || error("riga con $(length(c)) campi")
        f = Dict(INTEST[j] => c[j] for j in eachindex(INTEST))
        m = parse(Float64, f["m"]); n = parse(Float64, f["n"])
        k = findfirst(i -> coppie_csv[i] === (m, n), 1:288)
        k in cc || error("route $r: coppia ($m, $n) non nel campione")
        i = findfirst(j -> tr_col[j] == r && cp_col[j] == k, eachindex(tr_col))
        nrighe += 1
        dtesto = String[]
        for (col, nome) in (("stato", "stato"), ("tipo_esito", "tipo_esito"), ("motivo", "motivo"))
            atteso = decod[nome][Int(getproperty(tb, Symbol(col))[i])]
            col == "motivo" && atteso == "" && (atteso = "")
            String(f[col]) == atteso || push!(dtesto, "$col: $(f[col]) ≠ $atteso")
        end
        snc = getproperty(tb, :storage_non_convergente)[i]
        (snc === missing ? f["storage_non_convergente"] == "NaN" : f["storage_non_convergente"] == string(snc)) ||
            push!(dtesto, "storage_non_convergente: $(f["storage_non_convergente"]) ≠ $snc")
        f["tratta"] == @sprintf("route_%06d", r) && f["direzione"] == "andata&ritorno" || push!(dtesto, "tratta/direzione")
        f["caso"] == @sprintf("route_%06d_ar_m%.6g_n%.6g", r, m, n) || push!(dtesto, "caso")
        ndiff_testo += !isempty(dtesto)
        nb = 0; mu = 0; peggiore = ""
        for col in nomi_arrow
            col in ("tratta", "coppia", "stato", "motivo", "tipo_esito", "storage_non_convergente", "tempo_s") && continue
            a = Float64(getproperty(tb, Symbol(col))[i]); b = parse(Float64, f[col])
            push!(get!(valori, col, Tuple{Float64,Float64}[]), (a, b))
            u = ulp_dist(a, b)
            maxulp[col] = max(get(maxulp, col, 0), u)
            if u > 0
                nb += 1; nonbit[col] = get(nonbit, col, 0) + 1
                u > mu && (mu = u; peggiore = col)
            end
        end
        push!(conf, (route_id = r, coppia = k, m = m, n = n, stato = String(f["stato"]), tipo_esito = String(f["tipo_esito"]),
                     testo_uguale = isempty(dtesto), differenze_testo = join(dtesto, "; "), colonne_non_al_bit = nb,
                     ulp_max = mu, colonna_ulp_max = peggiore, costo = parse(Float64, f["costo"])))
    end
end
open(joinpath(DIR_LOG, "01_confronto.csv"), "w") do io
    ks = keys(conf[1]); println(io, join(ks, ','))
    for x in conf; println(io, join((v isa Float64 ? @sprintf("%.17g", v) : replace(string(v), ',' => ';') for v in values(x)), ',')); end
end
ncol = length(nomi_arrow) - 7
say("  righe confrontate: ", nrighe, " (attese 256); colonne numeriche confrontate: ", ncol, " (tutte tranne tempo_s)")
say("  stato, tipo_esito, motivo, storage_non_convergente, caso uguali: ", nrighe - ndiff_testo, " / ", nrighe)
say("  stati: ", Dict(s => count(x -> x.stato == s, conf) for s in unique(x.stato for x in conf)),
    "; tipo_esito: ", Dict(s => count(x -> x.tipo_esito == s, conf) for s in unique(x.tipo_esito for x in conf)))
nb_righe = count(x -> x.colonne_non_al_bit > 0, conf)
say("  righe con tutte le colonne numeriche al bit (=== , NaN compresi): ", nrighe - nb_righe, " / ", nrighe)
if !isempty(nonbit)
    say("  colonne non al bit (righe, ULP massimi):")
    for (col, nr) in sort(collect(nonbit); by = x -> -x[2])
        say(@sprintf("    %-34s %4d righe, max %s ULP", col, nr, maxulp[col] == typemax(Int) ? "∞ (NaN/Inf diverso)" : string(maxulp[col])))
    end
end
umax = maximum(x -> x.ulp_max, conf)
say("  ULP massimi su tutte le righe e colonne: ", umax == typemax(Int) ? "∞" : umax,
    " (gli ULP enormi vengono da colonne vicine a zero: residuo_kWh, batt_non_erogata_kWh, …)")
ndiff_testo > 0 && nota!("$ndiff_testo righe con stato/esito/motivo diversi")

# Criterio accettato il 13/11/2026 (registri del PC Windows, rivalutazione sul Mac M4: FMA, vedi fase 4):
#  - testo (stato, tipo_esito, motivo, storage_non_convergente, caso) uguale;
#  - grandezze discrete e di sola tratta/coppia al bit;
#  - NaN/Inf negli stessi posti;
#  - colonne continue: |Δ| / scala ≤ 1e-10, scala = max |valore| finito della colonna nelle 256 righe del registro.
const DISCRETE = ["m", "n", "m_richiesta", "durata_viaggio_s", "n_viaggi_giorno", "n_viaggi_anno", "km_viaggio", "km_anno",
                  "num_repl_FC", "num_repl_batt", "storage_iterazioni", "accensioni_FC", "n_celle_FC", "n_stringhe_batteria",
                  "vita_FC_tetto", "vita_batt_limite_calendario", "sostituzione_FC_saltata", "scarica_s"]
const TOLL_REL = 1e-10
say("\n  criterio accettato: testo uguale; discrete al bit; NaN/Inf negli stessi posti; continue |Δ|/scala ≤ ", TOLL_REL)
crit = NamedTuple[]
for (col, v) in sort(collect(valori); by = first)
    fin = [abs(a) for (a, b) in v if isfinite(a)]
    scala_c = isempty(fin) ? 0.0 : maximum(fin)
    stessi_nonfiniti = all(((a, b),) -> isfinite(a) == isfinite(b) && (isfinite(a) || isequal(a, b)), v)
    dmax = maximum((abs(a - b) for (a, b) in v if isfinite(a) && isfinite(b)); init = 0.0)
    nd = count(((a, b),) -> !isequal(a, b), v)
    rel = scala_c > 0 ? dmax / scala_c : (dmax > 0 ? Inf : 0.0)
    ok = stessi_nonfiniti && (col in DISCRETE ? nd == 0 : rel <= TOLL_REL)
    push!(crit, (colonna = col, discreta = col in DISCRETE, righe_diverse = nd, max_abs = dmax, scala = scala_c, rel_scala = rel,
                 nonfiniti_uguali = stessi_nonfiniti, ok = ok))
end
open(joinpath(DIR_LOG, "01_criterio.csv"), "w") do io
    println(io, join(keys(crit[1]), ','))
    for x in crit; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end
ko = [x for x in crit if !x.ok]
say("  colonne discrete al bit: ", count(x -> x.discreta && x.ok, crit), " / ", count(x -> x.discreta, crit),
    "; colonne con NaN/Inf negli stessi posti: ", count(x -> x.nonfiniti_uguali, crit), " / ", length(crit))
say(@sprintf("  colonne continue: max |Δ|/scala = %.3e (%s); colonne al bit in tutte le righe: %d / %d",
             maximum(x -> x.discreta ? 0.0 : x.rel_scala, crit), crit[argmax([x.discreta ? 0.0 : x.rel_scala for x in crit])].colonna,
             count(x -> x.righe_diverse == 0, crit), length(crit)))
say("  colonne fuori criterio: ", isempty(ko) ? "nessuna" : join((x.colonna for x in ko), ", "), "  (01_criterio.csv)")
isempty(ko) || nota!("colonne fuori dal criterio accettato: $(join((x.colonna for x in ko), ", "))")
esito = ndiff_testo == 0 && isempty(ko)
say("\nESITO 1b: ", esito ? "le righe coincidono con il registro secondo il criterio accettato (al bit: $(nrighe - nb_righe) righe su $nrighe; scarti da macchina ≤ $(TOLL_REL) della scala)" :
                         "NON COINCIDONO secondo il criterio accettato: vedi sopra")
say(@sprintf("\ntempo totale: %.1f s", time() - t_inizio))
say("anomalie: ", isempty(anomalie) ? "nessuna" : "")
foreach(a -> say("  - ", a), anomalie)
close(OUT)
