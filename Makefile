.PHONY: all build check test integration clean

all: build

build:
	./build.sh

check:
	bash -n lib/*.sh build.sh test/integration/run.sh
	sh -n install.sh
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -s bash lib/*.sh build.sh test/integration/run.sh && shellcheck -s sh install.sh; else printf '%s\n' 'check: shellcheck is not available, skipping'; fi

test: build
	@if command -v bats >/dev/null 2>&1; then bats test/unit; else printf '%s\n' 'test: SKIP (bats is not available)'; fi

integration: build
	bash test/integration/run.sh

clean:
	rm -rf dist
