# P1 Fail-Closed Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent incomplete, malformed, stale, degraded, or test-controlled input from becoming a production MariaDB configuration change while preserving rollback and recovery.

**Architecture:** Production and test artifacts use immutable build profiles. Shared strict parsers and exact evidence validators stop unsafe data at its source, while apply binds one validated proposal snapshot to history and publication and performs a fresh loaded-defaults scan before durable mutation. Rollback and recovery remain independent of forward safety checks.

**Tech Stack:** Bash 4+, POSIX shell installer, AWK, Bats, ShellCheck, Python 3 isolated mode, Docker Compose, MariaDB 10.6 and 11.4, GitHub Actions.

## Global Constraints

- Begin from merge commit `3d3bcdf` or a descendant containing the completed P0 privileged-boundary work.
- Preserve the public CLI, English/Slovak interface selector, `fleet-v3` report contract, normal RunCloud manual-restart workflow, and existing rollback history.
- `--force` may bypass only measurement and provenance requirements and the local time window.
- `--force` may not bypass proposal grammar, live-variable validation, loaded-default checks, backup, target, topology, Galera, mydumper, daemon validation, rollback, or recovery guards.
- Unknown, absent, malformed, reset, inconsistent, or stale evidence must never be converted to zero or safe evidence.
- The exact proposal bytes validated must be the bytes recorded and published.
- Forward safety checks must never block rollback or crash recovery.
- Production artifacts must ignore test-only command, fault, clock, ownership, path, and sample-threshold overrides.
- The shipped v0.4.1 20-column sample format requires a new audit and collection cycle; do not silently migrate it.
- Existing 17-column samples remain read-only analyzable with query-cache evidence unavailable; do not append or migrate them.
- Existing history schemas remain rollbackable; stricter fields apply only to newly created history.
- Do not manually edit or commit generated files under `dist/`.
- Write every regression test first and verify its intended red-green transition.
- Keep all code comments in English.
- Do not modify historical specifications or older dated plans.

---

### Task 1: Isolate Production Runtime and Artifact Profiles

**Files:**
- Modify: `lib/00-header.sh:1-14`
- Modify: `lib/10-util.sh`
- Modify: `lib/30-collect.sh:130-155`
- Modify: `lib/60-lifecycle.sh:785-900`
- Modify: `lib/90-main.sh:109-117`
- Modify: `build.sh`
- Modify: `Makefile`
- Modify: `install.sh`
- Modify: `test/integration/docker-compose.yml`
- Modify: `test/integration/run.sh`
- Create: `test/support/check-runtime-environment.sh`
- Modify: `.github/workflows/release.yml`
- Test: `test/unit/core.bats`
- Test: `test/unit/collect.bats`
- Test: `test/unit/install.bats`
- Test: `test/unit/lifecycle.bats`

**Interfaces:**
- Produces: readonly `DBTUNE_ARTIFACT_PROFILE=source-test|production|integration-test` embedded at build time.
- Produces: `dbtune_runtime_environment_contract()`, printing `name<TAB>immutable|operator|test-only|internal` records.
- Produces: `dbtune_runtime_prepare_environment()` returning 0 only after production sanitization succeeds.
- Produces: `dbtune_runtime_command_path NAME`, printing an absolute external executable path or returning 69.
- Produces: `dist/dbtune`, `dist/dbtune.sha256`, and test-only `dist/dbtune-integration`.
- Consumes: documented operator inputs `DBTUNE_UI_LANG`, `DBTUNE_STATE_DIR`, `DBTUNE_CONFIG_TARGET`, `DBTUNE_CONFIG_ALLOWED_DIR`, `DBTUNE_ROOT_CNF`, `DBTUNE_LOG_LEVEL`, and `DBTUNE_MAX_BACKUP_AGE_SECONDS`.

- [ ] **Step 1: Add build-profile argument and atomicity tests**

Add table-driven tests to `test/unit/core.bats` that preserve hashes of existing artifacts and run:

```bash
run ./build.sh --profile
[ "$status" -ne 0 ]

run ./build.sh --profile unknown
[ "$status" -ne 0 ]

run ./build.sh --profile production extra
[ "$status" -ne 0 ]

run ./build.sh --profile production --profile integration-test
[ "$status" -ne 0 ]
```

Assert every invalid invocation leaves the prior `dist/dbtune` and checksum unchanged. Add successful assertions that the default and `--profile production` contain exactly one readonly production marker, while `--profile integration-test` writes only `dist/dbtune-integration` and does not change production hashes.

- [ ] **Step 2: Add hostile production-environment tests**

Build production and run it with marker-producing stubs through every test-only category:

```bash
run env \
    DBTUNE_FLOCK="$BATS_TEST_TMPDIR/marker-command" \
    DBTUNE_SYSTEMCTL="$BATS_TEST_TMPDIR/marker-command" \
    DBTUNE_SQL_AUTH_METHOD=defaults \
    DBTUNE_SQL_DEFAULTS_FILE="$BATS_TEST_TMPDIR/attacker.cnf" \
    DBTUNE_PUBLISH_FAULT_HOOK="$BATS_TEST_TMPDIR/marker-command" \
    DBTUNE_NOW_EPOCH=1 \
    DBTUNE_MIN_APPLY_SAMPLES=0 \
    DBTUNE_OVERRIDE_MARKER="$marker" \
    "$PROJECT_ROOT/dist/dbtune" status

[ ! -e "$marker" ]
```

