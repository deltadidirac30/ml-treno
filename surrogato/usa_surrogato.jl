# surrogato/usa_surrogato.jl: il surrogato in pratica. Data una tratta, propone il progetto (m, n) più economico e lo
# verifica con il simulatore.
#
#   julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=<cartella delle tratte> tratta=<nome> [verifiche=5] [margine=si]
#   julia -t 8 --project=surrogato surrogato/usa_surrogato.jl doe=<route_id> [cartella=<tratte DoE>] [verifiche=5] [margine=si]
#
# es. (da ml_treno):
#   julia -t 8 --project=surrogato surrogato/usa_surrogato.jl cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze
#   julia -t 8 --project=surrogato surrogato/usa_surrogato.jl doe=15000
#
# Tratte DoE (doe=<route_id>, 1–16384): lette da tratte_doe_16384 (default ~/Documents/lavoro/ml_treno_dati/tratte_doe_16384)
# con leggi_tratte_materializzate, come la campagna. Lo script dice se la tratta era nell'addestramento (la rete l'ha vista),
# nella validazione o nel test, e mostra la migliore delle 288 coppie della campagna P9_D28_16384 per confronto.
#
# La tratta è una cartella <nome>/ con i 4 file <nome>_progressiva.txt, _altimetria.txt, _stazioni.txt, _limiti.txt, nel formato
# di train-powertrain/tratte_reali/README.md (lo stesso delle linee in tratte_rete). Treno di riferimento 195 t, andata e
# ritorno, modello e prezzi del simulatore di oggi (ConfigModello()), gli stessi con cui la rete è stata addestrata.
#
# Cosa fa (la strategia scelta sulla validazione e confermata sul test, fase 12):
#   1. legge la tratta e calcola le 66 caratteristiche (stesso codice della fase 1);
#   2. dice quanto la tratta è lontana dalle tratte di addestramento (più è lontana, meno ci si fida della rete);
#   3. la rete neurale (fase 10, rete_6b) valuta 9702 progetti (m da 0 a 0,99, n da 0,01 a 0,99, a passo 0,01) e da ognuno
#      ricava vincoli e costo con le formule del simulatore;
#   4. tiene i progetti che la rete dice fattibili (con margine=si anche SOC finale previsto ≥ 0,21 e probabilità di
#      scarica < 0,1) e prende i `verifiche` più economici, distanti fra loro almeno 0,03 in m o in n;
#   5. il simulatore vero valuta quei candidati; la proposta è il più economico davvero fattibile. Se nessuno lo è, si
#      verificano i candidati successivi (fino a 20 in tutto).
# Scrive anche ~/Documents/lavoro/ml_treno_dati/surrogato/<tratta>/candidati.csv.

const ML = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ML, "fase9", "comune.jl"))           # valuta (vincoli e costo), taglie
include(joinpath(ML, "fase10", "comune.jl"))          # la rete: carica_modello, ingressi, previsioni
include(joinpath(ML, "fase1", "caratteristiche.jl"))  # profilo_tratta, caratteristiche_orig, caratteristiche_nuove
BLAS.set_num_threads(min(8, Threads.nthreads()))
const T0 = time()

# ── argomenti ────────────────────────────────────────────────────────────────────
arg = Dict(split(a, '='; limit = 2)[1] => split(a, '='; limit = 2)[2] for a in ARGS if occursin('=', a))
const DOE = haskey(arg, "doe") ? parse(Int, arg["doe"]) : 0
DOE > 0 || (haskey(arg, "cartella") && haskey(arg, "tratta")) ||
    error("uso: usa_surrogato.jl cartella=<cartella> tratta=<nome>  oppure  doe=<route_id> [cartella=<tratte DoE>]; poi [verifiche=5] [margine=si]")
const CARTELLA = expanduser(get(arg, "cartella", DOE > 0 ? joinpath(BASE, "tratte_doe_16384") : ""))
const NOME = DOE > 0 ? @sprintf("route_%06d", DOE) : arg["tratta"]
const NVER = parse(Int, get(arg, "verifiche", "5")); const MARGINE = get(arg, "margine", "si") == "si"

# ── 1. la tratta e le caratteristiche ────────────────────────────────────────────
tc = DOE > 0 ? leggi_tratte_materializzate(CARTELLA; solo = [DOE])[1] : leggi_tratte_reali([NOME]; cartella = CARTELLA)[1]
if DOE > 0
    g = cld(DOE, 1024)
    insieme = g in (7, 12) ? "validazione (la rete non l'ha mai vista)" : g in (15, 16) ? "test (la rete non l'ha mai vista)" :
              "ADDESTRAMENTO: la rete l'ha vista, il risultato è ottimista"
    println("\nTratta DoE ", DOE, ": gruppo Sobol ", g, ", insieme di ", insieme)
end
const CP = tc.cp
pr = profilo_tratta(CP)
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]       # 66, ordine della rete
const L = X[findfirst(==(:x_L_km), NORM.nx)]; const T = X[findfirst(==(:x_tempo_limiti_ar_s), NORM.nx)]
println(@sprintf("\nTratta %s: L = %.1f km, %d fermate intermedie, limiti da %.0f a %.0f km/h, dislivello %.0f m",
                 NOME, L, length(pr.fermate), minimum(s[3] for s in pr.seg), maximum(s[3] for s in pr.seg), X[findfirst(==(:x_dislivello_m), NORM.nx)]))

