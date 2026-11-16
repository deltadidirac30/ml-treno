# surrogato/usa_surrogato.jl: il surrogato in pratica. Per una o più tratte propone il progetto (m, n) più economico e lo
# verifica con il simulatore.
#
#   surrogato cartella=<cartella delle tratte> tratta=<nome>[,<nome>…|tutte] [verifiche=5] [margine=si]
#   surrogato doe=<route_id>[,<route_id>…|<da>-<a>] [cartella=<tratte DoE>] [verifiche=5] [margine=si]
#
# (`surrogato` è l'alias in ~/.zshrc; senza alias: julia -t 8 --project=surrogato surrogato/usa_surrogato.jl … dalla cartella
# ml_treno, vedi LEGGIMI.md). Esempi:
#   surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Firenze
#   surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=Calabria,Canavese,Firenze
#   surrogato cartella=~/Documents/lavoro/train-powertrain/dati_rete/archivio/tratte_rete_20261110 tratta=tutte
#   surrogato doe=15000
#   surrogato doe=15000-15100
#
# Le tratte: cartelle <nome>/ con i 4 file <nome>_progressiva.txt, _altimetria.txt, _stazioni.txt, _limiti.txt, nel formato di
# train-powertrain/tratte_reali/README.md (lo stesso delle linee in tratte_rete). Tratte DoE (doe=…, 1–16384): da
# tratte_doe_16384 (default ~/Documents/lavoro/ml_treno_dati/tratte_doe_16384) con leggi_tratte_materializzate, come la
# campagna; per queste si dice anche se la rete le ha viste in addestramento e si confronta con la migliore delle 288 coppie
# della campagna P9_D28_16384. Treno di riferimento 195 t, andata e ritorno, modello e prezzi del simulatore di oggi
# (ConfigModello()), gli stessi con cui la rete è stata addestrata.
#
# Per ogni tratta (la strategia scelta sulla validazione e confermata sul test, fase 12):
#   1. le 66 caratteristiche (stesso codice della fase 1) e la distanza dalle tratte di addestramento;
#   2. la rete neurale (fase 10, rete_6b) valuta 9702 progetti (m da 0 a 0,99, n da 0,01 a 0,99, a passo 0,01) e da ognuno
#      ricava vincoli e costo con le formule del simulatore;
#   3. tiene i progetti che la rete dice fattibili (con margine=si anche SOC finale previsto ≥ 0,21 e probabilità di
#      scarica < 0,1) e prende i `verifiche` più economici, distanti fra loro almeno 0,03 in m o in n;
#   4. il simulatore vero valuta quei candidati; la proposta è il più economico davvero fattibile. Se nessuno lo è, si
#      verificano i candidati successivi (fino a 20 in tutto).
# Il tempo: ~13 s di avvio (caricamento e compilazione, una volta per lancio), poi ~0,05–0,1 s per tratta.
#
# strategia=G (fase12/13, per ora un'opzione; default strategia=semplice, quella sopra): la rete indica dove cercare, il
# simulatore decide. Il simulatore valuta: le 5 migliori della rete (con il margine); il migliore per la rete di ogni regime
# (sola batteria, ibrido con FC piccola m < 0,1, ibrido) e di ogni fascia di n (< 0,25, 0,25–0,5, 0,5–0,75, ≥ 0,75), fra i
# progetti con un margine largo (SOC previsto ≥ 0,18, scarica < 0,5, niente D3, massa nel limite); 5 progetti a sola batteria
# (n 0,2, 0,4, 0,6, 0,8, 0,99); il ripiego lungo la lista della rete finché uno dei candidati principali è fattibile (fino a
# 20). Poi una ricerca locale con il simulatore dal migliore fattibile e dal migliore fattibile di ogni regime: vicini
# (m ± s, n) e (m, n ± s) sulla griglia, s = 0,16, 0,08, 0,04, 0,02, 0,01, ci si sposta finché un vicino fattibile costa meno,
# al più 40 simulazioni per partenza. Sulle 166 linee della rete (dati RINF): 50 simulazioni per linea, ~0,13 s; tutte entro
# +1% dalla migliore delle 288 coppie (peggiore +0,58%), più economica in 143. `verifiche=` vale solo per la strategia semplice.
#   surrogato cartella=… tratta=tutte strategia=G
# Scrive ~/Documents/lavoro/ml_treno_dati/surrogato/<tratta>/candidati.csv e, con più tratte,
# ~/Documents/lavoro/ml_treno_dati/surrogato/riepilogo_<data e ora>.csv.
#
# Con una coppia data (m=… n=…, in aggiunta a cartella/tratta o doe) niente ricerca: la rete e il simulatore valutano quella
# sola coppia, e lo script mette fianco a fianco le grandezze, i vincoli, l'esito e il costo. Con 0 < m < 0,03 il simulatore
# non mette la fuel cell (D8): il progetto è a sola batteria e anche la rete lo valuta con m = 0. Scrive
# ~/Documents/lavoro/ml_treno_dati/surrogato/coppia_m<m>_n<n>_<data e ora>.csv.
#   surrogato doe=15000 m=0.30 n=0.50
#   surrogato cartella=~/Documents/lavoro/train-powertrain/tratte_reali tratta=tutte m=0.03 n=0.96

