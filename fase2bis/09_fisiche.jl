# Fase 2bis (= fase2/05_fisiche.jl sul riferimento v2): errore sulle grandezze fisiche previste (ripetizione 1; H2 per viaggio e vita FC sulle ibride, energia di
# ricarica per viaggio su tutte). Uso: julia --project=. 09_fisiche.jl. Scrive risultati/metriche_fisiche.csv.
using CSV, DataFrames, Statistics, Printf
const G = "/Users/kairos/Documents/lavoro/ml_treno_dati/fase2bis"
f = vcat(CSV.read(joinpath(G, "cv", "fisiche_r1_p66.csv"), DataFrame), CSV.read(joinpath(G, "cv", "fisiche_r1_p69.csv"), DataFrame))
# H2 e vita FC: solo le ibride (sulle sola batteria valgono 0 e Inf); energia di ricarica: escluse le 2 ibride con
# meno di 10 kWh (0,2 kWh: errore relativo senza significato)
f = f[((f.grandezza .== "E_ricarica_viaggio_kWh") .& (f.vero .>= 10)) .| ((f.grandezza .!= "E_ricarica_viaggio_kWh") .& f.ibrido), :]
f.err = f.prev ./ f.vero .- 1
m = combine(groupby(f, [:grandezza, :insieme, :famiglia]), :err => (e -> 100median(abs.(e))) => :err_mediana_pct,
            :err => (e -> 100quantile(abs.(e), 0.95)) => :err_p95_pct, :err => (e -> 100maximum(abs.(e))) => :err_max_pct,
            [:prev, :vero] => ((p, v) -> 1 - sum(abs2, log.(p) .- log.(v)) / sum(abs2, log.(v) .- mean(log.(v)))) => :R2_log)
sort!(m, [:grandezza, :insieme, :famiglia]); CSV.write("risultati/metriche_fisiche.csv", m)
for r in eachrow(m); @printf("%-24s %s %s  |err| mediana %5.2f%%  p95 %6.2f%%  max %6.2f%%  R²(log) %.4f\n", r.grandezza, r.insieme, r.famiglia, r.err_mediana_pct, r.err_p95_pct, r.err_max_pct, r.R2_log); end
