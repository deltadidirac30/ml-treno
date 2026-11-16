# fase12/14_errori_ottimo.jl: nel progetto scelto dalla strategia G (fase12/13), previsioni della rete contro il simulatore, sulle
# linee non elettrificate oltre il 70% (tutto RINF). Legge le scelte da ml_treno_dati/fase12_log/13_verifica_locale_linee.csv.
#   julia -t 8 --project=fase12 fase12/14_errori_ottimo.jl
include(joinpath("/Users/kairos/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno", "fase9", "comune.jl"))
include(joinpath("/Users/kairos/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno", "fase10", "comune.jl"))
include(joinpath("/Users/kairos/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Il mio Drive/Dottorato/ml_treno", "fase1", "caratteristiche.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = devnull
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/12_riassunto_non_el.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_TR = joinpath(TPR, "dati_rete", "tratte_rete_rinf", "tutto_rinf")
const REG = joinpath(BASE, "fase12", "sim_rinf", "tutto_rinf", "registro.csv")
const DIR_HTML = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")

# ── dati ─────────────────────────────────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
casi = Dict{String,Dict{Tuple{Float64,Float64},NamedTuple}}()
for l in readlines(REG)[2:end]
    c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
    get!(casi, String(c["tratta"]), Dict{Tuple{Float64,Float64},NamedTuple}())[(pf(c["m"]), pf(c["n"]))] =
        (completato = c["stato"] == "completed", fattibile = c["tipo_esito"] == "fattibile",
         durata = pf(c["durata_viaggio_s"]), serbatoio = pf(c["massa_serbatoio_kg"]), H2 = pf(c["H2_cons_kg"]), SOC = pf(c["SOC_end"]),
         scarica = pf(c["scarica_s"]) > 1e-6, vita_batt = pf(c["vita_batt_cicli_viaggi"]), vita_FC_f1 = pf(c["vita_FC_f1_ore"]),
         C_rate = pf(c["C_rate_scarica_max"]), costo = pf(c["total_cost_EUR_km"]), tempo = pf(c["tempo_s"]))
end
nomi = sort(collect(keys(casi)))
dividi(r) = (out = String[]; buf = IOBuffer(); dentro = false;
             for ch in r; ch == '"' ? (dentro = !dentro) : (ch == ',' && !dentro) ? push!(out, String(take!(buf))) : print(buf, ch); end;
             push!(out, String(take!(buf))); out)
rie = let l = readlines(joinpath(DIR_HTML, "riepilogo.csv")), h = dividi(l[1])
    Dict(d["tratta"] => d for d in (Dict(h[j] => x for (j, x) in enumerate(dividi(r))) for r in l[2:end] if !isempty(strip(r))))
end
quota_ne(l) = parse(Float64, rie[l]["km_non_el"]) / parse(Float64, rie[l]["lunghezza_km"])
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1); ((XA .- μ) ./ σ, μ, σ)
end
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA)
const CFG = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
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
const G = [(:durata, "durata del viaggio", :rel), (:serbatoio, "massa del serbatoio", :rel), (:H2, "idrogeno consumato", :rel),
           (:SOC, "SOC finale (assoluto)", :abs), (:vita_batt, "vita della batteria", :rel), (:vita_FC_f1, "vita della fuel cell", :rel),
           (:C_rate, "C-rate di scarica", :rel), (:costo, "costo [€/km]", :rel)]

function leggi(f)
    l = readlines(f); h = split(l[1], ',')
    [Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end]]
end
G13 = Dict(r["linea"] => (parse(Float64, r["G_m"]), parse(Float64, r["G_n"])) for r in leggi(expanduser("~/Documents/lavoro/ml_treno_dati/fase12_log/13_verifica_locale_linee.csv")))
sel = filter(l -> quota_ne(l) > 0.7, nomi)
E = Dict(g[1] => Float64[] for g in G); peg = Dict(g[1] => ("", 0.0) for g in G); fatt_rete = 0
for tc in leggi_tratte_reali(sel; cartella = DIR_TR)
    global fatt_rete
    m, n = G13[tc.id]
    pr = profilo_tratta(tc.cp); v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    p, v, _, _ = rete(X, [(m, n)])
    e = valuta_progetto(m, n, 195_000.0, tc.cp, "andata&ritorno"; config = CFG)
    g = sim_grandezze(e)
    fatt_rete += v.fattibile[1]
    for (k, _, tipo) in G
        k in (:serbatoio, :H2, :vita_FC_f1) && m == 0 && continue
        y = k === :costo ? e.costo_totale : getproperty(g, k); yh = k === :costo ? v.costo_totale[1] : getproperty(p, k)[1]
        (isfinite(y) && isfinite(yh)) || continue
        x = tipo === :rel ? 100(yh - y) / abs(y) : yh - y
        push!(E[k], x); abs(x) > abs(peg[k][2]) && (peg[k] = (tc.id, x))
    end
end
println(@sprintf("%d linee; nel progetto scelto (G) la rete lo dice fattibile in %d", length(sel), fatt_rete))
println(@sprintf("%-24s %6s %10s %10s %10s %10s %8s %8s   %s", "grandezza", "linee", "mediana", "|mediana|", "p90 |e|", "max |e|", ">5%", ">10%", "caso peggiore"))
for (k, nm, tipo) in G
    x = E[k]; f(v) = tipo === :abs ? @sprintf("%10.4f", v) : @sprintf("%9.2f%%", v)
    println(@sprintf("%-24s %6d ", nm, length(x)), join((f(v) for v in (median(x), median(abs.(x)), quantile(abs.(x), 0.9), maximum(abs.(x)))), " "),
            tipo === :abs ? @sprintf(" %8s %8s", "—", "—") : @sprintf(" %8d %8d", count(v -> abs(v) > 5, x), count(v -> abs(v) > 10, x)),
            @sprintf("   %s (%s)", peg[k][1], tipo === :abs ? @sprintf("%+.4f", peg[k][2]) : @sprintf("%+.1f%%", peg[k][2])))
end
