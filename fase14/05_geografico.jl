# fase14/05_geografico.jl: la p-mediana con il criterio geografico (a): due linee che hanno in comune almeno il 25% della lunghezza
# della più lunga devono usare lo stesso treno. Confronto anche con la soglia del 50%.
#
#   julia --project=fase14 fase14/05_geografico.jl > ~/Documents/lavoro/ml_treno_dati/fase14_log/log_05.txt 2>&1
#
# Km in comune: dai sezioni.csv dei dati sorgente (Drive del 17/11, copia locale ml_treno_dati/linee_rinf_sorgente). Ogni sezione va da
# una località RINF a un'altra (codice_da, codice_a): due linee condividono una sezione se hanno la stessa coppia di codici (in un
# verso o nell'altro); i km in comune sono la somma delle lunghezze delle sezioni condivise (la minore delle due, se differiscono).
# "Stesso treno" è transitivo: se A–B e B–C devono avere lo stesso treno, anche A e C. Le linee si raggruppano quindi nei gruppi
# connessi del grafo "km in comune oltre la soglia", e ogni gruppo usa un solo treno, che deve funzionare su tutte le sue linee.
# Modello: la p-mediana di fase14/02 sui gruppi invece che sulle linee (costo di un gruppo = somma degli extra-costi delle sue linee),
# con la stessa media sulle 146 linee; con il tetto, il treno di un gruppo deve stare entro il tetto su ogni sua linea.

