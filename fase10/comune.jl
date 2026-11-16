# fase10/comune.jl: la rete neurale unica del surrogato (passo 6). Preparazione dei dati, modello, funzione di errore,
# addestramento, previsioni nelle unità naturali, metriche come la fase 8.
#
# Ingressi (73): le 66 caratteristiche della tratta (asimmetriche: log con segno), m, n, standardizzati con le statistiche
# dell'addestramento; più 5 indicatori esatti: ibrido (m > 0) e le 4 fasce D25 di m (soglie di soglie_controllo).
# Uscite (8 teste) e funzione di errore: vedi TESTE. Righe in cui una grandezza non esiste: maschera (escluse da quella testa).

using Flux, JLD2, Arrow, Statistics, Printf, Random, Dates, LinearAlgebra
using TrainPowertrain
# condizionate: fase9/comune.jl (banco di prova) definisce le stesse costanti, con gli stessi valori
if !@isdefined(TP); const TP = TrainPowertrain; end
if !@isdefined(BASE); const BASE = expanduser("~/Documents/lavoro/ml_treno_dati"); end
if !@isdefined(TAB); const TAB = joinpath(BASE, "P9_D28_16384", "tabella"); end
const SOGLIE_D25 = [x.m for x in TP.soglie_controllo(ConfigModello())]      # 0,0957…, 0,1016…, 0,1195…
fascia_d25(m) = m == 0 ? 0 : m < SOGLIE_D25[1] ? 1 : m < SOGLIE_D25[2] ? 2 : m < SOGLIE_D25[3] ? 3 : 4

# ── le teste ─────────────────────────────────────────────────────────────────────
# tipo :ratio (1 + softplus, quadratico/σ²), :lin (μ + σ z, quadratico/σ²), :soc (0,9·sigmoide, quadratico/σ²),
# :bin (sigmoide, entropia incrociata). spazio: come si passa dalla grandezza vera al bersaglio della testa.
const TESTE = [
    (nome = :durata,    col = :y_durata_viaggio_s,      tipo = :ratio, righe = :tutte),            # r = durata / durata minima
    (nome = :serbatoio, col = :y_massa_serbatoio_kg,    tipo = :lin,   righe = :ibride),           # log(kg / 2L)
    (nome = :H2,        col = :y_H2_cons_kg,            tipo = :lin,   righe = :ibride_completed), # log(kg / 2L)
    (nome = :SOC,       col = :y_SOC_end,               tipo = :soc,   righe = :tutte),            # valore in [0; 0,9]
    (nome = :scarica,   col = :y_scarica_s,             tipo = :bin,   righe = :tutte),            # y > 1e-6
    (nome = :vita_batt, col = :y_vita_batt_cicli_viaggi, tipo = :lin,  righe = :tutte),            # log
    (nome = :vita_FC,   col = :y_vita_FC_f1_ore,        tipo = :lin,   righe = :ibride),           # log
    (nome = :C_rate,    col = :y_C_rate_scarica_max,    tipo = :lin,   righe = :tutte),            # log
]
const K = length(TESTE)
# variante 6e: la nona testa, probabilità che il progetto sia fattibile (tipo_esito == fattibile), su tutte le righe
const TESTA_FATTIBILE = (nome = :fattibile, col = :fattibile, tipo = :bin, righe = :tutte)
const TESTE_9 = vcat(TESTE, [TESTA_FATTIBILE])
testa(k) = k <= K ? TESTE[k] : TESTA_FATTIBILE

struct Dati
    X::Matrix{Float32}       # 73 × N ingressi normalizzati
    Y::Matrix{Float32}       # K × N bersagli nello spazio delle teste (0 dove la maschera è 0)
    W::Matrix{Float32}       # K × N maschere
    tratta::Vector{Int32}; coppia::Vector{Int16}; m::Vector{Float64}; n::Vector{Float64}
    L::Vector{Float64}; T::Vector{Float64}; stato::Vector{Int8}
