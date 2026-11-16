# fase12/05_ruvidezza.jl: perché le linee della rete fanno più cicli di carico della fuel cell delle tratte DoE (fase12/04).
#
#   julia -t 8 --project=fase12 fase12/05_ruvidezza.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_05.txt 2>&1
#
# Ipotesi: il profilo delle linee reali è più "ruvido" a corto raggio (la pendenza cambia spesso), quindi la potenza chiesta e
# quella della FC salgono e scendono di più; nessuna delle 66 caratteristiche lo misura. Per ogni tratta:
#   - il rapporto dei cicli di carico: mediana sulle coppie ibride completate di (voce "cicli di carico" per ora di viaggio) /
#     (mediana delle tratte DoE di validazione alla stessa coppia);
#   - misure di ruvidezza del profilo, dalla pendenza metro per metro come la vede il simulatore (profilo_tratta, fase 1):
#     variazione totale della pendenza Σ|Δp| per km, a 1 m e dopo una media su 100 m e su 1 km; numero di cambi di pendenza
#     per km; e, dalle 66 caratteristiche, cambi di segno della pendenza e dei limiti per km e densità delle fermate.
# Tratte: le 166 linee e 512 tratte DoE di validazione (gruppo 7, route 6145–6656). Nessuna simulazione nuova.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "05_ruvidezza.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/05_ruvidezza.jl  ", now())
const DIR_ARROW = joinpath(BASE, "P9_D28_16384", "arrow")
const DIR_RETE = expanduser("~/Documents/lavoro/train-powertrain/dati_rete/archivio/tratte_rete_20261110")
const DOE_IDS = 6145:6656
cid(m, n) = (round(m; digits = 12), round(n; digits = 12))

# ── la voce "cicli di carico" per ora, per caso ─────────────────────────────────
car_doe = Tuple{Int,Tuple{Float64,Float64},Float64}[]          # (tratta, coppia, µV/h) — tutta la validazione, per le mediane
for b in vcat(25:28, 45:48)
    t = Arrow.Table(joinpath(DIR_ARROW, @sprintf("blocco_%02d.arrow", b)))
    for i in eachindex(t.tratta)
        (t.stato[i] == 1 && t.m[i] > 0) || continue
        push!(car_doe, (Int(t.tratta[i]), cid(t.m[i], t.n[i]), Float64(t.dV_cicli_carico_uV[i]) / (Float64(t.durata_viaggio_s[i]) / 3600)))
    end
end
const MED = Dict(g => median(x[3] for x in v) for (g, v) in
                 (g => [x for x in car_doe if x[2] == g] for g in unique(x[2] for x in car_doe)))
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
car_lin = Tuple{String,Tuple{Float64,Float64},Float64}[]
for l in readlines(joinpath(BASE, "fase12", "sim_vere", "rete_288", "registro.csv"))[2:end]
    c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
    (c["stato"] == "completed" && pf(c["m"]) > 0) || continue
    push!(car_lin, (String(c["tratta"]), cid(pf(c["m"]), pf(c["n"])), pf(c["dV_cicli_carico_uV"]) / (pf(c["durata_viaggio_s"]) / 3600)))
end
rapporto(v) = median(x[3] / MED[x[2]] for x in v if haskey(MED, x[2]) && MED[x[2]] > 0)

# ── la ruvidezza del profilo ─────────────────────────────────────────────────────
function media_a_blocchi(p, w)
    nb = length(p) ÷ w
    return [mean(@view p[(k-1)*w+1:k*w]) for k in 1:nb]
end
tv(p) = sum(abs, diff(p))
function ruvidezza(cp)
    pr = profilo_tratta(cp)
    v = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    f(nm) = v[findfirst(==(nm), vcat(NOMI_ORIG, NOMI_NUOVE))]
    L = pr.L; p = pr.p
    return (L = L, tv_1m = tv(p) / L, tv_100m = tv(media_a_blocchi(p, 100)) / L, tv_1km = tv(media_a_blocchi(p, 1000)) / L,
            cambi_p = count(abs.(diff(p)) .> 0.01) / L, segno_p = f("slope_sign_changes_per_km"), cambi_v = f("vlim_changes_per_km"),
            fermate = f("stops_density"), pend_rms = f("slope_rms"))
