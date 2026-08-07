# P1 fail-closed safety design

Date: 2026-08-05
Status: approved

## Goal

Prevent incomplete, malformed, stale, or attacker-controlled evidence from
becoming a MariaDB configuration change. Every production path must stop before
durable mutation when it cannot prove that its runtime, proposal, evidence, and
loaded server defaults satisfy the safety contract.

This design covers the complete P1 package:

- immutable production and test artifact profiles;
- strict proposal grammar and manifest validation;
- exact collector counter handling and sample schema correction;
- tri-state MyISAM and `skip_name_resolve` decisions;
- landmine detection from daemon-loaded defaults;
- a final independent apply preflight;
- fail-safe rollback and crash recovery;
- documentation and verification of the new contracts.

## Safety principles

The implementation follows four rules.

1. Unknown is not zero, absent, safe, or disabled.
2. Validation succeeds only on complete exact input, never on accepted subsets.
3. The bytes validated are the bytes recorded and published.
4. New apply safety gates may block forward mutation but must not block rollback
   or recovery.

`--force` may bypass only measurement and provenance requirements and the local
time window. It may not bypass proposal grammar, live-variable validation,
loaded-default checks, backup, target, topology, Galera, mydumper, daemon
validation, rollback, or recovery guards.

## Architecture

Fail-closed safety is enforced at four independent layers.

### Trusted runtime

Builds embed one immutable profile:

```text
source-test
production
integration-test
```

The production artifact resets internal header state, sanitizes its runtime
environment before command dispatch, ignores test-only command, fault, clock,
ownership, path, and threshold overrides, and runs its Python publisher in an
isolated mode. Test hooks remain available only in source and integration test
profiles.

Every runtime `DBTUNE_*` variable is classified as one of:

- immutable build constant;
- documented operator input;
- test-only input;
- internal state.

Production accepts only the documented operator inputs. A contract test fails
when a new runtime variable is introduced without classification.

### Strict inputs

Proposal rendering and every apply mode share one strict CNF parser. The parser
accepts only blank lines, full-line comments, exactly one `[mysqld]` section,
and one or more safe key/value assignments. It rejects directives, other or
repeated groups, bare options, empty assignments, inline comments, controls,
multiple separators, unknown lines, and canonical duplicates.

Keys are normalized to lowercase with hyphens converted to underscores.
Duplicate detection happens after normalization. Parsing uses byte-stable locale
rules and rejects unreadable, non-regular, symlinked, or otherwise untrusted
input files.

### Tri-state evidence

Audit, collection, rules, and reporting preserve three semantic outcomes:

```text
known and valid
unknown or unavailable
invalid or degraded
```

Only known and valid evidence can produce a configuration proposal. Unknown or
invalid evidence produces `UNKNOWN` without proposal fields. Report and proposal
loading revalidate this relationship so a corrupted analysis file cannot attach
a key/value pair to `UNKNOWN`, `REVIEW`, `KEEP`, `OK`, or another non-changing
verdict.

### Final apply preflight

Immediately before durable mutation, apply independently verifies:

- the immutable runtime profile and sanitized environment;
- the strict proposal snapshot and its hashes;
- exact live-variable query output;
- proposal and analysis manifests where required;
- backup evidence;
- target and parent topology;
- Galera, mydumper, daemon, and restart safety;
- a fresh loaded-defaults scan and the central landmine catalog.

Failure in any check stops normal and forced apply before history, intent, state,
target, or service mutation.

## Artifact profile contract

`build.sh` accepts no profile argument or exactly one of:

```text
--profile production
--profile integration-test
```

No argument builds `dist/dbtune` and its checksum as production. The integration
profile builds a separate `dist/dbtune-integration` and must not change the
production artifact or checksum. Missing values, duplicate flags, extra
arguments, and unknown profiles fail before replacing a previous good artifact.

The build verifies that exactly one readonly profile assignment is present in
the output and that no source or alternate profile marker remains. Attempts to
override the profile through inherited environment or a readonly sourced value
must fail closed.

The production runtime resets internal SQL authentication state instead of
trusting inherited `DBTUNE_SQL_AUTH_METHOD` or `DBTUNE_SQL_DEFAULTS_FILE`.
Sanitization failures, including values that cannot be reset or unset, stop
dispatch. Production command resolution and the loaded-defaults scanner must not
accept exported shell functions as trusted executables.

Trusted executable resolution uses external-file lookup rather than shell
function lookup, returns an absolute path, and validates that path against the
production executable policy before invocation.

The Python publisher runs with `python3 -I -E -s` and receives test hooks only
as explicit arguments in test profiles. Inherited
`PYTHONPATH`, `PYTHONHOME`, and publisher fault variables cannot affect the
production publisher.

The supported production contract is direct execution through the artifact or
`bash dist/dbtune`. A production artifact detects sourcing in its header and
returns status `65` before loading runtime modules, so it cannot expose
privileged internal functions to the caller. Source-based module execution
remains a test-only contract.

