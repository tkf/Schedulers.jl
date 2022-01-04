mutable struct WorkStealingScheduler <: AbstractScheduler
    @const unfairspins::Int
    @const yieldspins::Int
    @const workerindices::Vector{Int}
    @const threadids::Vector{Int}
    @const workers::Vector{Worker}
    @const queues::Vector{WorkStealingDeque{Task}}
    @const stickyqueues::Vector{ConcurrentQueue{Task}}
    @const externalqueue::ConcurrentQueue{Task}
    @atomic closed::Bool
end

# default_yieldspins() = Threads.nthreads() == 1 ? -1 : 50
default_yieldspins() = -1

function WorkStealingScheduler(
    threadids::Vector{Int};
    unfairspins::Integer = -1,
    yieldspins::Integer = default_yieldspins(),
)
    workerindices = workerindices_from_threadids(threadids)
    ref = Ref{WorkStealingScheduler}()
    workers = create_workers(threadids, ref)
    queues = [WorkStealingDeque{Task}() for _ in threadids]
    stickyqueues = [ConcurrentQueue{Task}() for _ in threadids]
    scheduler = WorkStealingScheduler(
        unfairspins,
        yieldspins,
        workerindices,
        threadids,
        workers,
        queues,
        stickyqueues,
        ConcurrentQueue{Task}(),
        false,
    )
    ref[] = scheduler
    return scheduler
end

function Base.push!(scheduler::WorkStealingScheduler, task::Task)
    @return_if_something push_sticky!(scheduler, task)
    threadid = Threads.threadid()
    workerid = scheduler.workerindices[threadid]
    workerid == 0 && errorwith(; scheduler, threadid) do io, (; scheduler, threadid)
        println(io, "push!(scheduler, task) called outside of worker threads")
        println(io, "called at: threadid = ", threadid)
        print(io, "scheduler ", objid(scheduler), " uses worker thread(s): ")
        join(io, scheduler.threadids, ", ", ", and")
    end
    push!(scheduler.queues[workerid], task)
    return scheduler
end

function pushat!(scheduler::WorkStealingScheduler, workerid::Integer, task::Task)
    push!(scheduler.queues[workerid], task)
    return scheduler
end

function get_next_task!(scheduler::WorkStealingScheduler, isretry::Bool)
    @return_if_something get_next_task_common!(scheduler)
    threadid = Threads.threadid()
    workerid = scheduler.workerindices[threadid]
    if !isretry
        task = maybepop!(scheduler.queues[workerid])
        task === nothing || return something(task)
        length(scheduler.threadids) == 1 && return nothing
        for _ in 1:length(scheduler.threadids)
            w = rand(1:length(scheduler.threadids)-1)
            w += scheduler.threadids[w] == threadid
            task = maybepopfirst!(scheduler.queues[w])
            task === nothing || return something(task)
        end
    end
    for (tid, queue) in zip(scheduler.threadids, scheduler.queues)
        tid == threadid && continue
        task = maybepopfirst!(queue)
        task === nothing || return something(task)
    end
    return nothing
end
