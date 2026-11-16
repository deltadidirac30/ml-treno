# fase12/09_ottimo_lisciatura.jl: effetto della lisciatura dell'altimetria sull'ottimo del simulatore vero (niente surrogato).
#
#   julia -t 8 --project=fase12 fase12/09_ottimo_lisciatura.jl [linea] > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_09.txt 2>&1
#
# Una linea della rete (default Trapani-Alcamo_Diramazione, la più colpita in fase12/03-04), in 5 versioni: originale
# (archivio/tratte_rete_20261110) e media mobile della quota su 100, 200, 500 m e 1 km (dati_rete/tratte_rete_attenuate,
# media_100m scritta qui con la stessa funzione di fase12/07). Per ognuna il simulatore valuta la griglia fitta intera
# (m = 0, 0,03…0,99; n = 0,01…0,99; 9702 progetti), configurazione della campagna, andata e ritorno, treno da 195 t.
# Confronto: ottimo vero (m, n, regime, costo e voci di costo), le voci di degrado della FC, il miglior progetto per regime,
# e il costo del progetto ottimo dell'originale in ogni versione (stesso treno, solo il profilo cambia).

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
using Plots
gr()
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const LINEA = isempty(ARGS) ? "Trapani-Alcamo_Diramazione" : ARGS[1]
const OUT = open(joinpath(LOG, "09_ottimo_lisciatura_$(LINEA).txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/09_ottimo_lisciatura.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice(), "  linea ", LINEA)
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_ORIG = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")
const DIR_ATT = joinpath(TPR, "dati_rete", "tratte_rete_attenuate")
const SIM = joinpath(BASE, "fase12", "ottimo_lisciatura", LINEA)

# ── media_100m (stessa lisciatura di fase12/07) ─────────────────────────────────
leggi_valori(f) = [parse(Float64, strip(l)) for l in readlines(f) if !isempty(strip(l)) && !startswith(lstrip(l), '%')]
commenti(f) = [l for l in readlines(f) if startswith(lstrip(l), '%')]
function liscia(p, h, W)
    N = length(p); I = zeros(N)
    for i in 2:N; I[i] = I[i-1] + (p[i] - p[i-1]) * (h[i] + h[i-1]) / 2; end
    function integ(x)
        x <= p[1] && return 0.0
        x >= p[N] && return I[N]
        j = searchsortedlast(p, x); t = x - p[j]
        return I[j] + t * h[j] + (h[j+1] - h[j]) / (p[j+1] - p[j]) * t^2 / 2
    end
    return [(w = min(W / 2, p[i] - p[1], p[N] - p[i]); w <= 0 ? h[i] : (integ(p[i] + w) - integ(p[i] - w)) / (2w)) for i in 1:N]
end
if !isdir(joinpath(DIR_ATT, "media_100m"))
    for nome in sort([d for d in readdir(DIR_ORIG) if isdir(joinpath(DIR_ORIG, d))])
        d = joinpath(DIR_ATT, "media_100m", nome); mkpath(d)
        for s in ("progressiva", "stazioni", "limiti"); cp(joinpath(DIR_ORIG, nome, "$(nome)_$s.txt"), joinpath(d, "$(nome)_$s.txt"); force = true); end
        fa = joinpath(DIR_ORIG, nome, "$(nome)_altimetria.txt")
        hl = liscia(leggi_valori(joinpath(DIR_ORIG, nome, "$(nome)_progressiva.txt")), leggi_valori(fa), 100.0)
        open(joinpath(d, "$(nome)_altimetria.txt"), "w") do io
            for c in commenti(fa); println(io, c); end
            println(io, @sprintf("%% lisciata: media mobile della quota su 100 m (ml_treno/fase12/09_ottimo_lisciatura.jl, %s)", Dates.format(now(), "yyyy-mm-dd")))
            for x in hl; println(io, repr(x)); end
        end
    end
    open(joinpath(DIR_ATT, "README.md"), "a") do io
        println(io, "- `media_100m`: come le altre, finestra di 100 m (aggiunta da `ml_treno/fase12/09_ottimo_lisciatura.jl`).")
    end
    say("media_100m scritta per tutte le linee")
end

# ── simulazione della griglia fitta ──────────────────────────────────────────────
const VARIANTI = [("originale", DIR_ORIG), ("100 m", joinpath(DIR_ATT, "media_100m")), ("200 m", joinpath(DIR_ATT, "media_200m")),
                  ("500 m", joinpath(DIR_ATT, "media_500m")), ("1 km", joinpath(DIR_ATT, "media_1km"))]
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]); const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
const VOCI_COSTO = ["CAPEX_FC_EUR_km", "CAPEX_batt_EUR_km", "CAPEX_tank_EUR_km", "OPEX_H2_rech_EUR_km_att", "OPEX_batt_rech_EUR_km_att",
                    "OPEX_mant_FC_EUR_km_att", "OPEX_mant_batt_EUR_km_att", "OPEX_mant_tank_EUR_km_att", "cost_repl_FC_EUR_km_att",
                    "cost_repl_batt_EUR_km_att"]
