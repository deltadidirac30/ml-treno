# ============================================================================
# model.jl: Neural network architecture for energy prediction
#
# Defines MLPSurrogate — a multi-layer perceptron (MLP) neural network that
# takes 69 input features (from driving profiles) and outputs 4 energy predictions:
#   - H2_cons: hydrogen consumption (kg/km)
#   - SOC_end: battery state of charge at end (%)
#   - num_repl_FC: number of fuel cell replacements needed
#   - num_repl_batt: number of battery replacements needed
# ============================================================================

using Flux

# ============================================================================
# MLPSurrogate struct: A wrapper around the neural network
#
# In Julia, a "struct" is a custom data type that groups related data together.
# "mutable" means we can modify its fields after creation (necessary for training).
#
# Fields:
#   - chain: A Flux.Chain containing the stack of layers (Dense layers + activations)
#            Chain is an ordered sequence of layers that data flows through
# ============================================================================
mutable struct MLPSurrogate
    chain::Flux.Chain
end

# ============================================================================
# @functor macro: Makes the struct "trainable" by Flux
#
# When Flux trains a model, it needs to find all the weights/parameters inside it.
# This macro tells Flux: "Look inside MLPSurrogate, find the learnable parameters
# in the `chain` field, and update them when training."
# ============================================================================
Flux.@functor MLPSurrogate (chain,)

# ============================================================================
# Make MLPSurrogate callable: (m::MLPSurrogate)(x) = m.chain(x)
#
# In Julia, you can define what happens when you call an object like a function.
# This allows us to write:  output = model(input_data)
# Instead of:               output = model.chain(input_data)
#
# Args:
#   m: An MLPSurrogate instance
#   x: Input features (should be 69 dimensional)
# Returns:
#   Output from the neural network chain
# ============================================================================
(m::MLPSurrogate)(x) = m.chain(x)

# ============================================================================
# build_model(): Construct the neural network with 4 layers
#
# Builds a multi-layer perceptron with:
#   - Input: n_input features (default 69 from route profiles)
#   - Layer 1: 69 → 128 neurons, ReLU activation
#   - Layer 2: 128 → 64 neurons, ReLU activation
#   - Layer 3: 64 → 32 neurons, ReLU activation
#   - Layer 4: 32 → 4 neurons, NO activation (linear output for regression)
#
# What each layer does:
#   - Dense(a => b): Takes a input values, outputs b values via learned weights
#   - relu: Rectified Linear Unit — outputs max(0, x), adds non-linearity
#   - Last layer has NO activation because we want unbounded energy predictions
#
# Args:
#   n_input: Number of input features (default 69 from features.jl)
#
# Returns:
#   MLPSurrogate object containing the initialized chain
# ============================================================================
function build_model(n_input::Int = 69)
    # Construct the neural network chain (sequence of layers)
    chain = Flux.Chain(
        # Layer 1: Input features → 128 hidden neurons with ReLU activation
        # ReLU adds non-linearity, allowing the network to learn complex patterns
        Flux.Dense(n_input => 128, relu),

        # Layer 2: 128 → 64 neurons with ReLU activation
        # Progressively reduce dimensionality to force feature learning
        Flux.Dense(128    => 64,  relu),

        # Layer 3: 64 → 32 neurons with ReLU activation
        # Further compression of learned representations
        Flux.Dense(64     => 32,  relu),

        # Layer 4: 32 → 4 outputs (no activation)
        # Outputs are: H2_cons, SOC_end, num_repl_FC, num_repl_batt
        # No ReLU here because these outputs can be negative (before de-normalization)
        Flux.Dense(32     => 4),
    )

    # Safety check: ensure we have exactly 4 layers (architecture specification)
    @assert length(chain.layers) == 4 "Expected exactly 4 layers, got $(length(chain.layers))"

    # Wrap the chain in our MLPSurrogate struct and return
    return MLPSurrogate(chain)
end