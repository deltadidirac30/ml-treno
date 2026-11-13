# fase4/04_figure.jl: figure del passo 3 (png in fase4/figure).
#   julia -t 8 --project=fase4 fase4/04_figure.jl
# Richiede l'Arrow (02_arrow.jl), arrow/tratte_riassunto.arrow, risultati/coppie_riassunto.csv e log/03_venti.jls (03_contenuto.jl).

include(joinpath(@__DIR__, "comune.jl"))
using Plots, Statistics, Serialization
gr()

# colori (palette di riferimento: categoriche blu/arancio, sequenziale blu chiaro → scuro, grigio neutro)
const BLU, ARANCIO, VERDEACQUA = colorant"#2a78d6", colorant"#eb6834", colorant"#1baf7a"
const GRIGIO = colorant"#a3a29d"
const SEQ = cgrad([colorant"#cde2fb", colorant"#86b6ef", colorant"#3987e5", colorant"#256abf", colorant"#184f95", colorant"#0d366b"])
const COPPIE = leggi_coppie()
const SOGLIE = [x.m for x in TP.soglie_controllo(CFG)]
default(fontfamily = "Helvetica", titlefontsize = 9, guidefontsize = 8, tickfontsize = 7, legendfontsize = 7,
        grid = true, gridalpha = 0.15, framestyle = :box, dpi = 150, foreground_color_legend = nothing)
salva(p, nome) = (savefig(p, joinpath(FIG, nome)); println("  ", nome))
soglie!(p) = vline!(p, SOGLIE; color = :black, lw = 0.5, ls = :dash, alpha = 0.5, label = "")

