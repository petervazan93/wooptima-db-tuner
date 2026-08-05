# Plan: Wooptima DB Tuner - MariaDB audit and tuning tool for a RunCloud fleet

## Context

We operate approximately 40 dedicated servers (Hetzner, Ubuntu 22.04/24.04) managed through RunCloud. All host WordPress and WooCommerce stores (databases typically 3-15 GB, MariaDB 10.6-11.x, sometimes 2-3 stores on one server sharing a MariaDB instance). MariaDB runs everywhere on RunCloud defaults (128M buffer pool, `max_connections` 4096, `trxcommit=2`, and so on), which are unsuitable for an ecommerce workload.

Goal: a tool that **audits** each server, **collects** metrics from production traffic (7 days by default), **evaluates** them according to [mariadb-runcloud-preset.md](mariadb-runcloud-preset.md), and **proposes** a personalized configuration plus per-app recommendations, with safe apply/rollback.

**Approved decisions:**
- v1 is standalone per server; the report is also available as flat-key JSON, allowing future fleet aggregation in v2 without rework.
- MariaDB restart is always manual through the RunCloud panel (the tool only provides instructions; the `--restart` flag is for pilot scripting only).

## Tool form

**One standalone Bash script, `dbtune`,** with subcommands, developed as modules (`lib/*.sh`) and joined by the build step into one `dist/dbtune` artifact.

Why Bash (also confirmed by architectural analysis): approximately 90% of the work invokes `mariadb -Nse`, `systemctl`, `lsblk`, and `free`, then formats text; the source Markdown is already Bash-native (1:1 codification means fewer transcription errors); one greppable file can be debugged in place over root SSH across the fleet; there is no runtime skew between Ubuntu 22 and 24.

The discipline that makes Bash safe: all arithmetic through awk (no division in Bash), JSON through one tested emitter only, global `set -u`, mandatory `shellcheck` and `bats`, and library modules containing functions only (no top-level execution). The build is therefore simple concatenation and unit tests can target each module.

- **Deployment:** `scp dist/dbtune server:/usr/local/bin/dbtune` - one file.
- **State and data:** `/var/lib/dbtune/` (mode 700; audit, samples, analyses, reports, apply history, and `events.log`).
- **Output:** English Markdown report and terminal summary by default, explicit Slovak executable output with `DBTUNE_UI_LANG=sk`, plus machine-readable JSON.

## CLI and state machine

```text
dbtune audit [--json]                 # read-only audit, may run at any time
dbtune collect start [--days N]       # default 7; --long-query-time for deep mode
dbtune collect status | stop
dbtune analyze [--min-samples N]      # requires at least approximately 1 day of samples
dbtune report | propose
dbtune apply [--restart] [--force]
dbtune verify --post | --24h
dbtune rollback
dbtune status | version
dbtune _tick                          # internal, invoked by the systemd timer
```

States: `idle -> audited -> collecting -> collected -> analyzed -> proposed -> applied -> verified` (plus `rolled_back`, `recovery_required`, and `rollback_failed`). An invalid command for the current state receives a clear rejection. **Apply without measurement is blocked** ("a preset without measurement is guesswork"). `--force` requires the exact active-language confirmation phrase and marks the report as `WITHOUT MEASUREMENTS`/`BEZ MERANIA`. Apply and force additionally require separate authoritative backup evidence or a second explicit TTY confirmation.

## Language, schema, and release contract

- `DBTUNE_UI_LANG=en|sk` is the public interface selector. Unset or empty means English. Any unsupported non-empty value exits with status 64 before command dispatch. Operating-system locale variables do not select the interface language.
- `collect start` persists the validated language as `ui_lang` in `collect.tsv`; `_tick` restores it before diagnostics and automatic analyze/report execution.
- English force phrase: `APPLY WITHOUT MEASUREMENTS`. Slovak force phrase: `APLIKUJ BEZ MERANIA`.
- English backup phrase: `I CONFIRM A RESTORABLE BACKUP`. Slovak backup phrase: `POTVRDZUJEM OBNOVITELNU ZALOHU`.
- `analysis.tsv` uses the stable eight-column `reason_id` schema. `fleet-v3` JSON contains stable reason/warning IDs, selected language, and localized display text while retaining stable machine keys and enums.
- v0.4.0 never translates or rehashes an old `reason_sk` analysis. Report, propose, and apply fail closed and require a new v0.4.0 audit and measurement cycle; apply history and rollback recovery remain available.
- Current source is the `v0.4.1` release candidate, and the immutable source artifact version is `0.4.1`; publishing the tag and release assets remains a separate release action.

## AUDIT phase (read-only)

