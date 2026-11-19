# fase15/01_architettura.jl: studio dell'architettura della rete del surrogato. Quanto contano profondità e larghezza?
#
#   cd "$ML" && nohup caffeinate -i julia -t 8 --project=fase15 fase15/01_architettura.jl \
#       >> ~/Documents/lavoro/ml_treno_dati/fase15_log/log_01.txt 2>&1 &
#
# Varianti della rete 6b (fase10/02_addestra.jl, costruisci/addestra di fase10/comune.jl). Tutto il resto è identico:
# dati, normalizzazione, perdita, 40 epoche, coseno 1e-3 → 1e-5, lotti di 4096, pazienza 5, Float32.
#   - profondità, larghezza 256: 2, 3 e 6 strati (seme 1);
#   - larghezza, 4 strati: 128 e 512 (seme 1);
#   - 4 × 256 con semi 2 e 3: quanto cambia per il solo seme (soglia sotto cui le differenze non contano).
# Il punto 4 × 256 seme 1 è la rete 6b: non si riaddestra, si ricarica fase10/rete_6b.jld2.
#
# Parte 1: addestra in sequenza le varianti mancanti e salva dopo ognuna; rilanciato, riparte da quelle mancanti.
# Parte 2: per tutte le 8 reti, solo sulla validazione (il test non si tocca): parametri, tempo di addestramento, epoca
# migliore, perdita di validazione; errori delle 8 grandezze (come il 6b); banco di prova (come il 6c: fattibilità, costo,
# scelta fra le 288 coppie, secca e prime 5); tempo di previsione sulla griglia fitta (8 thread, le 12 tratte di
# fase10/06_velocita.jl); rugosità del costo sulle 4 linee del 6d (simulatore dalle simulazioni salvate dal 6d).
# Nessuna simulazione.
# Scrive in ~/Documents/lavoro/ml_treno_dati/fase15: rete_<nome>.jld2, pred_validazione_<nome>.arrow; in fase15_log:
# 01_architettura.txt (in aggiunta a ogni lancio), 01_storia_<nome>.csv, 01_riassunto.csv, 01_seme.csv, fig_architettura.png.
# Solo per la prova a secco: FASE15_PROVA=<cartella> salta la parte 1 e scrive tutto in <cartella>.

include(joinpath(@__DIR__, "..", "fase9", "comune.jl"))      # valuta, grandezze_vere, ...
include(joinpath(@__DIR__, "..", "fase10", "comune.jl"))     # costruisci, addestra, previsioni, metriche, ...
using Plots, Random
gr()
BLAS.set_num_threads(8)
const PROVA = get(ENV, "FASE15_PROVA", "")
const LOG = isempty(PROVA) ? joinpath(BASE, "fase15_log") : PROVA; mkpath(LOG)
const DAT = isempty(PROVA) ? joinpath(BASE, "fase15") : PROVA; mkpath(DAT)
const OUT = open(joinpath(LOG, "01_architettura.txt"), "a")
say(a...) = (s = string(a...); println(s); println(OUT, s); flush(OUT); flush(stdout))
say("\n", "="^120, "\nfase15/01_architettura.jl  ", now(), "  thread: ", Threads.nthreads(), "  BLAS: ", BLAS.get_num_threads(),
    "  Flux ", pkgversion(Flux), "  julia ", VERSION, "  TrainPowertrain ", TP.commit_codice(), isempty(PROVA) ? "" : "  PROVA A SECCO")
const T0 = time()

const COMUNI = (epoche = 40, lotto = 4096, lr = 1f-3, lr_fine = 1f-5, pazienza = 5)
const VARIANTI = [(nome = "4x256_s2", strati = 4, larghezza = 256, seme = 2),       # prima la soglia del seme
                  (nome = "4x256_s3", strati = 4, larghezza = 256, seme = 3),
                  (nome = "2x256", strati = 2, larghezza = 256, seme = 1),
                  (nome = "3x256", strati = 3, larghezza = 256, seme = 1),
                  (nome = "4x128", strati = 4, larghezza = 128, seme = 1),
                  (nome = "6x256", strati = 6, larghezza = 256, seme = 1),
                  (nome = "4x512", strati = 4, larghezza = 512, seme = 1)]
