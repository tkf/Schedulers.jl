const ConcreteScheduler = Union{WorkStealingScheduler,PrioritizedScheduler}
const ConcreteThunk = Thunk{ConcreteScheduler}

function create_workers(threadids::AbstractVector{<:Integer}, schedulerref::Ref)
    return map(threadids) do threadid
        t = @task try
            eventloop(schedulerref[])
        catch err
            @error(
                "Unexpected error from `eventloop($(schedulerref[]))`",
                exception = (err, catch_backtrace())
            )
            close(schedulerref[])
            rethrow()
        end
        @check 1 <= threadid <= Threads.nthreads()
        t.sticky = true
        ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, threadid - 1)
        return Worker(t)
    end
end

function Schedulers.open(@nospecialize(f), scheduler::AbstractScheduler)
    function main()
        try
            return f(scheduler)
        finally
            @record(:main_done)
            # TODO: wait until scheduler is empty? (i.e., the last worker that
            # tried to sleep close the scheduler; it still doesn't wait for the
            # "I/O")
            close(scheduler)
        end
    end
    @record(:open_register_main, scheduler)
    task = generic_task(main, scheduler)
    pushat!(scheduler, 1, taskof(task))
    run(scheduler)
    @check istaskdone(task)
    fetch(task)
end

schedulertypeof(::typeof(Schedulers.workstealing)) = WorkStealingScheduler
schedulertypeof(::typeof(Schedulers.prioritized)) = PrioritizedScheduler

(ctx::SchedulerContextFunction)(;
    workers::Union{Integer,AbstractVector{<:Integer}} = Threads.nthreads(),
    options...,
) = schedulertypeof(ctx)(normalize_threadids(workers); options...)

(ctx::SchedulerContextFunction)(@nospecialize(f); options...) =
    Schedulers.open(f, ctx(; options...))

function start(scheduler::AbstractScheduler)
    unfair = nothing
    for (threadid, worker) in zip(scheduler.threadids, scheduler.workers)
        task = taskof(worker)
        if threadid == Threads.threadid()
            unfair = (; threadid = threadid, task = task)
        else
            Base.schedule(task)
        end
    end
    if unfair !== nothing
        @check unfair.threadid == Threads.threadid()
        yield(unfair.task)
    end
    return scheduler
end

function Base.run(scheduler::AbstractScheduler)
    @record(:run_begin, scheduler)
    start(scheduler)
    waitall(Iterators.map(taskof, scheduler.workers);)
    @record(:run_end, scheduler)
    return
end

function normalize_threadids(workers::Integer)
    @argcheck 1 <= workers <= Threads.nthreads()
    return collect(1:Int(workers))
end

function normalize_threadids(workers::AbstractVector{<:Integer})
    @argcheck !isempty(workers)
    threadids = Int[]
    invalids = nothing
    for (i, n) in pairs(workers)
        if 1 <= n <= Threads.nthreads()
            push!(threadids, n)
        else
            invalids = @something(invalids, Pair{Int,Int}[])
            push!(invalids, i => n)
        end
    end
    if invalids === nothing
        sort!(threadids)
        dups = duplicated_items_in_sorted_iterable(threadids)
        if dups === nothing
            return threadids
        end
        error(str, "Duplicated worker IDs: ", join(dups, ", "))
    end
    str = sprint(invalids) do io, invalids
        print(io, "Invalid worker IDs (must be `0 < _ ≤ nthreads = ")
        print(io, Threads.nthreads())
        print(io, "`): ")
        join(io, ("$n ($i-th element)" for (i, n) in invalids), ", ")
    end
    error(str)
end

struct RescheduleRequest end
# struct WakeupRequest end

struct YieldRequest end
struct WaitRequest end
struct ReturnRequest end
struct ExceptionRequest end

