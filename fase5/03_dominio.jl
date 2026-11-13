# fase5/03_dominio.jl: le tratte reali e le linee della rete dentro il dominio delle 16384 tratte DoE?
#
#   julia -t 8 --project=fase5 fase5/03_dominio.jl > ~/Documents/lavoro/ml_treno_dati/fase5_log/log_03.txt 2>&1
#
# Le 66 caratteristiche (stesso codice: fase1/caratteristiche.jl) di:
#   reali          train-powertrain/tratte_reali: Calabria, Canavese, Firenze (Firenze-BRoute se identica a Firenze si
#                  salta; Sulmona-Carpinone esclusa su richiesta, 13/11)
#   rete_20261110  dati_rete/archivio/tratte_rete_20261110 (= tratte_rete committata in correzioni-modello, la versione
#                  su cui è stata rivista la DoE, 08f287d)
#   rete_20261113  tratte_rete del working tree di correzioni-modello (rigenerata il 13/11, non committata)
# lette con leggi_tratte_reali(; cartella) come il runner (cartella_reali=). Per ogni tratta: caratteristiche fuori
# dall'intervallo DoE e di quanto, distanza dal vicino DoE più prossimo (66 caratteristiche standardizzate con media e
# deviazione delle 16384) e suo percentile tra le distanze dal vicino delle tratte DoE.
# Scrive in DIR_LOG: 03_dominio.txt, 03_dominio_tratte.csv, 03_dominio_caratteristiche.csv; le caratteristiche in
# ~/Documents/lavoro/ml_treno_dati/fase5_dominio/caratteristiche_<insieme>.arrow.

