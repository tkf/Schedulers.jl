mutable struct LockedMinHeap{Heap,GetPriority,Priority}
    @const heap::Heap
    @const getpriority::GetPriority
    @atomic priority::Priority
    @atomic locked::Bool
end

lockedheap(
    ::Type{Eltype},
    ::Type{Priority} = Eltype;
    by = identity,
) where {Eltype,Priority} = LockedMinHeap(
    MutableBinaryHeap{Eltype}(Base.Order.By(by), EMPTY_VECTOR),
    by,
    typemax(Priority),
    false,
)

Base.eltype(h::LockedMinHeap) = eltype(typeof(h))
Base.eltype(::Type{LockedMinHeap{Heap}}) where {Heap} = eltype(Heap)

prioritytype(x) = prioritytype(typeof(x))
prioritytype(T::Type) = error("not defined for type ", T)
prioritytype(::Type{<:LockedMinHeap{<:Any,<:Any,Priority}}) where {Priority} = Priority

function Base.trylock(h::LockedMinHeap)
    if @atomic :monotonic h.locked
        return false
    end
    old = @atomicswap h.locked = true
    return !old
end

function Base.unlock(h::LockedMinHeap)
    @atomic h.locked = false
    return
end

function Base.push!(h::LockedMinHeap, x)
    push!(h.heap, x)
    @atomic :monotonic h.priority = h.getpriority(first(h.heap))
    return h
end

function Base.pop!(h::LockedMinHeap)
    x = pop!(h.heap)
    if isempty(h.heap)
        p = typemax(prioritytype(h))
    else
        p = h.getpriority(first(h.heap))
    end
    @atomic :monotonic h.priority = p
    return x
end

struct MultiQueue{Heap<:LockedMinHeap}
    heaps::Vector{Heap}
end

Base.eltype(q::MultiQueue) = eltype(typeof(q))
Base.eltype(::Type{MultiQueue{Heap}}) where {Heap} = eltype(Heap)

prioritytype(::Type{MultiQueue{Heap}}) where {Heap} = prioritytype(Heap)

function Base.push!(multiq::MultiQueue, x)
    nspins = 0
    while true
        nspins += 1
        h = rand(multiq.heaps)
        if trylock(h)
            try
                push!(h, x)
                return h
            finally
                unlock(h)
            end
        end
        if nspins > 1000
            errorwith(; multiq = multiq, x = x) do io, (; multiq, x)
                print(io, "Failed to push an element `", x, "` to ")
                show(io, MIME"text/plain"(), multiq)
            end
        end
    end
end

struct Contention end
struct LikelyEmpty end

function trypop!(multiq::MultiQueue)
    nempties = 0
    while true
        h1 = rand(multiq.heaps)
        h2 = rand(multiq.heaps)
        p1 = @atomic :monotonic h1.priority
        p2 = @atomic :monotonic h2.priority
        if p2 < p1
            p1, p2 = p2, p1
            h1, h2 = h2, h1
        end
        if p1 == typemax(prioritytype(multiq))
            nempties += 1
            if nempties > length(multiq.heaps)
                break
            else
                continue
            end
        end
        if trylock(h1)
            try
                return Some{eltype(h1)}(pop!(h1))
            finally
                unlock(h1)
            end
        end
        # nempties = 0
    end

    lockfailed = false
    for h in multiq.heaps
        p = @atomic :monotonic h.priority
        if p == typemax(prioritytype(multiq))
            continue
        end
        if trylock(h)
            try
                return Some{eltype(h)}(pop!(h))
            finally
                unlock(h)
            end
            lockfailed = true
        end
    end
    if lockfailed
        return Contention()
    else
        return LikelyEmpty()
    end
end
