module BenchFib

import Schedulers
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

function setup(; ns = [20])
    suite = BenchmarkGroup()
    for n in ns
        sn = suite["n=$n"] = BenchmarkGroup()
        sn["scheduler=:workstealing"] = @benchmarkable Schedulers.global_workstealing() do
            BaseFib.fib($n)
        end
        sn["scheduler=:prioritized"] = @benchmarkable Schedulers.global_prioritized() do
            BaseFib.fib($n)
        end
        sn["scheduler=:base"] = @benchmarkable BaseFib.fib($n)
    end
    return suite
end

function clear() end

end  # module
