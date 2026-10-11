# Fase 1 b, f (prima parte): caratteristiche delle 1024 tratte DoE e delle 5 reali, controlli, ridondanze,
# dominio.
#
# Uso, da ml_treno/fase1:   julia -t 8 --project=. 02_caratteristiche.jl
#
# Scrive in dati/: caratteristiche_doe.csv, caratteristiche_reali.csv, ridondanze.csv, dominio_reali.csv,
# dominio_reali_vicino.csv, controlli_caratteristiche.txt.

using CSV, DataFrames, Printf, Statistics, LinearAlgebra
include(joinpath(@__DIR__, "caratteristiche.jl"))

const TP   = "/Users/kairos/Documents/lavoro/train-powertrain"
const DATI = joinpath(@__DIR__, "dati")
mkpath(DATI)
out = open(joinpath(DATI, "controlli_caratteristiche.txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))

# ── calcolo ──────────────────────────────────────────────────────────────────
tratte = leggi_tratte_materializzate(joinpath(TP, "tratte_doe_matlab"))
reali  = TrainPowertrain.Campagna.leggi_tratte_reali(; cartella = joinpath(TP, "tratte_reali"))
X = Matrix{Float64}(undef, length(tratte), length(NOMI_CARATTERISTICHE))
t0 = time()
Threads.@threads :dynamic for k in eachindex(tratte)
    X[k, :] = tutte_le_caratteristiche(tratte[k].cp)
end
say(@sprintf("caratteristiche di 1024 tratte in %.1f s", time() - t0))
XR = reduce(vcat, (tutte_le_caratteristiche(t.cp)' for t in reali))

NOMI = NOMI_CARATTERISTICHE

df  = DataFrame(X, NOMI);  insertcols!(df, 1, :tratta => [t.id for t in tratte])
dfr = DataFrame(XR, NOMI); insertcols!(dfr, 1, :tratta => [t.id for t in reali])
CSV.write(joinpath(DATI, "caratteristiche_doe.csv"), df)
CSV.write(joinpath(DATI, "caratteristiche_reali.csv"), dfr)
col(n) = X[:, findfirst(==(n), NOMI)]

# ── controllo con i fattori del design (solo verifica: i fattori NON sono input) ──
des = vcat(CSV.read(joinpath(TP, "data_doe", "design_000001_000256.csv"), DataFrame),
           CSV.read(joinpath(TP, "data_doe", "design_000257_001024.csv"), DataFrame))
sort!(des, :route_id)
rid = [parse(Int, t.id[7:end]) for t in tratte]
des = des[indexin(rid, des.route_id), :]
say("\n[b1] controllo con i fattori del design (solo verifica)")
say(@sprintf("  L: max |L_km - design L_km| = %.4f km (L intero in metri nei file)", maximum(abs.(col("L_km") .- des.L_km))))
say("  fermate intermedie = n_stops del design: ", count(col("n_fermate") .== des.n_stops), "/1024")
say("  vlim_max = v_max_kmh del design: ", count(col("vlim_max") .== des.v_max_kmh), "/1024")
say("  numero di limiti = n_vlim_segments: ", count(round.(Int, col("vlim_changes_per_km") .* col("L_km")) .+ 1 .== des.n_vlim_segments), "/1024")
say(@sprintf("  pendenza media dalla tratta (‰) contro slope_mean del design: max scarto %.3e",
             maximum(abs.((col("slope_int_pos") .- col("slope_int_neg")) ./ col("L_km") .- des.slope_mean))))

# ── identità esatte e ridondanze ─────────────────────────────────────────────
say("\n[b2] identità esatte tra caratteristiche (sulle 1024 tratte)")
idn = [("slope_int_abs = slope_int_pos + slope_int_neg", col("slope_int_abs") .- col("slope_int_pos") .- col("slope_int_neg")),
       ("stops_sum_v2_segweighted = stops_sum_v2", col("stops_sum_v2_segweighted") .- col("stops_sum_v2")),
       ("stops_spacing_mean = L/(n_fermate+1)", col("stops_spacing_mean") .- col("L_km") ./ (col("n_fermate") .+ 1)),
       ("stops_density = n_fermate/L", col("stops_density") .- col("n_fermate") ./ col("L_km")),
       ("slope_int_pos - slope_int_neg = quota(L) - quota(0)", col("slope_int_pos") .- col("slope_int_neg") .- [let pr = profilo_tratta(t.cp); pr.h[end] - pr.h[1] end for t in tratte]),
       ("cross_int_p_v = cross_mean_p_v * L", col("cross_int_p_v") .- col("cross_mean_p_v") .* col("L_km")),
       ("vlim_frac_low + mid + high = 1", col("vlim_frac_low") .+ col("vlim_frac_mid") .+ col("vlim_frac_high") .- 1)]
for (s, r) in idn
    say(@sprintf("  %-62s max |scarto| = %.3e (scala %.3e)", s, maximum(abs.(r)), maximum(abs.(col(split(s)[1])))))
end

say("\n[b3] caratteristiche costanti sulle 1024: ", join([n for n in NOMI if std(col(n)) == 0], ", "))

cr = cor(X)
crs = cor(mapslices(x -> invperm(sortperm(x)) .* 1.0, X; dims = 1))   # Spearman (ranghi, senza correzione dei pari)
rid_rows = DataFrame(a = String[], b = String[], pearson = Float64[], spearman = Float64[])
for i in eachindex(NOMI), j in i+1:length(NOMI)
    (abs(cr[i, j]) >= 0.98 || abs(crs[i, j]) >= 0.98) && push!(rid_rows, (NOMI[i], NOMI[j], cr[i, j], crs[i, j]))
end
sort!(rid_rows, :pearson, by = abs, rev = true)
CSV.write(joinpath(DATI, "ridondanze.csv"), rid_rows)
say("\n[b4] coppie con |correlazione| >= 0,98 (Pearson o Spearman): ", nrow(rid_rows), " (ridondanze.csv)")
for r in eachrow(rid_rows)
    say(@sprintf("  %-28s %-28s P %+.4f  S %+.4f", r.a, r.b, r.pearson, r.spearman))
end

# risoluzione del profilo: lunghezza media dei tratti a pendenza costante (tratte reali da altimetria)
function tratti_costanti(cp)
    pr = profilo_tratta(cp); p = pr.p
    nc = 1 + count(i -> abs(p[i] - p[i-1]) > 1e-9, 2:length(p))
    return pr.L / nc
end
say("\n[b5] lunghezza media dei tratti a pendenza costante [km]")
lt = [tratti_costanti(t.cp) for t in tratte]
say(@sprintf("  DoE: min %.3f, mediana %.3f, max %.3f", minimum(lt), median(lt), maximum(lt)))
for t in reali; say(@sprintf("  %-18s %.4f", t.id, tratti_costanti(t.cp))); end

# ── dominio delle tratte reali ───────────────────────────────────────────────
say("\n[f1] tratte reali contro il dominio delle 1024 tratte DoE")
dom = DataFrame(caratteristica = String[], doe_min = Float64[], doe_p1 = Float64[], doe_mediana = Float64[],
                doe_p99 = Float64[], doe_max = Float64[])
for t in reali; dom[!, Symbol(t.id)] = Float64[]; dom[!, Symbol(t.id * "_fuori")] = Float64[]; end
quant(v, q) = quantile(v, q)
for (j, n) in enumerate(NOMI)
    v = X[:, j]; lo, hi = extrema(v); rng = hi - lo
    riga = Any[n, lo, quant(v, 0.01), median(v), quant(v, 0.99), hi]
    for k in eachindex(reali)
        x = XR[k, j]
        f = x > hi ? (x - hi) / (rng > 0 ? rng : 1.0) : x < lo ? -(lo - x) / (rng > 0 ? rng : 1.0) : 0.0
        push!(riga, x, f)
    end
    push!(dom, riga)
end
CSV.write(joinpath(DATI, "dominio_reali.csv"), dom)
for t in reali
    f = dom[!, Symbol(t.id * "_fuori")]
    idx = findall(!=(0.0), f)
    say("  ", t.id, ": ", length(idx), " caratteristiche fuori dall'intervallo DoE su ", length(NOMI))
    for i in idx[sortperm(abs.(f[idx]), rev = true)]
        say(@sprintf("      %-28s %12.5g  (DoE %.5g … %.5g; fuori di %+.1f%% dell'intervallo)", dom.caratteristica[i],
                     dom[i, Symbol(t.id)], dom.doe_min[i], dom.doe_max[i], 100 * f[i]))
    end
end

# distanza dal vicino più prossimo (caratteristiche standardizzate con media e deviazione delle DoE),
# confrontata con la stessa distanza tra le tratte DoE (senza la tratta stessa)
# insieme proposto: tutte tranne i duplicati esatti (b2); con e senza le 3 caratteristiche dalla dinamica
const DUPLICATI = ["stops_sum_v2_segweighted", "slope_int_abs", "stops_spacing_mean", "cross_int_p_v"]
const INSIEMI = Dict(
    "proposto_profilo" => [n for n in NOMI if !(n in DUPLICATI) && !(n in NOMI_DIN)],
    "proposto_profilo_din" => [n for n in NOMI if !(n in DUPLICATI)])
vic = DataFrame(insieme = String[], tratta = String[], d_vicino = Float64[], vicino = String[], percentile_doe = Float64[])
for (nome, ins) in sort(collect(INSIEMI))
    J = [findfirst(==(n), NOMI) for n in ins]
    μ = mean(X[:, J], dims = 1); σ = std(X[:, J], dims = 1)
    Z = (X[:, J] .- μ) ./ σ; ZR = (XR[:, J] .- μ) ./ σ
    dd = [minimum(norm(Z[i, :] .- Z[k, :]) for k in axes(Z, 1) if k != i) for i in axes(Z, 1)]
    say(@sprintf("  insieme '%s' (%d caratteristiche): distanza dal vicino tra DoE: mediana %.2f, p95 %.2f, max %.2f",
                 nome, length(J), median(dd), quantile(dd, 0.95), maximum(dd)))
    for k in eachindex(reali)
        ds = [norm(ZR[k, :] .- Z[i, :]) for i in axes(Z, 1)]
        i = argmin(ds)
        pc = 100 * count(<=(ds[i]), dd) / length(dd)
        push!(vic, (nome, reali[k].id, ds[i], tratte[i].id, pc))
        say(@sprintf("      %-18s vicino %s a %.2f (percentile %.1f delle distanze DoE)", reali[k].id, tratte[i].id, ds[i], pc))
    end
end
CSV.write(joinpath(DATI, "dominio_reali_vicino.csv"), vic)
close(out)
