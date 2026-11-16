# fase12/04_vita_fc.jl: da dove viene l'errore della rete sulla vita della fuel cell sulle 166 linee della rete (fase12/03: 16% in
# mediana contro 1,7% sulla validazione DoE, quasi sempre per eccesso).
#
#   julia -t 8 --project=fase12 fase12/04_vita_fc.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_04.txt 2>&1
#
# Nessuna simulazione nuova. Il simulatore (Degradation.jl, degrado_fc_dettaglio) somma quattro voci di degrado per viaggio:
#   accensioni (13,79 µV ciascuna), minimo (8,662 µV/h), cicli di carico (0,4185 µV per ciclo equivalente
#   Σ|ΔP| / (2·(P_nom − P_idling)), conteggio :cicli_equivalenti della campagna), alto carico (10 µV/h sopra 0,8·P_nom);
#   vita_FC_f1_ore = costante / (degrado per ora di viaggio).
# Confronto, sugli ibridi completati: le linee della rete (sim_vere/rete_288) contro le tratte DoE di validazione (gruppi 7 e 12
# della campagna P9_D28_16384), coppia per coppia (le 288 coppie sono le stesse). Poi quale voce spiega l'errore della rete.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "04_vita_fc.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/04_vita_fc.jl  ", now())
const VOCI = (:acc, :idl, :car, :alto); const NOMI_VOCI = ("accensioni", "minimo", "cicli di carico", "alto carico")
const COL_VOCI = ("dV_accensioni_uV", "dV_idling_uV", "dV_cicli_carico_uV", "dV_alto_carico_uV")
const DIR_ARROW = joinpath(BASE, "P9_D28_16384", "arrow")
coppia_id(m, n) = (round(m; digits = 12), round(n; digits = 12))

# ── i casi: ibridi completati, con le quattro voci per ora di viaggio ───────────
function caso(tratta, m, n, durata, dv, vita, acc, ore_fc)
    h = durata / 3600
    return (tratta = tratta, m = m, n = n, ore = h, r = dv ./ h, tot = sum(dv) / h, vita = vita, acc = acc, ore_fc = ore_fc)
end
# DoE, validazione (gruppi 7 e 12 = blocchi 25–28 e 45–48)
doe = NamedTuple[]
for b in vcat(25:28, 45:48)
    t = Arrow.Table(joinpath(DIR_ARROW, @sprintf("blocco_%02d.arrow", b)))
    for i in eachindex(t.tratta)
        (t.stato[i] == 1 && t.m[i] > 0) || continue
        push!(doe, caso(Int(t.tratta[i]), Float64(t.m[i]), Float64(t.n[i]), Float64(t.durata_viaggio_s[i]),
                        [Float64(getproperty(t, Symbol(c))[i]) for c in COL_VOCI], Float64(t.vita_FC_f1_ore[i]), Float64(t.accensioni_FC[i]),
                        Float64(t.ore_FC_viaggio_h[i])))
    end
end
# linee della rete
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
lin = NamedTuple[]
for l in readlines(joinpath(BASE, "fase12", "sim_vere", "rete_288", "registro.csv"))[2:end]
    c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
    (c["stato"] == "completed" && pf(c["m"]) > 0) || continue
    push!(lin, caso(String(c["tratta"]), pf(c["m"]), pf(c["n"]), pf(c["durata_viaggio_s"]), [pf(c[k]) for k in COL_VOCI],
                    pf(c["vita_FC_f1_ore"]), pf(c["accensioni_FC"]), pf(c["ore_FC_viaggio_h"])))
end
say(@sprintf("ibridi completati: DoE validazione %d casi (%d tratte), linee della rete %d casi (%d linee)", length(doe),
             length(unique(x.tratta for x in doe)), length(lin), length(unique(x.tratta for x in lin))))