- **Hardware:** CPU, RAM, swap, storage (ROTA plus NVMe detection, including md RAID through slave devices), and free space.
- **MariaDB:** version and version gates; effective variables; a **landmine scan** of existing configuration for variables removed by newer versions (`innodb_change_buffering` on 11.x is a critical finding because the server would fail on its next restart; also `innodb_buffer_pool_instances`, `innodb_log_files_in_group`, and others).
- **RunCloud layer:** `runcloud.cnf` values, `skip-log-bin`, query-cache hit rate, `open_files_limit` versus systemd `LimitNOFILE`, unattended-upgrades `MariaDB:` origin, backup (mydumper) frequency, wp-cron setup, `performance_schema`, and Galera detection (which rejects apply).
- **Applications:** `/home/*/webapps/*` WordPress detection, tolerant wp-config parser (define/const/env variants, custom prefix, multisite; fallback through wp-cli if available, otherwise SHOW TABLES), WooCommerce, Redis plus the `object-cache.php` drop-in, and page cache. Non-WordPress applications are marked and their databases are included in sizing.
- **Per database:** dataset, largest tables, `kb_per_row` log detector, autoload, HPOS, sessions, Action Scheduler (including failed actions), transients, and foreign indexes on postmeta.
- **PHP-FPM:** sum of `pm.max_children` across every version and pool (OLS stack produces a warning because formula input is missing).
- **Security mini-check:** bind address, wildcard grants, and a `root.cnf` note. Reports never contain passwords.
- **Root authentication probe:** unix_socket, then `root.cnf` defaults-extra-file; the method is remembered and the password never appears on the command line or in logs.

## COLLECT phase

- **systemd oneshot service and timer** (`OnCalendar=*:0/5`, `Persistent=false`, enabled so collection resumes automatically after reboot). Tick uses `flock` and **always exits 0**; health is tracked in a health file, not a failed unit.
- Every tick is a **60-second two-point delta** (two single SQL round trips for GLOBAL STATUS plus `/proc` mariadbd CPU, `free`, and load average), appended to `samples.tsv`: short-window buffer-pool hit ratio, misses/s, data-read/s, `Handler_read_rnd_next`/s, temporary-disk percentage, Threads_running/connected, query cache and its denominator, log waits, wait free, CPU percentage, RAM/swap, `restart_flag`, actual monotonic interval, and sample status. Rates and CPU use the real interval including SQL/scheduler delay; invalid or excessively long intervals are degraded and excluded by rules. Seven days is approximately 500 KB.
- **Slow log** runtime (`long_query_time=2` in `/var/log/mysql/slow.log` for logrotate coverage). **Self-healing:** tick detects an uptime reset (an unattended-upgrades restart), re-enables the slow log, and records `db_restart_detected`; `restart_flag` lets analyze segment lifetime counters correctly.
- **Daily:** per-database size snapshot in `dbsize.tsv` (growth rate for expansion reserve); disk guards for free space, sample-file size, and a slow log above 2 GB.
- **Automatic stop** after `--days`, followed by automatic `analyze` and `report`, leaving a completed report on the server after one week. The persisted collector language controls unattended diagnostics and the final report.

## ANALYZE phase - rules engine

Uniform contract: every rule emits `rule_id | scope (server/app:X) | severity | verdict | proposed_key/value | evidence | reason_id`. REPORT renders every record through the selected trusted catalog. PROPOSE consumes only server-scope records with `proposed_key`, so report and CNF cannot diverge. The schema is language-neutral and the same analysis hash is used in English and Slovak.

**Server rules** (direct codification of the Markdown): `R-BP-SIZE` (`min((dataset + 6-month growth) x 1.3; RAM x 0.5)`, rounded, growth requires at least 5 daily points, **never proposes reducing** the existing pool, MemAvailable guard), `R-MAXCONN` (`max(sum(pm.max_children) x 1.25 + 20; 100)` plus a measured-peak cross-check), `R-IO-CAP` (NVMe/SSD/HDD classes plus flush_neighbors gate), `R-LOG-FILE`/`R-LOG-BUF` (512M/1G; 64M log buffer only if measured log_waits > 0), `R-QCACHE` (the exact matrix from the Markdown: hit rate x Threads_running p95, never blanket-disable), `R-TRXCOMMIT` (=1 required because of skip-log-bin), `R-PINNED` (O_DIRECT, dirty pct/lwm, lock_wait_timeout=30, skip_name_resolve, tmp 64M with a LONGTEXT note, and so on), `R-MYISAM`, `R-SLOWLOG`, `R-UNATT` (blacklist recommendation), `R-OPENFILES`, `R-SEC`, and `R-BACKUP`.

**Version gates have two layers:** (1) a static gate table for families 10.6, 10.11, and 11.x (for example, change_buffering removed in 11.0, dynamic log_file_size since 10.9, dynamic io_threads since 10.11, query cache throughout the supported range, and flush_method deprecated in 11.x; mariadb/mysql binary-name fallback), and (2) **live authoritative validation** of every variable name against `information_schema.GLOBAL_VARIABLES` before apply.

