module Utils

import Schedulers
using ArgCheck: @argcheck

function fetch_finished(t::Union{Task,Schedulers.Task})
    @argcheck istaskdone(t)
    return fetch(t)
end

end  # module
