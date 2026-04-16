using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using Statistics

include(joinpath(@__DIR__, "..", "src", "dataset.jl"))
using .Dataset

const RAW_PATH = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")
const FEAT_PATH = joinpath(@__DIR__, "..", "data_generated", "features_matrix.csv")
const OUT_FINAL = joinpath(@__DIR__, "..", "data_generated", "dataset_final.csv")
const OUT_TRAIN  = joinpath(@__DIR__, "..", "data_generated", "train.csv")
const OUT_TEST  = joinpath(@__DIR__, "..", "data_generated", "test.csv")

function _to_float32!(df::DataFrame)
    for col in names(df)
        T = eltype(df[!, col])
        if T <: Number && !(T <: Float32)
            df[!, col] = Float32.(df[!, col])
        end
    end
end

println("Assembling dataset...")
df = assemble_dataset(RAW_PATH, FEAT_PATH)

expected_cols = 75
@assert ncol(df) == expected_cols "Expected $expected_cols columns, got $(ncol(df))"
num_cols = filter(n -> eltype(df[!, n]) <: Number, names(df))
@assert all(c -> all(isfinite, df[!, c]), num_cols) "Non-finite values in numeric columns"

_to_float32!(df)
CSV.write(OUT_FINAL, df)
println("  → dataset_final.csv  ($(nrow(df)) rows, $(ncol(df)) cols)")

println("Splitting train/test...")
train_df, test_df = train_test_split(df; test_frac=0.2, seed=42)

all_groups = unique(df.source_group)
train_groups = unique(train_df.source_group)
test_groups = unique(test_df.source_group)
@assert issubset(train_groups, all_groups) && issubset(test_groups, all_groups) "Stratification failed"

CSV.write(OUT_TRAIN, train_df)
CSV.write(OUT_TEST, test_df)
println("  → train.csv  ($(nrow(train_df)) rows)")
println("  → test.csv   ($(nrow(test_df)) rows)")

println("\nGroup distribution (train / test):")
for g in sort!(unique(df.source_group))
    n_tr = count(==(g), train_df.source_group)
    n_te = count(==(g), test_df.source_group)
    println("  $g  →  train=$n_tr  test=$n_te")
end

println("\nDone.")
