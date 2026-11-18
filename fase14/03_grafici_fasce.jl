# fase14/03_grafici_fasce.jl: (1) i grafici delle flotte della p-mediana (fase14/02); (2) il confronto con il metodo delle fasce.
#
#   julia --project=fase14 fase14/03_grafici_fasce.jl > ~/Documents/lavoro/ml_treno_dati/fase14_log/log_03.txt 2>&1
#
# Metodo delle fasce (la prima proposta): le linee si dividono in fasce secondo il loro progetto ottimo (m, n); per ogni fascia si
# prende un treno che funziona su tutte le linee della fascia, e ogni linea usa il treno della sua fascia. Fasce di m: sola batteria
# (m = 0), FC piccola (0 < m < 0,1), poi fasce larghe Δm da 0,1 in su; fasce di n larghe Δn da 0. Per ogni fascia si sceglie, fra i
# treni che funzionano su tutte le sue linee, quello con l'extra-costo medio minimo sulla fascia: è la versione migliore possibile del
# metodo. Si prova anche la variante "fasce + scelta libera": gli stessi treni, ma ogni linea usa quello che le costa meno.
# Il confronto è con la p-mediana a parità di numero di treni.
#
# Figure in fase14/figure/: fig_curva.png (extra-costo contro K), fig_piano_mn.png (flotte nel piano m, n), fig_mappa_K8.png (mappa).

