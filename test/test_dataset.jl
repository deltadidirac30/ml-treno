using Test
using CSV
using DataFrames
using Random

include(joinpath(@__DIR__, "..", "src", "dataset.jl"))
using .Dataset

const RAW_PATH = joinpath(@__DIR__, "..", "data_generated", "raw_rows.csv")
const FEAT_PATH = joinpath(@__DIR__, "..", "data_generated", "features_matrix.csv")

@testset "dataset.jl" begin
    @testset "assemble_dataset" begin
        df = assemble_dataset(RAW_PATH, FEAT_PATH)
        @test nrow(df) == 3126
        @test ncol(df) == 75
        @test hasproperty(df, :source_group)
        feat_cols = [n for n in names(df) if n ∉ ["row_idx", "H2_cons", "SOC_end", "num_repl_FC", "num_repl_batt", "source_group"]]
        @test length(feat_cols) == 69
        num_cols = filter(n -> eltype(df[!, n]) <: Number, names(df))
        @test all(c -> all(isfinite, df[!, c]), num_cols)
    end

    @testset "train_test_split" begin
        df = assemble_dataset(RAW_PATH, FEAT_PATH)

        train_df, test_df = train_test_split(df; test_frac=0.2, seed=42)
        @test nrow(train_df) + nrow(test_df) == nrow(df)
        @test nrow(train_df) > 0
        @test nrow(test_df) > 0

        all_groups = Set(df.source_group)
        train_groups = Set(train_df.source_group)
        test_groups = Set(test_df.source_group)
        @test issubset(train_groups, all_groups)
        @test issubset(test_groups, all_groups)

        train_df2, test_df2 = train_test_split(df; test_frac=0.2, seed=42)
        @test train_df.row_idx == train_df2.row_idx
        @test test_df.row_idx == test_df2.row_idx

        train_df3, test_df3 = train_test_split(df; test_frac=0.2, seed=123)
        @test train_df.row_idx != train_df3.row_idx
    end
end
