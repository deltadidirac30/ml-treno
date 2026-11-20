# fase16/03_confronto.jl: la strategia G (e la semplice, e la migliore delle 288 coppie) contro l'ottimo vero della griglia fitta
# simulata, sulle 256 tratte del test DoE; le stesse metriche di fase13/08_ottimo_vero.jl, accanto a quelle delle 146 linee reali.
# Nessuna simulazione nuova.
#
#   julia --project=fase16 fase16/03_confronto.jl > ~/Documents/lavoro/ml_treno_dati/fase16_log/log_03.txt 2>&1   (da lancia.sh)
#
# Ingressi: fase16/griglia (02_griglia.jl), fase16/riepilogo_G.csv e riepilogo_semplice.csv (il surrogato, lancia.sh), la migliore
# delle 288 coppie dalla campagna (tratte_riassunto.arrow); per le linee: fase13_log/08_ottimo_vero_linee.csv,
# 06_riassunto_non_el_linee.csv, surrogato/riepilogo_20261117_230954.csv (G + bordo, dati del 17/11), fase13_log/log_03_surrogato.txt.
# Scrive in fase16_log: 03_confronto.txt, 03_ottimo_tratte.csv, fig_ottimo_test.png.

using TrainPowertrain, Arrow, Statistics, Printf, Dates, Plots
gr()
const TP = TrainPowertrain
const BASE = expanduser("~/Documents/lavoro/ml_treno_dati")
const PROVA = get(ENV, "FASE16_PROVA", "")                 # solo per la prova a secco: legge e scrive tutto in quella cartella
const LOG = isempty(PROVA) ? joinpath(BASE, "fase16_log") : PROVA; const DAT = isempty(PROVA) ? joinpath(BASE, "fase16") : PROVA
const SIM = joinpath(DAT, "griglia")
const OUT = open(joinpath(LOG, "03_confronto.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase16/03_confronto.jl  ", now(), "  TrainPowertrain ", TP.commit_codice())
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA)
const CAMPIONE = parse.(Int, split(read(joinpath(DAT, "tratte.txt"), String), ','))

pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
pr2(s) = round(parse(Float64, s); digits = 2)
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
const REGIMI = ("sola batteria", "ibrido FC piccola", "ibrido")
function leggi_griglia(dir)
    l = eachline(joinpath(dir, "registro.csv")); h = split(first(l), ',')
    jm = findfirst(==("m"), h); jn = findfirst(==("n"), h); je = findfirst(==("tipo_esito"), h); jc = findfirst(==("total_cost_EUR_km"), h)
    jt = findfirst(==("tempo_s"), h)
    d = Dict{Tuple{Float64,Float64},Tuple{Bool,Float64}}(); tcpu = 0.0
    for r in l
        c = split(r, ',')
        d[(round(pf(c[jm]); digits = 2), round(pf(c[jn]); digits = 2))] = (c[je] == "fattibile", pf(c[jc])); tcpu += pf(c[jt])
    end
    return d, tcpu
end
function leggi_csv(f)
    l = readlines(f); h = split(l[1], ',')
    return Dict(String(split(r, ',')[1]) => Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r)))
end
"""Secondi per tratta e di avvio dal log di usa_surrogato.jl."""
function tempi_surrogato(f)
    t = read(f, String)
    a = match(r"\(([0-9.]+) s a tratta", t); b = match(r"\+ ([0-9.]+) s di avvio", t)
    return (tratta = a === nothing ? NaN : parse(Float64, a[1]), avvio = b === nothing ? NaN : parse(Float64, b[1]))
end

# ── le 256 tratte del test ───────────────────────────────────────────────────────
const RIE = Dict(:G => leggi_csv(joinpath(DAT, "riepilogo_G.csv")), :semplice => leggi_csv(joinpath(DAT, "riepilogo_semplice.csv")))
const TEMPI = Dict(:G => tempi_surrogato(joinpath(LOG, "01_surrogato_G.txt")), :semplice => tempi_surrogato(joinpath(LOG, "01_surrogato_semplice.txt")))
const RIA = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "tratte_riassunto.arrow"))
const JR = Dict(Int(r) => j for (j, r) in enumerate(RIA.tratta))
const LT = let tt = Arrow.Table(joinpath(BASE, "P9_D28_16384", "tabella", "test.arrow")); Dict(zip(Int.(tt.tratta), Float64.(tt.x_L_km))) end
const TGRIGLIA = Dict(parse(Int, split(l, ',')[1]) => parse(Float64, split(l, ',')[2]) for l in readlines(joinpath(LOG, "02_tempi.csv")))
say(@sprintf("tratte: %d; proposte nei riepiloghi: G %d, semplice %d", length(CAMPIONE), length(RIE[:G]), length(RIE[:semplice])))

