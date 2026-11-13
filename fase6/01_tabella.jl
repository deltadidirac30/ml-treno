# fase6/01_tabella.jl: passo 2 del surrogato, la tabella di addestramento (nessun addestramento).
#
#   julia -t 8 --project=fase6 fase6/01_tabella.jl > ~/Documents/lavoro/ml_treno_dati/fase6_log/log_01.txt 2>&1
#
# Una riga per caso simulato della campagna P9_D28_16384: (tratta, coppia) con le 66 caratteristiche della tratta
# (fase5, caratteristiche.arrow), m, n, le grandezze da imparare, l'esito vero. Tolte solo le 69 righe in errore
# (stato = error, route 2366 e 14664); le route 2366, 14664 e 13258 sono segnate.
# Divisione per tratta sui 16 gruppi Sobol da 1024 route ((g-1)·1024+1 … g·1024): 12 addestramento, 2 validazione,
# 2 test, scelti a caso con seme fisso (decisione del 13/11).
#
# Uscita in ~/Documents/lavoro/ml_treno_dati/P9_D28_16384/tabella/: addestramento.arrow, validazione.arrow, test.arrow
# (zstd, un record batch per gruppo). Controlli in fase6_log: 01_tabella.txt, 01_gruppi.csv, 01_confronto_gruppi.csv.

include(joinpath(@__DIR__, "..", "fase5", "comune.jl"))     # percorsi della campagna e delle caratteristiche
using Random, Statistics, Tables

