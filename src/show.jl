function Base.print(io::IO, scheduler::AbstractScheduler)
    print(io, nameof(typeof(scheduler)), " with ")
    nworkers = length(scheduler.workers)
    print(io, nworkers, " worker", nworkers == 1 ? "" : "s")
end

function Base.show(io::IO, ::MIME"text/plain", scheduler::AbstractScheduler)
    print(io, scheduler)
end

function Base.show(io::IO, ::MIME"text/plain", multiq::MultiQueue)
    print(io, "MultiQueue with ", length(multiq.heaps), " heaps and")
    print(io, " #elements = ")
    isfirst = true
    for h in multiq.heaps
        if isfirst
            isfirst = false
        else
            print(io, ", ")
        end
        if trylock(h)
            n = try
                length(h.heap)
            finally
                unlock(h)
            end
            print(io, n)
        else
            print(io, "???")
        end
    end
end
