# fase9/01_costo.jl: passo 5a, dal surrogato al costo, caso per caso, sulla validazione.
#
#   julia -t 8 --project=fase9 fase9/01_costo.jl > ~/Documents/lavoro/ml_treno_dati/fase9_log/log_01.txt 2>&1
#
# 1. collaudo del banco di prova: `valuta` con le grandezze VERE (e l'esito D3 vero) deve ridare fattibilità e costo
#    del registro;
# 2. surrogato: le 8 grandezze previste dal boosting (fase 7, modello E per la durata; fase 8 per le altre), D3 dalla
#    regola a posteriori C-rate > 20, poi `valuta`; confronto con il vero: fattibilità (in tutto e vincolo per vincolo)
#    e costo;
# 3. da dove viene l'errore: una grandezza vera alla volta al posto della prevista.
# Scrive in ~/Documents/lavoro/ml_treno_dati/fase9_log: 01_costo.txt, 01_ablazione.csv, fig_*.png; le previsioni e il
# costo del surrogato in ~/Documents/lavoro/ml_treno_dati/fase9/surrogato_validazione.arrow (per il passo 5b).

include(joinpath(@__DIR__, "comune.jl"))
using EvoTrees, Random, Plots
gr()
const LOG = joinpath(BASE, "fase9_log"); mkpath(LOG)
const DAT = joinpath(BASE, "fase9"); mkpath(DAT)
const OUT = open(joinpath(LOG, "01_costo.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase9/01_costo.jl  ", now(), "  thread: ", Threads.nthreads(), "  julia ", VERSION, "  EvoTrees ", pkgversion(EvoTrees),
    "  TrainPowertrain ", TP.commit_codice())
const T_INIZIO = time()

# ── dati e previsioni ────────────────────────────────────────────────────────────
const tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))
const NX = [c for c in Arrow.names(tv) if startswith(String(c), "x_")]
const X = reduce(hcat, (Vector{Float64}(getproperty(tv, c)) for c in vcat(NX, [:m, :n])))
const M = collect(tv.m); const Nn = collect(tv.n); const L = collect(tv.x_L_km); const T = collect(tv.x_tempo_limiti_ar_s)
const TR = Int.(tv.tratta); const STATO = collect(tv.stato)
const IBR = M .> 0
say(@sprintf("validazione: %d casi, %d tratte; completed %d, rejected D3 %d, fattibili %d", length(M), length(unique(TR)),
             count(==(1), STATO), count(==(2), STATO), count(tv.fattibile)))

# con l'arresto anticipato il modello salvato ha 50 alberi in più del migliore: come in fase 7/8 si usa ntree_limit = best + 1
function previsione_best(file)
    mdl = EvoTrees.load(file)
    best = mdl.info[:logger][:best_iter]
    return vec(EvoTrees.predict(mdl, X; ntree_limit = best + 1))
end
t0 = time()
F7 = joinpath(BASE, "fase7"); F8 = joinpath(BASE, "fase8")
const P = (durata = previsione_best(joinpath(F7, "durata_E.bson")) .* T,
           serbatoio = ifelse.(IBR, previsione_best(joinpath(F8, "modello_massa_serbatoio.bson")) .* 2 .* L, 0.0),
           H2 = ifelse.(IBR, previsione_best(joinpath(F8, "modello_H2_cons.bson")) .* 2 .* L, 0.0),
           SOC = clamp.(previsione_best(joinpath(F8, "modello_SOC_end.bson")), 0.0, 0.9),
           p_scarica = previsione_best(joinpath(F8, "modello_scarica.bson")),
           vita_batt = exp.(previsione_best(joinpath(F8, "modello_vita_batt.bson"))),
           vita_FC_f1 = ifelse.(IBR, exp.(previsione_best(joinpath(F8, "modello_vita_FC.bson"))), Inf),
           C_rate = exp.(previsione_best(joinpath(F8, "modello_C_rate.bson"))))
const Q = (durata = P.durata, serbatoio = P.serbatoio, H2 = P.H2, SOC = P.SOC, scarica = P.p_scarica .>= 0.5,
           vita_batt = P.vita_batt, vita_FC_f1 = P.vita_FC_f1, C_rate = P.C_rate)
say(@sprintf("previsioni delle 8 grandezze su %d casi: %.1f s (%.1f µs a caso con %d thread)", length(M), time() - t0,
             1e6 * (time() - t0) / length(M), Threads.nthreads()))
