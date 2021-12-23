set_threadid(task::Task, i) = set_raw_tid(task, i - 1)
unset_threadid(task::Task) = set_raw_tid(task, -1)

function set_raw_tid(task::Task, raw_tid)
    raw_tid = convert(Int16, raw_tid)
    ptr = Ptr{Int16}(pointer_from_objref(task)) + TASK_TID_OFFSET
    GC.@preserve task begin
        return unsafe_store!(ptr, raw_tid)
    end
end

function check_set_raw_tid()
    task = Task(nothing)
    for raw_tid in Int16(0):Int16(20)
        set_raw_tid(task, raw_tid)
        actual = Threads.threadid(task) - 1
        if raw_tid != actual
            error("expected tid ($raw_tid) does not match with the actual tid ($actual)")
        end
    end
end