# controllo: vita × degrado per ora = costante (la vita è davvero costante / degrado orario)
k_doe = [x.vita * x.tot for x in doe]; k_lin = [x.vita * x.tot for x in lin]
say(@sprintf("controllo vita × degrado orario: DoE %.6g–%.6g, linee %.6g–%.6g (deve essere una costante)", extrema(k_doe)..., extrema(k_lin)...))
const KV = median(k_doe)

# ── 1. le quattro voci: quanto pesano e quanto valgono per ora ───────────────────
say("\n1. Le quattro voci del degrado (µV per ora di viaggio), mediana sui casi:")
say(@sprintf("   %-16s %12s %12s %10s   %s", "voce", "DoE valid.", "linee rete", "rapporto", "quota del totale DoE → linee"))
for (j, nm) in enumerate(NOMI_VOCI)
    a = median(x.r[j] for x in doe); b = median(x.r[j] for x in lin)
    qa = median(x.r[j] / x.tot for x in doe); qb = median(x.r[j] / x.tot for x in lin)
    say(@sprintf("   %-16s %12.3f %12.3f %10.2f   %5.1f%% → %5.1f%%", nm, a, b, b / a, 100qa, 100qb))
end
say(@sprintf("   %-16s %12.3f %12.3f %10.2f", "totale", median(x.tot for x in doe), median(x.tot for x in lin),
             median(x.tot for x in lin) / median(x.tot for x in doe)))
say(@sprintf("   accensioni per viaggio: DoE %.1f, linee %.1f (mediana); ore di FC accesa / ore di viaggio: DoE %.3f, linee %.3f",
             median(x.acc for x in doe), median(x.acc for x in lin), median(x.ore_fc / x.ore for x in doe), median(x.ore_fc / x.ore for x in lin)))

# ── 2. coppia per coppia: le linee contro il DoE alla stessa (m, n) ─────────────
say("\n2. Coppia per coppia (stesse m, n): rapporto mediano linee / DoE di ogni voce per ora")
md = Dict{Tuple{Float64,Float64},Vector{Float64}}()   # mediana DoE di ogni voce e del totale, per coppia
for g in unique(coppia_id(x.m, x.n) for x in doe)
    xs = [x for x in doe if coppia_id(x.m, x.n) == g]
    md[g] = vcat([median(x.r[j] for x in xs) for j in 1:4], median(x.tot for x in xs))
end
rapp = [Float64[] for _ in 1:5]
for x in lin
    g = coppia_id(x.m, x.n); haskey(md, g) || continue
    for j in 1:4; md[g][j] > 0 && push!(rapp[j], x.r[j] / md[g][j]); end
    push!(rapp[5], x.tot / md[g][5])
end
for (j, nm) in enumerate((NOMI_VOCI..., "totale"))
    say(@sprintf("   %-16s mediana %.2f   (25° %.2f, 75° %.2f)", nm, median(rapp[j]), quantile(rapp[j], 0.25), quantile(rapp[j], 0.75)))
end

# ── 3. l'errore della rete: quale voce lo spiega ─────────────────────────────────
# la rete prevede la vita; il degrado orario "implicito" della rete è KV / vita prevista. Lo scarto fra il degrado vero e
# quello implicito si confronta con lo scarto di ogni voce dal DoE alla stessa coppia.
say("\n3. L'errore della rete sulla vita, voce per voce")
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const XL = let t = Arrow.Table(joinpath(BASE, "fase5_dominio", "caratteristiche_rete_20261110.arrow"))
    Dict(String(t.tratta[i]) => [Float64(getproperty(t, c)[i]) for c in NORM.nx] for i in eachindex(t.tratta))
