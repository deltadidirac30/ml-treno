# fase12/07_lisciatura.jl: le 166 linee della rete con l'altimetria lisciata (media mobile su 200 m, 500 m, 1 km). Cambiano
# simulatore e rete? (fase12/05: il gradino di quota di 0,1 m ogni 50 m delle linee gonfia i cicli di carico della fuel cell.)
#
#   julia -t 8 --project=fase12 fase12/07_lisciatura.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_07.txt 2>&1
#
# 1. Scrive train-powertrain/dati_rete/tratte_rete_attenuate/media_<W>/<linea>/: progressiva, stazioni e limiti copiati
#    identici da dati_rete/archivio/tratte_rete_20261110; altimetria = media della quota (lineare a tratti fra i punti) su
#    [x − w, x + w], w = min(W/2, distanza dai due capi), negli stessi punti. Le quote dei capi non cambiano.
# 2. Simula le 288 coppie della campagna su ogni variante, con la configurazione della campagna (come il passo 8c):
#    ~/Documents/lavoro/ml_treno_dati/fase12/sim_attenuate/media_<W>. La versione originale è sim_vere/rete_288.
# 3. Per ogni variante (originale compresa): ruvidezza del profilo; effetto sul simulatore (vita FC, cicli di carico, idrogeno,
#    costo e coppia migliore fra le 288); errori della rete come fase12/03 (caratteristiche ricalcolate sul profilo lisciato).

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "07_lisciatura.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/07_lisciatura.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_ORIG = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")
const DIR_ATT = joinpath(TPR, "dati_rete", "tratte_rete_attenuate")
const FINESTRE = [(200.0, "media_200m"), (500.0, "media_500m"), (1000.0, "media_1km")]
const SIM = joinpath(BASE, "fase12", "sim_attenuate")

# ── 1. le linee lisciate ─────────────────────────────────────────────────────────
leggi_valori(f) = [parse(Float64, strip(l)) for l in readlines(f) if !isempty(strip(l)) && !startswith(lstrip(l), '%')]
commenti(f) = [l for l in readlines(f) if startswith(lstrip(l), '%')]
"""Media della quota h (lineare a tratti sui punti p) su [x − w, x + w], w = min(W/2, distanza dai capi), in ogni punto."""
function liscia(p, h, W)
    N = length(p); I = zeros(N)
    for i in 2:N; I[i] = I[i-1] + (p[i] - p[i-1]) * (h[i] + h[i-1]) / 2; end
    function integ(x)                       # ∫ da p[1] a x
        x <= p[1] && return 0.0
        x >= p[N] && return I[N]
        j = searchsortedlast(p, x); t = x - p[j]
        return I[j] + t * h[j] + (h[j+1] - h[j]) / (p[j+1] - p[j]) * t^2 / 2
    end
    return [(w = min(W / 2, p[i] - p[1], p[N] - p[i]); w <= 0 ? h[i] : (integ(p[i] + w) - integ(p[i] - w)) / (2w)) for i in 1:N]
end
nomi = sort([d for d in readdir(DIR_ORIG) if isdir(joinpath(DIR_ORIG, d))])
length(nomi) == 166 || error("attese 166 linee in $DIR_ORIG")
mkpath(DIR_ATT)
open(joinpath(DIR_ATT, "README.md"), "w") do io
    println(io, "# Linee della rete con l'altimetria lisciata\n")
    println(io, "Copie delle 166 linee di `../archivio/tratte_rete_20261110`, generate il ", Dates.format(now(), "dd/mm/yyyy"),
            " da `ml_treno/fase12/07_lisciatura.jl`. **Non modificare a mano**: si rigenerano con lo script.\n")
    println(io, "- `media_200m`, `media_500m`, `media_1km`: la quota in ogni punto è la media della quota originale (lineare a tratti fra i",
            " punti) su una finestra centrata di 200 m, 500 m o 1 km; vicino ai capolinea la finestra si stringe, così le quote dei capi",
            " non cambiano. Progressiva, stazioni e limiti sono identici agli originali.")
    println(io, "- Perché: le quote della mappa sono prese ogni 50 m e arrotondate a 0,1 m, quindi la pendenza salta di 2‰ avanti e indietro;",
            " il simulatore conta questi salti come cicli di carico della fuel cell (ml_treno, fase12/05_ruvidezza.jl).")
    println(io, "\nSi usano come le altre: `surrogato cartella=", DIR_ATT, "/media_500m tratta=tutte`.")
