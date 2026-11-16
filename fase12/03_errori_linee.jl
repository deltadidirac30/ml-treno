# fase12/03_errori_linee.jl: quanto sbaglia la rete 6b su ogni grandezza, linea per linea, sulle 166 linee della rete.
#
#   julia -t 8 --project=fase12 fase12/03_errori_linee.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_03.txt 2>&1
#
# Nessuna simulazione nuova: usa le 288 coppie × 166 linee già simulate nel passo 8c (sim_vere/rete_288/registro.csv,
# configurazione della campagna) e le caratteristiche della fase 5 (caratteristiche_rete_20261110.arrow).
# Errori come la fase 10 (metriche):
#   relativo [%] = 100·|rete − simulatore| / |simulatore| per durata, serbatoio, idrogeno, vita della batteria, vita della FC,
#                  C-rate; assoluto per il SOC finale; percentuale di giusti per scarica (p ≥ 0,5) e fattibilità.
#   Casi: tutti i simulati (completati e scartati da D3) dove il simulatore dà la grandezza; serbatoio, idrogeno e vita della FC
#   solo negli ibridi (m > 0), idrogeno e SOC solo nei completati (nei scartati da D3 il registro non li ha); il costo
#   (senza penalità) sui casi fattibili per il simulatore e non scartati da D3 dalla rete.
# Scrive in fase12_log: 03_errori_linee.txt (riassunto) e 03_errori_linee.csv (una riga per linea: mediana e massimo di ogni
# grandezza sulle sue 288 coppie).

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "03_errori_linee.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/03_errori_linee.jl  ", now(), "  thread: ", Threads.nthreads())

const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const XL = let t = Arrow.Table(joinpath(BASE, "fase5_dominio", "caratteristiche_rete_20261110.arrow"))
    Dict(String(t.tratta[i]) => [Float64(getproperty(t, c)[i]) for c in NORM.nx] for i in eachindex(t.tratta))