const ML = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ML, "fase9", "comune.jl"))           # valuta (vincoli e costo), taglie
include(joinpath(ML, "fase10", "comune.jl"))          # la rete: carica_modello, ingressi, previsioni
include(joinpath(ML, "fase1", "caratteristiche.jl"))  # profilo_tratta, caratteristiche_orig, caratteristiche_nuove
BLAS.set_num_threads(min(8, Threads.nthreads()))
const T0 = time()

# ── argomenti ────────────────────────────────────────────────────────────────────
const ARG = Dict(String(split(a, '='; limit = 2)[1]) => String(split(a, '='; limit = 2)[2]) for a in ARGS if occursin('=', a))
const USO = "uso: surrogato cartella=<cartella> tratta=<nome>[,<nome>…|tutte]  oppure  surrogato doe=<route_id>[,…|<da>-<a>]; poi [strategia=semplice|G] [verifiche=5] [margine=si], oppure una coppia data: m=<m> n=<n>"
const IS_DOE = haskey(ARG, "doe")
IS_DOE || (haskey(ARG, "cartella") && haskey(ARG, "tratta")) || error(USO)
const CARTELLA = expanduser(get(ARG, "cartella", IS_DOE ? joinpath(BASE, "tratte_doe_16384") : ""))
const NVER = parse(Int, get(ARG, "verifiche", "5")); const MARGINE = get(ARG, "margine", "si") == "si"
const STRATEGIA = uppercase(get(ARG, "strategia", "semplice")) == "G" ? :G :
                  lowercase(get(ARG, "strategia", "semplice")) == "semplice" ? :semplice : error("strategia=semplice oppure strategia=G")
function elenco_doe(s)
    v = Int[]
    for p in split(s, ',')
        mm = match(r"^\s*(\d+)\s*-\s*(\d+)\s*$", p)
        mm === nothing ? push!(v, parse(Int, strip(p))) : append!(v, parse(Int, mm[1]):parse(Int, mm[2]))
    end
    return v
end
const ELENCO = IS_DOE ? elenco_doe(ARG["doe"]) :
               ARG["tratta"] == "tutte" ? sort([f for f in readdir(CARTELLA) if isdir(joinpath(CARTELLA, f))]) : String.(strip.(split(ARG["tratta"], ',')))
const DETTAGLIO = length(ELENCO) == 1

# ── preparato una volta sola ─────────────────────────────────────────────────────
const RETE, NORM, SC, INFO = carica_modello(joinpath(BASE, "fase10", "rete_6b.jld2"))
const NOMI70 = vcat(NOMI_ORIG, NOMI_NUOVE)
const IL = findfirst(==(:x_L_km), NORM.nx); const IT = findfirst(==(:x_tempo_limiti_ar_s), NORM.nx); const ID = findfirst(==(:x_dislivello_m), NORM.nx)
const GRIGLIA = [(m, n) for m in vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]) for n in [round(x; digits = 2) for x in 0.01:0.01:0.99]]
const GM = [g[1] for g in GRIGLIA]; const GN = [g[2] for g in GRIGLIA]; const NG = length(GRIGLIA)
const IDX = Dict(GRIGLIA[i] => i for i in 1:NG)
# strategia G: regimi e vicini sulla griglia (m = 0 oppure 0,03–0,99; n 0,01–0,99), come fase12/13
regime_g(m) = m == 0 ? "sola batteria" : m < 0.1 ? "ibrido FC piccola" : "ibrido"
const REGIMI_G = ("sola batteria", "ibrido FC piccola", "ibrido")
function vicini_g(m, n, s)
    r2(x) = round(x; digits = 2)
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
const CFG_SIM = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
# una coppia data (m=… n=…): niente ricerca, rete e simulatore su quella coppia
const MODO_COPPIA = haskey(ARG, "m") || haskey(ARG, "n")
MODO_COPPIA && !(haskey(ARG, "m") && haskey(ARG, "n")) && error("con una coppia data servono sia m= sia n=, es. m=0.30 n=0.50")
leggi_numero(s) = parse(Float64, replace(strip(s), ',' => '.'))
const M_RICH = MODO_COPPIA ? leggi_numero(ARG["m"]) : NaN
const N_RICH = MODO_COPPIA ? leggi_numero(ARG["n"]) : NaN
MODO_COPPIA && !(0 <= M_RICH <= 1 && 0 < N_RICH <= 1) && error("m deve stare fra 0 e 1, n fra 0 (escluso) e 1: m = $M_RICH, n = $N_RICH")
const M_EFF = MODO_COPPIA ? TP.m_effettiva(M_RICH, CFG_SIM) : NaN   # D8: con 0 < m < 0,03 niente fuel cell
if MODO_COPPIA
    M_EFF != M_RICH && println(@sprintf("Nota: con m = %.3g < 0,03 il simulatore non mette la fuel cell (D8): il progetto è a sola batteria, m = 0, n = %.3g.", M_RICH, N_RICH))
    (M_RICH > 0.996 || !(0.013 <= N_RICH <= 0.996)) &&
        println("Attenzione: la coppia è fuori dal campo delle coppie di addestramento (m da 0 a 0,996, n da 0,013 a 0,996): la rete estrapola.")
