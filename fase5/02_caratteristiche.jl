# fase5/02_caratteristiche.jl: passo 2, le 66 caratteristiche del surrogato sulle 16384 tratte DoE della campagna.
#
#   julia -t 8 --project=fase5 fase5/02_caratteristiche.jl > ~/Documents/lavoro/ml_treno_dati/fase5_log/log_02.txt 2>&1
#
# Stesso codice della fase 1 (fase1/caratteristiche.jl, che include src/features.jl): profilo_tratta(cp) da
# PrecalcoloTratta(cp, "andata"), poi caratteristiche_orig (67) e caratteristiche_nuove (3). Si tengono le 66
# approvate il 10/10 (senza i 4 duplicati; le 3 din_ non si calcolano). Tratte lette a blocchi di 256 con
# leggi_tratte_materializzate, come la campagna.
#
# Uscita: ~/Documents/lavoro/ml_treno_dati/P9_D28_16384/arrow/caratteristiche.arrow (route_id + 66 colonne x_).
# Controlli in DIR_LOG: 02_caratteristiche.txt, 02_statistiche.csv, 02_confronto_fase1.csv, 02_ridondanze.csv.

include(joinpath(@__DIR__, "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))   # profilo_tratta, caratteristiche_orig/_nuove, nomi
using Statistics, SHA, LinearAlgebra

mkpath(DIR_LOG)
const OUT = open(joinpath(DIR_LOG, "02_caratteristiche.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase5/02_caratteristiche.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION)
say("TrainPowertrain: ", pathof(TP), "  commit ", TP.commit_codice())
const F_CAR = normpath(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
const F_FEA = normpath(joinpath(@__DIR__, "..", "src", "features.jl"))
sha_file(f) = bytes2hex(sha256(read(f)))
say("codice: fase1/caratteristiche.jl sha256 ", sha_file(F_CAR), "; src/features.jl sha256 ", sha_file(F_FEA))
anomalie = String[]
nota!(s) = (push!(anomalie, s); say("  ANOMALIA: ", s))

# ── nomi ─────────────────────────────────────────────────────────────────────────
const DUPLICATI = ["stops_sum_v2_segweighted", "slope_int_abs", "stops_spacing_mean", "cross_int_p_v"]
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)                         # 67 + 3, quello che si calcola
const NOMI66 = [n for n in NOMI70 if !(n in DUPLICATI)]
const J66 = [findfirst(==(n), NOMI70) for n in NOMI66]
hdr1 = split(readline(joinpath(FASE1, "dati", "dataset_doe.csv")), ',')
x1 = [String(h[3:end]) for h in hdr1 if startswith(h, "x_") && !startswith(h, "x_din_")]
say("66 caratteristiche, stesso ordine e nomi delle colonne x_ di fase1/dati/dataset_doe.csv (senza din_): ", x1 == NOMI66)
x1 == NOMI66 || error("nomi diversi dalla fase 1")

"""le 70 caratteristiche calcolate (ordine NOMI70) e la quota finale h(L) del profilo"""
function car70(cp)
    pr = profilo_tratta(cp)
    return vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr)), pr.h[end]
end

# ── 2.0 il codice dà ancora i numeri della fase 1 sulle 1024 tratte di allora ──────
say("\n[2.0] controllo del codice: le 1024 tratte della fase 1 (tratte_doe_matlab) contro fase1/dati/caratteristiche_doe.csv")
let dir1 = joinpath(TP_ROOT, "tratte_doe_matlab")
    ref = readlines(joinpath(FASE1, "dati", "caratteristiche_doe.csv"))
    h = split(ref[1], ',')
    R = Dict(String(split(l, ',')[1]) => parse.(Float64, split(l, ',')[2:end]) for l in ref[2:end])
    jr = [findfirst(==(n), h) - 1 for n in NOMI70]
    nb = 0; nt = 0; maxrel = 0.0
    for k in 1:4
        tr = leggi_tratte_materializzate(dir1; solo = Set(((k-1)*256+1):(k*256)))
        res = Vector{Vector{Float64}}(undef, length(tr))
        Threads.@threads :dynamic for i in eachindex(tr)
            res[i] = car70(tr[i].cp)[1]
        end
        for (t, x) in zip(tr, res)
            r = R[t.id][jr]; nt += 1
            nb += count(j -> x[j] !== r[j], eachindex(x))
            maxrel = max(maxrel, maximum(abs(x[j] - r[j]) / max(abs(r[j]), 1e-300) for j in eachindex(x) if x[j] !== r[j]; init = 0.0))
        end
    end
    say("  tratte: ", nt, "; valori diversi al bit (dal CSV a 17 cifre): ", nb, " su ", nt * 70, "; scarto relativo massimo ", maxrel)
    nb == 0 || nota!("il codice delle caratteristiche non ridà la fase 1 al bit su $nb valori (relativo $maxrel)")
end

# ── 2.1 calcolo a blocchi di 256 ─────────────────────────────────────────────────
say("\n[2.1] calcolo sulle 16384 tratte, blocchi di 256, ", Threads.nthreads(), " thread")
X = Matrix{Float64}(undef, NTRATTE, length(NOMI70))
hfin = Vector{Float64}(undef, NTRATTE)
t_car = Vector{Float64}(undef, NTRATTE)          # tempo di calcolo di ogni tratta (un thread), s
t_lett = 0.0; t_calc = 0.0
t_inizio = time()
for k in 1:NBLOCCHI
    global t_lett, t_calc
    t0 = time()
    tr = tratte_blocco(k)
    t_lett += time() - t0
    t0 = time()
    Threads.@threads :dynamic for i in eachindex(tr)
        rid = rid_di(tr[i].id)
        s = time_ns()
        x, hL = car70(tr[i].cp)
        t_car[rid] = (time_ns() - s) / 1e9
        X[rid, :] = x; hfin[rid] = hL
    end
    t_calc += time() - t0
    tr = nothing
    k % 8 == 0 && say(@sprintf("  blocco %2d/64: lettura %.1f s, calcolo %.1f s (cumulati)", k, t_lett, t_calc))
    GC.gc()
end
say(@sprintf("  parete: lettura %.1f s (%.2f ms/tratta), calcolo %.1f s (%.2f ms/tratta con %d thread), totale %.1f s",
             t_lett, 1000t_lett / NTRATTE, t_calc, 1000t_calc / NTRATTE, Threads.nthreads(), time() - t_inizio))
say(@sprintf("  tempo di calcolo per tratta su un thread: mediana %.2f ms, media %.2f ms, p99 %.2f ms, massimo %.2f ms",
             1000median(t_car), 1000mean(t_car), 1000quantile(t_car, 0.99), 1000maximum(t_car)))
let L = X[:, findfirst(==("L_km"), NOMI70)]
    c = cor(L, t_car)
    say(@sprintf("  correlazione tempo–L: %.2f; tempo/L mediano %.3f ms/km", c, 1000median(t_car ./ L)))
end

# ── 2.2 scrittura ────────────────────────────────────────────────────────────────
col(n) = X[:, findfirst(==(n), NOMI70)]
tab = (; route_id = Int32.(1:NTRATTE), (Symbol("x_" * n) => X[:, j] for (n, j) in zip(NOMI66, J66))...)
meta = Dict("sorgente" => "fase5/02_caratteristiche.jl, $(now())",
            "tratte" => "$(DIR_TRATTE) (zip tratte_doe_16384.zip sha256 $(split(read(joinpath(DIR_LOG, "sha256.txt"), String))[1]))",
            "codice" => "fase1/caratteristiche.jl sha256 $(sha_file(F_CAR)); src/features.jl sha256 $(sha_file(F_FEA))",
            "TrainPowertrain" => TP.commit_codice(),
            "nota" => "66 caratteristiche approvate in fase 1 (senza i 4 duplicati, senza le 3 din_), una riga per tratta, route_id 1..16384")
Arrow.write(FILE_CARATT, tab; metadata = meta)
rt = Arrow.Table(FILE_CARATT)
ok_rt = collect(rt.route_id) == 1:NTRATTE && all(collect(getproperty(rt, Symbol("x_" * n))) == X[:, j] for (n, j) in zip(NOMI66, J66)) &&
        length(Arrow.names(rt)) == 67
say("\n[2.2] scritto ", FILE_CARATT, " (", filesize(FILE_CARATT), " byte), 16384 righe × ", length(Arrow.names(rt)),
    " colonne; riletto uguale: ", ok_rt)
ok_rt || nota!("caratteristiche.arrow riletto diverso")

# ── 2.3 NaN, Inf, statistiche ────────────────────────────────────────────────────
X66 = X[:, J66]
nnan = count(isnan, X66); ninf = count(isinf, X66)
say("\n[2.3] NaN: ", nnan, "; Inf: ", ninf, " (su ", length(X66), " valori)")
(nnan + ninf) > 0 && nota!("$nnan NaN e $ninf Inf nelle caratteristiche")
open(joinpath(DIR_LOG, "02_statistiche.csv"), "w") do io
    println(io, "caratteristica,min,mediana,max,media,dev_std,valori_distinti")
    for (j, n) in enumerate(NOMI66)
        v = X66[:, j]
        println(io, join(["x_" * n; [@sprintf("%.10g", f(v)) for f in (minimum, median, maximum, mean, std)]; length(unique(v))], ','))
    end
end
say("  costanti sulle 16384: ", join([n for (j, n) in enumerate(NOMI66) if all(==(X66[1, j]), X66[:, j])], ", "), " (nessuna = vuoto)")

# ── 2.4 confronto con gli intervalli delle 1024 tratte della fase 1 ───────────────
say("\n[2.4] intervalli contro le 1024 tratte della fase 1 (fase1/dati/caratteristiche_doe.csv)")
ref = readlines(joinpath(FASE1, "dati", "caratteristiche_doe.csv"))
h1 = split(ref[1], ',')
X1 = reduce(vcat, (parse.(Float64, split(l, ',')[2:end])' for l in ref[2:end]))
cf = NamedTuple[]
for (j, n) in enumerate(NOMI66)
    v1 = X1[:, findfirst(==(n), h1) - 1]; v = X66[:, j]
    lo1, hi1 = extrema(v1); lo, hi = extrema(v); r1 = hi1 - lo1
    sotto = count(<(lo1), v); sopra = count(>(hi1), v)
    push!(cf, (caratteristica = "x_" * n, f1_min = lo1, f1_mediana = median(v1), f1_max = hi1, min = lo, mediana = median(v), max = hi,
               n_sotto = sotto, n_sopra = sopra, quota_fuori = (sotto + sopra) / NTRATTE,
               fuori_sotto_rel = r1 > 0 ? max(lo1 - lo, 0) / r1 : (lo < lo1 ? Inf : 0.0),
               fuori_sopra_rel = r1 > 0 ? max(hi - hi1, 0) / r1 : (hi > hi1 ? Inf : 0.0)))
end
open(joinpath(DIR_LOG, "02_confronto_fase1.csv"), "w") do io
    println(io, join(keys(cf[1]), ','))
    for r in cf; println(io, join((x isa AbstractFloat ? @sprintf("%.10g", x) : string(x) for x in values(r)), ',')); end
end
fuori = [r for r in cf if r.n_sotto + r.n_sopra > 0]
say("  caratteristiche con almeno una tratta fuori dall'intervallo della fase 1: ", length(fuori), " su 66")
nfuori_t = count(i -> any(j -> (v1 = X1[:, findfirst(==(NOMI66[j]), h1) - 1]; X66[i, j] < minimum(v1) || X66[i, j] > maximum(v1)), 1:66), 1:NTRATTE)
say("  tratte con almeno una caratteristica fuori: ", nfuori_t, " su ", NTRATTE)
for r in sort(fuori; by = r -> -(r.fuori_sotto_rel + r.fuori_sopra_rel))
    say(@sprintf("  %-30s fase1 [%-10.4g %10.4g]  ora [%-10.4g %10.4g]  sotto %5d (%5.1f%% intervallo) sopra %5d (%6.1f%%)",
                 r.caratteristica, r.f1_min, r.f1_max, r.min, r.max, r.n_sotto, 100r.fuori_sotto_rel, r.n_sopra, 100r.fuori_sopra_rel))
end

# ── 2.5 coerenza con il design ───────────────────────────────────────────────────
say("\n[2.5] coerenza con i fattori del design (solo verifica: i fattori non sono ingressi)")
hdes, des = leggi_design()
Ld = Float64.(des["L_km"])
say(@sprintf("  L: max |x_L_km − L_km del design| = %.6f km (L intero in metri)", maximum(abs.(col("L_km") .- Ld))))
kv = Dict{Int,Float64}()
for k in 1:NBLOCCHI
    tb = Arrow.Table(file_arrow(k))
    for (r, x) in zip(tb.tratta, tb.km_viaggio); isnan(x) || (kv[Int(r)] = x); end
end
say("  2·x_L_km === km_viaggio del registro: ", count(i -> 2 * col("L_km")[i] === kv[i], 1:NTRATTE), " / ", NTRATTE,
    "; |2·x_L_km − km_viaggio| max ", maximum(abs(2 * col("L_km")[i] - kv[i]) for i in 1:NTRATTE))
say("  x_n_fermate == n_stops: ", count(col("n_fermate") .== des["n_stops"]), " / ", NTRATTE)
say("  x_vlim_max == v_max_kmh: ", count(col("vlim_max") .== des["v_max_kmh"]), " / ", NTRATTE)
nlim = round.(Int, col("vlim_changes_per_km") .* col("L_km")) .+ 1
say("  numero di limiti (vlim_changes_per_km·L + 1) == n_vlim_segments: ", count(nlim .== des["n_vlim_segments"]), " / ", NTRATTE)
pm = (col("slope_int_pos") .- col("slope_int_neg")) ./ col("L_km")
dp = abs.(pm .- des["slope_mean"])
say(@sprintf("  pendenza media (slope_int_pos − slope_int_neg)/L [‰] contro slope_mean: max scarto %.3e ‰, mediana %.3e; con L del design %.3e",
             maximum(dp), median(dp), maximum(abs.((col("slope_int_pos") .- col("slope_int_neg")) ./ Ld .- des["slope_mean"]))))
ip = argmax(dp)
say(@sprintf("    peggiore: route %d, %.6f contro %.6f ‰ (L %.3f km)", ip, pm[ip], des["slope_mean"][ip], Ld[ip]))
ds = abs.(col("stops_density") .- des["stop_density"])
say(@sprintf("  x_stops_density contro stop_density: max scarto %.3e 1/km (n/L con L in metri interi contro L_km del design)", maximum(ds)))
for (c, s) in ((col("n_fermate") .== des["n_stops"], "n_fermate"), (col("vlim_max") .== des["v_max_kmh"], "vlim_max"),
               (nlim .== des["n_vlim_segments"], "numero di limiti"))
    all(c) || nota!("$s diverso dal design in $(count(!, c)) tratte")
end
maximum(dp) > 1e-2 && nota!("pendenza media diversa dal design di oltre 1e-2 ‰ (max $(maximum(dp)))")

# ── 2.6 identità esatte e ridondanze ─────────────────────────────────────────────
say("\n[2.6] identità esatte tra caratteristiche (come fase 1 [b2]) sulle 16384")
idn = [("slope_int_abs = slope_int_pos + slope_int_neg", col("slope_int_abs") .- col("slope_int_pos") .- col("slope_int_neg")),
       ("stops_sum_v2_segweighted = stops_sum_v2", col("stops_sum_v2_segweighted") .- col("stops_sum_v2")),
       ("stops_spacing_mean = L/(n_fermate+1)", col("stops_spacing_mean") .- col("L_km") ./ (col("n_fermate") .+ 1)),
       ("stops_density = n_fermate/L", col("stops_density") .- col("n_fermate") ./ col("L_km")),
       ("slope_int_pos - slope_int_neg = quota(L) - quota(0)", col("slope_int_pos") .- col("slope_int_neg") .- hfin),
       ("cross_int_p_v = cross_mean_p_v * L", col("cross_int_p_v") .- col("cross_mean_p_v") .* col("L_km")),
       ("vlim_frac_low + mid + high = 1", col("vlim_frac_low") .+ col("vlim_frac_mid") .+ col("vlim_frac_high") .- 1)]
for (s, r) in idn
    say(@sprintf("  %-55s max |scarto| = %.3e (scala %.3e)", s, maximum(abs.(r)), maximum(abs.(col(split(s)[1])))))
end
say("  (i primi 4 lati sinistri non sono tra le 66; le 3 identità dentro le 66: stops_density, quota, vlim_frac)")
# coppie identiche al bit tra le 66
ug = [(NOMI66[a], NOMI66[b]) for a in 1:66 for b in a+1:66 if X66[:, a] == X66[:, b]]
say("  coppie di colonne identiche tra le 66: ", isempty(ug) ? "nessuna" : join(("$a = $b" for (a, b) in ug), ", "))
cr = cor(X66)
rk = mapslices(x -> invperm(sortperm(x)) .* 1.0, X66; dims = 1)
crs = cor(rk)
rid_rows = NamedTuple[]
for i in 1:66, j in i+1:66
    (abs(cr[i, j]) >= 0.98 || abs(crs[i, j]) >= 0.98) && push!(rid_rows, (a = NOMI66[i], b = NOMI66[j], pearson = cr[i, j], spearman = crs[i, j]))
end
sort!(rid_rows; by = r -> -abs(r.pearson))
open(joinpath(DIR_LOG, "02_ridondanze.csv"), "w") do io
    println(io, "a,b,pearson,spearman")
    foreach(r -> println(io, r.a, ',', r.b, ',', r.pearson, ',', r.spearman), rid_rows)
end
say("  coppie con |correlazione| ≥ 0,98 (Pearson o Spearman, ranghi senza correzione dei pari): ", length(rid_rows))
for r in rid_rows
    say(@sprintf("    %-28s %-28s P %+.4f  S %+.4f", r.a, r.b, r.pearson, r.spearman))
end
# rango della matrice standardizzata: dipendenze lineari esatte tra più colonne
Z = (X66 .- mean(X66; dims = 1)) ./ std(X66; dims = 1)
sv = svdvals(Z)
say(@sprintf("  valori singolari della matrice standardizzata: max %.3e, i 4 più piccoli %s", sv[1], join((@sprintf("%.3e", s) for s in sv[end-3:end]), ", ")))
say("  dipendenze lineari esatte (valori singolari < 1e-8·max): ", count(<(1e-8 * sv[1]), sv))

# tratte da segnalare
say("\n[2.7] tratte segnalate in fase 4: errore_D29 ", ROUTE_D29, " (caratteristiche calcolate come le altre)")
for r in ROUTE_D29
    say(@sprintf("  route %d: L %.3f km, fermate %d, v_max %g, dislivello %.1f m", r, col("L_km")[r], Int(col("n_fermate")[r]), col("vlim_max")[r], col("dislivello_m")[r]))
end
say(@sprintf("\ntempo totale: %.1f s", time() - t_inizio))
say("anomalie: ", isempty(anomalie) ? "nessuna" : "")
foreach(a -> say("  - ", a), anomalie)
close(OUT)