# controllo: le previsioni coincidono con quelle salvate in fase 7/8 (stessi modelli)
let p = Arrow.Table(joinpath(F8, "pred_SOC_end.arrow"))
    say("  controllo: SOC previsto = fase 8 (prima del taglio a [0; 0,9]): ",
        all(isapprox.(clamp.(collect(p.boosting), 0, 0.9), P.SOC; rtol = 0, atol = 0)))
end
say(@sprintf("  SOC previsto fuori da [0; 0,9] prima del taglio: %d casi", count(x -> x < 0 || x > 0.9, previsione_best(joinpath(F8, "modello_SOC_end.bson")))))

const V = grandezze_vere(tv)
const FATT_VERO = collect(tv.fattibile); const D3_VERO = collect(tv.d3)
const COSTO_VERO = collect(tv.costo); const TOT_VERO = collect(tv.total_cost_EUR_km)

# ── 1. collaudo con le grandezze vere ────────────────────────────────────────────
say("\n[1] collaudo: grandezze vere ed esito D3 vero → fattibilità e costo del registro?")
t0 = time()
rv = valuta(M, Nn, L, V; d3 = D3_VERO)
say(@sprintf("  %.1f s", time() - t0))
comp = STATO .== 1
say("  fattibile = registro (tipo_esito == fattibile): ", count(rv.fattibile .== FATT_VERO), " / ", length(M))
say("  vincoli: massa ", count(rv.viol_massa[comp] .== (tv.tipo_esito[comp] .∈ Ref((3, 4)))), " / ", count(comp),
    " (pesante o mista ⇔ massa oltre il limite)")
dr = abs.(rv.costo_totale[comp] .- TOT_VERO[comp]) ./ TOT_VERO[comp]
say(@sprintf("  costo senza penalità (completed): uguali al bit %d / %d; scarto relativo massimo %.2e", count(rv.costo_totale[comp] .== TOT_VERO[comp]),
             count(comp), maximum(dr)))
say("  costo con penalità = registro (scarto ≤ 1e-9 relativo): ", count(abs.(rv.costo .- COSTO_VERO) .<= 1e-9 .* abs.(COSTO_VERO)), " / ", length(M))
ok_coll = all(rv.fattibile .== FATT_VERO) && maximum(dr) < 1e-12
say("  ESITO DEL COLLAUDO: ", ok_coll ? "il banco di prova ridà il simulatore" : "NON RIDÀ IL SIMULATORE: vedi sopra")

# ── 2. il surrogato ──────────────────────────────────────────────────────────────
say("\n[2] surrogato: grandezze previste, D3 dalla regola C-rate > 20")
t0 = time()
rs = valuta(M, Nn, L, Q)
say(@sprintf("  %.1f s", time() - t0))
tp = count(rs.fattibile .& FATT_VERO); fn = count(.!rs.fattibile .& FATT_VERO); fp = count(rs.fattibile .& .!FATT_VERO); tn = count(.!rs.fattibile .& .!FATT_VERO)
say("  fattibilità (righe = vero, colonne = surrogato):")
say(@sprintf("                       surrogato: fattibile   non fattibile"))
say(@sprintf("    vero fattibile         %10d   %10d   (scartati per errore: %.2f%% dei fattibili)", tp, fn, 100fn / (tp + fn)))
say(@sprintf("    vero non fattibile     %10d   %10d   (promossi per errore: %.2f%% dei non fattibili)", fp, tn, 100fp / (fp + tn)))
say(@sprintf("    giusti %.3f%%; dei casi che il surrogato dice fattibili, davvero fattibili %.3f%%", 100(tp + tn) / length(M), 100tp / (tp + fp)))
say("  vincolo per vincolo (vero dalle grandezze vere; D3 vero dall'esito):")
vm_v = rv.viol_massa; vs_v = rv.viol_soc; vsc_v = rv.viol_scarica
for (nome, a, b) in (("D3 (C-rate > 20)", D3_VERO, rs.d3), ("massa > 29 250 kg", vm_v, rs.viol_massa),
                     ("SOC finale < 0,2", vs_v, rs.viol_soc), ("scarica totale", vsc_v, rs.viol_scarica))
    say(@sprintf("    %-20s violato davvero %7d; surrogato giusto %.3f%%; mancati %6d, in più %6d", nome, count(a),
                 100count(a .== b) / length(a), count(a .& .!b), count(.!a .& b)))
