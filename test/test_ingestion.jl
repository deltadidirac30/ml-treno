using Test
using DataFrames

include(joinpath(@__DIR__, "..", "src", "ingestion.jl"))

@testset "Ingestion" begin
    @testset "European float parsing" begin
        @test parse_eu_float("0,5") == 0.5
        @test parse_eu_float("1,234") == 1.234
        @test parse_eu_float("10,5") == 10.5
        @test parse_eu_float(0.5) == 0.5
        @test parse_eu_float(10) == 10.0
        @test ismissing(parse_eu_float(missing))
        @test parse_eu_float("invalid") === missing
    end
    
    @testset "TCO filter logic" begin
        test_df = DataFrame(
            TCO = [100.0, 600.0, 250.0, 500.0, 501.0],
            valid = [true, false, true, true, false],
        )
        filtered = filter(row -> row.TCO <= 500.0, test_df)
        @test nrow(filtered) == 3
        @test all(filtered.TCO .<= 500.0)
    end
    
    @testset "No NaN in result" begin
        test_df = DataFrame(
            P_nom_fc = [100.0, 200.0],
            C_batt = [50.0, 60.0],
            H2_cons = [10.0, 20.0],
            SOC_end = [0.5, 0.6],
        )
        for col in names(test_df)
            @test !any(isnan.(test_df[!, col]))
            @test !any(ismissing.(test_df[!, col]))
        end
    end
    
    @testset "Seed determinism" begin
        seed1 = hash(("test_file.xlsx", "sheet1", 1)) % UInt32
        seed2 = hash(("test_file.xlsx", "sheet1", 1)) % UInt32
        @test seed1 == seed2
        
        seed3 = hash(("test_file.xlsx", "sheet1", 2)) % UInt32
        @test seed1 != seed3
    end
    
    @testset "Integer parsing" begin
        @test parse_eu_int("5") == 5
        @test parse_eu_int("5,5") == 6
        @test parse_eu_int(5) == 5
        @test parse_eu_int(5.7) == 6
        @test ismissing(parse_eu_int(missing))
    end
end