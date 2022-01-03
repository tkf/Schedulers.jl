module TestBenchmarks

using SchedulersBenchmarks: clear, setup_smoke
using Test

function test_smoke_test_benchmarks()
    try
        local suite
        @test (suite = setup_smoke()) isa Any
        @test run(suite) isa Any
    finally
        clear()
    end
end

end  # module
