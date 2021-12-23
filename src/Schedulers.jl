baremodule Schedulers

baremodule _Prelude
abstract type SchedulerContextFunction <: Function end
using DefineSingletons: @def_singleton
end

# Schedulers
_Prelude.@def_singleton workstealing isa _Prelude.SchedulerContextFunction
_Prelude.@def_singleton prioritized isa _Prelude.SchedulerContextFunction
function open end

# High-level API
function spawn end
function yield end

function setpriority end

# Low-level API
function wait end
function schedule end
function current_task end
function current_scheduler end

module Internal

using ..Schedulers: Schedulers
using .._Prelude: SchedulerContextFunction

using ArgCheck: @argcheck, @check
using ConcurrentCollections: ConcurrentQueue, WorkStealingDeque, maybepop!, maybepopfirst!
using DataStructures: MutableBinaryHeap
using DefineSingletons: @def_singleton
using Historic: Historic, taskid, objid

include("utils.jl")
include("debug.jl")
include("multiqueue.jl")
include("taskhack.jl")

include("core.jl")
include("workstealing_scheduler.jl")
include("prioritized_scheduler.jl")
# include("fifo_scheduler.jl")
include("runtime.jl")
include("show.jl")

end  # module Internal

const Task = Internal.GenericTask

end  # baremodule Schedulers
