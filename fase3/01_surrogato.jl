# Fase 3, passo 1: modelli finali e surrogato puro sulle tratte reali Calabria, Canavese, Firenze.
# Modelli addestrati su TUTTE le 1024 tratte DoE del riferimento v2 (fase2bis/dati/dataset_doe_v2.csv), iperparametri
# scelti con la CV interna a 3 fold (fase2bis/comune.jl: adatta_scelto), per le 69 e per le 66 caratteristiche:
#   boosting (EvoTrees)  regime (tutte), m* (ibride), n* (ibride; sola batteria), e le grandezze fisiche in log:
#                        H2 per viaggio e H2 del serbatoio (ibride), energia di ricarica per viaggio, durata del
#                        viaggio, vita della batteria in viaggi (tutte), vita della FC in viaggi (ibride);
#                        D15 (sostituzione FC saltata): 0 in tutte le 1024 tratte, il modello è la costante 0;
#   processo gaussiano   log del costo €/km (tutte).
# Punto previsto come in fase 2: ibrido se p ≥ 0,5; m = clamp(m̂, 0,03, 1), 0 se sola batteria; n = clamp(n̂, 0,005, 1).
# Surrogato puro (nessuna valutazione del progetto): P_nom_FC e C_batt dalle formule del simulatore (reali.jl: taglie);
# viaggi al giorno = round(36000 / durata prevista), km all'anno dalla lunghezza; vite in anni = vite in viaggi /
# viaggi all'anno; 10 voci, costo e sostituzioni con costo_ricostruito (fase1/uscite.jl).
#
# Uso, da ml_treno/fase3:   julia -t 8 --project=. 01_surrogato.jl
# Scrive risultati/surrogato_reali.csv (una riga per insieme e tratta) e risultati/iperparametri.csv.

include(joinpath(@__DIR__, "..", "fase2bis", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "uscite.jl"))
include(joinpath(@__DIR__, "reali.jl"))

const SEME_FINALE = 20261013
d  = dati(); ibr = d.y_ibrido .== 1
all(==(0.0), d.y_D15_sost_saltata) || error("D15: sostituzione saltata presente nel DoE, serve un modello")
dr = CSV.read(joinpath(FASE1, "dataset_reali.csv"), DataFrame)
dr = dr[[findfirst(==(t), dr.tratta) for t in TRATTE], :]
R  = tratte_reali()

# (nome, tipo, sottoinsieme, trasformazione)
const BERSAGLI = [("regime", :cls, :tutte, :id), ("m_star", :reg, :ibride, :id), ("n_star_ibride", :reg, :ibride, :id),
                  ("n_star_batteria", :reg, :batteria, :id), ("H2_viaggio_kg", :reg, :ibride, :log),
                  ("serbatoio_H2_kg", :reg, :ibride, :log), ("E_ricarica_viaggio_kWh", :reg, :tutte, :log),
                  ("durata_viaggio_s", :reg, :tutte, :log), ("vita_batt_viaggi", :reg, :tutte, :log),
                  ("vita_FC_viaggi", :reg, :ibride, :log)]
colonna_y(nome) = nome == "regime" ? Float64.(ibr) : startswith(nome, "n_star") ? d.y_n_star : d[!, "y_" * nome]

righe = DataFrame(); hpt = DataFrame()
for ins in (:p69, :p66)
    cols = colonne(d, ins); X = matrice(d, cols); Xr = matrice(dr, cols)
    P = Dict{String,Vector{Float64}}()
    for (nome, tipo, sub, tr) in BERSAGLI
        sel = sub === :tutte ? trues(nrow(d)) : sub === :ibride ? ibr : .!ibr
        y = colonna_y(nome)[sel]; y = tr === :log ? log.(y) : y
        o, hp = adatta_scelto(:gb, tipo, X[sel, :], y; seme = SEME_FINALE)
        p = prevedi(o, Xr); P[nome] = tr === :log ? exp.(p) : p
        push!(hpt, (insieme = String(ins), bersaglio = nome, addestramento = count(sel), iperparametri = join(["$k=$v" for (k, v) in pairs(hp)], ";")))
        println(ins, " ", nome, " ", hp); flush(stdout)
    end
    gp = adatta_gp(X, log.(d.y_costo_EUR_km)); P["costo_gp"] = exp.(prevedi(gp, Xr))
    push!(hpt, (insieme = String(ins), bersaglio = "costo (processo gaussiano)", addestramento = nrow(d), iperparametri = "ARD-SE a massima verosimiglianza"))
    for (k, t) in enumerate(TRATTE)
        I = P["regime"][k] >= 0.5
        m = I ? clamp(P["m_star"][k], M_MIN, 1.0) : 0.0
        n = clamp(I ? P["n_star_ibride"][k] : P["n_star_batteria"][k], N_MIN, 1.0)
        tg = taglie(R[t].cp, R[t].pre, m, n)
        v_g = Float64(matlab_round(36000 / P["durata_viaggio_s"][k])); v_a = v_g * 365
        km_v = 2 * R[t].cp.lunghezza_binario_andata / 1000
        g = Dict("m_star" => m, "n_star" => n, "P_nom_FC_kW" => tg.P_nom_FC_kW, "C_batt_kWh" => tg.C_batt_kWh,
                 "serbatoio_H2_kg" => I ? P["serbatoio_H2_kg"][k] : 0.0, "H2_viaggio_kg" => I ? P["H2_viaggio_kg"][k] : 0.0,
                 "E_ricarica_viaggio_kWh" => P["E_ricarica_viaggio_kWh"][k], "durata_viaggio_s" => P["durata_viaggio_s"][k],
                 "viaggi_giorno" => v_g, "km_viaggio" => km_v, "km_anno" => v_a * km_v,
                 "vita_FC_viaggi" => I ? P["vita_FC_viaggi"][k] : Inf, "vita_FC_anni" => I ? P["vita_FC_viaggi"][k] / v_a : Inf,
                 "vita_batt_viaggi" => P["vita_batt_viaggi"][k], "vita_batt_anni" => P["vita_batt_viaggi"][k] / v_a,
                 "D15_sost_saltata" => 0.0, "D15_H2_coda_kg" => NaN)
        c, voci = costo_ricostruito(g)
        riga = Dict{Symbol,Any}(:insieme => String(ins), :tratta => t, :semplificata => dr.semplificata[k], :p_ibrido => P["regime"][k],
                                :m_prev_ibrido => P["m_star"][k], :n_prev_ibrido => P["n_star_ibride"][k], :n_prev_batteria => P["n_star_batteria"][k],
                                :regime => I ? "ibrido" : "sola_batteria", :costo_gp => P["costo_gp"][k], :costo_ricostruito => c)
        for (a, b) in g; riga[Symbol(a)] = b; end
        for (a, b) in voci; riga[Symbol(a)] = b; end
        push!(righe, NamedTuple(riga); cols = :union)
    end
end
CSV.write(joinpath(@__DIR__, "risultati", "surrogato_reali.csv"), righe)
CSV.write(joinpath(@__DIR__, "risultati", "iperparametri.csv"), hpt)
show(select(righe, :insieme, :tratta, :p_ibrido, :regime, :m_star, :n_star, :P_nom_FC_kW, :C_batt_kWh, :costo_gp, :costo_ricostruito, :n_sost_FC, :n_sost_batt), allcols = true)
