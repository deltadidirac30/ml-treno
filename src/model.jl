using Flux

mutable struct MLPSurrogate
    chain::Flux.Chain
end

Flux.@functor MLPSurrogate (chain,)

(m::MLPSurrogate)(x) = m.chain(x)

# Exactly 4 Dense layers as per spec: 128 → 64 → 32 → 4
function build_model(n_input::Int = 69)
    chain = Flux.Chain(
        Flux.Dense(n_input => 128, relu),
        Flux.Dense(128    => 64,  relu),
        Flux.Dense(64     => 32,  relu),
        Flux.Dense(32     => 4),
    )
    @assert length(chain.layers) == 4 "Expected exactly 4 layers, got $(length(chain.layers))"
    return MLPSurrogate(chain)
end