end
vita_rete = Dict{Tuple{String,Float64,Float64},Float64}()
for nome in unique(x.tratta for x in lin)
    xs = [x for x in lin if x.tratta == nome]; N = length(xs); xv = XL[nome]
    m = [x.m for x in xs]; n = [x.n for x in xs]
    d = Dati(ingressi(repeat(xv', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
             m, n, fill(xv[IL], N), fill(xv[IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    for i in 1:N; vita_rete[(nome, m[i], n[i])] = p.vita_FC_f1[i]; end
end
err = [100(vita_rete[(x.tratta, x.m, x.n)] / x.vita - 1) for x in lin]          # errore con segno, % (positivo: la rete la dà più lunga)
dtot = [x.tot - KV / vita_rete[(x.tratta, x.m, x.n)] for x in lin]               # degrado orario mancante alla rete [µV/h]
say(@sprintf("   errore con segno della rete: mediana %+.1f%%, 25° %+.1f%%, 75° %+.1f%%; degrado orario che manca alla rete: mediana %.3f µV/h",
             median(err), quantile(err, 0.25), quantile(err, 0.75), median(dtot)))
# eccesso di ogni voce rispetto al DoE alla stessa coppia [µV/h]
ecc = [[x.r[j] - md[coppia_id(x.m, x.n)][j] for x in lin] for j in 1:4]
say("   eccesso di ogni voce sulle linee rispetto al DoE alla stessa coppia (µV/h), e quota del degrado che manca alla rete:")
for (j, nm) in enumerate(NOMI_VOCI)
    say(@sprintf("   %-16s eccesso mediano %+.3f µV/h   somma degli eccessi / somma del degrado mancante: %5.1f%%", nm, median(ecc[j]),
                 100sum(ecc[j]) / sum(dtot)))
end
rk(v) = invperm(sortperm(v))
spear(a, b) = cor(Float64.(rk(a)), Float64.(rk(b)))
say("   correlazione di rango, caso per caso, fra l'errore della rete e l'eccesso di ogni voce:")
for (j, nm) in enumerate(NOMI_VOCI); say(@sprintf("   %-16s %+.2f", nm, spear(err, ecc[j]))); end

# per linea: errore mediano e voce dominante
say("\n4. Le 15 linee con l'errore più grande: errore mediano e rapporto linee / DoE di ogni voce (stessa coppia)")
say(@sprintf("   %-40s %8s %8s %8s %8s %8s %8s", "linea", "errore", "acc.", "minimo", "carico", "alto", "totale"))
per = NamedTuple[]
for nome in unique(x.tratta for x in lin)
    ii = [i for i in eachindex(lin) if lin[i].tratta == nome]
    q(j) = median(lin[i].r[j] / md[coppia_id(lin[i].m, lin[i].n)][j] for i in ii if md[coppia_id(lin[i].m, lin[i].n)][j] > 0)
    push!(per, (linea = nome, err = median(err[ii]), acc = q(1), idl = q(2), car = q(3), alto = q(4),
                tot = median(lin[i].tot / md[coppia_id(lin[i].m, lin[i].n)][5] for i in ii)))
end
sort!(per; by = x -> -x.err)
for x in per[1:15]
    say(@sprintf("   %-40s %+7.1f%% %8.2f %8.2f %8.2f %8.2f %8.2f", x.linea, x.err, x.acc, x.idl, x.car, x.alto, x.tot))
end
say(@sprintf("   correlazione di rango fra le linee, errore mediano contro rapporto: accensioni %+.2f, minimo %+.2f, carico %+.2f, alto %+.2f, totale %+.2f",
             spear([x.err for x in per], [x.acc for x in per]), spear([x.err for x in per], [x.idl for x in per]),
             spear([x.err for x in per], [x.car for x in per]), spear([x.err for x in per], [x.alto for x in per]),
             spear([x.err for x in per], [x.tot for x in per])))
open(joinpath(LOG, "04_vita_fc_linee.csv"), "w") do io
    println(io, "linea,errore_vita_FC_pct,rapporto_accensioni,rapporto_minimo,rapporto_carico,rapporto_alto_carico,rapporto_totale")
    for x in per; println(io, join((x.linea, (@sprintf("%.4g", v) for v in (x.err, x.acc, x.idl, x.car, x.alto, x.tot))...), ',')); end
end
close(OUT)
