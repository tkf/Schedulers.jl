module TestMultiScheduler

import Schedulers
using Schedulers.Internal: @record
using Test

using ..Utils: fetch_finished

function sets2()
    if Threads.nthreads() == 1
        workers1 = workers2 = 1:1
    else
        n1 = Threads.nthreads() ÷ 2
        n2 = Threads.nthreads() - n1
        workers1 = 1:n1
        workers2 = (1:n2) .+ n1
    end
    schedulers = [Schedulers.workstealing, Schedulers.prioritized]
    return Iterators.map(Iterators.product(schedulers, schedulers)) do (f1, f2)
        s1 = f1(workers = workers1)
        s2 = f2(workers = workers2)
        (; label = "$f1-$f2", s1, s2)
    end
end

function check_combination2(s1, s2)
    local t1, t2, t3
    @sync begin
        s1ready = Base.Event()
        t1ready = Base.Event()
        @async begin
            Schedulers.open(s1) do s1
                notify(s1ready)
                @record(:s1ready)
                @record(:wait_t1ready_begin)
                wait(t1ready)
                @record(:wait_t1ready_end)
                @record(:s1_waits_t1_begin)
                wait(t1)  # waiting a s1 task in a s1 task
                @record(:s1_waits_t1_end)
                @record(:s1_waits_t3_begin)
                wait(t3)  # waiting a s1 task in a s1 task
                @record(:s1_waits_t3_end)
            end
        end
        Schedulers.open(s2) do s2
            @record(:wait_s1ready_begin)
            wait(s1ready)
            @record(:wait_s1ready_end)
            t1 = Schedulers.spawn(s1) do
                t2 = Schedulers.spawn(s2) do
                    222
                end
                t3 = Schedulers.spawn(s1) do
                    @record(:t3_waits_t2_begin)
                    local y2 = fetch(t2)  # waiting a s2 task in a s1 task
                    @record(:t3_waits_t2_end)
                    y2 + 111
                end
                @record(:t1_waits_t3_begin)
                local y3 = fetch(t3)  # waiting a s1 task in a s1 task
                @record(:t1_waits_t3_end)
                @record(:t1_waits_t2_begin)
                local y2 = fetch(t2)  # waiting a s2 task in a s1 task
                @record(:t1_waits_t2_end)
                y3 - y2
            end
            notify(t1ready)
            @record(:t1ready)
            @record(:t2_waits_t1_begin)
            wait(t1)  # waiting a s2 task in a s1 task
            @record(:t2_waits_t1_end)
            @record(:t2_waits_t3_begin)
            wait(t3)  # waiting a s1 task in a s2 task
            @record(:t2_waits_t3_end)
        end
    end
    @test fetch_finished(t1) == 111
    @test fetch_finished(t2) == 222
    @test fetch_finished(t3) == 333
end

function test_combination2()
    @testset "$(p.label)" for p in sets2()
        check_combination2(p.s1, p.s2)
    end
end

end  # module
