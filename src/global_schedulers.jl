function (fn::GlobalSchedulerFunction)(thunk)
    promise = Channel{GenericTask}(1)
    function bg_waiter()  # aka bgw
        @record(:bgw_begin)
        try
            local task = Schedulers.spawn(thunk)
            trywait(task)
            @record(:bgw_done, task = taskid(task))
            @check isfinished(task)
            put!(promise, task)
        catch err
            @record(:bgw_error, exception = (err, catch_backtrace()))
            @error(
                "Unexpected error in background waiter",
                exception = (err, catch_backtrace())
            )
        finally
            close(promise)
        end
        @record(:bgw_end)
    end
    Schedulers.spawn(bg_waiter, schedulerof(fn))
    task = take!(promise)
    @check isfinished(task)
    return fetch(task)
end

const DEFAULT_WORKSTEALING_SCHEDULER_HANDLE =
    Ref{Union{WorkStealingScheduler,Nothing}}(nothing)
const DEFAULT_PRIORITIZED_SCHEDULER_HANDLE =
    Ref{Union{PrioritizedScheduler,Nothing}}(nothing)

schedulerof(::typeof(Schedulers.global_workstealing)) =
    DEFAULT_WORKSTEALING_SCHEDULER_HANDLE[]::WorkStealingScheduler
schedulerof(::typeof(Schedulers.global_prioritized)) =
    DEFAULT_PRIORITIZED_SCHEDULER_HANDLE[]::PrioritizedScheduler

close_if_something(x) = close(something(x))
close_if_something(::Nothing) = nothing

function init_global_schedulers()
    close_if_something(DEFAULT_WORKSTEALING_SCHEDULER_HANDLE[])
    close_if_something(DEFAULT_PRIORITIZED_SCHEDULER_HANDLE[])
    DEFAULT_WORKSTEALING_SCHEDULER_HANDLE[] = start(Schedulers.workstealing())
    DEFAULT_PRIORITIZED_SCHEDULER_HANDLE[] = start(Schedulers.prioritized())
    atexit() do
        close_if_something(DEFAULT_WORKSTEALING_SCHEDULER_HANDLE[])
        close_if_something(DEFAULT_PRIORITIZED_SCHEDULER_HANDLE[])
        DEFAULT_WORKSTEALING_SCHEDULER_HANDLE[] = nothing
        DEFAULT_PRIORITIZED_SCHEDULER_HANDLE[] = nothing
    end
end
