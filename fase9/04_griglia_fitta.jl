# fase9/04_griglia_fitta.jl: passo 5c, l'ottimo cercato dal surrogato su una griglia fitta di (m, n), verificato con il
# simulatore.
#
#   julia -t 8 --project=fase9 fase9/04_griglia_fitta.jl > ~/Documents/lavoro/ml_treno_dati/fase9_log/log_04.txt 2>&1
#
# Su 256 tratte di validazione (a caso, seme fisso): il surrogato (boosting, fasi 7-8) valuta la griglia
# m ∈ {0} ∪ {0,03; 0,04; …; 0,99}, n ∈ {0,01; …; 0,99} (98 × 99 = 9702 punti per tratta) con il banco di prova del passo 5a,
# senza margini. Candidati: la migliore secondo il surrogato e le 5 migliori distanti fra loro almeno 0,03 (in m o in n).
# Il simulatore (TrainPowertrain invariato, stesso percorso e configurazione della campagna: leggi_tratte_materializzate,
# CampagnaSpec in modalità griglia, andata e ritorno, esegui_campagna) valuta i 5 candidati. Confronto con la migliore
# delle 288 coppie vere e con le scelte del passo 5b (02_tratte.csv).
# Gradini: su 4 tratte, una linea in m (0,03…0,99 a passo 0,01) a n fissa, prevista e simulata.
# Scrive in fase9_log: 04_griglia.txt, 04_tratte.csv, fig_griglia_rimpianto.png, fig_linee.png; le cartelle di campagna in
# ~/Documents/lavoro/ml_treno_dati/fase9/sim_griglia (ricreate a ogni lancio).

include(joinpath(@__DIR__, "comune.jl"))
using EvoTrees, Random, Plots
gr()
const LOG = joinpath(BASE, "fase9_log")
const DAT = joinpath(BASE, "fase9")
const SIM = joinpath(DAT, "sim_griglia")
const DIR_TRATTE = joinpath(BASE, "tratte_doe_16384")
const OUT = open(joinpath(LOG, "04_griglia.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase9/04_griglia_fitta.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()

# ── tratte e griglia ─────────────────────────────────────────────────────────────
const S5 = Arrow.Table(joinpath(DAT, "surrogato_validazione.arrow"))
const TRV = sort(unique(Int.(S5.tratta)))
const SEME = 20261116
const CAMPIONE = sort(TRV[randperm(Xoshiro(SEME), length(TRV))[1:256]])
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99])
const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
say(@sprintf("campione: %d tratte di validazione (seme %d); griglia %d × %d = %d punti per tratta", length(CAMPIONE), SEME,
             length(MS), length(NS), length(GRIGLIA)))

# migliore delle 288 vere e scelte del passo 5b
const B288 = Dict{Int,NamedTuple}()
let tr = Int.(S5.tratta), fv = collect(S5.vero_fattibile), cv = collect(S5.vero_costo_totale), m = collect(S5.m), n = collect(S5.n)
    for i in eachindex(tr)
        fv[i] || continue
        r = tr[i]
        (!haskey(B288, r) || cv[i] < B288[r].costo) && (B288[r] = (costo = cv[i], m = m[i], n = n[i]))
    end
end
const T5B = let l = readlines(joinpath(LOG, "02_tratte.csv")), h = split(l[1], ',')
    col(c) = findfirst(==(c), h)
    Dict(parse(Int, x[col("tratta")]) => (fatt = x[col("surrogato_fattibile")] == "true", rimp = parse(Float64, x[col("rimpianto")]),
                                          top5 = parse(Float64, x[col("top5")])) for x in split.(l[2:end], ','))
end

# ── previsioni del surrogato sulla griglia ───────────────────────────────────────
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const NX = [c for c in Arrow.names(CT) if c != :route_id]
let tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
    [c for c in Arrow.names(tv) if startswith(String(c), "x_")] == NX || error("ordine delle caratteristiche diverso dall'addestramento")
