# fase14/02_pmediana.jl: la flotta di K treni standard (K = 1…15) che rende minimo l'extra-costo medio delle 146 linee (p-mediana),
# risolta in modo esatto con JuMP + HiGHS sulla tabella di fase14/01 (i 1985 treni non dominati).
#
#   julia --project=fase14 fase14/02_pmediana.jl > ~/Documents/lavoro/ml_treno_dati/fase14_log/log_02.txt 2>&1
#
# Il modello, per un K dato:
#   y[j] ∈ {0, 1}   il treno j fa parte della flotta;
#   x[i, j] ≥ 0     la linea i usa il treno j (definita solo se j funziona su i, e con il tetto solo se R[i, j] ≤ tetto);
#   Σ_j x[i, j] = 1 per ogni linea;  x[i, j] ≤ y[j];  Σ_j y[j] = K;
#   minimo di (1/146) Σ R[i, j] x[i, j]  (extra-costo medio, stesso peso per ogni linea).
# Con y intere, la x migliore è intera: ogni linea usa il treno della flotta che le costa meno (lo si ricontrolla dopo).
# Due versioni: senza tetto, e con tetto (nessuna linea oltre +10%; per i K in cui non è possibile anche +15%). Per ogni tetto si
# calcola prima il K minimo con cui è rispettabile (copertura: il minimo numero di treni che coprono tutte le linee entro il tetto).
# Uscite in ml_treno_dati/fase14_log: 02_pmediana.txt (riassunto), 02_flotte.csv (i treni), 02_assegnazioni.csv (linea → treno).

