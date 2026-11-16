# fase12/08_non_elettrificate.jl: il surrogato sulle linee della rete non elettrificate per più del 70%, con l'altimetria lisciata
# a 200 m (fase12/07), contro il simulatore: grandezze, regime, costo finale.
#
#   julia -t 8 --project=fase12 fase12/08_non_elettrificate.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_08.txt 2>&1
#
# Linee: km_non_el / lunghezza_km > 0,7 da dati_rete/archivio/tratte_rete_20261110/riepilogo.csv (la colonna perc_non_el vale 0
# ovunque e non si usa), nella versione train-powertrain/dati_rete/tratte_rete_attenuate/media_200m.
# Riferimento: il simulatore sulle 288 coppie della campagna (già simulate in fase12/07, sim_attenuate/media_200m).
#   A. le grandezze, rete contro simulatore sulle 288 coppie (come fase12/03);
#   B. la strategia di usa_surrogato.jl (rete sulla griglia fitta 9702, margine SOC ≥ 0,21 e scarica < 0,1, verifica delle 5
#      migliori distanti 0,03, fino a 20 se nessuna è fattibile): progetto proposto, regime, costo vero, contro la migliore delle 288;
#   C. nel progetto proposto, le grandezze previste dalla rete contro quelle del simulatore.
# Regimi: sola batteria (m = 0), ibrido con fuel cell piccola (0 < m < 0,1, sotto la soglia D25), ibrido (m ≥ 0,1).

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "08_non_elettrificate.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/08_non_elettrificate.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_TR = joinpath(TPR, "dati_rete", "tratte_rete_attenuate", "media_200m")
const REG = joinpath(BASE, "fase12", "sim_attenuate", "media_200m", "registro.csv")

# ── le linee ─────────────────────────────────────────────────────────────────────
"""Divide una riga CSV alle virgole fuori dalle virgolette."""
function dividi(r)
    out = String[]; buf = IOBuffer(); dentro = false
    for ch in r
        ch == '"' ? (dentro = !dentro) : (ch == ',' && !dentro) ? push!(out, String(take!(buf))) : print(buf, ch)
    end
    push!(out, String(take!(buf)))
    return out
end
function leggi_csv(f)
    l = readlines(f); h = dividi(l[1])
    return [Dict(h[j] => x for (j, x) in enumerate(dividi(r))) for r in l[2:end] if !isempty(strip(r))]
