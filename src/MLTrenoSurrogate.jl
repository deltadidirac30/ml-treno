module MLTrenoSurrogate

include("templates.jl")
include("profile_synth.jl")
include("model.jl")
include("train.jl")
include("evaluate.jl")

export REAL_ROUTE_TEMPLATES, template_for_row
export synthesize_slope, synthesize_vlim, synthesize_stops, synthesize_row
export MLPSurrogate, build_model
export zscore_fit, zscore_apply, loss_fn, train!
export evaluate

end