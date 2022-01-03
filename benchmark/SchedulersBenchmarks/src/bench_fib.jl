module BenchFib

import Schedulers
using Schedulers.Internal: WorkStealingScheduler, WorkerStates
using BenchmarkTools

module SchedulersFib
using Schedulers
function fib(n::Int)
    n <= 1 && return n
    t = Schedulers.spawn() do
        fib(n - 2)
    end
    return fib(n - 1) + fetch(t)::Int
end
end # module SchedulersFib

module BaseFib
function fib(n::Int)
    n <= 1 && return n
    t = Threads.@spawn fib(n - 2)
    return fib(n - 1) + fetch(t)::Int
end
end # module BaseFib

function unsafe_gc!(scheduler::WorkStealingScheduler)
    nspins = 0
    for worker in scheduler.workers
        while (@atomic :monotonic worker.state) != WorkerStates.WAITING
            yield()
            nspins += 1
            if nspins > 1_000_000
                return
            end
        end
    end
    for deque in scheduler.queues
        data = deque.buffer.data
        n = length(data)
        empty!(data)
        resize!(data, n)
    end
end

function setup(; ns = [20])
    suite = BenchmarkGroup()
    for n in ns
        sn = suite["n=$n"] = BenchmarkGroup()
        sn["scheduler=:workstealing"] = @benchmarkable(
            Schedulers.global_workstealing() do
                SchedulersFib.fib($n)
            end,
            # Calling GC manually to avoid hitting copy-stack
            setup = begin
                unsafe_gc!(Schedulers.Internal.DEFAULT_WORKSTEALING_SCHEDULER_HANDLE[])
                GC.gc(false)
            end
        )
        sn["scheduler=:prioritized"] = @benchmarkable(
            Schedulers.global_prioritized() do
                SchedulersFib.fib($n)
            end,
            # Calling GC manually to avoid hitting copy-stack
            setup = GC.gc(false)
        )
        sn["scheduler=:base"] = @benchmarkable(
            BaseFib.fib($n),
            # To be equivalent to what other benchmarks do:
            setup = GC.gc(false),
        )
    end
    return suite
end

function clear() end

end  # module