end
rie = Dict(r["tratta"] => r for r in leggi_csv(joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110", "riepilogo.csv")))
quota_ne(r) = parse(Float64, r["km_non_el"]) / parse(Float64, r["lunghezza_km"])
nomi = sort([k for (k, r) in rie if quota_ne(r) > 0.7])
say(@sprintf("linee non elettrificate per più del 70%%: %d su %d (totalmente non elettrificate: %d)", length(nomi), length(rie),
             count(k -> rie[k]["elettrificazione"] == "Totalmente non elettrificata", nomi)))

# ── simulatore: le 288 coppie già simulate ──────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
casi = Dict{String,Dict{Tuple{Float64,Float64},NamedTuple}}()
for l in readlines(REG)[2:end]
    c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
    get!(casi, String(c["tratta"]), Dict{Tuple{Float64,Float64},NamedTuple}())[(pf(c["m"]), pf(c["n"]))] =
        (completato = c["stato"] == "completed", fattibile = c["tipo_esito"] == "fattibile",
         durata = pf(c["durata_viaggio_s"]), serbatoio = pf(c["massa_serbatoio_kg"]), H2 = pf(c["H2_cons_kg"]), SOC = pf(c["SOC_end"]),
         scarica = pf(c["scarica_s"]) > 1e-6, vita_batt = pf(c["vita_batt_cicli_viaggi"]), vita_FC_f1 = pf(c["vita_FC_f1_ore"]),
         C_rate = pf(c["C_rate_scarica_max"]), costo = pf(c["total_cost_EUR_km"]))
end
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end

# ── rete ─────────────────────────────────────────────────────────────────────────
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1); ((XA .- μ) ./ σ, μ, σ)
end
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const CFG_SIM = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
function rete(X, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    d = Dati(ingressi(repeat(X', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
             m, n, fill(X[IL], N), fill(X[IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    return p, valuta(m, n, fill(X[IL], N), q), m, n
end
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
const REGIMI = ("sola batteria", "ibrido FC piccola", "ibrido")
function sim_grandezze(e)
    g = e.diagnostica === nothing ? nothing : e.diagnostica.grandezze
    cd = e.diagnostica === nothing ? nothing : e.diagnostica.cost_details
    x(k) = g !== nothing && haskey(g, k) ? Float64(g[k]) : cd !== nothing && haskey(cd, k) ? Float64(cd[k]) : NaN
    return (durata = x("durata_viaggio_s"), serbatoio = x("massa_serbatoio_kg"), H2 = x("H2_cons_kg"), SOC = x("SOC_end"),
            scarica = x("scarica_s") > 1e-6, vita_batt = x("vita_batt_cicli_viaggi"), vita_FC_f1 = x("vita_FC_f1_ore"), C_rate = x("C_rate_scarica_max"))
end

const G = [(:durata, "durata", :rel), (:serbatoio, "serbatoio", :rel), (:H2, "idrogeno", :rel), (:SOC, "SOC finale", :abs),
           (:vita_batt, "vita batteria", :rel), (:vita_FC_f1, "vita FC (f1)", :rel), (:C_rate, "C-rate scarica", :rel), (:costo, "costo", :rel)]
err288 = Dict(g[1] => Float64[] for g in G); errP = Dict(g[1] => Float64[] for g in G)
scar_ok = 0; scar_n = 0; fatt_ok = 0; fatt_n = 0
righe = NamedTuple[]
tc_tutte = leggi_tratte_reali(nomi; cartella = DIR_TR)
for tc in tc_tutte
    global scar_ok, scar_n, fatt_ok, fatt_n
    nome = tc.id; cs = casi[nome]
    pr = profilo_tratta(tc.cp); v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    dist = sqrt(minimum(vec(sum((ZA .- ((X' .- MU) ./ SG)) .^ 2; dims = 2))))
    # A. le 288 coppie
    p, v, m, n = rete(X, C288)
    for i in 1:288
        c = cs[C288[i]]
        fatt_n += 1; fatt_ok += v.fattibile[i] == c.fattibile
        isfinite(c.C_rate) && (scar_n += 1; scar_ok += (p.p_scarica[i] >= 0.5) == c.scarica)
        for (k, _, tipo) in G
            k in (:serbatoio, :H2, :vita_FC_f1) && m[i] == 0 && continue
            k in (:H2, :SOC) && !c.completato && continue
            k === :costo && !(c.fattibile && !v.d3[i]) && continue
            y = getproperty(c, k); yh = k === :costo ? v.costo_totale[i] : getproperty(p, k)[i]
            (isfinite(y) && isfinite(yh)) && push!(err288[k], tipo === :rel ? 100abs(yh - y) / abs(y) : abs(yh - y))
        end
    end
    fv = [cs[c].fattibile for c in C288]; cv = [cs[c].costo for c in C288]
    ib = argmin(ifelse.(fv, cv, Inf)); best = cv[ib]; mb, nb = C288[ib]
    # scelta della rete fra le 288 senza verifiche (per il regime "secco")
    ord288 = sortperm([v.fattibile[i] ? v.costo_totale[i] : Inf for i in 1:288]); i1 = ord288[1]
    # B. la strategia di usa_surrogato.jl
    pg, vg, mg, ng = rete(X, GRIGLIA)
    amm = vg.fattibile .& (pg.SOC .>= 0.21) .& (pg.p_scarica .< 0.1)
    cand = Int[]
    for i in sortperm([amm[i] ? vg.costo_totale[i] : Inf for i in eachindex(GRIGLIA)])
        amm[i] || break
        all(j -> max(abs(mg[i] - mg[j]), abs(ng[i] - ng[j])) >= 0.03 - 1e-9, cand) && push!(cand, i)
        length(cand) == 20 && break
    end
    pre = PrecalcoloTratta(tc.cp, "andata&ritorno")
    ver = NamedTuple[]
    for (k, i) in enumerate(cand)
        k > 5 && any(r -> r.fattibile, ver) && break
        e = valuta_progetto(mg[i], ng[i], 195_000.0, tc.cp, "andata&ritorno"; config = CFG_SIM, precalcolo = pre)
        push!(ver, (i = i, fattibile = e.stato === :completed && e.penalita == 0, costo = e.costo_totale, g = sim_grandezze(e)))
    end
    ok = [r for r in ver if r.fattibile]
    pr_ = isempty(ok) ? nothing : ok[argmin([r.costo for r in ok])]
    if pr_ !== nothing
        i = pr_.i
        for (k, _, tipo) in G
            k in (:serbatoio, :H2, :vita_FC_f1) && mg[i] == 0 && continue
            y = k === :costo ? pr_.costo : getproperty(pr_.g, k); yh = k === :costo ? vg.costo_totale[i] : getproperty(pg, k)[i]
            (isfinite(y) && isfinite(yh)) && push!(errP[k], tipo === :rel ? 100(yh - y) / abs(y) : yh - y)
        end
    end
    push!(righe, (linea = nome, regione = rie[nome]["regione"], L_km = X[IL], non_el_pct = 100quota_ne(rie[nome]), distanza = dist,
                  vero_m = mb, vero_n = nb, vero_regime = regime(mb), vero_costo = best,
                  secca288_regime = regime(m[i1]), secca288_fattibile = fv[i1],
                  m = pr_ === nothing ? NaN : mg[pr_.i], n = pr_ === nothing ? NaN : ng[pr_.i],
                  regime = pr_ === nothing ? "nessuna" : regime(mg[pr_.i]), costo_sim = pr_ === nothing ? NaN : pr_.costo,
                  costo_rete = pr_ === nothing ? NaN : vg.costo_totale[pr_.i], verifiche = length(ver),
                  rispetto_288 = pr_ === nothing ? NaN : 100(pr_.costo / best - 1)))
end

# ── riassunto ────────────────────────────────────────────────────────────────────
N = length(righe)
say(@sprintf("\nA. Le grandezze sulle 288 coppie (%d linee × 288 = %d casi): rete contro simulatore", N, 288N))
say(@sprintf("   %-16s %9s %9s %9s %9s %9s", "grandezza", "casi", "mediana", "media", "p95", "max"))
for (k, nm, tipo) in G
    e = err288[k]; f(x) = tipo === :abs ? @sprintf("%9.4f", x) : @sprintf("%8.2f%%", x)
    say(@sprintf("   %-16s %9d ", nm, length(e)), join((f(x) for x in (median(e), mean(e), quantile(e, 0.95), maximum(e))), " "))
end
say(@sprintf("   scarica giusta %.2f%%; fattibilità giusta %.2f%%", 100scar_ok / scar_n, 100fatt_ok / fatt_n))

say("\nB. La scelta del progetto (rete sulla griglia fitta + margine + verifiche), contro la migliore delle 288 simulate")
np = count(r -> r.regime != "nessuna", righe)
rel = [r.rispetto_288 for r in righe if isfinite(r.rispetto_288)]
say(@sprintf("   progetto fattibile proposto: %d linee su %d; verifiche: mediana %d, più di 5 in %d linee", np, N,
             round(Int, median(r.verifiche for r in righe)), count(r -> r.verifiche > 5, righe)))
say(@sprintf("   costo vero rispetto alla migliore delle 288: mediana %+.2f%%, 10° %+.2f%%, 90° %+.2f%%, max %+.2f%%", median(rel),
             quantile(rel, 0.1), quantile(rel, 0.9), maximum(rel)))
say(@sprintf("   più economico della migliore delle 288 in %d linee (%.0f%%); entro +1%% in %d (%.0f%%); oltre +3%% in %d", count(<(-1e-9), rel),
             100count(<(-1e-9), rel) / N, count(<=(1), rel), 100count(<=(1), rel) / N, count(>(3), rel)))
say("   regime: migliore delle 288 (righe) contro proposta del surrogato (colonne)")
say(@sprintf("   %-22s %16s %20s %10s %10s %10s", "", REGIMI..., "nessuna", "totale"))
for a in REGIMI
    say(@sprintf("   %-22s %16d %20d %10d %10d %10d", a,(count(r -> r.vero_regime == a && r.regime == b, righe) for b in (REGIMI..., "nessuna"))...,
                 count(r -> r.vero_regime == a, righe)))
end
say(@sprintf("   stesso regime: %d linee su %d; con la scelta secca fra le 288 (senza verifiche): %d (scelta non fattibile in %d)",
             count(r -> r.vero_regime == r.regime, righe), N, count(r -> r.vero_regime == r.secca288_regime, righe), count(r -> !r.secca288_fattibile, righe)))
say("   le linee con il regime diverso:")
for r in righe
    r.vero_regime == r.regime && continue
    say(@sprintf("     %-40s migliore 288: m %.2f n %.2f %.4f €/km (%s) | surrogato: m %.2f n %.2f %.4f €/km (%s), %+.2f%%", r.linea,
                 r.vero_m, r.vero_n, r.vero_costo, r.vero_regime, r.m, r.n, r.costo_sim, r.regime, r.rispetto_288))
end

say("\nC. Nel progetto proposto: grandezze previste dalla rete contro il simulatore (con il segno: + = rete più alta)")
say(@sprintf("   %-16s %6s %10s %10s %10s %10s", "grandezza", "casi", "mediana", "|mediana|", "p95 |e|", "max |e|"))
for (k, nm, tipo) in G
    e = errP[k]; isempty(e) && continue
    f(x) = tipo === :abs ? @sprintf("%10.4f", x) : @sprintf("%9.2f%%", x)
    say(@sprintf("   %-16s %6d ", nm, length(e)), join((f(x) for x in (median(e), median(abs.(e)), quantile(abs.(e), 0.95), maximum(abs.(e)))), " "))
end

say("\nD. Per fasce di distanza dall'addestramento")
for (a, b, nm) in ((0, 2.9, "vicina (≤ 2,9)"), (2.9, 4.7, "nella norma"), (4.7, Inf, "LONTANA (> 4,7)"))
    s = [r for r in righe if a < r.distanza <= b && isfinite(r.rispetto_288)]
    isempty(s) && continue
    x = [r.rispetto_288 for r in s]
    say(@sprintf("   %-18s %3d linee: costo vs 288 mediana %+.2f%%, max %+.2f%%, entro +1%% %.0f%%, stesso regime %.0f%%", nm, length(s),
                 median(x), maximum(x), 100count(<=(1), x) / length(s), 100count(r -> r.vero_regime == r.regime, s) / length(s)))
end

open(joinpath(LOG, "08_non_elettrificate.csv"), "w") do io
    k = keys(righe[1]); println(io, join(k, ','))
    for r in righe; println(io, join((x isa AbstractFloat ? @sprintf("%.6g", x) : string(x) for x in values(r)), ',')); end
end
say(@sprintf("\nTempo %.1f min. Tabella per linea: %s", (time() - T0) / 60, joinpath(LOG, "08_non_elettrificate.csv")))
close(OUT)
