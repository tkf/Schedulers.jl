module TestBasics

import Schedulers
using ArgCheck: @check
using Schedulers.Internal: @record
using Test

using ..Utils: fetch_finished

function check_simple_spawn(scheduler)
    @record(:check_simple_spawn_begin, scheduler)
    local t1, t2
    Schedulers.open(scheduler) do _
        t1 = Schedulers.spawn(() -> 1)
        t2 = Schedulers.spawn(() -> fetch(t1) + 2)
        wait(t2)
    end
    @record(:check_simple_spawn_end, scheduler)
    @test fetch_finished(t1) == 1
    @test fetch_finished(t2) == 3
end

function test_simple_spawn()
    @testset "$scheduler" for scheduler in [Schedulers.workstealing, Schedulers.prioritized]
        check_simple_spawn(scheduler())
    end
end

end  # module
