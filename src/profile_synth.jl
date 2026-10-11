# ============================================================================
# This module contains functions to synthesize driving profiles.
# 
# A "profile" contains all the information needed to simulate a train journey:
#   - L: Route length in km
#   - p: Slope profile (vector of slopes in permille, one per meter)
#   - vlim_segments: Speed limit segments (start, end, speed limit)
#   - stops: Positions of stops along the route (in km)
# 
# Each row in the dataset gets its own profile, generated using a
# deterministic seed (so the same row always gets the same profile).
# ============================================================================

using Random        # For random number generation with seeds
using Distributions # For statistical distributions (Normal, Dirichlet, Poisson)
using StatsBase     # For sampling with weights
using Statistics    # For mean() function


# Include the templates file (real Italian railway routes)
# @__DIR__ ensures this works regardless of where Julia is launched from
include(joinpath(@__DIR__, "templates.jl"))


# ============================================================================
# Synthesizes a slope profile along a route.
# 
# The route is divided into segments, each with a different average slope.
# Then random noise is added, and a moving average is applied for smoothness.
# Finally, slopes are clamped to realistic values (-35 to +35 permille).
# 
# INPUT:
#   - rng: Random number generator (with seed for reproducibility)
#   - L: Route length in km
#   - slope_baseline: Base slope value to use (permille)
# OUTPUT:
#   - Vector of slopes, one value per meter of the route
# 
# Example:
#   L = 100 km -> p will have 100,001 values (one per meter)
# ============================================================================
function synthesize_slope(rng::AbstractRNG, L::Float64, slope_baseline::Float64)::Vector{Float64}
    
    # Calculate number of points (one per meter)
    # L km * 1000 = number of meters + 1 for the starting point
    N = round(Int, L * 1000) + 1
    
    # Determine number of segments
    # Longer routes get more segments, minimum 3 segments
    K = max(3, floor(Int, L / 10))
    
    
    # Generate segment lengths using a Dirichlet distribution
    # This divides the total route into K random segments
    # Dirichlet(ones(K)) gives a uniform distribution over K parts
    seg_lengths = rand(rng, Dirichlet(ones(K))) .* (L * 1000)
    
    
    # Initialize the slope array (pre-allocate for efficiency)
    p = Vector{Float64}(undef, N)
    
    
    # Fill each segment with its slope value
    idx = 1  # Current position in the slope array
    for seg_len in seg_lengths
        
        # Convert segment length to integer
        seg_len_int = round(Int, seg_len)
        
        # Don't go past the end of the array
        if idx + seg_len_int - 1 > N
            seg_len_int = N - idx + 1
        end
        
        # Skip if segment is too short
        if seg_len_int <= 0
            continue
        end
        
        # Decide if this segment goes uphill (+) or downhill (-)
        sign_choice = rand(rng, [-1.0, 1.0])
        
        # Generate slope for this segment using a Normal distribution
        # Mean = baseline * direction, std = baseline/2 + 1
        μ_seg = rand(rng, Normal(slope_baseline * sign_choice, slope_baseline / 2 + 1))
        
        # Fill all points in this segment with the same slope
        for j in 1:seg_len_int
            if idx <= N
                p[idx] = μ_seg
                idx += 1
            end
        end
    end
    
    
    # Fill any remaining points by repeating the last value
    # (handles edge case where segments don't cover entire route)
    while idx <= N
        p[idx] = p[idx - 1]
        idx += 1
    end
    
    
    # Add random noise to make it more realistic
    # Random values from Normal(0, 1.5) added to each point
    p .+= randn(rng, N) .* 1.5
    
    
    # Apply a moving average filter (smoothing)
    # Window size = 100 meters
    p = moving_average(p, 100)
    
    
    # Clamp values to realistic range (-35 to +35 permille)
    # This represents the maximum slope for most railways
    p .= clamp.(p, -35.0, 35.0)
    
    
    return p
end


