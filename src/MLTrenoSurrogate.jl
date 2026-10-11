# ============================================================================
# MLTrenoSurrogate: Top-level Julia module for train energy surrogate modeling
#
# This module packages together all components needed to:
#   1. Synthesize realistic driving profiles (routes, slopes, speed limits, stops)
#   2. Extract 69 features from those profiles
#   3. Train a neural network to predict train energy consumption
#   4. Evaluate the trained model on test data
#
# To use: include("src/MLTrenoSurrogate.jl")
#         using .MLTrenoSurrogate
# ============================================================================

module MLTrenoSurrogate

# Load functions that synthesize synthetic driving profiles from parameters
# (profile_synth.jl already includes templates.jl internally)
include("profile_synth.jl")

# Load the neural network architecture: a 4-layer MLP that predicts energy outputs
include("model.jl")

# Load training utilities: loss functions, normalization, and the training loop
include("train.jl")

# Load evaluation function: computes prediction metrics (MSE, MAE, R², accuracy)
include("evaluate.jl")

# ============================================================================
# Public API: Template retrieval and profile synthesis
# ============================================================================
export REAL_ROUTE_TEMPLATES, template_for_row

# ============================================================================
# Public API: Profile synthesis functions
# These take a random number generator and parameters, return synthetic profiles
# ============================================================================
export synthesize_slope, synthesize_vlim, synthesize_stops, synthesize_row

# ============================================================================
# Public API: Model architecture and building
# MLPSurrogate is a struct wrapping the neural network
# build_model() creates a 69→128→64→32→4 multi-layer perceptron
# ============================================================================
export MLPSurrogate, build_model

# ============================================================================
# Public API: Training utilities
# zscore_fit / zscore_apply: normalize inputs to mean=0, std=1
# loss_fn: weighted mean-squared-error (outputs 3,4 weighted 2×)
# train!: main training loop with early stopping and best-checkpoint saving
# ============================================================================
export zscore_fit, zscore_apply, loss_fn, train!

# ============================================================================
# Public API: Evaluation
# evaluate() runs the model on test data and computes quality metrics
# ============================================================================
export evaluate

end