# fase12/12_riassunto_non_el.jl: (1) la strategia con un candidato per regime; (2) il riassunto del surrogato sulle linee non
# elettrificate oltre il 70%, ricostruite dai dati sorgente RINF (tratte_rete_rinf/tutto_rinf, fase12/11).
#
#   julia -t 8 --project=fase12 fase12/12_riassunto_non_el.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_12.txt 2>&1
#
# 1. Tre varianti della scelta del progetto, sulle 166 linee: A attuale (rete sulla griglia fitta 9702, margine SOC ≥ 0,21 e
#    scarica < 0,1, verifica delle 5 migliori distanti 0,03, fino a 20 se nessuna è fattibile); B come A + il migliore per la rete
#    di ogni regime (sola batteria, ibrido FC piccola m < 0,1, ibrido) fra i progetti con il margine; C come B ma il migliore per
#    regime fra i progetti con un margine largo (SOC previsto ≥ 0,18, scarica < 0,5, niente D3, massa nel limite). Riferimento: la
#    migliore delle 288 coppie simulate (sim_rinf/tutto_rinf).
# 2. Sulle linee non elettrificate oltre il 70%: errori della rete su ogni grandezza (288 coppie per linea: media, mediana, p95,
#    minimo e massimo, linea migliore e peggiore), la scelta con la variante scelta, gli errori nel progetto proposto e i tempi:
#    tempo del simulatore per progetto (colonna tempo_s del registro, un core), tempo misurato della rete sulla griglia e delle
#    verifiche, contro la griglia fitta tutta simulata (stimata: tempo medio per progetto della linea × 9702).

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "12_riassunto_non_el.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/12_riassunto_non_el.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
const T0 = time()
const TPR = expanduser("~/Documents/lavoro/train-powertrain")
const DIR_TR = joinpath(TPR, "dati_rete", "tratte_rete_rinf", "tutto_rinf")
const REG = joinpath(BASE, "fase12", "sim_rinf", "tutto_rinf", "registro.csv")
const DIR_HTML = joinpath(TPR, "dati_rete", "archivio", "tratte_rete_20261110")

# ── dati ─────────────────────────────────────────────────────────────────────────
const INTEST = String.(split(TP.INTESTAZIONE_REGISTRO, ','))
pf(s) = (x = tryparse(Float64, s); x === nothing ? NaN : x)
casi = Dict{String,Dict{Tuple{Float64,Float64},NamedTuple}}()
for l in readlines(REG)[2:end]
    c = Dict(INTEST[j] => x for (j, x) in enumerate(split(l, ',')))
    get!(casi, String(c["tratta"]), Dict{Tuple{Float64,Float64},NamedTuple}())[(pf(c["m"]), pf(c["n"]))] =
        (completato = c["stato"] == "completed", fattibile = c["tipo_esito"] == "fattibile",
         durata = pf(c["durata_viaggio_s"]), serbatoio = pf(c["massa_serbatoio_kg"]), H2 = pf(c["H2_cons_kg"]), SOC = pf(c["SOC_end"]),
         scarica = pf(c["scarica_s"]) > 1e-6, vita_batt = pf(c["vita_batt_cicli_viaggi"]), vita_FC_f1 = pf(c["vita_FC_f1_ore"]),
         C_rate = pf(c["C_rate_scarica_max"]), costo = pf(c["total_cost_EUR_km"]), tempo = pf(c["tempo_s"]))
end
nomi = sort(collect(keys(casi)))
dividi(r) = (out = String[]; buf = IOBuffer(); dentro = false;
             for ch in r; ch == '"' ? (dentro = !dentro) : (ch == ',' && !dentro) ? push!(out, String(take!(buf))) : print(buf, ch); end;
             push!(out, String(take!(buf))); out)
rie = let l = readlines(joinpath(DIR_HTML, "riepilogo.csv")), h = dividi(l[1])
    Dict(d["tratta"] => d for d in (Dict(h[j] => x for (j, x) in enumerate(dividi(r))) for r in l[2:end] if !isempty(strip(r))))
