# fase12/11_rete_rinf.jl: le 166 linee della rete ricostruite dai dati sorgente (Drive condiviso SurrogateTrains, livellette RINF e
# fermate dell'orario) e il surrogato su di esse, accanto alle versioni dalla mappa HTML (originale e lisciata a 200 m).
#
#   julia -t 8 --project=fase12 fase12/11_rete_rinf.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_11.txt 2>&1
#
# Sorgente: copia locale del Drive in ~/Documents/lavoro/ml_treno_dati/linee_rinf_sorgente/<regione>/<linea>/ (altimetria.csv,
# fermate.csv, velocita_tratti.csv). Scrive train-powertrain/dati_rete/tratte_rete_rinf/:
#   profilo_rinf  quota dalle livellette RINF (punti di altimetria.csv), stazioni e limiti della mappa (archivio/tratte_rete_20261110);
#   tutto_rinf    quota, fermate (fermate.csv) e limiti (velocita_tratti.csv) dal Drive. Le soste per fermata non sono
#                 rappresentabili: il simulatore usa 120 s per fermata e 300 s al capolinea, come per tutte le tratte.
# Poi, per le 4 versioni (mappa, mappa 200 m, profilo RINF, tutto RINF): il simulatore sulle 288 coppie (le due RINF simulate qui) e
# il surrogato come fase12/08: errori per grandezza sulle 288 coppie, scelta del progetto (griglia fitta + margine + verifiche)
# contro la migliore delle 288, regime, errori nel progetto proposto. Tutte le linee e le sole non elettrificate oltre il 70%.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "11_rete_rinf.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/11_rete_rinf.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_HTML = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")
const SRC = joinpath(BASE, "linee_rinf_sorgente")
const DIR_RINF = joinpath(TPR, "dati_rete", "tratte_rete_rinf")

# ── 1. costruzione delle linee dai dati sorgente ─────────────────────────────────
function leggi_csv(f)
    l = readlines(f); h = split(l[1], ',')
    return [Dict(String(h[j]) => String(x) for (j, x) in enumerate(split(r, ','))) for r in l[2:end] if !isempty(strip(r))]
end
nonc(f) = [l for l in readlines(f) if !startswith(lstrip(l), '%') && !isempty(strip(l))]
sorgente = Dict{String,String}()
for reg in readdir(SRC), l in (isdir(joinpath(SRC, reg)) ? readdir(joinpath(SRC, reg)) : String[])
    isfile(joinpath(SRC, reg, l, "altimetria.csv")) && (sorgente[l] = joinpath(SRC, reg, l))
end
nomi_html = sort([d for d in readdir(DIR_HTML) if isdir(joinpath(DIR_HTML, d))])
oggi = Dates.format(now(), "yyyy-mm-dd")
function scrivi(sotto, linea, s, q, stazioni, limiti, nota)
    d = joinpath(DIR_RINF, sotto, linea); mkpath(d)
    int = "% $(linea): dal Drive condiviso SurrogateTrains ($(nota)), ml_treno/fase12/11_rete_rinf.jl, $(oggi)"
    open(io -> (println(io, int); foreach(x -> println(io, repr(x)), s)), joinpath(d, "$(linea)_progressiva.txt"), "w")
    open(io -> (println(io, int); foreach(x -> println(io, repr(x)), q)), joinpath(d, "$(linea)_altimetria.txt"), "w")
    open(io -> (println(io, int); foreach(x -> println(io, x), stazioni)), joinpath(d, "$(linea)_stazioni.txt"), "w")
    open(io -> (println(io, int); foreach(x -> println(io, x), limiti)), joinpath(d, "$(linea)_limiti.txt"), "w")
end
"""Il profilo RINF (punti strettamente crescenti), esteso con la pendenza dell'ultimo tratto fino ad almeno `Lmin` [m]."""
function profilo(src, Lmin)
    a = leggi_csv(joinpath(src, "altimetria.csv"))
    s = Float64[]; q = Float64[]
    for r in a
        x = round(1000parse(Float64, r["s_km"]); digits = 3); h = parse(Float64, r["quota_m"])   # al millimetro: 1000·32.004 = 32003.999…
        (isempty(s) || x > s[end] + 1e-6) && (push!(s, x); push!(q, h))
    end
    if s[end] < Lmin - 1e-6
        g = (q[end] - q[end-1]) / (s[end] - s[end-1]); push!(q, q[end] + g * (Lmin - s[end])); push!(s, Lmin)
    end
    return s, q
