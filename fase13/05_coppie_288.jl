# fase13/05_coppie_288.jl: il simulatore sulle 288 coppie della campagna (le prime 288 di P9_D28_16384), sulle 146 linee non
# elettrificate oltre il 70% con i dati del 17/11 (fase13/01_linee.jl). Come fase12/11 (passo 2, versione "tutto RINF").
# Serve agli errori della rete sulle linee reali e al confronto "migliore delle 288" (fase13/06–08).
#
#   julia -t 8 --project=fase13 fase13/05_coppie_288.jl > ~/Documents/lavoro/ml_treno_dati/fase13_log/log_05.txt 2>&1

using TrainPowertrain, Arrow, Printf, Dates
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const DIR_RINF = expanduser("~/Documents/lavoro/train-powertrain/dati_rete/tratte_rete_rinf")
const DIR = joinpath(BASE, "fase13", "sim_288")
isdir(DIR) && error("$DIR esiste già")
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end
nomi = filter(!isempty, strip.(readlines(joinpath(DIR_RINF, "linee_non_el_70.txt"))))
t0 = time()
spec = CampagnaSpec(tratte = leggi_tratte_reali(nomi; cartella = joinpath(DIR_RINF, "tutto_rinf")), coppie = C288, cartella = DIR,
                    direzioni = ["andata&ritorno"], config = CFG_CAMP, peso_a_carico = 195_000.0, modalita = :griglia)
redirect_stdout(devnull) do; esegui_campagna(spec); end
strip(read(joinpath(DIR, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna")
println(@sprintf("fase13/05  %s  TrainPowertrain %s: 288 coppie × %d linee simulate in %.1f min; righe nel registro: %d",
                 now(), TrainPowertrain.commit_codice(), length(nomi), (time() - t0) / 60, countlines(joinpath(DIR, "registro.csv")) - 1))