include(joinpath(@__DIR__, "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
using Statistics, LinearAlgebra

BLAS.set_num_threads(min(8, Threads.nthreads()))
mkpath(DIR_LOG)
const DIR_DOM = joinpath(BASE_DATI, "fase5_dominio"); mkpath(DIR_DOM)
const OUT = open(joinpath(DIR_LOG, "03_dominio.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase5/03_dominio.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())

const DUPLICATI = ["stops_sum_v2_segweighted", "slope_int_abs", "stops_spacing_mean", "cross_int_p_v"]
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const NOMI66 = [n for n in NOMI70 if !(n in DUPLICATI)]
const J66 = [findfirst(==(n), NOMI70) for n in NOMI66]
car66(cp) = (pr = profilo_tratta(cp); vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))[J66])

# ── DoE ──────────────────────────────────────────────────────────────────────────
ct = Arrow.Table(FILE_CARATT)
X = reduce(hcat, (collect(getproperty(ct, Symbol("x_" * n))) for n in NOMI66))
size(X) == (NTRATTE, 66) || error("caratteristiche.arrow")
μ = mean(X; dims = 1); σ = std(X; dims = 1)
Z = (X .- μ) ./ σ
lo = vec(minimum(X; dims = 1)); hi = vec(maximum(X; dims = 1)); rng = hi .- lo
# distanza dal vicino più prossimo tra le DoE (senza sé stessa), a pezzi di 1024 righe
t0 = time()
n2 = vec(sum(Z .^ 2; dims = 2))
dd = Vector{Float64}(undef, NTRATTE)
for a in 1:1024:NTRATTE
    b = min(a + 1023, NTRATTE)
    G = Z[a:b, :] * Z'
    D = max.(n2[a:b] .+ n2' .- 2 .* G, 0.0)
    for (r, i) in enumerate(a:b); D[r, i] = Inf; end
    dd[a:b] = sqrt.(vec(minimum(D; dims = 2)))
end
say(@sprintf("DoE: distanza dal vicino (66 standardizzate): mediana %.2f, p95 %.2f, p99 %.2f, max %.2f (%.1f s)",
             median(dd), quantile(dd, 0.95), quantile(dd, 0.99), maximum(dd), time() - t0))

# ── insiemi ──────────────────────────────────────────────────────────────────────
const DIR_REALI = joinpath(TP_ROOT, "tratte_reali")
const DIR_RETE10 = joinpath(TP_ROOT, "dati_rete", "archivio", "tratte_rete_20261110")
const DIR_RETE13 = joinpath(TP_ROOT, "train-powertrain-matlab-correzioni-modello", "Codice_PRECONFIGURATORE_generale",
                            "tratte", "tratte_rete")
cartelle(d) = sort([f for f in readdir(d) if isdir(joinpath(d, f))])

function leggi_insieme(dir, nomi)
    tr = Vector{Any}(undef, length(nomi))
    Threads.@threads :dynamic for i in eachindex(nomi)
        tr[i] = try
            t = leggi_tratte_reali([nomi[i]]; cartella = dir)[1]
            (id = t.id, x = car66(t.cp), sha = t.sha256, L = t.cp.lunghezza_binario_andata / 1000, err = "")
        catch e
            (id = nomi[i], x = fill(NaN, 66), sha = "", L = NaN, err = sprint(showerror, e)[1:min(end, 200)])
        end
    end
    return tr
end

reali_nomi = [n for n in cartelle(DIR_REALI) if n != "Sulmona-Carpinone"]
say("\ntratte reali in ", DIR_REALI, ": ", join(cartelle(DIR_REALI), ", "), "  → esclusa Sulmona-Carpinone (richiesta del 13/11)")
R = leggi_insieme(DIR_REALI, reali_nomi)
iF = findfirst(t -> t.id == "Firenze", R); iB = findfirst(t -> t.id == "Firenze-BRoute", R)
if iF !== nothing && iB !== nothing && R[iF].sha == R[iB].sha
    say("Firenze-BRoute identica a Firenze (stessa impronta di tutti i dati): si salta")
    R = [t for t in R if t.id != "Firenze-BRoute"]
end
insiemi = [("reali", R),
           ("rete_20261110", leggi_insieme(DIR_RETE10, cartelle(DIR_RETE10))),
           ("rete_20261113", leggi_insieme(DIR_RETE13, cartelle(DIR_RETE13)))]

# ── domini ───────────────────────────────────────────────────────────────────────
righe = NamedTuple[]
per_car = Dict{String,Vector{Int}}()
for (nome, T) in insiemi
    ok = [t for t in T if isempty(t.err)]
    say("\n══ ", nome, ": ", length(T), " tratte, lette ", length(ok), isempty(ok) ? "" :
        @sprintf("; L da %.1f a %.1f km", minimum(t.L for t in ok), maximum(t.L for t in ok)))
    for t in T; isempty(t.err) || say("  NON LETTA ", t.id, ": ", t.err); end
    cont = zeros(Int, 66)
    for t in ok
        x = t.x
        f = [x[j] > hi[j] ? (x[j] - hi[j]) / rng[j] : x[j] < lo[j] ? -(lo[j] - x[j]) / rng[j] : 0.0 for j in 1:66]
        fuori = findall(!=(0.0), f)
        cont[fuori] .+= 1
        z = (x' .- μ) ./ σ
        d2 = vec(sum((Z .- z) .^ 2; dims = 2)); iv = argmin(d2); d = sqrt(d2[iv])
        pc = 100 * count(<=(d), dd) / NTRATTE
        ord = fuori[sortperm(abs.(f[fuori]); rev = true)]
        push!(righe, (insieme = nome, tratta = t.id, L_km = t.L, n_fuori = length(fuori),
                      max_fuori_pct = isempty(fuori) ? 0.0 : 100 * maximum(abs.(f[fuori])),
                      fuori = join((@sprintf("%s(%+.0f%%)", NOMI66[j], 100f[j]) for j in ord), " "),
                      d_vicino = d, vicino = iv, percentile_doe = pc))
    end
    per_car[nome] = cont
    rr = [r for r in righe if r.insieme == nome]
    isempty(rr) && continue
    say(@sprintf("  dentro tutti gli intervalli DoE: %d / %d; fuori in 1-3 caratteristiche: %d; in più di 3: %d",
                 count(r -> r.n_fuori == 0, rr), length(rr), count(r -> 1 <= r.n_fuori <= 3, rr), count(r -> r.n_fuori > 3, rr)))
    dv = [r.d_vicino for r in rr]; pv = [r.percentile_doe for r in rr]
    say(@sprintf("  distanza dal vicino DoE: mediana %.2f, max %.2f; percentile tra le DoE: mediana %.1f, oltre il p99 %d, oltre il massimo DoE %d",
                 median(dv), maximum(dv), median(pv), count(>(quantile(dd, 0.99)), dv), count(>(maximum(dd)), dv)))
    if nome == "reali" || count(r -> r.n_fuori > 0, rr) > 0
        say("  tratte fuori (o reali), ordinate per numero di caratteristiche fuori:")
        for r in sort(rr; by = r -> (-r.n_fuori, -r.d_vicino))
            (nome == "reali" || r.n_fuori > 0) || continue
            say(@sprintf("    %-40s L %6.1f km  fuori %2d (max %5.1f%%)  vicino route %5d a %.2f (perc. %5.1f)  %s",
                         r.tratta, r.L_km, r.n_fuori, r.max_fuori_pct, r.vicino, r.d_vicino, r.percentile_doe,
                         length(r.fuori) > 160 ? r.fuori[1:prevind(r.fuori, 161)] * " …" : r.fuori))
        end
    end
    j = findall(>(0), cont)
    isempty(j) || say("  caratteristiche fuori, numero di tratte: ", join(("$(NOMI66[k]) $(cont[k])" for k in j[sortperm(cont[j]; rev = true)]), ", "))
    # Arrow delle caratteristiche
    Arrow.write(joinpath(DIR_DOM, "caratteristiche_$nome.arrow"),
                (; tratta = [t.id for t in ok], (Symbol("x_" * n) => [t.x[k] for t in ok] for (k, n) in enumerate(NOMI66))...);
                metadata = Dict("sorgente" => "fase5/03_dominio.jl $(now())", "insieme" => nome))
end

# ── rete: 10/11 contro 13/11 ─────────────────────────────────────────────────────
say("\n══ rete del 10/11 contro rete del 13/11 (stesse cartelle)")
r10 = Dict(t.id => t for t in insiemi[2][2] if isempty(t.err)); r13 = Dict(t.id => t for t in insiemi[3][2] if isempty(t.err))
com = sort(collect(intersect(keys(r10), keys(r13))))
say("  cartelle: 10/11 ", length(r10), ", 13/11 ", length(r13), ", comuni ", length(com),
    "; solo 10/11: ", setdiff(keys(r10), keys(r13)), "; solo 13/11: ", setdiff(keys(r13), keys(r10)))
nd = count(k -> r10[k].sha != r13[k].sha, com)
ndx = count(k -> r10[k].x != r13[k].x, com)
say("  tratte con dati diversi (impronta): ", nd, "; con caratteristiche diverse: ", ndx)
if ndx > 0
    rel = [maximum(abs.(r10[k].x .- r13[k].x) ./ rng) for k in com]
    say(@sprintf("  scarto massimo per tratta / ampiezza DoE: mediana %.2e, max %.2e (%s)", median(rel), maximum(rel), com[argmax(rel)]))
    jj = [argmax(abs.(r10[k].x .- r13[k].x) ./ rng) for k in com if r10[k].x != r13[k].x]
    say("  caratteristica con lo scarto massimo, per tratta: ", join(("$(NOMI66[j]) $(count(==(j), jj))" for j in unique(jj)), ", "))
end

open(joinpath(DIR_LOG, "03_dominio_tratte.csv"), "w") do io
    println(io, join(keys(righe[1]), ','))
    for r in righe; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : replace(string(v), ',' => ';') for v in values(r)), ',')); end
end
open(joinpath(DIR_LOG, "03_dominio_caratteristiche.csv"), "w") do io
    println(io, "caratteristica,doe_min,doe_max,", join(("fuori_" * n for (n, _) in insiemi), ','))
    for (j, n) in enumerate(NOMI66)
        println(io, "x_", n, ',', @sprintf("%.6g,%.6g", lo[j], hi[j]), ',', join((per_car[k][j] for (k, _) in insiemi), ','))
    end
end
say("\nfatto: ", now())
close(OUT)