const RIF6B = (nome = "4x256", strati = 4, larghezza = 256, seme = 1)                 # la rete 6b
const ORDINE = ["2x256", "3x256", "4x256", "6x256", "4x128", "4x512", "4x256_s2", "4x256_s3"]   # profondità, larghezza, semi
const TUTTE = Dict(v.nome => v for v in vcat(VARIANTI, [RIF6B]))
const RETE_6B = joinpath(BASE, "fase10", "rete_6b.jld2")
file_rete(nome) = nome == RIF6B.nome ? RETE_6B : joinpath(DAT, "rete_$nome.jld2")
file_storia(nome) = nome == RIF6B.nome ? joinpath(BASE, "fase10_log", "02_storia.csv") : joinpath(LOG, "01_storia_$nome.csv")
etichetta(nome) = (v = TUTTE[nome]; "$(v.strati) × $(v.larghezza)" * (v.seme == 1 ? "" : ", seme $(v.seme)") * (nome == RIF6B.nome ? " (6b)" : ""))

const ta = Arrow.Table(joinpath(TAB, "addestramento.arrow"))
const tv = Arrow.Table(joinpath(TAB, "validazione.arrow"))

# ══ parte 1: addestramento delle varianti mancanti ═══════════════════════════════════════════════════════════════════
fatte = [v.nome for v in VARIANTI if isfile(file_rete(v.nome))]
mancanti = isempty(PROVA) ? [v for v in VARIANTI if !isfile(file_rete(v.nome))] : NamedTuple[]
say("\n[1] addestramento. Già fatte: ", isempty(fatte) ? "nessuna" : join(fatte, ", "), "; da fare: ",
    isempty(mancanti) ? "nessuna" : join((v.nome for v in mancanti), ", "))
if !isempty(mancanti)
    t0 = time()
    norm = normalizzazione(ta); da = prepara(ta, norm); dv = prepara(tv, norm); sc = scale_bersagli(da)
    say(@sprintf("  dati: addestramento %d righe, validazione %d righe, %d ingressi (%.1f s)", size(da.X, 2), size(dv.X, 2), size(da.X, 1), time() - t0))
    let d6 = load(RETE_6B)
        uguali = d6["norm"].nx == norm.nx && d6["norm"].μ == norm.μ && d6["norm"].σ == norm.σ && d6["norm"].trasf == norm.trasf &&
                 d6["sc"].μ == sc.μ && d6["sc"].σ == sc.σ
        say("  controllo: normalizzazione e scale identiche a quelle della 6b: ", uguali)
        uguali || error("normalizzazione o scale diverse dalla 6b")
    end
    for v in mancanti
        say("\n══ ", v.nome, ": ", v.strati, " strati × ", v.larghezza, ", seme ", v.seme, "   (inizio ", now(), ")")
        tw = time()
        model, storia = addestra(da, dv, sc; COMUNI..., larghezza = v.larghezza, strati = v.strati, seme = v.seme, say)
        tw = time() - tw
        ib = argmin([s.perdita_val for s in storia])
        open(file_storia(v.nome), "w") do io
            println(io, "epoca,eta,perdita_add,perdita_val,", join((String(h.nome) for h in TESTE), ','), ",tempo_s")
            for s in storia
                println(io, s.epoca, ',', s.eta, ',', s.perdita_add, ',', s.perdita_val, ',', join(s.per_testa_val, ','), ',', s.tempo_s)
            end
        end
        info = merge(COMUNI, (larghezza = v.larghezza, strati = v.strati, seme = v.seme, nin = size(da.X, 1), nome = v.nome,
                              epoche_fatte = length(storia), epoca_migliore = storia[ib].epoca, perdita_val = storia[ib].perdita_val,
                              tempo_add_s = sum(s.tempo_s for s in storia), tempo_parete_s = tw))
        tmp = joinpath(DAT, "rete_$(v.nome)_parziale.jld2")
        salva_modello(tmp, model, norm, sc, info); mv(tmp, file_rete(v.nome); force = true)     # il file esiste solo se completo
        say(@sprintf("  %s salvata: %d parametri, %d epoche, migliore %d (validazione %.4f), addestramento %.1f min (%.1f s per epoca), parete %.1f min",
                     v.nome, sum(length, Flux.trainables(model)), length(storia), storia[ib].epoca, storia[ib].perdita_val,
                     info.tempo_add_s / 60, info.tempo_add_s / length(storia), tw / 60))
        model = nothing; GC.gc()
    end
    da = nothing; dv = nothing; GC.gc()
