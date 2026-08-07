# Bats Background FD Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the complete Bats suite terminate reliably on GitHub Actions after all tests pass by preventing background test jobs from inheriting formatter-pipe descriptors.

**Architecture:** A test-only support helper enumerates and closes open non-standard descriptors inside each background subshell before the command under test starts. The four existing background launch sites retain their PID, output, lock, and exit-status assertions; production code, `make test`, and CI test selection remain unchanged.

**Tech Stack:** Bash 4+, Bats 1.10+, GNU/Linux GitHub Actions, macOS local test environment.

## Global Constraints

- Modify test code only; do not change production libraries, `Makefile`, or workflow structure.
- Preserve descriptors 0, 1, and 2, exclude Bash-reserved descriptor 255, and avoid probing closed descriptors individually under Bats' DEBUG trap.
- Apply the helper to all four explicit background launches in the unit suite.
- Preserve existing `wait`, `kill -0`, marker, lock, output-file, and state assertions; marker polling may allow up to 10 seconds for CI startup and must break immediately on success.
- Keep `make test` as one complete `bats test/unit` invocation.
- The two hanging PR #49 quality attempts are RED evidence; GREEN requires a fresh quality job to exit normally without cancellation or retry.
- Do not weaken, skip, split, or time-limit the complete unit gate.
- Do not manually edit or commit generated files under `dist/`.
- Keep all code comments in English.

---

### Task 1: Close Inherited Bats Descriptors in Background Jobs

**Files:**
- Create: `test/support/bats-fd-hygiene.bash`
- Modify: `test/unit/core.bats:3-15,115`
- Modify: `test/unit/collect.bats:608-640`
- Modify: `test/unit/lifecycle.bats:1963-1993`
- Test: `test/unit/core.bats`
- Test: `test/unit/collect.bats`
- Test: `test/unit/lifecycle.bats`
- Test: PR #49 `quality` and `integration` jobs

**Interfaces:**
- Produces: `dbtune_test_close_non_std_fds`, callable only from a background test subshell.
- Preserves: the existing background command PID as `$!` and its exit status through `wait`.
- Preserves: the complete local and CI unit/integration gate semantics.

- [ ] **Step 1: Add the failing helper contract test**

Add this focused test to `test/unit/core.bats` before the state-directory tests:

```bash
@test "background FD helper closes inherited descriptors and preserves standard output" {
    local inherited_fd helper_status=0
    local output_file="$BATS_TEST_TMPDIR/fd-helper.out"

    source "$PROJECT_ROOT/test/support/bats-fd-hygiene.bash"
    exec {inherited_fd}>"$BATS_TEST_TMPDIR/inherited-fd"
    (
        dbtune_test_close_non_std_fds
        if printf 'leak\n' 2>/dev/null >&"$inherited_fd"; then
            exit 1
        fi
        printf 'standard-output\n'
    ) >"$output_file" || helper_status=$?
    exec {inherited_fd}>&-

    [ "$helper_status" -eq 0 ]
    [ "$(cat "$output_file")" = standard-output ]
    [ ! -s "$BATS_TEST_TMPDIR/inherited-fd" ]
}
```

This test catches a missing helper, failure to close an inherited numeric FD,
or accidental closure of standard output.

- [ ] **Step 2: Run the helper test and verify RED**

Run:

```bash
bats --filter 'background FD helper' test/unit/core.bats
```

Expected: FAIL because `test/support/bats-fd-hygiene.bash` does not exist.

- [ ] **Step 3: Implement the minimal test-support helper**

Create `test/support/bats-fd-hygiene.bash`. Follow Bats' documented
`close_non_std_fds` approach: enumerate the calling shell's open descriptors
through `/proc/$BASHPID/fd` on Linux or `lsof` on macOS, retain only numeric
descriptors 3 through 254, and close that finite list. The implementation flow
is:

```bash
pid=$BASHPID
if [[ -d /proc/$pid/fd ]]; then
    # Record the calling shell's Linux descriptors.
elif command -v lsof >/dev/null 2>&1; then
    # Record the calling shell's macOS descriptors.
else
    return 69
fi
for fd in "${open_fds[@]}"; do
    eval "exec ${fd}>&-"
done
```

The helper contains function definitions only and has mode `0644`. It must not
run one close command for every possible descriptor because each command
invokes Bats' DEBUG trap and can exhaust the concurrency tests' startup window
on GitHub-hosted runners.

- [ ] **Step 4: Run the helper test and verify GREEN**

Run:

```bash
bats --filter 'background FD helper' test/unit/core.bats
```

Expected: `1/1` passes with no warning or extra output.

- [ ] **Step 5: Apply the helper to every background launch**

Source the helper from `setup()` in both `test/unit/collect.bats` and
`test/unit/lifecycle.bats`:

```bash
source "$BATS_TEST_DIRNAME/../support/bats-fd-hygiene.bash"
```

Replace each direct background launch with a subshell. Preserve the current
redirections and PID assignments exactly:

```bash
(
    dbtune_test_close_non_std_fds
    cmd_tick
) >"$BATS_TEST_TMPDIR/tick.out" &
tick_pid=$!

(
    dbtune_test_close_non_std_fds
    cmd_collect stop
) >"$BATS_TEST_TMPDIR/stop.out" &
stop_pid=$!

(
    dbtune_test_close_non_std_fds
    dbtune_dispatch apply
) >"$BATS_TEST_TMPDIR/apply.out" 2>&1 &
apply_pid=$!

(
    dbtune_test_close_non_std_fds
    dbtune_dispatch propose
) >"$BATS_TEST_TMPDIR/propose.out" 2>&1 &
propose_pid=$!
```

Keep the existing `kill -0`, release-file, `wait`, state, and snapshot
assertions around these launches. Extend only the marker polling loops from
approximately 2 seconds to 10 seconds; each loop must still break immediately
when its marker appears and retain the mandatory marker assertion afterward.

- [ ] **Step 6: Run the focused concurrency and helper tests**

Run:

```bash
bats --filter 'background FD helper|stop disables activations and waits for an active tick lock|paused apply deploys its verified snapshot' \
  test/unit/core.bats test/unit/collect.bats test/unit/lifecycle.bats
```

Expected: `3/3` passes and the Bats process exits immediately.

- [ ] **Step 7: Run the complete local verification gate**

Run:

```bash
make build
make check
make test
DBTUNE_REQUIRE_INTEGRATION=1 DBTUNE_UI_LANG=en make integration
git diff --check
git status --short
```

Expected: every command exits 0, all current unit tests pass, both MariaDB
integration versions pass, and status contains only the intended tracked
test/support changes before commit.

- [ ] **Step 8: Commit the FD hygiene fix**

```bash
git add test/support/bats-fd-hygiene.bash test/unit/core.bats \
  test/unit/collect.bats test/unit/lifecycle.bats
git commit -m "test: close inherited FDs in background jobs"
```

- [ ] **Step 9: Push and verify PR #49 CI**

Cancel the currently superseded hanging PR #49 attempt if it is still active,
push the new commit, and run:

```bash
gh pr checks 49 --watch --interval 15
```

Expected:

```text
quality     pass
integration pass
```

Inspect the completed `quality` log. The job must enter checkout post-cleanup
immediately after the final TAP record, without manual cancellation, timeout,
or retry.
