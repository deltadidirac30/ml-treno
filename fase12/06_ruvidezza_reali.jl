# fase12/06_ruvidezza_reali.jl: le misure di ruvidezza di 05_ruvidezza.jl, i cicli di carico e l'errore della rete sulla vita della FC
# sulle 3 tratte reali storiche (288 coppie da sim_vere/reale_*, già simulate nel passo 8b). Nessuna simulazione nuova.
#   julia -t 8 --project=fase12 fase12/06_ruvidezza_reali.jl "$PWD"   (dalla cartella ml_treno)
const ML = ARGS[1]
include(joinpath(ML, "fase9", "comune.jl")); include(joinpath(ML, "fase10", "comune.jl")); include(joinpath(ML, "fase1", "caratteristiche.jl"))
cid(m, n) = (round(m; digits = 12), round(n; digits = 12))
car = Dict{Tuple{Float64,Float64},Vector{Float64}}()
for b in vcat(25:28, 45:48)
    t = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", @sprintf("blocco_%02d.arrow", b)))
    for i in eachindex(t.tratta)
        (t.stato[i] == 1 && t.m[i] > 0) || continue
        push!(get!(car, cid(t.m[i], t.n[i]), Float64[]), Float64(t.dV_cicli_carico_uV[i]) / (Float64(t.durata_viaggio_s[i]) / 3600))
    end
end
MED = Dict(k => median(v) for (k, v) in car)
INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ',')); pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
media_blocchi(p, w) = [mean(@view p[(k-1)*w+1:k*w]) for k in 1:length(p)÷w]; tv(p) = sum(abs, diff(p))
RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
IL = findfirst(==(:x_L_km), NORM.nx); IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
println(@sprintf("%-12s %7s %10s %10s %10s %10s %12s %14s", "tratta", "L km", "cambi p/km", "Σ|Δp| 1m", "Σ|Δp| 100m", "Σ|Δp| 1km", "rapp. carico", "err. vita FC"))
for nome in ("Calabria", "Canavese", "Firenze")
    tc = only(leggi_tratte_reali([nome]; cartella = expanduser("~/Documents/lavoro/train-powertrain/tratte_reali")))
    pr = profilo_tratta(tc.cp); p = pr.p; L = pr.L
    v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr)); X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    rr = Float64[]; mm = Float64[]; nn = Float64[]; vv = Float64[]
    for l in readlines(joinpath(BASE, "fase12", "sim_vere", "reale_" * nome, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        (c["stato"] == "completed" && pf(c["m"]) > 0) || continue
        g = cid(pf(c["m"]), pf(c["n"])); haskey(MED, g) || continue          # solo le 288 coppie della campagna
        push!(rr, pf(c["dV_cicli_carico_uV"]) / (pf(c["durata_viaggio_s"]) / 3600) / MED[g])
        push!(mm, pf(c["m"])); push!(nn, pf(c["n"])); push!(vv, pf(c["vita_FC_f1_ore"]))
    end
    N = length(mm)
    d = Dati(ingressi(repeat(X', N, 1), mm, nn, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
             mm, nn, fill(X[IL], N), fill(X[IT], N), zeros(Int8, N))
    pv = previsioni(RETE, d, SC).vita_FC_f1
    e = 100 .* (pv ./ vv .- 1)
    println(@sprintf("%-12s %7.1f %10.2f %10.2f %10.2f %10.2f %12.2f   %+6.1f%% (|e| %.1f%%)", nome, L, count(abs.(diff(p)) .> 0.01) / L, tv(p) / L,
                     tv(media_blocchi(p, 100)) / L, tv(media_blocchi(p, 1000)) / L, median(rr), median(e), median(abs.(e))))
end
println("riferimento (05_ruvidezza): DoE validazione cambi 0,67/km, Σ|Δp| 5,5 / 5,5 / 4,4 ‰/km, rapporto 1,01; linee rete 23,4/km, 28,6 / 13,1 / 3,3 ‰/km, rapporto 2,39; errore vita FC linee +15,9% (|e| 15,7%)")
