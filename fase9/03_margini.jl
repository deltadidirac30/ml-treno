# fase9/03_margini.jl: prova dei margini di sicurezza sui vincoli nella scelta del surrogato (dopo il passo 5b).
#
#   julia -t 8 --project=fase9 fase9/03_margini.jl > ~/Documents/lavoro/ml_treno_dati/fase9_log/log_03.txt 2>&1
#
# Il surrogato considera fattibile un caso solo se: non D3 (C-rate previsto ≤ 20), SOC previsto ≥ 0,2 + δ_SOC, probabilità
# di scarica < p_max, massa prevista ≤ 29 250 − δ_massa. Per ogni combinazione e ogni tratta di validazione: scelta secca
# e verifica delle prime k (k = 3, 5) con il simulatore (lette dal registro). Misure: scelte non fattibili, tratte senza
# proposta, rimpianto. I margini si scelgono sulla validazione: il giudizio finale va confermato sul test.
# Usa surrogato_validazione.arrow (passo 5a). Nessuna simulazione. Scrive in fase9_log: 03_margini.txt, 03_margini.csv,
# fig_margini.png.

include(joinpath(@__DIR__, "comune.jl"))
using Plots
gr()
const LOG = joinpath(BASE, "fase9_log")
const OUT = open(joinpath(LOG, "03_margini.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase9/03_margini.jl  ", now(), "  thread: ", Threads.nthreads())

const S = Arrow.Table(joinpath(BASE, "fase9", "surrogato_validazione.arrow"))
const TR = Int.(S.tratta); const M = collect(S.m); const Nn = collect(S.n)
const SOC = collect(S.SOC); const PSC = collect(S.p_scarica); const D3 = collect(S.d3); const C_S = collect(S.costo_totale)
const F_V = collect(S.vero_fattibile); const C_V = collect(S.vero_costo_totale)
const MASSA = let tg = Dict{Tuple{Float64,Float64},Any}()
    [begin t = get!(() -> taglie(M[i], Nn[i]), tg, (M[i], Nn[i])); t.massa_batt + t.massa_FC + S.serbatoio[i] end for i in eachindex(M)]
end
const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const TRATTE = sort(collect(keys(RIGHE)))
const BEST = Dict(r => minimum(C_V[i] for i in RIGHE[r] if F_V[i]) for r in TRATTE)
# controllo: con i margini nulli si ritrova la fattibilità del surrogato del passo 5a
ok0 = all((.!D3 .& (SOC .>= 0.2) .& (PSC .< 0.5) .& (MASSA .<= LIMITE_MASSA)) .== collect(S.fattibile))
say("controllo: margini nulli = fattibilità del surrogato del passo 5a: ", ok0)
ok0 || error("la regola con margini nulli non ridà il passo 5a")

const KS = (1, 3, 5)
function prova(dsoc, pmax, dmassa)
    amm = .!D3 .& (SOC .>= 0.2 + dsoc) .& (PSC .< pmax) .& (MASSA .<= LIMITE_MASSA - dmassa)
    res = Dict(k => (nonf = 0, nessuna = 0, rimp = Float64[]) for k in KS)
    out = Dict{Int,Any}()
    for k in KS; out[k] = [0, 0, Float64[]]; end
    for r in TRATTE
        ii = [i for i in RIGHE[r] if amm[i]]
        if isempty(ii)
            for k in KS; out[k][2] += 1; end
            continue
        end
        ord = ii[sortperm(C_S[ii])]
        for k in KS
            cand = [i for i in ord[1:min(k, end)] if F_V[i]]
            if isempty(cand)
                out[k][1] += 1
            else
                push!(out[k][3], minimum(C_V[cand]) / BEST[r] - 1)
            end
        end
    end
    return out
end
NT = length(TRATTE)
righe = NamedTuple[]
for dsoc in (0.0, 0.01, 0.02, 0.03, 0.05, 0.08), pmax in (0.5, 0.3, 0.2, 0.1), dmassa in (0.0, 100.0, 200.0, 400.0)
    o = prova(dsoc, pmax, dmassa)
    for k in KS
        nf, ns, rr = o[k]
        push!(righe, (dsoc = dsoc, pmax = pmax, dmassa = dmassa, k = k, non_fattibili_pct = 100nf / NT, senza_proposta = ns,
                      rimpianto_mediana_pct = 100median(rr), rimpianto_p90_pct = 100quantile(rr, 0.9), rimpianto_p95_pct = 100quantile(rr, 0.95),
                      entro_1pct = 100count(<=(0.01), rr) / NT))
    end
end
open(joinpath(LOG, "03_margini.csv"), "w") do io
    println(io, join(keys(righe[1]), ','))
    for x in righe; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : v for v in values(x)), ',')); end