end

# ══ parte 2: misure sulla validazione, per tutte le reti ═════════════════════════════════════════════════════════════
const NOMI = [n for n in ORDINE if isfile(file_rete(n))]
say("\n[2] misure sulla validazione per ", length(NOMI), " reti: ", join(NOMI, ", "))

# banco di prova (come fase10/03_banco.jl e fase11/01_quanti_dati.jl)
const M = collect(tv.m); const Nn = collect(tv.n); const L = collect(tv.x_L_km); const TR = Int.(tv.tratta)
const FATT_VERO = collect(tv.fattibile); const TOT_VERO = collect(tv.total_cost_EUR_km)
all(valuta(M, Nn, L, grandezze_vere(tv); d3 = collect(tv.d3)).fattibile .== FATT_VERO) || error("collaudo del banco di prova non superato")
const RIGHE = let d = Dict{Int,Vector{Int}}(); for i in eachindex(TR); push!(get!(d, TR[i], Int[]), i); end; d end
const TRATTE = sort(collect(keys(RIGHE)))
const BEST = Dict(r => minimum(TOT_VERO[i] for i in RIGHE[r] if FATT_VERO[i]) for r in TRATTE)
qdi(p) = (durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC, scarica = p.p_scarica .>= 0.5, vita_batt = p.vita_batt,
          vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate)
function banco(p)
    v = valuta(M, Nn, L, qdi(p))
    out = Dict(k => fill(NaN, length(TRATTE)) for k in (1, 5))
    for (t, r) in enumerate(TRATTE)
        ii = [i for i in RIGHE[r] if v.fattibile[i]]; isempty(ii) && continue
        ord = ii[sortperm(v.costo_totale[ii])]
        for k in (1, 5)
            c = [i for i in ord[1:min(k, end)] if FATT_VERO[i]]
            isempty(c) || (out[k][t] = minimum(TOT_VERO[c]) / BEST[r] - 1)
        end
    end
    s = FATT_VERO .& .!v.d3; ec = 100 .* abs.(v.costo_totale[s] .- TOT_VERO[s]) ./ TOT_VERO[s]
    r1 = filter(isfinite, out[1]); r5 = filter(isfinite, out[5]); nt = length(TRATTE)
    return (fattibilita = 100mean(v.fattibile .== FATT_VERO), costo_mediana = median(ec), costo_p95 = quantile(ec, 0.95),
            secca_nonf = 100count(!isfinite, out[1]) / nt, secca_mediana = 100median(r1), secca_p95 = 100quantile(r1, 0.95),
            secca_entro1 = 100count(<=(0.01), r1) / nt,
            top5_nonf = 100count(!isfinite, out[5]) / nt, top5_mediana = 100median(r5), top5_p95 = 100quantile(r5, 0.95),
            top5_entro1 = 100count(<=(0.01), r5) / nt)
end

