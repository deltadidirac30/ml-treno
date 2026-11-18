# fase14/04_modulari.jl: flotte modulari. Invece di K coppie (m, n) libere si scelgono a taglie di fuel cell e b taglie di batteria;
# i treni disponibili sono tutte le combinazioni (più i treni a sola batteria, m = 0, con le stesse b batterie: "nessuna fuel cell" è
# sempre possibile). Ogni linea usa la combinazione che le costa meno fra quelle che funzionano; si minimizza l'extra-costo medio.
#
#   julia --project=fase14 fase14/04_modulari.jl > ~/Documents/lavoro/ml_treno_dati/fase14_log/log_04.txt 2>&1
#
# Modello (esatto, JuMP + HiGHS), sulla tabella intera di fase14/01 (qui la riduzione ai treni non dominati non vale):
#   u[m] ∈ {0,1}: la taglia di fuel cell m è in catalogo (m 0,03–0,99); Σ u = a;
#   v[n] ∈ {0,1}: la taglia di batteria n è in catalogo (n 0,01–0,99); Σ v = b;
#   x[i, j] ≥ 0: la linea i usa il treno j = (m, n); Σ_j x[i, j] = 1;
#   Σ_{j con taglia m} x[i, j] ≤ u[m] e Σ_{j con batteria n} x[i, j] ≤ v[n] per ogni linea i (forma più stretta di x ≤ u, x ≤ v).
# Per tenere il modello piccolo, x[i, j] esiste solo se l'extra-costo R[i, j] ≤ SOGLIA (50%); la soglia si controlla rifacendo
# una configurazione senza soglia, e se esclude ogni scelta di una linea si rifà senza soglia. Con il tetto la soglia è il tetto:
# prima si cerca il catalogo più piccolo (a + b minimo) che rispetta il tetto (10%, 15%, 20%), poi la flotta migliore con quel catalogo.
# Il confronto è con la p-mediana (fase14/02) con lo stesso numero di treni effettivamente usati.