end
# distanza dalle tratte di addestramento, come usa_surrogato.jl
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1); ((XA .- μ) ./ σ, μ, σ)
end
dist(x) = sqrt(minimum(vec(sum((ZA .- ((x' .- MU) ./ SG)) .^ 2; dims = 2))))
const DOM = let l = readlines(joinpath(@__DIR__, "..", "fase5", "risultati", "03_dominio_tratte.csv")), h = split(l[1], ',')
    Dict(String(x[2]) => parse(Int, x[findfirst(==("n_fuori"), h)]) for x in split.(l[2:end], ',') if x[1] == "rete_20261110")
end

# ── il registro del simulatore ───────────────────────────────────────────────────
const REG = joinpath(BASE, "fase12", "sim_vere", "rete_288", "registro.csv")
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
casi = Dict{String,Vector{NamedTuple}}()
for l in readlines(REG)[2:end]
    c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
    push!(get!(casi, String(c["tratta"]), NamedTuple[]),
          (m = pf(c["m"]), n = pf(c["n"]), completato = c["stato"] == "completed", fattibile = c["tipo_esito"] == "fattibile",
           durata = pf(c["durata_viaggio_s"]), serbatoio = pf(c["massa_serbatoio_kg"]), H2 = pf(c["H2_cons_kg"]), SOC = pf(c["SOC_end"]),
           scarica = pf(c["scarica_s"]) > 1e-6, scarica_nota = isfinite(pf(c["scarica_s"])), vita_batt = pf(c["vita_batt_cicli_viaggi"]),
           vita_FC_f1 = pf(c["vita_FC_f1_ore"]), C_rate = pf(c["C_rate_scarica_max"]), costo = pf(c["total_cost_EUR_km"])))
end
nomi = sort(collect(keys(casi)))
length(nomi) == 166 && all(k -> length(casi[k]) == 288, nomi) || error("attese 166 linee × 288 coppie")
haskey(XL, nomi[1]) || error("caratteristiche mancanti")

# ── errori, linea per linea ──────────────────────────────────────────────────────
const G = [(:durata, "durata", :rel), (:serbatoio, "serbatoio", :rel), (:H2, "idrogeno", :rel), (:SOC, "SOC finale", :abs),
           (:vita_batt, "vita batteria", :rel), (:vita_FC_f1, "vita FC (f1)", :rel), (:C_rate, "C-rate scarica", :rel), (:costo, "costo", :rel)]
tutti = Dict(g[1] => Float64[] for g in G)            # tutti gli errori, per il riassunto globale
segno = Dict(g[1] => Float64[] for g in G)            # gli stessi con il segno (rete − simulatore): la rete sta sopra o sotto?
righe = NamedTuple[]
for nome in nomi
    cs = casi[nome]; x = XL[nome]; N = length(cs)
    m = [c.m for c in cs]; n = [c.n for c in cs]
    d = Dati(ingressi(repeat(x', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
             m, n, fill(x[IL], N), fill(x[IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    v = valuta(m, n, fill(x[IL], N), q)
    r = Dict{Symbol,Any}(:linea => nome, :L_km => x[IL], :distanza => dist(x), :fuori_dominio => DOM[nome])
    for (k, _, tipo) in G
        e = Float64[]; es = Float64[]
        for i in 1:N
            c = cs[i]
            k in (:serbatoio, :H2, :vita_FC_f1) && m[i] == 0 && continue
            k in (:H2, :SOC) && !c.completato && continue
            k === :costo && !(c.fattibile && !v.d3[i]) && continue
            y = getproperty(c, k); yh = k === :costo ? v.costo_totale[i] : getproperty(p, k)[i]
            (isfinite(y) && isfinite(yh)) || continue
            push!(es, tipo === :rel ? 100(yh - y) / abs(y) : yh - y); push!(e, abs(es[end]))
        end
        append!(tutti[k], e); append!(segno[k], es)
        r[Symbol(k, "_mediana")] = isempty(e) ? NaN : median(e)
        r[Symbol(k, "_max")] = isempty(e) ? NaN : maximum(e)
        r[Symbol(k, "_casi")] = length(e)
    end
    sc = [i for i in 1:N if cs[i].scarica_nota]
    r[:scarica_giusta] = 100mean(q.scarica[i] == cs[i].scarica for i in sc)
    r[:fattibilita_giusta] = 100mean(v.fattibile[i] == cs[i].fattibile for i in 1:N)
    r[:fattibili_veri] = count(c -> c.fattibile, cs)
    push!(righe, NamedTuple(r))
end

# ── il CSV, una riga per linea ───────────────────────────────────────────────────
col = vcat([:linea, :L_km, :distanza, :fuori_dominio, :fattibili_veri],
           [Symbol(k, s) for (k, _, _) in G for s in ("_mediana", "_max", "_casi")], [:scarica_giusta, :fattibilita_giusta])
open(joinpath(LOG, "03_errori_linee.csv"), "w") do io
    println(io, join(col, ','))
    for r in righe; println(io, join((x isa AbstractFloat ? @sprintf("%.6g", x) : string(x) for x in (r[c] for c in col)), ',')); end
end

# ── il riassunto ─────────────────────────────────────────────────────────────────
say(@sprintf("\n%d linee × 288 coppie = %d casi simulati (%d completati)", length(nomi), sum(length(casi[k]) for k in nomi),
             sum(count(c -> c.completato, casi[k]) for k in nomi)))
say("\n1. Su tutti i casi insieme (errore relativo in %, SOC in valore assoluto):")
say(@sprintf("   %-15s %8s %8s %8s %8s %8s %8s %8s %16s", "grandezza", "casi", "media", "mediana", "p90", "p95", "min", "max", "rete sopra il sim."))
for (k, nm, tipo) in G
    e = tutti[k]
    f = tipo === :abs ? "%8.4f" : "%8.2f"
    say(@sprintf("   %-15s %8d ", nm, length(e)), join((Printf.format(Printf.Format(f), x) for x in (mean(e), median(e), quantile(e, 0.9), quantile(e, 0.95), minimum(e), maximum(e))), " "),
        @sprintf("   %5.1f%% dei casi", 100mean(segno[k] .> 0)))
end
sg = [r.scarica_giusta for r in righe]; fg = [r.fattibilita_giusta for r in righe]
say(@sprintf("   %-15s scarica giusta %.2f%% dei casi; fattibilità giusta %.2f%%", "",
             sum(r.scarica_giusta * 288 for r in righe) / (288 * length(righe)), sum(r.fattibilita_giusta * 288 for r in righe) / (288 * length(righe))))

say("\n2. Linea per linea: l'errore mediano di ogni linea (sulle sue coppie), e le linee migliore e peggiore:")
say(@sprintf("   %-15s %8s %8s %8s   %-38s %-38s", "grandezza", "media", "min", "max", "linea migliore", "linea peggiore"))
for (k, nm, tipo) in G
    v = [getproperty(r, Symbol(k, "_mediana")) for r in righe]; ok = findall(isfinite, v)
    imin = ok[argmin(v[ok])]; imax = ok[argmax(v[ok])]
    f = tipo === :abs ? "%8.4f" : "%8.2f"
    say(@sprintf("   %-15s ", nm), join((Printf.format(Printf.Format(f), x) for x in (mean(v[ok]), v[imin], v[imax])), " "),
        @sprintf("   %-38s %-38s", righe[imin].linea, righe[imax].linea))
end
say(@sprintf("   %-15s %8.2f %8.2f %8.2f   (%% giusta)", "scarica", mean(sg), minimum(sg), maximum(sg)))
say(@sprintf("   %-15s %8.2f %8.2f %8.2f   (%% giusta)", "fattibilità", mean(fg), minimum(fg), maximum(fg)))

say("\n3. Errore massimo su una singola coppia, per grandezza: dove succede")
for (k, nm, tipo) in G
    v = [getproperty(r, Symbol(k, "_max")) for r in righe]; ok = findall(isfinite, v); i = ok[argmax(v[ok])]
    say(tipo === :abs ? @sprintf("   %-15s %8.4f  %s", nm, v[i], righe[i].linea) : @sprintf("   %-15s %7.1f%%  %s", nm, v[i], righe[i].linea))
end
say("\nTabella completa: ", joinpath(LOG, "03_errori_linee.csv"))
close(OUT)
