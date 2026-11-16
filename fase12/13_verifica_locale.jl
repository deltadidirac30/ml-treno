# fase12/13_verifica_locale.jl: strategie di verifica più robuste per la scelta del progetto (casi "regime giusto, batteria
# sbagliata", come Rutigliano–Putignano in fase12/12). Linee della rete "tutto RINF" (fase12/11). Solo simulatore vero per le verifiche.
#
#   julia -t 8 --project=fase12 fase12/13_verifica_locale.jl > ~/Documents/lavoro/ml_treno_dati/fase12_log/log_13.txt 2>&1
#
# Varianti (tutte partono dalla rete sulla griglia fitta di 9702 progetti):
#   C  le 5 migliori per la rete con il margine (SOC ≥ 0,21, scarica < 0,1, distanti 0,03) + il migliore per la rete di ogni regime
#      con un margine largo (SOC ≥ 0,18, scarica < 0,5, niente D3, massa nel limite); fino a 20 se nessuna è fattibile (fase12/12);
#   D  C + il migliore per la rete (margine largo) in ogni fascia di n: < 0,25, 0,25–0,5, 0,5–0,75, ≥ 0,75 ("candidati sparsi");
#   E  C + ricerca locale con il simulatore dal migliore verificato: vicini (m ± s, n), (m, n ± s) con s = 0,16, 0,08, 0,04, 0,02,
#      0,01 sulla griglia (m = 0 oppure 0,03–0,99; n 0,01–0,99), ci si sposta finché un vicino fattibile costa meno, poi si dimezza
#      il passo; al più 40 simulazioni di ricerca;
#   F  D + E;
#   G  F + 5 progetti a sola batteria simulati (n 0,2, 0,4, 0,6, 0,8, 0,99) e ricerca locale anche dal migliore fattibile di ogni regime
#      (40 simulazioni al più per partenza).
# Il ripiego (fino a 20 candidati) continua finché è fattibile uno dei candidati principali, non uno "extra".
# Riferimento: la migliore delle 288 coppie simulate (sim_rinf/tutto_rinf). Tempi misurati sul Mac, una simulazione alla volta.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))
include(joinpath(@__DIR__, "..", "fase1", "caratteristiche.jl"))
BLAS.set_num_threads(8)
const LOG = joinpath(BASE, "fase12_log"); mkpath(LOG)
const OUT = open(joinpath(LOG, "13_verifica_locale.txt"), "w")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("fase12/13_verifica_locale.jl  ", now(), "  thread: ", Threads.nthreads(), "  TrainPowertrain ", TP.commit_codice())
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

# ── le strategie ─────────────────────────────────────────────────────────────────
const MGRID = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99])
r2(x) = round(x; digits = 2)
function vicini(m, n, s)
    out = Tuple{Float64,Float64}[]
    for nn in (n - s, n + s); 0.01 <= r2(nn) <= 0.99 && push!(out, (m, r2(nn))); end
    for mm in (m - s, m + s)
        mm = r2(mm); mm < 0.03 && (mm = m == 0 ? -1.0 : 0.0); mm == -1.0 && continue
        mm > 0.99 && continue
        (mm == 0 || mm >= 0.03) && mm != m && push!(out, (mm, n))
    end
    m == 0 && push!(out, (max(0.03, r2(s)), n))      # dalla sola batteria: la fuel cell più piccola del passo
    return unique(out)