function eventloop(scheduler::AbstractScheduler)
    @record(:eventloop_begin, scheduler)
    threadid = Threads.threadid()
    worker = workerof(scheduler)
    @check current_task() === taskof(worker)
    @atomic worker.state = WorkerStates.ACTIVE
    unfairspins = max(0, scheduler.unfairspins)
    yieldspins = unfairspins + max(0, scheduler.yieldspins)
    nspins = 0
    while true  # task execution loop
        @record(:try_get_next_task, scheduler, nspins)
        task::Union{Task,Nothing} = get_next_task!(scheduler, nspins > 0)
        if task === nothing
            @record(:no_next_task, scheduler)
        else
            @record(:got_next_task, scheduler, task = Historic.taskid(task))
            @DBG schedulerof(task) === scheduler
        end

        if task === nothing
            if !isopen(scheduler)
                @atomic worker.state = WorkerStates.DONE
                break
            end
            nspins += 1
            if nspins < unfairspins
                pause()
                continue
            elseif nspins < yieldspins
                yield()
                continue
            else
                @DBG @check worker.state == WorkerStates.ACTIVE
                task = trysleep!(scheduler, worker)
                if task === nothing
                    @DBG @check threadid == Threads.threadid()
                    continue
                end
            end
        end
        nspins = 0

        while true  # request-reply loop
            @DBG @check threadid == Threads.threadid()
            @record(:schedule, scheduler, task = Historic.taskid(task))
            thunkof(task).worker = worker
            unset_threadid(task)
            @DBG @check Threads.threadid(task) == 0
            request = yieldto(task, RescheduleRequest())
            thunkof(task).worker = nothing
            @record(:requested, scheduler, task = Historic.taskid(task), request)
            @DBG @check threadid == Threads.threadid()
            if request isa YieldRequest
                next = get_next_task!(scheduler, false)
                if next isa Task
                    push!(scheduler, task)
                    task = next
                else
                    # Nothing in the queue. Re-schedule the `task` that just yielded.
                end
            elseif request isa WaitRequest
                break
            elseif request isa Union{ReturnRequest,ExceptionRequest}
                if request isa ExceptionRequest
                    # Let the native scheduler complete the `task`.
                    # See also `_wait(task::GenericTask)`.
                    yield(task)
                end
                notifywaiters!(scheduler, task)
                break
            else
                msg = "thread=$threadid: Unexpected request from `yieldto`"
                @error msg request
                close(scheduler)
                errorwith(; scheduler, worker, request) do io, (; request)
                    print(io, msg)
                    println(io, ":")
                    show(io, MIME"text/plain"(), request)
                end
            end
        end  # request-reply loop
    end  # task execution loop
    @record(:eventloop_end, scheduler)
end

function (thunk::Thunk)()
    try
        @record(:thunk_begin)
        if current_task().sticky
            msg = "FATAL: copy_stack not supported"
            @error(msg)
            error(msg)
        end
        @atomic :monotonic thunk.state = TaskStates.STARTED
        y = thunk.f()
        @record(:thunk_returning)
        thunk.result = y
        @atomic :release thunk.state = TaskStates.DONE
        yieldto(taskof(thunk.worker), ReturnRequest())
    catch err
        # @error(:thunk_error, exception = (err, catch_backtrace()))
        @record(:thunk_error, exception = (err, catch_backtrace()))
        thunk.result = err
        @atomic :release thunk.state = TaskStates.ERROR
        yieldto(taskof(thunk.worker), ExceptionRequest())
        rethrow()
    end
end

function Schedulers.spawn(@nospecialize(f); options...)
    scheduler = Schedulers.current_scheduler()
    task = generic_task(f, scheduler; options...)
    @record(:spawn, task = taskid(task))
    schedule!(scheduler, task)
    return task
end

function Schedulers.spawn(@nospecialize(f), scheduler::AbstractScheduler; options...)
    task = generic_task(f, scheduler; options...)
    @record(:spawn_sch, task = taskid(task), scheduler)
    schedule!(scheduler, task, scheduler !== Schedulers.current_scheduler())
    return task
end

function Schedulers.schedule(task::GenericTask)
    scheduler = thunkof(task).scheduler
    schedule!(scheduler, task, scheduler !== Schedulers.current_scheduler())
    return
end

function schedule!(scheduler, task::Union{Task,GenericTask}, external::AnyBool = FALSE)
    task = taskof(task)
    isopen(scheduler) || errorwith(; scheduler) do io, data
        print(io, "scheduler ", typeof(data.scheduler), " is closed")
    end
    if boolean(external)
        push!(scheduler.externalqueue, task)
    else
        @DBG @check schedulerof(task) === scheduler
        push!(scheduler, task)
    end
    wakeall!(scheduler)
    return