end

"""Statistiche di normalizzazione: per caratteristica log con segno se |asimmetria| > 2, poi media e deviazione; m, n."""
function normalizzazione(t_add)
    nx = [c for c in propertynames(t_add) if startswith(String(c), "x_")]     # Arrow.Table o NamedTuple di colonne
    tr = Int.(t_add.tratta); first_i = unique(i -> tr[i], eachindex(tr))     # una riga per tratta
    trasf = Dict{Symbol,Tuple{Bool,Float64}}(); μ = Dict{Symbol,Float64}(); σ = Dict{Symbol,Float64}()
    for c in nx
        v = Float64.(getproperty(t_add, c)[first_i])
        s = std(v); sk = s > 0 ? mean(((v .- mean(v)) ./ s) .^ 3) : 0.0
        uselog = abs(sk) > 2
        scala = uselog ? (nz = filter(!=(0), abs.(v)); isempty(nz) ? 1.0 : median(nz)) : 1.0
        w = uselog ? sign.(v) .* log1p.(abs.(v) ./ scala) : v
        trasf[c] = (uselog, scala); μ[c] = mean(w); σ[c] = max(std(w), 1e-12)
    end
    mm = Float64.(t_add.m); nn = Float64.(t_add.n)
    μ[:m] = mean(mm); σ[:m] = std(mm); μ[:n] = mean(nn); σ[:n] = std(nn)
    return (nx = nx, trasf = trasf, μ = μ, σ = σ)
end

"""Ingressi normalizzati (73 × N) da caratteristiche (matrice N × 66 nell'ordine norm.nx), m, n."""
function ingressi(Xc::AbstractMatrix, m, n, norm)
    N = length(m); X = Matrix{Float32}(undef, length(norm.nx) + 7, N)
    for (j, c) in enumerate(norm.nx)
        uselog, scala = norm.trasf[c]
        @inbounds for i in 1:N
            v = Xc[i, j]; w = uselog ? sign(v) * log1p(abs(v) / scala) : v
            X[j, i] = (w - norm.μ[c]) / norm.σ[c]
        end
    end
    j0 = length(norm.nx)
    @inbounds for i in 1:N
        X[j0+1, i] = (m[i] - norm.μ[:m]) / norm.σ[:m]; X[j0+2, i] = (n[i] - norm.μ[:n]) / norm.σ[:n]
        X[j0+3, i] = m[i] > 0
        f = fascia_d25(m[i])
        for b in 1:4; X[j0+3+b, i] = f == b; end
    end
    return X
end

"""Dati di una tabella (fase 6) per le righe `sel` (default tutte)."""
function prepara(t, norm; sel = nothing, hs = TESTE)
    idx = sel === nothing ? collect(1:length(t.tratta)) : sel
    Xc = reduce(hcat, (Float64.(getproperty(t, c)[idx]) for c in norm.nx))
    m = Float64.(t.m[idx]); n = Float64.(t.n[idx]); L = Float64.(t.x_L_km[idx]); T = Float64.(t.x_tempo_limiti_ar_s[idx])
    st = Int8.(t.stato[idx]); N = length(idx)
    Y = zeros(Float32, length(hs), N); W = zeros(Float32, length(hs), N)
    for (k, h) in enumerate(hs)
        y = Float64.(getproperty(t, h.col)[idx])
        ok = h.righe === :tutte ? trues(N) : h.righe === :ibride ? m .> 0 : (m .> 0) .& (st .== 1)
        z = h.nome === :durata ? y ./ T :
            h.nome in (:serbatoio, :H2) ? log.(y ./ (2 .* L)) :
            h.nome === :scarica ? Float64.(y .> 1e-6) :
            h.nome in (:vita_batt, :vita_FC, :C_rate) ? log.(y) : y
        ok .&= isfinite.(z)
        Y[k, ok] .= Float32.(z[ok]); W[k, ok] .= 1f0
    end
    return Dati(ingressi(Xc, m, n, norm), Y, W, Int32.(t.tratta[idx]), Int16.(t.coppia[idx]), m, n, L, T, st)