R = NamedTuple[]; senza = Int[]; scarto_max = 0.0; anomalie = String[]
for r in CAMPIONE
    global scarto_max
    id = @sprintf("route_%06d", r)
    g, tcpu = leggi_griglia(joinpath(SIM, id))
    length(g) == NG || error("$id: la griglia ha $(length(g)) progetti")
    f = [k for k in GRIGLIA if g[k][1]]
    isempty(f) && (push!(senza, r); continue)
    c = [g[k][2] for k in f]; o = sortperm(c); opt = f[o[1]]; copt = c[o[1]]
    entro(p) = count(x -> x <= copt * (1 + p / 100), c)
    gap = Dict{Symbol,Float64}(); prop = Dict{Symbol,Tuple{Float64,Float64}}(); nsim = Dict{Symbol,Int}()
    for S in (:G, :semplice)
        x = get(RIE[S], id, nothing)
        nsim[S] = x === nothing ? 0 : parse(Int, x["candidati_verificati"])
        if x === nothing || isempty(x["m"])
            gap[S] = Inf; prop[S] = (NaN, NaN); continue
        end
        p = (pr2(x["m"]), pr2(x["n"])); prop[S] = p; cs = parse(Float64, x["costo_simulatore_EUR_km"])
        y = g[p]
        if y[1]
            scarto_max = max(scarto_max, abs(y[2] / cs - 1)); gap[S] = 100(y[2] / copt - 1)
        else
            push!(anomalie, "$id $S $(p): fattibile per il surrogato, non nella griglia"); gap[S] = 100(cs / copt - 1)
        end
    end
    j = JR[r]
    c288 = RIA.senza_coppie_fattibili[j] ? Inf : Float64(RIA.costo_migliore[j]); m288 = Float64(RIA.m_migliore[j])
    gap[:b288] = 100(c288 / copt - 1)
    posG = isfinite(gap[:G]) ? something(findfirst(==(prop[:G]), f[o]), 0) : 0
    push!(R, (tratta = r, L = LT[r], opt = opt, copt = copt, nfatt = length(f), tcpu = tcpu, tgriglia = get(TGRIGLIA, r, NaN),
              entro01 = entro(0.1), entro05 = entro(0.5), entro1 = entro(1.0), gap = gap, prop = prop, nsim = nsim, m288 = m288,
              posG = posG, regO = regime(opt[1]),
              reg = Dict(:G => isnan(prop[:G][1]) ? "" : regime(prop[:G][1]), :semplice => isnan(prop[:semplice][1]) ? "" : regime(prop[:semplice][1]),
                         :b288 => isfinite(c288) ? regime(m288) : "")))
end
say(@sprintf("tratte senza alcun progetto fattibile nella griglia (escluse): %d %s", length(senza), isempty(senza) ? "" : string(senza)))
say(@sprintf("controllo: costo delle proposte riletto dalla griglia contro quello del surrogato, scarto massimo %.1e (deve essere ~0); anomalie %d",
             scarto_max, length(anomalie)))
for a in anomalie; say("  ", a); end
N = length(R)

# ── le 146 linee reali (fase 13) ─────────────────────────────────────────────────
const F13 = joinpath(BASE, "fase13_log")
lin = leggi_csv(joinpath(F13, "08_ottimo_vero_linee.csv")); l06 = leggi_csv(joinpath(F13, "06_riassunto_non_el_linee.csv"))
lG = leggi_csv(joinpath(BASE, "surrogato", "riepilogo_20261117_230954.csv"))
const TLIN = tempi_surrogato(joinpath(F13, "log_03_surrogato.txt"))
RL = [(gap = Dict(:b288 => parse(Float64, x["migliore288_vs_ottimo_pct"]), :semplice => parse(Float64, x["semplice_vs_ottimo_pct"]),
                  :G => parse(Float64, x["Gbordo_vs_ottimo_pct"])),
       regO = x["ottimo_regime"], reg = Dict(:G => regime(parse(Float64, x["Gbordo_m"])), :b288 => regime(parse(Float64, l06[l]["migliore288_m"])), :semplice => ""),
       nsim = Dict(:G => parse(Int, lG[l]["candidati_verificati"]))) for (l, x) in lin]
NL = length(RL)

