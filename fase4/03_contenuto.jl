# fase4/03_contenuto.jl: passo 3, contenuto del dataset (tutte le righe, dall'Arrow).
#   julia -t 8 --project=fase4 fase4/03_contenuto.jl
# Scrive risultati/03_contenuto.txt, risultati/03_colonne.csv, risultati/coppie_riassunto.csv e
# arrow/tratte_riassunto.arrow (fuori da Google Drive). Le figure sono in 04_figure.jl.

include(joinpath(@__DIR__, "comune.jl"))
using Statistics, Random, Serialization

const TOL = 1e-12
const COPPIE = leggi_coppie()
const SOGLIE = [x.m for x in TP.soglie_controllo(CFG)]
const P_MAX = TP.Objective.P_MAX_DEF
const V_NOM = TP.Objective.V_NOMINALE
const RIF = TP.riferimento_batteria(195_000.0, V_NOM)
const LIM = TP.QUOTA_PESO_PROPULSIONE * 195_000.0
const ST_C, ST_R, ST_E = Int8(1), Int8(2), Int8(3)
const T_FATT = Int8(1)

# variazione relativa entro ogni gruppo: 0 se tutti uguali (isequal), Inf se finiti e non finiti mescolati
# (o non finiti diversi), altrimenti (max − min)/max(|max|, |min|); NaN per i gruppi vuoti
function variazioni(x::Vector{Float64}, gid::AbstractVector{<:Integer}, G::Int, mask::AbstractVector{Bool})
    mn = fill(Inf, G); mx = fill(-Inf, G); nn = zeros(Int, G); v0 = zeros(G); eq = trues(G); visto = falses(G)
    @inbounds for i in eachindex(x)
        mask[i] || continue
        g = gid[i]; v = x[i]
        if !visto[g]; visto[g] = true; v0[g] = v; elseif !isequal(v, v0[g]); eq[g] = false; end
        if isfinite(v); v < mn[g] && (mn[g] = v); v > mx[g] && (mx[g] = v); else nn[g] += 1; end
    end
    rv = fill(NaN, G)
    for g in 1:G
        visto[g] || continue
        rv[g] = eq[g] ? 0.0 : nn[g] > 0 ? Inf : (s = max(abs(mn[g]), abs(mx[g])); s == 0 ? 0.0 : (mx[g] - mn[g]) / s)
    end
    return rv
end
q(v, p) = (w = filter(!isnan, v); isempty(w) ? NaN : quantile(w, p))
g3(x) = isnan(x) ? "—" : x == 0 ? "0" : isinf(x) ? "Inf" : @sprintf("%.3g", x)

