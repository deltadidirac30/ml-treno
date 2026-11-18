# fase13/08_ottimo_vero.jl: fase12/15 (passo 2, il confronto) rifatto con i dati del 17/11: l'ottimo vero dalla griglia fitta di
# fase13/02 contro la migliore delle 288 coppie e le proposte del surrogato: strategia semplice (A) e C (fase13/06), G senza il bordo
# (fase13/07) e G con il bordo (il comando `surrogato`, il default, riepilogo del 17/11 sera). Nessuna simulazione nuova.
#
#   julia --project=fase13 fase13/08_ottimo_vero.jl > ~/Documents/lavoro/ml_treno_dati/fase13_log/log_08.txt 2>&1

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
using Plots
gr()
const LOG = joinpath(BASE, "fase13_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "08_ottimo_vero.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase13/08_ottimo_vero.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_TR = joinpath(TPR, "dati_rete", "tratte_rete_rinf", "tutto_rinf")
const SIM = joinpath(BASE, "fase13", "griglia_rinf")
const RIEP_G = joinpath(BASE, "surrogato", "riepilogo_20261117_230954.csv")   # G + bordo, dati 17/11
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA)
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))

# le linee non elettrificate oltre il 70%
dividi(r) = (out = String[]; buf = IOBuffer(); dentro = false;
             for ch in r; ch == '"' ? (dentro = !dentro) : (ch == ',' && !dentro) ? push!(out, String(take!(buf))) : print(buf, ch); end;
             push!(out, String(take!(buf))); out)
rie = let l = readlines(joinpath(BASE, "linee_rinf_sorgente", "riepilogo.csv")), h = dividi(l[1])
    Dict(replace(d["tronco"], '+' => '_') => d for d in (Dict(h[j] => x for (j, x) in enumerate(dividi(r))) for r in l[2:end] if !isempty(strip(r))))
end
quota_ne(l) = parse(Float64, rie[l]["km_non_elettrificati"]) / parse(Float64, rie[l]["lunghezza_km"])
nomi = sort([d for d in readdir(DIR_TR) if isdir(joinpath(DIR_TR, d)) && quota_ne(d) > 0.7])
say(@sprintf("linee: %d", length(nomi)))

# ── 2. confronto ─────────────────────────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
const J_M = findfirst(==("m"), INTEST); const J_N = findfirst(==("n"), INTEST); const J_ES = findfirst(==("tipo_esito"), INTEST)
const J_C = findfirst(==("total_cost_EUR_km"), INTEST); const J_T = findfirst(==("tempo_s"), INTEST)
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
function leggi_griglia(dir)
    d = Dict{Tuple{Float64,Float64},Tuple{Bool,Float64}}(); tcpu = 0.0
    for l in Iterators.drop(eachline(joinpath(dir, "registro.csv")), 1)
        c = split(l, ',')
        d[(pf(c[J_M]), pf(c[J_N]))] = (c[J_ES] == "fattibile", pf(c[J_C])); tcpu += pf(c[J_T])
    end
    return d, tcpu
end
function leggi_csv(f)
    l = readlines(f); h = split(l[1], ',')
    return Dict(String(split(r, ',')[1]) => Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r)))
