# fase13/02_griglia_fitta.jl: la griglia fitta simulata (9702 progetti) sulle 146 linee non elettrificate oltre il 70%, ricostruite
# dai dati del 17/11/2026 (fase13/01_linee.jl). È la tabella su cui si farà la classificazione dei treni. Come fase12/15 (passo 1):
# m = 0 oppure 0,03–0,99, n = 0,01–0,99, passo 0,01; configurazione della campagna, andata e ritorno, 195 t.
#
#   julia -t 8 --project=fase13 fase13/02_griglia_fitta.jl > ~/Documents/lavoro/ml_treno_dati/fase13_log/log_02.txt 2>&1
#
# Una campagna per linea in ml_treno_dati/fase13/griglia_rinf/<linea>. Si può riprendere: le linee già complete non si rifanno.
# Alla fine: l'ottimo vero di ogni linea (il progetto fattibile più economico) contro quello della griglia del 16/11
# (fase12/15, dati dell'11/11), in fase13_log/02_ottimo_linee.csv.

using TrainPowertrain, Arrow, Statistics, Printf, Dates
const TP = TrainPowertrain
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase13_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "02_griglia_fitta.txt"), "a")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase13/02_griglia_fitta.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const DIR_RINF = expanduser("~/Documents/lavoro/train-powertrain/dati_rete/tratte_rete_rinf")
const DIR_TR = joinpath(DIR_RINF, "tutto_rinf")
const SIM = joinpath(BASE, "fase13", "griglia_rinf")
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA)
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const nomi = filter(!isempty, strip.(readlines(joinpath(DIR_RINF, "linee_non_el_70.txt"))))
say(@sprintf("linee: %d, progetti per linea: %d", length(nomi), NG))

# ── 1. simulazione della griglia fitta ───────────────────────────────────────────
completa(dir) = isfile(joinpath(dir, "registro.csv")) && countlines(joinpath(dir, "registro.csv")) >= NG + 1
t_sim = Dict{String,Float64}(); fatte = 0
for (k, l) in enumerate(nomi)
    global fatte
    dir = joinpath(SIM, l)
    completa(dir) && continue
    isdir(dir) && rm(dir; recursive = true)              # campagna interrotta a metà: si rifà da capo
    t0 = time()
    spec = CampagnaSpec(tratte = leggi_tratte_reali([l]; cartella = DIR_TR), coppie = GRIGLIA, cartella = dir, direzioni = ["andata&ritorno"],
                        config = CFG_CAMP, peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(dir, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $dir")
    t_sim[l] = time() - t0; fatte += 1
    trascorso = time() - T0
    say(@sprintf("  [%3d/%d] %-40s %6.1f s   (trascorsi %.1f min, ne mancano circa %.0f)", k, length(nomi), l, t_sim[l], trascorso / 60,
                 trascorso / fatte * count(x -> !completa(joinpath(SIM, x)), nomi) / 60))
end
say(@sprintf("1. griglia fitta simulata su %d linee in questo lancio: %.1f min (%d già pronte)", fatte, sum(values(t_sim); init = 0.0) / 60, length(nomi) - fatte))

# ── 2. ottimo vero, contro la griglia del 16/11 ──────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
const J_M = findfirst(==("m"), INTEST); const J_N = findfirst(==("n"), INTEST); const J_ES = findfirst(==("tipo_esito"), INTEST)
const J_C = findfirst(==("total_cost_EUR_km"), INTEST)
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
function ottimo(dir)
    best = (NaN, NaN, Inf); nf = 0
    for r in Iterators.drop(eachline(joinpath(dir, "registro.csv")), 1)
        c = split(r, ',')
        c[J_ES] == "fattibile" || continue
        nf += 1; x = pf(c[J_C]); x < best[3] && (best = (pf(c[J_M]), pf(c[J_N]), x))
    end
    return best, nf
end
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
vecchio = let l = readlines(joinpath(BASE, "fase12_log", "15_ottimo_vero_linee.csv")), h = split(l[1], ',')
    Dict(String(split(r, ',')[1]) => Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r)))
end
righe = []
for l in nomi
    (m, n, c), nf = ottimo(joinpath(SIM, l))
    v = vecchio[l]; mv = parse(Float64, v["ottimo_m"]); nv = parse(Float64, v["ottimo_n"]); cv = parse(Float64, v["ottimo_costo"])
    push!(righe, (l, m, n, c, regime(m), nf, mv, nv, cv, regime(mv), 100(c / cv - 1)))
end
open(joinpath(LOG, "02_ottimo_linee.csv"), "w") do io
    println(io, "linea,m,n,costo,regime,fattibili,m_16nov,n_16nov,costo_16nov,regime_16nov,costo_vs_16nov_pct")
    for r in righe; println(io, join((r[1], r[2], r[3], @sprintf("%.5f", r[4]), r[5], r[6], r[7], r[8], @sprintf("%.5f", r[9]), r[10], @sprintf("%.3f", r[11])), ',')); end
end
dc = [r[11] for r in righe]
say("\n2. ottimo vero (dati 17/11) contro la griglia del 16/11 (dati 11/11), ", length(righe), " linee")
say(@sprintf("   costo dell'ottimo: mediana %+.2f%%, 10° %+.2f%%, 90° %+.2f%%, min %+.2f%%, max %+.2f%%", median(dc), quantile(dc, 0.1), quantile(dc, 0.9), minimum(dc), maximum(dc)))
say(@sprintf("   stesso progetto (m, n): %d; stesso regime: %d", count(r -> r[2] == r[7] && r[3] == r[8], righe), count(r -> r[5] == r[10], righe)))
for a in ("sola batteria", "ibrido FC piccola", "ibrido")
    say(@sprintf("   %-18s 16/11 %3d   17/11 %3d", a, count(r -> r[10] == a, righe), count(r -> r[5] == a, righe)))
end
say("   linee con il costo cambiato di oltre l'1% o con il progetto diverso:")
for r in sort(righe; by = r -> -abs(r[11]))
    (abs(r[11]) > 1 || r[2] != r[7] || r[3] != r[8]) || continue
    say(@sprintf("     %-40s %+6.2f%%   (%.2f, %.2f) → (%.2f, %.2f)%s", r[1], r[11], r[7], r[8], r[2], r[3], r[5] == r[10] ? "" : "   regime: " * r[10] * " → " * r[5]))
end
say(@sprintf("\nTempo totale %.1f min", (time() - T0) / 60))
close(OUT)
