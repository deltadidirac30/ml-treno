# fase10/04_griglia_fitta.jl: passo 6d, l'ottimo cercato dalla rete neurale su una griglia fitta di (m, n), verificato
# con il simulatore; come fase9/04_griglia_fitta.jl (passo 5c, boosting), sulle stesse 256 tratte e con la stessa griglia.
#
#   julia -t 8 --project=fase10 fase10/04_griglia_fitta.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_04.txt 2>&1
#
# Due varianti di fattibilità per il surrogato: senza margini, e con il margine piccolo del passo 6c (SOC previsto ≥ 0,21,
# probabilità di scarica < 0,1). Per ognuna: scelta secca e 5 candidati distanti almeno 0,03, simulati con il percorso della
# campagna. Confronto con la migliore delle 288 coppie vere, con la scelta della rete fra le 288 e con il passo 5c.
# Linee in m (le stesse 4 tratte del 5c): costo previsto dalla rete e dal boosting contro il simulatore, e "rugosità".
# Scrive in fase10_log: 04_griglia.txt, 04_tratte.csv, fig_griglia_rimpianto.png, fig_linee.png; simulazioni in
# ~/Documents/lavoro/ml_treno_dati/fase10/sim_griglia (ricreate a ogni lancio).

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))      # valuta, taglie, ...
include(joinpath(@__DIR__, "comune.jl"))                     # rete: carica_modello, ingressi, previsioni, ...
using EvoTrees, Random, Plots
gr()
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase10_log")
const DAT = joinpath(BASE, "fase10")
const SIM = joinpath(DAT, "sim_griglia")
const DIR_TRATTE = joinpath(BASE, "tratte_doe_16384")
const OUT = open(joinpath(LOG, "04_griglia.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase10/04_griglia_fitta.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()

# ── stesse tratte e stessa griglia del passo 5c ──────────────────────────────────
const S5 = Arrow.Table(joinpath(BASE, "fase9", "surrogato_validazione.arrow"))
const TRV = sort(unique(Int.(S5.tratta)))
const SEME = 20261116
const CAMPIONE = sort(TRV[randperm(Xoshiro(SEME), length(TRV))[1:256]])
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99])
const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
const T5C = let l = readlines(joinpath(BASE, "fase9_log", "04_tratte.csv")), h = split(l[1], ',')
    col(c) = findfirst(==(c), h)
    Dict(parse(Int, x[col("tratta")]) => (g1_fatt = x[col("g1_fattibile")] == "true", g1 = parse(Float64, x[col("g1_rel_288")]),
                                          g5_fatt = x[col("g5_fattibile")] == "true", g5 = parse(Float64, x[col("g5_rel_288")])) for x in split.(l[2:end], ','))
end
sort(collect(keys(T5C))) == CAMPIONE || error("il campione non è quello del passo 5c")
say(@sprintf("campione: le stesse %d tratte del passo 5c; griglia %d × %d = %d punti", length(CAMPIONE), length(MS), length(NS), length(GRIGLIA)))

const B288 = Dict{Int,NamedTuple}()
let tr = Int.(S5.tratta), fv = collect(S5.vero_fattibile), cv = collect(S5.vero_costo_totale), m = collect(S5.m), n = collect(S5.n)
    for i in eachindex(tr)
        fv[i] || continue
        r = tr[i]; (!haskey(B288, r) || cv[i] < B288[r].costo) && (B288[r] = (costo = cv[i], m = m[i], n = n[i]))
    end
end