end
const MISURE = (:tv_1m, :tv_100m, :tv_1km, :cambi_p, :segno_p, :cambi_v, :fermate, :pend_rms)
const NOMI_MIS = ("Σ|Δp| per km, a 1 m [‰/km]", "Σ|Δp| per km, media su 100 m", "Σ|Δp| per km, media su 1 km",
                  "cambi di pendenza per km", "cambi di segno della pendenza per km (car.)", "cambi di limite per km (car.)",
                  "fermate per km (car.)", "pendenza rms (car.)")

righe = NamedTuple[]
for tc in leggi_tratte_reali(sort(unique(x[1] for x in car_lin)); cartella = DIR_RETE)
    push!(righe, merge((tipo = "linea", nome = tc.id, rapp = rapporto([x for x in car_lin if x[1] == tc.id])), ruvidezza(tc.cp)))
end
for tc in leggi_tratte_materializzate(joinpath(BASE, "tratte_doe_16384"); solo = Set(DOE_IDS))
    r = parse(Int, tc.id[7:end])
    v = [x for x in car_doe if x[1] == r]; isempty(v) && continue
    push!(righe, merge((tipo = "DoE", nome = tc.id, rapp = rapporto(v)), ruvidezza(tc.cp)))
end
L_ = [r for r in righe if r.tipo == "linea"]; D_ = [r for r in righe if r.tipo == "DoE"]
say(@sprintf("tratte: %d linee, %d DoE di validazione", length(L_), length(D_)))

rk(v) = invperm(sortperm(v)); spear(a, b) = cor(Float64.(rk(a)), Float64.(rk(b)))
say("\n1. Rapporto dei cicli di carico (tratta / mediana DoE alla stessa coppia):")
say(@sprintf("   DoE: mediana %.2f (10° %.2f, 90° %.2f)   linee: mediana %.2f (10° %.2f, 90° %.2f)",
             median(r.rapp for r in D_), quantile([r.rapp for r in D_], 0.1), quantile([r.rapp for r in D_], 0.9),
             median(r.rapp for r in L_), quantile([r.rapp for r in L_], 0.1), quantile([r.rapp for r in L_], 0.9)))
say("\n2. Le misure di ruvidezza: valori (mediana) e correlazione di rango con il rapporto dei cicli di carico")
say(@sprintf("   %-44s %10s %10s %10s   %8s %8s %8s", "misura", "DoE", "linee", "linee/DoE", "ρ DoE", "ρ linee", "ρ tutte"))
for (k, nm) in zip(MISURE, NOMI_MIS)
    a = median(getproperty(r, k) for r in D_); b = median(getproperty(r, k) for r in L_)
    say(@sprintf("   %-44s %10.3f %10.3f %10.2f   %+8.2f %+8.2f %+8.2f", nm, a, b, b / a,
                 spear([r.rapp for r in D_], [getproperty(r, k) for r in D_]), spear([r.rapp for r in L_], [getproperty(r, k) for r in L_]),
                 spear([r.rapp for r in righe], [getproperty(r, k) for r in righe])))
end
# le linee stanno sulla stessa relazione del DoE? rapporto per fasce della misura migliore
let k = :tv_100m
    say("\n3. Rapporto dei cicli di carico per fasce di Σ|Δp| per km (media su 100 m), DoE e linee:")
    q = quantile([getproperty(r, k) for r in righe], 0:0.2:1)
    for i in 1:5
        sel(R) = [r.rapp for r in R if q[i] <= getproperty(r, k) <= q[i+1]]
        d = sel(D_); l = sel(L_)
        say(@sprintf("   %7.1f–%7.1f ‰/km:  DoE %3d tratte, rapporto %s   linee %3d, rapporto %s", q[i], q[i+1], length(d),
                     isempty(d) ? "  —  " : @sprintf("%.2f", median(d)), length(l), isempty(l) ? "  —  " : @sprintf("%.2f", median(l))))
    end
end
open(joinpath(LOG, "05_ruvidezza.csv"), "w") do io
    println(io, "tipo,tratta,rapporto_cicli_carico,", join(MISURE, ','), ",L_km")
    for r in righe; println(io, join((r.tipo, r.nome, (@sprintf("%.5g", getproperty(r, k)) for k in (:rapp, MISURE..., :L))...), ',')); end
end
close(OUT)
