# fase4/01_integrita.jl: passo 1, integrità dei 64 registri CSV (testo estratto in raw/).
#   julia -t 8 --project=fase4 fase4/01_integrita.jl
# Un blocco alla volta per thread (mai tutto il testo in memoria). Scrive risultati/01_integrita.txt,
# risultati/01_blocchi.csv e risultati/motivi.txt (dizionario di `motivo`, usato da 02_arrow.jl).

include(joinpath(@__DIR__, "comune.jl"))
using Serialization

const COPPIE = leggi_coppie()
const IDX = indice_coppie(COPPIE)
const PEN_AMMESSE = Set([0.0, 1000.0, 3000.0, 4000.0, 5000.0, 6000.0, 8000.0, 9000.0])
const NOMI_GRUPPI = ["completed m=0", "completed ibrido", "rejected m=0", "rejected ibrido", "error"]

function controlla_blocco(k)
    t0 = time()
    intest, cols, cattive = leggi_testo(k)
    nr = length(cols[1])
    S(c) = cols[COL[c]]
    # numeri
    num = Dict{String,Vector{Float64}}()
    nonnum = Dict{String,Int}()
    for c in COL_NUM
        v = Vector{Float64}(undef, nr); bad = 0
        for (i, s) in enumerate(S(c))
            x = tryparse(Float64, s)
            x === nothing ? (bad += 1; v[i] = NaN) : (v[i] = x)
        end
        num[c] = v
        bad > 0 && (nonnum[c] = bad)
    end
    N(c) = num[c]
    # tratte, coppie, direzione, caso
    tr = Vector{Int32}(undef, nr); cp = Vector{Int16}(undef, nr)
    tratta_cattiva = 0; coppia_assente = 0; caso_diverso = 0; dir_diversa = 0; mrich_diversa = Tuple{Int,Float64,Float64}[]
    for i in 1:nr
        id = id_tratta(S("tratta")[i])
        id === nothing ? (tratta_cattiva += 1; tr[i] = 0) : (tr[i] = id)
        j = get(IDX, (N("m")[i], N("n")[i]), Int16(0))
        j == 0 && (coppia_assente += 1)
        cp[i] = j
        S("direzione")[i] == DIREZIONE || (dir_diversa += 1)
        S("caso")[i] == @sprintf("%s_ar_m%.6g_n%.6g", S("tratta")[i], N("m")[i], N("n")[i]) || (caso_diverso += 1)
        N("m_richiesta")[i] === N("m")[i] || push!(mrich_diversa, (i, N("m_richiesta")[i], N("m")[i]))
    end
    # stato, motivo, tipo_esito, storage_non_convergente
    cnt = Dict{Tuple{String,String,String},Int}()      # (stato, tipo_esito, costo) -> righe
    motivi = Dict{String,Int}()
    snc = Dict{Tuple{String,String},Int}()
    for i in 1:nr
        st = String(S("stato")[i]); te = String(S("tipo_esito")[i])
        cnt[(st, te, @sprintf("%.17g", st == "completed" ? NaN : N("costo")[i]))] = get(cnt, (st, te, @sprintf("%.17g", st == "completed" ? NaN : N("costo")[i])), 0) + 1
        motivi[String(S("motivo")[i])] = get(motivi, String(S("motivo")[i]), 0) + 1
        snc[(st, String(S("storage_non_convergente")[i]))] = get(snc, (st, String(S("storage_non_convergente")[i])), 0) + 1
    end
    # gruppi per NaN/Inf
    gr = Vector{Int8}(undef, nr)
    for i in 1:nr
        st = S("stato")[i]; m0 = N("m")[i] == 0.0
        gr[i] = st == "completed" ? (m0 ? 1 : 2) : st == "rejected" ? (m0 ? 3 : 4) : 5
    end
    nan = zeros(Int, length(COL_NUM), 5); pinf = zeros(Int, length(COL_NUM), 5); minf = zeros(Int, length(COL_NUM), 5)
    ngr = [count(==(g), gr) for g in 1:5]
    for (q, c) in enumerate(COL_NUM), i in 1:nr
        x = N(c)[i]
        isnan(x) && (nan[q, gr[i]] += 1)
        x == Inf && (pinf[q, gr[i]] += 1)
        x == -Inf && (minf[q, gr[i]] += 1)
    end
    # penalità e coerenza con vincoli, grandezze fisiche e tipo_esito (completed)
    pen_fuori = 0; pen_inesatta = 0; incoer_vinc = 0; incoer_fis = 0; incoer_tipo = 0
    pen_cnt = Dict{Float64,Int}()
    esempi = String[]
    for i in 1:nr
        S("stato")[i] == "completed" || continue
        c = N("costo")[i]; t = N("total_cost_EUR_km")[i]
        vp = N("vincolo_peso_t")[i] > 0; vs = N("vincolo_scarica_100s")[i] > 0; vc = N("vincolo_soc_pt")[i] > 0
        pa = 1000.0 * vp + 3000.0 * vs + 5000.0 * vc
        d = c - t
        pr = round(d)
        pen_cnt[pr] = get(pen_cnt, pr, 0) + 1
        (pr in PEN_AMMESSE && abs(d - pr) < 1e-6) || (pen_fuori += 1)
        c === t + pa || (pen_inesatta += 1; length(esempi) < 5 && push!(esempi, "penalità: riga $i costo $c total $t attesa $pa"))
        pr == pa || (incoer_vinc += 1)
        fp = N("massa_propulsione_kg")[i] > N("limite_massa_propulsione_kg")[i]
        fs = abs(N("scarica_s")[i]) > 1e-6
        fc = N("SOC_end")[i] < 0.2
        (fp, fs, fc) == (vp, vs, vc) || (incoer_fis += 1; length(esempi) < 10 && push!(esempi, "fisica/vincoli: riga $i $((fp, fs, fc)) $((vp, vs, vc))"))
        te = S("tipo_esito")[i]
        att = !vp && !vs && !vc ? "fattibile" : vp && (vs || vc) ? "mista" : vp ? "pesante" : "piccola"
        te == att || (incoer_tipo += 1; length(esempi) < 15 && push!(esempi, "tipo_esito: riga $i $te atteso $att"))
    end
    # costo ricostruito con costo_da_grandezze, dalla riga letta con riga_registro_dict (Campagna.jl)
    n_comp = 0; costo_tot_div = 0; costo_div = 0; maxscarto = 0.0; maxscarto_rel = 0.0
    voci_div = Dict{String,Int}(); voci_max = Dict{String,Float64}()
    diag_cand = 0; diag_div = 0; diag_div_cand = 0; diag_fuso_mac = 0; diag_nofma_reg = 0; diag_tot_in_div = 0
    ulp_max = 0
    riga = Vector{SubString{String}}(undef, NCOL)
    for i in 1:nr
        S("stato")[i] == "completed" || continue
        n_comp += 1
        for q in 1:NCOL; riga[q] = cols[q][i]; end
        g = TP.riga_registro_dict(riga)
        r = TP.costo_da_grandezze(g; cfg = CFG)
        t = N("total_cost_EUR_km")[i]
        if !(r.costo_totale === t)
            costo_tot_div += 1
            maxscarto = max(maxscarto, abs(r.costo_totale - t)); maxscarto_rel = max(maxscarto_rel, abs(r.costo_totale - t) / abs(t))
            ulp_max = max(ulp_max, abs(reinterpret(Int64, r.costo_totale) - reinterpret(Int64, t)))
        end
        r.costo === N("costo")[i] || (costo_div += 1)
        # ipotesi dell'ultimo bit: potenza a esponente intero (1,04^15 con la vita calendariale) fusa o no
        rb = N("cost_repl_batt_EUR_km_att")[i]
        cand = N("vita_batt_limite_calendario")[i] == 1.0 && N("num_repl_batt")[i] >= 1
        cand && (diag_cand += 1)
        if !(r.voci["cost_repl_batt_EUR_km_att"] === rb)
            diag_div += 1
            cand && (diag_div_cand += 1)
            repl_batt(g; fuso = true) === r.voci["cost_repl_batt_EUR_km_att"] && (diag_fuso_mac += 1)
            repl_batt(g; fuso = false) === rb && (diag_nofma_reg += 1)
            r.costo_totale === t || (diag_tot_in_div += 1)
        end
        for v in VOCI_REGISTRO
            a = r.voci[v]; b = N(v)[i]
            if !isequal(a, b)
                voci_div[v] = get(voci_div, v, 0) + 1
                voci_max[v] = max(get(voci_max, v, 0.0), abs(a - b))
            end
        end
    end
    # righe di errore (testo, per il confronto con errori_P9_D28_16384.csv)
    righe_err = Dict{String,Vector{String}}()
    for i in 1:nr
        S("stato")[i] == "error" && (righe_err[String(S("caso")[i])] = [String(cols[q][i]) for q in 1:NCOL])
    end
    fine = S("fine")
    return (k = k, intest = intest, nr = nr, cattive = cattive, nonnum = nonnum, config = read(file_config(k), String),
            tratte = tr, coppie = cp, tratta_cattiva, coppia_assente, caso_diverso, dir_diversa, mrich_diversa,
            cnt, motivi, snc, nan, pinf, minf, ngr, pen_fuori, pen_inesatta, incoer_vinc, incoer_fis, incoer_tipo,
            pen_cnt, esempi, n_comp, costo_tot_div, costo_div, maxscarto, maxscarto_rel, voci_div, voci_max, righe_err,
            diag_cand, diag_div, diag_div_cand, diag_fuso_mac, diag_nofma_reg, diag_tot_in_div, ulp_max,
            fine_min = minimum(fine), fine_max = maximum(fine), tempo_cpu = sum(N("tempo_s")), t = time() - t0)