end
# quale vincolo causa gli errori di fattibilità (un caso può averne più d'uno)
let err = rs.fattibile .!= FATT_VERO
    say("  nei ", count(err), " casi con la fattibilità sbagliata, il vincolo sbagliato è:")
    for (nome, a, b) in (("D3", D3_VERO, rs.d3), ("massa", vm_v, rs.viol_massa), ("SOC", vs_v, rs.viol_soc), ("scarica", vsc_v, rs.viol_scarica))
        say(@sprintf("    %-8s %6d (%.1f%%)", nome, count(err .& (a .!= b)), 100count(err .& (a .!= b)) / count(err)))
    end
end
# costo: dove è definito sia vero sia previsto
function errcost(ct, sel)
    e = 100 .* abs.(ct[sel] .- TOT_VERO[sel]) ./ TOT_VERO[sel]
    return (n = count(sel), mediana = median(e), p95 = quantile(e, 0.95), p99 = quantile(e, 0.99), max = maximum(e),
            bias = 100mean((ct[sel] .- TOT_VERO[sel]) ./ TOT_VERO[sel]))
end
say("  costo senza penalità, errore relativo % (mediana / p95 / p99 / max; bias medio):")
for (nome, sel) in (("completed, non D3 per il surrogato", comp .& .!rs.d3),
                    ("davvero fattibili", FATT_VERO .& .!rs.d3),
                    ("davvero fattibili, sola batteria", FATT_VERO .& .!rs.d3 .& .!IBR),
                    ("davvero fattibili, ibridi", FATT_VERO .& .!rs.d3 .& IBR))
    e = errcost(rs.costo_totale, sel)
    say(@sprintf("    %-36s %7d casi: %.3f / %.3f / %.3f / %.2f; bias %+.3f%%", nome, e.n, e.mediana, e.p95, e.p99, e.max, e.bias))
end
let sel = FATT_VERO .& .!rs.d3, e = 100 .* abs.(rs.costo_totale .- TOT_VERO) ./ TOT_VERO
    say("  per fascia di lunghezza (davvero fattibili): ", join((let s = sel .& (L .>= a) .& (L .< b)
        @sprintf("%d–%d km %.2f / %.2f", a, b, median(e[s]), quantile(e[s], 0.95)) end for (a, b) in ((0, 25), (25, 100), (100, 200), (200, 301))), ";  "))
end

# ── 3. da dove viene l'errore ────────────────────────────────────────────────────
say("\n[3] da dove viene l'errore: una grandezza vera alla volta al posto della prevista")
abl = NamedTuple[]
sel_f = FATT_VERO .& .!rs.d3
base = errcost(rs.costo_totale, sel_f)
push!(abl, (grandezza_vera = "nessuna (surrogato)", fattibilita_giusta_pct = 100count(rs.fattibile .== FATT_VERO) / length(M),
            costo_err_mediana = base.mediana, costo_err_p95 = base.p95, costo_err_p99 = base.p99))
for k in NOMI_Q
    q = sostituisci(Q, V, k)
    r = valuta(M, Nn, L, q)
    s = FATT_VERO .& .!r.d3 .& isfinite.(r.costo_totale)
    e = errcost(r.costo_totale, s)
    push!(abl, (grandezza_vera = String(k), fattibilita_giusta_pct = 100count(r.fattibile .== FATT_VERO) / length(M),
                costo_err_mediana = e.mediana, costo_err_p95 = e.p95, costo_err_p99 = e.p99))
end
say(@sprintf("  %-22s %14s %14s %10s %10s", "grandezza resa vera", "fattib. giusta", "costo mediana", "p95", "p99"))
for a in abl
    say(@sprintf("  %-22s %13.3f%% %13.3f%% %9.3f%% %9.3f%%", a.grandezza_vera, a.fattibilita_giusta_pct, a.costo_err_mediana,
                 a.costo_err_p95, a.costo_err_p99))
end
open(joinpath(LOG, "01_ablazione.csv"), "w") do io
    println(io, join(keys(abl[1]), ','))
    for a in abl; println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(a)), ',')); end
end

