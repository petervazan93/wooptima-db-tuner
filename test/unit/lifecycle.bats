#!/usr/bin/env bats

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_CONFIG_TARGET="$BATS_TEST_TMPDIR/etc/99-zz-tuning.cnf"
    export DBTUNE_LOG_LEVEL=error
    export DBTUNE_MIN_APPLY_SAMPLES=1
    export DBTUNE_SQL_AUTH_METHOD=socket
    export DBTUNE_FLOCK=fake_flock
    export DBTUNE_RACE_LOCK_DIR="$BATS_TEST_TMPDIR/lifecycle-held"
    export STUB_TIME=1200
    export STUB_WSREP_ON=OFF
    export STUB_WSREP_ADDRESS=
    export STUB_MYDUMPER=0
    export STUB_VALIDATE_STATUS=0
    export STUB_VALIDATE_OUTPUT=
    export STUB_RESTART_FAIL=0
    export STUB_SERVICE_ACTIVE=1
    export STUB_GLOBAL_NAMES=$'max_connections\nskip_name_resolve'
    export STUB_EFFECTIVE=$'max_connections\t300\nskip_name_resolve\tON'
    export STUB_STATUS=$'uptime\t100\ninnodb_buffer_pool_wait_free\t0\ninnodb_log_waits\t0\naborted_connects\t0'
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$DBTUNE_STATE_DIR" "${DBTUNE_CONFIG_TARGET%/*}"
    make_stubs
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/60-lifecycle.sh"
    source "$BATS_TEST_DIRNAME/../../lib/50-report.sh"
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
    printf 'audit.hostname\ttest\n' >"$DBTUNE_STATE_DIR/audit.tsv"
    : >"$DBTUNE_STATE_DIR/apps.tsv"
    : >"$DBTUNE_STATE_DIR/databases.tsv"
    printf 'rule_id\tscope\tseverity\tverdict\tproposed_key\tproposed_value\tevidence\treason_sk\n' >"$DBTUNE_STATE_DIR/analysis.tsv"
    printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\n' >"$DBTUNE_STATE_DIR/samples.tsv"
    printf '2026-07-31T12:00:00Z\t100\t99\t0\t0\t0\t0\t1\t1\t30\t0\t0\t1\t1000\t0\t1\t0\n' >>"$DBTUNE_STATE_DIR/samples.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        lifecycle-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    dbtune_provenance_write_analysis_manifest "$DBTUNE_STATE_DIR/analysis-manifest.tsv" \
        "$DBTUNE_STATE_DIR/analysis.tsv" "$DBTUNE_STATE_DIR/samples.tsv"
    printf 'proposed\n' >"$DBTUNE_STATE_DIR/state"
    write_proposal
    write_manifest
}

fake_flock() {
    case $1 in
        -n) mkdir "$DBTUNE_RACE_LOCK_DIR" 2>/dev/null ;;
        -x)
            while ! mkdir "$DBTUNE_RACE_LOCK_DIR" 2>/dev/null; do
                sleep 0.01
            done
            ;;
        -u) rmdir "$DBTUNE_RACE_LOCK_DIR" 2>/dev/null || true ;;
    esac
}

file_mode() {
    if [[ $(uname -s) == Darwin ]]; then
        stat -f '%Lp' "$1"
    else
        stat -c '%a' "$1"
    fi
}

bats::on_failure() {
    printf '%s\n' "${output:-}" >&3
}

make_stubs() {
    cat >"$BATS_TEST_TMPDIR/bin/mariadb" <<'STUB'
#!/usr/bin/env bash
query=$(cat)
case $query in
    *"SELECT LOWER(VARIABLE_NAME) FROM information_schema.GLOBAL_VARIABLES"*) printf '%s\n' "$STUB_GLOBAL_NAMES" ;;
    *"WSREP_ON"*) printf '%s\t%s\n' "$STUB_WSREP_ON" "$STUB_WSREP_ADDRESS" ;;
    *"information_schema.PROCESSLIST"*) printf '%s\n' "$STUB_MYDUMPER" ;;
    *"LOWER(VARIABLE_NAME), VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES"*) printf '%s\n' "$STUB_EFFECTIVE" ;;
    *"information_schema.GLOBAL_STATUS"*) printf '%s\n' "$STUB_STATUS" ;;
    *) exit 2 ;;
esac
STUB
    cat >"$BATS_TEST_TMPDIR/bin/mariadbd" <<'STUB'
#!/usr/bin/env bash
case " $* " in
    *" --help --verbose "*) printf '%s\n' '  --validate-config' ;;
    *" --validate-config "*) printf '%s\n' "$STUB_VALIDATE_OUTPUT"; exit "$STUB_VALIDATE_STATUS" ;;
    *) exit 2 ;;
esac
STUB
    cat >"$BATS_TEST_TMPDIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DBTUNE_STATE_DIR/systemctl.log"
if [[ $1 == restart && $STUB_RESTART_FAIL == 1 ]]; then exit 1; fi
if [[ $1 == is-active && ($STUB_RESTART_FAIL == 1 || $STUB_SERVICE_ACTIVE == 0) ]]; then exit 3; fi
exit 0
STUB
    cat >"$BATS_TEST_TMPDIR/bin/date" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "+%H%M") printf '%s\n' "$STUB_TIME" ;;
    "-u +%Y%m%dT%H%M%SZ") printf '%s\n' '20260731T120000Z' ;;
    "-u +%Y-%m-%dT%H:%M:%SZ") printf '%s\n' '2026-07-31T12:00:00Z' ;;
    *) /bin/date "$@" ;;
esac
STUB
    cat >"$BATS_TEST_TMPDIR/bin/chown" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat >"$BATS_TEST_TMPDIR/bin/free" <<'STUB'
#!/usr/bin/env bash
cat <<'OUT'
              total        used        free      shared  buff/cache   available
Mem:          16000        8000        1000         100        7000        7000
Swap:          2000           0        2000
OUT
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/mariadb" "$BATS_TEST_TMPDIR/bin/mariadbd" \
        "$BATS_TEST_TMPDIR/bin/systemctl" "$BATS_TEST_TMPDIR/bin/date" "$BATS_TEST_TMPDIR/bin/chown" \
        "$BATS_TEST_TMPDIR/bin/free"
}

write_proposal() {
    cat >"$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" <<'CNF'
[mysqld]
max-connections = 300
skip_name_resolve = 1
CNF
}

write_manifest() {
    local analysis_manifest="$DBTUNE_STATE_DIR/analysis-manifest.tsv"

    dbtune_provenance_write_analysis_manifest "$analysis_manifest" \
        "$DBTUNE_STATE_DIR/analysis.tsv" "$DBTUNE_STATE_DIR/samples.tsv"
    {
        printf 'schema\t1\n'
        printf 'run_id\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" run_id)"
        printf 'audit_hash\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" audit_hash)"
        printf 'samples_hash\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" samples_hash)"
        printf 'analysis_hash\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" analysis_hash)"
        printf 'proposal_hash\t%s\n' "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf")"
    } >"$DBTUNE_STATE_DIR/proposal-manifest.tsv"
}

@test "apply rejects an unknown live variable before writing" {
    export STUB_GLOBAL_NAMES=max_connections
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"skip_name_resolve"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply rejects a proposal changed after manifest creation" {
    printf '# tampered\n' >>"$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"sa zmenil"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "validation failure immediately restores the original target" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export STUB_VALIDATE_OUTPUT="[ERROR] mariadbd: unknown variable 'bad=1'"
    export STUB_VALIDATE_STATUS=1
    run cmd_apply
    [ "$status" -eq 65 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(cat "$DBTUNE_STATE_DIR/state")" = proposed ]
}

@test "validation parser ignores benign invalid words in help output" {
    output_file="$BATS_TEST_TMPDIR/help.log"
    printf '%s\n' 'attempts due to invalid password' 'NO_ZERO_DATE, ALLOW_INVALID_DATES' 'query-cache-wlock-invalidate FALSE' >"$output_file"
    run dbtune_lifecycle_validation_output_ok "$output_file"
    [ "$status" -eq 0 ]
}

@test "apply rejects Galera without touching the target" {
    export STUB_WSREP_ON=ON
    run cmd_apply
    [ "$status" -eq 65 ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply rejects critical version and missing-backup findings" {
    printf 'R-VERSION\tserver\tcritical\tREMOVED\t\t\tinnodb_change_buffering\tOdstranena premenna\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    printf 'R-BACKUP\tserver\tcritical\tMISSING\t\t\tbackup unknown\tZaloha nie je potvrdena\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    write_manifest
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"R-VERSION"* ]]
    [[ "$output" == *"R-BACKUP"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "restart failure restores config and starts MariaDB" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export STUB_RESTART_FAIL=1
    run cmd_apply --restart
    [ "$status" -ne 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    grep -Fx 'start mariadb' "$DBTUNE_STATE_DIR/systemctl.log"
    [ "$(cat "$DBTUNE_STATE_DIR/state")" = proposed ]
}

@test "rollback is filesystem-first and marks a required RunCloud restart" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    run cmd_apply
    [ "$status" -eq 0 ]
    [ "$(cat "$DBTUNE_STATE_DIR/state")" = applied ]
    rm "$BATS_TEST_TMPDIR/bin/mariadb"

    run cmd_rollback
    [ "$status" -eq 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(cat "$DBTUNE_STATE_DIR/state")" = rolled_back ]
    [[ "$output" == *"RunCloud"* ]]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ -s "$history/RESTART_REQUIRED" ]
}

@test "rollback starts MariaDB when the service is down" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    export STUB_SERVICE_ACTIVE=0
    run cmd_rollback
    [ "$status" -eq 0 ]
    grep -Fx 'start mariadb' "$DBTUNE_STATE_DIR/systemctl.log"
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ ! -e "$history/RESTART_REQUIRED" ]
}

@test "unattended-upgrades window blocks apply without force" {
    export STUB_TIME=0610
    run cmd_apply
    [ "$status" -eq 75 ]
    [[ "$output" == *"05:30"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "force is rejected when stdin is not a TTY" {
    rm "$DBTUNE_STATE_DIR/samples.tsv" "$DBTUNE_STATE_DIR/analysis.tsv"
    run cmd_apply --force
    [ "$status" -eq 77 ]
    [[ "$output" == *"TTY"* ]]
}

@test "apply and verify post preserve lifecycle artifacts" {
    run cmd_apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"RunCloud"* ]]
    [ "$(file_mode "$DBTUNE_CONFIG_TARGET")" = 644 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ "$(dbtune_lifecycle_manifest_value "$history" run_id)" = lifecycle-run ]
    [ "$(dbtune_lifecycle_manifest_value "$history" proposal_hash)" = \
        "$(dbtune_sha256_file "$history/proposed.cnf")" ]

    run cmd_verify --post
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK max_connections=300"* ]]
    [ "$(cat "$DBTUNE_STATE_DIR/state")" = verified ]
}

@test "verify 24h compares current counters with apply baseline" {
    cmd_apply >/dev/null
    run cmd_verify --24h
    [ "$status" -eq 0 ]
    [[ "$output" == *$'METRIC\tBASELINE\tCURRENT\tDELTA_OR_RESET'* ]]
    [[ "$output" == *$'uptime\t100\t100\t0'* ]]
}

@test "status is filesystem-only and works without mariadb" {
    rm "$BATS_TEST_TMPDIR/bin/mariadb"
    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"state: proposed"* ]]
    [[ "$output" == *"config_present: nie"* ]]
}

@test "paused apply deploys its verified snapshot and serializes concurrent propose" {
    local apply_pid propose_pid propose_status=0
    cp "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" "$BATS_TEST_TMPDIR/expected.cnf"
    dbtune_lifecycle_after_manifest_check() {
        touch "$BATS_TEST_TMPDIR/apply-paused"
        while [[ ! -e $BATS_TEST_TMPDIR/apply-release ]]; do
            sleep 0.01
        done
    }

    dbtune_dispatch apply >"$BATS_TEST_TMPDIR/apply.out" 2>&1 &
    apply_pid=$!
    for _ in {1..200}; do
        [[ -e $BATS_TEST_TMPDIR/apply-paused ]] && break
        sleep 0.01
    done
    [ -e "$BATS_TEST_TMPDIR/apply-paused" ]

    dbtune_dispatch propose >"$BATS_TEST_TMPDIR/propose.out" 2>&1 &
    propose_pid=$!
    sleep 0.1
    kill -0 "$propose_pid"
    printf '# external mutable change after manifest check\n' >>"$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    touch "$BATS_TEST_TMPDIR/apply-release"
    wait "$apply_pid"
    wait "$propose_pid" || propose_status=$?

    [ "$propose_status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/expected.cnf" "$DBTUNE_CONFIG_TARGET"
    [ "$(dbtune_state_read)" = applied ]
}
