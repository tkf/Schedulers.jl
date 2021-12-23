function guess_tid_offset()
    task = Task(nothing)
    l = nfields(task)
    ptr0 = UInt(pointer_from_objref(task))
    ptr1 = ptr0 + fieldoffset(Task, l) + sizeof(fieldtype(Task, l))
    imask = UInt(sizeof(Int16) - 1)
    ptr1 += imask
    ptr1 &= ~imask

    tid = rand(Int16(1):typemax(Int16))
    ans = ccall(:jl_set_task_tid, Cint, (Any, Cint), task, tid)
    @assert ans != 0
    @assert Threads.threadid(task) == tid + 1
    GC.@preserve task begin
        loaded = unsafe_load(Ptr{Int16}(ptr1))
        loaded == tid && return Int(ptr1 - ptr0)
    end
    error("failed to guess threadid offset")
end

if abspath(PROGRAM_FILE) == @__FILE__
    const TASK_TID_OFFSET = guess_tid_offset()
    include("taskhack_impl.jl")
    check_set_raw_tid()
    println(TASK_TID_OFFSET)
end