end
quota_ne(l) = parse(Float64, rie[l]["km_non_el"]) / parse(Float64, rie[l]["lunghezza_km"])
const C288 = let c = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "coppie.arrow")); [(Float64(c.m[i]), Float64(c.n[i])) for i in 1:288] end
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1); ((XA .- μ) ./ σ, μ, σ)
end
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const NG = length(GRIGLIA)
const CFG = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
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
const G = [(:durata, "durata del viaggio", :rel), (:serbatoio, "massa del serbatoio", :rel), (:H2, "idrogeno consumato", :rel),
           (:SOC, "SOC finale (assoluto)", :abs), (:vita_batt, "vita della batteria", :rel), (:vita_FC_f1, "vita della fuel cell", :rel),
           (:C_rate, "C-rate di scarica", :rel), (:costo, "costo [€/km]", :rel)]

# ── la scelta del progetto, tre varianti ─────────────────────────────────────────
function scegli(tc, pg, vg, mg, ng, variante)
    amm = vg.fattibile .& (pg.SOC .>= 0.21) .& (pg.p_scarica .< 0.1)
    lista = Int[]
    for i in sortperm([amm[i] ? vg.costo_totale[i] : Inf for i in 1:NG])
        amm[i] || break
        all(j -> max(abs(mg[i] - mg[j]), abs(ng[i] - ng[j])) >= 0.03 - 1e-9, lista) && push!(lista, i)
        length(lista) == 20 && break
    end
    extra = Int[]
    if variante != :A
        largo = .!vg.d3 .& .!vg.viol_massa .& (pg.SOC .>= 0.18) .& (pg.p_scarica .< 0.5)
        crit = variante === :B ? amm : largo
        for r in REGIMI
            sel = [i for i in 1:NG if crit[i] && regime(mg[i]) == r]
            isempty(sel) && continue
            i = sel[argmin(vg.costo_totale[sel])]
            (i in lista[1:min(5, end)] || i in extra) || push!(extra, i)
        end
    end
    pre = PrecalcoloTratta(tc.cp, "andata&ritorno"); ver = NamedTuple[]; tsim = 0.0
    function prova(i)
        t = time()
        e = valuta_progetto(mg[i], ng[i], 195_000.0, tc.cp, "andata&ritorno"; config = CFG, precalcolo = pre)
        tsim += time() - t
        push!(ver, (i = i, fattibile = e.stato === :completed && e.penalita == 0, costo = e.costo_totale, g = sim_grandezze(e)))
    end
    foreach(prova, lista[1:min(5, end)]); foreach(prova, extra)
    k = 6
    while !any(r -> r.fattibile, ver) && k <= length(lista); prova(lista[k]); k += 1; end
    ok = [r for r in ver if r.fattibile]
    return (b = isempty(ok) ? nothing : ok[argmin([r.costo for r in ok])], nver = length(ver), tsim = tsim)
end

# riscaldamento (compilazione) prima di misurare i tempi
let tc = only(leggi_tratte_reali([nomi[1]]; cartella = DIR_TR)), pr = profilo_tratta(tc.cp)
    v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr)); X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    pg, vg, mg, ng = rete(X, GRIGLIA); scegli(tc, pg, vg, mg, ng, :C)
end