end

"""Media e deviazione dei bersagli sulle righe con maschera (addestramento): per le teste :lin e le scale delle perdite."""
function scale_bersagli(d::Dati)
    nk = size(d.Y, 1); μ = zeros(Float32, nk); σ = ones(Float32, nk)
    for k in 1:nk
        v = d.Y[k, d.W[k, :] .> 0]
        μ[k] = mean(v); σ[k] = std(v)
    end
    return (μ = μ, σ = σ)
end

# ── modello e perdita ────────────────────────────────────────────────────────────
function costruisci(nin; larghezza = 256, strati = 4, seme = 1, nout = K)
    rng = Xoshiro(seme)
    s = Any[Dense(nin => larghezza, gelu; init = Flux.glorot_uniform(rng))]
    for _ in 2:strati; push!(s, Dense(larghezza => larghezza, gelu; init = Flux.glorot_uniform(rng))); end
    push!(s, Dense(larghezza => nout; init = Flux.glorot_uniform(rng)))
    return Chain(s...)
end

"""Uscite delle teste nello spazio dei bersagli, da z (K × B)."""
function teste(z, sc)
    rows = map(1:size(z, 1)) do k
        zk = z[k:k, :]
        t = testa(k).tipo
        t === :ratio ? 1f0 .+ softplus.(zk) : t === :soc ? 0.9f0 .* sigmoid.(zk) : t === :bin ? sigmoid.(zk) : sc.μ[k] .+ sc.σ[k] .* zk
    end
    return reduce(vcat, rows)
end

"""Perdita per testa (vettore K) e totale pesato. Regressione: errore quadratico / σ²; :bin: entropia incrociata."""
function perdite(z, y, w, sc, pesi)
    ls = map(1:size(z, 1)) do k
        zk = z[k:k, :]; yk = y[k:k, :]; wk = w[k:k, :]
        t = testa(k).tipo
        l = if t === :bin
            Flux.Losses.logitbinarycrossentropy(zk, yk; agg = identity)
        else
            p = t === :ratio ? 1f0 .+ softplus.(zk) : t === :soc ? 0.9f0 .* sigmoid.(zk) : sc.μ[k] .+ sc.σ[k] .* zk
            ((p .- yk) ./ sc.σ[k]) .^ 2
        end
        sum(wk .* l) / max(sum(wk), 1f0)
    end
    return ls, sum(pesi .* ls)
end

"""Perdite per testa su un insieme di dati, a blocchi (senza gradiente)."""
function valuta_perdite(model, d::Dati, sc, pesi; blocco = 65536)
    N = size(d.X, 2); nk = size(d.Y, 1); tot = zeros(Float64, nk); nw = zeros(Float64, nk)
    for a in 1:blocco:N
        b = min(a + blocco - 1, N)
        z = model(view(d.X, :, a:b)); y = view(d.Y, :, a:b); w = view(d.W, :, a:b)
        for k in 1:nk
            zk = z[k:k, :]; t = testa(k).tipo
            l = if t === :bin
                Flux.Losses.logitbinarycrossentropy(zk, y[k:k, :]; agg = identity)
            else
                p = t === :ratio ? 1f0 .+ softplus.(zk) : t === :soc ? 0.9f0 .* sigmoid.(zk) : sc.μ[k] .+ sc.σ[k] .* zk
                ((p .- y[k:k, :]) ./ sc.σ[k]) .^ 2
            end
            tot[k] += sum(w[k:k, :] .* l); nw[k] += sum(w[k:k, :])
        end
    end
    ls = tot ./ max.(nw, 1)
    return ls, sum(pesi .* ls)
end

