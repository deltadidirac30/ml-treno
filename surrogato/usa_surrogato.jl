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
# Scrive ~/Documents/lavoro/ml_treno_dati/surrogato/<tratta>/candidati.csv e, con più tratte,
# ~/Documents/lavoro/ml_treno_dati/surrogato/riepilogo_<data e ora>.csv.

const ML = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ML, "fase9", "comune.jl"))           # valuta (vincoli e costo), taglie
include(joinpath(ML, "fase10", "comune.jl"))          # la rete: carica_modello, ingressi, previsioni
include(joinpath(ML, "fase1", "caratteristiche.jl"))  # profilo_tratta, caratteristiche_orig, caratteristiche_nuove
BLAS.set_num_threads(min(8, Threads.nthreads()))
const T0 = time()

# ── argomenti ────────────────────────────────────────────────────────────────────
const ARG = Dict(String(split(a, '='; limit = 2)[1]) => String(split(a, '='; limit = 2)[2]) for a in ARGS if occursin('=', a))
const USO = "uso: surrogato cartella=<cartella> tratta=<nome>[,<nome>…|tutte]  oppure  surrogato doe=<route_id>[,…|<da>-<a>]; poi [verifiche=5] [margine=si]"
const IS_DOE = haskey(ARG, "doe")
IS_DOE || (haskey(ARG, "cartella") && haskey(ARG, "tratta")) || error(USO)
const CARTELLA = expanduser(get(ARG, "cartella", IS_DOE ? joinpath(BASE, "tratte_doe_16384") : ""))
const NVER = parse(Int, get(ARG, "verifiche", "5")); const MARGINE = get(ARG, "margine", "si") == "si"
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
const CFG_SIM = ConfigModello(; modello = :corretta, soglia_cambio_carico = 1e-9, D3 = true, D5 = :nessuna, costi = ParametriCosto())
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
"""Il surrogato su una tratta (TrattaCampagna): candidati verificati e progetto proposto."""
function analizza(tc; doe = 0)
    nome = tc.id; cp = tc.cp
    pr = profilo_tratta(cp)
    v70 = vcat(caratteristiche_orig(pr), caratteristiche_nuove(pr))
    X = [v70[findfirst(==(String(c)[3:end]), NOMI70)] for c in NORM.nx]
    L = X[IL]; T = X[IT]
    dist = sqrt(minimum(vec(sum((ZA .- ((X' .- MU) ./ SG)) .^ 2; dims = 2))))
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
    ris = NamedTuple[]
    for (k, i) in enumerate(cand)
        k > NVER && any(r -> r.fattibile, ris) && break
        e = valuta_progetto(GM[i], GN[i], 195_000.0, cp, "andata&ritorno"; config = CFG_SIM, precalcolo = pre)
        push!(ris, (i = i, m = GM[i], n = GN[i], costo_rete = v.costo_totale[i], SOC_rete = p.SOC[i], costo_simulatore = e.costo_totale,
                    fattibile = e.stato === :completed && e.penalita == 0,
                    esito = e.stato === :completed ? (e.penalita == 0 ? "fattibile" : @sprintf("penalità %.0f", e.penalita)) :
                            String(e.stato) * " " * first(e.motivo, 40)))
    end
    ok = [r for r in ris if r.fattibile]
    b = isempty(ok) ? nothing : ok[argmin([r.costo_simulatore for r in ok])]
    camp = doe > 0 ? (j = findfirst(==(doe), Int.(RIA.tratta)); (m = RIA.m_migliore[j], n = RIA.n_migliore[j], costo = RIA.costo_migliore[j])) : nothing
    return (nome = nome, doe = doe, L = L, fermate = length(pr.fermate), vmin = minimum(s[3] for s in pr.seg), vmax = maximum(s[3] for s in pr.seg),
            dislivello = X[ID], distanza = dist, n_fattibili_rete = count(v.fattibile), n_ammessi = count(amm), candidati = ris, proposta = b,
            p = p, campagna = camp)
end

function scrivi_candidati(r)
    out = joinpath(BASE, "surrogato", r.nome); mkpath(out)
    open(joinpath(out, "candidati.csv"), "w") do io
        println(io, "m,n,costo_rete_EUR_km,SOC_rete,costo_simulatore_EUR_km,fattibile,esito")
        for c in r.candidati; println(io, join((c.m, c.n, c.costo_rete, c.SOC_rete, c.costo_simulatore, c.fattibile, c.esito), ',')); end
    end
    return joinpath(out, "candidati.csv")
end

"""L'uscita dettagliata per una tratta sola (come prima)."""
function stampa_dettaglio(r)
    r.doe > 0 && println("\nTratta DoE ", r.doe, ": gruppo Sobol ", cld(r.doe, 1024), ", insieme di ", insieme(r.doe),
                         insieme(r.doe) == "addestramento" ? " (la rete l'ha vista: il risultato è ottimista)" : " (la rete non l'ha mai vista)")
    println(@sprintf("\nTratta %s: L = %.1f km, %d fermate intermedie, limiti da %.0f a %.0f km/h, dislivello %.0f m", r.nome, r.L, r.fermate,
                     r.vmin, r.vmax, r.dislivello))
    g = giudizio(r.distanza)
    println(@sprintf("Distanza dalla tratta di addestramento più vicina: %.2f → %s", r.distanza,
                     g == "vicina" ? "vicina: come una tratta tipica di prova" : g == "nella norma" ? "nella norma (come la maggior parte delle linee reali)" :
                     "LONTANA: la rete qui sbaglia di più, conviene fare più verifiche (es. verifiche=10)"))
    println("  (riferimenti: tratte di prova mediana 2,9, 95° percentile 4,7; linee della rete mediana 3,7)")
    println(@sprintf("\nRete neurale: %d progetti; fattibili per la rete %d%s; simulatore: %d candidati verificati", NG, r.n_fattibili_rete,
                     MARGINE ? @sprintf(", con il margine %d", r.n_ammessi) : "", length(r.candidati)))
    println("\n   m      n     costo rete   costo simulatore   esito")
    for c in r.candidati
        println(@sprintf("  %.2f   %.2f   %8.4f     %10.4f        %s", c.m, c.n, c.costo_rete, c.costo_simulatore, c.esito))
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

# ── tutte le tratte ──────────────────────────────────────────────────────────────
t_avvio = time() - T0
risultati = NamedTuple[]
errori = Tuple{String,String}[]
t_tratte = time()
DETTAGLIO || println(@sprintf("\n%d tratte; avvio %.1f s\n\n  %-40s %7s %6s %-11s %6s %6s %9s %9s %s", length(ELENCO), t_avvio,
                              "tratta", "L [km]", "dist.", "", "m", "n", "€/km", "verif.", IS_DOE ? "rispetto alla campagna" : ""))
for (trs, ids) in (IS_DOE ? ((leggi_tratte_materializzate(CARTELLA; solo = Set(b)), b) for b in Iterators.partition(ELENCO, 256)) :
                   (((n,), [0]) for n in ELENCO))
    for tr in trs
        local tc, r
        try
            tc = IS_DOE ? tr : only(leggi_tratte_reali([tr]; cartella = CARTELLA))
            doe = IS_DOE ? parse(Int, tc.id[7:end]) : 0
            r = analizza(tc; doe)
        catch e
            nome = IS_DOE ? tr.id : String(tr)
            push!(errori, (nome, first(sprint(showerror, e), 200)))
            DETTAGLIO ? rethrow() : println("  ", rpad(nome, 40), " ERRORE: ", first(sprint(showerror, e), 120))
            continue
        end
        push!(risultati, r)
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

if !DETTAGLIO
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