end
"""Limiti contigui da 0 a L (interi, m)."""
function limiti_contigui(righe, L)
    out = String[]; a = 0
    for (k, r) in enumerate(righe)
        b = k == length(righe) ? max(round(Int, 1000parse(Float64, r["s_fine_km"])), L) : round(Int, 1000parse(Float64, r["s_fine_km"]))
        b > a && push!(out, @sprintf("%d %d %s", a, b, r["vmax_kmh"])); a = b
    end
    return out
end
problemi = Tuple{String,String}[]
costruite = String[]
capolinea_aggiunti = String[]
for linea in nomi_html
    try
        haskey(sorgente, linea) || error("nessuna cartella sorgente")
        st_html = nonc(joinpath(DIR_HTML, linea, "$(linea)_stazioni.txt")); lim_html = nonc(joinpath(DIR_HTML, linea, "$(linea)_limiti.txt"))
        L_html = parse(Float64, st_html[end])
        # profilo RINF + stazioni e limiti della mappa
        s, q = profilo(sorgente[linea], L_html)
        abs(s[end] - L_html) > 0.02L_html && error(@sprintf("lunghezza RINF %.0f m contro %.0f della mappa", s[end], L_html))
        scrivi("profilo_rinf", linea, s, q, st_html, lim_html, "quota delle livellette RINF; stazioni e limiti della mappa")
        # tutto dal Drive
        fer = leggi_csv(joinpath(sorgente[linea], "fermate.csv"))
        st = unique([round(Int, 1000parse(Float64, r["s_km"])) for r in fer]); sort!(st)
        st[1] == 0 || pushfirst!(st, 0)
        # se le fermate dell'orario finiscono prima della fine della linea (Edolo–Brescia e Sale Marasino–Brescia finiscono a
        # Iseo), il capolinea si mette a fine linea, dove finiscono profilo e limiti
        L_fin = round(Int, max(1000parse(Float64, leggi_csv(joinpath(sorgente[linea], "velocita_tratti.csv"))[end]["s_fine_km"]),
                               round(1000parse(Float64, leggi_csv(joinpath(sorgente[linea], "altimetria.csv"))[end]["s_km"]); digits = 3)))
        if st[end] < L_fin - 50
            push!(capolinea_aggiunti, @sprintf("%s: fermate fino a %.3f km, capolinea aggiunto a %.3f km", linea, st[end] / 1000, L_fin / 1000))
            push!(st, L_fin)
        end
        s2, q2 = profilo(sorgente[linea], st[end])
        lim = limiti_contigui(leggi_csv(joinpath(sorgente[linea], "velocita_tratti.csv")), st[end])
        scrivi("tutto_rinf", linea, s2, q2, string.(st), lim, "quota, fermate e limiti dai dati sorgente")
        leggi_tratte_reali([linea]; cartella = joinpath(DIR_RINF, "profilo_rinf")); leggi_tratte_reali([linea]; cartella = joinpath(DIR_RINF, "tutto_rinf"))
        push!(costruite, linea)
    catch e
        push!(problemi, (linea, first(sprint(showerror, e), 150)))
    end
