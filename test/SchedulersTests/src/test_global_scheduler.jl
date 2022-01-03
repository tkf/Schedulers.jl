module TestGlobalScheduler

import Schedulers
using Schedulers.Internal: WorkStealingScheduler, PrioritizedScheduler
using Test

function test_workstealing_trivial()
    scheduler = Schedulers.global_workstealing() do
        Schedulers.current_scheduler()
    end
    @test scheduler isa WorkStealingScheduler
end

function test_prioritized_trivial()
    scheduler = Schedulers.global_prioritized() do
        Schedulers.current_scheduler()
    end
    @test scheduler isa PrioritizedScheduler
end

end  # module