using JLD2, JuMP, HiGHS, Statistics, Printf, Dates
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase14_log")
const OUT = open(joinpath(LOG, "04_modulari.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase14/04_modulari.jl  ", now(), "  JuMP ", pkgversion(JuMP), "  HiGHS ", pkgversion(HiGHS))
const T0 = time()
const D = load(joinpath(BASE, "fase14", "tabella.jld2"))
const linee, m, n, P_FC, C_BATT, R = D["linee"], D["m"], D["n"], D["P_FC"], D["C_BATT"], D["R"]
const NL, NG = size(R)
const PM = load(joinpath(BASE, "fase14", "pmediana.jld2"))["ris"]
const SOGLIA = 0.5
const LIMITE_S = 900.0
const VM = sort(unique(m[m .> 0])); const VN = sort(unique(n))
pct(x) = @sprintf("%+.2f%%", 100x)
kw(x) = P_FC[findfirst(j -> m[j] == x && isfinite(P_FC[j]), 1:NG)]       # taglie: dipendono solo da m (o da n), vedi fase14/01
kwh(x) = C_BATT[findfirst(j -> n[j] == x && isfinite(C_BATT[j]), 1:NG)]

function modulare(a, b, tetto; soglia = SOGLIA)
    lim = min(tetto, soglia)
    coppie = [(i, j) for i in 1:NL for j in 1:NG if isfinite(R[i, j]) && R[i, j] <= lim]
    md = Model(HiGHS.Optimizer); set_silent(md); set_time_limit_sec(md, LIMITE_S)
    @variable(md, u[VM], Bin); @variable(md, v[VN], Bin)
    @variable(md, x[coppie] >= 0)
    per_linea = [Tuple{Int,Int}[] for _ in 1:NL]
    for p in coppie; push!(per_linea[p[1]], p); end
    for i in 1:NL
        isempty(per_linea[i]) && return nothing
        @constraint(md, sum(x[p] for p in per_linea[i]) == 1)
        for (val, grp) in ((mv, [p for p in per_linea[i] if m[p[2]] == mv]) for mv in VM)
            isempty(grp) || @constraint(md, sum(x[p] for p in grp) <= u[val])
        end
        for (val, grp) in ((nv, [p for p in per_linea[i] if n[p[2]] == nv]) for nv in VN)
            isempty(grp) || @constraint(md, sum(x[p] for p in grp) <= v[val])
        end
    end
    @constraint(md, sum(u) == a); @constraint(md, sum(v) == b)
    @objective(md, Min, sum(R[p...] * x[p] for p in coppie) / NL)
    t = time(); optimize!(md); t = time() - t
    st = termination_status(md)
    (st == MOI.OPTIMAL || (st == MOI.TIME_LIMIT && has_values(md))) || return nothing
    fc = [mv for mv in VM if value(u[mv]) > 0.5]; bt = [nv for nv in VN if value(v[nv]) > 0.5]
    # ricontrollo: ogni linea prende la combinazione disponibile più economica (entro il tetto)
    disp = [j for j in 1:NG if (m[j] == 0 || m[j] in fc) && n[j] in bt]
    ass = [disp[argmin([R[i, j] <= tetto ? R[i, j] : Inf for j in disp])] for i in 1:NL]
    ex = [R[i, ass[i]] for i in 1:NL]
    all(isfinite, ex) || return nothing
    abs(mean(ex) - objective_value(md)) < 1e-6 || say(@sprintf("   ATTENZIONE a=%d b=%d: ricontrollo %.6f contro modello %.6f", a, b, mean(ex), objective_value(md)))
    return (fc = fc, bt = bt, ass = ass, ex = ex, usati = length(unique(ass)), t = t, stato = st, gap = relative_gap(md), var = length(coppie))
end

# ── 1. controllo della soglia ────────────────────────────────────────────────────
say("\n1. controllo della soglia (a = 2 taglie di FC, b = 3 di batteria): soglia 50% contro nessuna soglia")
r1 = modulare(2, 3, Inf); r2 = modulare(2, 3, Inf; soglia = Inf)
say(@sprintf("   soglia 50%%: %s (%d variabili, %.0f s); senza soglia: %s (%d variabili, %.0f s, %s)", pct(mean(r1.ex)), r1.var, r1.t,
             r2 === nothing ? "—" : pct(mean(r2.ex)), r2 === nothing ? 0 : r2.var, r2 === nothing ? 0 : r2.t, r2 === nothing ? "nessuna soluzione" : string(r2.stato)))

# ── 2. le configurazioni ─────────────────────────────────────────────────────────
ris = Dict{Tuple{Float64,Int,Int},Any}()
for (tetto, nome) in ((Inf, "SENZA TETTO"),)
    say("\n2. ", nome, ": a taglie di fuel cell (più i treni senza FC) × b taglie di batteria")
    say(@sprintf("   %2s %2s %8s %6s %10s %10s %6s   %14s   %s", "a", "b", "taglie", "treni", "medio", "peggiore", ">10%", "p-mediana", "taglie scelte"))
    for a in 1:4, b in 2:5
        r = modulare(a, b, tetto)
        r === nothing && tetto == Inf && (r = modulare(a, b, tetto; soglia = Inf))   # la soglia può escludere l'unica scelta di una linea
        r === nothing && (say(@sprintf("   %2d %2d  nessuna soluzione", a, b)); continue)
        ris[(tetto, a, b)] = r
        k = r.usati; ch = string(tetto == Inf ? "senza" : "10", "_", k)
        say(@sprintf("   %2d %2d %8d %6d %10s %10s %6d   %14s   FC %s kW; batterie %s kWh%s", a, b, a + b, k, pct(mean(r.ex)), pct(maximum(r.ex)), count(>(0.10), r.ex),
                     haskey(PM, ch) ? pct(mean(PM[ch].ex)) : "—",
                     join((@sprintf("%.0f", kw(x)) for x in r.fc), "/"), join((@sprintf("%.0f", kwh(x)) for x in r.bt), "/"),
                     r.stato == MOI.OPTIMAL ? "" : @sprintf("   (limite di tempo, gap %.2g)", r.gap)))
    end
end

# ── 2b. con il tetto: il catalogo più piccolo che lo rispetta ─────────────────────
"""Il catalogo (a taglie di FC, b di batteria) con a + b minimo tale che ogni linea abbia una combinazione entro il tetto."""
function catalogo_minimo(tetto)
    coppie = [(i, j) for i in 1:NL for j in 1:NG if isfinite(R[i, j]) && R[i, j] <= tetto]
    md = Model(HiGHS.Optimizer); set_silent(md); set_time_limit_sec(md, LIMITE_S)
    @variable(md, u[VM], Bin); @variable(md, v[VN], Bin); @variable(md, x[coppie] >= 0)
    for i in 1:NL
        pl = [p for p in coppie if p[1] == i]
        @constraint(md, sum(x[p] for p in pl) == 1)
        for mv in VM; g = [p for p in pl if m[p[2]] == mv]; isempty(g) || @constraint(md, sum(x[p] for p in g) <= u[mv]); end
        for nv in VN; g = [p for p in pl if n[p[2]] == nv]; isempty(g) || @constraint(md, sum(x[p] for p in g) <= v[nv]); end
    end
    @objective(md, Min, sum(u) + sum(v) + 1e-3 * sum(u))      # a parità di taglie, meno fuel cell
    optimize!(md)
    termination_status(md) == MOI.OPTIMAL || return nothing
    return (a = round(Int, sum(value.(u))), b = round(Int, sum(value.(v))))
end
say("\n2b. CON IL TETTO: il catalogo più piccolo (a + b minimo) che tiene ogni linea entro il tetto, e la flotta migliore con quel catalogo")
for tetto in (0.10, 0.15, 0.20)
    c = catalogo_minimo(tetto)
    c === nothing && (say(@sprintf("   tetto +%.0f%%: nessun catalogo", 100tetto)); continue)
    for (a, b) in ((c.a, c.b), (c.a, c.b + 1), (c.a + 1, c.b))
        r = modulare(a, b, tetto)
        r === nothing && (say(@sprintf("   tetto +%.0f%%: %d FC × %d batterie: nessuna soluzione", 100tetto, a, b)); continue)
        ris[(tetto, a, b)] = r
        ch = string("10_", r.usati)
        say(@sprintf("   tetto +%.0f%%: %d FC × %d batterie (%d taglie%s): %d treni usati, medio %s, peggiore %s   [p-mediana con tetto +10%% e %d treni: %s]   FC %s kW; batterie %s kWh",
                     100tetto, a, b, a + b, (a, b) == (c.a, c.b) ? ", il minimo" : "", r.usati, pct(mean(r.ex)), pct(maximum(r.ex)), r.usati,
                     haskey(PM, ch) ? pct(mean(PM[ch].ex)) : "—", join((@sprintf("%.0f", kw(x)) for x in r.fc), "/"), join((@sprintf("%.0f", kwh(x)) for x in r.bt), "/")))
    end
end

# ── 3. qualche flotta per esteso ─────────────────────────────────────────────────
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
say("\n3. FLOTTE MODULARI PER ESTESO (solo le combinazioni usate)")
for (tetto, a, b) in vcat([(Inf, 2, 3), (Inf, 3, 4), (Inf, 4, 5)], sort([k for k in keys(ris) if k[1] == 0.10]))
    haskey(ris, (tetto, a, b)) || continue
    r = ris[(tetto, a, b)]
    say(@sprintf("\n   %s, %d FC × %d batterie: %d treni usati, extra-costo medio %s, peggiore %s", tetto == Inf ? "senza tetto" : "tetto +10%", a, b, r.usati,
                 pct(mean(r.ex)), pct(maximum(r.ex))))
    for j in sort(unique(r.ass); by = j -> (m[j], n[j]))
        li = findall(==(j), r.ass)
        say(@sprintf("     m %.2f n %.2f  %-18s FC %4.0f kW  batteria %4.0f kWh  %3d linee  medio %s, peggiore %s", m[j], n[j], regime(m[j]), P_FC[j], C_BATT[j],
                     length(li), pct(mean(r.ex[li])), pct(maximum(r.ex[li]))))
    end
end

open(joinpath(LOG, "04_modulari.csv"), "w") do io
    println(io, "tetto_pct,a_FC,b_batt,treni_usati,extra_medio_pct,extra_peggiore_pct,linee_oltre_10pct,FC_m,batt_n")
    for ((tetto, a, b), r) in sort(collect(ris); by = first)
        println(io, join((tetto == Inf ? "senza" : @sprintf("%.0f", 100tetto), a, b, r.usati, @sprintf("%.3f", 100mean(r.ex)), @sprintf("%.3f", 100maximum(r.ex)), count(>(0.1), r.ex),
                          join(r.fc, ' '), join(r.bt, ' ')), ','))
    end
end
jldsave(joinpath(BASE, "fase14", "modulari.jld2"); ris = Dict(string(k[1] == Inf ? "senza" : @sprintf("%.0f", 100k[1]), "_", k[2], "_", k[3]) => (fc = v.fc, bt = v.bt, ass = v.ass, ex = v.ex) for (k, v) in ris))
say(@sprintf("\nTabella: %s. Tempo totale %.1f min", joinpath(LOG, "04_modulari.csv"), (time() - T0) / 60))
close(OUT)
