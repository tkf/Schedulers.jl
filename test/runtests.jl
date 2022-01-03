import Schedulers

let flags = map(lowercase ∘ strip, split(get(ENV, "SCHEDULERS_JL_TEST_ENABLE", ""), ","))
    enable_full_debugging = "full" in flags
    enable_recording = enable_full_debugging || "recording" in flags
    enable_logging = enable_full_debugging || "logging" in flags
    enable_debugging = enable_full_debugging || "debugging" in flags
    if enable_recording
        @info "Enable recording"
        Schedulers.Internal.Debug.enable()
    end
    if enable_logging
        @info "Enable logging"
        Schedulers.Internal.Debug.enable_logging()
    end
    if enable_debugging
        @info "Enable debugging"
        Schedulers.Internal.enable_debug()
    end
end

using TestFunctionRunner
TestFunctionRunner.@run
