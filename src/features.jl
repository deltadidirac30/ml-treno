using Statistics

# List of all 69 feature names, grouped by category
const FEATURE_NAMES = [
    # Gruppo 0 — Scalari (3)
    "L_km", "P_nom_fc", "C_batt",
    # Gruppo 1 — Slope lavoro gravitazionale (4)
    "slope_int_pos", "slope_int_neg", "slope_int_abs", "slope_rms",
    # Gruppo 2 — Slope statistiche (8)
    "slope_mean_pos", "slope_std_pos", "slope_mean_neg", "slope_std_neg",
    "slope_max", "slope_min", "slope_std_all", "slope_std_sq_pos",
    # Gruppo 3 — Slope struttura spaziale (3)
    "slope_L_up_frac", "slope_sign_changes_per_km", "slope_max_run_up_km",
    # Gruppo 4 — Velocità statistiche (4)
    "vlim_mean", "vlim_std", "vlim_max", "vlim_min",
    # Gruppo 5 — Velocità energia cinetica (4)
    "vlim_sum_abs_dv2", "vlim_changes_per_km", "vlim_sum_dv_pos_sq", "vlim_sum_dv_neg_sq",
    # Gruppo 6 — Velocità classi (3)
    "vlim_frac_low", "vlim_frac_mid", "vlim_frac_high",
    # Gruppo 7 — Fermate densità (3)
    "stops_density", "stops_spacing_mean", "stops_spacing_std",
    # Gruppo 8 — Fermate energia (4)
    "stops_sum_v2", "stops_mean_v", "stops_std_v", "stops_sum_v2_segweighted",
    # Gruppo 9 — Fermate pendenza locale (3)
    "stops_mean_p", "stops_sum_abs_p", "stops_frac_on_slope",
    # Gruppo 10 — Cross-feature (10)
    "cross_Lup_v", "cross_Ldn_v", "cross_brake_energy_signed", "cross_thermal_fatigue",
    "cross_stops_v_seg", "cross_abs_p_highv", "cross_up_lowv", "cross_mean_p_v",
    "cross_int_p_v", "cross_var_p_v",
    # Gruppo 11 — Binning spaziale K=10 (20)
    "bin_p_1", "bin_p_2", "bin_p_3", "bin_p_4", "bin_p_5",
    "bin_p_6", "bin_p_7", "bin_p_8", "bin_p_9", "bin_p_10",
    "bin_v_1", "bin_v_2", "bin_v_3", "bin_v_4", "bin_v_5",
    "bin_v_6", "bin_v_7", "bin_v_8", "bin_v_9", "bin_v_10",
]
@assert length(FEATURE_NAMES) == 69

# Count elements in vector v where predicate pred returns true
# pred: a function like x -> x > 0 that returns true/false
function _count(pred::Function, v::Vector{T}) where T
    c = 0
    @inbounds for x in v
        pred(x) && (c += 1)
    end
    return c
end

# Filter vector to keep only positive values (> 0)
# Returns new vector with only elements where x > 0
function _filter_positive(v::AbstractVector{Float64})::Vector{Float64}
    r = Float64[]
    @inbounds for x in v
        if x > 0.0; push!(r, x); end
    end
    return r
end

# Filter vector to keep only negative values (< 0)
# Returns new vector with only elements where x < 0
function _filter_negative(v::AbstractVector{Float64})::Vector{Float64}
    r = Float64[]
    @inbounds for x in v
        if x < 0.0; push!(r, x); end
    end
    return r
end

# Get speed limit at position x_km by looking through segments
# Each segment is (start_km, end_km, speed_kmh)
# Returns the speed limit for the segment containing x_km
function vlim_at(x_km::Real, segments::Vector{Tuple{Float64,Float64,Float64}})::Float64
    @inbounds for seg in segments
        if x_km >= seg[1] && x_km < seg[2]
            return seg[3]
        end
    end
    return segments[end][3]
end

# Get slope at position x_km from slope vector p
# p has one value per meter, so index = round(x_km * 1000) + 1
# Returns slope in per mille (‰) at that position
function slope_at(x_km::Real, p::Vector{Float64})::Float64
    idx = clamp(round(Int, x_km * 1000) + 1, 1, length(p))
    return p[idx]
end

# Find maximum run length of consecutive positive values
# Example: [1,2,3,-1,2,3,4,5] -> max run is 4 (values 2,3,4,5)
function max_run_positive(v::Vector{Float64})::Int
    max_run = 0
    current_run = 0
    @inbounds for val in v
        if val > 0
            current_run += 1
            max_run = max(max_run, current_run)
        else
            current_run = 0
        end
    end
    return max_run