# ── 2. distanza dalle tratte di addestramento ────────────────────────────────────
let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1)
    d = sqrt(minimum(vec(sum(((XA .- μ) ./ σ .- ((X' .- μ) ./ σ)) .^ 2; dims = 2))))
    giudizio = d <= 2.9 ? "vicina: come una tratta tipica di prova" : d <= 4.7 ? "nella norma (come la maggior parte delle linee reali)" :
               "LONTANA: la rete qui sbaglia di più, conviene fare più verifiche (es. verifiche=10)"
    println(@sprintf("Distanza dalla tratta di addestramento più vicina: %.2f → %s", d, giudizio))
    println("  (riferimenti: tratte di prova mediana 2,9, 95° percentile 4,7; linee della rete mediana 3,7)")
end

# ── 3–4. la rete sulla griglia ───────────────────────────────────────────────────
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
t0 = time()
m = [g[1] for g in GRIGLIA]; n = [g[2] for g in GRIGLIA]; N = length(GRIGLIA)
d = Dati(ingressi(repeat(X', N, 1), m, n, NORM), zeros(Float32, K, N), zeros(Float32, K, N), zeros(Int32, N), zeros(Int16, N),
         m, n, fill(L, N), fill(T, N), zeros(Int8, N))
p = previsioni(RETE, d, SC)
q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
     vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
v = valuta(m, n, fill(L, N), q)
amm = v.fattibile .& (MARGINE ? (p.SOC .>= 0.21) .& (p.p_scarica .< 0.1) : trues(N))
println(@sprintf("\nRete neurale: %d progetti valutati in %.2f s; fattibili per la rete %d%s", N, time() - t0, count(v.fattibile),
                 MARGINE ? @sprintf(", con il margine %d", count(amm)) : ""))
any(amm) || error("la rete non trova progetti fattibili per questa tratta: prova margine=no, o la tratta è fuori dal campo del surrogato")
ord = sortperm([amm[i] ? v.costo_totale[i] : Inf for i in 1:N])
cand = Int[]
for i in ord
    amm[i] || break
    all(j -> max(abs(m[i] - m[j]), abs(n[i] - n[j])) >= 0.03 - 1e-9, cand) && push!(cand, i)
    length(cand) == 20 && break
end

# ── 5. verifica con il simulatore ────────────────────────────────────────────────
const CFG_SIM = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
pre = PrecalcoloTratta(CP, "andata&ritorno")
t0 = time()
ris = NamedTuple[]
for (k, i) in enumerate(cand)
    k > NVER && any(r -> r.fattibile, ris) && break        # dopo `verifiche` candidati ci si ferma, se uno è fattibile
    e = valuta_progetto(m[i], n[i], 195_000.0, CP, "andata&ritorno"; config = CFG_SIM, precalcolo = pre)
    push!(ris, (m = m[i], n = n[i], costo_rete = v.costo_totale[i], SOC_rete = p.SOC[i], costo_simulatore = e.costo_totale,
                fattibile = e.stato === :completed && e.penalita == 0, esito = e.stato === :completed ? (e.penalita == 0 ? "fattibile" :
                @sprintf("penalità %.0f", e.penalita)) : String(e.stato) * " " * first(e.motivo, 40)))
end
println(@sprintf("Simulatore: %d candidati verificati in %.2f s", length(ris), time() - t0))
println("\n   m      n     costo rete   costo simulatore   esito")
for r in ris
    println(@sprintf("  %.2f   %.2f   %8.4f     %10.4f        %s", r.m, r.n, r.costo_rete, r.costo_simulatore, r.esito))
end
out = joinpath(BASE, "surrogato", NOME); mkpath(out)
open(joinpath(out, "candidati.csv"), "w") do io
    println(io, "m,n,costo_rete_EUR_km,SOC_rete,costo_simulatore_EUR_km,fattibile,esito")
    for r in ris; println(io, join((r.m, r.n, r.costo_rete, r.SOC_rete, r.costo_simulatore, r.fattibile, r.esito), ',')); end
end

ok = [r for r in ris if r.fattibile]
if isempty(ok)
    println("\nNESSUN CANDIDATO FATTIBILE fra i primi ", length(ris), ": la tratta è difficile per il surrogato. Prova verifiche=20 o margine=si, o usa l'ottimizzatore del simulatore.")
else
    b = ok[argmin([r.costo_simulatore for r in ok])]
    tg = taglie(b.m, b.n)
    i = findfirst(j -> m[j] == b.m && n[j] == b.n, 1:N)
    println("\n══ PROGETTO PROPOSTO ══")
    println(@sprintf("  m = %.2f, n = %.2f  →  %s", b.m, b.n, b.m == 0 ? "treno a sola batteria" : "treno ibrido idrogeno–batteria"))
    println(@sprintf("  fuel cell: %.0f kW nominali   batteria: %.0f kWh", tg.P_nom, tg.C_batt))
    println(@sprintf("  costo (simulatore): %.4f €/km   (la rete prevedeva %.4f €/km)", b.costo_simulatore, b.costo_rete))
    println(@sprintf("  previsioni della rete: durata A/R %.2f h, idrogeno %.1f kg a viaggio, SOC finale %.3f, serbatoio %.0f kg",
                     p.durata[i] / 3600, p.H2[i], p.SOC[i], p.serbatoio[i]))
end
if DOE > 0
    r = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "tratte_riassunto.arrow"))
    i = findfirst(==(DOE), Int.(r.tratta))
    println(@sprintf("\nCampagna P9_D28_16384 (288 coppie simulate): migliore fattibile m = %.4f, n = %.4f, %.4f €/km%s", r.m_migliore[i],
                     r.n_migliore[i], r.costo_migliore[i], isempty(ok) ? "" : @sprintf(" → il progetto proposto costa %+.2f%%",
                     100 * (minimum(x.costo_simulatore for x in ok) / r.costo_migliore[i] - 1))))
end
println(@sprintf("\nTempo totale: %.1f s (compreso il caricamento di Julia e dei pacchetti, la prima volta più lento)", time() - T0))
println("Candidati in ", joinpath(out, "candidati.csv"))
