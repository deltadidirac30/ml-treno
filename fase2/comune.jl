# Fase 2: dati, divisioni per la validazione incrociata, modelli e scelta degli iperparametri.
# Le tratte reali NON si leggono qui: restano cieche fino alla fase 3.

using CSV, DataFrames, Statistics, StatsBase, Random, Printf, LinearAlgebra
using EvoTrees, DecisionTree, Optim

const FASE1 = joinpath(@__DIR__, "..", "fase1", "dati")
const RIS   = joinpath(@__DIR__, "risultati")
mkpath(RIS)

const SEME   = 20261012     # seme della validazione incrociata (ripetizione r: SEME + r)
const NREP   = 5
const NFOLD  = 5
const NINNER = 3            # fold interni per gli iperparametri
const M_MIN  = 0.03
const N_MIN  = 0.005        # n previsto tenuto ≥ 0,005 (n = 0 è fuori dominio, D7)

dati() = CSV.read(joinpath(FASE1, "dataset_doe.csv"), DataFrame)

"Colonne di input: :p66 (le 66 approvate) o :p69 (più le 3 din_)."
function colonne(d, insieme::Symbol)
    xs = [c for c in names(d) if startswith(c, "x_")]
    insieme === :p69 && return xs
    insieme === :p66 && return [c for c in xs if !startswith(c, "x_din_")]
    error("insieme $insieme")
end
matrice(d, cols) = Matrix{Float64}(d[:, cols])

"Fold (1..NFOLD) di ogni tratta nella ripetizione r, stratificato per regime."
function fold_di(ibrido::AbstractVector{Bool}, r::Int; nf = NFOLD, seme = SEME + r)
    rng = MersenneTwister(seme)
    f = zeros(Int, length(ibrido))
    for g in (true, false)
        idx = shuffle(rng, findall(==(g), ibrido))
        off = rand(rng, 0:nf-1)                      # così le classi non riempiono sempre gli stessi fold per primi
        for (k, i) in enumerate(idx); f[i] = mod(k - 1 + off, nf) + 1; end
    end
    return f
end

# ─────────────────────────── modelli ───────────────────────────
# Ogni famiglia ha una griglia di iperparametri; `adatta(fam, :cls|:reg, X, y, hp)` restituisce un oggetto e
# `prevedi(obj, X)` la probabilità di ibrido (:cls) o il valore (:reg).

struct Standard; μ::Matrix{Float64}; σ::Matrix{Float64}; end
Standard(X) = (μ = mean(X, dims = 1); σ = std(X, dims = 1); σ[σ .== 0] .= 1; Standard(μ, σ))
(s::Standard)(X) = (X .- s.μ) ./ s.σ

# mediana / classe maggioritaria
struct Costante; v::Float64; end
prevedi(o::Costante, X) = fill(o.v, size(X, 1))

# k-NN su caratteristiche standardizzate (statistiche del training)
struct KNN; s::Standard; Z::Matrix{Float64}; y::Vector{Float64}; k::Int; end
function vicini(o::KNN, X)
    Zq = o.s(X)
    D = sum(abs2, Zq, dims = 2) .+ sum(abs2, o.Z, dims = 2)' .- 2 .* (Zq * o.Z')
    return [partialsortperm(view(D, i, :), 1:min(o.k, size(o.Z, 1))) for i in axes(D, 1)]
end
prevedi(o::KNN, X) = [mean(o.y[v]) for v in vicini(o, X)]

# foresta casuale (DecisionTree.jl)
struct RF; f; cls::Bool; end
prevedi(o::RF, X) = o.cls ? apply_forest_proba(o.f, X, [0, 1])[:, 2] : apply_forest(o.f, X)

# boosting (EvoTrees.jl)
struct GB; m; end
prevedi(o::GB, X) = Float64.(o.m(X))

# processo gaussiano, nucleo esponenziale quadratico ARD + rumore, iperparametri a massima verosimiglianza marginale
struct GP; s::Standard; Z::Matrix{Float64}; α::Vector{Float64}; ℓ::Vector{Float64}; σf::Float64; ym::Float64; ys::Float64; end
function _K(Z1, Z2, ℓ, σf)
    A = Z1 ./ ℓ'; B = Z2 ./ ℓ'
    D = max.(sum(abs2, A, dims = 2) .+ sum(abs2, B, dims = 2)' .- 2 .* (A * B'), 0.0)
    return σf^2 .* exp.(-0.5 .* D)