using JLD2, JSON, JuMP, HiGHS, Statistics, Printf, Dates, Plots
gr()
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase14_log")
const FIG = joinpath(@__DIR__, "figure")
const OUT = open(joinpath(LOG, "05_geografico.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase14/05_geografico.jl  ", now(), "  JuMP ", pkgversion(JuMP), "  HiGHS ", pkgversion(HiGHS))
const T0 = time()
const D = load(joinpath(BASE, "fase14", "tabella.jld2"))
const linee, m, n, P_FC, C_BATT, R, tenuti = D["linee"], D["m"], D["n"], D["P_FC"], D["C_BATT"], D["R"], D["tenuti"]
const NL = length(linee)
const PM = load(joinpath(BASE, "fase14", "pmediana.jld2"))["ris"]
const KMAX = 15
const LIMITE_S = 600.0
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
pct(x) = @sprintf("%+.2f%%", 100x)

# ── 1. km in comune ──────────────────────────────────────────────────────────────
const SRC = joinpath(BASE, "linee_rinf_sorgente")
cartella = Dict{String,String}()
for reg in readdir(SRC), l in (isdir(joinpath(SRC, reg)) ? readdir(joinpath(SRC, reg)) : String[])
    isfile(joinpath(SRC, reg, l, "sezioni.csv")) && (cartella[l] = joinpath(SRC, reg, l))
end
function leggi_sezioni(l)
    r = readlines(joinpath(cartella[l], "sezioni.csv")); h = split(r[1], ',')
    ia, ib, il = findfirst(==("codice_da"), h), findfirst(==("codice_a"), h), findfirst(==("lunghezza_km"), h)
    d = Dict{Set{String},Float64}(); L = 0.0
    for x in r[2:end]
        isempty(strip(x)) && continue
        c = split(x, ','); km = parse(Float64, c[il]); L += km
        d[Set([String(c[ia]), String(c[ib])])] = km
    end
    return d, L
end
SEZ = Dict(l => leggi_sezioni(l) for l in linee)
comune = zeros(NL, NL)
for a in 1:NL, b in a+1:NL
    sa, sb = SEZ[linee[a]][1], SEZ[linee[b]][1]
    comune[a, b] = comune[b, a] = sum((min(sa[k], sb[k]) for k in intersect(keys(sa), keys(sb))); init = 0.0)
end
Lkm = [SEZ[l][2] for l in linee]
quota(a, b) = comune[a, b] / max(Lkm[a], Lkm[b])
open(joinpath(LOG, "05_km_in_comune.csv"), "w") do io
    println(io, "linea_a,linea_b,km_in_comune,L_a_km,L_b_km,quota_della_piu_lunga")
    for a in 1:NL, b in a+1:NL
        comune[a, b] > 0 && println(io, join((linee[a], linee[b], @sprintf("%.3f", comune[a, b]), @sprintf("%.3f", Lkm[a]), @sprintf("%.3f", Lkm[b]), @sprintf("%.4f", quota(a, b))), ','))
    end
end
say(@sprintf("1. km in comune: %d coppie di linee con almeno una sezione in comune; quota della più lunga ≥ 10%%: %d, ≥ 25%%: %d, ≥ 50%%: %d",
             count(>(0), comune) ÷ 2, count(((a, b),) -> a < b && quota(a, b) >= 0.10, Iterators.product(1:NL, 1:NL)),
             count(((a, b),) -> a < b && quota(a, b) >= 0.25, Iterators.product(1:NL, 1:NL)), count(((a, b),) -> a < b && quota(a, b) >= 0.50, Iterators.product(1:NL, 1:NL))))

"""I gruppi connessi del grafo "quota in comune ≥ soglia"."""
function gruppi(soglia)
    p = collect(1:NL)
    trova(x) = (while p[x] != x; p[x] = p[p[x]]; x = p[x]; end; x)
    for a in 1:NL, b in a+1:NL
        quota(a, b) >= soglia && (p[trova(a)] = trova(b))
    end
    g = Dict{Int,Vector{Int}}(); for i in 1:NL; push!(get!(g, trova(i), Int[]), i); end
    return sort(collect(values(g)); by = v -> (-length(v), linee[v[1]]))
end

# ── 2. p-mediana sui gruppi ──────────────────────────────────────────────────────
function pmediana_gruppi(G, K, tetto)
    ok(g, j) = all(i -> isfinite(R[i, j]) && R[i, j] <= tetto, g)
    coppie = [(k, j) for (k, g) in enumerate(G) for j in tenuti if ok(g, j)]
    per_g = [Int[] for _ in G]; for (k, j) in coppie; push!(per_g[k], j); end
    any(isempty, per_g) && return nothing
    md = Model(HiGHS.Optimizer); set_silent(md); set_time_limit_sec(md, LIMITE_S)
    @variable(md, y[tenuti], Bin); @variable(md, x[coppie] >= 0)
    for k in eachindex(G); @constraint(md, sum(x[(k, j)] for j in per_g[k]) == 1); end
    for p in coppie; @constraint(md, x[p] <= y[p[2]]); end
    @constraint(md, sum(y) == K)
    @objective(md, Min, sum(sum(R[i, p[2]] for i in G[p[1]]) * x[p] for p in coppie) / NL)
    t = time(); optimize!(md); t = time() - t
    st = termination_status(md)
    (st == MOI.OPTIMAL || (st == MOI.TIME_LIMIT && has_values(md))) || return nothing
    flotta = sort([j for j in tenuti if value(y[j]) > 0.5]; by = j -> (m[j], n[j]))
    ass = zeros(Int, NL)
    for g in G
        c = [ok(g, j) ? sum(R[i, j] for i in g) : Inf for j in flotta]
        ass[g] .= flotta[argmin(c)]
    end
    ex = [R[i, ass[i]] for i in 1:NL]
    abs(mean(ex) - objective_value(md)) < 1e-6 || error("K = $K: ricontrollo non torna")
    return (flotta = flotta, ass = ass, ex = ex, t = t, stato = st, gap = relative_gap(md))
end

ris = Dict{Tuple{Float64,Float64,Int},Any}()
for soglia in (0.25, 0.50)
    G = gruppi(soglia)
    say(@sprintf("\n2. SOGLIA %.0f%%: %d gruppi (%d linee da sole); i gruppi con più di 2 linee:", 100soglia, length(G), count(g -> length(g) == 1, G)))
    for g in G
        length(g) > 2 || continue
        say(@sprintf("   %2d linee, %5.1f–%5.1f km, ottimi: %d sola batteria, %d FC piccola, %d ibridi: %s", length(g), minimum(Lkm[g]), maximum(Lkm[g]),
                     count(i -> m[D["jopt"][i]] == 0, g), count(i -> 0 < m[D["jopt"][i]] < 0.1, g), count(i -> m[D["jopt"][i]] >= 0.1, g), join(linee[g], ", ")))
    end
    # il miglior treno di ogni gruppo da solo (K = numero di gruppi): quanto costa già solo stare insieme
    best = [minimum(j -> all(i -> isfinite(R[i, j]), g) ? sum(R[i, j] for i in g) : Inf, tenuti) for g in G]
    say(@sprintf("   con un treno per gruppo (K = %d gruppi) l'extra-costo medio è già %s: è il prezzo minimo dei gruppi", length(G), pct(sum(best) / NL)))
    for tetto in (Inf, 0.10, 0.15, 0.20)
        nessuno = [g for g in G if !any(j -> all(i -> isfinite(R[i, j]) && R[i, j] <= tetto, g), tenuti)]
        if !isempty(nessuno)
            say(@sprintf("   tetto +%.0f%%: impossibile, %d gruppi non hanno un treno entro il tetto su tutte le loro linee (per esempio %s)", 100tetto, length(nessuno),
                         join(linee[nessuno[1]][1:min(3, end)], ", ")))
            continue
        end
        nome = tetto == Inf ? "senza tetto" : @sprintf("tetto +%.0f%%", 100tetto)
        say(@sprintf("\n   %s — %3s %10s %10s %6s   %22s", nome, "K", "medio", "peggiore", ">10%", "senza criterio geografico"))
        for K in 1:KMAX
            r = pmediana_gruppi(G, K, tetto)
            r === nothing && continue
            ris[(soglia, tetto, K)] = r
            ch = tetto == Inf ? "senza_$K" : tetto == 0.10 ? "10_$K" : tetto == 0.15 ? "15_$K" : ""
            say(@sprintf("   %s   %3d %10s %10s %6d   %22s%s", " "^length(nome), K, pct(mean(r.ex)), pct(maximum(r.ex)), count(>(0.1), r.ex),
                         haskey(PM, ch) ? pct(mean(PM[ch].ex)) : "—", r.stato == MOI.OPTIMAL ? "" : @sprintf("   (limite di tempo, gap %.2g)", r.gap)))
        end
    end
end

# ── 3. qualche flotta per esteso ─────────────────────────────────────────────────
say("\n3. FLOTTE CON IL CRITERIO GEOGRAFICO (soglia 25%)")
for (tetto, K) in ((Inf, 5), (Inf, 8), (Inf, 10))
    haskey(ris, (0.25, tetto, K)) || continue
    r = ris[(0.25, tetto, K)]
    say(@sprintf("\n   %s, K = %d: extra-costo medio %s, peggiore %s", tetto == Inf ? "senza tetto" : @sprintf("tetto +%.0f%%", 100tetto), K, pct(mean(r.ex)), pct(maximum(r.ex))))
    for j in r.flotta
        li = findall(==(j), r.ass)
        say(@sprintf("     m %.2f n %.2f  %-18s FC %4.0f kW  batteria %4.0f kWh  %3d linee  medio %s, peggiore %s (%s)", m[j], n[j], regime(m[j]), P_FC[j], C_BATT[j],
                     length(li), pct(mean(r.ex[li])), pct(maximum(r.ex[li])), linee[li[argmax(r.ex[li])]]))
    end
end

# ── 4. tabelle, figure ───────────────────────────────────────────────────────────
nt(t) = t == Inf ? "senza" : @sprintf("%.0f", 100t)
open(joinpath(LOG, "05_assegnazioni.csv"), "w") do io
    println(io, "soglia_pct,tetto_pct,K,linea,m_treno,n_treno,regime_treno,extra_pct")
    for ((s, t, K), r) in sort(collect(ris); by = first), i in 1:NL
        j = r.ass[i]; println(io, join((@sprintf("%.0f", 100s), nt(t), K, linee[i], m[j], n[j], regime(m[j]), @sprintf("%.4f", 100r.ex[i])), ','))
    end
end
jldsave(joinpath(BASE, "fase14", "geografico.jld2"); comune, Lkm, ris = Dict(string(@sprintf("%.0f", 100k[1]), "_", nt(k[2]), "_", k[3]) => (flotta = v.flotta, ass = v.ass, ex = v.ex) for (k, v) in ris))

# curva: con e senza criterio geografico
p = plot(xlabel = "numero di treni K", ylabel = "extra-costo medio [%]", yscale = :log10, yticks = ([1, 2, 3, 5, 10, 20, 50, 100], string.([1, 2, 3, 5, 10, 20, 50, 100])),
         xticks = 1:15, legend = :topright, size = (900, 560), dpi = 120, left_margin = 6Plots.mm, bottom_margin = 6Plots.mm,
         title = "criterio geografico: extra-costo medio contro K")
k0 = 1:KMAX; plot!(p, k0, [100mean(PM["senza_$K"].ex) for K in k0]; color = :black, marker = :circle, lw = 2, label = "senza criterio geografico")
for (s, c) in ((0.25, :firebrick), (0.50, :darkorange))
    k = sort([K for (ss, t, K) in keys(ris) if ss == s && t == Inf])
    plot!(p, k, [100mean(ris[(s, Inf, K)].ex) for K in k]; color = c, marker = :circle, lw = 2, label = @sprintf("stesso treno se in comune ≥ %.0f%%", 100s))
end
savefig(p, joinpath(FIG, "fig_geografico_curva.png"))
# mappa K = 8 con soglia 25%
if haskey(ris, (0.25, Inf, 8))
    geo = JSON.parsefile(joinpath(@__DIR__, "..", "fase13", "presentazione_146", "linee_146.geojson"))
    r = ris[(0.25, Inf, 8)]; fl = r.flotta; idx = Dict(l => i for (i, l) in enumerate(linee)); pal = palette(:tab20)
    pm = plot(aspect_ratio = 1.3, legend = :bottomleft, xlabel = "longitudine", ylabel = "latitudine", size = (950, 1100), dpi = 120,
              title = @sprintf("8 treni, stesso treno se in comune ≥ 25%%: extra-costo medio %s", pct(mean(r.ex))))
    visti = Set{Int}()
    for f in geo["features"]
        i = idx[f["properties"]["linea"]]; c = findfirst(==(r.ass[i]), fl); j = fl[c]
        for tr in f["geometry"]["coordinates"]
            lab = c in visti ? "" : @sprintf("m %.2f n %.2f (%s, %d linee)", m[j], n[j], m[j] == 0 ? @sprintf("%.0f kWh", C_BATT[j]) : @sprintf("FC %.0f kW", P_FC[j]), count(==(j), r.ass))
            plot!(pm, [q[1] for q in tr], [q[2] for q in tr]; color = pal[c], lw = 2.5, label = lab); push!(visti, c)
        end
    end
    savefig(pm, joinpath(FIG, "fig_geografico_mappa_K8.png"))
end
say(@sprintf("\nTabelle: 05_km_in_comune.csv, 05_assegnazioni.csv; figure: fase14/figure/fig_geografico_*.png. Tempo totale %.1f min", (time() - T0) / 60))
close(OUT)
