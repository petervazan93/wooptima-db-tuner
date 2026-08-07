# Fast Local Test Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guarded eight-test local smoke gate that normally completes within 60 seconds while leaving complete unit and integration gates unchanged.

**Architecture:** A dedicated support script owns one anchored exact-name Bats filter, validates that it still selects exactly eight tests, and reports elapsed time. `Makefile` exposes `fast` and `test-timing`; current `test` and `integration` recipes retain their existing semantics. Core Bats tests exercise the runner with a fake Bats executable before the real smoke and full timing runs verify end-to-end behavior.

**Tech Stack:** Bash 4+, GNU/BSD Make, Bats 1.14+, ShellCheck, Markdown.

## Global Constraints

- `make fast` must run existing `check`, one production `build`, and exactly eight smoke tests.
- The smoke filter must be anchored and contain the eight exact names approved in the design.
- The runner must fail before its execution pass when selected count is not exactly `8`.
- Missing Bats must fail fast; it must not report a skipped green gate.
- `make test` and `make integration` behavior must remain unchanged.
- The 60-second objective is reported, not enforced as a timeout.
- Do not add Docker startup or MariaDB lifecycle work to `make fast`.
- Do not manually edit or commit generated files under `dist/`.
- Write regression tests first and verify their intended RED before implementation.
- Keep all code comments in English.

---

### Task 1: Add the Guarded Fast Gate and Timing Target

**Files:**
- Create: `test/support/run-fast-tests.sh`
- Modify: `test/unit/core.bats`
- Modify: `Makefile:1-22`
- Modify: `README.md:211-220`
- Test: `test/unit/core.bats`
- Test: real `make fast`
- Test: real `make test-timing`

**Interfaces:**
- Produces: `test/support/run-fast-tests.sh`, accepting optional `BATS_BIN` and no positional arguments.
- Produces: `make fast`.
- Produces: `make test-timing`.
- Preserves: existing `make test` and `make integration` recipes byte-for-byte.

- [ ] **Step 1: Add failing runner contract tests**

Add these tests to `test/unit/core.bats`. The fake Bats executable logs every argument, prints `STUB_FAST_COUNT` for the count pass, and succeeds for execution.

```bash
make_fast_bats_stub() {
    local stub="$BATS_TEST_TMPDIR/bats-fast-stub"

    cat >"$stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_FAST_LOG"
if [[ $1 == --count ]]; then
    printf '%s\n' "${STUB_FAST_COUNT:-8}"
    exit 0
fi
printf '%s\n' '1..8'
exit 0
STUB
    chmod +x "$stub"
    printf '%s\n' "$stub"
}

@test "fast test runner rejects a missing Bats executable" {
    run env BATS_BIN="$BATS_TEST_TMPDIR/missing-bats" \
        "$PROJECT_ROOT/test/support/run-fast-tests.sh"

    [ "$status" -eq 69 ]
    [[ $output == *'Bats is required'* ]]
}

@test "fast test runner rejects stale selected counts before execution" {
    local stub count
    stub=$(make_fast_bats_stub)
    export STUB_FAST_LOG="$BATS_TEST_TMPDIR/fast.log"

    for count in 7 9; do
        : >"$STUB_FAST_LOG"
        run env BATS_BIN="$stub" STUB_FAST_COUNT="$count" \
            "$PROJECT_ROOT/test/support/run-fast-tests.sh"
        [ "$status" -eq 65 ]
        [[ $output == *"selected $count tests; expected 8"* ]]
        [ "$(wc -l <"$STUB_FAST_LOG" | tr -d ' ')" -eq 1 ]
    done
}

@test "fast test runner executes the exact guarded smoke filter" {
    local stub
    stub=$(make_fast_bats_stub)
    export STUB_FAST_LOG="$BATS_TEST_TMPDIR/fast.log"

    run env BATS_BIN="$stub" STUB_FAST_COUNT=8 \
        "$PROJECT_ROOT/test/support/run-fast-tests.sh"

    [ "$status" -eq 0 ]
    [ "$(wc -l <"$STUB_FAST_LOG" | tr -d ' ')" -eq 2 ]
    grep -F -- '--count --filter ^(' "$STUB_FAST_LOG"
    grep -F -- 'CLI help and version are always available' "$STUB_FAST_LOG"
    grep -F -- 'runtime and POSIX installer catalogs are complete' "$STUB_FAST_LOG"
    grep -F -- "$PROJECT_ROOT/test/unit" "$STUB_FAST_LOG"
}
```