# rete su punti (m, n) di una tratta (come fase10/04 e 06)
const CT = Arrow.Table(joinpath(BASE, "P9_D28_16384", "arrow", "caratteristiche.arrow"))
const XC = reduce(hcat, (collect(getproperty(CT, c)) for c in Arrow.names(CT)))     # colonna 1 = route_id
const IL = findfirst(==(:x_L_km), Arrow.names(CT)); const IT = findfirst(==(:x_tempo_limiti_ar_s), Arrow.names(CT))
function rete_punti(model, norm, sc, r, punti)
    jx = [findfirst(==(c), Arrow.names(CT)) for c in norm.nx]
    m = [p[1] for p in punti]; n = [p[2] for p in punti]; N = length(punti)
    d = Dati(ingressi(repeat(XC[r:r, jx], N, 1), m, n, norm), zeros(Float32, K, N), zeros(Float32, K, N), fill(Int32(r), N), zeros(Int16, N),
             m, n, fill(XC[r, IL], N), fill(XC[r, IT], N), zeros(Int8, N))
    p = previsioni(model, d, sc)
    return m, n, fill(XC[r, IL], N), qdi(p)
end
rete_costo(model, norm, sc, r, punti) = ((m, n, Lr, q) = rete_punti(model, norm, sc, r, punti); valuta(m, n, Lr, q))

# velocità: griglia fitta e 12 tratte di validazione (4 corte, 4 medie, 4 lunghe) come fase10/06_velocita.jl
const MS = vcat(0.0, [round(x; digits = 2) for x in 0.03:0.01:0.99]); const NS = [round(x; digits = 2) for x in 0.01:0.01:0.99]
const GRIGLIA = [(m, n) for m in MS for n in NS]
const TR_VEL = let trv = TRATTE, Ls = [XC[r, IL] for r in TRATTE]
    scegli(a, b) = (s = [r for (r, l) in zip(trv, Ls) if a <= l < b]; s[round.(Int, range(1, length(s); length = 4))])
    vcat(scegli(0, 40), scegli(100, 180), scegli(240, 301))
end

# linee in m del 6d: costo del simulatore dalle simulazioni salvate da fase10/04_griglia_fitta.jl
const LINEE = [6146, 6876, 11610, 12285]
const MS_LINEA = [m for m in MS if m > 0]
const SIM_LINEE = Dict(r => let l = readlines(joinpath(BASE, "fase10", "sim_griglia", @sprintf("linea_%06d", r), "registro.csv")),
                                h = split(l[1], ','), jm = findfirst(==("m"), h), jn = findfirst(==("n"), h), jc = findfirst(==("total_cost_EUR_km"), h)
    rr = split.(l[2:end], ',')
    cm = Dict(round(parse(Float64, x[jm]); digits = 2) => parse(Float64, x[jc]) for x in rr)
    n0 = unique(round(parse(Float64, x[jn]); digits = 2) for x in rr); length(n0) == 1 || error("linea $r: n non unica")
    (n0 = n0[1], costo = [cm[m] for m in MS_LINEA])
end for r in LINEE)
"""Scarto mediano di ogni punto dalla media dei due vicini (come il 6d), sui soli terzetti finiti."""
function rug(c)
    v = [abs(c[i] - (c[i-1] + c[i+1]) / 2) / c[i] for i in 2:length(c)-1 if isfinite(c[i-1]) && isfinite(c[i]) && isfinite(c[i+1])]
    return median(v)
end

