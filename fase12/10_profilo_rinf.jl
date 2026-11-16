# fase12/10_profilo_rinf.jl: la stessa linea costruita dai dati sorgente (livellette RINF del Drive condiviso SurrogateTrains)
# invece che dalla mappa HTML (quota arrotondata a 0,1 m ogni 50 m). Solo simulatore vero, griglia fitta.
#
#   julia -t 8 --project=fase12 fase12/10_profilo_rinf.jl [linea] [regione] > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_10.txt 2>&1
#
# Due versioni nuove, in train-powertrain/dati_rete/tratte_rete_rinf/:
#   profilo_rinf  progressiva e quota dai punti di altimetria.csv (inizi delle livellette RINF, quota a piena precisione), stazioni e
#                 limiti identici alla versione dalla mappa (archivio/tratte_rete_20261110): cambia solo il profilo;
#   tutto_rinf    anche le fermate (fermate.csv) e i limiti (velocita_tratti.csv) dal Drive condiviso. Le soste di fermate.csv
#                 (60–600 s) non si possono dare al simulatore, che usa 120 s per fermata e 300 s al capolinea come per le altre.
# Simula la griglia fitta (9702 progetti) come fase12/09 e confronta con le versioni di fase12/09 (originale, 100 m, 200 m), che
# legge dai registri già scritti in ml_treno_dati/fase12/ottimo_lisciatura/<linea>.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const LINEA = length(ARGS) >= 1 ? ARGS[1] : "Trapani-Alcamo_Diramazione"
const REGIONE = length(ARGS) >= 2 ? ARGS[2] : "Sicilia"
const OUT = open(joinpath(LOG, "10_profilo_rinf_$(LINEA).txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/10_profilo_rinf.jl  ", now(), "  TrainPowertrain ", TP.commit_codice(), "  linea ", LINEA)
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_HTML = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")
const DRIVE = expanduser("~/Library/CloudStorage/GoogleDrive-emanuele.dalessio@uniroma1.it/Drive condivisi/SurrogateTrains/Linee Ferroviarie/01 - Italia/Linee")
const SRC = joinpath(DRIVE, REGIONE, LINEA)
const DIR_RINF = joinpath(TPR, "dati_rete", "tratte_rete_rinf")
const SIM09 = joinpath(BASE, "fase12", "ottimo_lisciatura", LINEA)

# ── le due versioni dai dati sorgente ────────────────────────────────────────────
function csv(f)
    l = readlines(f); h = split(l[1], ',')
    return [Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r))]
end
nonc(f) = [l for l in readlines(f) if !startswith(lstrip(l), '%') && !isempty(strip(l))]
alt = csv(joinpath(SRC, "altimetria.csv"))
s_m = [1000parse(Float64, r["s_km"]) for r in alt]; q = [parse(Float64, r["quota_m"]) for r in alt]
issorted(s_m) || error("altimetria.csv non ordinata")
L_html = parse(Float64, only(nonc(joinpath(DIR_HTML, LINEA, "$(LINEA)_progressiva.txt"))[end:end]))
abs(s_m[end] - L_html) < 1 || error(@sprintf("lunghezze diverse: RINF %.1f m, mappa %.1f m", s_m[end], L_html))
intest = "% $(LINEA): dal Drive condiviso SurrogateTrains (Linee/$(REGIONE)/$(LINEA)), ml_treno/fase12/10_profilo_rinf.jl, " * Dates.format(now(), "yyyy-mm-dd")
function scrivi(sotto, stazioni, limiti)
    d = joinpath(DIR_RINF, sotto, LINEA); mkpath(d)
    open(io -> (println(io, intest); foreach(x -> println(io, repr(x)), s_m)), joinpath(d, "$(LINEA)_progressiva.txt"), "w")
    open(io -> (println(io, intest * " (quota delle livellette RINF, altimetria.csv)"); foreach(x -> println(io, repr(x)), q)), joinpath(d, "$(LINEA)_altimetria.txt"), "w")
    open(io -> (println(io, intest); foreach(x -> println(io, x), stazioni)), joinpath(d, "$(LINEA)_stazioni.txt"), "w")
    open(io -> (println(io, intest); foreach(x -> println(io, x), limiti)), joinpath(d, "$(LINEA)_limiti.txt"), "w")
