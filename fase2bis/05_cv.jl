# Fase 2bis, passo 5 (= fase2/01_cv.jl sul riferimento v2): previsioni in validazione incrociata, 5 fold × 5 ripetizioni,
# STESSI fold di prova della fase 2 (stratificati sul regime v1, fold_esterni), seme fisso. In più la rete piccola (nn)
# per il solo costo, come confronto con il processo gaussiano (iperparametri: strati e larghezza dalla CV interna;
# arresto anticipato su un fold interno, vedi comune.jl).
# Ogni riga è una tratta, quindi la divisione è già per tratta. Gli iperparametri si scelgono con una CV interna a 3 fold
# sul solo training del fold (comune.jl: scegli), mai sul fold di prova. Le tratte reali non si usano.
#
# Per ogni famiglia (mediana, nn1, knn, rf, gb; gp solo per il costo) e insieme di input (p66, p69):
#   p_ibrido   classificatore ibrido / sola batteria (tutte le tratte del training)
#   m          regressore sulle sole ibride
#   n_ibr      regressore di n* sulle ibride; n_batt sulle sole batteria (si usa quello del regime previsto)
#   log costo  regressore su tutte
# nn1 copia l'ottimo (regime, m*, n*, costo) della tratta di training più vicina (caratteristiche standardizzate).
# In più, solo per rf e gb e solo nella ripetizione 1: H2 per viaggio e vita FC (ibride, log), energia di ricarica
# per viaggio (tutte, log).
#
# Uso, da ml_treno/fase2bis:   julia -t 8 --project=. 05_cv.jl
# Scrive GRANDI/cv/pred_r<r>_<insieme>.csv (riprende: salta i file già presenti) e GRANDI/cv/fisiche_r1_<insieme>.csv.

include(joinpath(@__DIR__, "comune.jl"))
const CV = joinpath(GRANDI, "cv"); mkpath(CV)
const FAM_DESIGN = [:mediana, :nn1, :knn, :rf, :gb]
const FAM_COSTO  = [:mediana, :nn1, :knn, :rf, :gb, :gp, :nn]
const FISICHE    = [("H2_viaggio_kg", :ibr), ("vita_FC_ore", :ibr), ("E_ricarica_viaggio_kWh", :tutte)]

d = dati()
ibr = d.y_ibrido .== 1
hpstr(hp) = join(["$k=$v" for (k, v) in pairs(hp)], ";")

function un_fold(X, itr, ite, fam, seme)
    yI = Float64.(ibr); ym = d.y_m_star; yn = d.y_n_star; yc = log.(d.y_costo_EUR_km)
    tI = findall(itr .& ibr); tB = findall(itr .& .!ibr); tA = findall(itr)
    Xte = X[ite, :]
    if fam === :nn1
        o = adatta(:nn1, :reg, X[tA, :], yc[tA], (k = 1,))
        j = tA[first.(vicini(o, Xte))]
        return (p = yI[j], m = ym[j], n_ibr = yn[j], n_batt = yn[j], logc = yc[j], hp = "k=1")
    end
    oc, hc = adatta_scelto(fam, :cls, X[tA, :], yI[tA]; seme)
    om, hm = adatta_scelto(fam, :reg, X[tI, :], ym[tI]; seme)
    oi, hi = adatta_scelto(fam, :reg, X[tI, :], yn[tI]; seme)
    ob, hb = adatta_scelto(fam, :reg, X[tB, :], yn[tB]; seme)
    ol, hl = adatta_scelto(fam, :reg, X[tA, :], yc[tA]; seme)
    return (p = prevedi(oc, Xte), m = prevedi(om, Xte), n_ibr = prevedi(oi, Xte), n_batt = prevedi(ob, Xte),
            logc = prevedi(ol, Xte), hp = join(["cls:" * hpstr(hc), "m:" * hpstr(hm), "n_ibr:" * hpstr(hi),
                                                "n_batt:" * hpstr(hb), "costo:" * hpstr(hl)], " "))
end

for r in 1:NREP, ins in (:p66, :p69)
    file = joinpath(CV, "pred_r$(r)_$(ins).csv")
    isfile(file) && (println("già fatto: ", file); continue)
    X = matrice(d, colonne(d, ins))
    f = fold_esterni(r)
    righe = DataFrame()
    fis = DataFrame()
    t0 = time()
    for k in 1:NFOLD
        itr = f .!= k; ite = .!itr; idx = findall(ite)
        seme = 1000r + k
        for fam in FAM_COSTO
            if fam === :gp
                o = adatta_gp(X[itr, :], log.(d.y_costo_EUR_km[itr]))
                lc = prevedi(o, X[ite, :])
                append!(righe, DataFrame(rip = r, fold = k, insieme = String(ins), famiglia = "gp", tratta = d.tratta[idx],
                                         p_ibrido = NaN, m_prev = NaN, n_ibr_prev = NaN, n_batt_prev = NaN,
                                         costo_prev = exp.(lc), iperparametri = "ARD-SE a massima verosimiglianza"))
                continue
            end
            if fam === :nn
                o, hp = adatta_scelto(:nn, :reg, X[itr, :], log.(d.y_costo_EUR_km[itr]); seme)
                append!(righe, DataFrame(rip = r, fold = k, insieme = String(ins), famiglia = "nn", tratta = d.tratta[idx],
                                         p_ibrido = NaN, m_prev = NaN, n_ibr_prev = NaN, n_batt_prev = NaN,
                                         costo_prev = exp.(prevedi(o, X[ite, :])), iperparametri = hpstr(hp) * ";epoche=$(o.epoche)"))
                continue
            end
            u = un_fold(X, itr, ite, fam, seme)
            append!(righe, DataFrame(rip = r, fold = k, insieme = String(ins), famiglia = String(fam), tratta = d.tratta[idx],
                                     p_ibrido = u.p, m_prev = u.m, n_ibr_prev = u.n_ibr, n_batt_prev = u.n_batt,
                                     costo_prev = exp.(u.logc), iperparametri = u.hp))
        end
        if r == 1
            for fam in (:rf, :gb), (g, chi) in FISICHE
                sel = chi === :ibr ? findall(itr .& ibr) : findall(itr)
                o, hp = adatta_scelto(fam, :reg, X[sel, :], log.(d[sel, "y_" * g]); seme)
                append!(fis, DataFrame(rip = r, fold = k, insieme = String(ins), famiglia = String(fam), grandezza = g,
                                       tratta = d.tratta[idx], prev = exp.(prevedi(o, X[ite, :])), vero = d[idx, "y_" * g],
                                       ibrido = ibr[idx], iperparametri = hpstr(hp)))
            end
        end
        @printf("rip %d %s fold %d fatto (%.0f s)\n", r, ins, k, time() - t0); flush(stdout)
    end
    CSV.write(file, righe)
    r == 1 && CSV.write(joinpath(CV, "fisiche_r1_$(ins).csv"), fis)
end