end
const XC = reduce(hcat, (collect(getproperty(CT, c)) for c in NX))
const F7 = joinpath(BASE, "fase7"); const F8 = joinpath(BASE, "fase8")
const MODELLI = Dict(k => EvoTrees.load(f) for (k, f) in (:durata => joinpath(F7, "durata_E.bson"),
    :serbatoio => joinpath(F8, "modello_massa_serbatoio.bson"), :H2 => joinpath(F8, "modello_H2_cons.bson"),
    :SOC => joinpath(F8, "modello_SOC_end.bson"), :scarica => joinpath(F8, "modello_scarica.bson"),
    :vita_batt => joinpath(F8, "modello_vita_batt.bson"), :vita_FC => joinpath(F8, "modello_vita_FC.bson"),
    :C_rate => joinpath(F8, "modello_C_rate.bson")))
prevedi(k, X) = (mdl = MODELLI[k]; vec(EvoTrees.predict(mdl, X; ntree_limit = mdl.info[:logger][:best_iter] + 1)))

"""Le 8 grandezze del surrogato (come il passo 5a) per i punti (m, n) della tratta r."""
function surrogato(r, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    X = hcat(repeat(XC[r:r, :], N, 1), m, n)
    L = XC[r, findfirst(==(:x_L_km), NX)]; T = XC[r, findfirst(==(:x_tempo_limiti_ar_s), NX)]
    ibr = m .> 0
    q = (durata = prevedi(:durata, X) .* T,
         serbatoio = ifelse.(ibr, prevedi(:serbatoio, X) .* 2L, 0.0), H2 = ifelse.(ibr, prevedi(:H2, X) .* 2L, 0.0),
         SOC = clamp.(prevedi(:SOC, X), 0.0, 0.9), scarica = prevedi(:scarica, X) .>= 0.5,
         vita_batt = exp.(prevedi(:vita_batt, X)), vita_FC_f1 = ifelse.(ibr, exp.(prevedi(:vita_FC, X)), Inf),
         C_rate = exp.(prevedi(:C_rate, X)))
    return m, n, fill(L, N), q
end

"""Le k migliori fra i punti fattibili per il surrogato, distanti fra loro almeno `dmin` (in m o in n)."""
function candidati(m, n, fatt, costo; k = 5, dmin = 0.03)
    ord = sortperm([fatt[i] ? costo[i] : Inf for i in eachindex(costo)])
    scelti = Int[]
    for i in ord
        fatt[i] || break
        all(j -> max(abs(m[i] - m[j]), abs(n[i] - n[j])) >= dmin - 1e-9, scelti) && push!(scelti, i)
        length(scelti) == k && break
    end
    return scelti
end

say("\n[1] il surrogato sulla griglia fitta")
t0 = time()
CAND = Dict{Int,Vector{NamedTuple}}()
for r in CAMPIONE
    m, n, L, q = surrogato(r, GRIGLIA)
    v = valuta(m, n, L, q)
    idx = candidati(m, n, v.fattibile, v.costo_totale)
    CAND[r] = [(m = m[i], n = n[i], costo_prev = v.costo_totale[i], soc_prev = q.SOC[i]) for i in idx]
end
say(@sprintf("  %d tratte × %d punti in %.1f s; tratte senza punti fattibili per il surrogato: %d", length(CAMPIONE), length(GRIGLIA),
             time() - t0, count(r -> isempty(CAND[r]), CAMPIONE)))

# ── simulazioni ──────────────────────────────────────────────────────────────────
# configurazione: come esegui_campagna.jl con gli argomenti della campagna (fase5/01_tratte.jl)
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
"""Simula le coppie (m, n) sulla tratta r con il percorso della campagna; restituisce (m, n) => (stato, fattibile, costo_totale, costo)."""
function simula(r, coppie, cartella)
    tr = leggi_tratte_materializzate(DIR_TRATTE; solo = [r])
    spec = CampagnaSpec(tratte = tr, coppie = coppie, cartella = cartella, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(cartella, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $cartella")
    out = Dict{Tuple{Float64,Float64},NamedTuple}()
    for l in readlines(joinpath(cartella, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        ct = parse(Float64, c["total_cost_EUR_km"]); co = parse(Float64, c["costo"])
        out[(parse(Float64, c["m"]), parse(Float64, c["n"]))] = (stato = c["stato"], fattibile = c["tipo_esito"] == "fattibile",
                                                                 costo_totale = ct, costo = co)
    end
    return out
end
isdir(SIM) && rm(SIM; recursive = true); mkpath(SIM)
say("\n[2] simulazioni dei candidati (5 per tratta)")
t0 = time()
RIS = Dict{Int,Any}()
for r in CAMPIONE
    isempty(CAND[r]) && continue
    RIS[r] = simula(r, [(c.m, c.n) for c in CAND[r]], joinpath(SIM, @sprintf("route_%06d", r)))
end
nsim = sum(length(v) for v in values(RIS))
say(@sprintf("  %d simulazioni in %.1f s; config.txt uguale a quello della campagna in tutte le cartelle", nsim, time() - t0))

# ── confronto ────────────────────────────────────────────────────────────────────
righe = NamedTuple[]
for r in CAMPIONE
    b = B288[r]; c = CAND[r]
    if isempty(c)   # nessun punto fattibile per il surrogato: nessuna proposta (conta come scelta non fattibile)
        push!(righe, (tratta = r, costo_288 = b.costo, m_288 = b.m, n_288 = b.n, m_g1 = NaN, n_g1 = NaN, g1_fattibile = false,
                      g1_stato = "nessuna", g1_costo_prev = NaN, g1_costo_vero = NaN, g1_rel_288 = NaN, g5_fattibile = false,
                      m_g5 = NaN, n_g5 = NaN, g5_rel_288 = NaN, b1_fattibile = T5B[r].fatt, b1_rel_288 = T5B[r].rimp, b5_rel_288 = T5B[r].top5))
        continue
    end
    s = RIS[r]
    v1 = s[(c[1].m, c[1].n)]
    fatt5 = [x for x in c if s[(x.m, x.n)].fattibile]
    best5 = isempty(fatt5) ? nothing : fatt5[argmin([s[(x.m, x.n)].costo_totale for x in fatt5])]
    push!(righe, (tratta = r, costo_288 = b.costo, m_288 = b.m, n_288 = b.n,
                  m_g1 = c[1].m, n_g1 = c[1].n, g1_fattibile = v1.fattibile, g1_stato = v1.stato,
                  g1_costo_prev = c[1].costo_prev, g1_costo_vero = v1.costo_totale,
                  g1_rel_288 = v1.fattibile ? v1.costo_totale / b.costo - 1 : NaN,
                  g5_fattibile = best5 !== nothing, m_g5 = best5 === nothing ? NaN : best5.m, n_g5 = best5 === nothing ? NaN : best5.n,
                  g5_rel_288 = best5 === nothing ? NaN : s[(best5.m, best5.n)].costo_totale / b.costo - 1,
                  b1_fattibile = T5B[r].fatt, b1_rel_288 = T5B[r].rimp, b5_rel_288 = T5B[r].top5))
end
open(joinpath(LOG, "04_tratte.csv"), "w") do io
    println(io, join(keys(righe[1]), ','))
    for x in righe; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : string(v) for v in values(x)), ',')); end
end
NT = length(righe)
function sintesi(nome, fatt, rel)
    rr = filter(isfinite, rel)
    say(@sprintf("  %-44s non fattibile %3d (%5.1f%%) | rispetto alla migliore delle 288: mediana %+.3f%%, p10 %+.3f%%, p90 %+.3f%%, p95 %+.3f%%; più economica in %d tratte (%.1f%%), entro +1%% in %.1f%%",
                 nome, count(!, fatt), 100count(!, fatt) / NT, 100median(rr), 100quantile(rr, 0.1), 100quantile(rr, 0.9),
                 100quantile(rr, 0.95), count(<(-1e-9), rr), 100count(<(-1e-9), rr) / NT, 100count(<=(0.01), rr) / NT))
end
say("\n[3] confronto sulle ", NT, " tratte del campione (costo vero della scelta / costo della migliore delle 288 − 1)")
sintesi("288 coppie, scelta secca (passo 5b)", [x.b1_fattibile for x in righe], [x.b1_rel_288 for x in righe])
sintesi("288 coppie, verifica delle prime 5 (passo 5b)", [isfinite(x.b5_rel_288) for x in righe], [x.b5_rel_288 for x in righe])
sintesi("griglia fitta, scelta secca", [x.g1_fattibile for x in righe], [x.g1_rel_288 for x in righe])
sintesi("griglia fitta, verifica delle prime 5", [x.g5_fattibile for x in righe], [x.g5_rel_288 for x in righe])
let s = [x for x in righe if x.g1_fattibile]
    e = [x.g1_costo_prev / x.g1_costo_vero - 1 for x in s]
    say(@sprintf("  griglia, scelta secca fattibile: costo previsto / vero − 1: mediana %+.2f%%, p5 %+.2f%%, p95 %+.2f%%", 100median(e),
                 100quantile(e, 0.05), 100quantile(e, 0.95)))
end
let s = [x for x in righe if !x.g1_fattibile]
    say("  griglia, scelte secche non fattibili per stato: ", Dict(st => count(x -> x.g1_stato == st, s) for st in unique(x.g1_stato for x in s)))
end
say(@sprintf("  regime della scelta secca sulla griglia uguale a quello della migliore delle 288: %.1f%%",
             100count(x -> (x.m_g1 == 0) == (x.m_288 == 0), righe) / NT))

# ── gradini: linee in m ──────────────────────────────────────────────────────────
say("\n[4] gradini: linee in m a n fissa, previste e simulate")
LINEE = let ib = [r for r in CAMPIONE if B288[r].m > 0]
    ib[round.(Int, range(1, length(ib); length = 4))]
end
plt = plot(layout = (2, 2), size = (1300, 900), dpi = 120)
for (k, r) in enumerate(LINEE)
    n0 = round(B288[r].n; digits = 2)
    punti = [(m, n0) for m in MS if m > 0]
    m, n, L, q = surrogato(r, punti)
    v = valuta(m, n, L, q)
    s = simula(r, punti, joinpath(SIM, @sprintf("linea_%06d", r)))
    cv = [s[p].costo_totale for p in punti]; fv = [s[p].fattibile for p in punti]
    plot!(plt[k], m, v.costo_totale; lw = 1, marker = :circle, ms = 2, msw = 0, color = :steelblue, label = "surrogato (boosting)",
          xlabel = "m", ylabel = "costo [€/km]", title = @sprintf("tratta %d, n = %.2f (L %.0f km)", r, n0, L[1]))
    plot!(plt[k], m, cv; lw = 2, color = :black, label = "simulatore")
    scatter!(plt[k], m[.!fv], cv[.!fv]; ms = 3, msw = 0, color = :red, label = "non fattibile (simulatore)")
    scatter!(plt[k], m[.!v.fattibile], v.costo_totale[.!v.fattibile]; ms = 2, msw = 0, color = :orange, marker = :x, label = "non fattibile (surrogato)")
    d = abs.(diff(v.costo_totale)) ./ v.costo_totale[1:end-1]; ds = abs.(diff(cv)) ./ cv[1:end-1]
    say(@sprintf("  tratta %5d, n %.2f: passi di m con costo previsto invariato %d su %d; salto previsto massimo fra punti vicini %.2f%% (simulato %.2f%%); fattibilità uguale %d su %d",
                 r, n0, count(==(0), diff(v.costo_totale)), length(d), 100maximum(d), 100maximum(ds), count(v.fattibile .== fv), length(fv)))
end
savefig(plt, joinpath(LOG, "fig_linee.png"))

# ── figura del rimpianto ─────────────────────────────────────────────────────────
plt = plot(size = (900, 500), dpi = 130, xlabel = "costo della scelta rispetto alla migliore delle 288 [%]",
           ylabel = "quota delle tratte", legend = :bottomright, xlims = (-10, 25),
           title = "griglia fitta contro 288 coppie, 256 tratte (curve sotto 1: scelte non fattibili)")
for (nome, v, col, st) in (("288, scelta secca", [x.b1_rel_288 for x in righe], :gray50, :solid),
                           ("288, verifica delle prime 5", [x.b5_rel_288 for x in righe], :gray50, :dash),
                           ("griglia, scelta secca", [x.g1_rel_288 for x in righe], :steelblue, :solid),
                           ("griglia, verifica delle prime 5", [x.g5_rel_288 for x in righe], :steelblue, :dash))
    rr = sort(100 .* filter(isfinite, v))
    plot!(plt, rr, (1:length(rr)) ./ NT; lw = 2, color = col, ls = st, label = nome, seriestype = :steppost)
end
vline!(plt, [0]; color = :black, lw = 1, label = "")
savefig(plt, joinpath(LOG, "fig_griglia_rimpianto.png"))
say("\nfigure: fig_griglia_rimpianto.png, fig_linee.png")
say(@sprintf("tempo totale: %.1f s", time() - T0))
close(OUT)