"""
    addestra(da, dv, sc; epoche, lotto, lr, lr_fine, pesi, larghezza, strati, seme, pazienza, say) -> (model, storia)

Adam, passo coseno da `lr` a `lr_fine` sulle `epoche`, lotti mescolati con seme fisso, arresto anticipato sulla perdita
totale di validazione (pazienza in epoche); restituisce il modello dell'epoca migliore.
"""
function addestra(da::Dati, dv::Dati, sc; epoche = 40, lotto = 4096, lr = 1f-3, lr_fine = 1f-5, pesi = nothing,
                  larghezza = 256, strati = 4, seme = 1, pazienza = 5, say = println)
    nk = size(da.Y, 1); pesi === nothing && (pesi = ones(Float32, nk))
    model = costruisci(size(da.X, 1); larghezza, strati, seme, nout = nk)
    opt = Flux.setup(Adam(lr), model)
    rng = Xoshiro(seme + 1)
    N = size(da.X, 2)
    storia = NamedTuple[]
    migliore = (perdita = Inf, epoca = 0, stato = deepcopy(Flux.state(model)))
    for e in 1:epoche
        η = Float32(lr_fine + 0.5 * (lr - lr_fine) * (1 + cos(pi * (e - 1) / max(epoche - 1, 1))))
        Flux.adjust!(opt, η)
        t0 = time(); perm = randperm(rng, N); somma = 0.0; nb = 0
        for a in 1:lotto:N
            idx = perm[a:min(a + lotto - 1, N)]
            x = da.X[:, idx]; y = da.Y[:, idx]; w = da.W[:, idx]
            l, g = Flux.withgradient(mdl -> perdite(mdl(x), y, w, sc, pesi)[2], model)
            isfinite(l) || error("perdita non finita all'epoca $e")
            Flux.update!(opt, model, g[1]); somma += l; nb += 1
        end
        ta = time() - t0
        lv, tv = valuta_perdite(model, dv, sc, pesi)
        push!(storia, (epoca = e, eta = η, perdita_add = somma / nb, perdita_val = tv, per_testa_val = lv, tempo_s = ta))
        say(@sprintf("  epoca %2d  η %.2e  addestramento %.4f  validazione %.4f  [%s]  %.1f s", e, η, somma / nb, tv,
                     join((@sprintf("%s %.4f", testa(k).nome, lv[k]) for k in 1:nk), " "), ta))
        if tv < migliore.perdita
            migliore = (perdita = tv, epoca = e, stato = deepcopy(Flux.state(model)))
        elseif e - migliore.epoca >= pazienza
            say("  arresto anticipato: nessun miglioramento da $pazienza epoche")
            break
        end
    end
    Flux.loadmodel!(model, migliore.stato)
    say(@sprintf("  epoca migliore %d (validazione %.4f)", migliore.epoca, migliore.perdita))
    return model, storia
end

# ── previsioni nelle unità naturali ───────────────────────────────────────────────
"""Le 8 grandezze nelle unità naturali (come il banco di prova del passo 5a) per i dati `d`."""
function previsioni(model, d::Dati, sc; blocco = 65536)
    N = size(d.X, 2); P = zeros(Float32, size(model(d.X[:, 1:1]), 1), N)
    for a in 1:blocco:N
        b = min(a + blocco - 1, N)
        P[:, a:b] = teste(model(view(d.X, :, a:b)), sc)
    end
    ibr = d.m .> 0
    return (durata = Float64.(P[1, :]) .* d.T,
            serbatoio = ifelse.(ibr, exp.(Float64.(P[2, :])) .* 2 .* d.L, 0.0),
            H2 = ifelse.(ibr, exp.(Float64.(P[3, :])) .* 2 .* d.L, 0.0),
            SOC = Float64.(P[4, :]), p_scarica = Float64.(P[5, :]),
            vita_batt = exp.(Float64.(P[6, :])), vita_FC_f1 = ifelse.(ibr, exp.(Float64.(P[7, :])), Inf),
            C_rate = exp.(Float64.(P[8, :])), p_fattibile = size(P, 1) > K ? Float64.(P[K+1, :]) : fill(NaN, N))
