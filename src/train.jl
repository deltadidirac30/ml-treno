# ============================================================================
# train.jl: Training utilities for the neural network
#
# Provides three main components:
#   1. Loss function: Weighted mean-squared-error for multi-output training
#   2. Normalization: Z-score normalization (mean=0, std=1) for stable training
#   3. Training loop: Mini-batch Adam optimizer with early stopping
# ============================================================================

using Flux     # Neural network framework
using Zygote   # Automatic differentiation engine (computes gradients)
using Optimisers  # Optimizer implementations (Adam, AdamW)
using Statistics  # Statistical functions
using Random      # For shuffle() used in mini-batch training loop

# ============================================================================
# Loss weights: Emphasize harder-to-predict outputs
#
# The 4 outputs have different importance and difficulty:
#   W = [1.0, 1.0, 2.0, 2.0]
#
# Weights [1, 1] for outputs 1-2 (H2_cons, SOC_end):
#   - Continuous values, easier to predict, standard weight
#
# Weights [2, 2] for outputs 3-4 (num_repl_FC, num_repl_batt):
#   - Integer-valued (replacement counts), harder to predict accurately
#   - Higher weight forces the model to learn them better
# ============================================================================
const W = Float32[1.0, 1.0, 2.0, 2.0]

# ============================================================================
# loss_fn(): Compute weighted mean-squared-error (MSE) loss
#
# MSE = mean( (prediction - truth)² )
# Larger errors are penalized more due to squaring. We use this as the objective
# function to minimize during training.
#
# Args:
#   ŷ: Predicted outputs (4 × batch_size) — predictions from the network
#   y: True outputs (4 × batch_size) — ground truth from training data
#
# Returns:
#   Scalar loss value (lower is better)
#
# What it does:
#   1. Compute (ŷ - y)² for each sample and output
#   2. Average across samples per output: mean(..., dims=2)
#   3. Weight each output by W: outputs 3,4 get 2× the penalty
#   4. Sum the 4 weighted losses and divide by 4 to normalize
# ============================================================================
function loss_fn(ŷ::AbstractMatrix{Float32}, y::AbstractMatrix{Float32})
    sum(W .* mean((ŷ .- y).^2, dims=2)) / 4
end

# ============================================================================
# zscore_fit(): Compute z-score normalization parameters
#
# Z-score normalization (also called standardization) transforms data to:
#   - Mean (μ) = 0
#   - Standard deviation (σ) = 1
#
# This is crucial for neural network training because:
#   - Features on the same scale converge faster
#   - Gradient descent works better with normalized inputs
#   - Prevents features with large values from dominating
#
# Args:
#   X: Input data matrix (n_features × n_samples)
#
# Returns:
#   Named tuple: (μ=mean_vector, σ=std_vector)
#   μ: Mean of each feature (n_features,)
#   σ: Std dev of each feature (n_features,)
#
# Note:
#   - Fit ONLY on training data (to avoid data leakage)
#   - Apply to both train and validation data using the fitted parameters
# ============================================================================
function zscore_fit(X::AbstractMatrix{Float32})
    # Compute mean per feature (across all samples)
    # dims=2 means average across dimension 2 (samples), keeping dimension 1 (features)
    μ_vec = vec(mean(X, dims=2))

    # Compute standard deviation per feature
    # corrected=true uses Bessel's correction (divides by n-1 instead of n)
    σ_vec = vec(std(X, dims=2; corrected=true))

    # Prevent division by zero: set any σ < 1e-8 to 1e-8
    # This handles features with zero variance (they won't be normalized, just centered)
    σ_vec = max.(σ_vec, Float32(1e-8))

    return (μ=μ_vec, σ=σ_vec)
end

# ============================================================================
# zscore_apply(): Apply pre-computed z-score normalization
#
# Transform data using already-fitted μ and σ from the training set
#
# Args:
#   X: Data to normalize (n_features × n_samples)
#   μ: Mean vector (fitted on training data)
#   σ: Std dev vector (fitted on training data)
#
# Returns:
#   Normalized data (same shape as X, but with mean≈0, std≈1)
#
# Formula: X_normalized = (X - μ) / σ
# ============================================================================
function zscore_apply(X::AbstractMatrix{Float32}, μ, σ)
    return (X .- μ) ./ σ
end