end

# Count number of sign changes in vector
# Ignores zeros - only counts when sign goes from + to - or - to +
# Example: [1,2,-1,-2,3,-1] -> 2 sign changes
function n_sign_changes(v::Vector{Float64})::Int
    n = length(v)
    n < 2 && return 0
    count = 0
    prev_nonzero = false
    prev_sign = 0.0
    @inbounds for i in 1:n
        if v[i] != 0.0
            if prev_nonzero && sign(v[i]) != prev_sign
                count += 1
            end
            prev_nonzero = true
            prev_sign = sign(v[i])
        end
    end
    return count
end

# Divide vector v into K equal bins and compute mean of each bin
# Used for spatial binning of slope and speed (K=10)
# Example: [1,2,3,4,5,6] with K=3 -> [1.5, 3.5, 5.5]
function bin_means(v::Vector{Float64}, K::Int)::Vector{Float64}
    n = length(v)
    bin_size = n / K
    result = zeros(K)
    for k in 1:K
        lo = max(1, ceil(Int, (k-1) * bin_size) + 1)
        hi = min(n, floor(Int, k * bin_size))
        if lo <= hi
            result[k] = sum(@view v[lo:hi]) / (hi - lo + 1)
        end
    end
    return result
end

# Main feature extraction function
# Input arguments (all keyword arguments with semicolon):
#   p::Vector{Float64} - slope vector, one value per meter (length = L*1000), values in per mille (‰)
#   vlim_segments - speed limit segments as [(start_km, end_km, speed_kmh), ...]
#   stops - stop positions in km
#   L - total line length in km
#   P_nom_fc - fuel cell nominal power (kW)
#   C_batt - battery capacity (kWh)
#
# Output: Vector{Float64} with exactly 69 features
function extract_features(; p::Vector{Float64},
                            vlim_segments::Vector{Tuple{Float64,Float64,Float64}},
                            stops::Vector{Float64},
                            L::Float64,
                            P_nom_fc::Float64,
                            C_batt::Float64)::Vector{Float64}

    # Distance between consecutive points: 1 meter in km (0.001 km = 1 m)
    dx = 1e-3

    # Separate positive and negative slopes for independent analysis
    p_pos = _filter_positive(p)
    p_neg = _filter_negative(p)

    # Gruppo 1: Slope gravitational work (4 features)
    # Integral of slope over the line - related to energy spent climbing
    slope_int_pos = sum(max.(p, 0.0)) * dx  # Integral of positive (uphill) slopes
    slope_int_neg = sum(max.(-p, 0.0)) * dx  # Integral of negative (downhill) slopes
    slope_int_abs = sum(abs.(p)) * dx        # Integral of absolute slope
    slope_rms = sqrt(mean(p.^2))           # Root mean square of slope

    # Gruppo 2: Slope statistics (8 features)
    # Mean, std, max, min of slopes
    slope_mean_pos = isempty(p_pos) ? 0.0 : mean(p_pos)
    slope_std_pos = length(p_pos) < 2 ? 0.0 : std(p_pos)
    slope_mean_neg = isempty(p_neg) ? 0.0 : mean(p_neg)
    slope_std_neg = length(p_neg) < 2 ? 0.0 : std(p_neg)

    slope_max = maximum(p)        # Maximum (steepest uphill)
    slope_min = minimum(p)        # Minimum (steepest downhill)
    slope_std_all = std(p)          # Standard deviation of all slopes
    slope_std_sq_pos = length(p_pos) < 2 ? 0.0 : std(p_pos.^2)

    # Gruppo 3: Slope spatial structure (3 features)
    # How slope is distributed along the line
    slope_L_up_frac = _count(x -> x > 0.0, p) / length(p)  # Fraction uphill
    slope_sign_changes_per_km = n_sign_changes(p) / L       # Sign changes per km
    slope_max_run_up_km = max_run_positive(p) / 1000.0          # Max consecutive uphill (km)

    # Extract speed values and segment lengths from segments
    v_vals = Float64[seg[3] for seg in vlim_segments]  # Speed values
    v_lens = Float64[seg[2] - seg[1] for seg in vlim_segments]  # Segment lengths

    # Gruppo 4: Speed statistics (4 features)
    # Statistics of speed limits
    vlim_mean = sum(v_vals .* v_lens) / L                  # Weighted mean speed
    vlim_var_sum = sum(v_lens .* (v_vals .- vlim_mean).^2)   # Weighted variance
    vlim_std = sqrt(vlim_var_sum / L)                       # Weighted std
    vlim_max = maximum(v_vals)                           # Maximum speed limit
    vlim_min = minimum(v_vals)                          # Minimum speed limit

    # Gruppo 5: Speed energy / kinetic energy (4 features)
    # Energy-related from speed changes
    vlim_sum_abs_dv2 = sum(abs.(diff(v_vals.^2)))  # Sum of |Δ(v²)|

    M = length(vlim_segments)
    vlim_changes_per_km = (M - 1) / L           # Speed changes per km
    vlim_sum_dv_pos_sq = sum(max.(diff(v_vals), 0.0).^2)  # Speed increases squared
    vlim_sum_dv_neg_sq = sum(max.(-diff(v_vals), 0.0).^2)  # Speed decreases squared

    # Gruppo 6: Speed classes (3 features)
    # Fraction of line in each speed class
    vlim_frac_low = sum(v_lens[i] for i in 1:M if v_vals[i] < 80.0; init=0.0) / L
    vlim_frac_mid = sum(v_lens[i] for i in 1:M if 80.0 <= v_vals[i] < 100.0; init=0.0) / L
    vlim_frac_high = sum(v_lens[i] for i in 1:M if v_vals[i] >= 100.0; init=0.0) / L

    # Gruppo 7: Stop density (3 features)
    # Number and spacing of stops
    stops_density = length(stops) / L  # Stops per km

    if isempty(stops)
        stops_spacing_mean = L
        stops_spacing_std = 0.0
    else
        # Include start (0) and end (L) in spacing calculation
        spacings = diff([0.0; stops; L])
        stops_spacing_mean = mean(spacings)
        stops_spacing_std = length(spacings) < 2 ? 0.0 : std(spacings)
    end

    # Get speed and slope at each stop position
    stops_vs = isempty(stops) ? Float64[] : [vlim_at(x, vlim_segments) for x in stops]
    stops_ps = isempty(stops) ? Float64[] : [slope_at(x, p) for x in stops]

    # Gruppo 8: Stop energy (4 features)
    # Energy-related at stop positions
    stops_sum_v2 = isempty(stops) ? 0.0 : sum(v^2 for v in stops_vs)
    stops_mean_v = isempty(stops) ? 0.0 : mean(stops_vs)
    stops_std_v = length(stops) < 2 ? 0.0 : std(stops_vs)

    stops_sum_v2_segweighted = 0.0
    @inbounds for seg in vlim_segments
        seg_stops = isempty(stops) ? 0 : _count(x -> x >= seg[1] && x < seg[2], stops)
        stops_sum_v2_segweighted += seg[3]^2 * seg_stops
    end

    # Gruppo 9: Stop local slope (3 features)
    # Slope at stop positions
    stops_mean_p = isempty(stops) ? 0.0 : mean(stops_ps)
    stops_sum_abs_p = isempty(stops) ? 0.0 : sum(abs, stops_ps)
    stops_frac_on_slope = isempty(stops) ? 0.0 : _count(x -> abs(x) > 5.0, stops_ps) / length(stops)

    # Pre-compute per-segment statistics for cross features
    seg_p_pos_means = Float64[]   # Mean positive slope per segment
    seg_p_neg_means = Float64[]  # Mean negative slope per segment
    seg_p_vars = Float64[]        # Slope variance per segment
    seg_stop_counts = Int[]      # Number of stops per segment

    @inbounds for seg in vlim_segments
        x1_m = max(1, round(Int, seg[1] * 1000) + 1)
        x2_m = min(length(p), round(Int, seg[2] * 1000) + 1)
        if x1_m <= x2_m
            seg_p = @view p[x1_m:x2_m]
            seg_p_pos = _filter_positive(seg_p)
            seg_p_neg = _filter_negative(seg_p)
            push!(seg_p_pos_means, isempty(seg_p_pos) ? 0.0 : mean(seg_p_pos))
            push!(seg_p_neg_means, isempty(seg_p_neg) ? 0.0 : mean(seg_p_neg))
            push!(seg_p_vars, length(seg_p) < 2 ? 0.0 : var(seg_p))
        else
            push!(seg_p_pos_means, 0.0)
            push!(seg_p_neg_means, 0.0)
            push!(seg_p_vars, 0.0)
        end
        push!(seg_stop_counts, isempty(stops) ? 0 : _count(x -> x >= seg[1] && x < seg[2], stops))
    end

    # Gruppo 10: Cross features (10 features)
    # Interactions between slope, speed, and stops
    cross_Lup_v = sum((vlim_segments[i][2] - vlim_segments[i][1]) * seg_p_pos_means[i] * v_vals[i] for i in 1:M; init=0.0)
    cross_Ldn_v = sum((vlim_segments[i][2] - vlim_segments[i][1]) * seg_p_neg_means[i] * v_vals[i] for i in 1:M; init=0.0)

    cross_brake_energy_signed = isempty(stops) ? 0.0 : sum(stops_vs[i]^2 * sign(stops_ps[i]) for i in eachindex(stops); init=0.0)

    cross_thermal_fatigue = sum((vlim_segments[i][2] - vlim_segments[i][1]) * seg_p_vars[i] * v_vals[i] for i in 1:M; init=0.0)

    cross_stops_v_seg = sum((vlim_segments[i][2] - vlim_segments[i][1]) * v_vals[i] * seg_stop_counts[i] for i in 1:M; init=0.0)

    cross_abs_p_highv = 0.0
    @inbounds for i in 1:M
        if v_vals[i] > 100.0
            x1_m = max(1, round(Int, vlim_segments[i][1] * 1000) + 1)
            x2_m = min(length(p), round(Int, vlim_segments[i][2] * 1000) + 1)
            if x1_m <= x2_m
                cross_abs_p_highv += (vlim_segments[i][2] - vlim_segments[i][1]) * mean(abs, @view p[x1_m:x2_m])
            end
        end
    end

    cross_up_lowv = sum((vlim_segments[i][2] - vlim_segments[i][1]) * seg_p_pos_means[i] for i in 1:M if v_vals[i] < 80.0; init=0.0)

    N_pts = length(p)
    pv_vals = Vector{Float64}(undef, N_pts)
    @inbounds for i in 1:N_pts
        pv_vals[i] = p[i] * vlim_at((i - 1) * dx, vlim_segments)
    end
    cross_mean_p_v = sum(pv_vals) / N_pts
    cross_int_p_v = sum(pv_vals) * dx
    cross_var_p_v = length(pv_vals) < 2 ? 0.0 : var(pv_vals)

    # Gruppo 11: Spatial binning (20 features)
    # Divide line into 10 equal parts, compute mean slope and speed for each
    bin_p = bin_means(p, 10)  # Mean slope in each tenth

    # Mean speed in each tenth (weighted by segment overlap)
    bin_v = zeros(10)
    for k in 1:10
        lo_km = (k - 1) * L / 10
        hi_km = k * L / 10
        total_w = 0.0
        weighted_v = 0.0
        @inbounds for seg in vlim_segments
            x1 = max(seg[1], lo_km)
            x2 = min(seg[2], hi_km)
            if x2 > x1
                w = x2 - x1
                weighted_v += w * seg[3]
                total_w += w
            end
        end
        bin_v[k] = total_w > 0 ? weighted_v / total_w : 0.0
    end

    # Assemble all 69 features into single vector
    # Order must match FEATURE_NAMES array
    features = Float64[
        # Gruppo 0: Basic scalars (3)
        L, P_nom_fc, C_batt,
        # Gruppo 1: Slope gravitational work (4)
        slope_int_pos, slope_int_neg, slope_int_abs, slope_rms,
        # Gruppo 2: Slope statistics (8)
        slope_mean_pos, slope_std_pos, slope_mean_neg, slope_std_neg,
        slope_max, slope_min, slope_std_all, slope_std_sq_pos,
        # Gruppo 3: Slope spatial structure (3)
        slope_L_up_frac, slope_sign_changes_per_km, slope_max_run_up_km,
        # Gruppo 4: Speed statistics (4)
        vlim_mean, vlim_std, vlim_max, vlim_min,
        # Gruppo 5: Speed energy (4)
        vlim_sum_abs_dv2, vlim_changes_per_km, vlim_sum_dv_pos_sq, vlim_sum_dv_neg_sq,
        # Gruppo 6: Speed classes (3)
        vlim_frac_low, vlim_frac_mid, vlim_frac_high,
        # Gruppo 7: Stop density (3)
        stops_density, stops_spacing_mean, stops_spacing_std,
        # Gruppo 8: Stop energy (4)
        stops_sum_v2, stops_mean_v, stops_std_v, stops_sum_v2_segweighted,
        # Gruppo 9: Stop local slope (3)
        stops_mean_p, stops_sum_abs_p, stops_frac_on_slope,
        # Gruppo 10: Cross features (10)
        cross_Lup_v, cross_Ldn_v, cross_brake_energy_signed, cross_thermal_fatigue,
        cross_stops_v_seg, cross_abs_p_highv, cross_up_lowv, cross_mean_p_v,
        cross_int_p_v, cross_var_p_v,
        # Gruppo 11: Spatial binning (20)
        bin_p..., bin_v...,
    ]

    @assert length(features) == 69
    @assert all(isfinite, features)

    return features
end