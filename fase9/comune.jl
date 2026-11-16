# fase9/comune.jl: il banco di prova del surrogato. Dalle 8 grandezze (vere o previste) di un caso (tratta, m, n):
# vincoli, fattibilità e costo con le regole del simulatore (TrainPowertrain.costo_da_grandezze, ConfigModello()).
# Nessuna simulazione. Le grandezze esatte da m e n (taglie di FC e batteria) vengono dalle stesse funzioni del
# simulatore, verificate al bit in fase 4 (§3.3).

using TrainPowertrain, Arrow, Statistics, Printf, Dates
const TP = TrainPowertrain

const BASE  = expanduser("~/Documents/lavoro/ml_treno_dati")
const TAB   = joinpath(BASE, "P9_D28_16384", "tabella")
const DIR_COPPIE = joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")
const CFG   = ConfigModello()                         # = config.txt della campagna (fase 5, passo 1b)
const V_NOM = 1500.0
const P_MAX = TP.Objective.P_MAX_DEF
const RIF   = TP.riferimento_batteria(195_000.0, V_NOM)
const LIMITE_MASSA = 0.15 * 195_000.0                 # 29 250 kg
const SOC_INIZIALE = 0.8
const SOGLIA_D3 = 20.0                                # C-rate di scarica oltre il quale il progetto è scartato (D3, a posteriori)

"""Taglie esatte da m e n (fase 4): P_nom e massa della FC, capacità ed energia e massa della batteria."""
function taglie(m, n)
    fc = m > 0 ? TP.taglia_FC_2(P_MAX * m, V_NOM; r = TP.rapporto_picco_fc()) : nothing
    bt = TP.taglia_batteria_da_n(n, RIF, V_NOM)
    return (P_nom = fc === nothing ? 0.0 : fc.P_nom_FC, massa_FC = fc === nothing ? 0.0 : fc.peso_totale_FC,
            C_batt = bt.E_batteria, massa_batt = bt.peso_totale_batteria, capacita = bt.Capacita_batteria)
end

"""
    valuta(m, n, L, q; d3 = nothing) -> NamedTuple di vettori

`q`: NamedTuple di vettori con le 8 grandezze di ogni caso: durata [s], serbatoio [kg], H2 [kg], SOC [-], scarica (Bool),
vita_batt [viaggi, cicli], vita_FC_f1 [h] (ignorata a m = 0), C_rate [-]. `d3`: esito D3 dato (Bool); se `nothing`, la
regola a posteriori C_rate > 20. Restituisce, per caso: d3, i tre vincoli violati (massa, SOC, scarica), fattibile, il
costo senza penalità (`costo_totale`, NaN se D3) e con penalità (`costo`, 20000 se D3).
"""
function valuta(m, n, L, q; d3 = nothing)
    N = length(m)
    tg = Dict{Tuple{Float64,Float64},Any}()
    for i in 1:N; get!(() -> taglie(m[i], n[i]), tg, (m[i], n[i])); end
    D3 = Vector{Bool}(d3 === nothing ? q.C_rate .> SOGLIA_D3 : d3)
    # Vector{Bool}, non BitVector: i thread scrivono elementi vicini, e un BitVector ne impacca 64 nella stessa parola
    vm = fill(false, N); vs = fill(false, N); vsc = fill(false, N); ct = fill(NaN, N); c = fill(NaN, N)
    Threads.@threads :dynamic for i in 1:N
        t = tg[(m[i], n[i])]
        massa = t.massa_batt + t.massa_FC + q.serbatoio[i]
        soc = q.SOC[i]
        vm[i] = massa > LIMITE_MASSA; vs[i] = soc < 0.2; vsc[i] = q.scarica[i]
        D3[i] && (c[i] = 20000.0; continue)
        g = Dict{String,Float64}(
            "m" => m[i], "n" => n[i], "P_nom_fc_kW" => t.P_nom, "C_batt_kWh" => t.C_batt,
            "H2_serbatoio_kg" => 0.055 * q.serbatoio[i], "km_viaggio" => 2 * L[i],
            "n_viaggi_giorno" => TP.matlab_round(36000 / (q.durata[i] + 1)),
            "E_ricarica_rete_kWh" => ((SOC_INIZIALE - soc) * t.capacita * V_NOM) / 1000.0,
            "H2_cons_kg" => q.H2[i], "SOC_end" => soc, "vita_batt_cicli_viaggi" => q.vita_batt[i],
            "vita_FC_viaggi" => NaN, "vita_FC_f1_ore" => m[i] > 0 ? q.vita_FC_f1[i] : Inf, "durata_viaggio_s" => q.durata[i],
            "f_degrado_FC" => CFG.f_degrado_fc, "ore_max_FC" => CFG.ore_max_fc, "massa_propulsione_kg" => massa,
            "limite_massa_propulsione_kg" => LIMITE_MASSA, "scarica_s" => q.scarica[i] ? 1.0 : 0.0)
        r = costo_da_grandezze(g, ParametriCosto(); cfg = CFG, vita_fc_da_f1 = true)
        ct[i] = r.costo_totale; c[i] = r.costo
    end
    fatt = .!D3 .& .!vm .& .!vs .& .!vsc
    return (d3 = D3, viol_massa = vm, viol_soc = vs, viol_scarica = vsc, fattibile = fatt, costo_totale = ct, costo = c)
end

const NOMI_Q = (:durata, :serbatoio, :H2, :SOC, :scarica, :vita_batt, :vita_FC_f1, :C_rate)
"""Le grandezze vere della tabella (fase 6) nella forma di `valuta`."""
function grandezze_vere(t)
    return (durata = collect(t.y_durata_viaggio_s), serbatoio = collect(t.y_massa_serbatoio_kg), H2 = collect(t.y_H2_cons_kg),
            SOC = collect(t.y_SOC_end), scarica = collect(t.y_scarica_s) .> 1e-6, vita_batt = collect(t.y_vita_batt_cicli_viaggi),
            vita_FC_f1 = collect(t.y_vita_FC_f1_ore), C_rate = collect(t.y_C_rate_scarica_max))
end
"""Sostituisce in `q` la grandezza `k` con quella di `v`."""
sostituisci(q, v, k) = merge(q, NamedTuple{(k,)}((getproperty(v, k),)))
