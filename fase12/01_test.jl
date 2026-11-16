# fase12/01_test.jl: passo 8a, l'esame finale sul test (gruppi 15 e 16), una volta sola, con il piano di
# REPORT_FASE12_ESAME.md (fissato prima, commit 50e5132).
#
#   julia -t 8 --project=fase12 fase12/01_test.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_01.txt 2>&1
#
# Rete 6b (nessun riaddestramento) e, per confronto, boosting delle fasi 7–8. Errori per grandezza; fattibilità e costo;
# scelta fra le 288 coppie (senza la 14664); griglia fitta con verifica al simulatore su 256 tratte (seme 20261117, senza la
# 14664), senza margini e con il margine piccolo. Accanto, gli stessi numeri sulla validazione (fasi 10).
# Scrive in fase12_log: 01_test.txt, 01_griglia_tratte.csv; simulazioni in ml_treno_dati/fase12/sim_griglia.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
using EvoTrees, Random
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase12"); mkpath(DAT)
const SIM = joinpath(DAT, "sim_griglia")
const DIR_TRATTE = joinpath(BASE, "tratte_doe_16384")
const F10 = joinpath(@__DIR__, "..", "fase10", "risultati")
const OUT = open(joinpath(LOG, "01_test.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/01_test.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()

const tt = Arrow.Table(joinpath(TAB, "test.arrow"))
const GT = sort(unique(Int.(tt.gruppo)))
say("test: gruppi ", GT, ", ", length(unique(tt.tratta)), " tratte, ", length(tt.tratta), " casi")
GT == [15, 16] || error("non è il test")

# ── previsioni: rete e boosting ──────────────────────────────────────────────────
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const DT = prepara(tt, NORM)
const PR = previsioni(RETE, DT, SC)
const X = reduce(hcat, (Vector{Float64}(getproperty(tt, c)) for c in vcat([c for c in Arrow.names(tt) if startswith(String(c), "x_")], [:m, :n])))
const IBR = collect(tt.m) .> 0
function pb(file)
    mdl = EvoTrees.load(file); vec(EvoTrees.predict(mdl, X; ntree_limit = mdl.info[:logger][:best_iter] + 1))
end
F7 = joinpath(BASE, "fase7"); F8 = joinpath(BASE, "fase8"); Lt = collect(tt.x_L_km); Tt = collect(tt.x_tempo_limiti_ar_s)
const PB = (durata = pb(joinpath(F7, "durata_E.bson")) .* Tt, serbatoio = ifelse.(IBR, pb(joinpath(F8, "modello_massa_serbatoio.bson")) .* 2 .* Lt, 0.0),
            H2 = ifelse.(IBR, pb(joinpath(F8, "modello_H2_cons.bson")) .* 2 .* Lt, 0.0), SOC = clamp.(pb(joinpath(F8, "modello_SOC_end.bson")), 0.0, 0.9),
            p_scarica = pb(joinpath(F8, "modello_scarica.bson")), vita_batt = exp.(pb(joinpath(F8, "modello_vita_batt.bson"))),
            vita_FC_f1 = ifelse.(IBR, exp.(pb(joinpath(F8, "modello_vita_FC.bson"))), Inf), C_rate = exp.(pb(joinpath(F8, "modello_C_rate.bson"))))

# ── 1. errori per grandezza ──────────────────────────────────────────────────────
say("\n[1] errori per grandezza sul test (mediana / p95), accanto alla validazione")
val = Dict(x[1] => (parse(Float64, x[3]), parse(Float64, x[4])) for x in split.(readlines(joinpath(F10, "02_metriche.csv"))[2:end], ','))
mb = Dict(x.grandezza => x for x in metriche(tt, PB, DT))
for x in metriche(tt, PR, DT)
    v = val[x.grandezza]; b = mb[x.grandezza]
    if x.tipo == "accuratezza"
        say(@sprintf("  %-11s rete: test %.2f%% (validazione %.2f%%) | boosting: test %.2f%%", x.grandezza, x.mediana, v[1], b.mediana))
    else
        say(@sprintf("  %-11s rete: test %.3f / %.3f (validazione %.3f / %.3f) | boosting: test %.3f / %.3f", x.grandezza, x.mediana, x.p95, v..., b.mediana, b.p95))
    end
end

# ── 2. fattibilità e costo ───────────────────────────────────────────────────────
const M = collect(tt.m); const Nn = collect(tt.n); const TR = Int.(tt.tratta)
const FATT = collect(tt.fattibile); const TOT = collect(tt.total_cost_EUR_km)
let rv = valuta(M, Nn, Lt, grandezze_vere(tt); d3 = collect(tt.d3))
    say("\n[2] collaudo sul test: le grandezze vere ridanno la fattibilità del simulatore: ", count(rv.fattibile .== FATT), " / ", length(FATT))
end
qq(p) = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
const RR = valuta(M, Nn, Lt, qq(PR)); const RB = valuta(M, Nn, Lt, qq(PB))
say("    fattibilità e costo (casi davvero fattibili): giusta %, costo mediana / p95 (validazione della rete: 98,86%, 1,26% / 5,21%)")
for (nome, r) in (("rete", RR), ("boosting", RB))
    s = FATT .& .!r.d3; e = 100 .* abs.(r.costo_totale[s] .- TOT[s]) ./ TOT[s]
    say(@sprintf("    %-9s fattibilità giusta %.3f%%; costo %.3f%% / %.3f%%", nome, 100mean(r.fattibile .== FATT), median(e), quantile(e, 0.95)))
end

# ── 3. scelta fra le 288 coppie ──────────────────────────────────────────────────
const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const TRATTE = [r for r in sort(collect(keys(RIGHE))) if r != 14664]
const BEST = Dict(r => minimum(TOT[i] for i in RIGHE[r] if FATT[i]) for r in TRATTE)
function scelta(amm, costo, k)
    out = fill(NaN, length(TRATTE))
    for (t, r) in enumerate(TRATTE)
        ii = [i for i in RIGHE[r] if amm[i]]; isempty(ii) && continue
        ord = ii[sortperm(costo[ii])]
        c = [i for i in ord[1:min(k, end)] if FATT[i]]
        isempty(c) || (out[t] = minimum(TOT[c]) / BEST[r] - 1)
    end
    return out
end
sint(v) = (rr = filter(isfinite, v); (nf = 100count(!isfinite, v) / length(v), med = 100median(rr), p95 = 100quantile(rr, 0.95), e1 = 100count(<=(0.01), rr) / length(v)))
sv = Dict((x[1], parse(Int, x[2])) => (parse(Float64, x[3]), parse(Float64, x[4]), parse(Float64, x[5]), parse(Float64, x[6]))
          for x in split.(readlines(joinpath(F10, "03_scelta.csv"))[2:end], ','))
say("\n[3] scelta fra le 288 coppie, ", length(TRATTE), " tratte del test (senza la 14664); validazione fra parentesi")
for (nome, r) in (("rete", RR), ("boosting", RB)), k in (1, 3, 5)
    x = sint(scelta(r.fattibile, r.costo_totale, k)); v = sv[(nome, k)]
    say(@sprintf("  %-9s %-24s non fattibili %5.2f%% (%5.2f%%) | rimpianto mediana %.3f%% (%.3f%%), p95 %5.2f%% (%5.2f%%) | entro 1%% %5.1f%% (%5.1f%%)%s",
                 nome, k == 1 ? "scelta secca" : "verifica delle prime $k", x.nf, v[1], x.med, v[2], x.p95, v[3], x.e1, v[4],
                 nome == "rete" && k == 5 ? "   ← strategia di riferimento fra le 288" : ""))
end

# ── 4. griglia fitta con verifica al simulatore ──────────────────────────────────
const CAMPIONE = sort(TRATTE[randperm(Xoshiro(20261117), length(TRATTE))[1:256]])
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]); const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const JX = [findfirst(==(c), Arrow.names(CT)) for c in NORM.nx]
const XC = reduce(hcat, (collect(getproperty(CT, c)) for c in Arrow.names(CT)))
const IL = findfirst(==(:x_L_km), Arrow.names(CT)); const IT = findfirst(==(:x_tempo_limiti_ar_s), Arrow.names(CT))
function rete_griglia(r)
    m = [p[1] for p in GRIGLIA]; n = [p[2] for p in GRIGLIA]; N = length(GRIGLIA)
    d = Dati(ingressi(repeat(XC[r:r, JX], N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), fill(Int32(r), N), zeros(Int16, N),
             m, n, fill(XC[r, IL], N), fill(XC[r, IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    return m, n, valuta(m, n, fill(XC[r, IL], N), qq(p)), p
end
function candidati(m, n, amm, costo; k = 5, dmin = 0.03)
    ord = sortperm([amm[i] ? costo[i] : Inf for i in eachindex(costo)]); scelti = Int[]
    for i in ord
        amm[i] || break
        all(j -> max(abs(m[i] - m[j]), abs(n[i] - n[j])) >= dmin - 1e-9, scelti) && push!(scelti, i)
        length(scelti) == k && break
    end
    return scelti
end
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
function simula(r, coppie, cartella)
    tr = leggi_tratte_materializzate(DIR_TRATTE; solo = [r])
    spec = CampagnaSpec(tratte = tr, coppie = unique(coppie), cartella = cartella, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(cartella, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna")
    out = Dict{Tuple{Float64,Float64},NamedTuple}()
    for l in readlines(joinpath(cartella, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        out[(parse(Float64, c["m"]), parse(Float64, c["n"]))] = (fattibile = c["tipo_esito"] == "fattibile", costo_totale = parse(Float64, c["total_cost_EUR_km"]))
    end
    return out
end
say("\n[4] griglia fitta (", length(GRIGLIA), " punti) con verifica al simulatore, ", length(CAMPIONE), " tratte del test (seme 20261117)")
isdir(SIM) && rm(SIM; recursive = true); mkpath(SIM)
t0 = time()
righe = NamedTuple[]
for r in CAMPIONE
    m, n, v, p = rete_griglia(r)
    c1 = candidati(m, n, v.fattibile, v.costo_totale)
    c2 = candidati(m, n, v.fattibile .& (p.SOC .>= 0.21) .& (p.p_scarica .< 0.1), v.costo_totale)
    s = simula(r, vcat([(m[i], n[i]) for i in c1], [(m[i], n[i]) for i in c2]), joinpath(SIM, @sprintf("route_%06d", r)))
    b = BEST[r]
    rel(i) = s[(m[i], n[i])].fattibile ? s[(m[i], n[i])].costo_totale / b - 1 : NaN
    best5(cc) = (f = filter(isfinite, [rel(i) for i in cc]); isempty(f) ? NaN : minimum(f))
    push!(righe, (tratta = r, g1_1 = isempty(c1) ? NaN : rel(c1[1]), g5_1 = best5(c1), g1_2 = isempty(c2) ? NaN : rel(c2[1]), g5_2 = best5(c2)))
end
say(@sprintf("  %.1f s (previsioni e %d simulazioni)", time() - t0, sum(length(readlines(joinpath(SIM, @sprintf("route_%06d", r), "registro.csv"))) - 1 for r in CAMPIONE)))
open(joinpath(LOG, "01_griglia_tratte.csv"), "w") do io
    println(io, join(keys(righe[1]), ','))
    for x in righe; println(io, join((v isa Float64 ? @sprintf("%.6g", v) : v for v in values(x)), ',')); end
end
vg = let l = readlines(joinpath(F10, "04_tratte.csv")), h = split(l[1], ',')
    Dict(c => [parse(Float64, x[findfirst(==(c), h)]) for x in split.(l[2:end], ',')] for c in ("g1_1", "g5_1", "g1_2", "g5_2"))
end
function sintg(v)
    rr = filter(isfinite, v)
    return (nf = 100count(!isfinite, v) / length(v), med = 100median(rr), p10 = 100quantile(rr, 0.1), p95 = 100quantile(rr, 0.95),
            meglio = 100count(<(-1e-9), rr) / length(v), e1 = 100count(<=(0.01), rr) / length(v))
end
for (c, nome) in (("g1_1", "griglia, scelta secca, senza margini"), ("g5_1", "griglia + verifica delle prime 5, senza margini"),
                  ("g1_2", "griglia, scelta secca, margine piccolo"), ("g5_2", "griglia + margine + verifica delle prime 5"))
    x = sintg([getproperty(y, Symbol(c)) for y in righe]); v = sintg(vg[c])
    say(@sprintf("  %-48s non fattibili %5.1f%% (%5.1f%%) | mediana %+.3f%% (%+.3f%%), p10 %+.2f%% (%+.2f%%), p95 %+.2f%% (%+.2f%%) | più economica della migliore delle 288 %5.1f%% (%5.1f%%), entro +1%% %5.1f%% (%5.1f%%)%s",
                 nome, x.nf, v.nf, x.med, v.med, x.p10, v.p10, x.p95, v.p95, x.meglio, v.meglio, x.e1, v.e1,
                 c == "g5_2" ? "   ← strategia di riferimento sulla griglia" : ""))
end
say(@sprintf("\ntempo totale: %.1f min", (time() - T0) / 60))
close(OUT)
