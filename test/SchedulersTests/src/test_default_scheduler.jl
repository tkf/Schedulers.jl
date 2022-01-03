module TestDefaultScheduler

import Schedulers
using Schedulers.Internal: WorkStealingScheduler, PrioritizedScheduler
using Test

function test_workstealing_trivial()
    scheduler = Schedulers.default_workstealing() do
        Schedulers.current_scheduler()
    end
    @test scheduler isa WorkStealingScheduler
end

function test_prioritized_trivial()
    scheduler = Schedulers.default_prioritized() do
        Schedulers.current_scheduler()
    end
    @test scheduler isa PrioritizedScheduler
end

end  # module