righe = NamedTuple[]
for nome in NOMI
    model, norm, sc, info = carica_modello(file_rete(nome))
    v = TUTTE[nome]
    (info.strati, info.larghezza) == (v.strati, v.larghezza) || error("$nome: architettura nel file diversa")
    np = sum(length, Flux.trainables(model))
    # storia: epoche, epoca migliore, perdita, tempo di addestramento
    st = let l = readlines(file_storia(nome)), h = split(l[1], ',')
        x = [parse.(Float64, split(r, ',')) for r in l[2:end]]
        (epoca = [Int(r[1]) for r in x], val = [r[findfirst(==("perdita_val"), h)] for r in x], tempo = [r[end] for r in x])
    end
    ib = argmin(st.val)
    say("\n══ ", nome, " = ", etichetta(nome), ": ", np, " parametri; ", length(st.epoca), " epoche, migliore ", st.epoca[ib],
        @sprintf(" (validazione %.4f); addestramento %.1f min (%.1f s per epoca)", st.val[ib], sum(st.tempo) / 60, mean(st.tempo)))
    # previsioni sulla validazione
    dv = prepara(tv, norm); p = previsioni(model, dv, sc)
    if nome == RIF6B.nome
        pr = Arrow.Table(joinpath(BASE, "fase10", "pred_validazione_6b.arrow"))
        say("  controllo: la 6b ricaricata ridà al bit le previsioni del passo 6b (SOC, H2, C-rate): ",
            p.SOC == collect(pr.SOC), ", ", p.H2 == collect(pr.H2), ", ", p.C_rate == collect(pr.C_rate))
    else
        Arrow.write(joinpath(DAT, "pred_validazione_$nome.arrow"),
                    (tratta = dv.tratta, coppia = dv.coppia, durata = p.durata, serbatoio = p.serbatoio, H2 = p.H2, SOC = p.SOC,
                     p_scarica = p.p_scarica, vita_batt = p.vita_batt, vita_FC_f1 = p.vita_FC_f1, C_rate = p.C_rate))
    end
    mt = Dict(x.grandezza => x for x in metriche(tv, p, dv))
    say("  grandezze (mediana / p95): ", join((g == "scarica" ? @sprintf("scarica %.2f%% (Brier %.4f)", mt[g].mediana, mt[g].p95) :
        g == "SOC" ? @sprintf("SOC %.4f / %.3f", mt[g].mediana, mt[g].p95) : @sprintf("%s %.3f%% / %.2f%%", g, mt[g].mediana, mt[g].p95)
        for g in ("durata", "serbatoio", "H2", "SOC", "vita_batt", "vita_FC_f1", "C_rate", "scarica")), ", "))
    b = banco(p)
    say(@sprintf("  banco: fattibilità giusta %.3f%%; costo mediana %.3f%%, p95 %.2f%%", b.fattibilita, b.costo_mediana, b.costo_p95))
    say(@sprintf("  scelta secca: non fattibili %.2f%%, rimpianto mediana %.3f%%, p95 %.2f%%, entro 1%% %.1f%% | prime 5: non fattibili %.2f%%, rimpianto mediana %.3f%%, p95 %.2f%%, entro 1%% %.1f%%",
                 b.secca_nonf, b.secca_mediana, b.secca_p95, b.secca_entro1, b.top5_nonf, b.top5_mediana, b.top5_p95, b.top5_entro1))
    dv = nothing; GC.gc()
    # velocità sulla griglia fitta (dopo il riscaldamento; per tratta il minimo di 3 ripetizioni)
    rete_costo(model, norm, sc, TR_VEL[1], GRIGLIA[1:100]); rete_costo(model, norm, sc, TR_VEL[1], GRIGLIA)
    tr_ = Float64[]; tc_ = Float64[]
    for r in TR_VEL
        push!(tr_, minimum(@elapsed(rete_punti(model, norm, sc, r, GRIGLIA)) for _ in 1:3))
        push!(tc_, minimum(@elapsed(rete_costo(model, norm, sc, r, GRIGLIA)) for _ in 1:3))
    end
    us_rete = 1e6mean(tr_) / length(GRIGLIA); us_costo = 1e6mean(tc_) / length(GRIGLIA)
    say(@sprintf("  griglia fitta (%d punti, 12 tratte, 8 thread): rete %.2f µs a punto, rete + costo %.2f µs a punto", length(GRIGLIA), us_rete, us_costo))
    # rugosità sulle 4 linee
    lin = map(LINEE) do r
        s = SIM_LINEE[r]; c = rete_costo(model, norm, sc, r, [(m, s.n0) for m in MS_LINEA]).costo_totale
        ok = isfinite.(c) .& isfinite.(s.costo)
        (tratta = r, n0 = s.n0, rug_sim = 100rug(s.costo), rug_rete = 100rug(c), err = 100median(abs.(c[ok] ./ s.costo[ok] .- 1)), nonfin = count(!isfinite, c))
    end
    say("  linee in m (rugosità simulatore / rete; errore mediano del costo): ",
        join((@sprintf("%d (n %.2f) %.3f%% / %.4f%%; %.2f%%%s", x.tratta, x.n0, x.rug_sim, x.rug_rete, x.err,
                       x.nonfin > 0 ? " [$(x.nonfin) punti non finiti]" : "") for x in lin), " | "))
    push!(righe, (; nome = nome, strati = v.strati, larghezza = v.larghezza, seme = v.seme, parametri = np, epoche = length(st.epoca),
                  epoca_migliore = st.epoca[ib], perdita_val = st.val[ib], tempo_add_min = sum(st.tempo) / 60, s_epoca = mean(st.tempo),
                  us_rete = us_rete, us_costo = us_costo,
                  durata = mt["durata"].mediana, durata_p95 = mt["durata"].p95, serbatoio = mt["serbatoio"].mediana, serbatoio_p95 = mt["serbatoio"].p95,
                  H2 = mt["H2"].mediana, H2_p95 = mt["H2"].p95, SOC = mt["SOC"].mediana, SOC_p95 = mt["SOC"].p95,
                  vita_batt = mt["vita_batt"].mediana, vita_batt_p95 = mt["vita_batt"].p95, vita_FC = mt["vita_FC_f1"].mediana,
                  vita_FC_p95 = mt["vita_FC_f1"].p95, C_rate = mt["C_rate"].mediana, C_rate_p95 = mt["C_rate"].p95,
                  scarica_acc = mt["scarica"].mediana, scarica_brier = mt["scarica"].p95, b...,
                  rug_rete = mean(x.rug_rete for x in lin), err_linee = mean(x.err for x in lin),
                  (Symbol("rug_$(x.tratta)") => x.rug_rete for x in lin)..., (Symbol("err_$(x.tratta)") => x.err for x in lin)...))
    model = nothing; GC.gc()