end

function main()
    mkpath(RIS)
    t0 = time()
    R = Vector{Any}(undef, NBLOCCHI)
    Threads.@threads :dynamic for k in 1:NBLOCCHI
        R[k] = controlla_blocco(k)
        @printf("blocco %02d: %d righe, %.1f s (thread %d)\n", k, R[k].nr, R[k].t, Threads.threadid())
        flush(stdout)
    end
    t_tot = time() - t0
    serialize(joinpath(DATI, "log", "01_blocchi.jls"), (R, t_tot))
    report(R, t_tot)
end

function report(R, t_tot)
    # occorrenze (tratta, coppia)
    occ = zeros(UInt8, NTRATTE, NCOPPIE); fuori = 0
    for r in R, (t, c) in zip(r.tratte, r.coppie)
        (1 <= t <= NTRATTE && 1 <= c <= NCOPPIE) ? (occ[t, c] = min(occ[t, c] + 0x01, 0xff)) : (fuori += 1)
    end
    motivi = Dict{String,Int}()
    for r in R, (m, c) in r.motivi; motivi[m] = get(motivi, m, 0) + c; end
    # dizionario dei motivi: "" (completed), D3, D7, poi gli altri in ordine alfabetico
    noti = ["", TP.Objective.MOTIVO_D3, TP.Objective.MOTIVO_D7]
    diz = vcat(noti, sort!([m for m in keys(motivi) if !(m in noti)]))
    open(joinpath(RIS, "motivi.txt"), "w") do io
        foreach(m -> println(io, m), diz)
    end
    # file degli errori
    lerr = readlines(FILE_ERRORI)
    unq(l) = (l = chomp(rstrip(l, '\r')); startswith(l, '"') && endswith(l, '"') ? split(l[2:end-1], "\",\"") : split(l, ','))
    h_err = unq(lerr[1])
    err_file = Dict(String(f[1]) => String.(f) for f in (unq(l) for l in lerr[2:end] if !isempty(strip(l))))
    err_reg = Dict{String,Vector{String}}()
    for r in R; merge!(err_reg, r.righe_err); end
    # blocchi
    open(joinpath(RIS, "01_blocchi.csv"), "w") do io
        println(io, "blocco,righe,route_min,route_max,route_attese,completed,rejected,error,fattibile,piccola,pesante,mista,errore,storage_nc_true,inizio,fine,tempo_cpu_h")
        for r in R
            st = Dict(s => sum((c for ((a, _, _), c) in r.cnt if a == s); init = 0) for s in STATI)
            te = Dict(s => sum((c for ((_, b, _), c) in r.cnt if b == s); init = 0) for s in TIPI_ESITO)
            ra = (r.k - 1) * TRATTE_BLOCCO + 1:r.k * TRATTE_BLOCCO
            println(io, join([r.k, r.nr, minimum(r.tratte), maximum(r.tratte), Set(r.tratte) == Set(ra),
                              st["completed"], st["rejected"], st["error"], (te[x] for x in TIPI_ESITO)...,
                              sum((c for ((_, v), c) in r.snc if v == "true"); init = 0), r.fine_min, r.fine_max,
                              @sprintf("%.3f", r.tempo_cpu / 3600)], ','))
        end
    end
    log_su(joinpath(RIS, "01_integrita.txt")) do io
        p(x...) = println(io, x...)
        p("# Passo 1: integrità dei registri P9_D28_16384 (", now(), ", ", Threads.nthreads(), " thread, ", @sprintf("%.1f", t_tot), " s)")
        p()
        p("## Intestazioni, righe, config")
        p("intestazioni = INTESTAZIONE_REGISTRO di Campagna.jl: ", count(r -> r.intest == TP.INTESTAZIONE_REGISTRO, R), "/64; colonne: ", NCOL)
        p("intestazioni distinte: ", length(unique(r.intest for r in R)))
        p("righe per blocco: ", sort!(unique(r.nr for r in R)), " (attese ", RIGHE_BLOCCO, "); totale ", fmt(sum(r.nr for r in R)))
        p("righe con numero di campi ≠ 95: ", sum(length(r.cattive) for r in R))
        p("campi numerici non leggibili: ", isempty(mapreduce(r -> r.nonnum, merge, R)) ? "nessuno" : mapreduce(r -> r.nonnum, merge, R))
        p("config.txt distinti: ", length(unique(r.config for r in R)), "; uguale alla descrizione di ConfigModello() + peso_a_carico=195000: ",
          strip(R[1].config) == TP.Campagna._descrivi(CFG) * " peso_a_carico=195000")
        p("config.txt: ", strip(R[1].config))
        p()
        p("## Tratte e coppie")
        p("tratta in formato route_XXXXXX: ", fmt(sum(r.nr for r in R) - sum(r.tratta_cattiva for r in R)), "; direzione ≠ andata&ritorno: ", sum(r.dir_diversa for r in R))
        p("caso ≠ \"<tratta>_ar_m%.6g_n%.6g\": ", sum(r.caso_diverso for r in R))
        p("(m, n) non uguali al bit a una coppia di campionamento_288.csv: ", sum(r.coppia_assente for r in R))
        p("m_richiesta !== m: ", sum(length(r.mrich_diversa) for r in R), isempty(R[1].mrich_diversa) ? "" : " esempi $(first(R[1].mrich_diversa, 3))")
        p("celle (tratta, coppia): 0 occorrenze ", count(==(0), occ), ", 1 occorrenza ", count(==(1), occ), ", >1 ", count(>(1), occ), "; fuori indice ", fuori)
        p("blocchi con route = (k−1)·256+1 … k·256: ", count(r -> Set(r.tratte) == Set((r.k - 1) * 256 + 1:r.k * 256), R), "/64")
        p("coppie distinte per (m, n): ", length(unique(COPPIE)), "; m = 0: ", count(c -> c[1] == 0.0, COPPIE),
          " (righe 1-256: ", count(c -> c[1] == 0.0, COPPIE[1:256]), "); 0 < m < m_min: ", count(c -> 0 < c[1] < CFG.m_min_fc, COPPIE))
        p()
        p("## Stato, tipo_esito, costo dei non completati (totali)")
        tot = Dict{Tuple{String,String,String},Int}()
        for r in R, (k2, c) in r.cnt; tot[k2] = get(tot, k2, 0) + c; end
        for (k2, c) in sort!(collect(tot); by = x -> (-x[2]))
            p(@sprintf("  %-10s %-10s costo=%-6s %10s  %s", k2[1], k2[2], k2[3] == "NaN" ? "—" : k2[3], fmt(c), pct(c, sum(r.nr for r in R))))
        end
        for s in STATI
            n_ = sum((c for (k2, c) in tot if k2[1] == s); init = 0)
            p(@sprintf("  %-10s %10s  %s", s, fmt(n_), pct(n_, sum(r.nr for r in R))))
        end
        p("motivi (", length(diz), " distinti):")
        for m in diz
            p(@sprintf("  %8s  %s", fmt(get(motivi, m, 0)), m == "" ? "(vuoto)" : length(m) > 160 ? m[1:prevind(m, 160)] * "…" : m))
        end
        p("storage_non_convergente per stato:")
        snc = Dict{Tuple{String,String},Int}()
        for r in R, (k2, c) in r.snc; snc[k2] = get(snc, k2, 0) + c; end
        for (k2, c) in sort!(collect(snc)); p("  ", k2, " => ", fmt(c)); end
        p()
        p("## Errori: confronto con errori_P9_D28_16384.csv")
        p("righe nel file: ", length(err_file), "; colonne del file: ", length(h_err), ", intestazione = registro: ", h_err == INTEST)
        p("righe di errore nei registri: ", length(err_reg))
        p("stessi casi: ", Set(keys(err_file)) == Set(keys(err_reg)), "; righe identiche campo per campo: ",
          count(k2 -> haskey(err_reg, k2) && err_reg[k2] == err_file[k2], collect(keys(err_file))))
        dif = [k2 for k2 in keys(err_file) if haskey(err_reg, k2) && err_reg[k2] != err_file[k2]]
        if !isempty(dif)
            k2 = first(dif); q = findall(i -> err_reg[k2][i] != err_file[k2][i], 1:NCOL)
            p("  esempio di differenza (", k2, "): colonne ", INTEST[q], " registro ", err_reg[k2][q], " file ", err_file[k2][q])
        end
        er_t = Dict{String,Int}()
        for v in values(err_reg); er_t[v[2]] = get(er_t, v[2], 0) + 1; end
        p("tratte con errori: ", sort!(collect(er_t)))
        p("prefissi dei motivi di errore: ", unique(first(split(v[7], ':')) for v in values(err_reg)))
        p()
        p("## Penalità sulle completed")
        pc = Dict{Float64,Int}()
        for r in R, (k2, c) in r.pen_cnt; pc[k2] = get(pc, k2, 0) + c; end
        p("costo − total_cost_EUR_km (arrotondato): ", join([@sprintf("%g: %s", k2, fmt(c)) for (k2, c) in sort!(collect(pc))], ", "))
        p("fuori da {0,1000,3000,4000,5000,6000,8000,9000} (o non intero entro 1e-6): ", sum(r.pen_fuori for r in R))
        p("costo !== total_cost_EUR_km + penalità dai vincoli (1000·[peso_t>0] + 3000·[scarica_100s>0] + 5000·[soc_pt>0]): ", sum(r.pen_inesatta for r in R))
        p("penalità ≠ quella dei vincoli: ", sum(r.incoer_vinc for r in R))
        p("vincoli > 0 ≠ grandezze fisiche (massa > limite, |scarica_s| > 1e-6, SOC_end < 0,2): ", sum(r.incoer_fis for r in R))
        p("tipo_esito ≠ quello atteso dai vincoli: ", sum(r.incoer_tipo for r in R))
        es = reduce(vcat, (r.esempi for r in R)); isempty(es) || p("esempi: ", first(es, 10))
        p()
        p("## Costo ricostruito: costo_da_grandezze(riga_registro_dict(riga); cfg = ConfigModello()) sulle completed")
        p("righe completed: ", fmt(sum(r.n_comp for r in R)))
        p("costo_totale !== total_cost_EUR_km: ", sum(r.costo_tot_div for r in R), "; scarto massimo ", maximum(r.maxscarto for r in R),
          " (relativo ", maximum(r.maxscarto_rel for r in R), ")")
        p("costo_totale: distanza massima in ULP ", maximum(r.ulp_max for r in R))
        p("costo (con penalità) !== costo del registro: ", sum(r.costo_div for r in R))
        p("diagnostica (cost_repl_batt_EUR_km_att): righe con batteria limitata dal calendario e ≥ 1 sostituzione (t = 15 anni, 1,04^15 a esponente intero): ",
          fmt(sum(r.diag_cand for r in R)))
        p("  voce diversa dal registro: ", fmt(sum(r.diag_div for r in R)), ", di cui tra quelle righe: ", fmt(sum(r.diag_div_cand for r in R)))
        p("  ricalcolo a mano con la potenza di questa macchina === voce di costo_da_grandezze: ", fmt(sum(r.diag_fuso_mac for r in R)))
        p("  ricalcolo con pow_body a muladd NON fusi === colonna del registro: ", fmt(sum(r.diag_nofma_reg for r in R)))
        p("  righe con costo_totale diverso, tutte tra queste: ", sum(r.diag_tot_in_div for r in R) == sum(r.costo_tot_div for r in R),
          " (", sum(r.diag_tot_in_div for r in R), " su ", sum(r.costo_tot_div for r in R), ")")
        vd = Dict{String,Int}(); vm = Dict{String,Float64}()
        for r in R, (k2, c) in r.voci_div; vd[k2] = get(vd, k2, 0) + c; vm[k2] = max(get(vm, k2, 0.0), r.voci_max[k2]); end
        p("voci di cost_details diverse dalla colonna (isequal) su ", length(VOCI_REGISTRO), " voci: ", isempty(vd) ? "nessuna" : join(["$k2: $(vd[k2]) (max $(vm[k2]))" for k2 in sort!(collect(keys(vd)))], "; "))
        p()
        p("## NaN / +Inf / −Inf per colonna e gruppo (righe per gruppo: ", join(["$(NOMI_GRUPPI[g]) $(fmt(sum(r.ngr[g] for r in R)))" for g in 1:5], ", "), ")")
        nan = sum(r.nan for r in R); pinf = sum(r.pinf for r in R); minf = sum(r.minf for r in R)
        ngr = sum(r.ngr for r in R)
        p(@sprintf("%-30s | %s", "colonna", join([@sprintf("%-26s", g) for g in NOMI_GRUPPI], " | ")))
        for (q, c) in enumerate(COL_NUM)
            all(iszero, nan[q, :]) && all(iszero, pinf[q, :]) && all(iszero, minf[q, :]) && continue
            cel(g) = (nan[q, g] == ngr[g] && ngr[g] > 0) ? "tutte NaN" :
                     join(filter(!isempty, [nan[q, g] > 0 ? "NaN $(fmt(nan[q, g]))" : "", pinf[q, g] > 0 ? "+Inf $(fmt(pinf[q, g]))" : "",
                                            minf[q, g] > 0 ? "−Inf $(fmt(minf[q, g]))" : ""]), ", ")
            p(@sprintf("%-30s | %s", c, join([@sprintf("%-26s", cel(g)) for g in 1:5], " | ")))
        end
        p("colonne numeriche senza NaN né Inf in nessun gruppo: ", join([c for (q, c) in enumerate(COL_NUM) if all(iszero, nan[q, :]) && all(iszero, pinf[q, :]) && all(iszero, minf[q, :])], ", "))
        p()
        p("## Tempi della campagna")
        p("prima riga scritta ", minimum(r.fine_min for r in R), ", ultima ", maximum(r.fine_max for r in R))
        p("somma di tempo_s (CPU per valutazione): ", @sprintf("%.1f h", sum(r.tempo_cpu for r in R) / 3600),
          "; media ", @sprintf("%.1f ms", 1000 * sum(r.tempo_cpu for r in R) / sum(r.nr for r in R)))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    # "solo_report": rifà il testo da log/01_blocchi.jls, senza rileggere i CSV
    "solo_report" in ARGS ? report(deserialize(joinpath(DATI, "log", "01_blocchi.jls"))...) : main()
end
