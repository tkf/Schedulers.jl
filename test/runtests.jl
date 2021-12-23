import Schedulers

let envbool(name) = lowercase(get(ENV, name, "false")) == "true"
    enable_full_debugging = envbool("SCHEDULERS_JL_ENABLE_FULL_DEBUGGING")
    enable_recording = enable_full_debugging || envbool("SCHEDULERS_JL_ENABLE_RECORDING")
    enable_logging = enable_full_debugging || envbool("SCHEDULERS_JL_ENABLE_LOGGING")
    enable_debugging = enable_full_debugging || envbool("SCHEDULERS_JL_ENABLE_DEBUGGING")
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
