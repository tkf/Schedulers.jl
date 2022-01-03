module TestBenchmarks

using Schedulers.Internal: Debug
using SchedulersBenchmarks: clear, setup
using Test

function test_smoke_test_benchmarks()
    try
        local suite
        #=
        @test (suite = setup_smoke()) isa Any
        =#
        @test (suite = setup()) isa Any
        Debug.get_logger() === nothing || return
        @test run(suite) isa Any
    finally
        clear()
    end
end

end  # module
