# Fase 1 (completamento): verità a forza bruta sulle 4 tratte reali distinte, come `verita` in
# train-powertrain/analisi/2026-10-11_verifica_nomad/verifica_c.jl (e la fase B di 2026-10-09_verifica_ottimizzatore):
#   griglia fitta m = 0:0,01:1 più m_log, n = 0:0,01:1; rifinitura con pattern e confine di ottimizza_mn da 5 semi
#   fattibili distinti a distanza ≥ 0,05; sola batteria migliorata (strisce, bordo inferiore, 3 partenze).
# In più, per ogni tratta, il miglior progetto fattibile per regime (per Firenze: la sola batteria, m* = 0,0301 è al
# confine con m_min = 0,03).
#
# Uso, da ml_treno/fase1:   julia -t 4 --project=. 06_forza_bruta.jl
# Scrive dati/forza_bruta_reali.csv e dati/controlli_forza_bruta.txt; le storie delle valutazioni (tutti i punti) in
# /Users/kairos/Documents/lavoro/ml_treno_dati/forza_bruta_reali/ (fuori da Drive e da git).

using TrainPowertrain, Printf, CSV, DataFrames
const OM   = TrainPowertrain.OttimizzatoreMN
const TP   = "/Users/kairos/Documents/lavoro/train-powertrain"
const DATI = joinpath(@__DIR__, "dati")
const STORIE = "/Users/kairos/Documents/lavoro/ml_treno_dati/forza_bruta_reali"
const PESO = 195_000.0
const DIR  = "andata&ritorno"
const CFG  = ConfigModello()
const OPZ  = OpzioniOttimizzatore()
const TRATTE = ["Sulmona-Carpinone", "Calabria", "Firenze", "Canavese"]   # le più lunghe prima
mkpath(STORIE)

# copia di `verita` di verifica_c.jl (stesse chiamate, stesso ordine)
function verita(f)
    V = OM._Valutatore(f, CFG.m_min_fc, typemax(Int))
    V.fase = "griglia"
    ms = unique(vcat([k / 100 for k in 0:100], OPZ.m_log))
    for m in ms, k in 0:100; V(m, k / 100); end
    fatt = sort!([(p, r.costo) for (p, r) in V.cache if r.tipo === :fattibile]; by = x -> (x[2], x[1]))
    semi = Tuple{Float64,Float64}[]
    for (p, _) in fatt
        length(semi) >= 5 && break
        all(q -> max(abs(p[1] - q[1]), abs(p[2] - q[2])) >= OPZ.passo_griglia - 1e-12, semi) && push!(semi, p)
    end
    val = OM._costo(V); h = OPZ.passo_griglia
    for s in semi
        V.fase = "pattern"
        x, cx, _, _ = OM._pattern(val, s, s[1] > 0 ? min(h / 2, s[1]) : h / 2, h / 2, OPZ.passo_minimo, CFG.m_min_fc)
        cx < OPZ.soglia_penalita || continue
        V.fase = "confine"
        for (ax, sg) in ((2, -1), (2, 1), (1, -1), (1, 1))
            y = OM._sul_confine(val, x, ax, sg, OPZ; dmax = h / 2)
            y === nothing && continue
            y, cy = OM._scivola(val, y, ax, sg, h / 4, OPZ)
            cy < cx && ((x, cx) = (y, cy))
        end
    end
    OM._sola_batteria!(V, OPZ)
    return OM._risultato(V, OPZ.soglia_penalita), V
end

occursin(TrainPowertrain.Campagna._descrivi(CFG), read(joinpath(TP, "campagne", "2026-10-08_ottimizza_ar_1024tratte", "config.txt"), String)) ||
    error("ConfigModello() diversa dalla campagna")
reali = Dict(t.id => t for t in TrainPowertrain.Campagna.leggi_tratte_reali(; cartella = joinpath(TP, "tratte_reali")))
ris = Vector{Any}(undef, length(TRATTE))
t0 = time()
Threads.@threads :dynamic for k in eachindex(TRATTE)
    t = TRATTE[k]; cp = reali[t].cp; pre = PrecalcoloTratta(cp, DIR)
    f(m, n) = esito_ottimizzatore(valuta_progetto(m, n, PESO, cp, DIR; config = CFG, precalcolo = pre), PESO)
    t1 = time()
    o, V = verita(f)
    # migliore fattibile per regime tra tutti i punti valutati
    fb = [(p, r.costo) for (p, r) in V.cache if r.tipo === :fattibile]
    bb = filter(x -> x[1][1] == 0.0, fb); bi = filter(x -> x[1][1] > 0.0, fb)
    best(v) = isempty(v) ? ((NaN, NaN), NaN) : v[argmin(last.(v))]
    ris[k] = (o = o, batt = best(bb), ibr = best(bi), tempo = time() - t1)
    open(joinpath(STORIE, "$(t)_storia.csv"), "w") do io
        println(io, "m,n,costo,fase")
        for s in o.storia; println(io, join([@sprintf("%.17g", s[1]), @sprintf("%.17g", s[2]), @sprintf("%.17g", s[3]), s[4]], ',')); end
    end
end
out = open(joinpath(DATI, "controlli_forza_bruta.txt"), "w")
say(a...) = (s = string(a...); println(s); println(out, s); flush(out))
say(@sprintf("forza bruta su %d tratte in %.0f s di parete (%d thread), commit %s", length(TRATTE), time() - t0, Threads.nthreads(), commit_codice()))
ott = CSV.read(joinpath(DATI, "ottimi_reali.csv"), DataFrame)
df = DataFrame()
for (k, t) in enumerate(TRATTE)
    r = ris[k]; o = r.o
    v = ott[findfirst(==(t), ott.tratta), :]
    sc = 100 * (o.costo - v.costo_star) / v.costo_star
    say(@sprintf("%-18s forza bruta m %.6f n %.6f costo %.10f (%d valutazioni, %.0f s, fattibile %s); verità attuale %.10f (%s): scarto %+.4f%%",
                 t, o.m, o.n, o.costo, o.valutazioni, r.tempo, o.fattibile, v.costo_star, v.provenienza, sc))
    say(@sprintf("%-18s   miglior sola batteria: m 0 n %.6f costo %.10f (%+.3f%% sulla verità attuale); miglior ibrido: m %.6f n %.6f costo %.10f (%+.3f%%)",
                 "", r.batt[1][2], r.batt[2], 100 * (r.batt[2] - v.costo_star) / v.costo_star, r.ibr[1]..., r.ibr[2],
                 100 * (r.ibr[2] - v.costo_star) / v.costo_star))
    push!(df, (tratta = t, m = o.m, n = o.n, costo = o.costo, valutazioni = o.valutazioni, tempo_s = r.tempo, fattibile = o.fattibile,
               costo_verita_precedente = v.costo_star, scarto_pct = sc,
               batt_n = r.batt[1][2], batt_costo = r.batt[2], ibr_m = r.ibr[1][1], ibr_n = r.ibr[1][2], ibr_costo = r.ibr[2]))
end
CSV.write(joinpath(DATI, "forza_bruta_reali.csv"), df)
close(out)
