module Dataset

using CSV
using DataFrames
using Random

export assemble_dataset, train_test_split

const OUTPUT_COLS = ["H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt"]
const FEATURE_COLS_RAW = [
    "L_km", "P_nom_fc", "C_batt", "slope_int_pos", "slope_int_neg",
    "slope_int_abs", "slope_rms", "slope_mean_pos", "slope_std_pos",
    "slope_mean_neg", "slope_std_neg", "slope_max", "slope_min",
    "slope_std_all", "slope_std_sq_pos", "slope_L_up_frac",
    "slope_sign_changes_per_km", "slope_max_run_up_km", "vlim_mean",
    "vlim_std", "vlim_max", "vlim_min", "vlim_sum_abs_dv2",
    "vlim_changes_per_km", "vlim_sum_dv_pos_sq", "vlim_sum_dv_neg_sq",
    "vlim_frac_low", "vlim_frac_mid", "vlim_frac_high", "stops_density",
    "stops_spacing_mean", "stops_spacing_std", "stops_sum_v2",
    "stops_mean_v", "stops_std_v", "stops_sum_v2_segweighted",
    "stops_mean_p", "stops_sum_abs_p", "stops_frac_on_slope",
    "cross_Lup_v", "cross_Ldn_v", "cross_brake_energy_signed",
    "cross_thermal_fatigue", "cross_stops_v_seg", "cross_abs_p_highv",
    "cross_up_lowv", "cross_mean_p_v", "cross_int_p_v", "cross_var_p_v",
    "bin_p_1", "bin_p_2", "bin_p_3", "bin_p_4", "bin_p_5",
    "bin_p_6", "bin_p_7", "bin_p_8", "bin_p_9", "bin_p_10",
    "bin_v_1", "bin_v_2", "bin_v_3", "bin_v_4", "bin_v_5",
    "bin_v_6", "bin_v_7", "bin_v_8", "bin_v_9", "bin_v_10",
]
@assert length(FEATURE_COLS_RAW) == 69 "Feature column count must be 69"

function assemble_dataset(raw_rows_path::AbstractString, features_path::AbstractString)::DataFrame
    raw_df = CSV.read(raw_rows_path, DataFrame; types=Dict(:row_idx=>Int))
    feat_df = CSV.read(features_path, DataFrame; types=Dict(:row_idx=>Int))

    @assert "row_idx" in names(raw_df) && "row_idx" in names(feat_df) "Missing row_idx"
    @assert all(c -> c in names(feat_df), FEATURE_COLS_RAW) "Missing feature columns in features_matrix"
    @assert all(c -> c in names(raw_df), OUTPUT_COLS) "Missing output columns in raw_rows"

    raw_narrow = select(raw_df, :row_idx, OUTPUT_COLS..., :source_file)
    feat_narrow = select(feat_df, :row_idx, FEATURE_COLS_RAW...)

    joined = innerjoin(raw_narrow, feat_narrow, on=:row_idx)
    sort!(joined, :row_idx)

    source_group = basename.(joined.source_file)
    select!(joined, Not(:source_file))
    insertcols!(joined, ncol(joined) + 1, :source_group => source_group)

    return joined
end

function train_test_split(
    df::DataFrame;
    test_frac::Real=0.2,
    seed::Integer=42,
)::Tuple{DataFrame,DataFrame}
    Random.seed!(seed)

    train_rows = Int[]
    test_rows = Int[]

    for g in groupby(df, :source_group)
        idxs = g.row_idx
        n = nrow(g)
        if n < 5
            append!(train_rows, idxs)
        else
            n_test = max(1, round(Int, n * test_frac))
            perm = Random.shuffle(1:n)
            test_i = view(perm, 1:n_test)
            train_i = view(perm, n_test+1:n)
            append!(test_rows, idxs[test_i])
            append!(train_rows, idxs[train_i])
        end
    end

    train_set = Set(train_rows)
    test_set = Set(test_rows)

    train_df = filter(r -> r.row_idx in train_set, df)
    test_df = filter(r -> r.row_idx in test_set, df)

    return train_df, test_df
end

end