# ============================================================================
# Applies a moving average filter to smooth a vector.
# 
# Each element becomes the average of itself and its neighbors.
# Edge elements have smaller windows (can't go beyond array bounds).
# 
# INPUT:
#   - v: Input vector of floats
#   - window: Size of the averaging window
# OUTPUT:
#   - Smoothed vector
# 
# Example with window=3:
#   Input:  [1, 2, 3, 4, 5]
#   Output: [1.5, 2, 3, 4, 4.5]
#   (First element: avg of positions 1-2, Last: avg of 4-5)
# ============================================================================
function moving_average(v::Vector{Float64}, window::Int)::Vector{Float64}
    n = length(v)
    result = similar(v)  # Pre-allocate output array
    half_w = window ÷ 2  # Half the window size
    
    for i in 1:n
        # Calculate the window bounds for this position
        lo = max(1, i - half_w)  # Don't go before first element
        hi = min(n, i + half_w)  # Don't go after last element
        
        # Calculate the average
        result[i] = sum(@view v[lo:hi]) / (hi - lo + 1)
    end
    
    return result
end


# ============================================================================
# Synthesizes speed limit segments along a route.
# 
# The route is divided into segments, each with a speed limit.
# The speed limits are sampled from common Italian railway speeds (50-150 km/h),
# weighted towards the baseline speed.
# 
# INPUT:
#   - rng: Random number generator
#   - L: Route length in km
#   - v_max_baseline: Preferred maximum speed (km/h)
#   - p: Optional slope profile (if provided, steep sections get lower limits)
# OUTPUT:
#   - Vector of tuples (start_km, end_km, speed_limit_kmh)
# 
# Example output:
#   [(0.0, 25.0, 150.0), (25.0, 80.0, 110.0), (80.0, 100.0, 90.0)]
# ============================================================================
function synthesize_vlim(rng::AbstractRNG, L::Float64, v_max_baseline::Float64; p::Union{Vector{Float64},Nothing}=nothing)::Vector{Tuple{Float64,Float64,Float64}}
    
    # Determine number of segments based on route length
    # Poisson distribution: average = L/15 segments
    M = rand(rng, Poisson(L / 15)) + 1  # At least 1 segment
    
    
    # Generate segment lengths using Dirichlet (uniform division into M parts)
    lens = rand(rng, Dirichlet(ones(M))) .* L
    
    # Calculate segment boundaries (cumulative sum)
    # edges[1] = 0, edges[2] = lens[1], edges[3] = lens[1]+lens[2], etc.
    edges = cumsum([0.0; lens])
    edges[end] = L  # Ensure last edge is exactly at L
    
    
    # Define possible speed limits (common Italian railway speeds)
    v_candidates = [50.0, 70.0, 90.0, 110.0, 130.0, 150.0]
    
    
    # Calculate weights for each speed limit
    # Higher weight for speeds close to the baseline
    # Uses a Gaussian (Normal) distribution centered on baseline
    weights = [exp(-((v - v_max_baseline)^2) / (2 * 20^2)) for v in v_candidates]
    weights ./= sum(weights)  # Normalize so they sum to 1
    
    
    # Create array to store the segments
    segments = Vector{Tuple{Float64,Float64,Float64}}(undef, M)
    
    
    # Generate speed limit for each segment
    for i in 1:M
        
        # Sample a speed limit based on the weights
        v_idx = sample(rng, 1:6, Weights(weights))
        v_lim = v_candidates[v_idx]
        
        
        # If slope profile is provided, reduce speed on steep sections
        if p !== nothing
            
            # Convert segment boundaries to indices in the slope array
            x_start_m = Int(round(edges[i] * 1000)) + 1
            x_end_m = min(Int(round(edges[i+1] * 1000)) + 1, length(p))
            
            # If segment has valid range
            if x_start_m <= x_end_m
                seg_p = @view p[x_start_m:x_end_m]
                
                # If average absolute slope > 20 permille, reduce speed limit
                if mean(abs.(seg_p)) > 20.0
                    v_idx_new = max(1, v_idx - 1)  # Reduce by one level
                    v_lim = v_candidates[v_idx_new]
                end
            end
        end
        
        # Store this segment: (start, end, speed_limit)
        segments[i] = (edges[i], edges[i+1], v_lim)
    end
    
    
    return segments
end