const LOG6 = joinpath(BASE_DATI, "fase6_log"); mkpath(LOG6)
const DIR_TAB = joinpath(BASE_DATI, "P9_D28_16384", "tabella"); mkpath(DIR_TAB)
const OUT = open(joinpath(LOG6, "01_tabella.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase6/01_tabella.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION)
anomalie = String[]
nota!(s) = (push!(anomalie, s); say("  ANOMALIA: ", s))
t_inizio = time()

# ── divisione ────────────────────────────────────────────────────────────────────
const SEME = 20261113
const NGRUPPI = 16
const SPLIT = ["addestramento", "validazione", "test"]
perm = randperm(Xoshiro(SEME), NGRUPPI)
split_di_gruppo = zeros(Int8, NGRUPPI)
split_di_gruppo[perm[1:12]] .= 1; split_di_gruppo[perm[13:14]] .= 2; split_di_gruppo[perm[15:16]] .= 3
gruppo_di(r) = cld(r, 1024)
say("\n[1] divisione per tratta, seme $SEME (Xoshiro, randperm dei 16 gruppi): ")
for s in 1:3
    say("  ", rpad(SPLIT[s], 14), "gruppi ", join(sort(findall(==(s), split_di_gruppo)), ", "))
end
open(joinpath(LOG6, "01_gruppi.csv"), "w") do io
    println(io, "gruppo,route_da,route_a,insieme")
    for g in 1:NGRUPPI; println(io, g, ',', (g-1)*1024+1, ',', g*1024, ',', SPLIT[split_di_gruppo[g]]); end
end

# ── caratteristiche e informazioni per tratta ───────────────────────────────────
ct = Arrow.Table(FILE_CARATT)
NOMI_X = [String(c) for c in Arrow.names(ct) if c != :route_id]
length(NOMI_X) == 66 && collect(ct.route_id) == 1:NTRATTE || error("caratteristiche.arrow inatteso")
X = reduce(hcat, (collect(getproperty(ct, Symbol(c))) for c in NOMI_X))
const ROUTE_OLTRE_12H = 13258
segnalata = zeros(Int8, NTRATTE)               # 0 nessuna, 1 errore D29 (righe in errore tolte), 2 oltre 12 h
for r in ROUTE_D29; segnalata[r] = 1; end
segnalata[ROUTE_OLTRE_12H] = 2
ria = Arrow.Table(joinpath(DIR_ARROW, "tratte_riassunto.arrow"))
collect(ria.tratta) == 1:NTRATTE || error("tratte_riassunto non in ordine di route")
regime_migliore = collect(ria.regime_migliore)    # 1 sola batteria, 2 ibrido

# ── colonne ─────────────────────────────────────────────────────────────────────
# grandezze da imparare (fase 4, §3.3) e il C-rate per la regola D3 a posteriori
const Y = ["durata_viaggio_s", "massa_serbatoio_kg", "H2_cons_kg", "SOC_end", "scarica_s", "vita_batt_cicli_viaggi",
           "vita_FC_viaggi", "vita_FC_f1_ore", "C_rate_scarica_max"]
# per i passi successivi (costo vero, fattibilità): non si imparano
const ALTRE = ["costo", "total_cost_EUR_km"]
say("\n[2] colonne: tratta, coppia, gruppo, insieme, segnalata, m, n, 66 x_, y_ (", join(Y, ", "),
    "), stato, d3, tipo_esito, D28, SOC_end_ricavato, ", join(ALTRE, ", "))

# ── costruzione per gruppo ───────────────────────────────────────────────────────
soc_scarto = 0.0; soc_n = 0
d3_regola = zeros(Int, 3, 2, 2)        # insieme × d3 vero (1 no, 2 sì) × C-rate > 20 (1 no, 2 sì)
righe_tolte = 0
parti = Vector{Any}(undef, NGRUPPI)
for g in 1:NGRUPPI
    global soc_scarto, soc_n, righe_tolte
    cols = Dict{String,Vector}()
    for k in ((g-1)*4+1):(g*4)               # 4 blocchi Arrow da 256 tratte
        t = Arrow.Table(file_arrow(k))
        keep = findall(!=(Int8(3)), t.stato)
        righe_tolte += length(t.stato) - length(keep)
        app(c, v) = append!(get!(cols, c, similar(v, 0)), v)
        app("tratta", t.tratta[keep]); app("coppia", t.coppia[keep])
        app("m", t.m[keep]); app("n", t.n[keep])
        app("stato", t.stato[keep]); app("tipo_esito", t.tipo_esito[keep])
        app("D28", Bool.(coalesce.(t.storage_non_convergente[keep], false)))
        for c in vcat(Y, ALTRE, ["vincolo_soc_pt"]); app(c, collect(getproperty(t, Symbol(c)))[keep]); end
    end
    tr = Int.(cols["tratta"]); st = cols["stato"]
    # SOC_end dei rejected (D3) dal vincolo: vincolo_soc_pt = 100·(0,2 − SOC_end) (fase 4)
    soc = cols["SOC_end"]; v = cols["vincolo_soc_pt"]
    ric = 0.2 .- v ./ 100
    comp = st .== 1
    soc_scarto = max(soc_scarto, maximum(abs.(ric[comp] .- soc[comp]))); soc_n += count(comp)
    deriv = st .== 2
    all(isnan, soc[deriv]) || nota!("gruppo $g: SOC_end non NaN in righe rejected")
    soc[deriv] = ric[deriv]
    s = split_di_gruppo[g]
    d3 = st .== 2
    cr = cols["C_rate_scarica_max"] .> 20
    for i in eachindex(d3); d3_regola[s, d3[i] + 1, cr[i] + 1] += 1; end
    nr = length(tr)
    tab = (; tratta = Int32.(tr), coppia = cols["coppia"], gruppo = fill(Int8(g), nr), insieme = fill(s, nr),
           segnalata = segnalata[tr], m = cols["m"], n = cols["n"],
           (Symbol(c) => X[tr, j] for (j, c) in enumerate(NOMI_X))...,
           (Symbol("y_" * c) => cols[c] for c in Y)...,
           stato = st, d3 = d3, tipo_esito = cols["tipo_esito"], fattibile = cols["tipo_esito"] .== 1, D28 = cols["D28"],
           SOC_end_ricavato = deriv,
           (Symbol(c) => cols[c] for c in ALTRE)...)
    parti[g] = tab
    say(@sprintf("  gruppo %2d (%s): %d righe, %d tratte", g, SPLIT[s], nr, length(unique(tr))))
end
say(@sprintf("  righe tolte (stato = error): %d", righe_tolte))
righe_tolte == 69 || nota!("righe in errore tolte: $righe_tolte invece di 69")
say(@sprintf("  SOC_end ricavato da vincolo_soc_pt, controllo sulle %d completed: max |scarto| %.2e", soc_n, soc_scarto))
soc_scarto < 1e-9 || nota!("SOC_end ricavato con scarto $soc_scarto")

# ── scrittura ────────────────────────────────────────────────────────────────────
say("\n[3] scrittura (zstd, un record batch per gruppo) in ", DIR_TAB)
meta = Dict("sorgente" => "fase6/01_tabella.jl $(now())",
            "divisione" => "16 gruppi Sobol da 1024 route; seme $SEME; " *
                           join(("$(SPLIT[s]): gruppi $(join(sort(findall(==(s), split_di_gruppo)), ','))" for s in 1:3), "; "),
            "codici" => "insieme 1 addestramento 2 validazione 3 test; stato 1 completed 2 rejected (D3); tipo_esito 1 fattibile 2 piccola 3 pesante 4 mista; segnalata 0 no 1 errore D29 (righe in errore tolte) 2 oltre 12 h (13258)",
            "note" => "x_ = caratteristiche.arrow (fase5); y_ = registro; SOC_end dei rejected ricavato da vincolo_soc_pt (SOC_end_ricavato); H2_cons_kg NaN nei rejected; vite FC +Inf a m = 0")
for s in 1:3
    t0 = time()
    gs = sort(findall(==(s), split_di_gruppo))
    f = joinpath(DIR_TAB, SPLIT[s] * ".arrow")
    Arrow.write(f, Tables.partitioner(parti[g] for g in gs); compress = :zstd, metadata = meta)
    say(@sprintf("  %-14s %6.1f MiB, %.1f s", SPLIT[s] * ".arrow", filesize(f) / 2^20, time() - t0))
end

# ── controlli ────────────────────────────────────────────────────────────────────
say("\n[4] controlli sui file riletti")
T = [Arrow.Table(joinpath(DIR_TAB, s * ".arrow")) for s in SPLIT]
tratte_di = [Set(Int.(t.tratta)) for t in T]
say("  righe: ", join((@sprintf("%s %s", SPLIT[s], fmt(length(T[s].tratta))) for s in 1:3), ", "),
    "; totale ", fmt(sum(length(t.tratta) for t in T)), " (attese 4.718.523)")
sum(length(t.tratta) for t in T) == 4_718_523 || nota!("totale righe diverso da 4.718.523")
say("  tratte: ", join((@sprintf("%s %d", SPLIT[s], length(tratte_di[s])) for s in 1:3), ", "),
    "; in comune tra due insiemi: ", length(intersect(tratte_di[1], tratte_di[2])) + length(intersect(tratte_di[1], tratte_di[3])) +
                                     length(intersect(tratte_di[2], tratte_di[3])))
# 288 righe per tratta (meno le righe in errore), ogni (tratta, coppia) una volta
for (s, t) in enumerate(T)
    cnt = Dict{Int,Int}()
    for r in t.tratta; cnt[r] = get(cnt, r, 0) + 1; end
    diverse = [(r, c) for (r, c) in cnt if c != 288]
    coppie_uniche = length(Set(zip(t.tratta, t.coppia))) == length(t.tratta)
    say("  ", rpad(SPLIT[s], 14), "tratte con un numero di righe diverso da 288: ", sort(diverse), "; (tratta, coppia) uniche: ", coppie_uniche)
    coppie_uniche || nota!("$(SPLIT[s]): (tratta, coppia) ripetute")
end
# caratteristiche uguali a caratteristiche.arrow (prima riga di ogni tratta)
let ok = true
    for t in T
        tr = Int.(t.tratta)
        first_i = Dict{Int,Int}(); for i in eachindex(tr); get!(first_i, tr[i], i); end
        for (j, c) in enumerate(NOMI_X)
            v = getproperty(t, Symbol(c))
            ok &= all(v[i] === X[r, j] for (r, i) in first_i)
        end
    end
    say("  caratteristiche uguali al bit a caratteristiche.arrow: ", ok)
    ok || nota!("caratteristiche diverse da caratteristiche.arrow")
end
# NaN e Inf per colonna e stato
say("  NaN / +Inf nelle colonne y_ (completed | rejected), su tutti gli insiemi:")
for c in Y
    v = reduce(vcat, (collect(getproperty(t, Symbol("y_" * c))) for t in T)); st = reduce(vcat, (collect(t.stato) for t in T))
    m0 = reduce(vcat, (collect(t.m) for t in T)) .== 0
    f(sel, p) = count(i -> sel[i] && p(v[i]), eachindex(v))
    say(@sprintf("    %-24s completed: NaN %7d, Inf %7d (di cui a m = 0: %d) | rejected: NaN %6d, Inf %6d", c,
                 f(st .== 1, isnan), f(st .== 1, isinf), f((st .== 1) .& m0, isinf), f(st .== 2, isnan), f(st .== 2, isinf)))
end
nx = sum(count(x -> !isfinite(x), getproperty(t, Symbol(c))) for t in T for c in NOMI_X)
say("  NaN/Inf nelle 66 caratteristiche: ", nx)

# regola D3 a posteriori
say("\n[5] regola D3 a posteriori: rejected (D3) contro C_rate_scarica_max > 20")
for s in 1:3
    a = d3_regola[s, :, :]
    say(@sprintf("  %-14s D3 e C>20: %6d | D3 e C≤20: %4d | non D3 e C>20: %d | non D3 e C≤20: %8d  → D3 ritrovati %.2f%%",
                 SPLIT[s], a[2, 2], a[2, 1], a[1, 2], a[1, 1], 100 * a[2, 2] / (a[2, 1] + a[2, 2])))
end

# confronto tra gli insiemi
say("\n[6] gli insiemi si somigliano?")
function quota(t, f); v = f(t); count(v) / length(v); end
for s in 1:3
    t = T[s]; trs = sort(collect(tratte_di[s]))
    say(@sprintf("  %-14s completed %.2f%%, rejected D3 %.2f%%, fattibili %.2f%%, D28 %.3f%%; tratte con migliore a sola batteria %.1f%%",
                 SPLIT[s], 100quota(t, t -> t.stato .== 1), 100quota(t, t -> t.stato .== 2), 100quota(t, t -> t.fattibile),
                 100quota(t, t -> t.D28), 100 * count(r -> regime_migliore[r] == 1, trs) / length(trs)))
end
# KS: massima distanza tra le funzioni di ripartizione (caratteristiche sulle tratte, y_ sulle righe completed)
function ks(a, b)
    a = sort(filter(isfinite, a)); b = sort(filter(isfinite, b))
    (isempty(a) || isempty(b)) && return NaN
    i = j = 1; d = 0.0
    while i <= length(a) && j <= length(b)
        x = min(a[i], b[j])
        while i <= length(a) && a[i] <= x; i += 1; end
        while j <= length(b) && b[j] <= x; j += 1; end
        d = max(d, abs((i - 1) / length(a) - (j - 1) / length(b)))
    end
    return d
end
righe_ks = NamedTuple[]
tr_s = [sort(collect(tratte_di[s])) for s in 1:3]
for (j, c) in enumerate(NOMI_X)
    push!(righe_ks, (colonna = c, livello = "tratta", ks_validazione = ks(X[tr_s[2], j], X[tr_s[1], j]),
                     ks_test = ks(X[tr_s[3], j], X[tr_s[1], j]),
                     mediana_add = median(X[tr_s[1], j]), mediana_val = median(X[tr_s[2], j]), mediana_test = median(X[tr_s[3], j])))
end
for c in Y
    v = [collect(getproperty(T[s], Symbol("y_" * c)))[T[s].stato .== 1] for s in 1:3]
    med(x) = (y = filter(isfinite, x); isempty(y) ? NaN : median(y))
    push!(righe_ks, (colonna = "y_" * c, livello = "riga completed", ks_validazione = ks(v[2], v[1]), ks_test = ks(v[3], v[1]),
                     mediana_add = med(v[1]), mediana_val = med(v[2]), mediana_test = med(v[3])))
end
open(joinpath(LOG6, "01_confronto_gruppi.csv"), "w") do io
    println(io, join(keys(righe_ks[1]), ','))
    for r in righe_ks; println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(r)), ',')); end