media_blocchi(p, w) = [mean(@view p[(k-1)*w+1:k*w]) for k in 1:length(p)÷w]; tv(p) = sum(abs, diff(p))

ris = NamedTuple[]
for (nv, cart) in VARIANTI
    t0 = time()
    tc = leggi_tratte_reali([LINEA]; cartella = cart)
    dir = joinpath(SIM, replace(nv, " " => ""))
    spec = CampagnaSpec(tratte = tc, coppie = GRIGLIA, cartella = dir, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(dir, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $dir")
    casi = Dict{Tuple{Float64,Float64},Dict{String,String}}()
    for l in readlines(joinpath(dir, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        casi[(pf(c["m"]), pf(c["n"]))] = c
    end
    length(casi) == length(GRIGLIA) || error("$nv: $(length(casi)) casi invece di $(length(GRIGLIA))")
    pr = profilo_tratta(only(tc).cp)
    push!(ris, (nome = nv, casi = casi, tv1 = tv(pr.p) / pr.L, tv100 = tv(media_blocchi(pr.p, 100)) / pr.L, tv1k = tv(media_blocchi(pr.p, 1000)) / pr.L,
                disl = maximum(pr.h) - minimum(pr.h), pmax = maximum(abs, media_blocchi(pr.p, 100))))
    say(@sprintf("%-10s griglia fitta (%d progetti) simulata in %.1f min", nv, length(GRIGLIA), (time() - t0) / 60))
end

fatt(c) = c["tipo_esito"] == "fattibile"
costo(c) = pf(c["total_cost_EUR_km"])
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
function ottimo(casi; filtro = _ -> true)
    k = [g for g in GRIGLIA if fatt(casi[g]) && filtro(g)]
    isempty(k) && return nothing
    return k[argmin([costo(casi[g]) for g in k])]
end
col(f) = join((@sprintf("%14s", f(r)) for r in ris), "")
say("\n", @sprintf("%-44s", ""), join((@sprintf("%14s", r.nome) for r in ris), ""))
say("IL PROFILO")
say(@sprintf("%-44s", "  Σ|Δp| per km, a 1 m [‰/km]"), col(r -> @sprintf("%.2f", r.tv1)))
say(@sprintf("%-44s", "  Σ|Δp| per km, media su 100 m"), col(r -> @sprintf("%.2f", r.tv100)))
say(@sprintf("%-44s", "  Σ|Δp| per km, media su 1 km"), col(r -> @sprintf("%.2f", r.tv1k)))
say(@sprintf("%-44s", "  pendenza massima su 100 m [‰]"), col(r -> @sprintf("%.1f", r.pmax)))
say(@sprintf("%-44s", "  dislivello [m]"), col(r -> @sprintf("%.1f", r.disl)))
say("L'OTTIMO VERO (griglia fitta simulata)")
ott = [ottimo(r.casi) for r in ris]
say(@sprintf("%-44s", "  progetti fattibili"), col(r -> string(count(g -> fatt(r.casi[g]), GRIGLIA))))
say(@sprintf("%-44s", "  m, n"), join((@sprintf("%14s", @sprintf("%.2f, %.2f", g...)) for g in ott), ""))
say(@sprintf("%-44s", "  regime"), join((@sprintf("%14s", regime(g[1])) for g in ott), ""))
tg = [taglie(g...) for g in ott]
say(@sprintf("%-44s", "  fuel cell [kW] / batteria [kWh]"), join((@sprintf("%14s", @sprintf("%.0f / %.0f", t.P_nom, t.C_batt)) for t in tg), ""))
say(@sprintf("%-44s", "  costo [€/km]"), join((@sprintf("%14.4f", costo(r.casi[g])) for (r, g) in zip(ris, ott)), ""))
say(@sprintf("%-44s", "  rispetto all'originale"), join((@sprintf("%13.2f%%", 100(costo(r.casi[g]) / costo(ris[1].casi[ott[1]]) - 1)) for (r, g) in zip(ris, ott)), ""))
say("  voci di costo dell'ottimo [€/km]:")
for v in VOCI_COSTO
    say(@sprintf("%-44s", "    " * v), join((@sprintf("%14.4f", pf(r.casi[g][v])) for (r, g) in zip(ris, ott)), ""))
end
for (k, nm) in (("H2_cons_kg", "idrogeno [kg/viaggio]"), ("SOC_end", "SOC finale"), ("vita_FC_f1_ore", "vita FC f1 [h]"),
                ("vita_FC_anni", "vita FC [anni]"), ("num_repl_FC", "sostituzioni FC"), ("vita_batt_anni", "vita batteria [anni]"),
                ("num_repl_batt", "sostituzioni batteria"), ("durata_viaggio_s", "durata A/R [s]"))
    say(@sprintf("%-44s", "  " * nm), join((@sprintf("%14.4g", pf(r.casi[g][k])) for (r, g) in zip(ris, ott)), ""))
end
say("IL MIGLIORE PER REGIME [€/km] (m, n)")
for (nm, f) in (("sola batteria", g -> g[1] == 0), ("ibrido FC piccola (m < 0,1)", g -> 0 < g[1] < 0.1), ("ibrido (m ≥ 0,1)", g -> g[1] >= 0.1))
    say(@sprintf("%-44s", "  " * nm), join((let g = ottimo(r.casi; filtro = f)
        g === nothing ? @sprintf("%14s", "—") : @sprintf("%14s", @sprintf("%.3f (%.2f,%.2f)", costo(r.casi[g]), g...)) end for r in ris), ""))
end
say("LO STESSO TRENO (l'ottimo dell'originale) IN OGNI VERSIONE")
g0 = ott[1]
say(@sprintf("%-44s", @sprintf("  m %.2f, n %.2f: costo [€/km]", g0...)), col(r -> @sprintf("%.4f", costo(r.casi[g0]))))
say(@sprintf("%-44s", "  esito"), col(r -> r.casi[g0]["tipo_esito"]))
for (k, nm) in (("vita_FC_f1_ore", "vita FC f1 [h]"), ("num_repl_FC", "sostituzioni FC"), ("cost_repl_FC_EUR_km_att", "sostituzioni FC [€/km]"),
                ("H2_cons_kg", "idrogeno [kg/viaggio]"), ("SOC_end", "SOC finale"))
    say(@sprintf("%-44s", "  " * nm), col(r -> @sprintf("%.4g", pf(r.casi[g0][k]))))
end
say("  voci di degrado della FC [µV per ora di viaggio]:")
for (k, nm) in (("dV_accensioni_uV", "accensioni"), ("dV_idling_uV", "minimo"), ("dV_cicli_carico_uV", "cicli di carico"), ("dV_alto_carico_uV", "alto carico"))
    say(@sprintf("%-44s", "    " * nm), col(r -> @sprintf("%.2f", pf(r.casi[g0][k]) / (pf(r.casi[g0]["durata_viaggio_s"]) / 3600))))
end
# quanto cambia la classifica: posizione dell'ottimo di ogni versione nella classifica dell'originale
say("LA CLASSIFICA")
for (r, g) in zip(ris, ott)
    c0 = ris[1].casi
    f0 = [h for h in GRIGLIA if fatt(c0[h])]; ord = sortperm([costo(c0[h]) for h in f0])
    pos = findfirst(==(g), f0[ord])
    say(@sprintf("  ottimo di %-10s: nell'originale è %s, costa %s", r.nome, pos === nothing ? "NON fattibile" : "il $(pos)°",
                 fatt(c0[g]) ? @sprintf("%+.2f%% rispetto all'ottimo dell'originale", 100(costo(c0[g]) / costo(c0[ott[1]]) - 1)) : c0[g]["tipo_esito"]))
end

# ── figura: il costo migliore per ogni m (inviluppo su n), per versione ───────────
plt = plot(size = (1100, 500), dpi = 120, left_margin = 10Plots.mm, bottom_margin = 6Plots.mm, xlabel = "m", ylabel = "costo minimo su n [€/km]",
           title = "$(LINEA): ottimo del simulatore vero, profilo originale e lisciato", legend = :topright)
for r in ris
    y = [let k = [g for g in GRIGLIA if g[1] == m && fatt(r.casi[g])]; isempty(k) ? NaN : minimum(costo(r.casi[g]) for g in k) end for m in MS]
    plot!(plt, MS, y; label = r.nome, lw = 2)
end
mkpath(joinpath(@__DIR__, "figure"))
savefig(plt, joinpath(@__DIR__, "figure", "fig_ottimo_lisciatura_$(LINEA).png"))
say(@sprintf("\nTempo %.1f min. Figura: fase12/figure/fig_ottimo_lisciatura_%s.png", (time() - T0) / 60, LINEA))
close(OUT)
