include_dependency("guess_task_layout.jl")
const TASK_TID_OFFSET = let script = joinpath(@__DIR__, "guess_task_layout.jl")
    out = read(`$(Base.julia_cmd()) --startup-file=no $script`, String)
    parse(Int, out)
end

include("taskhack_impl.jl")
check_set_raw_tid()
