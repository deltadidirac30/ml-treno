# Fase 2, passo 4: analisi del modello scelto.
#   (1) importanza per permutazione (sui fold di prova della ripetizione 1) per regime, m* (ibride), n* (ibride e sola
#       batteria) e costo: singole caratteristiche e gruppi permutati insieme;
#   (2) curva di apprendimento: training di 256, 512, 768 tratte e tutto il fold (ripetizione 1), simulatore nel punto
#       previsto;
#   (3) dove si concentrano gli errori (sim_cv.csv, tutte le ripetizioni): ottimi sul limite di massa, sul limite di
#       SOC, vicino alla soglia D20 (m* ≈ 0,1195), vicino a m_min, vicino ai salti dei viaggi al giorno.
#
# Uso, da ml_treno/fase2:   julia -t 8 --project=. 04_analisi.jl <famiglia> <insieme> <famiglia_costo>
# Scrive in risultati/ importanza, importanza_gruppi, curva_apprendimento, errori_categorie (.csv) e analisi (.txt),
# con il suffisso _<famiglia>_<insieme>.

include(joinpath(@__DIR__, "comune.jl"))
include(joinpath(@__DIR__, "simulatore.jl"))
const FAM = Symbol(ARGS[1]); const INS = Symbol(ARGS[2]); const FAMC = Symbol(ARGS[3])
d = dati(); ibr = d.y_ibrido .== 1
cols = colonne(d, INS); X = matrice(d, cols)
out = open(joinpath(RIS, "analisi_$(FAM)_$(INS).txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))
say("famiglia $(FAM), insieme $(INS), costo con $(FAMC)")

gruppo(c) = c == "x_L_km" ? "lunghezza" :
            startswith(c, "x_bin_p") ? "bin_pendenza" : startswith(c, "x_bin_v") ? "bin_velocita" :
            startswith(c, "x_slope") || c == "x_dislivello_m" ? "pendenza" :
            startswith(c, "x_vlim") ? "limiti_velocita" :
            startswith(c, "x_stops") || c == "x_n_fermate" ? "fermate" :
            startswith(c, "x_cross") ? "incrociate" : c == "x_tempo_limiti_ar_s" ? "tempo_limiti" :
            startswith(c, "x_din") ? "dinamica" : error(c)
gruppi = unique(gruppo.(cols))

# ── (1) importanza per permutazione ─────────────────────────────────────────
const BERSAGLI = [("regime", :cls, trues(nrow(d)), Float64.(ibr)), ("m_ibride", :reg, ibr, d.y_m_star),
                  ("n_ibride", :reg, ibr, d.y_n_star), ("n_sola_batteria", :reg, .!ibr, d.y_n_star),
                  ("costo", :reg, trues(nrow(d)), log.(d.y_costo_EUR_km))]
f1 = fold_di(ibr, 1)
imp = DataFrame(); impg = DataFrame()
rng = MersenneTwister(7)
for (nome, tipo, sel, y) in BERSAGLI, k in 1:NFOLD
    itr = findall((f1 .!= k) .& sel); ite = findall((f1 .== k) .& sel)
    fam = nome == "costo" ? FAMC : FAM
    o, _ = adatta_scelto(fam, tipo, X[itr, :], y[itr]; seme = 1000 + k)
    base = perdita(tipo, y[ite], prevedi(o, X[ite, :]))
    for (j, c) in enumerate(cols), rip in 1:3
        Xp = X[ite, :]; Xp[:, j] = Xp[shuffle(rng, 1:length(ite)), j]
        push!(imp, (bersaglio = nome, fold = k, caratteristica = c, aumento_rel = perdita(tipo, y[ite], prevedi(o, Xp)) / base - 1))
    end
    for g in gruppi, rip in 1:3
        J = findall(c -> gruppo(c) == g, cols); Xp = X[ite, :]; pp = shuffle(rng, 1:length(ite))
        Xp[:, J] = Xp[pp, J]
        push!(impg, (bersaglio = nome, fold = k, gruppo = g, aumento_rel = perdita(tipo, y[ite], prevedi(o, Xp)) / base - 1))
    end
end
imp = combine(groupby(imp, [:bersaglio, :caratteristica]), :aumento_rel => mean => :aumento_rel, :aumento_rel => std => :dev)
impg = combine(groupby(impg, [:bersaglio, :gruppo]), :aumento_rel => mean => :aumento_rel, :aumento_rel => std => :dev)
sort!(imp, [:bersaglio, order(:aumento_rel, rev = true)]); sort!(impg, [:bersaglio, order(:aumento_rel, rev = true)])
CSV.write(joinpath(RIS, "importanza_$(FAM)_$(INS).csv"), imp); CSV.write(joinpath(RIS, "importanza_gruppi_$(FAM)_$(INS).csv"), impg)
say("\n(1) importanza per permutazione: aumento relativo della perdita (Brier per il regime, errore quadratico medio altrimenti)")
for (nome, _, _, _) in BERSAGLI
    g = impg[impg.bersaglio .== nome, :]; s = imp[imp.bersaglio .== nome, :]
    say("  ", nome, " — gruppi: ", join([@sprintf("%s %+.2f", r.gruppo, r.aumento_rel) for r in eachrow(g)], ", "))
    say("  ", " "^length(nome), "   prime 10: ", join([@sprintf("%s %+.3f", r.caratteristica[3:end], r.aumento_rel) for r in eachrow(first(s, 10))], ", "))
end

# ── (2) curva di apprendimento ──────────────────────────────────────────────
say("\n(2) curva di apprendimento (ripetizione 1, stessi fold di prova)")
lc = DataFrame()
for dim in (256, 512, 768, 0)
    righe = DataFrame()
    for k in 1:NFOLD
        tutti = findall(f1 .!= k); ite = findall(f1 .== k)
        if dim == 0
            itr = tutti
        else   # sottoinsieme stratificato per regime
            r2 = MersenneTwister(100dim + k); nI = round(Int, dim * mean(ibr[tutti]))
            itr = vcat(shuffle(r2, filter(i -> ibr[i], tutti))[1:nI], shuffle(r2, filter(i -> !ibr[i], tutti))[1:dim-nI])
        end
        tI = filter(i -> ibr[i], itr); tB = filter(i -> !ibr[i], itr)
        s = 2000 + k
        oc, _ = adatta_scelto(FAM, :cls, X[itr, :], Float64.(ibr[itr]); seme = s)
        om, _ = adatta_scelto(FAM, :reg, X[tI, :], d.y_m_star[tI]; seme = s)
        oi, _ = adatta_scelto(FAM, :reg, X[tI, :], d.y_n_star[tI]; seme = s)
        ob, _ = adatta_scelto(FAM, :reg, X[tB, :], d.y_n_star[tB]; seme = s)
        ol = FAMC === :gp ? adatta_gp(X[itr, :], log.(d.y_costo_EUR_km[itr])) :
             first(adatta_scelto(FAMC, :reg, X[itr, :], log.(d.y_costo_EUR_km[itr]); seme = s))
        Xt = X[ite, :]; reg = prevedi(oc, Xt) .>= 0.5
        append!(righe, DataFrame(tratta = d.tratta[ite], ibrido_prev = reg, m = ifelse.(reg, clamp.(prevedi(om, Xt), M_MIN, 1.0), 0.0),
                                 n = clamp.(ifelse.(reg, prevedi(oi, Xt), prevedi(ob, Xt)), N_MIN, 1.0),
                                 costo_prev = exp.(prevedi(ol, Xt))))
    end
    es = valuta_punti(righe.tratta, righe.m, righe.n)
    s = hcat(righe, es); leftjoin!(s, select(d, :tratta, :y_ibrido, :y_costo_EUR_km), on = :tratta)
    rp = (s.costo[s.fattibile] .- s.y_costo_EUR_km[s.fattibile]) ./ s.y_costo_EUR_km[s.fattibile]
    ec = abs.(s.costo_prev ./ s.y_costo_EUR_km .- 1)
    nt = dim == 0 ? round(Int, 1024 * 4 / 5) : dim
    push!(lc, (training = nt, errore_regime_pct = 100mean(s.ibrido_prev .!= (s.y_ibrido .== 1)), non_fattibili_pct = 100mean(.!s.fattibile),
               rimpianto_mediana_pct = 100median(rp), rimpianto_p95_pct = 100quantile(rp, 0.95),
               err_costo_mediana_pct = 100median(ec), err_costo_p95_pct = 100quantile(ec, 0.95)))
    r = lc[end, :]
    say(@sprintf("  training %4d: err. regime %4.1f%%, non fattibili %5.1f%%, rimpianto mediana %.3f%% p95 %.2f%%, costo diretto mediana %.2f%% p95 %.2f%%",
                 r.training, r.errore_regime_pct, r.non_fattibili_pct, r.rimpianto_mediana_pct, r.rimpianto_p95_pct, r.err_costo_mediana_pct, r.err_costo_p95_pct))
end
CSV.write(joinpath(RIS, "curva_apprendimento_$(FAM)_$(INS).csv"), lc)

# ── (3) dove si concentrano gli errori ──────────────────────────────────────
sim = CSV.read(joinpath(RIS, "sim_cv.csv"), DataFrame)
sim = sim[(sim.modello .== String(FAM)) .& (sim.insieme .== String(INS)), :]
leftjoin!(sim, select(d, :tratta, :y_massa_propulsione_kg, :y_SOC_fine, :y_durata_viaggio_s), on = :tratta)
frazione(x) = x - floor(x)
categorie = [
    ("limite di massa (≥ 99,9% di 29 250 kg)", s -> s.y_massa_propulsione_kg .>= 0.999 * 29250),
    ("limite di SOC (SOC* < 0,2005)", s -> s.y_SOC_fine .< 0.2005),
    ("sotto entrambi i limiti", s -> (s.y_massa_propulsione_kg .>= 0.999 * 29250) .& (s.y_SOC_fine .< 0.2005)),
    ("lontano da entrambi i limiti", s -> (s.y_massa_propulsione_kg .< 0.999 * 29250) .& (s.y_SOC_fine .>= 0.2005)),
    ("vicino a D20 (|m* − 0,1195| < 0,01)", s -> (s.y_ibrido .== 1) .& (abs.(s.y_m_star .- 0.1195) .< 0.01)),
    ("vicino a m_min (0,03 < m* < 0,04)", s -> (s.y_ibrido .== 1) .& (s.y_m_star .< 0.04)),
    ("vicino a un salto dei viaggi al giorno (|frazione(36000/durata) − 0,5| < 0,05)", s -> abs.(frazione.(36000 ./ s.y_durata_viaggio_s) .- 0.5) .< 0.05),
    ("ibride", s -> s.y_ibrido .== 1), ("sola batteria", s -> s.y_ibrido .== 0), ("tutte", s -> trues(nrow(s))),
]
ec = DataFrame()
say("\n(3) errori per categoria dell'ottimo vero ($(FAM), $(INS), 5 ripetizioni)")
for (nome, fsel) in categorie
    s = sim[fsel(sim), :]
    rp = s.rimpianto[s.fattibile]
    push!(ec, (categoria = nome, tratte = length(unique(s.tratta)), errore_regime_pct = 100mean(s.ibrido_prev .!= (s.y_ibrido .== 1)),
               non_fattibili_pct = 100mean(.!s.fattibile), nf_SOC_pct = 100mean(s.viol_SOC), nf_massa_pct = 100mean(s.viol_massa),
               rimpianto_mediana_pct = isempty(rp) ? NaN : 100median(rp), rimpianto_p95_pct = isempty(rp) ? NaN : 100quantile(rp, 0.95)))
    r = ec[end, :]
    say(@sprintf("  %-82s %4d tratte | err. regime %5.1f%% | non fatt. %5.1f%% (SOC %5.1f, massa %5.1f) | rimpianto med %.3f%% p95 %.2f%%",
                 r.categoria, r.tratte, r.errore_regime_pct, r.non_fattibili_pct, r.nf_SOC_pct, r.nf_massa_pct, r.rimpianto_mediana_pct, r.rimpianto_p95_pct))
end
CSV.write(joinpath(RIS, "errori_categorie_$(FAM)_$(INS).csv"), ec)
close(out)