end
st_html = nonc(joinpath(DIR_HTML, LINEA, "$(LINEA)_stazioni.txt")); lim_html = nonc(joinpath(DIR_HTML, LINEA, "$(LINEA)_limiti.txt"))
scrivi("profilo_rinf", st_html, lim_html)
fer = csv(joinpath(SRC, "fermate.csv")); vel = csv(joinpath(SRC, "velocita_tratti.csv"))
st_rinf = [string(round(Int, 1000parse(Float64, r["s_km"]))) for r in fer]
lim_rinf = [@sprintf("%d %d %s", round(Int, 1000parse(Float64, r["s_inizio_km"])), round(Int, 1000parse(Float64, r["s_fine_km"])), r["vmax_kmh"]) for r in vel]
scrivi("tutto_rinf", st_rinf, lim_rinf)
isfile(joinpath(DIR_RINF, "README.md")) || open(joinpath(DIR_RINF, "README.md"), "w") do io
    println(io, "# Linee della rete costruite dai dati sorgente RINF\n")
    println(io, "Dal Drive condiviso SurrogateTrains (`Linee Ferroviarie/01 - Italia/Linee/<regione>/<linea>`), con `ml_treno/fase12/10_profilo_rinf.jl`.")
    println(io, "- `profilo_rinf`: quota dalle livellette RINF (`altimetria.csv`, a piena precisione); stazioni e limiti identici a `../archivio/tratte_rete_20261110`.")
    println(io, "- `tutto_rinf`: anche fermate (`fermate.csv`) e limiti (`velocita_tratti.csv`) dal Drive. Le soste per fermata non sono rappresentabili nel formato a 4 file.")
end
say(@sprintf("scritte %s/{profilo_rinf,tutto_rinf}/%s: %d punti (livellette), %d stazioni RINF contro %d della mappa", DIR_RINF, LINEA,
             length(s_m), length(st_rinf), length(st_html)))

