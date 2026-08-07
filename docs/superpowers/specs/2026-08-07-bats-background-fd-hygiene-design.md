# Bats Background FD Hygiene Design

## Problem

GitHub Actions `quality` prints all 336 successful Bats results but does not
return from `make test`. Cancelled job cleanup shows the `make`/Bats process

The complete suite exits normally on macOS and in an Ubuntu 24.04 container.
The GitHub log and the Bats background-task documentation identify the
environment-sensitive difference: a background process spawned by a Bats test
can inherit formatter pipe file descriptors. A surviving descendant keeps the
pipe open after every test body has passed, so the formatter waits indefinitely.

The suite has four explicit background launches:

- `cmd_tick` and `cmd_collect stop` in `test/unit/collect.bats`.
- `dbtune_dispatch apply` and `dbtune_dispatch propose` in
  `test/unit/lifecycle.bats`.

## Scope

Add test-only file-descriptor hygiene to all four background launch sites.
Do not change production code, `Makefile`, CI workflow structure, test
selection, or application behavior.

## Design

Create `test/support/bats-fd-hygiene.bash` with one function:

```bash
dbtune_test_close_non_std_fds
```

The function enumerates the calling process's open descriptors through
`/proc/$BASHPID/fd` on Linux or `lsof` on macOS, then closes the open numeric
descriptors from 3 through 254. Enumerating first avoids running Bats' DEBUG
trap hundreds of times for descriptors that were never open. Descriptors 0, 1,
and 2 remain available for normal command input and captured test output.
Descriptor 255 is excluded because Bash may reserve it for script input.

Each affected test sources the helper and wraps its background command in a
subshell:

```bash
(
    dbtune_test_close_non_std_fds
    command_under_test
) >"$output_file" 2>&1 &
pid=$!
```

Marker polling allows up to 10 seconds for the added descriptor discovery and
command startup on GitHub-hosted runners, while still breaking immediately on
success. The marker assertion remains mandatory after the polling loop.

The test continues to wait for the subshell PID and assert its existing
behavior. Closing inherited Bats descriptors changes only formatter-pipe
ownership; it does not detach the process, hide its exit status, or weaken
concurrency assertions.

## Error Handling

Descriptor discovery fails explicitly when neither Linux procfs nor `lsof` is
available. The helper runs only inside new background subshells, so it cannot
close descriptors used by the parent test process. Existing `wait`, `kill -0`,
lock, output-file, and state assertions remain authoritative.

## Testing

Use the hanging PR #49 `quality` attempts as RED evidence: both print all 336
successful tests and fail to terminate.

Add a focused helper contract test that opens a non-standard descriptor,
invokes the helper in a subshell, and proves that descriptor is unavailable
while standard output still works. Run the two existing concurrency tests,
the complete local unit suite, and required integration. The two concurrency
tests retain hard marker assertions after their bounded startup polling.

Push the fix to PR #49. GREEN requires both GitHub `quality` and `integration`
jobs to complete successfully without cancellation or retry. In particular,
`quality` must transition to post-job cleanup immediately after the final TAP
record instead of leaving a live Bats/make process tree.

## Non-Goals

- Splitting the complete unit suite into per-file CI invocations.
- Adding a timeout that converts the leak into a delayed failure.
- Changing production process management.
- Identifying one specific surviving grandchild when closing inherited Bats
  descriptors removes the entire documented failure class.
