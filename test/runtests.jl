using Test

@testset "MLTrenoSurrogate" begin
    include("test_ingestion.jl")
    include("test_profile_synth.jl")
    include("test_model.jl")
    include("test_dataset.jl")
    include("test_train.jl")
    include("test_features.jl")
    include("test_doe_generator.jl")
end