using JLD2, JuMP, HiGHS, Statistics, Printf, Dates
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase14_log")
const OUT = open(joinpath(LOG, "02_pmediana.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase14/02_pmediana.jl  ", now(), "  JuMP ", pkgversion(JuMP), "  HiGHS ", pkgversion(HiGHS))
const T0 = time()
const D = load(joinpath(BASE, "fase14", "tabella.jld2"))
const linee, m, n, P_FC, C_BATT, R, tenuti = D["linee"], D["m"], D["n"], D["P_FC"], D["C_BATT"], D["R"], D["tenuti"]
const NL = length(linee)
const KMAX = 15
const LIMITE_S = 600.0          # tempo massimo per un problema; se si arriva al limite si riporta lo scarto (gap) dall'ottimo
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
pct(x) = @sprintf("%+.2f%%", 100x)

"""Il K minimo per coprire tutte le linee con treni entro il tetto (copertura minima, esatta)."""
function k_minimo(tetto)
    md = Model(HiGHS.Optimizer); set_silent(md); set_time_limit_sec(md, LIMITE_S)
    @variable(md, y[tenuti], Bin)
    for i in 1:NL
        js = [j for j in tenuti if R[i, j] <= tetto]
        isempty(js) && return typemax(Int)
        @constraint(md, sum(y[j] for j in js) >= 1)
    end
    @objective(md, Min, sum(y)); optimize!(md)
    return round(Int, objective_value(md))
end

"""p-mediana esatta: la flotta di K treni con l'extra-costo medio minimo; `tetto` = Inf per nessun tetto."""
function pmediana(K, tetto)
    md = Model(HiGHS.Optimizer); set_silent(md); set_time_limit_sec(md, LIMITE_S)
    coppie = [(i, j) for i in 1:NL for j in tenuti if R[i, j] <= tetto]      # Inf <= Inf: con tetto = Inf vanno escluse le non fattibili
    filter!(p -> isfinite(R[p...]), coppie)
    @variable(md, y[tenuti], Bin)
    @variable(md, x[coppie] >= 0)
    per_linea = [Tuple{Int,Int}[] for _ in 1:NL]; per_treno = Dict(j => Tuple{Int,Int}[] for j in tenuti)
    for p in coppie; push!(per_linea[p[1]], p); push!(per_treno[p[2]], p); end
    for i in 1:NL; @constraint(md, sum(x[p] for p in per_linea[i]) == 1); end
    for p in coppie; @constraint(md, x[p] <= y[p[2]]); end
    @constraint(md, sum(y) == K)
    @objective(md, Min, sum(R[p...] * x[p] for p in coppie) / NL)
    t = time(); optimize!(md); t = time() - t
    st = termination_status(md)
    (st == MOI.OPTIMAL || (st == MOI.TIME_LIMIT && has_values(md))) || return nothing
    flotta = sort([j for j in tenuti if value(y[j]) > 0.5]; by = j -> (m[j], n[j]))
    # ricontrollo: ogni linea usa il treno della flotta che le costa meno (entro il tetto)
    ass = [flotta[argmin([R[i, j] <= tetto ? R[i, j] : Inf for j in flotta])] for i in 1:NL]
    ex = [R[i, ass[i]] for i in 1:NL]
    abs(mean(ex) - objective_value(md)) < 1e-6 || error("K = $K: l'assegnazione ricontrollata non torna con il modello")
    return (flotta = flotta, ass = ass, ex = ex, t = t, gap = relative_gap(md), stato = st, var = length(coppie))
end

# ── 1. il K minimo per ogni tetto ────────────────────────────────────────────────
const TETTI = [(Inf, "senza tetto"), (0.10, "tetto +10%"), (0.15, "tetto +15%")]
kmin = Dict(t => (t == Inf ? 1 : k_minimo(t)) for (t, _) in TETTI)
say(@sprintf("1. numero minimo di treni per rispettare il tetto: +10%% → %d treni; +15%% → %d treni", kmin[0.10], kmin[0.15]))

# ── 2. la p-mediana per K = 1…15 ─────────────────────────────────────────────────
ris = Dict{Tuple{Float64,Int},Any}()
for (tetto, nome) in TETTI
    say("\n2. ", uppercase(nome), tetto == Inf ? "" : @sprintf(" (possibile da K = %d)", kmin[tetto]))
    say(@sprintf("   %3s %10s %10s %10s %8s %8s %8s   %6s %8s", "K", "medio", "mediana", "peggiore", ">5%", ">10%", ">20%", "tempo", "variabili"))
    for K in max(1, kmin[tetto]):KMAX
        r = pmediana(K, tetto)
        r === nothing && (say(@sprintf("   %3d nessuna soluzione", K)); continue)
        ris[(tetto, K)] = r
        say(@sprintf("   %3d %10s %10s %10s %8d %8d %8d   %5.1fs %8d%s", K, pct(mean(r.ex)), pct(median(r.ex)), pct(maximum(r.ex)),
                     count(>(0.05), r.ex), count(>(0.10), r.ex), count(>(0.20), r.ex), r.t, r.var,
                     r.stato == MOI.OPTIMAL ? "" : @sprintf("   (limite di tempo, gap %.2g)", r.gap)))
    end
end

# ── 3. le flotte ─────────────────────────────────────────────────────────────────
function descrivi(tetto, K)
    r = ris[(tetto, K)]
    for j in r.flotta
        li = findall(==(j), r.ass)
        say(@sprintf("     m %.2f n %.2f  %-18s FC %4.0f kW  batteria %4.0f kWh  %3d linee  extra-costo medio %s, peggiore %s (%s)", m[j], n[j], regime(m[j]),
                     P_FC[j], C_BATT[j], length(li), pct(mean(r.ex[li])), pct(maximum(r.ex[li])), linee[li[argmax(r.ex[li])]]))
    end
end
say("\n3. LE FLOTTE (treni ordinati per m e n)")
for (tetto, nome) in TETTI, K in (3, 4, 5, 6, 8, 10, 15)
    haskey(ris, (tetto, K)) || continue
    tetto == 0.15 && K > kmin[0.10] && continue              # oltre il K minimo del +10% basta il +10%
    say(@sprintf("\n   %s, K = %d: extra-costo medio %s, peggiore %s", nome, K, pct(mean(ris[(tetto, K)].ex)), pct(maximum(ris[(tetto, K)].ex))))
    descrivi(tetto, K)
end

# ── 4. tabelle per i passi successivi ────────────────────────────────────────────
nome_t(t) = t == Inf ? "senza" : @sprintf("%.0f", 100t)
open(joinpath(LOG, "02_flotte.csv"), "w") do io
    println(io, "tetto_pct,K,m,n,regime,P_FC_kW,C_batt_kWh,linee,extra_medio_pct,extra_peggiore_pct")
    for ((tetto, K), r) in sort(collect(ris); by = first), j in r.flotta
        li = findall(==(j), r.ass)
        println(io, join((nome_t(tetto), K, m[j], n[j], regime(m[j]), round(P_FC[j]), round(C_BATT[j]), length(li),
                          @sprintf("%.3f", 100mean(r.ex[li])), @sprintf("%.3f", 100maximum(r.ex[li]))), ','))
    end
end
open(joinpath(LOG, "02_assegnazioni.csv"), "w") do io
    println(io, "tetto_pct,K,linea,m_treno,n_treno,regime_treno,extra_pct")
    for ((tetto, K), r) in sort(collect(ris); by = first), i in 1:NL
        j = r.ass[i]
        println(io, join((nome_t(tetto), K, linee[i], m[j], n[j], regime(m[j]), @sprintf("%.4f", 100r.ex[i])), ','))
    end
end
jldsave(joinpath(BASE, "fase14", "pmediana.jld2"); ris = Dict(string(nome_t(k[1]), "_", k[2]) => (flotta = v.flotta, ass = v.ass, ex = v.ex) for (k, v) in ris))
say(@sprintf("\nTabelle: %s, %s. Tempo totale %.1f min", joinpath(LOG, "02_flotte.csv"), joinpath(LOG, "02_assegnazioni.csv"), (time() - T0) / 60))
close(OUT)