end

function reschedule(task::Union{Task,GenericTask}, current_scheduler)
    scheduler = schedulerof(task)
    schedule!(scheduler, taskof(task), scheduler !== current_scheduler)
end

function trysleep!(scheduler::AbstractScheduler, worker::Worker)
    @atomic worker.state = WorkerStates.PREPARE_WAITING
    task::Union{Task,Nothing} = get_next_task!(scheduler, true)
    task isa Task && @goto done

    state = @atomic :monotonic worker.state
    state == WorkerStates.PREPARE_WAITING || @goto done

    @record(:worker_wait_cas, scheduler)
    @yield_unsafe begin
        state, ok = @atomicreplace(
            worker.state,
            WorkerStates.PREPARE_WAITING => WorkerStates.WAITING
        )
        ok || @goto done

        @record(:worker_wait_begin, scheduler, {yield = false})
    end  # @yield_unsafe
    Base.wait()
    @record(:worker_wait_end, scheduler)

    @label done
    @atomic worker.state = WorkerStates.ACTIVE
    return task
end

function wakeall!(scheduler::AbstractScheduler)
    for worker in scheduler.workers
        state = @atomic worker.state
        @record(:wakeall_check, worker_state = state, task = taskid(worker))
        while state == WorkerStates.PREPARE_WAITING
            state, ok = @atomicreplace(
                worker.state,
                WorkerStates.PREPARE_WAITING => WorkerStates.NOTIFYING
            )
            if ok
                state = WorkerStates.NOTIFYING
                @record(:wakeall_set_notifying, task = taskid(worker))
                break
            end
        end
        while state == WorkerStates.WAITING
            state, ok =
                @atomicreplace(worker.state, WorkerStates.WAITING => WorkerStates.NOTIFYING)
            if ok
                Base.schedule(worker.task)
                @record(:wakeall_scheduled, task = taskid(worker))
                state = WorkerStates.NOTIFYING
                break
            end
        end
    end
end

Schedulers.yield() = yieldto(scheduler_task(), current_task())::RescheduleRequest

function Schedulers.wait()
    @yield_unsafe begin
        @record(:wait_begin, waiter_state = thunkof(current_task()).state, {yield = false})
    end
    yieldto(scheduler_task(), WaitRequest())::RescheduleRequest
    @record(:wait_end, waiter_state = thunkof(current_task()).state)
    @DBG @check Threads.threadid() == Threads.threadid(workerof(current_task()))
    return
end

function maybe_current_task()
    task::Task = current_task()
    isdefined(task, :code) || return nothing  # root task does not set it
    task.code isa ConcreteThunk && return GenericTask(task)
    return nothing
end

function Schedulers.current_task()
    @return_if_something maybe_current_task()
    errorwith(; task = current_task()) do io, (; task)
        print(
            io,
            "Schedulers.current_task() is called from a task not scheduled with \
            Schedulers.spawn: ",
            task,
        )
    end
end

function Schedulers.current_scheduler()
    task = @something(maybe_current_task(), return nothing)
    return thunkof(task).scheduler
end

function _wait(task::GenericTask)
    thunk = thunkof(task)
    state = @atomic :monotonic thunk.state
    if state == TaskStates.DONE
        Threads.atomic_fence()
        return state
    elseif state == TaskStates.ERROR
        Threads.atomic_fence()
        return state
    end
    return nothing
end

