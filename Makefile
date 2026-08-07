.PHONY: all build check fast test test-timing integration clean

all: build

build:
	./build.sh

check:
	bash -n lib/*.sh build.sh test/integration/run.sh test/support/check-runtime-environment.sh test/support/run-fast-tests.sh
	sh -n install.sh
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -s bash lib/*.sh build.sh test/integration/run.sh test/support/check-runtime-environment.sh test/support/run-fast-tests.sh && shellcheck -s sh install.sh; else printf '%s\n' 'check: shellcheck is not available, skipping'; fi
	./test/support/check-runtime-environment.sh

fast: check build
	./test/support/run-fast-tests.sh

test: build
	@if command -v bats >/dev/null 2>&1; then bats test/unit; else printf '%s\n' 'test: SKIP (bats is not available)'; fi

test-timing: build
	@command -v bats >/dev/null 2>&1 || { printf '%s\n' 'test-timing: FAIL (bats is not available)'; exit 69; }
	bats -T test/unit

integration: build
	./build.sh --profile integration-test
	bash test/integration/run.sh

clean:
	rm -rf dist