# ============================================================================
# Synthesizes stop positions along a route.
# 
# Generates n_stops random stop positions, ensuring minimum spacing
# of 1 km between consecutive stops.
# 
# INPUT:
#   - rng: Random number generator
#   - L: Route length in km
#   - n_stops: Number of stops to generate
# OUTPUT:
#   - Vector of stop positions in km (sorted ascending)
# 
# Example:
#   L=100, n_stops=3 -> [15.5, 45.2, 82.0] (positions in km)
# ============================================================================
function synthesize_stops(rng::AbstractRNG, L::Float64, n_stops::Int)::Vector{Float64}
    
    # If no stops needed, return empty vector
    if n_stops == 0
        return Float64[]
    end
    
    
    stops = Vector{Float64}()
    attempts = 0
    max_attempts = 10
    
    
    # Try to generate valid stops (with minimum spacing)
    while length(stops) < n_stops && attempts < max_attempts
        attempts += 1
        empty!(stops)  # Clear the vector
        
        # Generate n_stops random positions between 0 and L
        proposed = sort(rand(rng, n_stops) .* L)
        
        # Filter positions to ensure 1 km minimum spacing
        for x in proposed
            if isempty(stops)
                # First stop - always add
                push!(stops, x)
            else
                # Check if this stop is at least 1 km from the last stop
                if x - last(stops) >= 1.0
                    push!(stops, x)
                end
            end
        end
        
        # If no valid stops found, place one at the midpoint
        if isempty(stops)
            push!(stops, L / 2)
        end
    end
    
    
    return stops
end


# ============================================================================
# Synthesizes a complete driving profile for a single row.
# 
# This is the main function that brings everything together.
# It:
#   1. Extracts parameters from the row (or uses random defaults)
#   2. Generates the slope profile
#   3. Generates speed limit segments
#   4. Generates stop positions
#   5. Returns all as a NamedTuple
# 
# INPUT:
#   - row: A DataFrame row containing the original data
# OUTPUT:
#   - NamedTuple with fields: L, p, vlim_segments, stops
# 
# The row contains:
#   - seed: Random seed for reproducibility
#   - explicit_param: Which parameter was varied in this experiment
#   - explicit_value: The value of that parameter
# ============================================================================
function synthesize_row(row)::NamedTuple
    
    # Extract the seed from the row and create a random number generator
    # This ensures the same row always gets the same profile
    seed = row.seed
    rng = MersenneTwister(seed)
    
    
    # Extract parameter info from the row
    explicit_param = row.explicit_param
    explicit_value = Float64(row.explicit_value)
    
    
    # Generate random default values for route parameters
    # These will be used unless overridden by explicit_param/value
    L::Float64 = rand(rng, 30:5:300)  # Random length between 30-300 km
    n_stops::Int = rand(rng, 0:2:50)  # Random stops: 0, 2, 4, ..., 50
    slope_baseline::Float64 = sample(rng, [0.0, 3.0, 6.0, 9.0, 12.0], Weights([0.3, 0.25, 0.2, 0.15, 0.1]))
    v_max_baseline::Float64 = sample(rng, [100.0, 120.0, 140.0], Weights([0.4, 0.4, 0.2]))
    
    
    # Override defaults based on the explicit parameter
    # This ensures the synthesized profile matches what was varied in the experiment
    
    if explicit_param == "n_stops"
        # This row varies the number of stops
        n_stops = Int(round(explicit_value))
        
    elseif explicit_param == "L_km"
        # This row varies the route length
        L = explicit_value
        
    elseif explicit_param == "slope_permille"
        # This row varies the slope
        slope_baseline = explicit_value
        
    elseif explicit_param == "v_max_kmh"
        # This row varies the maximum speed
        v_max_baseline = explicit_value
        
    elseif explicit_param == "template_id"
        # This row uses a real Italian railway route template
        template_id = Int(round(explicit_value))
        template = template_for_row(template_id)
        
        # Use template properties with some random variation
        L = template.L_km * (0.9 + 0.2 * rand(rng))  # ±10% of template length
        n_stops = template.n_stops
        slope_baseline = template.slope_mean
        v_max_baseline = template.v_max
    end
    
    
    # Clamp values to valid ranges
    L = clamp(L, 30.0, 300.0)
    n_stops = clamp(n_stops, 0, 50)
    slope_baseline = clamp(slope_baseline, 0.0, 35.0)
    v_max_baseline = clamp(v_max_baseline, 50.0, 150.0)
    
    
    # Generate the actual profile components
    p = synthesize_slope(rng, L, slope_baseline)
    vlim_segments = synthesize_vlim(rng, L, v_max_baseline; p=p)
    stops = synthesize_stops(rng, L, n_stops)
    
    
    # Return everything as a NamedTuple
    return (L=L, p=p, vlim_segments=vlim_segments, stops=stops)
end