end
# tratte di addestramento standardizzate, per la distanza
const ZA, MU, SG = let ct = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
    XA = reduce(hcat, (collect(getproperty(ct, c)) for c in NORM.nx))[[r for r in 1:16384 if cld(r, 1024) in (1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 13, 14)], :]
    μ = mean(XA; dims = 1); σ = std(XA; dims = 1)
    ((XA .- μ) ./ σ, μ, σ)
end
const RIA = IS_DOE ? Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "tratte_riassunto.arrow")) : nothing
giudizio(d) = d <= 2.9 ? "vicina" : d <= 4.7 ? "nella norma" : "LONTANA"
insieme(r) = (g = cld(r, 1024); g in (7, 12) ? "validazione" : g in (15, 16) ? "test" : "addestramento")

# ── una tratta ───────────────────────────────────────────────────────────────────
"""Le caratteristiche della tratta per la rete e la distanza dalla tratta di addestramento più vicina."""
function descrivi_tratta(tc)
    pr = profilo_tratta(tc.cp)
    v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    dist = sqrt(minimum(vec(sum((ZA .- ((X' .- MU) ./ SG)) .^ 2; dims = 2))))
    return (pr = pr, X = X, L = X[IL], T = X[IT], dist = dist)
end

"""Il surrogato su una tratta (TrattaCampagna): candidati verificati e progetto proposto."""
function analizza(tc; doe = 0)
    nome = tc.id; cp = tc.cp
    dt = descrivi_tratta(tc)
    pr = dt.pr; X = dt.X; L = dt.L; T = dt.T; dist = dt.dist
    d = Dati(ingressi(repeat(X', NG, 1), GM, GN, NORM), zeros(Float32, K, NG), zeros(Float32, K, NG), zeros(Int32, NG), zeros(Int16, NG),
             GM, GN, fill(L, NG), fill(T, NG), zeros(Int8, NG))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    v = valuta(GM, GN, fill(L, NG), q)
    amm = v.fattibile .& (MARGINE ? (p.SOC .>= 0.21) .& (p.p_scarica .< 0.1) : trues(NG))
    ord = sortperm([amm[i] ? v.costo_totale[i] : Inf for i in 1:NG])
    cand = Int[]
    for i in ord
        amm[i] || break
        all(j -> max(abs(GM[i] - GM[j]), abs(GN[i] - GN[j])) >= 0.03 - 1e-9, cand) && push!(cand, i)
        length(cand) == 20 && break
    end
    pre = PrecalcoloTratta(cp, "andata&ritorno")
    ris = NamedTuple[]; fatti = Dict{Int,Int}()            # indice nella griglia → posizione in ris (niente simulazioni doppie)
    function simula!(i, origine)
        haskey(fatti, i) && return ris[fatti[i]]
        e = valuta_progetto(GM[i], GN[i], 195_000.0, cp, "andata&ritorno"; config = CFG_SIM, precalcolo = pre)
        push!(ris, (i = i, m = GM[i], n = GN[i], costo_rete = v.costo_totale[i], SOC_rete = p.SOC[i], costo_simulatore = e.costo_totale,
                    fattibile = e.stato === :completed && e.penalita == 0, origine = origine,
                    esito = e.stato === :completed ? (e.penalita == 0 ? "fattibile" : @sprintf("penalità %.0f", e.penalita)) :
                            String(e.stato) * " " * first(e.motivo, 40)))
        fatti[i] = length(ris)
        return ris[end]
    end
    ricerche = NamedTuple[]
    if STRATEGIA === :semplice
        for (k, i) in enumerate(cand)
            k > NVER && any(r -> r.fattibile, ris) && break
            simula!(i, "rete $k")
        end
    else
        for (k, i) in enumerate(cand[1:min(5, end)]); simula!(i, "rete $k"); end
        largo = .!v.d3 .& .!v.viol_massa .& (p.SOC .>= 0.18) .& (p.p_scarica .< 0.5)
        migliore(f) = (s = [i for i in 1:NG if largo[i] && f(i)]; isempty(s) ? nothing : s[argmin(v.costo_totale[s])])
        for rg in REGIMI_G; i = migliore(i -> regime_g(GM[i]) == rg); i === nothing || simula!(i, "migliore: " * rg); end
        for (a, b) in ((0.0, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 1.01))
            i = migliore(i -> a <= GN[i] < b); i === nothing || simula!(i, @sprintf("migliore: n %.2f–%.2f", a, min(b, 1.0)))
        end
        for nn in (0.2, 0.4, 0.6, 0.8, 0.99); simula!(IDX[(0.0, nn)], "sola batteria fissa"); end
        k = 6     # ripiego: lungo la lista della rete finché uno dei candidati principali è fattibile
        while !any(i -> ris[fatti[i]].fattibile, cand[1:min(k - 1, end)]) && k <= length(cand); simula!(cand[k], "rete $k (ripiego)"); k += 1; end
        okG = [r for r in ris if r.fattibile]
        if !isempty(okG)
            partenze = [okG[argmin([r.costo_simulatore for r in okG])].i]
            for rg in REGIMI_G
                o = [r for r in okG if regime_g(r.m) == rg]; isempty(o) || push!(partenze, o[argmin([r.costo_simulatore for r in o])].i)
            end
            for i0 in unique(partenze)
                n0 = length(ris); budget = n0 + 40
                m0, nn0, c0 = GM[i0], GN[i0], ris[fatti[i0]].costo_simulatore
                for s in (0.16, 0.08, 0.04, 0.02, 0.01)
                    mosso = true
                    while mosso && length(ris) < budget
                        mosso = false; best = nothing
                        for g in vicini_g(m0, nn0, s)
                            length(ris) >= budget && break
                            j = get(IDX, g, nothing); j === nothing && continue
                            r = simula!(j, "ricerca locale")
                            r.fattibile && r.costo_simulatore < c0 - 1e-12 && (best === nothing || r.costo_simulatore < best[3]) && (best = (g..., r.costo_simulatore))
                        end
                        best === nothing || ((m0, nn0, c0) = best; mosso = true)
                    end
                end
                push!(ricerche, (da = (GM[i0], GN[i0]), costo_da = ris[fatti[i0]].costo_simulatore, a = (m0, nn0), costo_a = c0, simulazioni = length(ris) - n0))
            end
        end
    end
    ok = [r for r in ris if r.fattibile]
    b = isempty(ok) ? nothing : ok[argmin([r.costo_simulatore for r in ok])]
    camp = doe > 0 ? (j = findfirst(==(doe), Int.(RIA.tratta)); (m = RIA.m_migliore[j], n = RIA.n_migliore[j], costo = RIA.costo_migliore[j])) : nothing
    return (nome = nome, doe = doe, L = L, fermate = length(pr.fermate), vmin = minimum(s[3] for s in pr.seg), vmax = maximum(s[3] for s in pr.seg),
            dislivello = X[ID], distanza = dist, n_fattibili_rete = count(v.fattibile), n_ammessi = count(amm), candidati = ris, proposta = b,
            p = p, campagna = camp, ricerche = ricerche)
end

function scrivi_candidati(r)
    out = joinpath(BASE, "surrogato", r.nome); mkpath(out)
    open(joinpath(out, "candidati.csv"), "w") do io
        println(io, "m,n,costo_rete_EUR_km,SOC_rete,costo_simulatore_EUR_km,fattibile,esito,origine")
        for c in r.candidati; println(io, join((c.m, c.n, c.costo_rete, c.SOC_rete, c.costo_simulatore, c.fattibile, c.esito, c.origine), ',')); end
    end
    return joinpath(out, "candidati.csv")
end

"""La descrizione della tratta, comune alle due uscite dettagliate."""
function stampa_tratta(r; consiglio = "conviene fare più verifiche (es. verifiche=10)")
    r.doe > 0 && println("\nTratta DoE ", r.doe, ": gruppo Sobol ", cld(r.doe, 1024), ", insieme di ", insieme(r.doe),
                         insieme(r.doe) == "addestramento" ? " (la rete l'ha vista: il risultato è ottimista)" : " (la rete non l'ha mai vista)")
    println(@sprintf("\nTratta %s: L = %.1f km, %d fermate intermedie, limiti da %.0f a %.0f km/h, dislivello %.0f m", r.nome, r.L, r.fermate,
                     r.vmin, r.vmax, r.dislivello))
    g = giudizio(r.distanza)
    println(@sprintf("Distanza dalla tratta di addestramento più vicina: %.2f → %s", r.distanza,
                     g == "vicina" ? "vicina: come una tratta tipica di prova" : g == "nella norma" ? "nella norma (come la maggior parte delle linee reali)" :
                     "LONTANA: la rete qui sbaglia di più, " * consiglio))
    println("  (riferimenti: tratte di prova mediana 2,9, 95° percentile 4,7; linee della rete mediana 3,7)")
end

"""L'uscita dettagliata per una tratta sola (come prima)."""
function stampa_dettaglio(r)
    stampa_tratta(r)
    println(@sprintf("\nRete neurale: %d progetti; fattibili per la rete %d%s; simulatore: %d progetti simulati (strategia %s)", NG, r.n_fattibili_rete,
                     MARGINE ? @sprintf(", con il margine %d", r.n_ammessi) : "", length(r.candidati), STRATEGIA === :G ? "G" : "semplice"))
    println("\n   m      n     costo rete   costo simulatore   esito                 origine")
    for c in r.candidati
        c.origine == "ricerca locale" && continue
        println(@sprintf("  %.2f   %.2f   %8.4f     %10.4f        %-21s %s", c.m, c.n, c.costo_rete, c.costo_simulatore, c.esito, c.origine))
    end
    if !isempty(r.ricerche)
        println("\nRicerca locale con il simulatore (", count(c -> c.origine == "ricerca locale", r.candidati), " simulazioni):")
        for s in r.ricerche
            println(@sprintf("  da m %.2f, n %.2f (%.4f €/km) → m %.2f, n %.2f (%.4f €/km, %+.2f%%), %d simulazioni", s.da..., s.costo_da, s.a..., s.costo_a,
                             100(s.costo_a / s.costo_da - 1), s.simulazioni))
        end
    end
    if r.proposta === nothing
        println("\nNESSUN CANDIDATO FATTIBILE fra i primi ", length(r.candidati), ": la tratta è difficile per il surrogato. Prova verifiche=20 o margine=si, o usa l'ottimizzatore del simulatore.")
    else
        b = r.proposta; tg = taglie(b.m, b.n); i = b.i
        println("\n══ PROGETTO PROPOSTO ══")
        println(@sprintf("  m = %.2f, n = %.2f  →  %s", b.m, b.n, b.m == 0 ? "treno a sola batteria" : "treno ibrido idrogeno–batteria"))
        println(@sprintf("  fuel cell: %.0f kW nominali   batteria: %.0f kWh", tg.P_nom, tg.C_batt))
        println(@sprintf("  costo (simulatore): %.4f €/km   (la rete prevedeva %.4f €/km)", b.costo_simulatore, b.costo_rete))
        println(@sprintf("  previsioni della rete: durata A/R %.2f h, idrogeno %.1f kg a viaggio, SOC finale %.3f, serbatoio %.0f kg",
                         r.p.durata[i] / 3600, r.p.H2[i], r.p.SOC[i], r.p.serbatoio[i]))
    end
    if r.campagna !== nothing
        c = r.campagna
        println(@sprintf("\nCampagna P9_D28_16384 (288 coppie simulate): migliore fattibile m = %.4f, n = %.4f, %.4f €/km%s", c.m, c.n, c.costo,
                         r.proposta === nothing ? "" : @sprintf(" → il progetto proposto costa %+.2f%%", 100 * (r.proposta.costo_simulatore / c.costo - 1))))
    end
end

# ── una coppia data (m=… n=…) ────────────────────────────────────────────────────
const NOMI_CONFRONTO = (:durata, :H2, :serbatoio, :SOC, :scarica, :C_rate, :vita_batt, :vita_FC_f1, :massa, :costo)

"""Le grandezze del simulatore (come le colonne y_ della tabella, fase 6); NaN se il progetto non è stato simulato."""
function grandezze_simulatore(e)
    g = e.diagnostica === nothing ? nothing : e.diagnostica.grandezze
    cd = e.diagnostica === nothing ? nothing : e.diagnostica.cost_details
    x(k) = g !== nothing && haskey(g, k) ? Float64(g[k]) : cd !== nothing && haskey(cd, k) ? Float64(cd[k]) : NaN
    return (durata = x("durata_viaggio_s"), H2 = x("H2_cons_kg"), serbatoio = x("massa_serbatoio_kg"), SOC = x("SOC_end"),
            scarica = x("scarica_s") > 1e-6, C_rate = x("C_rate_scarica_max"), vita_batt = x("vita_batt_cicli_viaggi"),
            vita_FC_f1 = x("vita_FC_f1_ore"), massa = x("massa_propulsione_kg"))
end

"""L'esito del simulatore in parole: fattibile, i vincoli violati (dalle penalità 5000 SOC, 3000 scarica, 1000 massa), o scartato."""
function esito_simulatore(e)
    e.stato === :error && return "errore: " * replace(first(e.motivo, 60), ',' => ';')
    e.stato === :completed || return "scartato: " * replace(first(e.motivo, 60), ',' => ';')
    e.penalita == 0 && return "fattibile"
    resto = e.penalita; v = String[]
    for (c, nm) in ((5000.0, "SOC"), (3000.0, "scarica"), (1000.0, "massa"))
        resto >= c - 0.5 && (push!(v, nm); resto -= c)
    end
    return "viola " * join(v, " e ") * @sprintf(" (penalità %.0f)", e.penalita)
end

"""Rete e simulatore sulla coppia data (M_RICH, N_RICH) di una tratta."""
function analizza_coppia(tc; doe = 0)
    dt = descrivi_tratta(tc); L = dt.L
    d = Dati(ingressi(repeat(dt.X', 1, 1), [M_EFF], [N_RICH], NORM), zeros(Float32, K, 1), zeros(Float32, K, 1), zeros(Int32, 1), zeros(Int16, 1),
             [M_EFF], [N_RICH], [L], [dt.T], zeros(Int8, 1))
    p = previsioni(RETE, d, SC)
    q = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
         vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
    v = valuta([M_EFF], [N_RICH], [L], q)
    tg = taglie(M_EFF, N_RICH)
    viol = [nm for (b, nm) in ((v.viol_soc[1], "SOC"), (v.viol_scarica[1], "scarica"), (v.viol_massa[1], "massa")) if b]
    rete = (durata = p.durata[1], H2 = p.H2[1], serbatoio = p.serbatoio[1], SOC = p.SOC[1], scarica = q.scarica[1], p_scarica = p.p_scarica[1],
            C_rate = p.C_rate[1], vita_batt = p.vita_batt[1], vita_FC_f1 = p.vita_FC_f1[1], massa = tg.massa_batt + tg.massa_FC + p.serbatoio[1],
            costo = v.costo_totale[1], fattibile = v.fattibile[1],
            esito = v.d3[1] ? "scartato (D3: C-rate > 20)" : v.fattibile[1] ? "fattibile" : "viola " * join(viol, " e "),
            al_limite = v.fattibile[1] && (p.SOC[1] < 0.21 || p.p_scarica[1] >= 0.1))
    t0 = time()
    e = valuta_progetto(M_RICH, N_RICH, 195_000.0, tc.cp, "andata&ritorno"; config = CFG_SIM)
    t_sim = time() - t0
    sim = merge(grandezze_simulatore(e), (costo = e.costo_totale, fattibile = e.stato === :completed && e.penalita == 0, esito = esito_simulatore(e)))
    return (nome = tc.id, doe = doe, L = L, fermate = length(dt.pr.fermate), vmin = minimum(s[3] for s in dt.pr.seg),
            vmax = maximum(s[3] for s in dt.pr.seg), dislivello = dt.X[ID], distanza = dt.dist, taglie = tg, rete = rete, sim = sim, t_sim = t_sim)
end

fmt(f, x) = isfinite(x) ? Printf.format(Printf.Format(f), x) : "—"
differenza(a, b, tipo) = !(isfinite(a) && isfinite(b)) ? "" : tipo === :rel ? (b == 0 ? "" : @sprintf("%+.2f%%", 100 * (a / b - 1))) : @sprintf("%+.3f", a - b)

"""L'uscita dettagliata per una coppia data su una tratta."""
function stampa_coppia(r)
    stampa_tratta(r; consiglio = "da prendere con più cautela")
    ibr = M_EFF > 0; tg = r.taglie; a = r.rete; b = r.sim
    println(@sprintf("\n══ PROGETTO m = %.2f, n = %.2f ══  %s", M_RICH, N_RICH, ibr ? "treno ibrido idrogeno–batteria" : "treno a sola batteria"))
    println(@sprintf("  fuel cell: %.0f kW nominali   batteria: %.0f kWh", tg.P_nom, tg.C_batt))
    println(@sprintf("\n  %-38s %14s %14s %12s", "", "rete neurale", "simulatore", "rete − sim."))
    riga(nome, x, y, f, tipo) = println(@sprintf("  %-38s %14s %14s %12s", nome, fmt(f, x), fmt(f, y), differenza(x, y, tipo)))
    riga("durata del viaggio A/R [h]", a.durata / 3600, b.durata / 3600, "%.3f", :rel)
    ibr && riga("idrogeno consumato [kg a viaggio]", a.H2, b.H2, "%.2f", :rel)
    ibr && riga("serbatoio [kg]", a.serbatoio, b.serbatoio, "%.1f", :rel)
    riga("SOC finale (vincolo ≥ 0,20)", a.SOC, b.SOC, "%.3f", :abs)
    println(@sprintf("  %-38s %14s %14s", "scarica completa (vincolo: no)", (a.scarica ? "sì" : "no") * @sprintf(" (p=%.2f)", a.p_scarica),
                     isnan(b.C_rate) ? "—" : b.scarica ? "sì" : "no"))
    riga("C-rate di scarica massimo (D3: ≤ 20)", a.C_rate, b.C_rate, "%.2f", :rel)
    riga("vita della batteria a cicli [viaggi]", a.vita_batt, b.vita_batt, "%.0f", :rel)
    ibr && riga("vita della fuel cell (f1) [h]", a.vita_FC_f1, b.vita_FC_f1, "%.0f", :rel)
    riga(@sprintf("massa propulsione [kg] (≤ %.0f)", LIMITE_MASSA), a.massa, b.massa, "%.0f", :rel)
    riga("costo [€/km], senza penalità", a.costo, b.costo, "%.4f", :rel)
    println(@sprintf("  %-38s %14s %14s", "esito", a.esito, b.esito))
    a.al_limite && println("\n  La rete lo dice fattibile ma vicino al limite (SOC previsto < 0,21 o probabilità di scarica ≥ 0,1): qui sbaglia più spesso.")
    a.fattibile != b.fattibile && println("\n  Rete e simulatore NON sono d'accordo sulla fattibilità: fa fede il simulatore.")
end

"""Il riepilogo CSV della coppia data, una riga per tratta."""
function scrivi_coppia(risultati)
    f = joinpath(BASE, "surrogato", @sprintf("coppia_m%.3f_n%.3f_%s.csv", M_RICH, N_RICH, Dates.format(now(), "yyyymmdd_HHMMSS"))); mkpath(dirname(f))
    open(f, "w") do io
        println(io, "tratta,L_km,distanza,giudizio,insieme,m,n,m_simulata,P_nom_FC_kW,C_batt_kWh,",
                join((string(k, "_", s) for k in NOMI_CONFRONTO for s in ("rete", "sim")), ','), ",p_scarica_rete,fattibile_rete,fattibile_sim,esito_rete,esito_sim")
        for r in risultati
            println(io, join((r.nome, @sprintf("%.3f", r.L), @sprintf("%.3f", r.distanza), giudizio(r.distanza), r.doe > 0 ? insieme(r.doe) : "",
                              M_RICH, N_RICH, M_EFF, @sprintf("%.1f", r.taglie.P_nom), @sprintf("%.1f", r.taglie.C_batt),
                              (Float64(getproperty(x, k)) for k in NOMI_CONFRONTO for x in (r.rete, r.sim))...,
                              @sprintf("%.4f", r.rete.p_scarica), r.rete.fattibile, r.sim.fattibile, r.rete.esito, r.sim.esito), ','))
        end
    end
    return f
end

# ── tutte le tratte ──────────────────────────────────────────────────────────────
t_avvio = time() - T0
risultati = NamedTuple[]
errori = Tuple{String,String}[]
t_tratte = time()
DETTAGLIO || (MODO_COPPIA ?
    println(@sprintf("\n%d tratte, coppia m = %.2f, n = %.2f; avvio %.1f s\n\n  %-40s %7s %6s %-11s %9s %9s %8s %6s %6s  %-24s %s", length(ELENCO),
                     M_RICH, N_RICH, t_avvio, "tratta", "L [km]", "dist.", "", "€/km rete", "€/km sim", "diff.", "SOC r.", "SOC s.", "esito rete", "esito simulatore")) :
    println(@sprintf("\n%d tratte; avvio %.1f s\n\n  %-40s %7s %6s %-11s %6s %6s %9s %9s %s", length(ELENCO), t_avvio,
                     "tratta", "L [km]", "dist.", "", "m", "n", "€/km", "verif.", IS_DOE ? "rispetto alla campagna" : "")))
for (trs, ids) in (IS_DOE ? ((leggi_tratte_materializzate(CARTELLA; solo = Set(b)), b) for b in Iterators.partition(ELENCO, 256)) :
                   (((n,), [0]) for n in ELENCO))
    for tr in trs
        local tc, r
        try
            tc = IS_DOE ? tr : only(leggi_tratte_reali([tr]; cartella = CARTELLA))
            doe = IS_DOE ? parse(Int, tc.id[7:end]) : 0
            r = MODO_COPPIA ? analizza_coppia(tc; doe) : analizza(tc; doe)
        catch e
            nome = IS_DOE ? tr.id : String(tr)
            push!(errori, (nome, first(sprint(showerror, e), 200)))
            DETTAGLIO ? rethrow() : println("  ", rpad(nome, 40), " ERRORE: ", first(sprint(showerror, e), 120))
            continue
        end
        push!(risultati, r)
        if MODO_COPPIA
            a = r.rete; s = r.sim
            DETTAGLIO ? stampa_coppia(r) :
                println(@sprintf("  %-40s %7.1f %6.2f %-11s %9s %9s %8s %6s %6s  %-24s %s", r.nome, r.L, r.distanza, giudizio(r.distanza),
                                 fmt("%.4f", a.costo), fmt("%.4f", s.costo), differenza(a.costo, s.costo, :rel), fmt("%.3f", a.SOC), fmt("%.3f", s.SOC),
                                 a.esito * (a.al_limite ? " (al limite)" : ""), s.esito))
            continue
        end
        f = scrivi_candidati(r)
        if DETTAGLIO
            stampa_dettaglio(r)
            println("\nCandidati in ", f)
        else
            b = r.proposta
            rel = r.campagna === nothing || b === nothing ? "" : @sprintf("%+.2f%% (%s)", 100 * (b.costo_simulatore / r.campagna.costo - 1), insieme(r.doe))
            println(b === nothing ? @sprintf("  %-40s %7.1f %6.2f %-11s %s", r.nome, r.L, r.distanza, giudizio(r.distanza), "nessun candidato fattibile") :
                    @sprintf("  %-40s %7.1f %6.2f %-11s %6.2f %6.2f %9.4f %9d %s", r.nome, r.L, r.distanza, giudizio(r.distanza), b.m, b.n,
                             b.costo_simulatore, length(r.candidati), rel))
        end
    end
end
t_tratte = time() - t_tratte

if MODO_COPPIA
    f = scrivi_coppia(risultati)
    if DETTAGLIO
        println(@sprintf("\nTempo: %.1f s di avvio + %.2f s per la tratta (la simulazione %.3f s), quasi tutti di compilazione al primo uso", t_avvio, t_tratte,
                         isempty(risultati) ? NaN : risultati[1].t_sim))
    else
        nr = count(r -> r.rete.fattibile, risultati); ns = count(r -> r.sim.fattibile, risultati)
        ac = count(r -> r.rete.fattibile == r.sim.fattibile, risultati)
        ec = [abs(r.rete.costo / r.sim.costo - 1) for r in risultati if isfinite(r.rete.costo) && isfinite(r.sim.costo)]
        println(@sprintf("\n%d tratte analizzate, %d errori: fattibile per la rete in %d, per il simulatore in %d; d'accordo sulla fattibilità in %d; errore del costo (rete contro simulatore) mediano %.2f%%; %.1f s per le tratte + %.1f s di avvio",
                         length(risultati), length(errori), nr, ns, ac, isempty(ec) ? NaN : 100 * median(ec), t_tratte, t_avvio))
    end
    println("Riepilogo in ", f)
elseif !DETTAGLIO
    f = joinpath(BASE, "surrogato", "riepilogo_" * Dates.format(now(), "yyyymmdd_HHMMSS") * ".csv"); mkpath(dirname(f))
    open(f, "w") do io
        println(io, "tratta,L_km,distanza,giudizio,m,n,regime,P_nom_FC_kW,C_batt_kWh,costo_simulatore_EUR_km,costo_rete_EUR_km,candidati_verificati,",
                "insieme,campagna_m,campagna_n,campagna_costo_EUR_km,rispetto_campagna_pct")
        for r in risultati
            b = r.proposta; tg = b === nothing ? nothing : taglie(b.m, b.n); c = r.campagna
            println(io, join((r.nome, @sprintf("%.3f", r.L), @sprintf("%.3f", r.distanza), giudizio(r.distanza),
                              b === nothing ? "" : b.m, b === nothing ? "" : b.n, b === nothing ? "nessuna proposta" : b.m == 0 ? "sola batteria" : "ibrido",
                              b === nothing ? "" : @sprintf("%.1f", tg.P_nom), b === nothing ? "" : @sprintf("%.1f", tg.C_batt),
                              b === nothing ? "" : @sprintf("%.6f", b.costo_simulatore), b === nothing ? "" : @sprintf("%.6f", b.costo_rete),
                              length(r.candidati), r.doe > 0 ? insieme(r.doe) : "", c === nothing ? "" : c.m, c === nothing ? "" : c.n,
                              c === nothing ? "" : @sprintf("%.6f", c.costo),
                              c === nothing || b === nothing ? "" : @sprintf("%.4f", 100 * (b.costo_simulatore / c.costo - 1))), ','))
        end
    end
    np = count(r -> r.proposta !== nothing, risultati)
    println(@sprintf("\n%d tratte analizzate, %d con un progetto proposto, %d senza, %d errori; %.1f s per le tratte (%.2f s a tratta, compresa la compilazione del codice durante la prima) + %.1f s di avvio",
                     length(risultati), np, length(risultati) - np, length(errori), t_tratte, t_tratte / max(length(risultati), 1), t_avvio))
    if IS_DOE && np > 0
        rel = [100 * (r.proposta.costo_simulatore / r.campagna.costo - 1) for r in risultati if r.proposta !== nothing]
        println(@sprintf("rispetto alla migliore delle 288 coppie della campagna: mediana %+.2f%%, più economico in %d tratte, entro +1%% in %d",
                         median(rel), count(<(-1e-9), rel), count(<=(1), rel)))
    end
    println("Riepilogo in ", f)
else
    println(@sprintf("\nTempo: %.1f s di avvio + %.2f s per la tratta, quasi tutti di compilazione del codice al primo uso: con più tratte in un lancio (es. tratta=A,B,C o doe=15000-15100) ogni tratta in più costa ~0,1 s", t_avvio, t_tratte))
end
