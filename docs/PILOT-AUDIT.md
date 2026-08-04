# Audit-only pilot on one RunCloud server

## Scope

The pilot performs only a one-time read-only audit of MariaDB, the operating system, and WordPress applications. It creates only a directory containing the binary and state files under `/var/lib/dbtune` with modes `700/600` on the server.

Forbidden in this phase:

- `collect start`
- `analyze`, `report`, and `propose`
- `apply`, MariaDB restart, and `rollback`
- any changes to `runcloud.cnf`, WordPress databases, or application files

The interface defaults to English. To run the executable interface in Slovak, set `DBTUNE_UI_LANG=sk` explicitly. This selection changes human-readable output only; commands, paths, machine keys, audit classifications, and exit statuses remain unchanged.

## Entry gates

Do not start the audit until all conditions hold:

- the target is Ubuntu 22.04 or 24.04 with MariaDB 10.6, 10.11, or 11.x,
- MariaDB is `active` and the server has no active incident,
- the server is not a Galera/wsrep node,
- mydumper, mysqldump, and RunCloud backup are not running,
- `/` and `/var/lib/mysql` each have at least 1 GB free,
- the audit runs outside checkout peaks and scheduled backup windows,
- RunCloud panel access is available; the audit does not use restart.

## Local artifact verification

```bash
make check
make test
(cd dist && shasum -a 256 -c dbtune.sha256)
```

## Read-only preflight

`SERVER` is an SSH alias, hostname, or IP address. Do not send a password or private key in the command or chat.

```bash
ssh root@SERVER 'uname -a; . /etc/os-release; printf "%s %s\n" "$ID" "$VERSION_ID"; mariadb --version; systemctl is-active mariadb; df -Pk / /var/lib/mysql; pgrep -af "mydumper|mysqldump|mariadb-dump" || true'
```

Stop the pilot if MariaDB is not active, a backup is running, or space is insufficient.

## Upload without installing into PATH

```bash
ssh root@SERVER 'install -d -o root -g root -m 700 /root/dbtune-pilot'
scp dist/dbtune dist/dbtune.sha256 root@SERVER:/root/dbtune-pilot/
ssh root@SERVER '(cd /root/dbtune-pilot && sha256sum -c dbtune.sha256) && chmod 700 /root/dbtune-pilot/dbtune'
```

## The only permitted run

GNU `timeout` terminates the entire audit if it exceeds 15 minutes. JSON is captured locally; stderr remains visible to the operator.

The audit query budget is 5 seconds for connection and 5 seconds of `max_statement_time` for each read-only SQL statement. Exact full-table counts are disabled; large-table sizes and counts use metadata estimates, and selective WordPress queries remain under the same statement budget. A timeout or SQL failure must appear in TSV as `unknown` and `audit_error.*`, not as zero. Every application has a canonical `audit_status` (`complete`, `partial`, `failed`) and `source_error`; only `complete` without a source error allows an absent finding to be interpreted as verified empty. Effective values are stored in `audit.sql_connect_timeout_seconds`, `audit.sql_statement_timeout_seconds`, and `audit.exact_full_table_counts`.

An authoritative result requires complete `mariadb`, `hardware`, `applications`, and `security` sections. `PASS` is a complete audit without findings, `FINDINGS` is a complete audit with findings, `UNKNOWN` means missing required evidence in one or more sections, and `ERROR` means every required section failed. A classified audit returns `0` for `PASS`/`FINDINGS`, `2` for `UNKNOWN`, and `1` for `ERROR`. Usage, validation, dependency, and other technical failures may use existing exit statuses `64+`; automation must not interpret them as audit classifications. JSON is written even before returning `2` or a classified `1`, so the shell wrapper must capture exit status without discarding output and must stop the pilot on a nonzero status.

The MariaDB section additionally validates a versioned minimum schema for every current value that can enter a server rule or proposal. A missing, `unknown`, malformed, conflicting, or version-invalid required key means `UNKNOWN`; exact keys without values appear in `audit.section.mariadb.missing_evidence`, `invalid_evidence`, and `conflicting_evidence`. On MariaDB 11.x, deprecated `innodb_flush_method` appears explicitly in `optional_evidence` rather than being presented as a required proposal input.

```bash
install -d -m 700 pilot-artifacts
set +e
ssh root@SERVER 'timeout --signal=TERM 15m /root/dbtune-pilot/dbtune audit --json' >pilot-artifacts/audit.json
audit_status=$?
set -e
printf 'dbtune audit exit status: %s\n' "$audit_status"
scp root@SERVER:/var/lib/dbtune/audit.tsv pilot-artifacts/
scp root@SERVER:/var/lib/dbtune/apps.tsv pilot-artifacts/
scp root@SERVER:/var/lib/dbtune/databases.tsv pilot-artifacts/
scp root@SERVER:/var/lib/dbtune/events.log pilot-artifacts/
test "$audit_status" -eq 0
```

## Stop conditions during the audit

Immediately terminate the audit with `Ctrl-C` if:

- load or IO wait increases and affects the store,
- a backup starts,
- MariaDB stops responding,
- checkout or HTTP 5xx errors appear,
- the audit exceeds 15 minutes.

Do not run another subcommand after termination. Evaluate the local artifacts and landmine/security findings first.

## Cleanup

The binary may remain in the root-only directory until a decision is made. If the pilot is stopped:

```bash
ssh root@SERVER 'rm -rf /root/dbtune-pilot'
```

Run cleanup only after downloading the required audit artifacts. This default cleanup intentionally leaves `/var/lib/dbtune` untouched because it may contain apply or recovery history from before the pilot. Do not remove that state directory unless you have independently proved that this pilot created it from an absent path and that it contains no apply or recovery history.