# ── la rete ──────────────────────────────────────────────────────────────────────
const RETE, NORM, SC, INFO = carica_modello(joinpath(DAT, "rete_6b.jld2"))
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const JX = [findfirst(==(c), Arrow.names(CT)) for c in NORM.nx]
const XC = reduce(hcat, (collect(getproperty(CT, c)) for c in Arrow.names(CT)))     # colonna 1 = route_id
const IL = findfirst(==(:x_L_km), Arrow.names(CT)); const IT = findfirst(==(:x_tempo_limiti_ar_s), Arrow.names(CT))
"""Le 8 grandezze della rete (unità naturali) e la probabilità di scarica per i punti (m, n) della tratta r."""
function rete(r, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    Xc = repeat(XC[r:r, JX], N, 1)
    d = Dati(ingressi(Xc, m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), fill(Int32(r), N), zeros(Int16, N), m, n,
             fill(XC[r, IL], N), fill(XC[r, IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    return m, n, fill(XC[r, IL], N), q, p.p_scarica
end
# controllo: sulle 288 coppie della validazione la rete qui ridà le previsioni salvate al passo 6b
let pr = Arrow.Table(joinpath(DAT, "pred_validazione_6b.arrow")), r = CAMPIONE[1]
    ii = findall(==(r), Int.(pr.tratta)); tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
    m, n, L, q, _ = rete(r, [(tv.m[i], tv.n[i]) for i in ii])
    say("controllo: la rete ricaricata ridà le previsioni del passo 6b (SOC, H2): ", q.SOC == collect(pr.SOC)[ii], ", ", q.H2 == collect(pr.H2)[ii])
end

# il boosting, solo per le linee (stesse funzioni del passo 5c)
const F7 = joinpath(BASE, "fase7"); const F8 = joinpath(BASE, "fase8")
const MB = Dict(k => EvoTrees.load(f) for (k, f) in (:durata => joinpath(F7, "durata_E.bson"), :serbatoio => joinpath(F8, "modello_massa_serbatoio.bson"),
    :H2 => joinpath(F8, "modello_H2_cons.bson"), :SOC => joinpath(F8, "modello_SOC_end.bson"), :scarica => joinpath(F8, "modello_scarica.bson"),
    :vita_batt => joinpath(F8, "modello_vita_batt.bson"), :vita_FC => joinpath(F8, "modello_vita_FC.bson"), :C_rate => joinpath(F8, "modello_C_rate.bson")))
pb(k, X) = (mdl = MB[k]; vec(EvoTrees.predict(mdl, X; ntree_limit = mdl.info[:logger][:best_iter] + 1)))
function boosting(r, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    X = hcat(repeat(XC[r:r, JX], N, 1), m, n); L = XC[r, IL]; T = XC[r, IT]; ibr = m .> 0
    q = (durata = pb(:durata, X) .* T, serbatoio = ifelse.(ibr, pb(:serbatoio, X) .* 2L, 0.0), H2 = ifelse.(ibr, pb(:H2, X) .* 2L, 0.0),
         SOC = clamp.(pb(:SOC, X), 0.0, 0.9), scarica = pb(:scarica, X) .>= 0.5, vita_batt = exp.(pb(:vita_batt, X)),
         vita_FC_f1 = ifelse.(ibr, exp.(pb(:vita_FC, X)), Inf), C_rate = exp.(pb(:C_rate, X)))
    return m, n, fill(L, N), q
end

function candidati(m, n, amm, costo; k = 5, dmin = 0.03)
    ord = sortperm([amm[i] ? costo[i] : Inf for i in eachindex(costo)])
    scelti = Int[]
    for i in ord
        amm[i] || break
        all(j -> max(abs(m[i] - m[j]), abs(n[i] - n[j])) >= dmin - 1e-9, scelti) && push!(scelti, i)
        length(scelti) == k && break
    end
    return scelti
end

# ── griglia ──────────────────────────────────────────────────────────────────────
const VARIANTI = (("senza margini", (q, p) -> trues(length(p))), ("SOC ≥ 0,21, scarica < 0,1", (q, p) -> (q.SOC .>= 0.21) .& (p .< 0.1)))
say("\n[1] la rete sulla griglia fitta")
t0 = time()
CAND = Dict{Tuple{Int,Int},Vector{NamedTuple}}()
for r in CAMPIONE
    m, n, L, q, ps = rete(r, GRIGLIA)
    v = valuta(m, n, L, q)
    for (iv, (_, f)) in enumerate(VARIANTI)
        amm = v.fattibile .& f(q, ps)
        CAND[(r, iv)] = [(m = m[i], n = n[i], costo_prev = v.costo_totale[i]) for i in candidati(m, n, amm, v.costo_totale)]
    end
end
say(@sprintf("  %d tratte × %d punti in %.1f s; tratte senza punti ammessi: %s", length(CAMPIONE), length(GRIGLIA), time() - t0,
             join(("$(VARIANTI[iv][1]) $(count(r -> isempty(CAND[(r, iv)]), CAMPIONE))" for iv in eachindex(VARIANTI)), ", ")))

# ── simulazioni ──────────────────────────────────────────────────────────────────
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
function simula(r, coppie, cartella)
    tr = leggi_tratte_materializzate(DIR_TRATTE; solo = [r])
    spec = CampagnaSpec(tratte = tr, coppie = unique(coppie), cartella = cartella, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(cartella, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $cartella")
    out = Dict{Tuple{Float64,Float64},NamedTuple}()
    for l in readlines(joinpath(cartella, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        out[(parse(Float64, c["m"]), parse(Float64, c["n"]))] = (stato = c["stato"], fattibile = c["tipo_esito"] == "fattibile",
                                                                 costo_totale = parse(Float64, c["total_cost_EUR_km"]))
    end
    return out
end
isdir(SIM) && rm(SIM; recursive = true); mkpath(SIM)
say("\n[2] simulazioni dei candidati (5 per tratta e per variante)")
t0 = time()
RIS = Dict{Int,Any}()
for r in CAMPIONE
    cc = reduce(vcat, ([(c.m, c.n) for c in CAND[(r, iv)]] for iv in eachindex(VARIANTI)))
    RIS[r] = simula(r, cc, joinpath(SIM, @sprintf("route_%06d", r)))
end
say(@sprintf("  %d simulazioni in %.1f s; config.txt uguale a quello della campagna", sum(length(v) for v in values(RIS)), time() - t0))

# ── confronto ────────────────────────────────────────────────────────────────────
# scelta della rete fra le 288 coppie (passo 6c), sulle tratte del campione
const S288 = let pr = Arrow.Table(joinpath(DAT, "pred_validazione_6b.arrow")), tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
    q = (durata = collect(pr.durata), serbatoio = collect(pr.serbatoio), H2 = collect(pr.H2), SOC = collect(pr.SOC),
         scarica = collect(pr.p_scarica) .>= 0.5, vita_batt = collect(pr.vita_batt), vita_FC_f1 = collect(pr.vita_FC_f1), C_rate = collect(pr.C_rate))
    v = valuta(collect(tv.m), collect(tv.n), collect(tv.x_L_km), q)
    fv = collect(tv.fattibile); cv = collect(tv.total_cost_EUR_km); tr = Int.(tv.tratta)
    d = Dict{Int,NamedTuple}()
    for r in CAMPIONE
        ii = [i for i in findall(==(r), tr) if v.fattibile[i]]; ord = ii[sortperm(v.costo_totale[ii])]
        c5 = [i for i in ord[1:min(5, end)] if fv[i]]
        d[r] = (s1 = fv[ord[1]] ? cv[ord[1]] / B288[r].costo - 1 : NaN, s5 = isempty(c5) ? NaN : minimum(cv[c5]) / B288[r].costo - 1)
    end
    d
end
righe = NamedTuple[]
for r in CAMPIONE
    b = B288[r]; s = RIS[r]
    x = Dict{Symbol,Any}(:tratta => r, :costo_288 => b.costo, :m_288 => b.m, :n_288 => b.n)
    for (iv, _) in enumerate(VARIANTI)
        c = CAND[(r, iv)]
        if isempty(c)
            x[Symbol("g1_$iv")] = NaN; x[Symbol("g5_$iv")] = NaN; x[Symbol("m1_$iv")] = NaN; continue
        end
        v1 = s[(c[1].m, c[1].n)]
        x[Symbol("g1_$iv")] = v1.fattibile ? v1.costo_totale / b.costo - 1 : NaN
        x[Symbol("m1_$iv")] = c[1].m
        x[Symbol("p1_$iv")] = c[1].costo_prev / v1.costo_totale - 1
        f5 = [s[(y.m, y.n)].costo_totale for y in c if s[(y.m, y.n)].fattibile]
        x[Symbol("g5_$iv")] = isempty(f5) ? NaN : minimum(f5) / b.costo - 1
    end
    x[:rete288_s1] = S288[r].s1; x[:rete288_s5] = S288[r].s5
    x[:boost_g1] = T5C[r].g1_fatt ? T5C[r].g1 : NaN; x[:boost_g5] = T5C[r].g5_fatt ? T5C[r].g5 : NaN
    push!(righe, (; x...))
end
cols = [:tratta, :costo_288, :m_288, :n_288, :g1_1, :g5_1, :g1_2, :g5_2, :rete288_s1, :rete288_s5, :boost_g1, :boost_g5]
open(joinpath(LOG, "04_tratte.csv"), "w") do io
    println(io, join(cols, ','))
    for x in righe; println(io, join((let v = getproperty(x, c); v isa Float64 ? @sprintf("%.6g", v) : string(v) end for c in cols), ',')); end
end
NT = length(righe)
function sintesi(nome, rel)
    rr = filter(isfinite, rel)
    say(@sprintf("  %-50s non fattibile %5.1f%% | rispetto alla migliore delle 288: mediana %+.3f%%, p10 %+.2f%%, p90 %+.2f%%, p95 %+.2f%%; più economica %5.1f%%, entro +1%% %5.1f%%",
                 nome, 100count(!isfinite, rel) / NT, 100median(rr), 100quantile(rr, 0.1), 100quantile(rr, 0.9), 100quantile(rr, 0.95),
                 100count(<(-1e-9), rr) / NT, 100count(<=(0.01), rr) / NT))
end
say("\n[3] confronto sulle ", NT, " tratte (costo vero della scelta / migliore delle 288 − 1; negativo = più economica)")
sintesi("boosting, griglia, scelta secca (5c)", [x.boost_g1 for x in righe])
sintesi("boosting, griglia, verifica delle prime 5 (5c)", [x.boost_g5 for x in righe])
sintesi("rete, 288 coppie, scelta secca (6c)", [x.rete288_s1 for x in righe])
sintesi("rete, 288 coppie, verifica delle prime 5 (6c)", [x.rete288_s5 for x in righe])
for (iv, (nome, _)) in enumerate(VARIANTI)
    sintesi("rete, griglia, scelta secca, $nome", [getproperty(x, Symbol("g1_$iv")) for x in righe])
    sintesi("rete, griglia, verifica delle prime 5, $nome", [getproperty(x, Symbol("g5_$iv")) for x in righe])
end
for (iv, (nome, _)) in enumerate(VARIANTI)
    e = filter(isfinite, [getproperty(x, Symbol("p1_$iv")) for x in righe if haskey(x, Symbol("p1_$iv")) && isfinite(getproperty(x, Symbol("g1_$iv")))])
    say(@sprintf("  rete, griglia, %s: costo previsto / vero della scelta secca fattibile − 1: mediana %+.2f%%, p5 %+.2f%%, p95 %+.2f%%",
                 nome, 100median(e), 100quantile(e, 0.05), 100quantile(e, 0.95)))
end

# ── linee in m ───────────────────────────────────────────────────────────────────
say("\n[4] linee in m a n fissa (le 4 tratte del passo 5c): rete, boosting, simulatore")
LINEE = let ib = [r for r in CAMPIONE if B288[r].m > 0]; ib[round.(Int, range(1, length(ib); length = 4))] end
rug(c) = median(abs.(c[2:end-1] .- (c[1:end-2] .+ c[3:end]) ./ 2) ./ c[2:end-1])       # scarto dalla media dei vicini
plt = plot(layout = (2, 2), size = (1300, 900), dpi = 120)
for (k, r) in enumerate(LINEE)
    n0 = round(B288[r].n; digits = 2); punti = [(m, n0) for m in MS if m > 0]
    m, n, L, q, _ = rete(r, punti); vr = valuta(m, n, L, q)
    mb, nb, Lb, qb = boosting(r, punti); vb = valuta(mb, nb, Lb, qb)
    s = simula(r, punti, joinpath(SIM, @sprintf("linea_%06d", r)))
    cv = [s[p].costo_totale for p in punti]; fv = [s[p].fattibile for p in punti]
    plot!(plt[k], m, cv; lw = 2.5, color = :black, label = "simulatore", xlabel = "m", ylabel = "costo [€/km]",
          title = @sprintf("tratta %d, n = %.2f (L %.0f km)", r, n0, L[1]))
    plot!(plt[k], m, vb.costo_totale; lw = 1, color = :gray60, label = "boosting")
    plot!(plt[k], m, vr.costo_totale; lw = 1.5, color = :steelblue, label = "rete neurale")
    scatter!(plt[k], m[.!fv], cv[.!fv]; ms = 2.5, msw = 0, color = :red, label = "non fattibile (simulatore)")
    say(@sprintf("  tratta %5d, n %.2f: rugosità (|c − media dei vicini| / c, mediana) simulatore %.4f%%, rete %.4f%%, boosting %.4f%%; errore mediano del costo rete %.2f%%, boosting %.2f%%; fattibilità giusta rete %d, boosting %d su %d",
                 r, n0, 100rug(cv), 100rug(vr.costo_totale), 100rug(vb.costo_totale), 100median(abs.(vr.costo_totale ./ cv .- 1)),
                 100median(abs.(vb.costo_totale ./ cv .- 1)), count(vr.fattibile .== fv), count(vb.fattibile .== fv), length(fv)))
end
savefig(plt, joinpath(LOG, "fig_linee.png"))

plt = plot(size = (950, 520), dpi = 130, xlabel = "costo della scelta rispetto alla migliore delle 288 [%]", ylabel = "quota delle tratte",
           legend = :bottomright, xlims = (-10, 15), title = "griglia fitta, 256 tratte (curve sotto 1: scelte non fattibili)")
for (nome, v, col, st) in (("boosting, verifica delle prime 5 (5c)", [x.boost_g5 for x in righe], :gray50, :dash),
                           ("rete, 288 coppie, verifica delle prime 5", [x.rete288_s5 for x in righe], :darkorange, :dash),
                           ("rete, griglia, scelta secca", [x.g1_1 for x in righe], :steelblue, :solid),
                           ("rete, griglia, verifica delle prime 5", [x.g5_1 for x in righe], :steelblue, :dash),
                           ("rete, griglia, margine, verifica delle prime 5", [x.g5_2 for x in righe], :green4, :dash))
    rr = sort(100 .* filter(isfinite, v))
    plot!(plt, rr, (1:length(rr)) ./ NT; lw = 2, color = col, ls = st, label = nome, seriestype = :steppost)
end
vline!(plt, [0]; color = :black, lw = 1, label = "")
savefig(plt, joinpath(LOG, "fig_griglia_rimpianto.png"))
say("\nfigure: fig_griglia_rimpianto.png, fig_linee.png")
say(@sprintf("tempo totale: %.1f s", time() - T0))
close(OUT)