end
function strategia(tc, pg, vg, mg, ng, variante)
    pre = PrecalcoloTratta(tc.cp, "andata&ritorno")
    cache = Dict{Tuple{Float64,Float64},NamedTuple}(); tsim = Ref(0.0)
    function sim(m, n)
        get!(cache, (m, n)) do
            t = time()
            e = valuta_progetto(m, n, 195_000.0, tc.cp, "andata&ritorno"; config = CFG, precalcolo = pre)
            tsim[] += time() - t
            (fattibile = e.stato === :completed && e.penalita == 0, costo = e.costo_totale)
        end
    end
    amm = vg.fattibile .& (pg.SOC .>= 0.21) .& (pg.p_scarica .< 0.1)
    largo = .!vg.d3 .& .!vg.viol_massa .& (pg.SOC .>= 0.18) .& (pg.p_scarica .< 0.5)
    lista = Int[]
    for i in sortperm([amm[i] ? vg.costo_totale[i] : Inf for i in 1:NG])
        amm[i] || break
        all(j -> max(abs(mg[i] - mg[j]), abs(ng[i] - ng[j])) >= 0.03 - 1e-9, lista) && push!(lista, i)
        length(lista) == 20 && break
    end
    extra = Int[]
    migliore(f) = (s = [i for i in 1:NG if largo[i] && f(i)]; isempty(s) ? nothing : s[argmin(vg.costo_totale[s])])
    for r in REGIMI; i = migliore(i -> regime(mg[i]) == r); i === nothing || push!(extra, i); end
    if variante === :G
        for n in (0.2, 0.4, 0.6, 0.8, 0.99); sim(0.0, n); end
    end
    if variante in (:D, :F, :G)
        for (a, b) in ((0.0, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 1.01)); i = migliore(i -> a <= ng[i] < b); i === nothing || push!(extra, i); end
    end
    for i in unique(vcat(lista[1:min(5, end)], extra)); sim(mg[i], ng[i]); end
    k = 6
    # ripiego: si continua lungo la lista principale finché uno dei suoi candidati è fattibile (non basta un candidato "extra")
    while !any(i -> cache[(mg[i], ng[i])].fattibile, lista[1:min(k - 1, end)]) && k <= length(lista); sim(mg[lista[k]], ng[lista[k]]); k += 1; end
    n_ver = length(cache)
    ok = [(g, r) for (g, r) in cache if r.fattibile]
    isempty(ok) && return (b = nothing, costo = NaN, nsim = length(cache), nver = n_ver, tsim = tsim[])
    g0, r0 = ok[argmin([r.costo for (_, r) in ok])]
    if variante in (:E, :F, :G)
        function ricerca(m0, n0, c0, budget)
            for s in (0.16, 0.08, 0.04, 0.02, 0.01)
                mosso = true
                while mosso && length(cache) < budget
                    mosso = false; best = nothing
                    for (mm, nn) in vicini(m0, n0, s)
                        length(cache) >= budget && break
                        r = sim(mm, nn)
                        r.fattibile && r.costo < c0 - 1e-12 && (best === nothing || r.costo < best[3]) && (best = (mm, nn, r.costo))
                    end
                    best === nothing || ((m0, n0, c0) = best; mosso = true)
                end
            end
            return (m0, n0, c0)
        end
        partenze = [g0]
        if variante === :G      # anche dal migliore fattibile di ogni regime già simulato
            for rg in REGIMI
                okr = [(g, r) for (g, r) in cache if r.fattibile && regime(g[1]) == rg]
                isempty(okr) || push!(partenze, okr[argmin([r.costo for (_, r) in okr])][1])
            end
        end
        fin = [ricerca(g..., cache[g].costo, length(cache) + 40) for g in unique(partenze)]
        b = fin[argmin([f[3] for f in fin])]
        g0 = (b[1], b[2]); r0 = cache[g0]
    end
    return (b = g0, costo = r0.costo, nsim = length(cache), nver = n_ver, tsim = tsim[])
end

# riscaldamento
let tc = only(leggi_tratte_reali([nomi[1]]; cartella = DIR_TR)), pr = profilo_tratta(tc.cp)
    v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr)); X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    pg, vg, mg, ng = rete(X, GRIGLIA); strategia(tc, pg, vg, mg, ng, :F)
end
const VAR = [(:C, "C regime"), (:D, "D + sparsi in n"), (:E, "E + ricerca locale"), (:F, "F sparsi + locale"), (:G, "G F + sola batt.")]
ris = Dict{String,Any}()
for tc in leggi_tratte_reali(nomi; cartella = DIR_TR)
    nome = tc.id; cs = casi[nome]
    t0 = time()
    pr = profilo_tratta(tc.cp); v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    pg, vg, mg, ng = rete(X, GRIGLIA); t_rete = time() - t0
    fv = [cs[c].fattibile for c in C288]; cv = [cs[c].costo for c in C288]; ib = argmin(ifelse.(fv, cv, Inf))
    ris[nome] = (vero = C288[ib], vero_costo = cv[ib], L = X[IL], ne = quota_ne(nome), t_rete = t_rete,
                 st = Dict(v => strategia(tc, pg, vg, mg, ng, v) for (v, _) in VAR))