function main()
    mkpath(FIG)
    T = Arrow.Table(FILE_TRATTE_ARROW); Rt = Arrow.Table(FILE_RIASSUNTO_ARROW)
    # ── per coppia ──
    l = readlines(joinpath(RIS, "coppie_riassunto.csv")); h = split(l[1], ',')
    col(nome) = [parse(Float64, split(x, ',')[findfirst(==(nome), h)]) for x in l[2:end]]
    mm, nn = first.(COPPIE), last.(COPPIE)
    pan = []
    for (nome, tit) in (("quota_fattibili", "quota di tratte fattibili"), ("quota_rejected_D3", "quota rejected (D3)"),
                        ("quota_scarica_totale", "quota con scarica totale (scarica_s > 0)"), ("quota_D28", "quota D28 (storage non convergente)"))
        v = col(nome)
        p = scatter(mm, nn; zcolor = v, color = SEQ, ms = 4, msw = 0.3, msc = :white, label = "", title = tit,
                    xlabel = "m", ylabel = "n", colorbar = true, xlims = (-0.02, 1.02), ylims = (0, 1.02))
        soglie!(p); push!(pan, p)
    end
    salva(plot(pan...; layout = (2, 2), size = (1000, 800)), "coppie_quote.png")

    # ── colonne per le distribuzioni ──
    D = carica_tutto(["tratta", "coppia", "stato", "tipo_esito", "m", "n", "total_cost_EUR_km", "SOC_end", "H2_cons_kg", "E_ricarica_rete_kWh",
                      "num_repl_FC", "num_repl_batt", "durata_viaggio_s", "massa_treno_kg", "storage_non_convergente"])
    fatt = D["tipo_esito"] .== 1; comp = D["stato"] .== 1; ibr = D["m"] .> 0
    tc = D["total_cost_EUR_km"][fatt]
    p1 = histogram(tc; bins = 200, color = BLU, lw = 0, label = "", xlabel = "total_cost_EUR_km [€/km]", ylabel = "righe",
                   title = "costo delle righe fattibili ($(fmt(length(tc))))")
    p2 = histogram(log10.(tc); bins = 200, color = BLU, lw = 0, label = "", xlabel = "log10 total_cost_EUR_km", ylabel = "righe", title = "stesso, in scala logaritmica")
    salva(plot(p1, p2; layout = (1, 2), size = (1000, 380), left_margin = 4Plots.mm, bottom_margin = 4Plots.mm), "costo_fattibili.png")

    p1 = histogram(D["SOC_end"][comp]; bins = 150, color = GRIGIO, lw = 0, label = "completed", xlabel = "SOC_end", ylabel = "righe", title = "SOC a fine viaggio")
    histogram!(p1, D["SOC_end"][fatt]; bins = 150, color = BLU, lw = 0, label = "fattibili"); vline!(p1, [0.2]; color = :black, ls = :dash, label = "0,2")
    p2 = histogram(D["H2_cons_kg"][comp .& ibr]; bins = 150, color = GRIGIO, lw = 0, label = "completed ibride", xlabel = "H2_cons_kg [kg/viaggio A/R]", title = "idrogeno per viaggio")
    histogram!(p2, D["H2_cons_kg"][fatt .& ibr]; bins = 150, color = ARANCIO, lw = 0, label = "fattibili ibride")
    p3 = histogram(D["E_ricarica_rete_kWh"][comp]; bins = 150, color = GRIGIO, lw = 0, label = "completed", xlabel = "E_ricarica_rete_kWh [kWh/viaggio]", title = "energia di ricarica dalla rete")
    histogram!(p3, D["E_ricarica_rete_kWh"][fatt]; bins = 150, color = BLU, lw = 0, label = "fattibili")
    salva(plot(p1, p2, p3; layout = (1, 3), size = (1300, 380), left_margin = 4Plots.mm, bottom_margin = 5Plots.mm), "distribuzioni.png")

    # ── migliore per tratta contro il design ──
    ok = Rt.regime_migliore .> 0
    reg = Rt.regime_migliore
    fattori = [(:L_km, "L_km [km]"), (:slope_mean, "slope_mean [‰]"), (:slope_std, "slope_std [‰]"), (:slope_segment_length_mean_km, "slope_segment_length_mean_km"),
               (:stop_density, "stop_density [1/km]"), (:stop_spacing_cv, "stop_spacing_cv"), (:v_max_kmh, "v_max_kmh"), (:speed_restriction_index, "speed_restriction_index"),
               (:speed_change_density, "speed_change_density [1/km]"), (:n_stops, "n_stops"), (:round_trip_estimate_h, "round_trip_estimate_h"), (:n_vlim_segments, "n_vlim_segments")]
    pan = []
    for (k, (f, nome)) in enumerate(fattori)
        x = Float64.(getproperty(T, f))
        p = scatter(x[ok .& (reg .== 1)], Rt.costo_migliore[ok .& (reg .== 1)]; ms = 1.2, msw = 0, color = BLU, alpha = 0.35, label = k == 1 ? "sola batteria" : "",
                    xlabel = nome, ylabel = k % 4 == 1 ? "costo migliore [€/km]" : "", yscale = :log10)
        scatter!(p, x[ok .& (reg .== 2)], Rt.costo_migliore[ok .& (reg .== 2)]; ms = 1.2, msw = 0, color = ARANCIO, alpha = 0.35, label = k == 1 ? "ibrido" : "")
        push!(pan, p)
    end
    salva(plot(pan...; layout = (3, 4), size = (1400, 950), left_margin = 4Plots.mm, bottom_margin = 4Plots.mm,
               plot_title = "costo della migliore coppia fattibile per tratta contro i fattori del design (16384 tratte)", plot_titlefontsize = 10), "migliore_vs_design.png")
    L = T.L_km; sd = T.stop_density
    p = scatter(L[reg .== 1], sd[reg .== 1]; ms = 1.5, msw = 0, color = BLU, alpha = 0.5, label = "sola batteria ($(count(==(1), reg)))",
                xlabel = "L_km [km]", ylabel = "stop_density [1/km]", title = "regime della migliore coppia fattibile")
    scatter!(p, L[reg .== 2], sd[reg .== 2]; ms = 1.5, msw = 0, color = ARANCIO, alpha = 0.5, label = "ibrido ($(count(==(2), reg)))")
    # quota di ibride per fascia di L
    bins = 0:10:ceil(maximum(L) / 10) * 10
    qi = [(c = (L .>= a) .& (L .< a + 10); count(c) == 0 ? NaN : count(c .& (reg .== 2)) / count(c)) for a in bins[1:end-1]]
    p2 = plot(collect(bins[1:end-1]) .+ 5, qi; color = ARANCIO, lw = 2, marker = :circle, ms = 3, msw = 0, label = "",
              xlabel = "L_km [km]", ylabel = "quota di tratte con migliore ibrida", ylims = (0, 1), title = "quota ibride per fascia di 10 km")
    salva(plot(p, p2; layout = (1, 2), size = (1200, 450), left_margin = 4Plots.mm, bottom_margin = 4Plots.mm), "regime_migliore.png")

    # ── 20 tratte: mappe in (m, n) ──
    V = deserialize(joinpath(DATI, "log", "03_venti.jls"))
    # gli indici di riga di 03 sono nell'ordine di carica_tutto: stessi qui
    for (qn, tit) in (("H2_cons_kg", "H2_cons_kg [kg/viaggio]"), ("E_ricarica_rete_kWh", "E_ricarica_rete_kWh [kWh]"), ("SOC_end", "SOC_end"),
                      ("num_repl_FC", "num_repl_FC"), ("num_repl_batt", "num_repl_batt"), ("total_cost_EUR_km", "total_cost_EUR_km [€/km]"))
        x = D[qn]; pan = []
        for t in V.venti
            ii = [V.righe[(Int32(t), Int16(c))] for c in 1:NCOPPIE]
            ok = [comp[i] for i in ii]
            v = x[ii]
            # costo in log10 (le penalità lo portano a migliaia)
            vv = qn == "total_cost_EUR_km" ? log10.(v) : v
            p = scatter(mm[.!ok], nn[.!ok]; marker = :x, ms = 2.5, color = GRIGIO, label = "", title = "route $t" * (qn == "total_cost_EUR_km" ? " (log10)" : ""))
            scatter!(p, mm[ok], nn[ok]; zcolor = vv[ok], color = SEQ, ms = 3.2, msw = 0, label = "", colorbar = true, xlims = (-0.02, 1.02), ylims = (0, 1.02))
            soglie!(p); push!(pan, p)
        end
        salva(plot(pan...; layout = (4, 5), size = (1700, 1250), plot_title = "$tit sulle 288 coppie (x grigie: rejected D3); assi m, n; tratteggio: soglie D25",
                   plot_titlefontsize = 10), "regolarita_$(qn).png")
    end

    # ── durata contro massa del treno (D27), 6 tratte delle 20 ──
    pan = []
    for t in V.venti[1:6]
        ii = [V.righe[(Int32(t), Int16(c))] for c in 1:NCOPPIE if comp[V.righe[(Int32(t), Int16(c))]]]
        mt = D["massa_treno_kg"][ii] ./ 1000; du = D["durata_viaggio_s"][ii] ./ 3600
        p = scatter(mt[D["m"][ii] .== 0], du[D["m"][ii] .== 0]; ms = 2.5, msw = 0, color = BLU, label = "sola batteria", title = "route $t",
                    xlabel = "massa del treno [t]", ylabel = "durata A/R [h]")
        scatter!(p, mt[D["m"][ii] .> 0], du[D["m"][ii] .> 0]; ms = 2.5, msw = 0, color = ARANCIO, label = "ibrido")
        push!(pan, p)
    end
    salva(plot(pan...; layout = (2, 3), size = (1300, 700), left_margin = 4Plots.mm, bottom_margin = 4Plots.mm), "durata_massa.png")

    # ── D28 in (m, n): righe per coppia ──
    d28 = [x === true for x in D["storage_non_convergente"]]
    cnt = zeros(Int, NCOPPIE); for i in findall(d28); cnt[D["coppia"][i]] += 1; end
    p = scatter(mm[cnt .== 0], nn[cnt .== 0]; ms = 2.5, msw = 0, color = GRIGIO, label = "nessuna riga D28", xlabel = "m", ylabel = "n")
    scatter!(p, mm[cnt .> 0], nn[cnt .> 0]; zcolor = cnt[cnt .> 0], color = SEQ, ms = 5, msw = 0.3, msc = :white, label = "",
             title = "righe D28 per coppia (su 16384 tratte)", colorbar = true)
    soglie!(p)
    salva(plot(p; size = (650, 520)), "d28_coppie.png")
end

main()
