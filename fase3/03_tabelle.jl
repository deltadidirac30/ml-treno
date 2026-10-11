# Fase 3, passo 3: tabelle di confronto per tratta. Valore vero (ottimo della fase 1, confermato con la forza bruta:
# fase1/dati/dataset_reali.csv), surrogato puro (a), surrogato + simulatore (b: rifinitura NOMAD-PB 200 dal punto
# previsto), errore relativo %. Insieme principale p69; p66 in una tabella riassuntiva.
# Uso, da ml_treno/fase3:   julia --project=. 03_tabelle.jl. Scrive risultati/tabelle_fase3.md e risultati/confronto_reali.csv.
using CSV, DataFrames, Printf
include(joinpath(@__DIR__, "..", "fase1", "uscite.jl"))       # VOCI
const TR = ["Calabria", "Canavese", "Firenze"]
v = CSV.read(joinpath(@__DIR__, "..", "fase1", "dati", "dataset_reali.csv"), DataFrame)
a = CSV.read(joinpath(@__DIR__, "risultati", "surrogato_reali.csv"), DataFrame)
b = CSV.read(joinpath(@__DIR__, "risultati", "simulatore_reali.csv"), DataFrame)
const RIGHE = [("regime", "regime", ""), ("m_star", "m", ""), ("n_star", "n", ""), ("P_nom_FC_kW", "P_nom FC", "kW"),
               ("C_batt_kWh", "C_batt", "kWh"), ("serbatoio_H2_kg", "serbatoio H2", "kg"), ("costo_EUR_km", "costo totale", "€/km"),
               [(x, x, "€/km") for x in VOCI]..., ("n_sost_FC", "sostituzioni FC", ""), ("n_sost_batt", "sostituzioni batteria", "")]
num(x) = x isa Number ? Float64(x) : NaN
f(x) = x isa AbstractString ? x : isnan(x) ? "—" : abs(x) >= 100 ? @sprintf("%.1f", x) : abs(x) >= 1 ? @sprintf("%.3f", x) : @sprintf("%.4f", x)
function err(p, t)
    (p isa AbstractString || t isa AbstractString) && return p == t ? "uguale" : "diverso"
    (isnan(p) || isnan(t)) && return "—"
    t == 0 && return p == 0 ? "0" : "—"
    return @sprintf("%+.1f%%", 100 * (p / t - 1))
end
io = IOBuffer(); lungo = DataFrame()
for ins in ("p69", "p66"), t in TR
    V = v[v.tratta .== t, :][1, :]; A = a[(a.insieme .== ins) .& (a.tratta .== t), :][1, :]
    B = b[(b.insieme .== ins) .& (b.tratta .== t) .& (b.partenza .== "previsto"), :][1, :]
    val(R, k, src) = k == "regime" ? (src === :b ? (R.fattibile_fin ? (R.m_fin > 0 ? "ibrido" : "sola_batteria") : "non fattibile") : String(R[Symbol(k == "regime" ? "regime" : k)])) :
                     k == "costo_EUR_km" ? (src === :a ? num(R.costo_ricostruito) : src === :b ? (R.fattibile_fin ? num(R.costo_EUR_km) : NaN) : num(R.y_costo_EUR_km)) :
                     src === :v ? num(R[Symbol("y_" * k)]) : (src === :b && !R.fattibile_fin) ? NaN : num(R[Symbol(k)])
    for (k, lab, u) in RIGHE
        vv = k == "regime" ? String(V.y_regime) : val(V, k, :v); aa = val(A, k, :a); bb = val(B, k, :b)
        push!(lungo, (insieme = ins, tratta = t, grandezza = lab, unita = u, vero = string(f(vv)), surrogato = string(f(aa)), err_surrogato = err(aa, vv),
                      simulatore = string(f(bb)), err_simulatore = err(bb, vv)))
    end
    push!(lungo, (insieme = ins, tratta = t, grandezza = "costo previsto dal processo gaussiano", unita = "€/km", vero = f(V.y_costo_EUR_km),
                  surrogato = f(A.costo_gp), err_surrogato = err(A.costo_gp, V.y_costo_EUR_km), simulatore = "", err_simulatore = ""))
end
CSV.write(joinpath(@__DIR__, "risultati", "confronto_reali.csv"), lungo)
for t in TR
    s = lungo[(lungo.insieme .== "p69") .& (lungo.tratta .== t), :]
    println(io, "\n### $t", t == "Calabria" ? " (profilo SEMPLIFICATO: quota tutta a zero, limite unico 130 km/h)" : "", "\n")
    println(io, "| grandezza | unità | vero | (a) surrogato | errore (a) | (b) + simulatore | errore (b) |\n|---|---|---:|---:|---:|---:|---:|")
    for r in eachrow(s); println(io, "| $(r.grandezza) | $(r.unita) | $(r.vero) | $(r.surrogato) | $(r.err_surrogato) | $(r.simulatore) | $(r.err_simulatore) |"); end
end
println(io, "\n### Confronto p66 (66 caratteristiche, senza din_)\n")
println(io, "| tratta | regime vero / (a) / (b) | m vero / (a) / (b) | n vero / (a) / (b) | costo vero | (a) processo gaussiano | (a) ricostruito | (b) |\n|---|---|---|---|---:|---:|---:|---:|")
for t in TR
    s = lungo[(lungo.insieme .== "p66") .& (lungo.tratta .== t), :]; g(x) = s[s.grandezza .== x, :][1, :]
    println(io, "| $t | $(g("regime").vero) / $(g("regime").surrogato) / $(g("regime").simulatore) | $(g("m").vero) / $(g("m").surrogato) / $(g("m").simulatore) | ",
            "$(g("n").vero) / $(g("n").surrogato) / $(g("n").simulatore) | $(g("costo totale").vero) | $(g("costo previsto dal processo gaussiano").surrogato) ($(g("costo previsto dal processo gaussiano").err_surrogato)) | ",
            "$(g("costo totale").surrogato) ($(g("costo totale").err_surrogato)) | $(g("costo totale").simulatore) ($(g("costo totale").err_simulatore)) |")
end
write(joinpath(@__DIR__, "risultati", "tabelle_fase3.md"), take!(io))
print(read(joinpath(@__DIR__, "risultati", "tabelle_fase3.md"), String))