# ============================================================================
# train!(): Main training loop with mini-batch learning and early stopping
#
# Adjusts the neural network weights to minimize the loss function.
# Uses mini-batch gradient descent with the Adam optimizer.
#
# Key concepts:
#   - Mini-batch: Process batch_size samples at once, not all data (faster, noisier gradients)
#   - Gradient descent: Move weights in the direction that reduces loss
#   - Early stopping: Stop training when validation loss stops improving (prevent overfitting)
#   - Best checkpoint: Save the model snapshot with lowest validation loss (not final state)
#
# Args:
#   model: MLPSurrogate network to train (weights will be modified)
#   X_tr, Y_tr: Training data (features and targets)
#   X_val, Y_val: Validation data (unseen during training, used to detect overfitting)
#
#   epochs: Maximum number of passes through training data (default 200)
#   batch_size: Number of samples per gradient update (default 32)
#              Smaller batch = noisier gradients but faster updates
#              Larger batch = smoother gradients but slower per-epoch
#
#   lr: Learning rate (default 1e-3 = 0.001)
#      How big a step to take when updating weights (higher = faster convergence, risk of overshooting)
#
#   patience: Early stopping patience (default 20)
#            Stop if validation loss doesn't improve for this many epochs
#
#   weight_decay: L2 regularization strength (default 0)
#                If > 0, use AdamW which adds penalty for large weights (prevents overfitting)
#                If = 0, use plain Adam
#
# Returns:
#   (log, best_model):
#     log: Vector of training records [(epoch, train_loss, val_loss), ...]
#     best_model: Deep copy of model with best validation loss (most generalizable)
# ============================================================================
function train!(model, X_tr::Matrix{Float32}, Y_tr::Matrix{Float32},
                X_val::Matrix{Float32}, Y_val::Matrix{Float32};
                epochs::Int=200, batch_size::Int=32, lr::Float64=1e-3, patience::Int=20, weight_decay::Float64=0.0)

    # ====== STEP 1: Choose and initialize optimizer ======
    # Adam: Adaptive learning rates per parameter (converges faster)
    # AdamW: Adam + weight decay regularization (reduces overfitting)
    opt = if weight_decay > 0.0
        Optimisers.AdamW(lr, (0.9, 0.999), weight_decay, 1e-8)
    else
        Optimisers.Adam(lr)
    end

    # Setup: Initialize optimizer internal state (momentum buffers, etc.)
    opt_state     = Optimisers.setup(opt, model)

    # ====== STEP 2: Initialize tracking variables ======
    best_val      = Inf32          # Best validation loss seen so far
    no_improve    = 0              # Epochs since last improvement
    log           = Vector{NamedTuple}()  # Training history
    best_model    = deepcopy(model)       # Save initial model as baseline

    # ====== STEP 3: Training loop (one epoch = one pass through all data) ======
    for epoch in 1:epochs
        # Shuffle training data indices to randomize batch order
        idx = shuffle(1:size(X_tr, 2))
        epoch_loss = 0f0
        nb = 0  # Number of batches processed

        # ====== Process mini-batches ======
        for i in 1:batch_size:length(idx)-batch_size+1
            # Select a batch of samples
            bi = idx[i:i+batch_size-1]      # Batch indices
            xb = X_tr[:, bi]                # Batch features
            yb = Y_tr[:, bi]                # Batch targets

            # ====== AUTOMATIC DIFFERENTIATION: Compute loss and gradients ======
            # Zygote.withgradient computes:
            #   1. Forward pass: run model(xb), compute loss
            #   2. Backward pass: compute derivatives of loss w.r.t. all model weights
            lval, grads = Zygote.withgradient(model) do m
                loss_fn(m(xb), yb)
            end

            # ====== UPDATE MODEL WEIGHTS ======
            # Adam updates each weight: w_new = w_old - lr * gradient
            # (with adaptive scaling based on momentum)
            Optimisers.update!(opt_state, model, grads[1])

            # Accumulate batch loss
            epoch_loss += lval
            nb += 1
        end

        # ====== STEP 4: Evaluate on validation set ======
        # Compute loss on validation data (never used in training)
        train_l = epoch_loss / nb              # Average training loss this epoch
        val_l   = loss_fn(model(X_val), Y_val)  # Validation loss
        push!(log, (epoch=epoch, train_loss=train_l, val_loss=val_l))

        # ====== STEP 5: Early stopping logic ======
        # If validation loss improved, save this model
        if val_l < best_val - 1f-5  # Require improvement of at least 1e-5
            best_val   = val_l
            no_improve = 0
            best_model = deepcopy(model)  # Save this checkpoint
        else
            # No improvement: increment the patience counter
            no_improve += 1
            # If patience exhausted, stop training (prevent overfitting)
            no_improve ≥ patience && (println("Early stop @ epoch $epoch"); break)
        end

        # ====== STEP 6: Print progress ======
        epoch % 10 == 0 && println("Epoch $epoch  train=$(round(train_l; digits=5))  val=$(round(val_l; digits=5))")
    end

    # Return training history and best model (best validation loss, not final state)
    return log, best_model
end