# ── simulazione e confronto ──────────────────────────────────────────────────────
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]); const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
media_blocchi(p, w) = [mean(@view p[(k-1)*w+1:k*w]) for k in 1:length(p)÷w]; tv(p) = sum(abs, diff(p))
function carica(nv, cart, dir)
    tc = leggi_tratte_reali([LINEA]; cartella = cart)
    if !isfile(joinpath(dir, "registro.csv")) || countlines(joinpath(dir, "registro.csv")) < length(GRIGLIA) + 1
        t0 = time()
        spec = CampagnaSpec(tratte = tc, coppie = GRIGLIA, cartella = dir, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                            peso_a_carico = 195_000.0, modalita = :griglia)
        redirect_stdout(devnull) do; esegui_campagna(spec); end
        say(@sprintf("%-14s griglia fitta simulata in %.1f min", nv, (time() - t0) / 60))
    end
    strip(read(joinpath(dir, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $dir")
    casi = Dict{Tuple{Float64,Float64},Dict{String,String}}()
    for l in readlines(joinpath(dir, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ','))); casi[(pf(c["m"]), pf(c["n"]))] = c
    end
    length(casi) == length(GRIGLIA) || error("$nv: $(length(casi)) casi")
    pr = profilo_tratta(only(tc).cp)
    return (nome = nv, casi = casi, tv1 = tv(pr.p) / pr.L, tv100 = tv(media_blocchi(pr.p, 100)) / pr.L, tv1k = tv(media_blocchi(pr.p, 1000)) / pr.L,
            disl = maximum(pr.h) - minimum(pr.h), fermate = length(pr.fermate))
end
ris = [carica("mappa", DIR_HTML, joinpath(SIM09, "originale")),
       carica("mappa 100 m", joinpath(TPR, "dati_rete", "tratte_rete_attenuate", "media_100m"), joinpath(SIM09, "100m")),
       carica("mappa 200 m", joinpath(TPR, "dati_rete", "tratte_rete_attenuate", "media_200m"), joinpath(SIM09, "200m")),
       carica("profilo RINF", joinpath(DIR_RINF, "profilo_rinf"), joinpath(BASE, "fase12", "profilo_rinf", LINEA, "profilo_rinf")),
       carica("tutto RINF", joinpath(DIR_RINF, "tutto_rinf"), joinpath(BASE, "fase12", "profilo_rinf", LINEA, "tutto_rinf"))]

fatt(c) = c["tipo_esito"] == "fattibile"; costo(c) = pf(c["total_cost_EUR_km"])
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
ottimo(casi; filtro = _ -> true) = (k = [g for g in GRIGLIA if fatt(casi[g]) && filtro(g)]; isempty(k) ? nothing : k[argmin([costo(casi[g]) for g in k])])
col(f) = join((@sprintf("%15s", f(r)) for r in ris), "")
ott = [ottimo(r.casi) for r in ris]
say("\n", @sprintf("%-40s", ""), join((@sprintf("%15s", r.nome) for r in ris), ""))
say("IL PROFILO")
say(@sprintf("%-40s", "  Σ|Δp| per km, a 1 m [‰/km]"), col(r -> @sprintf("%.2f", r.tv1)))
say(@sprintf("%-40s", "  Σ|Δp| per km, media su 100 m"), col(r -> @sprintf("%.2f", r.tv100)))
say(@sprintf("%-40s", "  Σ|Δp| per km, media su 1 km"), col(r -> @sprintf("%.2f", r.tv1k)))
say(@sprintf("%-40s", "  dislivello [m]"), col(r -> @sprintf("%.1f", r.disl)))
say(@sprintf("%-40s", "  fermate intermedie"), col(r -> string(r.fermate)))
say("L'OTTIMO VERO (griglia fitta simulata)")
say(@sprintf("%-40s", "  progetti fattibili"), col(r -> string(count(g -> fatt(r.casi[g]), GRIGLIA))))
say(@sprintf("%-40s", "  m, n"), join((@sprintf("%15s", @sprintf("%.2f, %.2f", g...)) for g in ott), ""))
say(@sprintf("%-40s", "  regime"), join((@sprintf("%15s", regime(g[1])) for g in ott), ""))
say(@sprintf("%-40s", "  fuel cell [kW] / batteria [kWh]"), join((@sprintf("%15s", (t = taglie(g...); @sprintf("%.0f / %.0f", t.P_nom, t.C_batt))) for g in ott), ""))
say(@sprintf("%-40s", "  costo [€/km]"), join((@sprintf("%15.4f", costo(r.casi[g])) for (r, g) in zip(ris, ott)), ""))
say(@sprintf("%-40s", "  rispetto alla mappa"), join((@sprintf("%14.2f%%", 100(costo(r.casi[g]) / costo(ris[1].casi[ott[1]]) - 1)) for (r, g) in zip(ris, ott)), ""))
for (k, nm) in (("H2_cons_kg", "idrogeno [kg/viaggio]"), ("SOC_end", "SOC finale"), ("vita_FC_f1_ore", "vita FC f1 [h]"), ("num_repl_FC", "sostituzioni FC"),
                ("cost_repl_FC_EUR_km_att", "sostituzioni FC [€/km]"), ("num_repl_batt", "sostituzioni batteria"), ("durata_viaggio_s", "durata A/R [s]"))
    say(@sprintf("%-40s", "  " * nm), join((@sprintf("%15.4g", pf(r.casi[g][k])) for (r, g) in zip(ris, ott)), ""))
end
say("IL MIGLIORE PER REGIME [€/km] (m, n)")
for (nm, f) in (("sola batteria", g -> g[1] == 0), ("ibrido FC piccola", g -> 0 < g[1] < 0.1), ("ibrido (m ≥ 0,1)", g -> g[1] >= 0.1))
    say(@sprintf("%-40s", "  " * nm), join((let g = ottimo(r.casi; filtro = f)
        @sprintf("%15s", g === nothing ? "—" : @sprintf("%.3f (%.2f,%.2f)", costo(r.casi[g]), g...)) end for r in ris), ""))
end
g0 = ott[1]
say(@sprintf("LO STESSO TRENO (ottimo della mappa: m %.2f, n %.2f) IN OGNI VERSIONE", g0...))
say(@sprintf("%-40s", "  costo [€/km]"), col(r -> @sprintf("%.4f", costo(r.casi[g0]))))
say(@sprintf("%-40s", "  esito"), col(r -> r.casi[g0]["tipo_esito"]))
say(@sprintf("%-40s", "  SOC finale"), col(r -> @sprintf("%.4f", pf(r.casi[g0]["SOC_end"]))))
for (k, nm) in (("dV_accensioni_uV", "accensioni [µV/h]"), ("dV_idling_uV", "minimo [µV/h]"), ("dV_cicli_carico_uV", "cicli di carico [µV/h]"),
                ("dV_alto_carico_uV", "alto carico [µV/h]"))
    say(@sprintf("%-40s", "  " * nm), col(r -> @sprintf("%.2f", pf(r.casi[g0][k]) / (pf(r.casi[g0]["durata_viaggio_s"]) / 3600))))
end
say(@sprintf("\nTempo %.1f min", (time() - T0) / 60))
close(OUT)
