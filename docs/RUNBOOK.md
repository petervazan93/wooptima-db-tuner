# dbtune rollout runbook

## Prerequisites

- Run as `root` on supported MariaDB 10.6, 10.11, or 11.x, not on a Galera/wsrep node. `apply`, rollback, and crash recovery require `python3` with `dir_fd` support and Linux `renameat2`.
- Before the pilot, verify a restorable database backup, RunCloud panel access, and an out-of-band console. Local cron entries are not evidence of a successful RunCloud backup.
- A normal `apply` expects state `proposed`, at least 288 valid samples, and `proposal-manifest.tsv`, which binds the proposal to one measurement cycle through `run_id`, `audit_hash`, `samples_hash`, `analysis_hash`, and `proposal_hash`.
- The default target is `/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf`, and the allowed directory is `/etc/mysql/mariadb.conf.d`. A nonstandard `DBTUNE_CONFIG_TARGET` also requires an explicit `DBTUNE_CONFIG_ALLOWED_DIR`; the target must be a direct `.cnf` file in that directory. Apply, verify, and rollback reject a target symlink, dangling symlink, more than one stable hard link, a symlinked parent component, replacement of the parent directory during apply, and an existing file outside the `root:root 0644` contract. The state file and lifecycle lock file must have exactly one hard link at a stable path. Managed configuration publication uses an atomic exchange or no-replace rename, so the target never has a temporary second hard link, including at crash boundaries.
- Without `--force`, apply is blocked from 05:30 to 07:30 local time and is always blocked by Galera, a running mydumper process, or authoritative backup status `missing`. Both apply and `--force` require a valid backup-evidence artifact or a separate safety confirmation on a TTY.

## Interface language and v0.4.0 artifacts

- The executable and installer default to English when `DBTUNE_UI_LANG` is unset or empty. `DBTUNE_UI_LANG=en` selects English explicitly and `DBTUNE_UI_LANG=sk` selects Slovak. Any other non-empty value exits with status 64 before command dispatch. `LANG`, `LC_MESSAGES`, and other operating-system locale variables do not select the interface language.
- Use `sudo dbtune audit` for the English default or `sudo DBTUNE_UI_LANG=sk dbtune audit` for Slovak. Commands, options, paths, keys, enums, schema versions, and exit statuses do not change with the selected language.
- `collect start` stores the validated language as `ui_lang` in root-owned `collect.tsv`. The systemd `_tick` path restores it before lifecycle diagnostics and before automatic analyze/report completion, so unattended output keeps the language selected at collection start.
- The flat JSON report schema is `fleet-v3`. It includes `report.language`, stable reason and warning IDs, and localized display text. Consumers must use stable IDs and machine keys rather than parse localized prose.
- v0.4.0 `analysis.tsv` keeps eight columns but ends in `reason_id`. Report, propose, and apply reject the old `reason_sk` header without translating, rehashing, or mutating it. Start a new v0.4.0 audit and measurement cycle. Existing apply history and rollback recovery remain available.
- The currently published release is `v0.3.0`, and the immutable artifact version is still `0.3.0`; v0.4.0 is a new feature-release cycle built on that release.

## Pilot

1. Select 1-2 servers: one MariaDB 10.6 and one from the 11.x family. Do not choose the largest store or a server without a tested backup.
2. Complete `audit`, collection, `analyze`, report review, and `propose`. Manually review pool sizing, `max_connections`, storage class, and application findings.
   The report must have a known current value for every active server change. A missing current value, unsafe proposal, or alias duplicate such as `max_connections`/`max-connections` is an input error, not an item to skip.
3. Run `dbtune apply`. The tool verifies independent backup evidence, checks every active name from `[mysqld]` in one query against `information_schema.GLOBAL_VARIABLES`, stores the baseline, and atomically writes the configuration as `root:root 0644`.
4. Read `$STATE/apply/<timestamp>-<pid>/ROLLBACK.txt` before restart. It contains literal commands and works without dbtune and without a working database.
5. Without `--restart`, restart through RunCloud at `Services -> MariaDB -> Restart`. Use `--restart` only for pilot scripting; it invokes `systemctl restart mariadb`, checks the active state, and restores the configuration on failure.
6. Wait approximately 5 minutes and run `dbtune verify --post`. Verify first checks that the target is a regular nonsymlink file with `root:root 0644` and the hash of the exact deployed snapshot. It then checks effective values and growth in `Innodb_buffer_pool_wait_free`, `Innodb_log_waits`, and `Aborted_connects` against a reset-aware baseline, swap growth, and critically low available RAM. A failure is a reason to roll back.
7. After 24 hours and at least one real peak, run `dbtune verify --24h`. The output compares status and memory with the baseline; a reset lifetime counter is marked as `reset:<value>`.