The release workflow behaviorally tests the exact bytes it will attest and
publish. It verifies the production marker, checksum, syntax, executable mode,
negative override behavior, and absence of the integration artifact from release
subjects. The installer independently rejects a validly checksummed and attested
artifact whose embedded profile is not production.

## Proposal snapshot and grammar contract

Apply creates a private mode-0400 proposal snapshot before safety validation.
The strict parser processes that snapshot exactly once and produces:

- canonical key/value records;
- the exact snapshot SHA-256;
- the canonical-record SHA-256;
- the assignment count.

Every downstream validator, history writer, and publisher receives those
expected values. The snapshot hash is checked before history copy, before target
staging, and at the publisher boundary. A changed snapshot is never reparsed as
new trusted input.

Parser failure cannot be hidden by process substitution. Partial output followed
by a nonzero status is a failure and must not trigger SQL, confirmation, backup
checks, history creation, or target mutation.

The live-variable SQL response must contain exactly the requested canonical key
set, each key once, with no extra columns, controls, duplicates, unknown rows, or
partial output. Any mismatch fails the preflight.

Proposal manifests use an exact-key schema. Required keys occur exactly once,
unknown keys are rejected, hashes have the required shape, counts are positive,
and the file hash, canonical-record hash, analysis record hash, and assignment
count agree.

## Durable mutation boundary

Before all safety gates pass, apply may create only:

- a private ephemeral proposal snapshot;
- its canonical records and hashes;
- a private backup-evidence snapshot after proposal validation.

Before all gates pass, apply must not create or change:

- an `apply/` history directory;
- an apply intent journal;
- the current pointer;
- lifecycle state;
- a target-side temporary file;
- the managed target;
- MariaDB service state.

After the durable boundary begins, the existing intent journal and atomic
publisher remain authoritative. A failure after target mutation initiates the
existing automatic restore path and cannot leave state as successfully applied.

New history records use a schema that preserves the audit run/hash, proposal
snapshot hashes and count, live loaded-defaults fingerprint and timestamp, and
force mode. Existing history schemas remain rollbackable.

## Loaded-defaults and landmine contract

Audit and apply share one central landmine catalog containing canonical option
name, version gate, severity, and reason identifier. No consumer may maintain a
private subset.

The scanner resolves `mariadbd` from the trusted executable policy and falls
back to `mysqld` only when `mariadbd` is unavailable. It does not hide a failure
from an available `mariadbd` by using the fallback. It invokes `--print-defaults`
without evaluating the output as shell code.

The scanner contract is:

- nonzero exit or malformed/control-containing output is `failed`;
- empty successful output is `complete` with no loaded options;
- stderr is diagnostic only and is not parsed as options;
- duplicate known option tokens collapse to one loaded record;
- exact `--name` and `--name=value` forms are normalized;
- unknown syntactically valid options are ignored;
- malformed tokens fail the scan.

Audit publishes `landmine.scan.status=complete|failed`, the scan method, and
`.loaded=1` only for detected known options. With a complete scan, an absent
`.loaded` key means authoritatively not loaded. Missing, failed, duplicate,
conflicting, or malformed status/evidence is unknown and cannot imply safety.

Apply does not rely only on stored audit evidence. It performs a fresh live scan
as late as practical before history creation and durable publication. Scan
failure or a loaded critical landmine blocks normal and forced apply. Old audits
without the loaded-defaults contract require a new audit cycle.

Landmine checks are forward-mutation checks only. Rollback and crash recovery do
not invoke the scanner and continue to work when MariaDB, audit files, or current
defaults are unavailable or unsafe.

## Counter and sample contract

Collector and audit status snapshots require an exact counter schema. Every
required key appears once, unknown keys and extra fields are rejected, and every
value is a canonical unsigned decimal in the supported uint64 range. Missing,
empty, signed, decimal, over-range, or excessively long values are not converted
to zero.

Counter comparison and subtraction remain exact above `2^53`; AWK floating-point
conversion cannot decide resets or deltas. Cumulative counters and gauges are
classified explicitly. A decrease in any cumulative counter without an
authoritative restart produces `degraded_counter_reset` for the entire row.

If PID/starttime restart identity is missing or malformed at either snapshot,
the row becomes `degraded_restart_identity`. Unknown identity never means no
restart.

Row status precedence is:

1. authoritative restart;
2. unaccounted cumulative counter reset;
3. cross-counter inconsistency;
4. unknown restart identity;
5. invalid interval;
6. valid row.

Cross-counter invariants include:

- `Qcache_hits_delta <= Com_select_delta`;
- buffer-pool reads delta <= buffer-pool read requests delta;
- created disk temporary tables delta <= all created temporary tables delta;
- zero `Com_select_delta` implies zero query-cache percentage.

The collector validates these invariants before calculating percentages.
Sample inspection validates all representable invariants again so a manually
corrupted TSV cannot influence analysis, reports, or apply readiness.

The corrected 20-column schema uses `com_select_delta`. The shipped v0.4.1
20-column `qcache_queries_delta` format and legacy 17-column format are detected
at `collect start` before slow-log, timer, config, or lifecycle mutation. Both
remain readable under their documented analysis compatibility, but neither can
be appended or silently migrated. A new audit and collection cycle is required.