Add focused tests for hostile `PYTHONPATH`, exported command functions, `DBTUNE_PROGRAM_PATH`, inherited profile overrides, readonly bad profile while sourcing, readonly `PATH`, and `bash dist/dbtune version`. Assert a production artifact sourced through `source dist/dbtune` returns 65 and does not define `cmd_apply`.

Add `test/support/check-runtime-environment.sh`. It extracts every `DBTUNE_[A-Z0-9_]+` symbol referenced by production files under `lib/` and requires exactly one classification from `dbtune_runtime_environment_contract`: `immutable`, `operator`, `test-only`, or `internal`. Duplicate and unclassified symbols fail with their names. Add this checker to `make check` so a new runtime variable cannot bypass review.

- [ ] **Step 3: Run profile tests and verify RED**

Run:

```bash
make build
bats --filter 'build profile|production artifact|environment cannot switch|production artifact cannot be sourced' test/unit/core.bats test/unit/collect.bats test/unit/lifecycle.bats
```

Expected: failures show that build arguments are ignored, runtime overrides are inherited, and production sourcing is currently allowed.

- [ ] **Step 4: Add the immutable source marker and early source guard**

At the top of `lib/00-header.sh`, after `set -u`, add:

```bash
# shellcheck disable=SC2034 # Replaced with an immutable value in built artifacts.
readonly DBTUNE_ARTIFACT_PROFILE=source-test

if [[ $DBTUNE_ARTIFACT_PROFILE == production && ${BASH_SOURCE[0]} != "$0" ]]; then
    return 65
fi
```

Reset internal header values to safe defaults in production instead of accepting inherited `DBTUNE_PROGRAM`, `DBTUNE_DEFAULT_DAYS`, `DBTUNE_SQL_AUTH_METHOD`, or `DBTUNE_SQL_DEFAULTS_FILE`.

- [ ] **Step 5: Implement validated profile builds**

Parse `build.sh` arguments before creating a temporary file:

```bash
profile=production
case $# in
    0) ;;
    2)
        [[ $1 == --profile ]] || fail "unknown argument: $1"
        profile=$2
        ;;
    *) fail "usage: build.sh [--profile production|integration-test]" ;;
esac
case $profile in
    production|integration-test) ;;
    *) fail "unsupported profile: $profile" ;;
esac
```

Assemble into a profile-specific temporary file, replace exactly one source marker, verify exactly one readonly selected marker and no alternate markers, run syntax/ShellCheck, and publish with `mv` only after all checks pass. Production writes the checksum; integration-test never rewrites it.

Replace the current production artifact self-test that sources the assembled file. Validate production through `bash "$temporary" version`, static presence of every required command definition, and embedded asset retrieval through a test-profile build. A production artifact must never be sourced merely for build validation.

- [ ] **Step 6: Implement production environment preparation**

Add `dbtune_runtime_prepare_environment()` to `lib/10-util.sh`. For production it must:

```text
set PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set LC_ALL=C and LANG=C
reset DBTUNE_PROGRAM=dbtune and DBTUNE_DEFAULT_DAYS=7
reset DBTUNE_SQL_AUTH_METHOD and DBTUNE_SQL_DEFAULTS_FILE to empty
preserve only the seven documented operator DBTUNE_* environment inputs
preserve and verify immutable DBTUNE_ARTIFACT_PROFILE and DBTUNE_ARTIFACT_VERSION
unset every other exported DBTUNE_* name discovered through compgen -e
verify every assignment and unset succeeded
```

The function returns 65 on any readonly or sanitization failure. Call it at the start of `dbtune_main()`, before i18n initialization and dispatch.

- [ ] **Step 7: Add trusted executable resolution and isolated Python**

Implement:

```bash
dbtune_runtime_command_path() {
    local name=${1:-} path
    [[ $name =~ ^[A-Za-z0-9._+-]+$ ]] || return 64
    path=$(type -P -- "$name") || return 69
    [[ $path == /* && -f $path && ! -L $path && -x $path ]] || return 69
    printf '%s\n' "$path"
}
```

