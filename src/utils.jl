macro _const(ex)
    ex = esc(ex)
    if VERSION < v"1.8.0-DEV.1148"
        return ex
    else
        return Expr(:const, ex)
    end
end

const var"@const" = var"@_const"

@def_singleton TRUE
@def_singleton FALSE
const BOOL = Union{typeof(TRUE),typeof(FALSE)}
const AnyBool = Union{BOOL,Bool}

boolean(b::Bool) = b
boolean(::typeof(TRUE)) = true
boolean(::typeof(FALSE)) = false

macro return_if_something(ex, before_return = nothing)
    quote
        ans = $(esc(ex))
        if ans === nothing
        else
            $(esc(before_return))
            return something(ans)
        end
    end
end

function duplicated_items_in_sorted_iterable(xs)
    dups = nothing
    y = iterate(xs)
    y === nothing && return dups
    prev, state = y
    while true
        y = iterate(xs, state)
        y === nothing && return dups
        curr, state = y
        if isless(prev, curr)
            prev = curr
        elseif isless(curr, prev)
            error("Input is not sorted")
        else
            dups = @something(dups, eltype(xs)[])
            push!(dups, curr)
        end
    end
end

Historic.@define Debug
using .Debug: @record

"""
    @yield_unsafe expression

Document that `expression` must not yield to the Julia scheduler.

This macro is used purely for documentation.  The `expression` is evaluated
as-is.
"""
macro yield_unsafe(ex)
    esc(ex)
end

function contextualized_buffer(io::IO)
    buffer = IOBuffer()
    ctx = IOContext(buffer, io)
    ctx = IOContext(ctx, :displaysize => displaysize(io))
    return (ctx, buffer)
end

""" `printing(f, io::IO)` is same as `f(io)` but tries to print it in "one shot" """
function printing(f, io::IO)
    (ctx, buffer) = contextualized_buffer(io)
    y = f(ctx)
    seekstart(buffer)
    write(io, take!(buffer))
    return y
end

struct LazyException <: Exception
    f::Any
    data::NamedTuple
end

function Base.showerror(io::IO, e::LazyException)
    printing(io) do io
        e.f(io, e.data)
    end
end

errorwith(f; data...) = throw(LazyException(f, values(data)))

donothing(_args...; _kwargs...) = nothing

function waitall(waitables; onerror = donothing, logerror = nothing)
    exception = nothing
    for w in waitables
        try
            Base.wait(w)
        catch err
            if logerror !== nothing
                @error "$logerror" exception = (err, catch_backtrace())
            end
            exception = @something(exception, CompositeException())
            push!(exception, err)
            onerror(w, err)
        end
    end
    exception === nothing || throw(exception)
end

function pause()
    ccall(:jl_cpu_pause, Cvoid, ())
    GC.safepoint()
end

const EMPTY_VECTOR = Union{}[]

struct DontCallMe end
const wait = DontCallMe()
const schedule = DontCallMe()
# const yield = DontCallMe()
