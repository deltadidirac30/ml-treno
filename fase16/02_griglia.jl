# fase16/02_griglia.jl: la griglia fitta simulata (9702 progetti: m = 0 oppure 0,03–0,99, n = 0,01–0,99, passo 0,01) sulle 256
# tratte del test DoE (fase16/01_tratte.jl), con il percorso e il config.txt della campagna, come fase13/02_griglia_fitta.jl:
# configurazione della campagna, andata e ritorno, 195 t. Tratte DoE lette con leggi_tratte_materializzate, come la campagna.
#
#   julia -t 8 --project=fase16 fase16/02_griglia.jl >> ~/Documents/lavoro/ml_treno_dati/fase16_log/log_02.txt 2>&1   (da lancia.sh)
#
# Una campagna per tratta in ml_treno_dati/fase16/griglia/route_<id>. Si può riprendere: le tratte già complete non si rifanno,
# una tratta interrotta a metà si rifà da capo. Scrive in fase16_log: 02_griglia.txt (in aggiunta), 02_tempi.csv.

using TrainPowertrain, Arrow, Statistics, Printf, Dates
const TP = TrainPowertrain
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const LOG = joinpath(BASE, "fase16_log"); mkpath(LOG)
const SIM = joinpath(BASE, "fase16", "griglia"); mkpath(SIM)
const OUT = open(joinpath(LOG, "02_griglia.txt"), "a")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("\nfase16/02_griglia.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const DIR_TRATTE = joinpath(BASE, "tratte_doe_16384")
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA)
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const CAMPIONE = parse.(Int, split(read(joinpath(BASE, "fase16", "tratte.txt"), String), ','))
cartella(r) = joinpath(SIM, @sprintf("route_%06d", r))
completa(dir) = isfile(joinpath(dir, "registro.csv")) && countlines(joinpath(dir, "registro.csv")) >= NG + 1
mancanti = [r for r in CAMPIONE if !completa(cartella(r))]
say(@sprintf("tratte: %d, progetti per tratta: %d; già complete %d, da fare %d", length(CAMPIONE), NG, length(CAMPIONE) - length(mancanti), length(mancanti)))
const TR = isempty(mancanti) ? [] : leggi_tratte_materializzate(DIR_TRATTE; solo = Set(mancanti))
length(TR) == length(mancanti) || error("lette $(length(TR)) tratte su $(length(mancanti))")
fatte = 0; tsum = 0.0
for tr in TR
    global fatte, tsum
    r = parse(Int, tr.id[7:end]); dir = cartella(r)
    isdir(dir) && rm(dir; recursive = true)              # campagna interrotta a metà: si rifà da capo
    t0 = time()
    spec = CampagnaSpec(tratte = [tr], coppie = GRIGLIA, cartella = dir, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(dir, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $dir")
    completa(dir) || error("registro incompleto in $dir")
    dt = time() - t0; fatte += 1; tsum += dt
    open(joinpath(LOG, "02_tempi.csv"), "a") do io; println(io, r, ',', @sprintf("%.2f", dt)); end
    say(@sprintf("  [%3d/%d] route_%06d %6.1f s   (trascorsi %.1f min, ne mancano circa %.0f)", fatte, length(TR), r, dt, (time() - T0) / 60,
                 tsum / fatte * (length(TR) - fatte) / 60))
end
say(@sprintf("griglia fitta: %d tratte simulate in questo lancio in %.1f min; complete %d su %d", fatte, (time() - T0) / 60,
             count(r -> completa(cartella(r)), CAMPIONE), length(CAMPIONE)))
close(OUT)