## MyISAM and proposal semantics

R-MYISAM consumes a validated unsigned `Key_read_requests` value:

- missing or malformed produces `UNKNOWN` with no proposal;
- exact zero may propose the configured key buffer target;
- a positive value keeps the existing setting.

Proposal loading accepts key/value fields only from explicitly changing
verdicts. Key and value must either both be present or both be absent. Conflicting
or duplicate proposal records fail report and proposal publication without
replacing previous artifacts.

Evidence-dependent values such as `key_buffer_size` and `skip_name_resolve` are
not emitted as static commented recommendations when their rule is unknown or
under review.

## Grant and skip-name-resolve contract

Audit emits `security.hostname_grant_count` as an unsigned count only when
`security.grants_audited=1`; otherwise it emits `unknown`. A complete security
section requires these fields to be mutually consistent. Missing, malformed,
duplicate, or contradictory combinations make the section partial and the
overall evidence non-authoritative.

Grant collection uses an unambiguous field format and counts account rows, not
distinct host strings. Classification accepts only validated forms:

- exact case-insensitive `localhost`;
- exact `%`;
- IPv4 addresses with four octets in `0..255`;
- explicitly supported numeric IPv4 wildcard and netmask forms;
- syntactically valid full or compressed IPv6 forms;
- explicitly supported hexadecimal IPv6 wildcard forms.

Invalid numeric-looking hosts, mixed DNS/address forms, empty values, malformed
netmasks, and all other non-empty values are hostname-dependent. Classification
never treats arbitrary text containing digits, dots, or colons as an address.

`skip_name_resolve` current values accept only `0`, `1`, `OFF`, or `ON`, with
equivalent enabled and disabled forms normalized. The rule behaves as follows:

- malformed or unknown current value: `UNKNOWN`;
- failed or inconsistent grant evidence: `UNKNOWN`;
- hostname-dependent grants: `REVIEW`;
- already enabled with complete address-only grants: `OK`;
- disabled with complete address-only grants: normal comparison and possible
  `CHANGE`.

Only the final case may add `skip_name_resolve=1` to a proposal.

## Error behavior

Invalid input, incomplete evidence, stale hashes, schema conflicts, and unsafe
loaded defaults return the existing data/safety status `65`. Failure to contact
a required external service or execute a required SQL query returns the existing
infrastructure status `69`. Malformed or partial output returns `65`; neither
status permits continuation.

Diagnostics identify the blocking category and the required operator action
without logging credentials, raw grant data, or unnecessary counter values.
Private snapshots are removed on preflight failure. The target, lifecycle state,
current pointer, history, and services remain unchanged.

Failure after the durable mutation boundary uses the intent journal and existing
automatic recovery. Event/reporting failure after a committed state does not
misrepresent or undo the committed filesystem state.

## Compatibility

The public CLI, English/Slovak interface selector, `fleet-v3` report contract,
normal RunCloud manual-restart workflow, and existing rollback history remain
supported.

The new sample denominator is an intentional collection-cycle boundary. Existing
v0.4.1 20-column samples require a fresh audit and collection cycle. Legacy
17-column samples retain their documented read-only analysis behavior with query
cache evidence unavailable.

Old apply histories remain rollbackable. New strict history fields apply only to
newly created history schema versions.

## Testing strategy

Every behavior change follows a red-green test cycle. Required coverage includes:

- build argument matrices and atomic preservation of previous artifacts;
- hostile profile, command, path, SQL-auth, readonly, and Python environments;
- installer and release rejection of non-production artifacts;
- table-driven strict CNF and exact manifest grammar;
- parser partial-output/nonzero propagation;
- exact live-variable SQL result sets;
- proposal snapshot replacement at every validation/publication boundary;
- normal and forced apply from every permitted lifecycle state;
- fresh scan disagreement with stored audit evidence;
- loaded-default scanner fallback, malformed output, empty output, and version
  gates;
- rollback and recovery with a failed scanner, missing audit, and old history;
- exact uint64 arithmetic, reset precedence, unknown restart identity, and
  cross-counter invariants;
- old sample header rejection before collector mutation;
- MyISAM and skip-name-resolve state matrices;
- strict IPv4, IPv6, wildcard, netmask, and hostname classification;
- analysis/report rejection of proposal fields on non-changing verdicts;
- MariaDB 10.6 and 11.4 integration using real `--print-defaults` output.

The completion gate is:

```bash
make build
make check
make test
DBTUNE_REQUIRE_INTEGRATION=1 DBTUNE_UI_LANG=en make integration
sh test/support/check-catalog.sh runtime lib/05-i18n.sh lib/*.sh
```

The release gate also behaviorally verifies the exact production artifact bytes
before attestation and publication.

## Expected result

No malformed, incomplete, stale, degraded, or test-controlled input can become a
production MariaDB configuration change. Every forward mutation is based on one
strictly validated and hash-bound proposal snapshot plus fresh loaded-defaults
evidence. Failures preserve the prior target and lifecycle state, while rollback
and recovery remain available independently of the failed forward checks.