**Per-app findings with severity** (recommendations only; the tool never writes to WordPress databases):
- *critical:* missing object cache (distinguishing Redis down from missing drop-in); wp-cron completely disabled
- *high:* autoload above 3 MB (plus top 20), HPOS disabled with orders in postmeta, log tables above 20 `kb_per_row`
- *medium:* autoload 1-3 MB, HPOS compatibility sync causing duplicate writes, failed Action Scheduler actions, rogue meta_value index, Redis eviction policy
- *low:* Action Scheduler retention 30d to 7d (explicitly not 1d)

The report retains the source document's philosophy: the "application layer - solve first" section appears before the database configuration proposal.

## REPORT and PROPOSE

- **Executive summary** (top actions by impact), then **server section** (hardware, workload profile with percentiles, worst windows, and backup correlation; proposed configuration as a **diff against current effective values** with per-value reasons), then **per-app sections** (findings plus copy-paste SQL/wp-cli steps).
- `proposed-99-zz-tuning.cnf` is rendered from the template (Step 2 of the Markdown), alongside `report.json` using schema `fleet-v3`.
- Machine consumers use stable IDs, keys, enums, and canonical proposal records. Localized CNF comments can make `proposal_hash` language-specific, but `proposal_records_hash`, proposal keys, and proposal values stay language-neutral.

## APPLY / VERIFY / ROLLBACK - defense in depth

1. Before writing, validate variable names against live `information_schema`.
2. Write **only** `/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf` (`runcloud.cnf` is never touched), then run capability-probed `mariadbd --validate-config` with the parser from the Markdown (it ignores lock errors from the running server). Validation uses a `root:mysql` mode `0710` parent; root-owned mode `0600` probe and output logs stay outside the only mysql-writable path, a dedicated `mysql:mysql` mode `0700` datadir.
3. Guard the unattended-upgrades window (reject apply from 05:30 to 07:30 without `--force`) and check the process list for a running mydumper backup before restart instructions.
4. Restart is decoupled: apply prints exact RunCloud panel instructions and expectations (a longer first start after a redo-log change), plus **`ROLLBACK.txt` with literal commands** so recovery does not require the tool itself.
5. `rollback` is a filesystem-only operation (mv plus systemctl start), without SQL, and works while the database is down.
6. `verify --post` checks no growth in wait_free, log_waits, or aborted relative to a reset-aware baseline, stable swap, and stores the post-restart baseline. `verify --24h` compares against the successful post-restart baseline.

## Repository structure and tests

```text
lib/00-header ... 90-main.sh   # numbered modules, functions only
templates/tuning.cnf.tmpl      # Step 2 from the Markdown with placeholders
build.sh + Makefile            # concatenation, embedded templates/units, bash -n, shellcheck, sha256
test/stubs/                    # fake mariadb, systemctl, lsblk, free, and others
test/fixtures/                 # captured GLOBAL STATUS/VARIABLES for 10.6 and 11.4, wp-config variants,
                               # RunCloud configurations, FPM pools, lsblk profiles, synthetic 7-day samples
test/unit/*.bats               # formulas, query-cache matrix, version gates, delta math, parser, state machine
test/integration/              # docker-compose with MariaDB 10.6 and 11.4 plus Ubuntu SUT, seeded WP/Woo schema,
                               # fake-timer tick loop (systemd-in-docker skipped on macOS), complete lifecycle
docs/RUNBOOK.md
```

## Implementation sequence

1. Repository skeleton, build pipeline, state machine, and utility/log/SQL layer
2. Audit module (detection, applications, and per-database data)
3. Collector (systemd, tick, self-healing, and guards)
4. Rules engine and version gates (the core of the tool)
5. Report and proposal
6. Apply, verify, and rollback
7. Tests (fixtures, Bats, and Docker harness), continuously alongside modules
8. RUNBOOK: pilot on 1-2 servers (one per MariaDB family, with verified backups), stage 5 servers, then process the rest of the fleet in batches of approximately 10, always applying manually per server

After the skeleton, modules 2-5 can be developed in parallel with final integration and review.

## Verification

- Clean `shellcheck`, green `bats` against fixtures for both MariaDB families, and validated emitted JSON.
- Docker harness: full lifecycle from audit through ticks, analyze, report, propose, CNF validation in the database container, apply, restart, and `verify --post`, in English and Slovak with equivalent proposal keys and values.
- Real pilot: one fleet server, comparing the audit with manual measurements from the reference store in the Markdown.

## Out of scope for v1

- Central fleet aggregation (v2; JSON reports are ready)
- Automatic application-layer fixes (Redis installation, autoload cleanup, HPOS migration); only recommendations with instructions
- Galera setups (apply rejects them)
