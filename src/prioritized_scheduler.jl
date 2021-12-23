taskheap() = lockedheap(Pair{PriorityInt,Task}, PriorityInt; by = first)
# Note: to avoid messing up the heap invariance, the priority is quenched by the
# time it is pushed to the heap

const TaskHeap = typeof(taskheap())

mutable struct PrioritizedScheduler <: AbstractScheduler
    @const unfairspins::Int
    @const yieldspins::Int
    @const workerindices::Vector{Int}
    @const threadids::Vector{Int}
    @const workers::Vector{Worker}
    @const multiq::MultiQueue{TaskHeap}
    @const externalqueue::ConcurrentQueue{Task}
    @atomic closed::Bool
end

function PrioritizedScheduler(
    threadids::Vector{Int};
    unfairspins::Integer = -1,
    yieldspins::Integer = default_yieldspins(),
    c::Real = 2,
)
    workerindices = workerindices_from_threadids(threadids)
    ref = Ref{PrioritizedScheduler}()
    workers = create_workers(threadids, ref)
    heaps = [taskheap() for _ in 1:ceil(Int, c * length(threadids))]
    if length(heaps) < length(threadids)
        error(
            "not enough number of heaps: length(heaps) = ",
            length(heaps),
            " ≥ length(threadids) = ",
            length(threadids),
            "; i.e., c = ",
            c,
            " is too small",
        )
    end
    scheduler = PrioritizedScheduler(
        unfairspins,
        yieldspins,
        workerindices,
        threadids,
        workers,
        MultiQueue(heaps),
        ConcurrentQueue{Task}(),
        false,
    )
    ref[] = scheduler
    return scheduler
end

function Base.push!(scheduler::PrioritizedScheduler, task::Task)
    priority = thunkof(task).priority
    push!(scheduler.multiq, -priority => task)
    return scheduler
end

function get_next_task!(scheduler::PrioritizedScheduler, _isretry::Bool)
    let y = maybepopfirst!(scheduler.externalqueue)
        if y isa Some
            return something(y)::Task
        end
    end
    while true

        y = trypop!(scheduler.multiq)
        if y isa Some
            return last(something(y))::Task
        else
            # TODO: do different things when `Contention` vs `LikelyEmpty`?
            return nothing
        end
    end
end

function Schedulers.setpriority(priority::Integer)
    priority = as_priority(priority)
    thunkof(Schedulers.current_task()).priority = priority
    return
end