The first start may take longer after changing `innodb_log_file_size`. Increased `Innodb_buffer_pool_reads` during the first warm-up window is not, by itself, a regression.

## Run semantics

- Every successful `dbtune audit` creates a new `run_id` and `audit_hash`. Audit does not change MariaDB or system configuration, but it publishes a new measurement cycle; there is no separate `--new-run` option.
- Required authoritative sections are `mariadb`, `hardware`, `applications`, and `security`. `PASS` means complete sections without findings, `FINDINGS` means complete sections with findings, `UNKNOWN` means partial or failed required evidence while preserving the available audit, and `ERROR` means all required sections failed. Terminal text, audit JSON, and the report identify failed/partial sections and affected recommendation domains.
- The MariaDB evidence schema is the single source for the audit query, proposal current keys, data domains, and version gates. Before continuing, `audit.section.mariadb.missing_evidence`, `invalid_evidence`, and `conflicting_evidence` must equal `none`; `optional_evidence` explains version-specific optional input. Diagnostics never contain the rejected value.
- A classified audit returns `0` for `PASS`/`FINDINGS`, `2` for `UNKNOWN`, and `1` for `ERROR`. Usage, validation, dependency, and other technical failures may use existing exit statuses `64+`; automation must not interpret those as audit classifications. Diagnostic artifacts remain published for classified `UNKNOWN`/`ERROR`, but do not treat the measurement cycle as authoritative or continue automatically.
- Audit is rejected while state is `collecting` so that the original slow-log recovery configuration is not lost. Run `dbtune collect stop` first.
- On a repeated audit, previous audit, collect, analysis, report, and proposal artifacts are copied to `$STATE/runs/<run_id>/`. Active downstream artifacts are invalidated and state changes to `audited`.
- `$STATE/apply/` and `$STATE/apply/current` are unchanged by a new audit. `dbtune status` displays `rollback_available: true`, and rollback remains available after a new measurement cycle starts; while state is `collecting`, stop collection first for safety.
- `analysis-manifest.tsv` must match the current audit run/hash, `samples.tsv`, and `analysis.tsv` exactly. Report and proposal verify this contract again. Normal apply also verifies the proposal manifest and deploys a private snapshot with the exact verified `proposal_hash`.
- `proposal-manifest.tsv` additionally binds `proposal_count` and `proposal_records_hash` to a canonical list. Apply compares the list with both analysis and the actual CNF keys and values.
- Mutating lifecycle commands wait for a shared exclusive lock. `_tick` is nonblocking: when the lifecycle lock is busy, it records a skip event and exits successfully, so the systemd timer creates neither a deadlock nor a failed unit.
- New collector `samples.tsv` files append `qcache_queries_delta`, `interval_seconds`, and `sample_status` to the original 17 columns. Only `sample_status=ok` without `restart_flag` counts as a valid sample. `degraded_interval` means an invalid or excessively long monotonic interval and cannot enter rules/report metrics; the query-cache percentile additionally uses only windows with `qcache_queries_delta > 0`.

## Force

`--force` bypasses only a missing or changed measurement/analysis manifest and the time window. It still requires a manually prepared proposal and state `audited|analyzed|proposed`; it does not bypass live variable validation, Galera, mydumper, backup evidence, writes, validation, or rollback protections.

Force works only on a TTY and requires the exact phrase for the active language:

```text
en: APPLY WITHOUT MEASUREMENTS
sk: APLIKUJ BEZ MERANIA
```

Independent of force, `$STATE/backup-evidence.tsv` must contain `schema`, `status`, `source`, `checked_at`, and `last_success`, be a regular nonsymlink file owned by the current root process, and have mode `0600` or `0400`. `verified` requires `source` and a valid UTC time for the last successful run that is neither in the future nor older than `DBTUNE_MAX_BACKUP_AGE_SECONDS` (default 86400 seconds, including the exact boundary). An existing invalid, future, or expired artifact blocks apply, and the error reports the evaluated `age_seconds` and `max_age_seconds`. `missing` means confirmed absence and blocks apply. A missing artifact or a valid artifact with status `unknown` requires a second, separate TTY phrase for the active language:

```text
en: I CONFIRM A RESTORABLE BACKUP
sk: POTVRDZUJEM OBNOVITELNU ZALOHU
```

The process displays and compares the selected phrase byte-for-byte, without case folding or regular expressions. Safety events store stable confirmation IDs and `ui_lang`, not translated phrases. When measurement is actually missing or invalid, apply history, `apply-report.md`, an existing `report.md`, and `events.log` receive the localized `WITHOUT MEASUREMENTS`/`BEZ MERANIA` marker. Force used only for the time window is recorded in `apply_completed`, but the report is not incorrectly marked as unmeasured.

## Staging and fleet

1. After a successful pilot, deploy to 5 representative servers, one at a time and outside backup windows.
2. Observe them for at least 24 hours. Compare checkout errors, DB CPU/IO, swap, connection peak, wait-free, and log waits.
3. Process the rest of the fleet in batches of at most approximately 10 servers. Do not start the next batch before `verify --post` for the previous batch.
4. Keep the manual RunCloud restart. Check state with `dbtune status`; the command does not query SQL and works during a database outage.

Per-app action steps in the report are copy-paste read-only diagnostics. Before running them, check the `target` (app, path, database, and prefix) and shell quoting. dbtune never runs them automatically; do not perform cleanup, migration, `DELETE`, `DROP`, or `UPDATE` without separate review, a verified restorable backup, and a maintenance plan. The top-autoload section contains only names and sizes. Backup correlation for the worst windows compares available evidence but does not establish causality by itself.

## Rollback

Preferred procedure:

```bash
sudo dbtune rollback
```

When the target was originally absent, rollback moves the deployed regular file into apply history and leaves the target absent. When the original target was regular, it first preserves the deployed file in history and atomically publishes the original snapshot; it neither restores nor follows symlinks. It does not use SQL. If MariaDB is not running, it invokes `systemctl start mariadb`; if MariaDB is running, runtime values do not change without a restart, so it creates `RESTART_REQUIRED` and requests a manual restart through the RunCloud panel. `dbtune status` displays this pending restart.

If filesystem restoration fails, `apply/current` remains on the problematic history, state becomes `recovery_required` or `rollback_failed`, and `dbtune status` prints both `sudo dbtune rollback` and the path to `ROLLBACK.txt`. Neither the pointer nor previous state is blindly reset after a failed apply; they are restored only after a confirmed restore.

If dbtune is unavailable, run the lines from the latest `$STATE/apply/<timestamp>-<pid>/ROLLBACK.txt`. Do not edit `runcloud.cnf`.

## Artifacts and limits

- Apply history is never overwritten. It contains `manifest.tsv` with immutable `cycle_id`, run/audit/proposal and backup-evidence hashes, and configuration-backup provenance; an immutable deployed `proposed.cnf`; a backup-evidence snapshot or interactive-confirmation record; optional `original.cnf`; baseline, validation, and rollback artifacts; and `ROLLBACK.txt`.
- Before the first target change, rollback durably publishes `rollback-intent.tsv`. After interruption, the next locked lifecycle command idempotently completes restore, `ROLLBACK_COMPLETED.tsv`, `apply/last-rollback`, `apply/current`, and state `rolled_back`; it removes the journal only after synchronizing every step. When restoring configuration from an earlier apply cycle, `apply/current` points to that exact cycle, while `apply/last-rollback` and completion metadata preserve the rolled-back cycle, backup used, and hash.
- The first successful `verify --post` stores `post-status.tsv` as the post-restart baseline. Later `verify --post` and `verify --24h` runs evaluate health lifetime counters against this baseline; `--24h` fails without a successful `--post`. If uptime or a counter decreases, the reset baseline is zero. An unchanged nonzero value therefore passes, growth fails, and reset to zero passes. This does not replace the collector's short 60-second deltas or application monitoring.
- Validation capability-probes `mariadbd --validate-config`; on a version without that option, it parses `mariadbd --help --verbose`. It tolerates documented lock/Aria/InnoDB initialization errors from the running server and rejects other `[ERROR]`, unknown, invalid, and value errors.
- Docker integration runs the real `dist/dbtune` against MariaDB 10.6 and 11.4 through audit, short fake-timer collection, analyze, report, propose, apply, container restart, and `verify --post`. Only systemd-in-container is replaced by a minimal stub; the pilot must validate the real systemd timer and production data.