function trywait(task::GenericTask)
    thunk = thunkof(task)
    @return_if_something _wait(task)

    # Register the `current_task()` as a waiter of `task`
    waiter = Waiter()
    @DBG @check waiter.task === current_task()
    @DBG @check waiter.state == WaiterStates.INITIAL
    head = @atomic :monotonic thunk.waiter
    while true
        waiter.next = head
        (head, ok) = @atomicreplace(thunk.waiter, head => waiter)
        ok && break
    end
    @record(:wait_register, node = objid(waiter))

    @return_if_something _wait(task) begin
        @check waiter.state in (WaiterStates.INITIAL, WaiterStates.DONTWAIT)
    end

    @record(:wait_cas)
    # If the CAS is successful, there should be no yield point until
    # `Schedulers.wait()` yields.
    @yield_unsafe begin
        (state, ok) =
            @atomicreplace(waiter.state, WaiterStates.INITIAL => WaiterStates.WAITING)
    end  # @yield_unsafe
    if ok
        Schedulers.wait()
        @check waiter.state == WaiterStates.NOTIFYING
    else
        @record(:wait_dontwait)
        @check state == WaiterStates.DONTWAIT
    end
    @return_if_something _wait(task)

    # Unreachable:
    errorwith(;
        task,
        task_state = stateof(task),
        waiter,
    ) do io, (; task, task_state, waiter)
        print(io, "FATAL: invalid state at the end of `wait(task)`")
        print(io, "\n  task = ", task)
        print(io, "\n  stateof(task) = ", task_state)
        print(io, "\n  waiter.task (current task) = ", waiter.task)
        print(io, "\n  waiter.state = ", waiter.state)
    end
    return
end

function Base.wait(task::GenericTask)
    @record(:wait_task_begin, task = taskid(task))
    state = trywait(task)
    @record(:wait_task_end, task = taskid(task), task_state = thunkof(task).state, state)
    if state == TaskStates.DONE
        @record(:wait_done, task = taskid(task))
        return
    elseif state == TaskStates.ERROR
        @record(:wait_error, task = taskid(task))
        # throw(thunk.result)
        Base.wait(task.task)  # use `TaskFailedException` for better stack trace

        # Unreachable:
        threadid = Threads.threadid()
        waiter = current_task()
        msg = "thread=$threadid: Unreachable: `wait` did not throw"
        @error msg waiter task
        errorwith(; threadid, waiter, task) do io, (; waiter, task)
            print(io, msg)
            print(io, "\n  waiter = ", waiter)
            print(io, "\n  task = ", task)
        end
    else
        error("unreachable: invalid state returned from `trywait`: ", state)
    end
end

function notifywaiters!(scheduler::AbstractScheduler, task::Task)
    task_state = @atomic :monotonic thunkof(task).state
    @record(:notify_begin, task = taskid(task), task_state)
    if !isfinished(task_state)
        errorwith(; scheduler, task, task_state) do io, (; task, task_state)
            print(io, "FATAL: `notifywaiters!` called on an unfinished task")
            print(io, "\n  task = ", task)
            print(io, "\n  stateof(task) = ", task_state)
        end
    end
    thunk = thunkof(task)
    waiter::Union{Waiter,Nothing} = @atomic thunk.waiter
    @atomic :monotonic thunk.waiter = nothing  # help GC
    while true
        waiter === nothing && break
        state = @atomic :monotonic waiter.state
        @record(
            :notify_task,
            task = taskid(task),
            waiter = taskid(waiter),
            node = objid(waiter)
        )
        while state == WaiterStates.INITIAL
            (state, ok) =
                @atomicreplace(waiter.state, WaiterStates.INITIAL => WaiterStates.DONTWAIT)
            if ok
                state = WaiterStates.DONTWAIT
                @record(:notify_dontwait, task = taskid(task), waiter = taskid(waiter))
                break
            end
        end
        while state == WaiterStates.WAITING
            (state, ok) =
                @atomicreplace(waiter.state, WaiterStates.WAITING => WaiterStates.NOTIFYING)
            if ok
                @record(:notify_waking, task = taskid(task), waiter = taskid(waiter))
                # TODO: wake the task with `WakeupRequest()`
                reschedule(taskof(waiter), scheduler)
                break
            end
        end
        waiter = waiter.next
    end
    waiter = thunk.waiter
    if waiter !== nothing
        errorwith(; scheduler, task, waiter) do io, (; task, waiter)
            print(io, "FATAL: a waiter is registered after the task is marked finished")
            print(io, "\n  task = ", task)
            print(io, "\n  stateof(task) = ", task_state)
            print(io, "\n  waiter.task = ", waiter.task)
        end
    end
    @record(:notify_end, task = taskid(task))
end

function Base.fetch(task::GenericTask)
    Base.wait(task)
    return thunkof(task).result
end