Restrict accepted paths to `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, `/usr/local/bin`, or `/usr/local/sbin`. When effective UID is zero, verify the executable and each traversed parent are root-owned and not group/world writable before returning the path.

Use the resolved Python path and invoke the publisher as `"$python" -I -E -s ...`. Remove Python reads of `DBTUNE_PUBLISH_FAIL_MATCH`, `DBTUNE_PUBLISH_FAULT_HOOK`, `DBTUNE_PUBLISH_CRASH_POINT`, and `DBTUNE_PUBLISH_CRASH_MATCH`; pass those values as explicit arguments only in source/integration profiles. Use the same resolver for production systemd command generation so exported functions cannot replace commands.

- [ ] **Step 8: Route integration through its own artifact**

Make `make integration` build `dist/dbtune-integration`, mount it as `/usr/local/bin/dbtune`, and assert inside both MariaDB containers:

```text
integration artifact profile = integration-test
production artifact profile = production
integration hooks execute only for integration artifact
the same hooks do not affect production artifact
```

- [ ] **Step 9: Add installer and release profile gates**

In `install.sh`, after checksum/attestation and before execution, require the exact readonly production marker and reject source/integration markers. Add an installer test using a correctly checksummed and attestable integration-profile fixture; assert status is nonzero and the existing target remains unchanged.

In `.github/workflows/release.yml`, verify on the exact bytes to be attested:

```bash
test "$(grep -c '^readonly DBTUNE_ARTIFACT_PROFILE=production$' dist/dbtune)" -eq 1
! grep -q 'DBTUNE_ARTIFACT_PROFILE=source-test\|DBTUNE_ARTIFACT_PROFILE=integration-test' dist/dbtune
test -x dist/dbtune
sha256sum -c dist/dbtune.sha256
test ! -e dist/dbtune-integration
```

Run the hostile environment smoke test before attestation.

- [ ] **Step 10: Verify and commit runtime isolation**

Run:

```bash
make build
make check
bats test/unit/core.bats test/unit/collect.bats test/unit/install.bats test/unit/lifecycle.bats
```

Commit:

```bash
git add lib/00-header.sh lib/10-util.sh lib/30-collect.sh lib/60-lifecycle.sh lib/90-main.sh \
    build.sh Makefile install.sh test/integration test/unit test/support/check-runtime-environment.sh \
    .github/workflows/release.yml