end
s12 = leggi_csv(joinpath(LOG, "06_riassunto_non_el_linee.csv")); s13 = leggi_csv(joinpath(LOG, "07_verifica_locale_linee.csv"))
sG = leggi_csv(RIEP_G)
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
const REGIMI = ("sola batteria", "ibrido FC piccola", "ibrido")
pr2(x) = round(parse(Float64, x); digits = 2)
R = NamedTuple[]
scarto_max = 0.0
for l in nomi
    global scarto_max
    g, tcpu = leggi_griglia(joinpath(SIM, l))
    f = [k for k in GRIGLIA if g[k][1]]
    c = [g[k][2] for k in f]; o = sortperm(c); opt = f[o[1]]; copt = c[o[1]]
    entro(p) = count(x -> x <= copt * (1 + p / 100), c)
    # le proposte
    prop = Dict{Symbol,Tuple{Float64,Float64}}()
    prop[:C] = (pr2(s13[l]["C_m"]), pr2(s13[l]["C_n"])); prop[:G] = (pr2(s13[l]["G_m"]), pr2(s13[l]["G_n"])); prop[:Gb] = (pr2(sG[l]["m"]), pr2(sG[l]["n"]))
    # A (strategia semplice): costo da fase13/06 (le coordinate non sono salvate)
    cA = parse(Float64, s12[l]["migliore288_costo"]) * (1 + parse(Float64, s12[l]["A_rispetto_288"]) / 100)
    c288 = parse(Float64, s12[l]["migliore288_costo"])
    for v in (:C, :G)
        x = g[prop[v]]; x[1] || error("$l: la proposta $v $(prop[v]) non è fattibile nella griglia")
        scarto_max = max(scarto_max, abs(x[2] / parse(Float64, s13[l]["$(v)_costo"]) - 1))
    end
    let x = g[prop[:Gb]]; x[1] || error("$l: la proposta G + bordo non è fattibile nella griglia")
        scarto_max = max(scarto_max, abs(x[2] / parse(Float64, sG[l]["costo_simulatore_EUR_km"]) - 1)); end
    pos(p) = findfirst(==(p), f[o])
    push!(R, (linea = l, L = parse(Float64, rie[l]["lunghezza_km"]), opt = opt, copt = copt, nfatt = length(f), tcpu = tcpu,
              entro01 = entro(0.1), entro05 = entro(0.5), entro1 = entro(1.0),
              gap = Dict(:A => 100(cA / copt - 1), :C => 100(g[prop[:C]][2] / copt - 1), :G => 100(g[prop[:G]][2] / copt - 1), :Gb => 100(g[prop[:Gb]][2] / copt - 1), :b288 => 100(c288 / copt - 1)),
              prop = prop, posG = pos(prop[:Gb]), regG = regime(prop[:Gb][1]), regO = regime(opt[1])))
end
say(@sprintf("\n2. controllo: costo delle proposte C, G e G + bordo riletto dalla griglia contro quello delle verifiche, scarto massimo %.1e (deve essere ~0)", scarto_max))
N = length(R)
const STR = [(:b288, "migliore delle 288"), (:A, "surrogato semplice"), (:C, "surrogato C"), (:G, "G senza bordo"), (:Gb, "G + bordo")]
say("\nIL COSTO RISPETTO ALL'OTTIMO VERO (griglia fitta simulata), ", N, " linee")
say(@sprintf("%-34s", ""), join((@sprintf("%20s", x[2]) for x in STR), ""))
col(f) = join((@sprintf("%20s", f([r.gap[v] for r in R])) for (v, _) in STR), "")
say(@sprintf("%-34s", "  media"), col(x -> @sprintf("%+.3f%%", mean(x))))
say(@sprintf("%-34s", "  mediana"), col(x -> @sprintf("%+.3f%%", median(x))))
say(@sprintf("%-34s", "  90° percentile"), col(x -> @sprintf("%+.3f%%", quantile(x, 0.9))))
say(@sprintf("%-34s", "  massimo"), col(x -> @sprintf("%+.3f%%", maximum(x))))
say(@sprintf("%-34s", "  esattamente l'ottimo"), col(x -> string(count(<(1e-9), x))))
say(@sprintf("%-34s", "  entro 0,1%"), col(x -> string(count(<=(0.1), x))))
say(@sprintf("%-34s", "  entro 0,5%"), col(x -> string(count(<=(0.5), x))))
say(@sprintf("%-34s", "  entro 1%"), col(x -> string(count(<=(1), x))))
say(@sprintf("%-34s", "  oltre 2%"), col(x -> string(count(>(2), x))))
say(@sprintf("%-34s", "  oltre 5%"), col(x -> string(count(>(5), x))))
say("\nIL REGIME: ottimo vero (righe) contro surrogato G + bordo (colonne)")
for a in REGIMI
    s = [r for r in R if r.regO == a]
    say(@sprintf("  %-20s %3d → %s", a, length(s), join((@sprintf("%s %d", b, count(r -> r.regG == b, s)) for b in REGIMI), ", ")))
end
say(@sprintf("  stesso regime: %d su %d", count(r -> r.regO == r.regG, R), N))
dm = [abs(r.prop[:Gb][1] - r.opt[1]) for r in R]; dn = [abs(r.prop[:Gb][2] - r.opt[2]) for r in R]
say(@sprintf("  distanza della proposta G + bordo dall'ottimo: m mediana %.2f (max %.2f), n mediana %.2f (max %.2f); stesso punto in %d linee",
             median(dm), maximum(dm), median(dn), maximum(dn), count(r -> r.prop[:Gb] == r.opt, R)))