# ── la tabella ───────────────────────────────────────────────────────────────────
const STR = [(:b288, "migliore 288"), (:semplice, "semplice"), (:G, "G + bordo")]
fin(v) = filter(isfinite, v)
pct(x) = @sprintf("%+.3f%%", x)
function righe_tabella(RR, nn, sims, tempo)
    out = Vector{Vector{String}}()
    g(v) = [r.gap[v] for r in RR]
    push!(out, [pct(mean(fin(g(v)))) for (v, _) in STR]); push!(out, [pct(median(fin(g(v)))) for (v, _) in STR])
    push!(out, [pct(quantile(fin(g(v)), 0.9)) for (v, _) in STR]); push!(out, [pct(maximum(fin(g(v)))) for (v, _) in STR])
    push!(out, [string(count(<(1e-9), g(v))) for (v, _) in STR])
    for p in (0.1, 0.5, 1.0); push!(out, [string(count(<=(p), g(v))) for (v, _) in STR]); end
    for p in (2.0, 5.0); push!(out, [string(count(x -> isfinite(x) && x > p, g(v))) for (v, _) in STR]); end
    push!(out, [string(count(!isfinite, g(v))) for (v, _) in STR])
    push!(out, [all(r -> r.reg[v] != "" || !isfinite(r.gap[v]), RR) ? string(count(r -> r.reg[v] == r.regO, RR)) : "—" for (v, _) in STR])
    push!(out, sims); push!(out, tempo)
    return out
end
const ETICHETTE = ["media", "mediana", "90° percentile", "massimo", "esattamente l'ottimo", "entro 0,1%", "entro 0,5%", "entro 1%", "oltre 2%",
                   "oltre 5%", "nessuna proposta fattibile", "regime giusto", "simulazioni per tratta (media)", "tempo per tratta"]
simsT = ["288", @sprintf("%.1f", mean(r.nsim[:semplice] for r in R)), @sprintf("%.1f (max %d)", mean(r.nsim[:G] for r in R), maximum(r.nsim[:G] for r in R))]
tempoT = ["(campagna)", @sprintf("%.2f s", TEMPI[:semplice].tratta), @sprintf("%.2f s", TEMPI[:G].tratta)]
simsL = ["288", "—", @sprintf("%.1f (max %d)", mean(r.nsim[:G] for r in RL), maximum(r.nsim[:G] for r in RL))]
tempoL = ["(campagna)", "—", @sprintf("%.2f s", TLIN.tratta)]
TT = righe_tabella(R, N, simsT, tempoT); TL = righe_tabella(RL, NL, simsL, tempoL)
say("\nIL COSTO RISPETTO ALL'OTTIMO VERO (griglia fitta simulata): $N tratte DoE del test (mai viste) e $NL linee reali (fase 13)")
say(@sprintf("%-30s", ""), join((@sprintf("%21s", "test: " * s) for (_, s) in STR)), "  |", join((@sprintf("%21s", "linee: " * s) for (_, s) in STR)))
for (k, e) in enumerate(ETICHETTE)
    say(@sprintf("%-30s", "  " * e), join((@sprintf("%21s", x) for x in TT[k])), "  |", join((@sprintf("%21s", x) for x in TL[k])))
end
say("  (i conteggi sono su $N tratte a sinistra e $NL linee a destra; la migliore delle 288 può costare meno dell'ottimo della griglia,",
    " perché le 288 coppie non stanno sulla griglia a passo 0,01. Tempo del surrogato: a tratta, sul Mac, compresa la compilazione",
    @sprintf(" durante la prima tratta; avvio a parte: test G %.1f s, semplice %.1f s)", TEMPI[:G].avvio, TEMPI[:semplice].avvio))

say("\nIL REGIME: ottimo vero (righe) contro surrogato G + bordo (colonne), tratte del test")
for a in REGIMI
    s = [r for r in R if r.regO == a]
    say(@sprintf("  %-20s %3d → %s", a, length(s), join((@sprintf("%s %d", b, count(r -> r.reg[:G] == b, s)) for b in REGIMI), ", ")))
end
say(@sprintf("  stesso regime: %d su %d", count(r -> r.regO == r.reg[:G], R), N))
RG = [r for r in R if isfinite(r.gap[:G])]
dm = [abs(r.prop[:G][1] - r.opt[1]) for r in RG]; dn = [abs(r.prop[:G][2] - r.opt[2]) for r in RG]
say(@sprintf("  distanza della proposta G dall'ottimo: m mediana %.2f (max %.2f), n mediana %.2f (max %.2f); stesso punto in %d tratte",
             median(dm), maximum(dm), median(dn), maximum(dn), count(r -> r.prop[:G] == r.opt, RG)))
say(@sprintf("  posizione della proposta G nella classifica dei progetti fattibili: mediana %d°, 90° percentile %d°, peggiore %d°",
             round(Int, median(r.posG for r in RG)), round(Int, quantile([r.posG for r in RG], 0.9)), maximum(r.posG for r in RG)))