end
pr(x) = @sprintf("  δSOC %.2f  p_scarica < %.1f  δmassa %3.0f kg | k=%d: non fattibili %5.2f%%, senza proposta %d, rimpianto mediana %.3f%% p90 %.2f%% p95 %.2f%%, entro 1%% %.1f%%",
                 x.dsoc, x.pmax, x.dmassa, x.k, x.non_fattibili_pct, x.senza_proposta, x.rimpianto_mediana_pct, x.rimpianto_p90_pct,
                 x.rimpianto_p95_pct, x.entro_1pct)
sel(f) = [x for x in righe if f(x)]

say("\n[1] un margine alla volta (scelta secca, k = 1)")
for x in sel(x -> x.k == 1 && x.pmax == 0.5 && x.dmassa == 0); say(pr(x)); end
for x in sel(x -> x.k == 1 && x.dsoc == 0 && x.dmassa == 0 && x.pmax < 0.5); say(pr(x)); end
for x in sel(x -> x.k == 1 && x.dsoc == 0 && x.pmax == 0.5 && x.dmassa > 0); say(pr(x)); end

for k in KS
    say("\n[2] k = $k: le combinazioni con meno scelte non fattibili, e fra queste il rimpianto mediano più basso (prime 8)")
    v = sort(sel(x -> x.k == k); by = x -> (round(x.non_fattibili_pct; digits = 1), x.rimpianto_mediana_pct))
    for x in v[1:8]; say(pr(x)); end
end
say("\n[3] frontiera: per ogni soglia di scelte non fattibili, il rimpianto mediano più basso (k = 1)")
for soglia in (10.0, 5.0, 3.0, 2.0, 1.0, 0.5)
    v = sel(x -> x.k == 1 && x.non_fattibili_pct <= soglia)
    isempty(v) && (say(@sprintf("  ≤ %4.1f%%: nessuna combinazione", soglia)); continue)
    say(@sprintf("  ≤ %4.1f%%:", soglia), pr(v[argmin([x.rimpianto_mediana_pct for x in v])]))
end
say("\n[4] frontiera con la verifica delle prime 3 (k = 3)")
for soglia in (2.0, 1.0, 0.5, 0.2, 0.1)
    v = sel(x -> x.k == 3 && x.non_fattibili_pct <= soglia)
    isempty(v) && (say(@sprintf("  ≤ %4.1f%%: nessuna combinazione", soglia)); continue)
    say(@sprintf("  ≤ %4.1f%%:", soglia), pr(v[argmin([x.rimpianto_mediana_pct for x in v])]))
end

# figura: scelte non fattibili contro rimpianto mediano, tutte le combinazioni, per k
plt = plot(size = (850, 500), dpi = 130, xlabel = "scelte non fattibili [% delle tratte]", ylabel = "rimpianto mediano [%]",
           title = "margini di sicurezza: ogni punto è una combinazione (δSOC, p_scarica, δmassa)", legend = :topright)
for (k, col) in ((1, :steelblue), (3, :darkorange), (5, :green4))
    v = sel(x -> x.k == k)
    scatter!(plt, [x.non_fattibili_pct for x in v], [x.rimpianto_mediana_pct for x in v]; ms = 3, msw = 0, color = col,
             label = k == 1 ? "surrogato da solo" : "verifica delle prime $k")
end
savefig(plt, joinpath(LOG, "fig_margini.png"))
say("\nfigura: fig_margini.png")
close(OUT)
