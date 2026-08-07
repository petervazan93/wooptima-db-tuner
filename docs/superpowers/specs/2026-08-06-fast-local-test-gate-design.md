# Fast Local Test Gate Design

Date: 2026-08-06
Status: approved

## Goal

Provide a useful local verification command that normally completes within 60
seconds while preserving the complete unit, integration, and release gates.

The fast gate reduces repeated feedback latency during TDD. It is not evidence
that the full release suite passes and cannot replace the full gate before a
task commit, review, merge, tag, or release.

## Current Bottlenecks

The complete unit directory currently contains 328 Bats tests. Several core
tests rebuild artifacts independently, and every Bats test executes its file's
setup in a fresh process.

Required integration is intentionally heavier. It builds production and
integration artifacts, builds and starts MariaDB 10.6 and 11.4 containers,
requires two stable health observations per service, and runs the complete
lifecycle sequentially for both families. Each lifecycle includes audit, six
collector ticks, analysis, localized reports/proposals, landmine rejection,
apply, container restart, health wait, and verification.

These complete gates provide valuable coverage but are too expensive for every
small red-green iteration.

## Selected Approach

Add a layered local gate:

```text
focused RED/GREEN test
        |
        v
make fast                 target: normally under 60 seconds
        |
        v
make test + integration  unchanged full evidence before commit/review
```

`make fast` runs:

1. existing source syntax, ShellCheck, and runtime-environment checks;
2. one normal production build;
3. an exact curated smoke selection covering every unit-test domain.

It does not start Docker, restart MariaDB, or claim full-suite coverage.

## Smoke Contract

The smoke suite contains exactly eight existing tests, one from each unit file:

| Domain | Exact test name |
| --- | --- |
| Core | `CLI help and version are always available` |
| Collection | `delta metrics use counter differences` |
| Audit | `loaded defaults catalog is the single exact landmine definition` |
| Rules | `audit effective variables exactly cover the rules proposal contract` |
| Report | `strict proposal grammar emits canonical records only after complete validation` |
| Lifecycle | `apply rejects an unknown live variable before writing` |
| Installer | `installer rejects an unsupported interface language before trust checks` |
| I18n | `runtime and POSIX installer catalogs are complete` |

The selection intentionally checks public dispatch, counter math, central
catalog ownership, audit/rule parity, strict proposal parsing, apply preflight,
installer fail-closed behavior, and catalog completeness. It is broad smoke
coverage, not a substitute for edge-case matrices.

## Runner Contract

Create `test/support/run-fast-tests.sh`.

The runner:

- requires `bats` instead of silently skipping;
- stores one anchored regular expression containing the eight exact names;
- asks Bats to count selected tests before running them;
- requires the count to equal exactly `8`;
- fails before execution when a test is renamed, removed, or duplicated;
- runs only the selected tests from `test/unit`;
- prints selected count and elapsed whole seconds.

The count guard prevents a stale filter from producing a misleading green fast
gate.

## Make Targets

Extend `Makefile` with:

```text
make fast         check + one production build + guarded smoke suite
make test-timing  one production build + full Bats suite with -T timing
```

Existing meanings remain unchanged:

```text
make test         complete unit suite
make integration  complete MariaDB 10.6 and 11.4 integration
```

`make check` validates and ShellChecks the new support script.

The 60-second objective is measured and reported, not enforced as a hard
timeout. A hard timeout would create false failures on slower hosts and hide the
actual slow component.

## Developer Workflow

During implementation:

1. run the smallest focused test and observe RED;
2. implement the minimal change and observe focused GREEN;
3. run `make fast` for cross-domain smoke feedback;
4. run the task's complete required unit/integration commands once before its
   commit and review.

Fix rounds repeat focused tests and `make fast`; they rerun the complete gate
when the fix changes behavior covered by that gate or before the reviewed task
is accepted.

## Error Behavior

- Missing `bats` makes `make fast` fail with a clear diagnostic.
- A selected count other than eight makes the runner fail without running a
  partial suite.
- A failing smoke test preserves the original Bats output and nonzero status.
- `make test-timing` remains diagnostic; it does not change test order or
  acceptance criteria.

## Testing

Regression coverage includes:

- runner rejects missing Bats;
- runner rejects selected count `7` and `9`;
- runner invokes Bats with the anchored filter and `test/unit` only after count
  `8`;
- `make fast` initially fails because the target does not exist, then passes;
- real fast run selects exactly eight tests and reports elapsed time;
- fast run normally completes below 60 seconds on the current development host;
- `make test` remains complete and unchanged;
- `make integration` remains complete and unchanged;
- syntax, ShellCheck, and `git diff --check` pass.

## Expected Result

Routine TDD gains a deterministic under-one-minute feedback path without
weakening any merge or release evidence. Timing data remains available for a
later, separately designed parallelization or Docker-reuse optimization if the
full gate is still too slow.