using JLD2, JSON, Statistics, Printf, Dates, Plots
gr()
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase14_log")
const FIG = joinpath(@__DIR__, "figure"); mkpath(FIG)
const OUT = open(joinpath(LOG, "03_grafici_fasce.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase14/03_grafici_fasce.jl  ", now())
const D = load(joinpath(BASE, "fase14", "tabella.jld2"))
const linee, m, n, P_FC, C_BATT, R, tenuti, jopt = D["linee"], D["m"], D["n"], D["P_FC"], D["C_BATT"], D["R"], D["tenuti"], D["jopt"]
const NL = length(linee)
const PM = load(joinpath(BASE, "fase14", "pmediana.jld2"))["ris"]      # chiavi "senza_K", "10_K", "15_K"
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
pct(x) = @sprintf("%+.2f%%", 100x)
Ks(t) = sort([parse(Int, split(k, '_')[2]) for k in keys(PM) if startswith(k, t * "_")])
medio(t, K) = mean(PM["$(t)_$K"].ex); peggiore(t, K) = maximum(PM["$(t)_$K"].ex)

# ── 1. il metodo delle fasce ─────────────────────────────────────────────────────
mo = m[jopt]; no = n[jopt]
function fascia_m(x, dm)
    x == 0 && return 0
    x < 0.1 && return 1
    return isinf(dm) ? 2 : 2 + floor(Int, (x - 0.1) / dm + 1e-9)
end
fascia_n(x, dn) = floor(Int, x / dn - 1e-9)
function fasce(dm, dn)
    gruppi = Dict{Tuple{Int,Int},Vector{Int}}()
    for i in 1:NL; push!(get!(gruppi, (fascia_m(mo[i], dm), fascia_n(no[i], dn)), Int[]), i); end
    treni = Int[]; ass = zeros(Int, NL)
    for (_, g) in sort(collect(gruppi); by = first)
        cand = [j for j in tenuti if all(i -> isfinite(R[i, j]), g)]   # basta cercare fra i non dominati
        isempty(cand) && return nothing
        j = cand[argmin([mean(R[g, j]) for j in cand])]
        push!(treni, j); ass[g] .= j
    end
    ex = [R[i, ass[i]] for i in 1:NL]
    ex_lib = [minimum(R[i, j] for j in treni) for i in 1:NL]           # stessi treni, scelta libera
    return (K = length(unique(treni)), ex = ex, ex_lib = ex_lib, treni = unique(treni), gruppi = length(gruppi))
end
say("\n1. METODO DELLE FASCE contro p-mediana (senza tetto) a parità di numero di treni")
say(@sprintf("   %-26s %3s %10s %10s %8s   %14s   %14s", "fasce (Δm oltre 0,1; Δn)", "K", "medio", "peggiore", ">10%", "scelta libera", "p-mediana"))
righe_f = []
for dm in (Inf, 0.2, 0.1, 0.05), dn in (1.0, 0.5, 0.34, 0.25, 0.2, 0.1)
    f = fasce(dm, dn)
    nome = @sprintf("Δm %s, Δn %.2f", isinf(dm) ? "—   " : @sprintf("%.2f", dm), dn)
    f === nothing && (say("   ", nome, ": una fascia senza treni che funzionino su tutte le sue linee"); continue)
    f.K > 15 && continue
    push!(righe_f, (dm = dm, dn = dn, f...))
    say(@sprintf("   %-26s %3d %10s %10s %8d   %14s   %14s", nome, f.K, pct(mean(f.ex)), pct(maximum(f.ex)), count(>(0.1), f.ex),
                 pct(mean(f.ex_lib)), f.K in Ks("senza") ? pct(medio("senza", f.K)) : "—"))
end
# il migliore schema di fasce per ogni K
say("\n   per ogni K, lo schema di fasce migliore contro la p-mediana:")
for K in sort(unique(r.K for r in righe_f))
    r = righe_f[argmin([x.K == K ? mean(x.ex) : Inf for x in righe_f])]
    say(@sprintf("   K = %2d: fasce %s (Δm %s, Δn %.2f), p-mediana %s, cioè %.1f volte", K, pct(mean(r.ex)), isinf(r.dm) ? "—" : @sprintf("%.2f", r.dm), r.dn,
                 pct(medio("senza", K)), mean(r.ex) / medio("senza", K)))
end

# ── 2. la curva extra-costo contro K ─────────────────────────────────────────────
colori = Dict("senza" => :black, "10" => :firebrick, "15" => :darkorange)
nomi = Dict("senza" => "p-mediana senza tetto", "10" => "p-mediana, tetto +10%", "15" => "p-mediana, tetto +15%")
p1 = plot(xlabel = "numero di treni K", ylabel = "extra-costo medio [%]", yscale = :log10, yticks = ([1, 2, 3, 5, 10, 20, 50, 100], string.([1, 2, 3, 5, 10, 20, 50, 100])),
          xticks = 1:15, legend = :topright, title = "extra-costo medio delle 146 linee")
p2 = plot(xlabel = "numero di treni K", ylabel = "linea peggiore [%]", yscale = :log10, ylims = (7, 230), yticks = ([5, 10, 20, 50, 100, 200], string.([5, 10, 20, 50, 100, 200])),
          xticks = 1:15, legend = false, title = "extra-costo della linea peggiore")
for t in ("senza", "15", "10")
    k = Ks(t)
    plot!(p1, k, [100medio(t, K) for K in k]; color = colori[t], marker = :circle, lw = 2, label = nomi[t])
    plot!(p2, k, [100peggiore(t, K) for K in k]; color = colori[t], marker = :circle, lw = 2)
end
scatter!(p1, [r.K for r in righe_f], [100mean(r.ex) for r in righe_f]; color = :steelblue, marker = :diamond, ms = 5, label = "fasce di m e n")
scatter!(p2, [r.K for r in righe_f], [100maximum(r.ex) for r in righe_f]; color = :steelblue, marker = :diamond, ms = 5)
hline!(p2, [10]; color = :gray, ls = :dash)
savefig(plot(p1, p2; layout = (1, 2), size = (1400, 520), dpi = 120, left_margin = 8Plots.mm, bottom_margin = 8Plots.mm), joinpath(FIG, "fig_curva.png"))

# ── 3. le flotte nel piano (m, n) ────────────────────────────────────────────────
pal = palette(:tab20)
function piano(chiave, titolo)
    r = PM[chiave]; fl = r.flotta
    p = plot(xlabel = "m (fuel cell)", ylabel = "n (batteria)", xlims = (-0.02, 0.5), ylims = (0.2, 1.0), legend = false, title = titolo)
    for (c, j) in enumerate(fl)
        li = findall(==(j), r.ass)
        scatter!(p, mo[li] .+ 0.004 .* randn(length(li)), no[li]; color = pal[c], ms = 4, msw = 0, alpha = 0.8)
        scatter!(p, [m[j]], [n[j]]; color = pal[c], marker = :star5, ms = 12, msc = :black)
    end
    return p
end
import Random; Random.seed!(1)
pp = [piano("senza_5", @sprintf("K = 5 senza tetto (medio %s)", pct(medio("senza", 5)))),
      piano("10_8", @sprintf("K = 8, tetto +10%% (medio %s)", pct(medio("10", 8)))),
      piano("senza_15", @sprintf("K = 15 (medio %s)", pct(medio("senza", 15))))]
savefig(plot(pp...; layout = (1, 3), size = (1700, 560), dpi = 120, left_margin = 8Plots.mm, bottom_margin = 8Plots.mm,
             plot_title = "punti = ottimo di ogni linea (colore = treno assegnato), stelle = treni della flotta"), joinpath(FIG, "fig_piano_mn.png"))

# ── 4. la mappa della flotta K = 8 con tetto +10% ────────────────────────────────
geo = JSON.parsefile(joinpath(@__DIR__, "..", "fase13", "presentazione_146", "linee_146.geojson"))
r = PM["10_8"]; fl = r.flotta; idx = Dict(l => i for (i, l) in enumerate(linee))
pm = plot(aspect_ratio = 1.3, legend = :bottomleft, xlabel = "longitudine", ylabel = "latitudine", size = (950, 1100), dpi = 120,
          title = @sprintf("flotta di 8 treni con tetto +10%%: extra-costo medio %s", pct(medio("10", 8))))
visti = Set{Int}()
for f in geo["features"]
    i = idx[f["properties"]["linea"]]; c = findfirst(==(r.ass[i]), fl); j = fl[c]
    for tr in f["geometry"]["coordinates"]
        lab = c in visti ? "" : @sprintf("m %.2f n %.2f (%s, %d linee)", m[j], n[j], m[j] == 0 ? @sprintf("%.0f kWh", C_BATT[j]) : @sprintf("FC %.0f kW", P_FC[j]),
                                          count(==(j), r.ass))
        plot!(pm, [p[1] for p in tr], [p[2] for p in tr]; color = pal[c], lw = 2.5, label = lab); push!(visti, c)
    end
end
savefig(pm, joinpath(FIG, "fig_mappa_K8.png"))
say("\nFigure: fase14/figure/fig_curva.png, fig_piano_mn.png, fig_mappa_K8.png")
close(OUT)