- [ ] **Step 2: Verify the runner tests are RED**

Run:

```bash
bats --filter 'fast test runner' test/unit/core.bats
```

Expected: FAIL because `test/support/run-fast-tests.sh` does not exist.

- [ ] **Step 3: Verify the Make targets are RED**

Run:

```bash
make fast
make test-timing
```

Expected: both commands fail with `No rule to make target`.

- [ ] **Step 4: Implement the guarded runner**

Create executable `test/support/run-fast-tests.sh` with this implementation:

```bash
#!/usr/bin/env bash

set -u

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 1
bats_bin=${BATS_BIN:-bats}
expected_count=8
filter='^(CLI help and version are always available|delta metrics use counter differences|loaded defaults catalog is the single exact landmine definition|audit effective variables exactly cover the rules proposal contract|strict proposal grammar emits canonical records only after complete validation|apply rejects an unknown live variable before writing|installer rejects an unsupported interface language before trust checks|runtime and POSIX installer catalogs are complete)$'

if ! command -v "$bats_bin" >/dev/null 2>&1; then
    printf '%s\n' 'fast tests: Bats is required' >&2
    exit 69
fi

selected=$(
    "$bats_bin" --count --filter "$filter" "$project_root/test/unit"
) || exit $?
if [[ $selected != "$expected_count" ]]; then
    printf 'fast tests: selected %s tests; expected %s\n' \
        "$selected" "$expected_count" >&2
    exit 65
fi

started=$SECONDS
printf 'fast tests: running %s guarded smoke tests\n' "$selected"
"$bats_bin" --filter "$filter" "$project_root/test/unit"
result=$?
printf 'fast tests: completed in %ss\n' "$((SECONDS - started))"
exit "$result"
```

Set mode `0755`.

- [ ] **Step 5: Verify runner tests are GREEN**

```bash
bats --filter 'fast test runner' test/unit/core.bats
```

Expected: 3 tests pass.

- [ ] **Step 6: Add Make targets without changing full gates**

Update `.PHONY`, include the new script in `bash -n` and Bash ShellCheck input,
and add:

```make
fast: check build
	./test/support/run-fast-tests.sh

test-timing: build
	@command -v bats >/dev/null 2>&1 || { printf '%s\n' 'test-timing: FAIL (bats is not available)'; exit 69; }
	bats -T test/unit
```

Leave the current `test:` and `integration:` recipes unchanged.

- [ ] **Step 7: Document the layered workflow**

Change the README development block to:

```bash
make fast
make build
make check
make test
make test-timing
make integration
```

State that `make fast` is an eight-test local smoke gate, `make test-timing`
runs the complete timed unit suite, and full unit/integration gates remain
required before review and release.

- [ ] **Step 8: Run the real fast gate and measure it**

```bash
/usr/bin/time -p make fast
```

Expected: exit 0, exactly 8 selected tests, and normally `real` below 60 seconds.
If it exceeds 60 seconds, preserve the passing result but report the measured
time as a concern instead of weakening the smoke contract.

- [ ] **Step 9: Run the complete timed unit gate**

```bash
make test-timing
```

Expected: all 328 current unit tests pass with per-test timing output.

- [ ] **Step 10: Verify integration semantics are unchanged**

```bash
git diff -- Makefile
git diff --check
```

Confirm the existing `integration: build`, integration-profile build, and
`test/integration/run.sh` invocation lines are unchanged.

- [ ] **Step 11: Commit the fast gate**

```bash
git add Makefile README.md test/support/run-fast-tests.sh test/unit/core.bats
git commit -m "test: add fast local verification gate"
```