say("\nPER REGIME DELL'OTTIMO E PER LUNGHEZZA (G + bordo, tratte del test)")
for (nome, sel) in vcat([(a, r -> r.regO == a) for a in REGIMI],
                        [("L < 100 km", r -> r.L < 100), ("L 100–200 km", r -> 100 <= r.L < 200), ("L ≥ 200 km", r -> r.L >= 200)])
    s = [r for r in R if sel(r)]; isempty(s) && continue
    x = [r.gap[:G] for r in s]
    say(@sprintf("  %-20s %3d tratte: esattamente l'ottimo %3d, entro 1%% %3d, oltre 2%% %2d; media %s, massimo %s", nome, length(s), count(<(1e-9), x),
                 count(<=(1), x), count(y -> isfinite(y) && y > 2, x), pct(mean(fin(x))), pct(maximum(fin(x)))))
end

say("\nQUANTO È PIATTO IL COSTO VICINO ALL'OTTIMO (progetti fattibili entro lo 0,1 / 0,5 / 1% dall'ottimo, mediana sulle tratte)")
say(@sprintf("  %d / %d / %d progetti su %d fattibili (mediana)", round(Int, median(r.entro01 for r in R)), round(Int, median(r.entro05 for r in R)),
             round(Int, median(r.entro1 for r in R)), round(Int, median(r.nfatt for r in R))))

say("\nLE TRATTE CON IL SURROGATO G + BORDO OLTRE LO 0,5% DALL'OTTIMO (o senza proposta)")
for r in sort(R; by = r -> -r.gap[:G])
    r.gap[:G] > 0.5 || break
    say(@sprintf("  route_%06d L %6.1f km: ottimo (%.2f, %.2f) %.4f €/km %-18s | G (%.2f, %.2f) %s %-18s %d sim. | 288 %s, semplice %s", r.tratta, r.L,
                 r.opt..., r.copt, r.regO, r.prop[:G]..., pct(r.gap[:G]), r.reg[:G], r.nsim[:G], pct(r.gap[:b288]), pct(r.gap[:semplice])))
end

tg = fin([r.tgriglia for r in R]); tc = [r.tcpu for r in R]
say("\nI TEMPI")
say(@sprintf("  griglia fitta simulata: %.1f s di orologio per tratta (mediana %.1f, 8 thread), %.1f h di calcolo sommando i singoli progetti;",
             mean(tg), median(tg), sum(tc) / 3600))
say(@sprintf("  surrogato G: %.2f s per tratta (%.1f simulazioni), cioè circa %.0f volte meno della griglia simulata", TEMPI[:G].tratta,
             mean(r.nsim[:G] for r in R), mean(tg) / TEMPI[:G].tratta))

open(joinpath(LOG, "03_ottimo_tratte.csv"), "w") do io
    println(io, "tratta,L_km,ottimo_m,ottimo_n,ottimo_costo,ottimo_regime,fattibili,entro_0.5pct,G_m,G_n,G_regime,G_vs_ottimo_pct,G_simulazioni,G_posizione,",
            "semplice_m,semplice_n,semplice_vs_ottimo_pct,semplice_simulazioni,migliore288_m,migliore288_vs_ottimo_pct,t_griglia_s,t_griglia_cpu_s")
    for r in R
        println(io, join((r.tratta, @sprintf("%.3f", r.L), r.opt..., @sprintf("%.6g", r.copt), r.regO, r.nfatt, r.entro05, r.prop[:G]..., r.reg[:G],
                          @sprintf("%.4f", r.gap[:G]), r.nsim[:G], r.posG, r.prop[:semplice]..., @sprintf("%.4f", r.gap[:semplice]), r.nsim[:semplice],
                          @sprintf("%.4f", r.m288), @sprintf("%.4f", r.gap[:b288]), @sprintf("%.1f", r.tgriglia), @sprintf("%.1f", r.tcpu)), ','))
    end
end

# figura: distribuzione cumulata dello scarto dall'ottimo, test (continue) e linee (tratteggiate)
plt = plot(size = (1050, 560), dpi = 120, left_margin = 8Plots.mm, bottom_margin = 6Plots.mm, xlabel = "costo rispetto all'ottimo vero [%]",
           ylabel = "quota delle tratte (cumulata)", legend = :bottomright, xlims = (-1, 8), ylims = (0, 1.02),
           title = "costo contro l'ottimo vero: $N tratte del test (—), $NL linee (- -)", titlefontsize = 11)
for ((v, nm), col) in zip(STR, (:gray50, :darkorange, :steelblue))
    for (RR, ls, et) in ((R, :solid, "test"), (RL, :dash, "linee"))
        x = sort(fin([r.gap[v] for r in RR])); plot!(plt, x, (1:length(x)) ./ length(RR); seriestype = :steppost, lw = 2, color = col, ls = ls, label = "$nm, $et")
    end
end
vline!(plt, [0]; color = :black, lw = 1, label = "")
savefig(plt, joinpath(LOG, "fig_ottimo_test.png"))
say("\nTabella: ", joinpath(LOG, "03_ottimo_tratte.csv"), "; figura: fig_ottimo_test.png")
close(OUT)