end
for (W, sotto) in FINESTRE, nome in nomi
    d = joinpath(DIR_ATT, sotto, nome); mkpath(d)
    for s in ("progressiva", "stazioni", "limiti")
        cp(joinpath(DIR_ORIG, nome, "$(nome)_$s.txt"), joinpath(d, "$(nome)_$s.txt"); force = true)
    end
    fa = joinpath(DIR_ORIG, nome, "$(nome)_altimetria.txt")
    p = leggi_valori(joinpath(DIR_ORIG, nome, "$(nome)_progressiva.txt")); h = leggi_valori(fa)
    length(p) == length(h) && issorted(p) || error("$nome: progressiva e altimetria incoerenti")
    hl = liscia(p, h, W)
    open(joinpath(d, "$(nome)_altimetria.txt"), "w") do io
        for c in commenti(fa); println(io, c); end
        println(io, @sprintf("%% lisciata: media mobile della quota su %.0f m (ml_treno/fase12/07_lisciatura.jl, %s)", W, Dates.format(now(), "yyyy-mm-dd")))
        for x in hl; println(io, repr(x)); end
    end
end
say(@sprintf("1. linee lisciate scritte in %s (%s): %.1f s", DIR_ATT, join(last.(FINESTRE), ", "), time() - T0))

# ── 2. il simulatore sulle varianti ──────────────────────────────────────────────
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end
VARIANTI = [("originale", DIR_ORIG, joinpath(BASE, "fase12", "sim_vere", "rete_288"))]
for (W, sotto) in FINESTRE
    t0 = time(); cart = joinpath(SIM, sotto)
    tc = leggi_tratte_reali(nomi; cartella = joinpath(DIR_ATT, sotto))
    spec = CampagnaSpec(tratte = tc, coppie = C288, cartella = cart, direzioni = ["andata&ritorno"], config = CFG_CAMP,
                        peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(cart, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $cart")
    push!(VARIANTI, (sotto, joinpath(DIR_ATT, sotto), cart))
    say(@sprintf("2. %s: 288 coppie × %d linee simulate in %.1f min", sotto, length(tc), (time() - t0) / 60))
end

# ── 3. confronto ─────────────────────────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
"""I casi del registro, per linea: (m, n) => grandezze del simulatore."""
function leggi_registro(cart)
    casi = Dict{String,Dict{Tuple{Float64,Float64},NamedTuple}}()
    for l in readlines(joinpath(cart, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        get!(casi, String(c["tratta"]), Dict{Tuple{Float64,Float64},NamedTuple}())[(pf(c["m"]), pf(c["n"]))] =
            (completato = c["stato"] == "completed", fattibile = c["tipo_esito"] == "fattibile",
             durata = pf(c["durata_viaggio_s"]), serbatoio = pf(c["massa_serbatoio_kg"]), H2 = pf(c["H2_cons_kg"]), SOC = pf(c["SOC_end"]),
             scarica = pf(c["scarica_s"]) > 1e-6, scarica_nota = isfinite(pf(c["scarica_s"])), vita_batt = pf(c["vita_batt_cicli_viaggi"]),
             vita_FC_f1 = pf(c["vita_FC_f1_ore"]), C_rate = pf(c["C_rate_scarica_max"]), costo = pf(c["total_cost_EUR_km"]),
             carico_h = pf(c["dV_cicli_carico_uV"]) / (pf(c["durata_viaggio_s"]) / 3600))
    end
    return casi
end
# mediana DoE (validazione) dei cicli di carico per ora, per coppia (come fase12/05)
cid(m, n) = (round(m; digits = 12), round(n; digits = 12))
const MED_CAR = let car = Dict{Tuple{Float64,Float64},Vector{Float64}}()
    for b in vcat(25:28, 45:48)
        t = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", @sprintf("blocco_%02d.arrow", b)))
        for i in eachindex(t.tratta)
            (t.stato[i] == 1 && t.m[i] > 0) || continue
            push!(get!(car, cid(t.m[i], t.n[i]), Float64[]), Float64(t.dV_cicli_carico_uV[i]) / (Float64(t.durata_viaggio_s[i]) / 3600))
        end
    end
    Dict(k => median(v) for (k, v) in car)
end
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1); ((XA .- μ) ./ σ, μ, σ)
end
media_blocchi(p, w) = [mean(@view p[(k-1)*w+1:k*w]) for k in 1:length(p)÷w]; tv(p) = sum(abs, diff(p))
const G = [(:durata, "durata", :rel), (:serbatoio, "serbatoio", :rel), (:H2, "idrogeno", :rel), (:SOC, "SOC finale", :abs),
           (:vita_batt, "vita batteria", :rel), (:vita_FC_f1, "vita FC (f1)", :rel), (:C_rate, "C-rate scarica", :rel), (:costo, "costo", :rel)]

ris = Dict{String,Any}(); per_linea = Dict{String,Vector{NamedTuple}}()
REG_ORIG = leggi_registro(VARIANTI[1][3])
for (nomev, cart_tratte, cart_sim) in VARIANTI
    reg = nomev == "originale" ? REG_ORIG : leggi_registro(cart_sim)
    tc = leggi_tratte_reali(nomi; cartella = cart_tratte)
    err = Dict(g[1] => Float64[] for g in G); vfc_segno = Float64[]; costo_segno = Float64[]
    ruv = NamedTuple[]; rapp_car = Float64[]; d_vita = Float64[]; d_H2 = Float64[]; d_costo288 = Float64[]
    camb_coppia = 0; camb_regime = 0; giusti_f = 0; tot_f = 0; dist = Float64[]
    righe = NamedTuple[]
    for t in tc
        nome = t.id; cs = reg[nome]; co = REG_ORIG[nome]
        pr = profilo_tratta(t.cp); p = pr.p; L = pr.L
        push!(ruv, (cambi = count(abs.(diff(p)) .> 0.01) / L, tv1 = tv(p) / L, tv100 = tv(media_blocchi(p, 100)) / L,
                    tv1k = tv(media_blocchi(p, 1000)) / L, disl = maximum(pr.h) - minimum(pr.h)))
        v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr)); X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
        push!(dist, sqrt(minimum(vec(sum((ZA .- ((X' .- MU) ./ SG)) .^ 2; dims = 2)))))
        m = [c[1] for c in C288]; n = [c[2] for c in C288]; N = 288
        d = Dati(ingressi(repeat(X', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
                 m, n, fill(X[IL], N), fill(X[IT], N), zeros(Int8, N))
        pp = previsioni(RETE, d, SC)
        q = (durata = pp.durata, serbatoio = pp.serbatoio, H2 = pp.H2, SOC = pp.SOC, scarica = pp.p_scarica .>= 0.5, vita_batt = pp.vita_batt,
             vita_FC_f1 = pp.vita_FC_f1, C_rate = pp.C_rate)
        v = valuta(m, n, fill(X[IL], N), q)
        efc = Float64[]; ecos = Float64[]
        for i in 1:N
            c = cs[C288[i]]; o = co[C288[i]]
            tot_f += 1; giusti_f += v.fattibile[i] == c.fattibile
            for (k, _, tipo) in G
                k in (:serbatoio, :H2, :vita_FC_f1) && m[i] == 0 && continue
                k in (:H2, :SOC) && !c.completato && continue
                k === :costo && !(c.fattibile && !v.d3[i]) && continue
                y = getproperty(c, k); yh = k === :costo ? v.costo_totale[i] : getproperty(pp, k)[i]
                (isfinite(y) && isfinite(yh)) || continue
                e = tipo === :rel ? 100(yh - y) / abs(y) : yh - y
                push!(err[k], abs(e))
                k === :vita_FC_f1 && (push!(vfc_segno, e); push!(efc, e))
                k === :costo && (push!(costo_segno, e); push!(ecos, e))
            end
            if m[i] > 0 && c.completato && o.completato
                push!(d_vita, 100(c.vita_FC_f1 / o.vita_FC_f1 - 1)); push!(d_H2, 100(c.H2 / o.H2 - 1))
                haskey(MED_CAR, cid(m[i], n[i])) && MED_CAR[cid(m[i], n[i])] > 0 && push!(rapp_car, c.carico_h / MED_CAR[cid(m[i], n[i])])
            end
        end
        # la coppia migliore fra le 288 (simulatore), qui e nell'originale
        fv = [cs[c].fattibile for c in C288]; cv = [cs[c].costo for c in C288]
        fo = [co[c].fattibile for c in C288]; cvo = [co[c].costo for c in C288]
        ib = argmin(ifelse.(fv, cv, Inf)); io = argmin(ifelse.(fo, cvo, Inf))
        push!(d_costo288, 100(cv[ib] / cvo[io] - 1))
        camb_coppia += ib != io; camb_regime += (m[ib] > 0) != (m[io] > 0)
        push!(righe, (linea = nome, distanza = dist[end], cambi_p_km = ruv[end].cambi, tv100 = ruv[end].tv100,
                      err_vita_FC = isempty(efc) ? NaN : median(efc), err_costo = isempty(ecos) ? NaN : median(ecos),
                      migliore_m = m[ib], migliore_n = n[ib], migliore_costo = cv[ib], rispetto_originale = d_costo288[end]))
    end
    per_linea[nomev] = righe
    ris[nomev] = (err = err, vfc = vfc_segno, cos = costo_segno, ruv = ruv, rapp = rapp_car, d_vita = d_vita, d_H2 = d_H2, d288 = d_costo288,
                  cc = camb_coppia, cr = camb_regime, fatt = 100giusti_f / tot_f, dist = dist)
end

nv = first.(VARIANTI)
col(f) = join((@sprintf("%12s", f(ris[x])) for x in nv), "")
say("\n", @sprintf("%-46s", ""), join((@sprintf("%12s", x) for x in nv), ""))
say("A. il profilo (mediana sulle linee)")
say(@sprintf("%-46s", "   cambi di pendenza per km"), col(r -> @sprintf("%.2f", median(x.cambi for x in r.ruv))))
say(@sprintf("%-46s", "   Σ|Δp| per km a 1 m [‰/km]"), col(r -> @sprintf("%.2f", median(x.tv1 for x in r.ruv))))
say(@sprintf("%-46s", "   Σ|Δp| per km, media su 100 m"), col(r -> @sprintf("%.2f", median(x.tv100 for x in r.ruv))))
say(@sprintf("%-46s", "   Σ|Δp| per km, media su 1 km"), col(r -> @sprintf("%.2f", median(x.tv1k for x in r.ruv))))
say(@sprintf("%-46s", "   dislivello [m]"), col(r -> @sprintf("%.1f", median(x.disl for x in r.ruv))))
say(@sprintf("%-46s", "   distanza dall'addestramento"), col(r -> @sprintf("%.2f", median(r.dist))))
say("   (DoE di validazione: cambi 0,67/km, Σ|Δp| 5,5 / 5,5 / 4,4 ‰/km)")
say("B. il simulatore (ibridi completati; rispetto all'originale)")
say(@sprintf("%-46s", "   cicli di carico / DoE alla stessa coppia"), col(r -> @sprintf("%.2f", median(r.rapp))))
say(@sprintf("%-46s", "   vita FC rispetto all'originale, mediana"), col(r -> @sprintf("%+.1f%%", median(r.d_vita))))
say(@sprintf("%-46s", "   idrogeno rispetto all'originale, mediana"), col(r -> @sprintf("%+.2f%%", median(r.d_H2))))
say(@sprintf("%-46s", "   migliore delle 288: costo vs originale, med."), col(r -> @sprintf("%+.2f%%", median(r.d288))))
say(@sprintf("%-46s", "   … 10° percentile (le linee che calano di più)"), col(r -> @sprintf("%+.2f%%", quantile(r.d288, 0.1))))
say(@sprintf("%-46s", "   … massimo"), col(r -> @sprintf("%+.2f%%", maximum(r.d288))))
say(@sprintf("%-46s", "   linee con un'altra coppia migliore"), col(r -> string(r.cc)))
say(@sprintf("%-46s", "   linee con un altro regime migliore"), col(r -> string(r.cr)))
say("C. la rete contro il simulatore (errore mediano su tutti i casi)")
for (k, nm, tipo) in G
    say(@sprintf("%-46s", "   " * nm), col(r -> tipo === :abs ? @sprintf("%.4f", median(r.err[k])) : @sprintf("%.2f%%", median(r.err[k]))))
end
say(@sprintf("%-46s", "   vita FC, con il segno (+ = rete più lunga)"), col(r -> @sprintf("%+.1f%%", median(r.vfc))))
say(@sprintf("%-46s", "   vita FC: casi con la rete più lunga"), col(r -> @sprintf("%.0f%%", 100mean(r.vfc .> 0))))
say(@sprintf("%-46s", "   costo, con il segno (+ = rete più cara)"), col(r -> @sprintf("%+.2f%%", median(r.cos))))
say(@sprintf("%-46s", "   costo, 95° percentile dell'errore"), col(r -> @sprintf("%.2f%%", quantile(r.err[:costo], 0.95))))
say(@sprintf("%-46s", "   fattibilità giusta"), col(r -> @sprintf("%.2f%%", r.fatt)))

open(joinpath(LOG, "07_lisciatura_linee.csv"), "w") do io
    println(io, "variante,linea,distanza,cambi_p_km,tv100_permille_km,err_vita_FC_pct,err_costo_pct,migliore_m,migliore_n,migliore_costo_EUR_km,migliore_rispetto_originale_pct")
    for x in nv, r in per_linea[x]
        println(io, join((x, r.linea, (@sprintf("%.5g", getproperty(r, k)) for k in (:distanza, :cambi_p_km, :tv100, :err_vita_FC, :err_costo,
                                                                                        :migliore_m, :migliore_n, :migliore_costo, :rispetto_originale))...), ','))
    end
end
say(@sprintf("\nTempo totale %.1f min. Tabella per linea: %s", (time() - T0) / 60, joinpath(LOG, "07_lisciatura_linee.csv")))
close(OUT)