# ── 4. una sola grandezza prevista, le altre vere ───────────────────────────────
say("\n[4] una sola grandezza prevista (le altre vere): quanto errore porta ciascuna da sola")
say("    (D3 dalla regola sul C-rate in uso: vero o previsto; costo sui casi davvero fattibili e non D3)")
abl1 = NamedTuple[]
for k in NOMI_Q
    q = sostituisci(V, Q, k)
    r = valuta(M, Nn, L, q)
    s = FATT_VERO .& .!r.d3 .& isfinite.(r.costo_totale)
    e = errcost(r.costo_totale, s); eb = errcost(r.costo_totale, s .& .!IBR); ei = errcost(r.costo_totale, s .& IBR)
    push!(abl1, (grandezza_prevista = String(k), fattibilita_giusta_pct = 100count(r.fattibile .== FATT_VERO) / length(M),
                 costo_err_mediana = e.mediana, costo_err_p95 = e.p95, sola_batt_mediana = eb.mediana, sola_batt_p95 = eb.p95,
                 ibridi_mediana = ei.mediana, ibridi_p95 = ei.p95))
end
say(@sprintf("  %-14s %14s %22s %22s %22s", "prevista", "fattib. giusta", "costo: mediana / p95", "sola batteria", "ibridi"))
for a in abl1
    say(@sprintf("  %-14s %13.3f%%   %8.3f%% / %7.3f%%   %8.3f%% / %7.3f%%   %8.3f%% / %7.3f%%", a.grandezza_prevista,
                 a.fattibilita_giusta_pct, a.costo_err_mediana, a.costo_err_p95, a.sola_batt_mediana, a.sola_batt_p95,
                 a.ibridi_mediana, a.ibridi_p95))
end
open(joinpath(LOG, "01_una_prevista.csv"), "w") do io
    println(io, join(keys(abl1[1]), ','))
    for a in abl1; println(io, join((x isa Float64 ? @sprintf("%.6g", x) : x for x in values(a)), ',')); end
end

# ── salvataggio per il passo 5b ──────────────────────────────────────────────────
Arrow.write(joinpath(DAT, "surrogato_validazione.arrow"),
            (tratta = Int32.(TR), coppia = tv.coppia, m = M, n = Nn,
             durata = P.durata, serbatoio = P.serbatoio, H2 = P.H2, SOC = P.SOC, p_scarica = P.p_scarica, vita_batt = P.vita_batt,
             vita_FC_f1 = P.vita_FC_f1, C_rate = P.C_rate,
             d3 = rs.d3, viol_massa = rs.viol_massa, viol_soc = rs.viol_soc, viol_scarica = rs.viol_scarica, fattibile = rs.fattibile,
             costo_totale = rs.costo_totale, costo = rs.costo,
             vero_fattibile = FATT_VERO, vero_d3 = D3_VERO, vero_costo_totale = TOT_VERO, vero_costo = COSTO_VERO))
say("\nsalvato ", joinpath(DAT, "surrogato_validazione.arrow"))

# ── figure ───────────────────────────────────────────────────────────────────────
let s = findall(FATT_VERO .& .!rs.d3), ic = s[randperm(Xoshiro(3), length(s))[1:min(60_000, length(s))]]
    plt = scatter(TOT_VERO[ic], rs.costo_totale[ic]; ms = 1.2, msw = 0, alpha = 0.3, color = ifelse.(IBR[ic], :steelblue, :darkorange),
                  legend = false, size = (650, 600), dpi = 130, xlabel = "costo vero [€/km]", ylabel = "costo del surrogato [€/km]",
                  title = "casi davvero fattibili (blu ibridi, arancio sola batteria)")
    a, b = extrema(TOT_VERO[ic]); plot!(plt, [a, b], [a, b]; color = :black, ls = :dash)
    savefig(plt, joinpath(LOG, "fig_costo_previsto_vero.png"))
end
let nomi = [a.grandezza_prevista for a in abl1]
    v = hcat([a.sola_batt_p95 for a in abl1], [a.ibridi_p95 for a in abl1])
    x = 1:length(nomi)
    plt = bar(x .- 0.2, v[:, 1]; bar_width = 0.4, label = "sola batteria", color = :darkorange, size = (900, 480), dpi = 130,
              xticks = (x, nomi), ylabel = "errore del costo, p95 [%]", bottom_margin = 8Plots.mm,
              title = "errore del costo se fosse prevista solo questa grandezza (le altre vere)")
    bar!(plt, x .+ 0.2, v[:, 2]; bar_width = 0.4, label = "ibridi", color = :steelblue)
    savefig(plt, joinpath(LOG, "fig_una_prevista.png"))
end
say("figure: fig_costo_previsto_vero.png, fig_una_prevista.png")
say(@sprintf("\ntempo totale: %.1f s", time() - T_INIZIO))
close(OUT)