end
open(joinpath(DIR_RINF, "README.md"), "w") do io
    println(io, "# Linee della rete costruite dai dati sorgente RINF\n")
    println(io, "Generate il $(oggi) da `ml_treno/fase12/11_rete_rinf.jl` dalla copia locale del Drive condiviso SurrogateTrains",
            " (`Linee Ferroviarie/01 - Italia/Linee/<regione>/<linea>`). **Non modificare a mano.**\n")
    println(io, "- `profilo_rinf`: quota dai punti di `altimetria.csv` (inizi delle livellette RINF, a piena precisione); stazioni e limiti identici a `../archivio/tratte_rete_20261110` (la mappa HTML).")
    println(io, "- `tutto_rinf`: anche fermate (`fermate.csv`, quelle dell'orario) e limiti (`velocita_tratti.csv`). Le soste per fermata non sono rappresentabili nel formato a 4 file.")
    println(io, "\nLinee costruite: $(length(costruite)) su $(length(nomi_html)).")
    isempty(capolinea_aggiunti) || (println(io, "\nFermate dell'orario che finiscono prima della fine della linea (capolinea aggiunto a fine linea in `tutto_rinf`):"); foreach(x -> println(io, "- ", x), capolinea_aggiunti))
    isempty(problemi) || (println(io, "\nNon costruite:"); foreach(p -> println(io, "- ", p[1], ": ", p[2]), problemi))
end
say(@sprintf("1. linee costruite: %d su %d (%.1f s)", length(costruite), length(nomi_html), time() - T0))
for p in problemi; say("   non costruita: ", p[1], ": ", p[2]); end
for x in capolinea_aggiunti; say("   ", x); end

# ── 2. simulatore sulle 288 coppie delle versioni RINF ──────────────────────────
const CFG_CAMP = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
const DESC_CAMP = strip(read(joinpath(BASE, "P9_D28_16384", "raw", "P9_D28_16384", "blocco_01", "config.txt"), String))
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end
const VERSIONI = [("mappa", DIR_HTML, joinpath(BASE, "fase12", "sim_vere", "rete_288")),
                  ("mappa 200 m", joinpath(TPR, "dati_rete", "tratte_rete_attenuate", "media_200m"), joinpath(BASE, "fase12", "sim_attenuate", "media_200m")),
                  ("profilo RINF", joinpath(DIR_RINF, "profilo_rinf"), joinpath(BASE, "fase12", "sim_rinf", "profilo_rinf")),
                  ("tutto RINF", joinpath(DIR_RINF, "tutto_rinf"), joinpath(BASE, "fase12", "sim_rinf", "tutto_rinf"))]
for (nv, cart, dir) in VERSIONI[3:4]
    t0 = time()
    spec = CampagnaSpec(tratte = leggi_tratte_reali(costruite; cartella = cart), coppie = C288, cartella = dir, direzioni = ["andata&ritorno"],
                        config = CFG_CAMP, peso_a_carico = 195_000.0, modalita = :griglia)
    redirect_stdout(devnull) do; esegui_campagna(spec); end
    strip(read(joinpath(dir, "config.txt"), String)) == DESC_CAMP || error("config.txt diverso dalla campagna in $dir")
    say(@sprintf("2. %s: 288 coppie × %d linee simulate in %.1f min", nv, length(costruite), (time() - t0) / 60))
end

# ── 3. il surrogato su ogni versione ─────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
function leggi_registro(dir)
    casi = Dict{String,Dict{Tuple{Float64,Float64},NamedTuple}}()
    for l in readlines(joinpath(dir, "registro.csv"))[2:end]
        c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
        get!(casi, String(c["tratta"]), Dict{Tuple{Float64,Float64},NamedTuple}())[(pf(c["m"]), pf(c["n"]))] =
            (completato = c["stato"] == "completed", fattibile = c["tipo_esito"] == "fattibile",
             durata = pf(c["durata_viaggio_s"]), serbatoio = pf(c["massa_serbatoio_kg"]), H2 = pf(c["H2_cons_kg"]), SOC = pf(c["SOC_end"]),
             scarica = pf(c["scarica_s"]) > 1e-6, vita_batt = pf(c["vita_batt_cicli_viaggi"]), vita_FC_f1 = pf(c["vita_FC_f1_ore"]),
             C_rate = pf(c["C_rate_scarica_max"]), costo = pf(c["total_cost_EUR_km"]))
    end
    return casi
