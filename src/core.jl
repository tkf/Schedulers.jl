abstract type AbstractScheduler end

function workerindices_from_threadids(threadids::AbstractVector{<:Integer})
    workerindices = zeros(Int, Threads.nthreads())
    for (wi, tid) in pairs(threadids)
        workerindices[tid] = wi
    end
    return workerindices
end

Base.isopen(scheduler::AbstractScheduler) = !@atomic scheduler.closed
function Base.close(scheduler::AbstractScheduler)
    @record(:close, scheduler)
    @atomic scheduler.closed = true
    wakeall!(scheduler)
    return
end

function scheduler_task()
    thunk = thunkof(current_task())
    worker = @atomic :monotonic thunk.worker
    worker::Worker
    return taskof(worker)
end

pushat!(scheduler::AbstractScheduler, _workerid::Integer, task::Task) =
    push!(scheduler, task)

"""
    taskof(thing) -> task::Core.Task

Return a `task` associated with the `thing` (scheduler, worker, `GenericTask`
etc.).
"""
taskof
taskof(task::Task) = task

baremodule WorkerStates
using Base: @enum, UInt8
@enum Kind::UInt8 begin
    ACTIVE
    PREPARE_WAITING
    WAITING
    NOTIFYING
    CREATED
    DONE
end
end  # baremodule TaskStates

mutable struct Worker
    @const task::Task
    @atomic state::WorkerStates.Kind
end

Worker(task::Task) = Worker(task, WorkerStates.CREATED)
taskof(worker::Worker) = worker.task

Threads.threadid(worker::Worker) = Threads.threadid(taskof(worker))

baremodule WaiterStates
using Base: @enum, UInt8
@enum Kind::UInt8 begin
    # Set by waiter:
    INITIAL
    WAITING
    # Set by notifier:
    DONTWAIT
    NOTIFYING
end
end

mutable struct Waiter
    @const task::Task
    next::Union{Waiter,Nothing}
    @atomic state::WaiterStates.Kind
end

Waiter() = Waiter(current_task(), nothing, WaiterStates.INITIAL)

taskof(waiter::Waiter) = waiter.task

baremodule TaskStates
using Base: @enum, UInt8
@enum Kind::UInt8 begin
    DONE
    ERROR
    STARTED
    CREATED
end
end  # baremodule TaskStates

const PriorityInt = Int

as_priority(::Nothing) = zero(PriorityInt)
function as_priority(priority::Integer)
    priority = convert(PriorityInt, priority)
    return max(typemin(PriorityInt) + 1, priority)
end

struct Closed end

mutable struct Thunk{Scheduler<:AbstractScheduler}
    @const f::OpaqueClosure{Tuple{}}
    @const scheduler::Scheduler
    priority::PriorityInt
    @atomic worker::Union{Nothing,Worker}
    result::Any
    @atomic waiter::Union{Nothing,Closed,Waiter}
    state::TaskStates.Kind

    Thunk{Scheduler}(
        @nospecialize(f),
        scheduler::Scheduler,
        priority::Union{Integer,Nothing},
    ) where {Scheduler<:AbstractScheduler} = new{Scheduler}(
        f,
        scheduler,
        as_priority(priority),
        nothing,
        nothing,
        nothing,
        TaskStates.CREATED,
    )
end

thunkof(tasklike) = taskof(tasklike).code::ConcreteThunk
schedulerof(tasklike) = thunkof(tasklike).scheduler

struct GenericTask
    task::Task
end

function generic_task(
    @nospecialize(f),
    scheduler::AbstractScheduler;
    priority::Union{Integer,Nothing} = nothing,
)
    thunk = ConcreteThunk(as_opaqueclosure(f)::OpaqueClosure{Tuple{}}, scheduler, priority)
    task = Task(thunk)
    task.sticky = false  # will be flipped in `(::Thunk)()`
    return GenericTask(task)
end

as_opaqueclosure(@nospecialize(f)) = @opaque () -> f()
as_opaqueclosure(f::OpaqueClosure) = f
# TODO: transform the thunk to `OpaqueClosure` in a frontend macro

GenericTask(waiter::Waiter) = GenericTask(taskof(waiter))

taskof(task::GenericTask) = task.task

stateof(task) = thunkof(task).state
isfinished(state::TaskStates.Kind) = state == TaskStates.DONE || state == TaskStates.ERROR
isfinished(task) = isfinished(stateof(task))

Base.istaskdone(task::GenericTask) = isfinished(task)
Base.istaskfailed(task::GenericTask) = stateof(task) == TaskStates.ERROR

Historic.taskid(task::GenericTask) = Historic.taskid(task.task)
Historic.taskid(waiter::Waiter) = Historic.taskid(waiter.task)
Historic.taskid(worker::Worker) = Historic.taskid(worker.task)

struct ThunkID
    uint::UInt
end

ThunkID(thunk::Thunk) = ThunkID(UInt(pointer_from_objref(thunk)))

function Base.print(io::IO, id::ThunkID)
    print(io, "thunk-", string(id.uint; base = 16, pad = Sys.WORD_SIZE >> 2))
end