git commit -m "security: isolate production runtime overrides"
```

---

### Task 2: Bind Strict CNF Input to Apply Publication

**Files:**
- Modify: `lib/10-util.sh`
- Modify: `lib/50-report.sh:1057-1068`
- Modify: `lib/60-lifecycle.sh:320-529,626-780,1985-2160`
- Modify: `lib/05-i18n.sh`
- Test: `test/unit/report.bats`
- Test: `test/unit/lifecycle.bats`

**Interfaces:**
- Produces: `dbtune_cnf_entries_strict FILE`, printing canonical `key<TAB>value` records or returning 65.
- Produces: `dbtune_manifest_validate_exact FILE SCHEMA`, where `SCHEMA` contains one required key per line.
- Produces: `dbtune_lifecycle_prepare_proposal_snapshot SOURCE SNAPSHOT RECORDS`, setting apply-scope globals `DBTUNE_APPLY_SNAPSHOT_HASH`, `DBTUNE_APPLY_RECORDS_HASH`, and `DBTUNE_APPLY_RECORD_COUNT`.
- Consumes: `dbtune_proposal_key_is_safe KEY` and `dbtune_proposal_value_is_safe VALUE`, moved to `lib/10-util.sh`.

- [ ] **Step 1: Add a table-driven strict grammar test**

For normal and forced apply, reject each of:

```text
empty file
comments and [mysqld] but no assignment
assignment before [mysqld]
second [mysqld] section
[server] or [client]
!include and !includedir
bare option
empty key or value
inline # or ; comment
multiple = separators
case/hyphen canonical duplicate
CRLF or embedded control
unsafe or sensitive key
unreadable, directory, or symlink input
```

For each case assert status 65, no SQL call, no confirmation, unchanged target/state/current pointer, no `apply/` directory, and no residual `.apply-*` snapshots.

- [ ] **Step 2: Add partial-parser and exact SQL output tests**

Stub the parser to print one valid record and then return 65. Assert apply stops before SQL. Add live-variable response cases for duplicate row, extra key, extra TSV field, blank row, control, and command failure after partial output. All must stop before durable mutation.

- [ ] **Step 3: Add snapshot TOCTOU and manifest tests**

Inject proposal replacement at these hooks:

```text
after strict parse
before history copy
before target temporary copy
before publisher invocation
```

Assert every replacement is detected by the expected snapshot hash. Add proposal-manifest cases for duplicate-first, duplicate-last, identical duplicate, unknown key, missing schema, malformed hash, zero count, and extra TSV fields.

- [ ] **Step 4: Run strict-input tests and verify RED**

Run:

```bash
bats --filter 'strict proposal grammar|partial parser|exact live variable|proposal snapshot mutation|proposal manifest exact' test/unit/lifecycle.bats test/unit/report.bats
```

Expected: permissive parsing, process substitution, first-value manifest lookup, and re-reading changed files cause failures.

- [ ] **Step 5: Move shared key/value predicates and implement the parser**

Move the two safety predicates to `lib/10-util.sh`. Implement `dbtune_cnf_entries_strict` with an `LC_ALL=C` AWK grammar pass writing to a private temporary records file. AWK emits only from `END` after every line and the final section/count constraints pass. The shell wrapper then validates every buffered key/value through the shared safety predicates and prints the temporary file only after all records pass. Trap and remove the temporary file on every exit; never expose partial parser output.

The parser must canonicalize only after validating the raw key, reject duplicates after canonicalization, and apply the shared sensitive-key policy before accepting output.

- [ ] **Step 6: Implement exact manifest validation**

`dbtune_manifest_validate_exact FILE SCHEMA` must require a regular readable single-link file, exactly two TSV fields per row, every schema key exactly once, no unknown keys, and no controls. Use it before any `dbtune_manifest_value` lookup for proposal manifests.

The proposal schema is exactly:

```text
schema
run_id
audit_hash
samples_hash
analysis_hash
analysis_fingerprint
proposal_hash
proposal_count
proposal_records_hash
```

- [ ] **Step 7: Prepare and bind one apply snapshot**

Implement `dbtune_lifecycle_prepare_proposal_snapshot SOURCE SNAPSHOT RECORDS` to:

```text
copy SOURCE to a private regular mode-0400 SNAPSHOT
strictly parse SNAPSHOT into a private RECORDS file
compute exact snapshot and records SHA-256 hashes
count non-empty records and require count > 0
set DBTUNE_APPLY_SNAPSHOT_HASH, DBTUNE_APPLY_RECORDS_HASH, DBTUNE_APPLY_RECORD_COUNT
```

All later proposal validation and variable-name collection must read `RECORDS`, never rerun a parser through process substitution.

- [ ] **Step 8: Enforce exact live-variable output**

Build the query from canonical records. Capture SQL output in a private file, preserve its command status, then require exactly one single-field row for every requested key and no other rows. Return 69 only when SQL execution fails without trustworthy output; return 65 for malformed or partial output.

- [ ] **Step 9: Carry expected hashes through history and publisher**

Extend `dbtune_lifecycle_prepare_history()` and `dbtune_lifecycle_install_config()` with explicit expected snapshot hash, records hash, and count parameters. Recompute and compare the snapshot hash before each copy. Pass the expected hash into the Python publisher and compare it to the source file descriptor immediately before staging.

- [ ] **Step 10: Verify and commit strict apply input**

Run:

```bash
make check
bats test/unit/report.bats
bats test/unit/lifecycle.bats
```

Commit:

```bash
git add lib/10-util.sh lib/50-report.sh lib/60-lifecycle.sh lib/05-i18n.sh test/unit/report.bats test/unit/lifecycle.bats
git commit -m "fix: bind strict proposal input to apply"
```

---

### Task 3: Preserve Exact Counter and Sample Evidence

**Files:**
- Modify: `lib/10-util.sh:618-759`
- Modify: `lib/20-audit.sh:630-700`
- Modify: `lib/30-collect.sh:157-233,465-681,741-840`
- Modify: `lib/40-rules.sh`
- Modify: `lib/50-report.sh`
- Modify: `test/fixtures/samples-7d.tsv`
- Modify: all unit fixtures containing the sample header
- Test: `test/unit/audit.bats`
- Test: `test/unit/collect.bats`
- Test: `test/unit/rules.bats`
- Test: `test/unit/report.bats`
- Test: `test/unit/lifecycle.bats`

**Interfaces:**
- Produces: `dbtune_uint64_valid VALUE`; `dbtune_uint64_compare LEFT RIGHT`, printing `-1`, `0`, or `1`; and `dbtune_uint64_subtract HIGH LOW`, printing the exact difference or returning 65 when `HIGH < LOW`.
- Produces: the canonical 20-column sample header ending `com_select_delta`, `interval_seconds`, `sample_status`.
- Produces: statuses `ok`, `degraded_interval`, `degraded_counter_reset`, `degraded_counter_inconsistent`, and `degraded_restart_identity`.
- Consumes: exact 13-key MariaDB status snapshots.

- [ ] **Step 1: Add uint64 boundary and exact-delta tests**

Test:

```text
0 and 18446744073709551615 are valid
18446744073709551616 is invalid
an overlong decimal is invalid
9007199254740993 - 9007199254740992 = 1
9007199254740992 compares lower than 9007199254740993
leading zero forms other than 0 are invalid
```

Add counter rows at those boundaries to audit and collector tests.

- [ ] **Step 2: Add exact snapshot and degraded-state tests**

For each of the 13 expected status keys, test missing, duplicate, unknown, extra field, empty, signed, decimal, over-range, and conflicting output. Add a table that decreases every cumulative counter independently without a restart and expects `degraded_counter_reset`.

Add unknown restart identity cases for missing first/second PID, missing starttime, malformed persisted identity, same PID with changed starttime, changed PID, and a restart whose new uptime exceeds the old short uptime.

- [ ] **Step 3: Add invariant and old-header preflight tests**

Cover:

```text
Qcache_hits_delta > Com_select_delta
buffer_pool_reads_delta > buffer_pool_read_requests_delta
Created_tmp_disk_tables_delta > Created_tmp_tables_delta
Com_select_delta == 0 with nonzero qcache percentage
```

Assert collector and `dbtune_samples_inspect` classify them as degraded/rejected and never count them as valid. For old v0.4.1 20-column and legacy 17-column files, invoke `collect start` and assert unchanged file hash, slow-log values, timer, collect config, and state.

- [ ] **Step 4: Run evidence tests and verify RED**

Run:

```bash
bats --filter 'uint64|status snapshot rejects|counter reset|restart identity|counter inconsistent|old sample header' test/unit/collect.bats test/unit/audit.bats test/unit/lifecycle.bats
```

Expected: AWK rounding, zero coercion, legacy migration, and missing identity acceptance cause failures.

- [ ] **Step 5: Implement decimal-string uint64 helpers**

Normalize only canonical unsigned decimal strings. Compare by digit count then lexical byte order. Subtract right-to-left one digit at a time with borrow and trim no significant digits. Do not use Bash arithmetic or AWK numeric conversion for uint64 comparison/subtraction.

Use these helpers for all cumulative counter deltas and invariant comparisons. AWK may format final percentages only after exact ordering and delta strings are established.

- [ ] **Step 6: Validate exact audit and collector snapshots**

Require `NF == 2`, the exact key set, one occurrence per key, and canonical uint64 values. Buffer output until the entire response passes. Audit query-cache evidence is `unknown` unless both counters are exact, `Com_select > 0`, and hits do not exceed selects.

Calculate query-cache percentage as:

```text
100 * Qcache_hits / Com_select
```

- [ ] **Step 7: Implement status precedence and restart identity**

Classify cumulative counters separately from gauges. Apply this precedence:

```text
authoritative restart -> restart_flag=1 and excluded row
unaccounted cumulative decrease -> degraded_counter_reset
cross-counter violation -> degraded_counter_inconsistent
missing/malformed process identity -> degraded_restart_identity
invalid interval -> degraded_interval
otherwise -> ok
```

Persist process identity only after validating all fields. Diagnostics list counter names, never raw large values.

- [ ] **Step 8: Publish and enforce the new sample schema**

Rename field 18 to `com_select_delta` in collector, inspector, percentile filters, rules, reports, lifecycle provenance, fixtures, and docs fixtures. `dbtune_samples_inspect` accepts the new degraded statuses but excludes them from valid counts and rechecks row-level invariants.

Add `dbtune_collect_preflight_samples_file()` and call it in `dbtune_collect_start()` before SQL, directory creation, config writes, slow-log changes, systemd installation, or state transition. Existing old-20 and legacy-17 headers return 65 with a new-cycle diagnostic. Remove automatic legacy append migration.

- [ ] **Step 9: Run all sample consumers and commit**

Run:

```bash
bats test/unit/collect.bats
bats test/unit/audit.bats
bats test/unit/rules.bats
bats test/unit/report.bats
bats test/unit/lifecycle.bats
```

Commit:

```bash
git add lib/10-util.sh lib/20-audit.sh lib/30-collect.sh lib/40-rules.sh lib/50-report.sh test/fixtures test/unit
git commit -m "fix: preserve exact counter evidence"
```

---

### Task 4: Enforce Tri-State Proposal Semantics

**Files:**
- Modify: `lib/40-rules.sh:614-668`
- Modify: `lib/50-report.sh:1088-1204`
- Modify: `lib/05-i18n.sh`
- Test: `test/unit/rules.bats`
- Test: `test/unit/report.bats`

**Interfaces:**
- Produces: R-MYISAM `UNKNOWN|CHANGE|KEEP` from exact `mariadb.status.key_read_requests` evidence.
- Produces: `dbtune_analysis_verdict_can_propose VERDICT`, allowing proposal fields only for explicit changing verdicts.
- Consumes: `dbtune_audit_mariadb_evidence_valid VALIDATOR VALUE` for key-specific current-value validation.

- [ ] **Step 1: Add R-MYISAM state tests**

Test missing, `unknown`, `unresolved`, malformed, zero, positive, and maximum uint64 `Key_read_requests`. Missing/malformed must emit `UNKNOWN` with empty columns 5 and 6 and `proposal_blocked=missing-or-invalid-metric`. Exact zero may propose `key_buffer_size=32M`; positive values must `KEEP`.

- [ ] **Step 2: Add semantic proposal-loader tests**

Create analysis rows where `UNKNOWN`, `REVIEW`, `KEEP`, `OK`, or `UNSUPPORTED` carries key/value fields. Add one-sided key/value, malformed key-specific current value, duplicate conflicting verdicts, and an active proposal with a non-changing verdict. Assert report and propose return 65 without replacing existing report/proposal/manifest files.

- [ ] **Step 3: Add static-hint suppression tests**

For unknown MyISAM and unknown/reviewed skip-name-resolve evidence, render the CNF and assert it contains neither active nor commented `key_buffer_size = 32M` or `skip_name_resolve = 1` recommendations.

- [ ] **Step 4: Run tests and verify RED**

Run:

```bash
bats --filter 'R-MYISAM|non-changing verdict|proposal fields|static recommendation' test/unit/rules.bats test/unit/report.bats
```

- [ ] **Step 5: Implement explicit MyISAM evidence handling**

Replace numeric defaulting with exact text validation. Missing or invalid evidence must never call `size_setting`; zero and positive branches are explicit.

- [ ] **Step 6: Enforce proposal verdict and current-value schemas**

Implement `dbtune_analysis_verdict_can_propose()` with the exact allowlist of changing server verdicts already produced by rules, initially `CHANGE` and `REDUCE`. Require key/value both absent for every other verdict. Before adding a proposal, validate current evidence using the key's audit schema and canonicalize equivalent bool values.

Remove evidence-dependent MyISAM and skip-name-resolve lines from the static proposal header. They may appear only through validated active rules.

- [ ] **Step 7: Verify catalogs and commit**

Run:

```bash
sh test/support/check-catalog.sh runtime lib/05-i18n.sh lib/*.sh
bats test/unit/rules.bats
bats test/unit/report.bats
```

Commit:

```bash
git add lib/40-rules.sh lib/50-report.sh lib/05-i18n.sh test/unit/rules.bats test/unit/report.bats
git commit -m "fix: enforce tri-state proposal semantics"
```

---

### Task 5: Gate Skip-Name-Resolve on Exact Grant Evidence

**Files:**
- Modify: `lib/20-audit.sh:1209-1221,1272-1446`
- Modify: `lib/40-rules.sh:645-654`
- Modify: `lib/50-report.sh`
- Modify: `lib/05-i18n.sh`
- Modify: `test/fixtures/audit-10.6.tsv`
- Modify: `test/fixtures/audit-11.4.tsv`
- Test: `test/unit/audit.bats`
- Test: `test/unit/rules.bats`
- Test: `test/unit/report.bats`

**Interfaces:**
- Produces: `dbtune_grant_host_classify HOST`, printing `address|hostname` or returning 65 for empty/control input.
- Produces: `security.hostname_grant_count=UINT|unknown` paired with `security.grants_audited=0|1`.
- Produces: `skip_name_resolve_rule()` with exact current-value and grant-evidence state handling.

- [ ] **Step 1: Add strict host classification tests**

Add valid cases for localhost, `%`, IPv4 boundaries, supported IPv4 wildcard/netmask forms, full/compressed IPv6, IPv4-mapped IPv6, and supported hexadecimal wildcard forms. Add hostname-dependent cases for DNS names, escaped wildcards, mixed address/DNS text, invalid octets, noncontiguous or malformed masks, `1..2.3`, `::::`, `abcd:host`, empty, NULL representation, and controls.

- [ ] **Step 2: Add security evidence consistency tests**

Test every combination of `grants_audited=0|1|malformed|missing` with hostname count `0|positive|unknown|malformed|missing|duplicate`. Only `1` plus one valid uint count can make the security section complete. Query failure must emit exactly `grants_audited=0` and count `unknown`.

- [ ] **Step 3: Add skip-name-resolve matrix tests**

Cover current values `ON`, `1`, `OFF`, `0`, missing, `unknown`, `unresolved`, `2`, and arbitrary text crossed with complete zero-hostname, complete positive-hostname, failed, and malformed grant evidence.

Expected core outcomes:

```text
ON/1 + complete zero -> OK
OFF/0 + complete zero -> CHANGE skip_name_resolve=1
any valid current + hostname count > 0 -> REVIEW, no proposal
unknown/malformed current or grant evidence -> UNKNOWN, no proposal
```

- [ ] **Step 4: Run tests and verify RED**

Run:

```bash
bats --filter 'grant host|hostname grant|security evidence|skip_name_resolve' test/unit/audit.bats test/unit/rules.bats test/unit/report.bats
```

- [ ] **Step 5: Implement unambiguous grant collection and classification**

Query `HEX(USER), HEX(HOST)` as exactly two TSV fields, reject duplicate/malformed rows, reject NUL-containing hex before decoding, decode only validated even-length hex, and classify every account row. Count hostname-dependent account rows, not distinct hosts. Do not publish raw grant values in diagnostics.

Implement strict IPv4 octet checks and IPv6 parsing without treating arbitrary colon-containing text as an address. Accept numeric IPv4 wildcards only as one to three canonical octets followed by a final `%` component, for example `192.168.%`; classify `_` and mixed DNS/address wildcard forms as hostname-dependent. Accept IPv4 netmasks only as `address/contiguous-mask`, with both sides valid dotted IPv4. Accept IPv6 wildcards only as valid leading hexadecimal groups followed by a final `%` component. Unknown forms classify as hostname-dependent; empty/control input fails the audit evidence.

- [ ] **Step 6: Implement security and rule tri-state contracts**

Finalize security as complete only when grant status/count are mutually consistent and listener evidence is known. Implement the dedicated skip rule with exact bool normalization and no call to generic `setting()` until current/grant evidence passes.

Add additive `fleet-v3` fields for security section status, `security.grants_audited`, and `security.hostname_grant_count` without renaming existing fields.

- [ ] **Step 7: Verify and commit grant safety**

Run:

```bash
bats test/unit/audit.bats
bats test/unit/rules.bats
bats test/unit/report.bats
sh test/support/check-catalog.sh runtime lib/05-i18n.sh lib/*.sh
```

Commit:

```bash
git add lib/20-audit.sh lib/40-rules.sh lib/50-report.sh lib/05-i18n.sh test/fixtures test/unit
git commit -m "fix: gate skip-name-resolve on grant evidence"
```

---

### Task 6: Derive and Recheck Loaded Server Landmines

**Files:**
- Create: `lib/15-mariadb-safety.sh`
- Modify: `lib/20-audit.sh:294-320,1241-1446`
- Modify: `lib/40-rules.sh:630-643`
- Modify: `lib/60-lifecycle.sh:399-429,579-780,1985-2160`
- Modify: `lib/05-i18n.sh`
- Modify: `test/fixtures/audit-10.6.tsv`
- Modify: `test/fixtures/audit-11.4.tsv`
- Test: `test/unit/audit.bats`
- Test: `test/unit/rules.bats`
- Test: `test/unit/lifecycle.bats`
- Test: `test/integration/run.sh`

**Interfaces:**
- Produces: `dbtune_landmine_catalog`, printing `name<TAB>minimum-version<TAB>severity<TAB>reason-id`.
- Produces: `dbtune_loaded_defaults_scan OUTPUT_FILE`, atomically writing exact scan evidence or returning 65/69.
- Produces: `dbtune_loaded_defaults_assert_safe FILE`, returning 0 only for complete evidence with no loaded critical option.
- Consumes: `dbtune_runtime_command_path` from Task 1.
- Consumes: proposal snapshot metadata from Task 2.

- [ ] **Step 1: Add loaded-default scanner contract tests**

Test `mariadbd` absent with valid `mysqld` fallback, available-but-failing `mariadbd` without fallback, empty success, stderr-only diagnostics, malformed/control output, duplicate known tokens, exact `--name` and `--name=value`, unknown valid options, and version gates. Unused CNF files, client sections, and comments must not create loaded evidence.

- [ ] **Step 2: Add rule and audit tri-state tests**

Cover:

```text
complete + loaded=1
complete + loaded absent
failed
missing status
duplicate/conflicting status
malformed loaded value
old config_* evidence only
```

Only complete plus loaded may emit `REMOVED`/`DEPRECATED`. Failed/missing/conflicting evidence must make MariaDB audit partial and rules `UNKNOWN` without a proposal.

- [ ] **Step 3: Add live apply preflight tests**

For normal and forced apply from `audited`, `analyzed`, and `proposed`, test:

```text
stored audit says safe, live scan loads critical option
stored audit says safe, live scan fails
old audit lacks scan contract
scan output changes after proposal validation
warning-only loaded option
```

Critical/failure/old evidence returns 65 before history/intent/current/state/target/service mutation. Warning-only evidence is recorded but does not bypass other checks.

- [ ] **Step 4: Add rollback and recovery independence tests**

Make the scanner unavailable, corrupt current audit evidence, and add a current critical option. Assert `cmd_rollback`, failed-apply recovery, interrupted rollback continuation, and old-history restore never invoke the scanner and still restore filesystem state.

- [ ] **Step 5: Run landmine tests and verify RED**

Run:

```bash
bats --filter 'loaded defaults|landmine scan|live landmine|force cannot bypass|rollback ignores landmine' test/unit/audit.bats test/unit/rules.bats test/unit/lifecycle.bats
```

- [ ] **Step 6: Implement the shared catalog and scanner**

Create `lib/15-mariadb-safety.sh` with one catalog:

```text
innodb_file_format             10.3 critical reason_variable_removed_startup
innodb_file_format_max         10.3 critical reason_variable_removed_startup
innodb_buffer_pool_instances   10.6 critical reason_variable_removed_config
innodb_log_files_in_group      10.6 critical reason_variable_removed_config
innodb_change_buffering        11.0 critical reason_variable_removed_startup
innodb_flush_method            11.0 warning  reason_flush_method_deprecated
```

Resolve `mariadbd`; use `mysqld` only when absent. Capture stdout and stderr separately. Parse tokens without `eval`, normalize exact known option forms, and collapse duplicates. Whenever the output path can be written, publish a syntactically valid status snapshot even on scanner failure; return 65 for malformed output and 69 for command unavailability so callers cannot confuse the status record with command success. The snapshot contains:

```text
landmine.scan.status complete|failed
landmine.scan.method mariadbd_print_defaults|mysqld_print_defaults
landmine.<name>.loaded 1
landmine.<name>.severity critical|warning
finding.landmine.<name> critical|warning
```

- [ ] **Step 7: Replace filesystem evidence in audit and rules**

Remove recursive CNF grep and all `config_*` or severity-only rule fallbacks. Audit records scan failure as one warning and marks MariaDB partial. Rules require a complete exact scan contract; absent `.loaded` under complete means not loaded.

- [ ] **Step 8: Add the fresh apply scan before durable mutation**

After proposal, live-variable, backup, target, Galera, and mydumper validation, execute one final fresh scan into a private snapshot and call `dbtune_loaded_defaults_assert_safe` immediately before `dbtune_lifecycle_new_history()`. No unrelated check or mutation may occur between that scan and history creation. `--force` follows the same path. Bind the final scan snapshot hash and loaded-option fingerprint into the new history; do not substitute stored audit evidence for this scan.

Extend new history metadata with audit run/hash, proposal hashes/count, live scan timestamp, scan method, loaded-option fingerprint, and force flag. Require new fields only for the new history schema.

- [ ] **Step 9: Add real MariaDB integration assertions**

For 10.6 and 11.4 assert:

```text
landmine.scan.status = complete
landmine.scan.method = mariadbd_print_defaults
an injected loaded critical option blocks apply before publication
removing it permits the normal lifecycle
```

- [ ] **Step 10: Verify and commit loaded-default safety**

Run:

```bash
make check
bats test/unit/audit.bats test/unit/rules.bats test/unit/lifecycle.bats
DBTUNE_REQUIRE_INTEGRATION=1 DBTUNE_UI_LANG=en make integration
```

Commit:

```bash
git add lib/15-mariadb-safety.sh lib/20-audit.sh lib/40-rules.sh lib/60-lifecycle.sh lib/05-i18n.sh test/fixtures test/unit test/integration/run.sh
git commit -m "fix: block apply on loaded server landmines"
```

---

### Task 7: Document Contracts and Run the P1 Completion Gate

**Files:**
- Modify: `README.md`
- Modify: `SECURITY.md`
- Modify: `docs/RUNBOOK.md`
- Modify: `PLAN.md`
- Modify: `mariadb-runcloud-preset.md`

**Interfaces:**
- Documents: immutable profiles, environment allowlist, strict force grammar, exact proposal snapshot, sample schema boundary, degraded evidence, grant gate, live landmine scan, and rollback independence.
- Consumes: all completed P1 runtime and test interfaces.

- [ ] **Step 1: Document artifact and force boundaries**

State exactly which operator environment variables production accepts, that release artifacts ignore all test-only overrides, that production artifacts cannot be sourced, and that installer/release reject non-production profiles. List exactly what `--force` may and may not bypass.

- [ ] **Step 2: Document evidence and collection boundaries**

Document exact uint64 handling, degraded statuses, query-cache formula `100 * Qcache_hits / Com_select`, cross-counter invariants, and the `com_select_delta` field. Explain that active v0.4.1 20-column and legacy 17-column collections must stop and begin a fresh audit/collection cycle before new writes; existing apply and rollback history remains available.

- [ ] **Step 3: Document grants, landmines, and recovery**

Explain that `skip_name_resolve` requires complete address-only grant evidence, that loaded options come from daemon `--print-defaults`, and that apply repeats the scan immediately before mutation. State that scan/audit failures block forward apply but never block rollback or recovery.

- [ ] **Step 4: Run static contract checks**

Run:

```bash
make build
make check
sh test/support/check-catalog.sh runtime lib/05-i18n.sh lib/*.sh
git diff --check
```

Expected: zero errors and no unclassified production profile or catalog references.

- [ ] **Step 5: Run the full unit suite**

Run:

```bash
make test
```

Expected: all tests pass with no failures or terminated jobs.

- [ ] **Step 6: Run required integration**

Run:

```bash
DBTUNE_REQUIRE_INTEGRATION=1 DBTUNE_UI_LANG=en make integration
```

Expected: MariaDB 10.6 and 11.4 complete audit, collection, analysis, report, propose, apply, restart, verify, and rollback coverage with production/integration profile assertions.

- [ ] **Step 7: Review the complete branch diff**

Check:

```bash
git diff --check origin/main...HEAD
git status --short
git log --oneline origin/main..HEAD
```

Confirm generated `dist/` files are absent, no test hook is reachable in production, all new messages exist in EN/SK catalogs, and every spec section maps to a passing test.

- [ ] **Step 8: Commit P1 documentation**

```bash
git add README.md SECURITY.md docs/RUNBOOK.md PLAN.md mariadb-runcloud-preset.md
git commit -m "docs: document fail-closed safety contracts"
```

## P1 Completion Gate

Do not begin P2 until all conditions hold:

- [ ] Production artifacts ignore every non-operator inherited `DBTUNE_*` value and isolated Python ignores Python environment injection.
- [ ] Integration hooks work only through the immutable integration-test artifact.
- [ ] Build, installer, and release reject non-production release artifacts fail-closed.
- [ ] Normal and forced apply reject every strict-grammar, manifest, SQL exact-set, stale-hash, and TOCTOU violation before durable mutation.
- [ ] Exact uint64 handling preserves one-unit deltas above `2^53` and rejects over-range values.
- [ ] Missing, malformed, reset, inconsistent, or restart-identity-unknown counters cannot become proposals.
- [ ] Old 20-column and legacy 17-column files are never appended or migrated.
- [ ] Non-changing analysis verdicts cannot carry proposal values.
- [ ] `skip_name_resolve` is proposed only with a valid disabled current value and complete hostname-independent grant evidence.
- [ ] Audit, rules, and apply use one central loaded-defaults catalog.
- [ ] A fresh failed or critical apply-time scan blocks normal and forced apply.
- [ ] Rollback and recovery succeed without audit, SQL, or loaded-default scanning, including old history schemas.
- [ ] `make check`, `make test`, required integration, catalog validation, and `git diff --check` pass.
- [ ] A read-only pilot confirms the new audit keys and starts a fresh measurement cycle before any apply attempt.