end
function _nlml_grad!(G, θ, Z, y)
    p = size(Z, 2)
    ℓ = exp.(θ[1:p]); σf = exp(θ[p+1]); σn = exp(θ[p+2])
    K = _K(Z, Z, ℓ, σf); n = length(y)
    Ky = Symmetric(K + (σn^2 + 1e-8) * I)
    C = cholesky(Ky; check = false)
    issuccess(C) || return Inf
    α = C \ y
    nlml = 0.5 * dot(y, α) + sum(log, diag(C.U)) + 0.5 * n * log(2π)
    if G !== nothing
        W = α * α' .- inv(C)                       # dL/dθ = -0.5 tr(W dK/dθ)
        WK = W .* K
        Threads.@threads for d in 1:p
            z = view(Z, :, d); acc = 0.0
            @inbounds for j in 1:n, i in 1:n
                acc += WK[i, j] * (z[i] - z[j])^2
            end
            G[d] = -0.5 * acc / ℓ[d]^2
        end
        G[p+1] = -0.5 * sum(WK) * 2
        G[p+2] = -0.5 * LinearAlgebra.tr(W) * 2 * σn^2
    end
    return nlml
end
function adatta_gp(X, y; iter = 200)
    s = Standard(X); Z = s(X)
    ym, ys = mean(y), std(y); yz = (y .- ym) ./ ys
    p = size(Z, 2)
    θ0 = vcat(fill(log(sqrt(p)), p), 0.0, log(0.1))
    fg!(F, G, θ) = (v = _nlml_grad!(G, θ, Z, yz); F === nothing ? nothing : v)
    res = optimize(Optim.NLSolversBase.only_fg!(fg!), θ0, LBFGS(), Optim.Options(iterations = iter))
    θ = Optim.minimizer(res)
    ℓ = exp.(θ[1:p]); σf = exp(θ[p+1]); σn = exp(θ[p+2])
    Ky = Symmetric(_K(Z, Z, ℓ, σf) + (σn^2 + 1e-8) * I)
    α = cholesky(Ky) \ yz
    return GP(s, Z, α, ℓ, σf, ym, ys)
end
prevedi(o::GP, X) = o.ym .+ o.ys .* (_K(o.s(X), o.Z, o.ℓ, o.σf) * o.α)

const GRIGLIE = Dict(
    :mediana => [(;)],
    :nn1     => [(k = 1,)],
    :knn     => [(k = k,) for k in (3, 5, 7, 10)],
    :rf      => [(nsub = s, foglia = f) for s in (:radq, :terzo) for f in (1, 5)],
    :gb      => [(prof = p, giri = g) for p in (3, 5) for g in (200, 600)],
    :gp      => [(;)],
)

function adatta(fam::Symbol, tipo::Symbol, X, y, hp; seme = 1)
    if fam === :mediana
        return Costante(tipo === :cls ? Float64(mean(y) >= 0.5) : median(y))
    elseif fam in (:nn1, :knn)
        s = Standard(X); return KNN(s, s(X), Float64.(y), hp.k)
    elseif fam === :rf
        p = size(X, 2); nsub = hp.nsub === :radq ? round(Int, sqrt(p)) : round(Int, p / 3)
        f = tipo === :cls ? build_forest(Int.(y), X, nsub, 300, 0.7, -1, hp.foglia, 2; rng = seme) :
                            build_forest(Float64.(y), X, nsub, 300, 0.7, -1, hp.foglia, 2; rng = seme)
        return RF(f, tipo === :cls)
    elseif fam === :gb
        cfg = EvoTreeRegressor(loss = tipo === :cls ? :logloss : :mse, nrounds = hp.giri, eta = 0.05, max_depth = hp.prof,
                               rowsample = 0.8, colsample = 0.8, L2 = 1.0, nbins = 64, seed = seme)
        return GB(EvoTrees.fit(cfg; x_train = X, y_train = Float64.(y)))
    elseif fam === :gp
        tipo === :reg || error("GP solo per regressione")
        return adatta_gp(X, Float64.(y))
    end
    error("famiglia $fam")
end

# errore per la scelta degli iperparametri: Brier per la classificazione, errore quadratico medio per la regressione
perdita(tipo, y, p) = mean(abs2, Float64.(y) .- p)

"""
    scegli(fam, tipo, X, y; seme) -> hp

Iperparametri dalla griglia di `fam` con una CV interna a NINNER fold sul solo training (mai il fold di prova).
"""
function scegli(fam, tipo, X, y; seme = 1)
    G = GRIGLIE[fam]
    length(G) == 1 && return G[1]
    fi = tipo === :cls ? fold_di(Bool.(y .> 0.5), 0; nf = NINNER, seme = seme) :
                         mod.(randperm(MersenneTwister(seme), length(y)), NINNER) .+ 1
    err = map(G) do hp
        mean(1:NINNER) do k
            tr = fi .!= k; te = .!tr
            o = adatta(fam, tipo, X[tr, :], y[tr], hp; seme)
            perdita(tipo, y[te], prevedi(o, X[te, :]))
        end
    end
    return G[argmin(err)]
end

"Adatta con la scelta degli iperparametri e restituisce (oggetto, hp)."
function adatta_scelto(fam, tipo, X, y; seme = 1)
    hp = scegli(fam, tipo, X, y; seme)
    return adatta(fam, tipo, X, y, hp; seme), hp
end