say(@sprintf("  posizione della proposta G + bordo nella classifica dei progetti fattibili: mediana %d°, 90° percentile %d°, peggiore %d°",
             round(Int, median(r.posG for r in R)), round(Int, quantile([r.posG for r in R], 0.9)), maximum(r.posG for r in R)))
say("\nQUANTO È PIATTO IL COSTO VICINO ALL'OTTIMO (progetti fattibili entro lo 0,1 / 0,5 / 1% dall'ottimo, mediana sulle linee)")
say(@sprintf("  %d / %d / %d progetti su %d fattibili (mediana)", round(Int, median(r.entro01 for r in R)), round(Int, median(r.entro05 for r in R)),
             round(Int, median(r.entro1 for r in R)), round(Int, median(r.nfatt for r in R))))
say("\nLE LINEE CON IL SURROGATO G + BORDO OLTRE LO 0,5% DALL'OTTIMO")
for r in sort(R; by = r -> -r.gap[:Gb])
    r.gap[:Gb] > 0.5 || break
    say(@sprintf("  %-38s L %6.1f km: ottimo (%.2f, %.2f) %.4f €/km %-18s | G+bordo (%.2f, %.2f) %+.2f%% %-18s | 288 %+.2f%%, semplice %+.2f%%", r.linea, r.L,
                 r.opt..., r.copt, r.regO, r.prop[:Gb]..., r.gap[:Gb], r.regG, r.gap[:b288], r.gap[:A]))
end
tc = [r.tcpu for r in R]
say("\nI TEMPI")
say(@sprintf("  griglia fitta simulata: %.1f h di calcolo sommando i singoli progetti (8 in parallelo); di orologio 57,5 min per le 146 linee (fase13/02), %.1f s per linea",
             sum(tc) / 3600, 57.5 * 60 / N))

open(joinpath(LOG, "08_ottimo_vero_linee.csv"), "w") do io
    println(io, "linea,L_km,ottimo_m,ottimo_n,ottimo_costo,ottimo_regime,fattibili,entro_0.5pct,G_m,G_n,G_regime,G_vs_ottimo_pct,Gbordo_posizione,",
            "C_vs_ottimo_pct,semplice_vs_ottimo_pct,migliore288_vs_ottimo_pct,t_griglia_cpu_s,Gbordo_m,Gbordo_n,Gbordo_vs_ottimo_pct")
    for r in R
        println(io, join((r.linea, r.L, r.opt..., @sprintf("%.6g", r.copt), r.regO, r.nfatt, r.entro05, r.prop[:G]..., regime(r.prop[:G][1]), @sprintf("%.4f", r.gap[:G]), r.posG,
                          @sprintf("%.4f", r.gap[:C]), @sprintf("%.4f", r.gap[:A]), @sprintf("%.4f", r.gap[:b288]), @sprintf("%.1f", r.tcpu),
                          r.prop[:Gb]..., @sprintf("%.4f", r.gap[:Gb])), ','))
    end
end
# figura: distribuzione dello scarto dall'ottimo
plt = plot(size = (1000, 520), dpi = 120, left_margin = 8Plots.mm, bottom_margin = 6Plots.mm, xlabel = "costo rispetto all'ottimo vero [%]",
           ylabel = "linee (cumulato)", title = "$(N) linee non elettrificate: quanto costa la scelta rispetto all'ottimo del simulatore",
           legend = :bottomright, xlims = (-0.05, 8))
for (v, nm) in STR
    x = sort([r.gap[v] for r in R]); plot!(plt, x, 1:length(x); seriestype = :steppost, lw = 2, label = nm)
end
mkpath(joinpath(@__DIR__, "figure")); savefig(plt, joinpath(@__DIR__, "figure", "fig_ottimo_vero.png"))  # fase13/figure
say(@sprintf("\nTempo totale %.1f min. Tabella: %s; figura: fase13/figure/fig_ottimo_vero.png", (time() - T0) / 60, joinpath(LOG, "08_ottimo_vero_linee.csv")))
close(OUT)