end
kx = [r for r in righe_ks if r.livello == "tratta"]; ky = [r for r in righe_ks if r.livello != "tratta"]
# soglia di riferimento: KS al 99% per due campioni di 2048 e 12288 tratte ≈ 1,63·sqrt(1/2048 + 1/12288)
soglia = 1.63 * sqrt(1 / 2048 + 1 / 12288)
say(@sprintf("  caratteristiche (KS tra tratte, contro l'addestramento): max validazione %.4f (%s), max test %.4f (%s); soglia al 99%% per campioni casuali %.4f",
             maximum(r -> r.ks_validazione, kx), kx[argmax([r.ks_validazione for r in kx])].colonna,
             maximum(r -> r.ks_test, kx), kx[argmax([r.ks_test for r in kx])].colonna, soglia))
say("  caratteristiche oltre la soglia: validazione ", count(r -> r.ks_validazione > soglia, kx), ", test ", count(r -> r.ks_test > soglia, kx))
for r in ky
    say(@sprintf("    %-26s KS validazione %.4f, test %.4f; mediane add/val/test %.4g / %.4g / %.4g", r.colonna, r.ks_validazione, r.ks_test,
                 r.mediana_add, r.mediana_val, r.mediana_test))
end
for c in ["x_L_km", "x_slope_rms", "x_n_fermate", "x_vlim_mean", "x_dislivello_m"]
    r = kx[findfirst(x -> x.colonna == c, kx)]
    say(@sprintf("    %-26s mediane add/val/test %.4g / %.4g / %.4g (KS %.4f / %.4f)", c, r.mediana_add, r.mediana_val, r.mediana_test,
                 r.ks_validazione, r.ks_test))
end
say("  tratte segnalate per insieme: ", join(("$r ($(SPLIT[split_di_gruppo[gruppo_di(r)]]))" for r in (2366, 14664, 13258)), ", "))

say(@sprintf("\ntempo totale: %.1f s", time() - t_inizio))
say("anomalie: ", isempty(anomalie) ? "nessuna" : "")
foreach(a -> say("  - ", a), anomalie)
close(OUT)
