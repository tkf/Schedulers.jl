include config.mk

JULIA ?= julia
JULIA_CMD ?= $(JULIA) --color=yes --startup-file=no
JULIA_REPL_CMD ?= $(JULIA)

export TEST_FUNCTION_RUNNER_JL_TIMEOUT ?= 30

export JULIA_LOAD_PATH = @:$(shell pwd):$(shell pwd)/test/SchedulersTests
export JULIA_PROJECT = $(shell pwd)/test

.PHONY: all test test-* instantiate

all: test-all

test: test-nthreads-2

test-all: 
	$(MAKE) test-all-nthreads
	SCHEDULERS_JL_ENABLE_FULL_DEBUGGING=true $(MAKE) test-all-nthreads
	SCHEDULERS_JL_ENABLE_RECORDING=true $(MAKE) test-all-nthreads
	SCHEDULERS_JL_ENABLE_LOGGING=true $(MAKE) test-all-nthreads
	SCHEDULERS_JL_ENABLE_DEBUGGING=true $(MAKE) test-all-nthreads

test-all-nthreads: \
test-nthreads-1 \
test-nthreads-2 \
test-nthreads-$(shell scripts/nthreads.sh)

test-nthreads-%:
	@env | grep TEST_FUNCTION_RUNNER_JL
	JULIA_NUM_THREADS=$* $(JULIA) test/runtests.jl

instantiate: test/Manifest.toml Manifest.toml

test/Manifest.toml: test/Project.toml
	JULIA_LOAD_PATH=@:@stdlib JULIA_PROJECT=test $(JULIA_CMD) \
		-e 'using Pkg' \
		-e 'Pkg.resolve()'

Manifest.toml: Project.toml
	JULIA_LOAD_PATH=@:@stdlib JULIA_PROJECT=. $(JULIA_CMD) \
		-e 'using Pkg' \
		-e 'Pkg.resolve()'

repl:
	JULIA_LOAD_PATH=$(JULIA_LOAD_PATH): \
	TEST_FUNCTION_RUNNER_JL_TIMEOUT=3.14e7 \
		$(JULIA_REPL_CMD)

config.mk:
	touch $@
#	ln -s default-config.mk $@