ris = Dict{String,Any}()
for tc in leggi_tratte_reali(nomi; cartella = DIR_TR)
    nome = tc.id; cs = casi[nome]
    t0 = time()
    pr = profilo_tratta(tc.cp); v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    t_car = time() - t0
    dist = sqrt(minimum(vec(sum((ZA .- ((X' .- MU) ./ SG)) .^ 2; dims = 2))))
    # errori sulle 288 coppie
    p, v, m, n = rete(X, C288)
    e = Dict(g[1] => Float64[] for g in G); es = Dict(g[1] => Float64[] for g in G); fok = 0; sok = 0; sn = 0
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
            x = tipo === :rel ? 100(yh - y) / abs(y) : yh - y
            push!(e[k], abs(x)); push!(es[k], x)
        end
    end
    fv = [cs[c].fattibile for c in C288]; cv = [cs[c].costo for c in C288]
    ib = argmin(ifelse.(fv, cv, Inf))
    t0 = time(); pg, vg, mg, ng = rete(X, GRIGLIA); t_rete = time() - t0
    sc = Dict(var => scegli(tc, pg, vg, mg, ng, var) for var in (:A, :B, :C))
    # nel progetto proposto (variante C)
    eP = Dict{Symbol,Float64}(); b = sc[:C].b
    if b !== nothing
        for (k, _, tipo) in G
            k in (:serbatoio, :H2, :vita_FC_f1) && mg[b.i] == 0 && continue
            y = k === :costo ? b.costo : getproperty(b.g, k); yh = k === :costo ? vg.costo_totale[b.i] : getproperty(pg, k)[b.i]
            (isfinite(y) && isfinite(yh)) && (eP[k] = tipo === :rel ? 100(yh - y) / abs(y) : yh - y)
        end
    end
    i0 = findfirst(g -> g == (0.0, 0.98), GRIGLIA)
    ris[nome] = (e = e, es = es, fatt = 100fok / 288, scar = 100sok / max(sn, 1), dist = dist, L = X[IL], ne = quota_ne(nome),
                 vero = C288[ib], vero_costo = cv[ib], sc = sc, mg = mg, eP = eP,
                 soc_098 = pg.SOC[i0], fatt_098 = vg.fattibile[i0],
                 t_car = t_car, t_rete = t_rete, t_288 = sum(cs[c].tempo for c in C288), t_medio = mean(cs[c].tempo for c in C288))
end

# ── 1. le tre varianti ───────────────────────────────────────────────────────────
rel(r, var) = (b = r.sc[var].b; b === nothing ? NaN : 100(b.costo / r.vero_costo - 1))
reg_prop(r, var) = (b = r.sc[var].b; b === nothing ? "nessuna" : regime(r.mg[b.i]))
const VAR = [(:A, "A attuale"), (:B, "B + regime"), (:C, "C + regime largo")]
for (titolo, sel) in (("TUTTE LE 166 LINEE", nomi), ("NON ELETTRIFICATE OLTRE IL 70%", filter(l -> quota_ne(l) > 0.7, nomi)))
    say("\n1. LE TRE VARIANTI DELLA SCELTA — ", titolo, " (", length(sel), " linee); riferimento: migliore delle 288 simulate")
    say(@sprintf("%-42s", ""), join((@sprintf("%18s", x[2]) for x in VAR), ""))
    col(f) = join((@sprintf("%18s", f(v)) for (v, _) in VAR), "")
    x(v) = [rel(ris[l], v) for l in sel if isfinite(rel(ris[l], v))]
    say(@sprintf("%-42s", "  progetto fattibile"), col(v -> @sprintf("%d/%d", length(x(v)), length(sel))))
    say(@sprintf("%-42s", "  costo vs migliore 288: mediana"), col(v -> @sprintf("%+.2f%%", median(x(v)))))
    say(@sprintf("%-42s", "  … 10° / 90° percentile"), col(v -> @sprintf("%+.1f / %+.1f%%", quantile(x(v), 0.1), quantile(x(v), 0.9))))
    say(@sprintf("%-42s", "  … caso peggiore"), col(v -> @sprintf("%+.2f%%", maximum(x(v)))))
    say(@sprintf("%-42s", "  più economico / entro +1% / oltre +3%"), col(v -> @sprintf("%d / %d / %d", count(<(-1e-9), x(v)), count(<=(1), x(v)), count(>(3), x(v)))))
    say(@sprintf("%-42s", "  stesso regime della migliore 288"), col(v -> string(count(l -> reg_prop(ris[l], v) == regime(ris[l].vero[1]), sel))))
    say(@sprintf("%-42s", "  simulazioni di verifica: media / max"), col(v -> @sprintf("%.1f / %d", mean(ris[l].sc[v].nver for l in sel), maximum(ris[l].sc[v].nver for l in sel))))
end
say("\n   le 3 linee difficili di fase12/11 (sola batteria a n 0,98): SOC previsto dalla rete a (0, 0,98) e scelta delle varianti")
for l in ("Edolo-Brescia", "Corteolona-Cremona", "Roccella_Jonica-Catanzaro_Lido")
    r = ris[l]
    say(@sprintf("   %-32s SOC rete (0;0,98) %.3f (fattibile per la rete: %s) | migliore 288 %.3f €/km | A %+.2f%% (%s), B %+.2f%% (%s), C %+.2f%% (%s)",
                 l, r.soc_098, r.fatt_098, r.vero_costo, rel(r, :A), reg_prop(r, :A), rel(r, :B), reg_prop(r, :B), rel(r, :C), reg_prop(r, :C)))
end

# ── 2. il riassunto sulle non elettrificate oltre il 70% ─────────────────────────
sel = filter(l -> quota_ne(l) > 0.7, nomi); N = length(sel)
say("\n\n2. RIASSUNTO — LINEE NON ELETTRIFICATE OLTRE IL 70% (", N, " linee, ", count(l -> quota_ne(l) >= 0.995, sel), " totalmente non elettrificate)")
say(@sprintf("   lunghezza %.1f–%.1f km (mediana %.1f); distanza dall'addestramento mediana %.2f, LONTANE (> 4,7) %d",
             minimum(ris[l].L for l in sel), maximum(ris[l].L for l in sel), median(ris[l].L for l in sel), median(ris[l].dist for l in sel), count(l -> ris[l].dist > 4.7, sel)))
say("\n2a. Errori della rete su ogni grandezza, sulle 288 coppie di ogni linea (", 288N, " casi)")
say(@sprintf("   %-24s %7s %8s %8s %8s %8s %8s   %-44s %s", "grandezza", "casi", "media", "mediana", "p95", "min", "max", "linea migliore (mediana)", "linea peggiore (mediana)"))
for (k, nm, tipo) in G
    t = reduce(vcat, [ris[l].e[k] for l in sel]); f(x) = tipo === :abs ? @sprintf("%8.4f", x) : @sprintf("%7.2f%%", x)
    ml = [(median(ris[l].e[k]), l) for l in sel if !isempty(ris[l].e[k])]; a = minimum(ml); b = maximum(ml)
    say(@sprintf("   %-24s %7d ", nm, length(t)), join((f(x) for x in (mean(t), median(t), quantile(t, 0.95), minimum(t), maximum(t))), " "),
        @sprintf("   %-44s %s", @sprintf("%s (%s)", a[2], strip(f(a[1]))), @sprintf("%s (%s)", b[2], strip(f(b[1])))))
end
say(@sprintf("   %-24s scarica giusta %.2f%% dei casi (min per linea %.1f%%); fattibilità giusta %.2f%% (min per linea %.1f%%)", "",
             mean(ris[l].scar for l in sel), minimum(ris[l].scar for l in sel), mean(ris[l].fatt for l in sel), minimum(ris[l].fatt for l in sel)))
say("   errore con il segno (+ = rete più alta), mediana: ", join((@sprintf("%s %+.2f%s", nm, median(reduce(vcat, [ris[l].es[k] for l in sel])), tipo === :abs ? "" : "%")
                                                           for (k, nm, tipo) in G), "; "))

say("\n2b. La scelta del progetto (variante C), contro la migliore delle 288 simulate")
x = [rel(ris[l], :C) for l in sel]
say(@sprintf("   fattibile %d/%d; costo vero vs migliore 288: media %+.2f%%, mediana %+.2f%%, min %+.2f%%, max %+.2f%%", count(isfinite, x), N, mean(x), median(x), minimum(x), maximum(x)))
say(@sprintf("   più economico in %d linee (%.0f%%), entro +1%% in %d (%.0f%%), oltre +3%% in %d", count(<(-1e-9), x), 100count(<(-1e-9), x) / N,
             count(<=(1), x), 100count(<=(1), x) / N, count(>(3), x)))
say("   regime (righe: migliore 288; colonne: surrogato)")
for a in REGIMI
    s = [l for l in sel if regime(ris[l].vero[1]) == a]
    say(@sprintf("     %-20s %3d → %s", a, length(s), join((@sprintf("%s %d", b, count(l -> reg_prop(ris[l], :C) == b, s)) for b in REGIMI), ", ")))
end
say("   le linee oltre +2%:")
for l in sel
    rel(ris[l], :C) > 2 || continue
    r = ris[l]; b = r.sc[:C].b
    say(@sprintf("     %-36s L %.1f km, dist %.2f: migliore 288 (%.2f, %.2f) %.3f €/km, surrogato (%.2f, %.2f) %.3f €/km, %+.2f%%", l, r.L, r.dist,
                 r.vero..., r.vero_costo, r.mg[b.i], GRIGLIA[b.i][2], b.costo, rel(r, :C)))
end
say("\n2c. Nel progetto proposto: rete contro simulatore")
say(@sprintf("   %-24s %6s %10s %10s %10s %10s", "grandezza", "linee", "mediana", "|mediana|", "p95 |e|", "max |e|"))
for (k, nm, tipo) in G
    t = [ris[l].eP[k] for l in sel if haskey(ris[l].eP, k)]; isempty(t) && continue
    f(x) = tipo === :abs ? @sprintf("%10.4f", x) : @sprintf("%9.2f%%", x)
    say(@sprintf("   %-24s %6d ", nm, length(t)), join((f(x) for x in (median(t), median(abs.(t)), quantile(abs.(t), 0.95), maximum(abs.(t)))), " "))
end

say("\n2d. I tempi, sul Mac M4 a 8 core")
say("   (simulatore: colonna tempo_s del registro, misurata con 8 simulazioni in parallelo; su un core libero lo stesso progetto è da 1,2 a")
say("    3 volte più veloce, misurato su 5 linee. Il confronto giusto è quindi a parità di macchina: griglia simulata su 8 core = Σ tempo_s / 8,")
say("    che torna con la misura diretta di fase12/09: Trapani–Alcamo 9702 progetti in 0,7–0,8 min)")
tm = [ris[l].t_medio for l in sel]
say(@sprintf("   simulatore, un progetto (8 in parallelo): media %.1f ms, mediana %.1f ms, da %.1f a %.1f ms secondo la linea", 1000mean(tm), 1000median(tm), 1000minimum(tm), 1000maximum(tm)))
tg = [ris[l].t_medio * NG / 8 for l in sel]
say(@sprintf("   griglia fitta (9702 progetti) tutta simulata su 8 core, per linea: media %.1f s, da %.1f a %.1f s; tutte le %d linee: %.0f min", mean(tg), minimum(tg), maximum(tg), N, sum(tg) / 60))
t288 = [ris[l].t_288 / 8 for l in sel]
say(@sprintf("   le sole 288 coppie della campagna su 8 core, per linea: media %.2f s; tutte le linee: %.1f min", mean(t288), sum(t288) / 60))
ts = [ris[l].t_car + ris[l].t_rete + ris[l].sc[:C].tsim for l in sel]
say(@sprintf("   surrogato (variante C), per linea: caratteristiche %.0f ms + rete sulla griglia %.0f ms + verifiche %.0f ms (%.1f simulazioni) = %.3f s in media, max %.2f s",
             1000mean(ris[l].t_car for l in sel), 1000mean(ris[l].t_rete for l in sel), 1000mean(ris[l].sc[:C].tsim for l in sel),
             mean(ris[l].sc[:C].nver for l in sel), mean(ts), maximum(ts)))
say(@sprintf("   tutte le %d linee con il surrogato: %.0f s (più ~10 s di avvio di Julia, una volta sola)", N, sum(ts)))
say(@sprintf("   guadagno a parità di macchina: %.0f× sul totale rispetto alla griglia fitta simulata (per linea: mediana %.0f×, da %.0f× a %.0f×); %.0f× rispetto alle sole 288 coppie",
             sum(tg) / sum(ts), median(tg ./ ts), minimum(tg ./ ts), maximum(tg ./ ts), sum(t288) / sum(ts)))

open(joinpath(LOG, "12_riassunto_non_el_linee.csv"), "w") do io
    println(io, "linea,quota_non_el,L_km,distanza,", join(("err_$(k)_mediana" for (k, _, _) in G), ','), ",fattibilita_giusta,migliore288_m,migliore288_n,migliore288_costo,",
            "A_rispetto_288,B_rispetto_288,C_rispetto_288,C_m,C_n,C_costo,C_regime,C_verifiche,t_sim_progetto_ms_8_in_parallelo,t_surrogato_s,t_griglia_simulata_8core_s")
    for l in nomi
        r = ris[l]; b = r.sc[:C].b
        println(io, join((l, (@sprintf("%.4g", v) for v in (r.ne, r.L, r.dist, (isempty(r.e[k]) ? NaN : median(r.e[k]) for (k, _, _) in G)..., r.fatt,
                                                              r.vero..., r.vero_costo, rel(r, :A), rel(r, :B), rel(r, :C)))...,
                          b === nothing ? "" : r.mg[b.i], b === nothing ? "" : GRIGLIA[b.i][2], b === nothing ? "" : @sprintf("%.5g", b.costo),
                          reg_prop(r, :C), r.sc[:C].nver, @sprintf("%.2f", 1000r.t_medio),
                          @sprintf("%.3f", r.t_car + r.t_rete + r.sc[:C].tsim), @sprintf("%.1f", r.t_medio * NG / 8)), ','))
    end
end
say(@sprintf("\nTempo totale %.1f min. Tabella per linea: %s", (time() - T0) / 60, joinpath(LOG, "12_riassunto_non_el_linee.csv")))
close(OUT)