end
fmt(v) = v isa AbstractFloat ? @sprintf("%.6g", v) : string(v)
open(joinpath(LOG, "01_riassunto.csv"), "w") do io
    println(io, join(keys(righe[1]), ','))
    for x in righe; println(io, join((fmt(v) for v in values(x)), ',')); end
end

# ══ riassunto e confronto con la variabilità del seme ════════════════════════════════════════════════════════════════
say("\n[3] riassunto (validazione)")
say(" rete              parametri  epoche (migl.)  add. [min]  s/epoca  µs/punto  perdita   H2 med   SOC med  costo med/p95   secca nonf/p95/entro1   prime5 nonf/p95/entro1  rugosità")
for x in righe
    say(@sprintf(" %-17s %9d  %6d (%2d)  %10.1f  %7.1f  %8.2f  %7.4f  %6.2f%%  %7.4f  %5.2f%% / %4.1f%%  %5.1f%% / %4.1f%% / %4.1f%%  %5.2f%% / %4.1f%% / %4.1f%%  %.4f%%",
                 etichetta(x.nome), x.parametri, x.epoche, x.epoca_migliore, x.tempo_add_min, x.s_epoca, x.us_costo, x.perdita_val, x.H2, x.SOC,
                 x.costo_mediana, x.costo_p95, x.secca_nonf, x.secca_p95, x.secca_entro1, x.top5_nonf, x.top5_p95, x.top5_entro1, x.rug_rete))
end
const METRICHE_SEME = (:perdita_val, :durata, :serbatoio, :H2, :SOC, :SOC_p95, :vita_batt, :vita_FC, :C_rate, :scarica_acc, :fattibilita,
                       :costo_mediana, :costo_p95, :secca_nonf, :secca_mediana, :secca_p95, :secca_entro1, :top5_nonf, :top5_p95, :top5_entro1, :rug_rete)