end

"""Metriche per grandezza come la fase 8 (sulle stesse righe), dalla tabella `t` e dalle previsioni `p`."""
function metriche(t, p, d::Dati)
    out = NamedTuple[]
    st = d.stato; m = d.m
    for (nome, col, sel, tipo) in ((:durata, :y_durata_viaggio_s, trues(length(m)), :rel), (:serbatoio, :y_massa_serbatoio_kg, m .> 0, :rel),
                                   (:H2, :y_H2_cons_kg, (m .> 0) .& (st .== 1), :rel), (:SOC, :y_SOC_end, trues(length(m)), :abs),
                                   (:vita_batt, :y_vita_batt_cicli_viaggi, trues(length(m)), :rel), (:vita_FC_f1, :y_vita_FC_f1_ore, m .> 0, :rel),
                                   (:C_rate, :y_C_rate_scarica_max, trues(length(m)), :rel))
        y = Float64.(getproperty(t, col))[sel]; q = getproperty(p, nome)[sel]
        e = tipo === :rel ? 100 .* abs.(q .- y) ./ abs.(y) : abs.(q .- y)
        push!(out, (grandezza = String(nome), tipo = String(tipo), mediana = median(e), p95 = quantile(e, 0.95), p99 = quantile(e, 0.99), max = maximum(e)))
    end
    ys = Float64.(t.y_scarica_s) .> 1e-6; c = p.p_scarica .>= 0.5
    push!(out, (grandezza = "scarica", tipo = "accuratezza", mediana = 100mean(c .== ys), p95 = mean(abs2, p.p_scarica .- ys), p99 = NaN, max = NaN))
    return out
end

"""Valori di riferimento del boosting (fase 7 E per la durata, fase 8 per le altre), stesse metriche."""
function riferimento_boosting(ml_treno)
    r = Dict{String,NamedTuple}()
    l = readlines(joinpath(ml_treno, "fase8", "risultati", "01_metriche.csv")); h = split(l[1], ',')
    for x in split.(l[2:end], ',')
        x[2] == "boosting" || continue
        g = Dict(h .=> x)
        nome = Dict("massa_serbatoio" => "serbatoio", "H2_cons" => "H2", "SOC_end" => "SOC", "scarica" => "scarica",
                    "vita_batt" => "vita_batt", "vita_FC" => "vita_FC_f1", "C_rate" => "C_rate")[g["grandezza"]]
        r[nome] = g["grandezza"] == "scarica" ? (mediana = 100parse(Float64, g["accuratezza"]), p95 = parse(Float64, g["brier"])) :
                                                 (mediana = parse(Float64, g["err_mediana"]), p95 = parse(Float64, g["err_p95"]))
    end
    l = readlines(joinpath(ml_treno, "fase7", "risultati", "03_metriche.csv")); h = split(l[1], ',')
    for x in split.(l[2:end], ',')
        x[1] == "E boosting sul rapporto r" || continue   # la riga sulla validazione (non quella sull'addestramento)
        g = Dict(h .=> x); r["durata"] = (mediana = parse(Float64, g["err_pct_mediana"]), p95 = parse(Float64, g["err_pct_p95"]))
    end
    return r
end

"""Salva modello, normalizzazione, scale e impostazioni (JLD2)."""
salva_modello(file, model, norm, sc, info) = jldsave(file; stato = Flux.state(model), norm, sc, info)
function carica_modello(file)
    d = load(file)
    info = d["info"]
    model = costruisci(info.nin; larghezza = info.larghezza, strati = info.strati, nout = hasproperty(info, :nout) ? info.nout : K)
    Flux.loadmodel!(model, d["stato"])
    return model, d["norm"], d["sc"], info
end