end
rel(r, v) = 100(r.st[v].costo / r.vero_costo - 1)
for (titolo, sel) in (("TUTTE LE 166 LINEE", nomi), ("NON ELETTRIFICATE OLTRE IL 70%", filter(l -> quota_ne(l) > 0.7, nomi)))
    say("\n", titolo, " (", length(sel), " linee); riferimento: migliore delle 288 coppie simulate")
    say(@sprintf("%-46s", ""), join((@sprintf("%20s", x[2]) for x in VAR), ""))
    col(f) = join((@sprintf("%20s", f(v)) for (v, _) in VAR), "")
    x(v) = [rel(ris[l], v) for l in sel if isfinite(rel(ris[l], v))]
    say(@sprintf("%-46s", "  progetto fattibile"), col(v -> @sprintf("%d/%d", length(x(v)), length(sel))))
    say(@sprintf("%-46s", "  costo vs migliore 288: media / mediana"), col(v -> @sprintf("%+.2f / %+.2f%%", mean(x(v)), median(x(v)))))
    say(@sprintf("%-46s", "  … migliore / peggiore"), col(v -> @sprintf("%+.1f / %+.2f%%", minimum(x(v)), maximum(x(v)))))
    say(@sprintf("%-46s", "  più economico / entro +1% / oltre +2% / +3%"), col(v -> @sprintf("%d / %d / %d / %d", count(<(-1e-9), x(v)), count(<=(1), x(v)), count(>(2), x(v)), count(>(3), x(v)))))
    say(@sprintf("%-46s", "  stesso regime della migliore 288"), col(v -> string(count(l -> regime(ris[l].st[v].b[1]) == regime(ris[l].vero[1]), sel))))
    say(@sprintf("%-46s", "  simulazioni per linea: media / max"), col(v -> @sprintf("%.1f / %d", mean(ris[l].st[v].nsim for l in sel), maximum(ris[l].st[v].nsim for l in sel))))
    say(@sprintf("%-46s", "  tempo per linea (rete + simulazioni): media"), col(v -> @sprintf("%.3f s", mean(ris[l].t_rete + ris[l].st[v].tsim for l in sel))))
    say(@sprintf("%-46s", "  … massimo"), col(v -> @sprintf("%.2f s", maximum(ris[l].t_rete + ris[l].st[v].tsim for l in sel))))
    say(@sprintf("%-46s", "  … tutte le linee"), col(v -> @sprintf("%.0f s", sum(ris[l].t_rete + ris[l].st[v].tsim for l in sel))))
end
say("\nLe linee che in almeno una variante superano +1%:")
say(@sprintf("  %-36s %7s %18s", "linea", "L km", "migliore 288"), join((@sprintf("%24s", x[2]) for x in VAR), ""))
for l in nomi
    r = ris[l]; any(v -> rel(r, v) > 1, first.(VAR)) || continue
    say(@sprintf("  %-36s %7.1f %18s", l, r.L, @sprintf("(%.2f,%.2f) %.3f", r.vero..., r.vero_costo)),
        join((@sprintf("%24s", @sprintf("(%.2f,%.2f) %+.2f%%", r.st[v].b..., rel(r, v))) for (v, _) in VAR), ""))
end
open(joinpath(LOG, "13_verifica_locale_linee.csv"), "w") do io
    println(io, "linea,quota_non_el,L_km,migliore288_m,migliore288_n,migliore288_costo,", join(("$(v)_m,$(v)_n,$(v)_costo,$(v)_rispetto_288,$(v)_simulazioni" for (v, _) in VAR), ','))
    for l in nomi
        r = ris[l]
        println(io, join((l, @sprintf("%.3f", r.ne), @sprintf("%.2f", r.L), r.vero..., @sprintf("%.5g", r.vero_costo),
                          (x for (v, _) in VAR for x in (r.st[v].b..., @sprintf("%.5g", r.st[v].costo), @sprintf("%.3f", rel(r, v)), r.st[v].nsim))...), ','))
    end
end
say(@sprintf("\nTempo totale %.1f min. Tabella per linea: %s", (time() - T0) / 60, joinpath(LOG, "13_verifica_locale_linee.csv")))
close(OUT)