const R = Dict(x.nome => x for x in righe)
const SEMI = [n for n in ("4x256", "4x256_s2", "4x256_s3") if haskey(R, n)]
if length(SEMI) >= 2
    say("\n[4] differenze dalla 6b e soglia del seme (soglia = max − min fra i semi ", join(SEMI, ", "),
        " della 4 × 256; rapporto = |Δ| / soglia)")
    altre = [n for n in NOMI if n ∉ SEMI]
    say(" ", rpad("misura", 14), join((lpad(n == RIF6B.nome ? "6b" : n, 10) for n in SEMI)), lpad("dev. st.", 10), lpad("soglia", 9),
        join((lpad(n, 20) for n in altre)))
    open(joinpath(LOG, "01_seme.csv"), "w") do io
        println(io, "misura,", join(SEMI, ','), ",dev_std_semi,soglia,", join(("$(n)_delta,$(n)_rapporto" for n in altre), ','))
        for k in METRICHE_SEME
            vs = [getproperty(R[n], k) for n in SEMI]; a = vs[1]; sg = maximum(vs) - minimum(vs); ds = std(vs)
            d = [getproperty(R[n], k) - a for n in altre]
            say(" ", rpad(String(k), 14), join((lpad(@sprintf("%.4g", x), 10) for x in vs)), lpad(@sprintf("%.3g", ds), 10),
                lpad(@sprintf("%.3g", sg), 9), join((lpad(@sprintf("%+.3g (%.1f×)", di, abs(di) / sg), 20) for di in d)))
            println(io, String(k), ',', join((fmt(x) for x in vs), ','), ',', fmt(ds), ',', fmt(sg), ',',
                    join((fmt(di) * ',' * fmt(abs(di) / sg) for di in d), ','))
        end
    end
end

# ══ figura ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
plt = plot(layout = (2, 2), size = (1400, 1000), dpi = 120)
for nome in NOMI
    l = readlines(file_storia(nome)); h = split(l[1], ','); jv = findfirst(==("perdita_val"), h)
    x = [parse.(Float64, split(r, ',')) for r in l[2:end]]
    plot!(plt[1], [r[1] for r in x], [r[jv] for r in x]; lw = nome == RIF6B.nome ? 3 : 1.5, label = etichetta(nome), yscale = :log10,
          ls = startswith(nome, "4x256_s") ? :dash : :solid, xlabel = "epoca", ylabel = "perdita di validazione (scala log)",
          title = "perdita di validazione", legend = :topright)
end
serie = (("profondità (× 256)", ["2x256", "3x256", "4x256", "6x256"], :steelblue), ("larghezza (4 strati)", ["4x128", "4x256", "4x512"], :darkorange))
for (k, (campo, titolo, ylab)) in enumerate(((:perdita_val, "perdita di validazione migliore", "perdita"),
                                             (:costo_mediana, "errore del costo (casi fattibili), mediana", "%"),
                                             (:secca_p95, "scelta secca fra le 288: rimpianto p95", "%")))
    sp = plt[k+1]
    for (lab, ns, col) in serie
        ns = [n for n in ns if haskey(R, n)]
        isempty(ns) && continue
        plot!(sp, [R[n].parametri for n in ns], [getproperty(R[n], campo) for n in ns]; marker = :circle, lw = 2, color = col, label = lab,
              xscale = :log10, xlabel = "parametri", ylabel = ylab, title = titolo)
        for n in ns; annotate!(sp, R[n].parametri, getproperty(R[n], campo), text(" " * replace(n, "x" => "×"), 8, :left, :bottom)); end
    end
    ss = [n for n in ("4x256_s2", "4x256_s3") if haskey(R, n)]
    isempty(ss) || scatter!(sp, [R[n].parametri for n in ss], [getproperty(R[n], campo) for n in ss]; marker = :star5, ms = 9,
                            color = :black, label = "4 × 256, semi 2 e 3")
end
savefig(plt, joinpath(LOG, "fig_architettura.png"))
say("\nfigura: fig_architettura.png")
say(@sprintf("tempo totale: %.1f min  (%s)", (time() - T0) / 60, now()))
close(OUT)
