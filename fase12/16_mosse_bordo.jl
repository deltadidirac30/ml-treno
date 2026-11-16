# fase12/16: emulazione sulla griglia fitta già simulata da 15 (nessuna simulazione nuova).
# Dalla proposta G si aggiungono mosse "lungo il bordo": m - 0,01 o - 0,02 e si sale in n finché il progetto è fattibile.
# Uso, dalla cartella ml_treno: julia --project=fase12 fase12/16_mosse_bordo.jl
# emulazione sulla griglia fitta già simulata: dalla proposta G, mosse "lungo il bordo" (meno FC, più batteria)
using CSV, DataFrames, Printf, Statistics
B = joinpath(ENV["HOME"], "Documents/lavoro/ml_treno_dati")
L = CSV.read(joinpath(B, "fase12_log/15_ottimo_vero_linee.csv"), DataFrame)
r2(x) = round(x; digits = 2)
res = []
for row in eachrow(L)
    d = CSV.read(joinpath(B, "fase12/griglia_rinf", row.linea, "registro.csv"), DataFrame; select = [:m, :n, :tipo_esito, :total_cost_EUR_km])
    C = Dict((r2(r.m), r2(r.n)) => (r.tipo_esito == "fattibile" ? r.total_cost_EUR_km : Inf) for r in eachrow(d))
    visti = Set{Tuple{Float64,Float64}}()
    costo(p) = (push!(visti, p); get(C, p, Inf))
    m, n = r2(row.G_m), r2(row.G_n); c = costo((m, n))
    while true
        best = ((m, n), c)
        # mosse sul bordo: m - d, e si sale in n finché è fattibile (al più +0.12)
        for dm in (0.01, 0.02)
            mm = r2(m - dm); (mm < 0.03 && mm != 0) && (mm = m >= 0.03 + dm ? mm : (m > 0.03 ? 0.03 : -1.0)); mm < 0 && continue
            mm == m && continue
            for e in 0.0:0.01:0.12
                nn = r2(n + e); nn > 0.99 && break
                cc = costo((mm, nn))
                if isfinite(cc); cc < best[2] - 1e-12 && (best = ((mm, nn), cc)); break; end
            end
        end
        # vicini a passo 0,01
        for p in ((m, r2(n - 0.01)), (m, r2(n + 0.01)), (r2(m + 0.01), n))
            0.01 <= p[2] <= 0.99 || continue
            cc = costo(p); cc < best[2] - 1e-12 && (best = (p, cc))
        end
        best[1] == (m, n) && break
        (m, n), c = best
    end
    push!(res, (linea = row.linea, G = row.G_vs_ottimo_pct, H = 100 * (c / row.ottimo_costo - 1), sim = length(visti) - 1))
end
R = DataFrame(res)
for (k, v) in (("G", R.G), ("G + bordo", R.H))
    @printf("%-10s media %+.3f%%  mediana %+.3f%%  p90 %+.3f%%  max %+.3f%%  entro 0,01%% %d  entro 0,5%% %d  entro 1%% %d  oltre 2%% %d\n",
        k, mean(v), median(v), quantile(v, 0.9), maximum(v), count(<=(0.01), v), count(<=(0.5), v), count(<=(1), v), count(>(2), v))
end
@printf("simulazioni in più: media %.1f, max %d\n", mean(R.sim), maximum(R.sim))
for r in eachrow(sort(R[R.G .> 0.5, :], :G, rev = true)); @printf("  %-36s G %+.2f%%  ->  %+.2f%%  (%d sim)\n", r.linea, r.G, r.H, r.sim); end