function main()
    mkpath(RIS)
    t0 = time()
    D = carica_tutto()
    N = length(D["tratta"])
    @printf("caricate %d righe, %d colonne in %.1f s\n", N, length(D), time() - t0); flush(stdout)
    tr = D["tratta"]; cp = D["coppia"]; st = D["stato"]; te = D["tipo_esito"]; m = D["m"]; n = D["n"]
    snc = D["storage_non_convergente"]
    comp = st .== ST_C
    sim = st .!= ST_E                      # simulate: completed e rejected (D3)
    fatt = te .== T_FATT
    ibr = m .> 0
    d28 = [x === true for x in snc]
    numcols = [c for c in String.(keys(D)) if eltype(D[c]) === Float64]
    numcols = [c for c in COL_NUM if c in numcols]          # ordine del registro
    out = IOBuffer()
    p(x...) = (println(out, x...); println(x...))

    p("# Passo 3: contenuto del dataset P9_D28_16384 (", now(), ", ", Threads.nthreads(), " thread)")
    p("righe ", fmt(N), ": completed ", fmt(count(comp)), ", fattibili ", fmt(count(fatt)), ", rejected ", fmt(count(st .== ST_R)), ", error ", fmt(count(st .== ST_E)))

    # ── 1. dipendenza delle colonne da tratta e coppia (completed) ──────────────────
    p("\n## 1. Colonne numeriche: costante, funzione della sola coppia, della sola tratta o di entrambe (completed, tolleranza relativa $TOL)")
    uno = ones(Int8, N)
    righe_col = Vector{Any}(undef, length(numcols))
    Threads.@threads :dynamic for j in eachindex(numcols)
        x = D[numcols[j]]
        rg = variazioni(x, uno, 1, comp)[1]
        rc = variazioni(x, cp, NCOPPIE, comp)
        rt = variazioni(x, tr, NTRATTE, comp)
        cl = rg <= TOL ? "costante" : maximum(filter(!isnan, rc)) <= TOL ? "solo coppia" :
             maximum(filter(!isnan, rt)) <= TOL ? "solo tratta" : "entrambe"
        xs = x[comp]; f = filter(isfinite, xs)
        righe_col[j] = (col = numcols[j], classe = cl, min = isempty(f) ? NaN : minimum(f), max = isempty(f) ? NaN : maximum(f),
                        nonfin = count(!isfinite, xs), rc_max = maximum(filter(!isnan, rc)),
                        rt_max = maximum(filter(!isnan, rt)), rt_med = q(rt, 0.5), rt_p99 = q(rt, 0.99),
                        rt_ok = count(v -> v <= TOL, rt) / count(!isnan, rt))
    end
    open(joinpath(RIS, "03_colonne.csv"), "w") do io
        println(io, "colonna,classe,min,max,non_finiti,var_rel_max_entro_coppia,var_rel_max_entro_tratta,var_rel_mediana_entro_tratta,var_rel_p99_entro_tratta,quota_tratte_costante")
        for r in righe_col
            println(io, join([r.col, r.classe, r.min, r.max, r.nonfin, r.rc_max, r.rt_max, r.rt_med, r.rt_p99, r.rt_ok], ','))
        end
    end
    p(@sprintf("%-30s %-12s %11s %11s %9s %11s %11s %11s %11s", "colonna", "classe", "min", "max", "non fin.", "maxΔ coppia", "maxΔ tratta", "medΔ tratta", "p99Δ tratta"))
    for r in righe_col
        p(@sprintf("%-30s %-12s %11s %11s %9s %11s %11s %11s %11s", r.col, r.classe, g3(r.min), g3(r.max), fmt(r.nonfin), g3(r.rc_max), g3(r.rt_max), g3(r.rt_med), g3(r.rt_p99)))
    end
    p("(Δ = variazione relativa (max−min)/max|·| entro il gruppo; Inf = valori finiti e non finiti nello stesso gruppo)")
    p("per classe: ", join(["$k: $(count(r -> r.classe == k, righe_col))" for k in ("costante", "solo coppia", "solo tratta", "entrambe")], ", "))

    # ── 2. formule esatte tra colonne (===, completed salvo dove detto) ─────────────
    p("\n## 2. Formule esatte tra colonne (=== bit per bit; sulle completed salvo dove detto)")
    C(c) = D[c]
    function prova(nome, mask, f)
        idx = findall(mask)
        nd = Threads.Atomic{Int}(0); mx = zeros(Threads.nthreads() * 4)
        Threads.@threads :static for i in idx
            a, b = f(i)
            if !(a === b)
                Threads.atomic_add!(nd, 1)
                s = max(abs(a), abs(b)); r = s == 0 ? 0.0 : abs(a - b) / s
                t = Threads.threadid(); isnan(r) || (mx[t] = max(mx[t], r))
            end
        end
        p(@sprintf("  %-92s righe %9s  diverse %9s  scarto rel. max %s", nome, fmt(length(idx)), fmt(nd[]), g3(maximum(mx))))
        return nd[]
    end
    nvg, nva, dur = C("n_viaggi_giorno"), C("n_viaggi_anno"), C("durata_viaggio_s")
    prova("n_viaggi_giorno = matlab_round(36000/(durata_viaggio_s+1))", sim, i -> (nvg[i], Float64(TP.matlab_round(36000 / (dur[i] + 1)))))
    prova("n_viaggi_anno = 365·n_viaggi_giorno", sim, i -> (nva[i], nvg[i] * 365))
    prova("km_anno = n_viaggi_anno·km_viaggio", sim, i -> (C("km_anno")[i], nva[i] * C("km_viaggio")[i]))
    prova("massa_propulsione = massa_batteria + massa_FC + massa_serbatoio", sim, i -> (C("massa_propulsione_kg")[i], C("massa_batteria_kg")[i] + C("massa_FC_kg")[i] + C("massa_serbatoio_kg")[i]))
    prova("massa_treno = 195000 + massa_FC + massa_batteria + massa_serbatoio", sim, i -> (C("massa_treno_kg")[i], 195000.0 + C("massa_FC_kg")[i] + C("massa_batteria_kg")[i] + C("massa_serbatoio_kg")[i]))
    prova("H2_serbatoio = massa_serbatoio·0,055", sim, i -> (C("H2_serbatoio_kg")[i], C("massa_serbatoio_kg")[i] * 0.055))
    prova("P_max_FC_kW = P_max·m (P_max = 1435/η + 200)", sim, i -> (C("P_max_FC_kW")[i], P_MAX * m[i]))
    fcz = Dict(c => TP.taglia_FC_2(P_MAX * COPPIE[c][1], V_NOM; r = TP.rapporto_picco_fc()) for c in 1:NCOPPIE)
    bt = Dict(c => TP.taglia_batteria_da_n(COPPIE[c][2], RIF, V_NOM) for c in 1:NCOPPIE)
    prova("P_nom_fc_kW = taglia_FC_2(m·P_max; r = rapporto_picco_fc()).P_nom_FC", comp .& ibr, i -> (C("P_nom_fc_kW")[i], fcz[cp[i]].P_nom_FC))
    prova("P_nom_fc_kW = 0 a sola batteria", comp .& .!ibr, i -> (C("P_nom_fc_kW")[i], 0.0))
    prova("massa_FC_kg = taglia_FC_2(...).peso_totale_FC (0 a sola batteria)", sim, i -> (C("massa_FC_kg")[i], ibr[i] ? fcz[cp[i]].peso_totale_FC : 0.0))
    prova("n_celle_FC = taglia_FC_2(...).n_celle_FC (0 a sola batteria)", sim, i -> (C("n_celle_FC")[i], ibr[i] ? Float64(fcz[cp[i]].n_celle_FC) : 0.0))
    prova("C_batt_kWh = taglia_batteria_da_n(n, riferimento_batteria(195 t), 1500).E_batteria", comp, i -> (C("C_batt_kWh")[i], bt[cp[i]].E_batteria))
    prova("massa_batteria_kg = taglia_batteria_da_n(...).peso_totale_batteria", sim, i -> (C("massa_batteria_kg")[i], bt[cp[i]].peso_totale_batteria))
    prova("n_stringhe_batteria = taglia_batteria_da_n(...).n_stringhe_batteria", sim, i -> (C("n_stringhe_batteria")[i], Float64(bt[cp[i]].n_stringhe_batteria)))
    prova("E_ref_kWh = riferimento_batteria(195 t, 1500).E_ref", sim, i -> (C("E_ref_kWh")[i], RIF.E_ref))
    prova("limite_massa_propulsione_kg = 0,15·195000", sim, i -> (C("limite_massa_propulsione_kg")[i], LIM))
    soc0 = unique(C("SOC_iniziale")[sim]); p("  SOC_iniziale: valori distinti ", soc0)
    prova("E_ricarica_rete = ((SOC_iniziale − SOC_end)·Capacita_batteria(n)·1500)/1000", comp,
          i -> (C("E_ricarica_rete_kWh")[i], ((C("SOC_iniziale")[i] - C("SOC_end")[i]) * bt[cp[i]].Capacita_batteria * V_NOM) / 1000.0))
    prova("vincolo_soc_pt = 100·(0,2 − SOC_end)", comp, i -> (C("vincolo_soc_pt")[i], 100 * (0.2 - C("SOC_end")[i])))
    prova("E_ricarica_rete = ((SOC_iniziale − (0,2 − vincolo_soc_pt/100))·Cap(n)·1500)/1000 (rejected D3)", st .== ST_R,
          i -> (C("E_ricarica_rete_kWh")[i], ((C("SOC_iniziale")[i] - (0.2 - C("vincolo_soc_pt")[i] / 100)) * bt[cp[i]].Capacita_batteria * V_NOM) / 1000.0))
    prova("vincolo_peso_t = (massa_propulsione − 29250)/1000", sim, i -> (C("vincolo_peso_t")[i], (C("massa_propulsione_kg")[i] - LIM) / 1000))
    prova("vincolo_scarica_100s = |scarica_s|/100", sim, i -> (C("vincolo_scarica_100s")[i], abs(C("scarica_s")[i]) / 100))
    prova("E_frenatura_recuperata = E_frenatura_disponibile − frenata_dissipata", sim,
          i -> (C("E_frenatura_recuperata_kWh")[i], C("E_frenatura_disponibile_kWh")[i] - C("frenata_dissipata_kWh")[i]))
    prova("ore_FC_viaggio_h = durata/3600 (ibrido), 0 (sola batteria)", sim, i -> (C("ore_FC_viaggio_h")[i], ibr[i] ? dur[i] / 3600.0 : 0.0))
    prova("I_stringa_scarica_max_A = C_rate_scarica_max·2,5", sim, i -> (C("I_stringa_scarica_max_A")[i], C("C_rate_scarica_max")[i] * 2.5))
    prova("vita_batt_viaggi = min(vita_batt_cicli_viaggi, 15·n_viaggi_anno)", sim, i -> (C("vita_batt_viaggi")[i], min(C("vita_batt_cicli_viaggi")[i], 15.0 * nva[i])))
    prova("vita_batt_anni = vita_batt_viaggi/n_viaggi_anno", sim, i -> (C("vita_batt_anni")[i], C("vita_batt_viaggi")[i] / nva[i]))
    prova("vita_batt_cicli_anni = vita_batt_cicli_viaggi/n_viaggi_anno", sim, i -> (C("vita_batt_cicli_anni")[i], C("vita_batt_cicli_viaggi")[i] / nva[i]))
    prova("vita_FC_anni = vita_FC_viaggi/n_viaggi_anno (ibrido)", sim .& ibr, i -> (C("vita_FC_anni")[i], C("vita_FC_viaggi")[i] / nva[i]))
    fvita(i) = (ov = dur[i] / 3600.0; l = (C("vita_FC_f1_ore")[i] / ov) / C("f_degrado_FC")[i]; t = C("ore_max_FC")[i] / ov; t < l ? t : l)
    prova("vita_FC_viaggi = min((vita_FC_f1_ore/ore)/f, 25000/ore), ore = durata/3600 (ibrido; costo_da_grandezze con f diverso)", sim .& ibr, i -> (C("vita_FC_viaggi")[i], fvita(i)))
    prova("vita_FC_ore (D16) = vita_FC_viaggi·durata/3600 (ibrido)", comp .& ibr, i -> (C("vita_FC_ore")[i], C("vita_FC_viaggi")[i] * dur[i] / 3600.0))
    L = Dict{Int,Float64}()
    let l = readlines(FILE_DESIGN); h = split(l[1], ','); jL = findfirst(==("L_km"), h)
        for x in l[2:end]; c = split(x, ','); L[parse(Int, c[1])] = parse(Float64, c[jL]); end
    end
    prova("km_viaggio = 2·L_km del design", sim, i -> (C("km_viaggio")[i], 2 * L[tr[i]]))
    tet = count(i -> C("vita_FC_tetto")[i] == 1.0, findall(comp .& ibr))
    p("  vita della FC limitata dal tetto di 25000 h (vita_FC_tetto = 1): ", fmt(tet), " righe ibride completed su ", fmt(count(comp .& ibr)))
    p("  vita della batteria limitata dal calendario (vita_batt_limite_calendario = 1): ", fmt(count(i -> C("vita_batt_limite_calendario")[i] == 1.0, findall(comp))), " completed su ", fmt(count(comp)))
    p("  sostituzione_FC_saltata = 1: ", count(i -> C("sostituzione_FC_saltata")[i] == 1.0, findall(sim)), " (D15 spenta)")

    # ── 3. controlli fisici ──────────────────────────────────────────────────────────
    p("\n## 3. Controlli fisici (completed)")
    ck(nome, mask, f) = (k = count(i -> !f(i), findall(mask)); p(@sprintf("  %-70s violazioni %s su %s", nome, fmt(k), fmt(count(mask)))); k)
    ck("durata A/R ≤ 12 h (43200 s)", comp, i -> dur[i] <= 43200)
    p("  durata massima ", maximum(dur[comp]), " s = ", round(maximum(dur[comp]) / 3600; digits = 2), " h; minima ", minimum(dur[comp]), " s")
    ck("n_viaggi_giorno ≥ 1", comp, i -> nvg[i] >= 1)
    p("  n_viaggi_giorno: ", sort!([(v, count(==(v), nvg[comp])) for v in unique(nvg[comp])]))
    for c in ("SOC_iniziale", "SOC_minimo", "SOC_massimo", "SOC_end")
        ck("$c in [0, 1]", comp, i -> 0 <= C(c)[i] <= 1)
    end
    ck("SOC_minimo ≤ SOC_end ≤ SOC_massimo", comp, i -> C("SOC_minimo")[i] <= C("SOC_end")[i] <= C("SOC_massimo")[i])
    ck("massa_batteria, massa_propulsione, massa_treno > 0", comp, i -> C("massa_batteria_kg")[i] > 0 && C("massa_propulsione_kg")[i] > 0 && C("massa_treno_kg")[i] > 0)
    ck("massa_FC, massa_serbatoio > 0 (ibrido)", comp .& ibr, i -> C("massa_FC_kg")[i] > 0 && C("massa_serbatoio_kg")[i] > 0)
    ck("massa_FC = massa_serbatoio = H2_cons = 0 (sola batteria)", comp .& .!ibr, i -> C("massa_FC_kg")[i] == 0 && C("massa_serbatoio_kg")[i] == 0 && C("H2_cons_kg")[i] == 0)
    ck("H2_cons_kg > 0 (ibrido)", comp .& ibr, i -> C("H2_cons_kg")[i] > 0)
    ck("total_cost_EUR_km > 0", comp, i -> C("total_cost_EUR_km")[i] > 0)
    voci_pos = ["CAPEX_FC_EUR_km", "CAPEX_batt_EUR_km", "CAPEX_tank_EUR_km", "OPEX_batt_rech_EUR_km_att", "OPEX_H2_rech_EUR_km_att",
                "OPEX_mant_FC_EUR_km_att", "OPEX_mant_batt_EUR_km_att", "OPEX_mant_tank_EUR_km_att", "cost_repl_FC_EUR_km_att", "cost_repl_batt_EUR_km_att"]
    ck("le 10 voci di costo ≥ 0", comp, i -> all(C(v)[i] >= 0 for v in voci_pos))
    ck("valore_residuo_FC/batt ≤ 0", comp, i -> C("valore_residuo_FC_EUR_km")[i] <= 0 && C("valore_residuo_batt_EUR_km")[i] <= 0)
    ck("E_ricarica_rete_kWh ≥ 0 (SOC_end ≤ SOC_iniziale)", comp, i -> C("E_ricarica_rete_kWh")[i] >= 0)
    ck("E_ricarica_rete_kWh ≥ 0 sulle fattibili", fatt, i -> C("E_ricarica_rete_kWh")[i] >= 0)
    p("  num_repl_batt: massimo ", maximum(C("num_repl_batt")[comp]), " (fattibili: ", maximum(C("num_repl_batt")[fatt]), "); num_repl_FC: massimo ", maximum(C("num_repl_FC")[comp]),
      " (fattibili: ", maximum(C("num_repl_FC")[fatt]), ")")

    # durata e massa a tratta fissa (D27)
    p("\n### Durata, energie e massa del treno a tratta fissa (D27)")
    p("  Dal codice: la dinamica riceve structure_caratteristiche_treno(FC, batteria, serbatoio, carico), che usa solo la somma M;")
    p("  durata, E_trazione e E_frenatura_disponibile dipendono quindi solo da (tratta, massa_treno).")
    ordine = sortperm(tr)                 # righe raggruppate per tratta
    inizio = searchsortedfirst.(Ref(tr[ordine]), 1:NTRATTE)
    res = Vector{NTuple{8,Int}}(undef, NTRATTE); maxcalo = zeros(NTRATTE)
    Mt = C("massa_treno_kg"); Et = C("E_trazione_kWh")
    Threads.@threads :dynamic for t in 1:NTRATTE
        a = inizio[t]; b = t == NTRATTE ? N : inizio[t + 1] - 1
        idx = [ordine[j] for j in a:b if comp[ordine[j]]]
        sort!(idx; by = i -> Mt[i])
        conf = 0; ok = 0; strett = 0; viol = 0; okE = 0; violE = 0; cons = 0; consv = 0; mc = 0.0
        for x in 1:length(idx), y in x+1:length(idx)
            i, j = idx[x], idx[y]
            Mt[i] < Mt[j] || continue
            conf += 1
            dur[i] <= dur[j] ? (ok += 1; dur[i] < dur[j] && (strett += 1)) : (viol += 1; mc = max(mc, dur[i] - dur[j]))
            Et[i] <= Et[j] ? (okE += 1) : (violE += 1)
        end
        for x in 1:length(idx)-1
            i, j = idx[x], idx[x+1]
            Mt[i] < Mt[j] || continue
            cons += 1; dur[i] > dur[j] && (consv += 1)
        end
        res[t] = (conf, ok, strett, viol, okE, violE, cons, consv); maxcalo[t] = mc
    end
    S(k) = sum(r[k] for r in res)
    p("  coppie di righe confrontabili (stessa tratta, completed, massa_treno diversa): ", fmt(S(1)))
    p("  durata non decrescente con la massa: ", fmt(S(2)), " (", pct(S(2), S(1)), "); strettamente crescente: ", pct(S(3), S(1)),
      "; durata che cala con la massa: ", fmt(S(4)), " (", pct(S(4), S(1)), "), calo massimo ", maximum(maxcalo), " s")
    p("  tra righe consecutive in massa: ", fmt(S(7)), " confronti, cali ", fmt(S(8)), " (", pct(S(8), S(7)), ")")
    p("  tratte con almeno un calo: ", count(r -> r[4] > 0, res), "; con più dell'1% di coppie in calo: ", count(r -> r[1] > 0 && r[4] / r[1] > 0.01, res))
    p("  E_trazione non decrescente con la massa: ", pct(S(5), S(1)), " (cali: ", fmt(S(6)), ")")

    # ── 4. D28 ───────────────────────────────────────────────────────────────────────
    p("\n## 4. D28: ciclo dello storage non convergente")
    idx28 = findall(d28)
    p("  righe: ", fmt(length(idx28)), " (", pct(length(idx28), count(sim .& ibr)), " delle righe ibride simulate); stati: ",
      [(STATI[s], count(i -> st[i] == s, idx28)) for s in (ST_C, ST_R)], "; tipi: ", [(TIPI_ESITO[k], count(i -> te[i] == k, idx28)) for k in 1:5])
    p("  fattibili: ", fmt(count(i -> fatt[i], idx28)), "; tratte coinvolte: ", fmt(length(unique(tr[idx28]))), "; coppie coinvolte: ", length(unique(cp[idx28])))
    p("  tutte le righe D28 hanno m > 0: ", all(ibr[idx28]), "; storage_iterazioni delle righe D28: ", sort!(unique(C("storage_iterazioni")[idx28])))
    bm = [0.0, 0.03, SOGLIE..., 0.15, 0.2, 0.3, 0.5, 0.75, 1.0 + 1e-9]
    p("  per m (righe D28 / righe simulate con quella m):")
    for k in 1:length(bm)-1
        sel = findall(i -> bm[k] <= m[i] < bm[k+1], 1:N) ; sel = filter(i -> sim[i], sel)
        isempty(sel) && continue
        p(@sprintf("    m ∈ [%.4f, %.4f): %7s / %9s  %s", bm[k], bm[k+1], fmt(count(i -> d28[i], sel)), fmt(length(sel)), pct(count(i -> d28[i], sel), length(sel))))
    end
    p("  per n:")
    for k in 0:9
        sel = filter(i -> sim[i] && ibr[i] && k / 10 <= n[i] < (k + 1) / 10, 1:N)
        p(@sprintf("    n ∈ [%.1f, %.1f): %7s / %9s  %s", k / 10, (k + 1) / 10, fmt(count(i -> d28[i], sel)), fmt(length(sel)), pct(count(i -> d28[i], sel), length(sel))))
    end
    si = C("storage_iterazioni")
    p("  storage_iterazioni sulle righe ibride simulate: ", join(["$v: $(fmt(c))" for (v, c) in sort!([(v, count(==(v), si[sim .& ibr])) for v in unique(si[sim .& ibr])])], ", "))
    p("  storage_iterazioni sulle righe a sola batteria: ", unique(si[sim .& .!ibr]))
    p("  coppie con più righe D28: ", [(Int(c), COPPIE[c], k) for (c, k) in first(sort!([(c, count(i -> cp[i] == c, idx28)) for c in unique(cp[idx28])]; by = x -> -x[2]), 8)])

    # ── 5. riassunto per tratta ──────────────────────────────────────────────────────
    p("\n## 5. Per tratta (tratte_riassunto.arrow)")
    tot = C("total_cost_EUR_km")
    nf = zeros(Int32, NTRATTE); best = fill(NaN, NTRATTE); bestc = zeros(Int16, NTRATTE); bestb = fill(NaN, NTRATTE); besti = fill(NaN, NTRATTE)
    nfb = zeros(Int32, NTRATTE); nfi = zeros(Int32, NTRATTE); best28 = falses(NTRATTE)
    qt = zeros(NTRATTE, 5); qr = zeros(NTRATTE); qe = zeros(NTRATTE); q28 = zeros(NTRATTE); nr = zeros(Int, NTRATTE)
    for i in 1:N
        t = tr[i]; nr[t] += 1
        qt[t, te[i]] += 1; st[i] == ST_R && (qr[t] += 1); st[i] == ST_E && (qe[t] += 1); d28[i] && (q28[t] += 1)
        fatt[i] || continue
        nf[t] += 1; ibr[i] ? (nfi[t] += 1) : (nfb[t] += 1)
        c = tot[i]
        if c < best[t] || isnan(best[t]) || (c == best[t] && cp[i] < bestc[t])
            best[t] = c; bestc[t] = cp[i]; best28[t] = d28[i]
        end
        ibr[i] ? (isnan(besti[t]) || c < besti[t]) && (besti[t] = c) : (isnan(bestb[t]) || c < bestb[t]) && (bestb[t] = c)
    end
    regime = Int8[c == 0 ? 0 : COPPIE[c][1] == 0 ? 1 : 2 for c in bestc]
    riass = (tratta = Int32.(1:NTRATTE), n_righe = Int16.(nr), n_fattibili = Int16.(nf), n_fattibili_sola_batteria = Int16.(nfb), n_fattibili_ibride = Int16.(nfi),
             costo_migliore = best, coppia_migliore = bestc, m_migliore = [c == 0 ? NaN : COPPIE[c][1] for c in bestc],
             n_migliore = [c == 0 ? NaN : COPPIE[c][2] for c in bestc], regime_migliore = regime,
             costo_migliore_sola_batteria = bestb, costo_migliore_ibrido = besti, migliore_D28 = collect(best28),
             quota_fattibile = qt[:, 1] ./ nr, quota_piccola = qt[:, 2] ./ nr, quota_pesante = qt[:, 3] ./ nr, quota_mista = qt[:, 4] ./ nr,
             quota_errore = qt[:, 5] ./ nr, quota_rejected_D3 = qr ./ nr, quota_D28 = q28 ./ nr, senza_coppie_fattibili = nf .== 0)
    Arrow.write(FILE_RIASSUNTO_ARROW, riass; metadata = Dict("regime_migliore" => "0 = nessuna fattibile, 1 = sola batteria (m = 0), 2 = ibrido",
                "costo_migliore" => "total_cost_EUR_km della migliore fattibile delle 288 coppie (tipo_esito = fattibile); a parità la coppia di indice minore",
                "quote" => "frazioni delle 288 righe della tratta (quota_piccola comprende i rejected D3)"))
    p("  tratte senza nessuna coppia fattibile: ", count(nf .== 0), isempty(findall(nf .== 0)) ? "" : " → $(first(findall(nf .== 0), 20))")
    p("  coppie fattibili per tratta: min ", minimum(nf), ", mediana ", median(nf), ", max ", maximum(nf), "; quantili 1%/10%/90%: ", quantile(nf, [0.01, 0.1, 0.9]))
    p("  regime della migliore: sola batteria ", count(==(1), regime), ", ibrido ", count(==(2), regime), ", nessuna ", count(==(0), regime))
    p("  migliore nell'intervallo D25: ", [(j, count(c -> c > 0 && (x = COPPIE[c][1]; j == 0 ? x == 0 : j == 1 ? 0 < x < SOGLIE[1] : j == 2 ? SOGLIE[1] <= x < SOGLIE[2] : j == 3 ? SOGLIE[2] <= x < SOGLIE[3] : x >= SOGLIE[3]), bestc)) for j in 0:4])
    p("  tratte in cui la migliore fattibile è D28 (storage non convergente): ", count(best28))
    p("  coppie che sono la migliore in almeno una tratta: ", length(unique(bestc[bestc .> 0])), " su 288; le più frequenti: ",
      first(sort!([(Int(c), round.(COPPIE[c]; digits = 4), count(==(c), bestc)) for c in unique(bestc[bestc .> 0])]; by = x -> -x[3]), 10))
    p("  costo della migliore: min ", g3(minimum(filter(!isnan, best))), ", mediana ", g3(median(filter(!isnan, best))), ", max ", g3(maximum(filter(!isnan, best))), " €/km")
    bi = filter(!isnan, besti .- bestb)
    p("  migliore ibrida − migliore a sola batteria (tratte con entrambe, ", length(bi), "): mediana ", g3(median(bi)), " €/km, quota < 0 (vince l'ibrido): ", pct(count(<(0), bi), length(bi)))

    # ── 6. per coppia ────────────────────────────────────────────────────────────────
    p("\n## 6. Per coppia (risultati/coppie_riassunto.csv)")
    sc = C("scarica_s"); vs = C("vincolo_soc_pt"); vp = C("vincolo_peso_t")
    cf = zeros(Int, NCOPPIE); cr = zeros(Int, NCOPPIE); csc = zeros(Int, NCOPPIE); c28 = zeros(Int, NCOPPIE); cs = zeros(Int, NCOPPIE); cpz = zeros(Int, NCOPPIE); cn = zeros(Int, NCOPPIE); ce = zeros(Int, NCOPPIE)
    for i in 1:N
        c = cp[i]; cn[c] += 1
        fatt[i] && (cf[c] += 1); st[i] == ST_R && (cr[c] += 1); st[i] == ST_E && (ce[c] += 1); d28[i] && (c28[c] += 1)
        comp[i] && sc[i] > 0 && (csc[c] += 1); comp[i] && vs[i] > 0 && (cs[c] += 1); comp[i] && vp[i] > 0 && (cpz[c] += 1)
    end
    open(joinpath(RIS, "coppie_riassunto.csv"), "w") do io
        println(io, "coppia,m,n,origine,righe,quota_fattibili,quota_rejected_D3,quota_scarica_totale,quota_SOC_sotto_0.2,quota_peso_oltre,quota_D28,quota_errore")
        for c in 1:NCOPPIE
            println(io, join([c, @sprintf("%.17g", COPPIE[c][1]), @sprintf("%.17g", COPPIE[c][2]), c <= 256 ? "sobol" : "soglie", cn[c],
                              cf[c] / cn[c], cr[c] / cn[c], csc[c] / cn[c], cs[c] / cn[c], cpz[c] / cn[c], c28[c] / cn[c], ce[c] / cn[c]], ','))
        end
    end
    p("  coppie mai fattibili: ", count(==(0), cf), " → ", [(Int(c), round.(COPPIE[c]; digits = 3)) for c in findall(==(0), cf)][1:min(end, 30)])
    p("  coppie fattibili in tutte le tratte: ", count(==(NTRATTE), cf))
    p("  quota di fattibili per coppia: mediana ", g3(median(cf ./ cn)), ", max ", g3(maximum(cf ./ cn)))
    p("  coppie con rejected D3 > 50%: ", count(>(0.5), cr ./ cn), "; con scarica totale > 50%: ", count(>(0.5), csc ./ cn), "; con peso oltre il limite in tutte le tratte: ", count(==(NTRATTE), cpz))

    # ── 7. regolarità in (m, n) su 20 tratte a caso ──────────────────────────────────
    p("\n## 7. Regolarità in (m, n): 20 tratte a caso (seme 20261113), grafo dei 6 vicini tra le 288 coppie")
    rng = MersenneTwister(20261113)
    venti = sort!(randperm(rng, NTRATTE)[1:20])
    p("  tratte: ", venti)
    Q = ["H2_cons_kg", "E_ricarica_rete_kWh", "SOC_end", "num_repl_FC", "num_repl_batt", "total_cost_EUR_km", "durata_viaggio_s", "massa_serbatoio_kg", "vita_batt_cicli_viaggi", "vita_FC_f1_ore"]
    # grafo dei vicini nelle coordinate (m, n) normalizzate al dominio
    xy = [(c[1], c[2]) for c in COPPIE]
    archi = Set{Tuple{Int,Int}}()
    for a in 1:NCOPPIE
        d = [(hypot(xy[a][1] - xy[b][1], xy[a][2] - xy[b][2]), b) for b in 1:NCOPPIE if b != a]
        for (_, b) in first(sort!(d), 6); push!(archi, (min(a, b), max(a, b))); end
    end
    archi = collect(archi)
    riga = Dict{Tuple{Int32,Int16},Int}()
    for i in 1:N; tr[i] in venti && (riga[(tr[i], cp[i])] = i); end
    serialize(joinpath(DATI, "log", "03_venti.jls"), (venti = venti, righe = Dict(k => v for (k, v) in riga)))
    attraversa(a, b) = begin ma, mb = minmax(xy[a][1], xy[b][1]); any(s -> ma < s <= mb, SOGLIE) end
    p(@sprintf("  %-24s %8s %9s %9s | salti > 25%%: %6s %6s %6s %6s %6s %6s", "grandezza", "archi", ">10% amp", ">25% amp", "D25", "regime", "repl FC", "repl b.", "viaggi", "esito"))
    for qn in Q
        x = C(qn); na = 0; n10 = 0; n25 = 0; cause = zeros(Int, 6)
        for t in venti
            vals = [x[riga[(Int32(t), Int16(c))]] for c in 1:NCOPPIE if comp[riga[(Int32(t), Int16(c))]]]
            fv = filter(isfinite, vals); isempty(fv) && continue
            amp = maximum(fv) - minimum(fv); amp == 0 && continue
            for (a, b) in archi
                i, j = riga[(Int32(t), Int16(a))], riga[(Int32(t), Int16(b))]
                (comp[i] && comp[j] && isfinite(x[i]) && isfinite(x[j])) || continue
                na += 1; r = abs(x[i] - x[j]) / amp
                r > 0.10 && (n10 += 1)
                if r > 0.25
                    n25 += 1
                    attraversa(a, b) && (cause[1] += 1)
                    (m[i] == 0) != (m[j] == 0) && (cause[2] += 1)
                    C("num_repl_FC")[i] != C("num_repl_FC")[j] && (cause[3] += 1)
                    C("num_repl_batt")[i] != C("num_repl_batt")[j] && (cause[4] += 1)
                    nvg[i] != nvg[j] && (cause[5] += 1)
                    te[i] != te[j] && (cause[6] += 1)
                end
            end
        end
        p(@sprintf("  %-24s %8d %9s %9s | %18s %6d %6d %6d %6d %6d %6d", qn, na, pct(n10, na), pct(n25, na), fmt(n25) * " salti:", cause...))
    end
    p("  (amp = max − min della grandezza nella tratta; un salto può avere più cause)")
    p("  valori distinti per tratta (mediana sulle 20): ", [(qn, median([length(unique(C(qn)[[riga[(Int32(t), Int16(c))] for c in 1:NCOPPIE if comp[riga[(Int32(t), Int16(c))]]]])) for t in venti])) for qn in ("num_repl_FC", "num_repl_batt", "n_viaggi_giorno")])
    # zone rade delle 288 coppie
    p("\n### Zone rade delle 288 coppie")
    ib = [c for c in xy if c[1] > 0]
    nmax = TP.n_massima_sola_batteria(195_000.0, CFG)
    lo = (CFG.m_min_fc, 0.01); hi = (1.0, nmax)
    G = 400
    vuoti = Tuple{Float64,Float64,Float64}[]
    for a in 0:G, b in 0:G
        x = lo[1] + (hi[1] - lo[1]) * a / G; y = lo[2] + (hi[2] - lo[2]) * b / G
        push!(vuoti, (minimum(hypot(x - c[1], y - c[2]) for c in ib), x, y))
    end
    sort!(vuoti; rev = true)
    scelti = Tuple{Float64,Float64,Float64}[]
    for v in vuoti
        length(scelti) >= 6 && break
        all(s -> hypot(v[2] - s[2], v[3] - s[3]) > s[1] + v[1], scelti) && push!(scelti, v)
    end
    p("  dominio ibrido m ∈ [0,03, 1], n ∈ [0,01, ", round(nmax; digits = 5), "] con 256 coppie ibride: distanza media dal punto più vicino ", g3(mean(first.(vuoti))),
      ", 95° percentile ", g3(quantile(first.(vuoti), 0.95)), ", massima ", g3(vuoti[1][1]))
    p("  cerchi vuoti più grandi (raggio, centro m, n): ", [(round(s[1]; digits = 3), round(s[2]; digits = 3), round(s[3]; digits = 3)) for s in scelti])
    p("  bordi: coppie con m > 0,95: ", count(c -> c[1] > 0.95, ib), "; con n < 0,05: ", count(c -> c[2] < 0.05, ib), "; con n > 0,95: ", count(c -> c[2] > 0.95, ib))
    lim = [CFG.m_min_fc, SOGLIE..., 1.0]
    for k in 1:length(lim)-1
        nk = count(c -> lim[k] <= c[1] < lim[k+1] || (k == length(lim) - 1 && c[1] == 1.0), ib)
        p(@sprintf("  m ∈ [%.5f, %.5f): %3d coppie, larghezza %.4f, %.0f coppie per unità di m", lim[k], lim[k+1], nk, lim[k+1] - lim[k], nk / (lim[k+1] - lim[k])))
    end
    for s in SOGLIE
        sx = filter(c -> c[1] < s, ib); dx = filter(c -> c[1] >= s, ib)
        p(@sprintf("  soglia %.5f: coppia più vicina a sinistra a Δm = %.2e, a destra a Δm = %.2e", s, s - maximum(first.(sx)), minimum(first.(dx)) - s))
    end
    nb = sort!([c[2] for c in xy if c[1] == 0])
    p("  sola batteria: 32 valori di n tra ", round(nb[1]; digits = 4), " e ", round(nb[end]; digits = 4), ", passo massimo ", round(maximum(diff(nb)); digits = 4), ", mediano ", round(median(diff(nb)); digits = 4))

    # ── 8. prezzi: scenari sul blocco 1 ──────────────────────────────────────────────
    p("\n## 8. Scenari di prezzo con costo_da_grandezze (blocco 1, 256 tratte; solo prova del percorso)")
    b1 = findall(i -> tr[i] <= TRATTE_BLOCCO, 1:N)
    base = TP.ParametriCosto()
    scen = [("base", base), ("H2 ×0,5", TP.ParametriCosto(costo_H2 = base.costo_H2 * 0.5)), ("H2 ×2", TP.ParametriCosto(costo_H2 = base.costo_H2 * 2)),
            ("FC ×0,5", TP.ParametriCosto(costo_specifico_FC = base.costo_specifico_FC * 0.5))]
    g = Dict{String,Float64}()
    costi = Dict{String,Vector{Float64}}(); pen = Dict{String,Vector{Float64}}()
    for (nome, pr) in scen
        cv = fill(NaN, length(b1)); pv = fill(NaN, length(b1))
        for (k, i) in enumerate(b1)
            comp[i] || continue
            for c in COL_COSTO; g[c] = C(c)[i]; end
            r = TP.costo_da_grandezze(g, pr; cfg = CFG)
            cv[k] = r.costo; pv[k] = r.penalita
        end
        costi[nome] = cv; pen[nome] = pv
    end
    p("  penalità identiche in tutti gli scenari (la fattibilità non dipende dai prezzi): ", all(isequal(pen["base"], pen[s]) for (s, _) in scen))
    function migliori(nome)
        bc = Dict{Int32,Tuple{Float64,Int16}}()
        for (k, i) in enumerate(b1)
            fatt[i] || continue
            c = costi[nome][k]; t = tr[i]
            (!haskey(bc, t) || (c, cp[i]) < bc[t]) && (bc[t] = (c, cp[i]))
        end
        bc
    end
    B0 = migliori("base")
    for (nome, _) in scen[2:end]
        B = migliori(nome)
        ch = [t for t in keys(B0) if B[t][2] != B0[t][2]]
        reg(c) = COPPIE[c][1] == 0 ? "batteria" : "ibrido"
        dir = Dict{String,Int}()
        for t in ch; k = reg(B0[t][2]) * "→" * reg(B[t][2]); dir[k] = get(dir, k, 0) + 1; end
        dm = [COPPIE[B[t][2]][1] - COPPIE[B0[t][2]][1] for t in ch]; dn = [COPPIE[B[t][2]][2] - COPPIE[B0[t][2]][2] for t in ch]
        dc = [B[t][1] / B0[t][1] - 1 for t in keys(B0)]
        p(@sprintf("  %-8s migliore coppia cambiata in %3d tratte su %d; ", nome, length(ch), length(B0)), "cambi di regime ", dir,
          "; Δm mediano ", isempty(dm) ? "—" : g3(median(dm)), ", Δn mediano ", isempty(dn) ? "—" : g3(median(dn)),
          "; costo della migliore: variazione mediana ", @sprintf("%+.1f%%", 100median(dc)))
        # stessa riga del registro, ma è un'altra coppia: controlla che nei casi senza cambio il costo nuovo sia della stessa coppia
    end

    write(joinpath(RIS, "03_contenuto.txt"), String(take!(out)))
    @printf("fatto in %.1f s\n", time() - t0)
end

(abspath(PROGRAM_FILE) == @__FILE__) && main()
