# fase10/06_velocita.jl: quanto è più veloce la rete neurale (6b) del simulatore, alla pari.
#
#   julia -t 1 --project=fase10 fase10/06_velocita.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_06_t1.txt 2>&1
#   julia -t 8 --project=fase10 fase10/06_velocita.jl > ~/Documents/lavoro/ml_treno_dati/fase10_log/log_06_t8.txt 2>&1
#
# Simulatore: valuta_progetto (TrainPowertrain invariato, configurazione della campagna) su 12 tratte di validazione di
# lunghezza diversa × 3 coppie, dopo un giro di riscaldamento; il precalcolo della tratta a parte.
# Rete: le 8 grandezze + vincoli e costo (valuta della fase 9) per 1 punto, per le 288 coppie e per la griglia fitta
# (9702 punti) delle stesse tratte. Con -t 1 tutto su un core (anche BLAS); con -t 8 la rete usa 8 thread.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "comune.jl"))
const NT = Threads.nthreads()
BLAS.set_num_threads(NT)
const LOG = joinpath(BASE, "fase10_log")
const OUT = open(joinpath(LOG, "06_velocita_t$(NT).txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase10/06_velocita.jl  ", now(), "  thread: ", NT, "  BLAS: ", BLAS.get_num_threads(), "  ", Sys.cpu_info()[1].model)

const DIR_TRATTE = joinpath(BASE, "tratte_doe_16384")
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const JX = [findfirst(==(c), Arrow.names(CT)) for c in NORM.nx]
const XC = reduce(hcat, (collect(getproperty(CT, c)) for c in Arrow.names(CT)))
const IL = findfirst(==(:x_L_km), Arrow.names(CT)); const IT = findfirst(==(:x_tempo_limiti_ar_s), Arrow.names(CT))
function rete_costo(r, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    d = Dati(ingressi(repeat(XC[r:r, JX], N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), fill(Int32(r), N), zeros(Int16, N),
             m, n, fill(XC[r, IL], N), fill(XC[r, IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    return valuta(m, n, fill(XC[r, IL], N), q)
end

# 12 tratte di validazione: 4 corte, 4 medie, 4 lunghe
tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
trv = sort(unique(Int.(tv.tratta))); Ls = [XC[r, IL] for r in trv]
scegli(a, b) = (s = [r for (r, L) in zip(trv, Ls) if a <= L < b]; s[round.(Int, range(1, length(s); length = 4))])
TRATTE = vcat(scegli(0, 40), scegli(100, 180), scegli(240, 301))
GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(c.m[i], c.n[i]) for i in 1:288] end
using Random
COPPIE = C288[randperm(Xoshiro(20261116), 288)[1:24]]     # 24 coppie a caso fra le 288, le stesse per tutte le tratte

# riscaldamento (compilazione) di entrambi
let t = leggi_tratte_materializzate(DIR_TRATTE; solo = [TRATTE[1]])[1]
    pre = PrecalcoloTratta(t.cp, "andata&ritorno")
    valuta_progetto(0.3, 0.6, 195_000.0, t.cp, "andata&ritorno"; config = CFG_CAMP, precalcolo = pre)
    rete_costo(TRATTE[1], [(0.3, 0.6)]); rete_costo(TRATTE[1], GRIGLIA[1:100])
end

say("\n tratta    L [km] | simulatore: precalcolo  per progetto (media di 24) | rete + costo: 1 punto   288 coppie   griglia 9702 | rapporto per progetto")
righe = NamedTuple[]
for r in TRATTE
    t = leggi_tratte_materializzate(DIR_TRATTE; solo = [r])[1]
    t0 = time(); pre = PrecalcoloTratta(t.cp, "andata&ritorno"); tpre = time() - t0
    ts = Float64[]
    for (m, n) in COPPIE
        t0 = time(); valuta_progetto(m, n, 195_000.0, t.cp, "andata&ritorno"; config = CFG_CAMP, precalcolo = pre); push!(ts, time() - t0)
    end
    tsim = mean(ts)
    t1 = minimum(@elapsed(rete_costo(r, [(0.3, 0.6)])) for _ in 1:20)
    t288 = minimum(@elapsed(rete_costo(r, C288)) for _ in 1:3)
    tgr = minimum(@elapsed(rete_costo(r, GRIGLIA)) for _ in 1:2)
    push!(righe, (tratta = r, L = XC[r, IL], pre = tpre, sim = tsim, r1 = t1, r288 = t288, rgr = tgr))
    say(@sprintf(" %6d  %7.1f |  %8.1f ms  %10.1f ms                    | %8.1f µs  %8.1f ms  %9.0f ms | %8.0f×", r, XC[r, IL], 1000tpre,
                 1000tsim, 1e6t1, 1000t288, 1000tgr, tsim / (tgr / length(GRIGLIA))))
end
sim = mean(x.sim for x in righe); gr_ = mean(x.rgr for x in righe) / length(GRIGLIA); r1 = mean(x.r1 for x in righe); r288 = mean(x.r288 for x in righe)
say(@sprintf("\nmedie: simulatore %.1f ms a progetto (+ precalcolo %.1f ms a tratta); rete + costo %.1f µs per un punto solo, %.1f µs a punto sulle 288 coppie, %.2f µs a punto sulla griglia",
             1000sim, 1000mean(x.pre for x in righe), 1e6r1, 1e6r288 / 288, 1e6gr_))
say(@sprintf("rapporto per progetto: punto singolo %.0f×, 288 coppie %.0f×, griglia %.0f×", sim / r1, sim / (r288 / 288), sim / gr_))
close(OUT)