end
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1); ((XA .- μ) ./ σ, μ, σ)
end
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
function rete(X, punti)
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    d = Dati(ingressi(repeat(X', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
             m, n, fill(X[IL], N), fill(X[IT], N), zeros(Int8, N))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    return p, valuta(m, n, fill(X[IL], N), q), m, n
end
regime(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
const REGIMI = ("sola batteria", "ibrido FC piccola", "ibrido")
function sim_grandezze(e)
    g = e.diagnostica === nothing ? nothing : e.diagnostica.grandezze
    cd = e.diagnostica === nothing ? nothing : e.diagnostica.cost_details
    x(k) = g !== nothing && haskey(g, k) ? Float64(g[k]) : cd !== nothing && haskey(cd, k) ? Float64(cd[k]) : NaN
    return (durata = x("durata_viaggio_s"), serbatoio = x("massa_serbatoio_kg"), H2 = x("H2_cons_kg"), SOC = x("SOC_end"),
            scarica = x("scarica_s") > 1e-6, vita_batt = x("vita_batt_cicli_viaggi"), vita_FC_f1 = x("vita_FC_f1_ore"), C_rate = x("C_rate_scarica_max"))
end
const G = [(:durata, "durata", :rel), (:serbatoio, "serbatoio", :rel), (:H2, "idrogeno", :rel), (:SOC, "SOC finale", :abs),
           (:vita_batt, "vita batteria", :rel), (:vita_FC_f1, "vita FC (f1)", :rel), (:C_rate, "C-rate scarica", :rel), (:costo, "costo", :rel)]

"""Il surrogato su una versione: per linea, errori sulle 288 coppie e la scelta del progetto."""
function valuta_versione(cart, dir)
    reg = leggi_registro(dir)
    out = Dict{String,Any}()
    for tc in leggi_tratte_reali(costruite; cartella = cart)
        nome = tc.id; cs = reg[nome]
        pr = profilo_tratta(tc.cp); v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
        X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
        dist = sqrt(minimum(vec(sum((ZA .- ((X' .- MU) ./ SG)) .^ 2; dims = 2))))
        p, v, m, n = rete(X, C288)
        e = Dict(g[1] => Float64[] for g in G); vfc = Float64[]; fok = 0; sok = 0; sn = 0
        for i in 1:288
            c = cs[C288[i]]
            fok += v.fattibile[i] == c.fattibile
            isfinite(c.C_rate) && (sn += 1; sok += (p.p_scarica[i] >= 0.5) == c.scarica)
            for (k, _, tipo) in G
                k in (:serbatoio, :H2, :vita_FC_f1) && m[i] == 0 && continue
                k in (:H2, :SOC) && !c.completato && continue
                k === :costo && !(c.fattibile && !v.d3[i]) && continue
                y = getproperty(c, k); yh = k === :costo ? v.costo_totale[i] : getproperty(p, k)[i]
                (isfinite(y) && isfinite(yh)) || continue
                push!(e[k], tipo === :rel ? 100abs(yh - y) / abs(y) : abs(yh - y))
                k === :vita_FC_f1 && push!(vfc, 100(yh - y) / abs(y))
            end
        end
        fv = [cs[c].fattibile for c in C288]; cv = [cs[c].costo for c in C288]
        ib = argmin(ifelse.(fv, cv, Inf))
        # la strategia di usa_surrogato.jl
        pg, vg, mg, ng = rete(X, GRIGLIA)
        amm = vg.fattibile .& (pg.SOC .>= 0.21) .& (pg.p_scarica .< 0.1)
        cand = Int[]
        for i in sortperm([amm[i] ? vg.costo_totale[i] : Inf for i in eachindex(GRIGLIA)])
            amm[i] || break
            all(j -> max(abs(mg[i] - mg[j]), abs(ng[i] - ng[j])) >= 0.03 - 1e-9, cand) && push!(cand, i)
            length(cand) == 20 && break
        end
        pre = PrecalcoloTratta(tc.cp, "andata&ritorno"); ver = NamedTuple[]
        for (k, i) in enumerate(cand)
            k > 5 && any(r -> r.fattibile, ver) && break
            es = valuta_progetto(mg[i], ng[i], 195_000.0, tc.cp, "andata&ritorno"; config = CFG_CAMP, precalcolo = pre)
            push!(ver, (i = i, fattibile = es.stato === :completed && es.penalita == 0, costo = es.costo_totale, g = sim_grandezze(es)))
        end
        ok = [r for r in ver if r.fattibile]; b = isempty(ok) ? nothing : ok[argmin([r.costo for r in ok])]
        eP = Dict{Symbol,Float64}()
        if b !== nothing
            for (k, _, tipo) in G
                k in (:serbatoio, :H2, :vita_FC_f1) && mg[b.i] == 0 && continue
                y = k === :costo ? b.costo : getproperty(b.g, k); yh = k === :costo ? vg.costo_totale[b.i] : getproperty(pg, k)[b.i]
                (isfinite(y) && isfinite(yh)) && (eP[k] = tipo === :rel ? 100(yh - y) / abs(y) : yh - y)
            end
        end
        out[nome] = (err = e, vfc = vfc, fatt = 100fok / 288, scar = 100sok / max(sn, 1), dist = dist, L = X[IL], fermate = length(pr.fermate),
                     vero = C288[ib], vero_costo = cv[ib], prop = b === nothing ? (NaN, NaN) : (mg[b.i], ng[b.i]),
                     costo = b === nothing ? NaN : b.costo, rel = b === nothing ? NaN : 100(b.costo / cv[ib] - 1), nver = length(ver), eP = eP)
    end
    return out
end
R = Dict(nv => valuta_versione(cart, dir) for (nv, cart, dir) in VERSIONI)
say(@sprintf("3. surrogato valutato sulle 4 versioni (%.1f min dall'inizio)", (time() - T0) / 60))

rie = Dict(r["tratta"] => r for r in let l = readlines(joinpath(DIR_HTML, "riepilogo.csv")), h = nothing
    # il riepilogo ha campi fra virgolette con virgole: si leggono solo le prime colonne che servono, per nome, con un parser minimo
    dividi(r) = (out = String[]; buf = IOBuffer(); dentro = false;
                 for ch in r; ch == '"' ? (dentro = !dentro) : (ch == ',' && !dentro) ? push!(out, String(take!(buf))) : print(buf, ch); end;
                 push!(out, String(take!(buf))); out)
    hh = dividi(l[1]); [Dict(hh[j] => x for (j, x) in enumerate(dividi(r))) for r in l[2:end] if !isempty(strip(r))]
end)
non_el(l) = parse(Float64, rie[l]["km_non_el"]) / parse(Float64, rie[l]["lunghezza_km"]) > 0.7
nv = first.(VERSIONI)
for (titolo, sel) in (("TUTTE LE LINEE COSTRUITE", costruite), ("LE LINEE NON ELETTRIFICATE OLTRE IL 70%", filter(non_el, costruite)))
    say("\n══ ", titolo, @sprintf(" (%d linee)", length(sel)))
    say(@sprintf("%-44s", ""), join((@sprintf("%14s", x) for x in nv), ""))
    col(f) = join((@sprintf("%14s", f(R[x])) for x in nv), "")
    say("A. errori della rete sulle 288 coppie (mediana / 95° percentile)")
    for (k, nm, tipo) in G
        say(@sprintf("%-44s", "   " * nm), col(r -> (e = reduce(vcat, [r[l].err[k] for l in sel]);
            tipo === :abs ? @sprintf("%.4f/%.3f", median(e), quantile(e, 0.95)) : @sprintf("%.2f/%.1f%%", median(e), quantile(e, 0.95)))))
    end
    say(@sprintf("%-44s", "   vita FC con il segno (+ = rete più lunga)"), col(r -> @sprintf("%+.1f%%", median(reduce(vcat, [r[l].vfc for l in sel])))))
    say(@sprintf("%-44s", "   fattibilità giusta"), col(r -> @sprintf("%.2f%%", mean(r[l].fatt for l in sel))))
    say(@sprintf("%-44s", "   distanza dall'addestramento (mediana)"), col(r -> @sprintf("%.2f", median(r[l].dist for l in sel))))
    say(@sprintf("%-44s", "   linee LONTANE (> 4,7)"), col(r -> string(count(l -> r[l].dist > 4.7, sel))))
    say("B. la scelta del progetto (griglia fitta + margine + verifiche) contro la migliore delle 288")
    say(@sprintf("%-44s", "   progetto fattibile"), col(r -> @sprintf("%d/%d", count(l -> isfinite(r[l].costo), sel), length(sel))))
    rels(r) = [r[l].rel for l in sel if isfinite(r[l].rel)]
    say(@sprintf("%-44s", "   costo vs migliore 288: mediana"), col(r -> @sprintf("%+.2f%%", median(rels(r)))))
    say(@sprintf("%-44s", "   … 10° / 90° percentile"), col(r -> @sprintf("%+.1f/%+.1f%%", quantile(rels(r), 0.1), quantile(rels(r), 0.9))))
    say(@sprintf("%-44s", "   … massimo"), col(r -> @sprintf("%+.2f%%", maximum(rels(r)))))
    say(@sprintf("%-44s", "   più economico delle 288"), col(r -> @sprintf("%.0f%%", 100count(<(-1e-9), rels(r)) / length(sel))))
    say(@sprintf("%-44s", "   entro +1%"), col(r -> @sprintf("%.0f%%", 100count(<=(1), rels(r)) / length(sel))))
    say(@sprintf("%-44s", "   oltre +3%"), col(r -> string(count(>(3), rels(r)))))
    say(@sprintf("%-44s", "   più di 5 verifiche"), col(r -> string(count(l -> r[l].nver > 5, sel))))
    say(@sprintf("%-44s", "   stesso regime della migliore 288"), col(r -> @sprintf("%d/%d", count(l -> regime(r[l].vero[1]) == regime(r[l].prop[1]), sel), length(sel))))
    for a in REGIMI
        say(@sprintf("%-44s", "   migliore 288 " * a), col(r -> (s = [l for l in sel if regime(r[l].vero[1]) == a];
            @sprintf("%d → %d/%d/%d", length(s), (count(l -> regime(r[l].prop[1]) == b, s) for b in REGIMI)...))))
    end
    say("C. nel progetto proposto, rete contro simulatore (mediana del valore assoluto; costo e vita FC anche con il segno)")
    for (k, nm, tipo) in G
        say(@sprintf("%-44s", "   " * nm), col(r -> (e = [r[l].eP[k] for l in sel if haskey(r[l].eP, k)];
            isempty(e) ? "—" : tipo === :abs ? @sprintf("%.4f", median(abs.(e))) : @sprintf("%.2f%%", median(abs.(e))))))
    end
    for k in (:costo, :vita_FC_f1)
        say(@sprintf("%-44s", "   $(k) con il segno"), col(r -> (e = [r[l].eP[k] for l in sel if haskey(r[l].eP, k)]; isempty(e) ? "—" : @sprintf("%+.2f%%", median(e)))))
    end
end
say("\nCosto della migliore delle 288 (simulatore), tutto RINF contro mappa, per linea: mediana ",
    @sprintf("%+.1f%%", median(100(R["tutto RINF"][l].vero_costo / R["mappa"][l].vero_costo - 1) for l in costruite)),
    @sprintf(", 10° %+.1f%%, 90° %+.1f%%", quantile([100(R["tutto RINF"][l].vero_costo / R["mappa"][l].vero_costo - 1) for l in costruite], [0.1, 0.9])...))
open(joinpath(LOG, "11_rete_rinf_linee.csv"), "w") do io
    println(io, "versione,linea,non_el_70,L_km,fermate,distanza,err_H2_med,err_SOC_med,err_vitaFC_med,err_costo_med,fattibilita_giusta,",
            "migliore288_m,migliore288_n,migliore288_costo,surrogato_m,surrogato_n,surrogato_costo,rispetto_288_pct,verifiche")
    for x in nv, l in costruite
        r = R[x][l]; md(k) = isempty(r.err[k]) ? NaN : median(r.err[k])
        println(io, join((x, l, non_el(l), (@sprintf("%.5g", v) for v in (r.L, r.fermate, r.dist, md(:H2), md(:SOC), md(:vita_FC_f1), md(:costo), r.fatt,
                                                                           r.vero..., r.vero_costo, r.prop..., r.costo, r.rel, r.nver))...), ','))
    end
end
say(@sprintf("\nTempo totale %.1f min. Tabella per linea: %s", (time() - T0) / 60, joinpath(LOG, "11_rete_rinf_linee.csv")))
close(OUT)
