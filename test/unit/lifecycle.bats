#!/usr/bin/env bats

setup() {
    unset DBTUNE_UI_LANG
    BATS_TEST_TMPDIR=$(CDPATH='' cd -- "$BATS_TEST_TMPDIR" && pwd -P)
    export BATS_TEST_TMPDIR
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_CONFIG_TARGET="$BATS_TEST_TMPDIR/etc/99-zz-tuning.cnf"
    export DBTUNE_CONFIG_ALLOWED_DIR="$BATS_TEST_TMPDIR/etc"
    export DBTUNE_LOG_LEVEL=error
    export DBTUNE_MIN_APPLY_SAMPLES=1
    export DBTUNE_SQL_AUTH_METHOD=socket
    export DBTUNE_BACKUP_EVIDENCE_UID
    DBTUNE_BACKUP_EVIDENCE_UID=$(id -u)
    export DBTUNE_NOW_EPOCH=1785499200
    export DBTUNE_MAX_BACKUP_AGE_SECONDS=86400
    export DBTUNE_FLOCK=fake_flock
    export DBTUNE_SYNC=true
    unset DBTUNE_FAULT_INJECT
    export DBTUNE_RACE_LOCK_DIR="$BATS_TEST_TMPDIR/lifecycle-held"
    export STUB_TIME=1200
    export STUB_WSREP_ON=OFF
    export STUB_WSREP_ADDRESS=
    export STUB_MYDUMPER=0
    export STUB_VALIDATE_STATUS=0
    export STUB_VALIDATE_OUTPUT=
    export STUB_RESTART_FAIL=0
    export STUB_START_FAIL=0
    export STUB_SERVICE_ACTIVE=1
    export STUB_FAIL_CP_MATCH=
    export STUB_FAIL_MV_MATCH=
    export STUB_FAIL_CHOWN_MATCH=
    export STUB_FAIL_CHMOD_MATCH=
    export STUB_FAIL_MKDIR_MATCH=
    export STUB_HELP_HAS_VALIDATE_CONFIG=1
    export STUB_DEFAULTS_OUTPUT=
    export STUB_DEFAULTS_ERROR=
    export STUB_DEFAULTS_STATUS=0
    unset DBTUNE_PUBLISH_FAIL_MATCH
    unset DBTUNE_PUBLISH_FAULT_HOOK
    unset DBTUNE_PUBLISH_CRASH_POINT
    unset DBTUNE_PUBLISH_CRASH_MATCH
    export STUB_GLOBAL_NAMES=$'max_connections\nskip_name_resolve'
    export STUB_GLOBAL_STATUS=0
    export STUB_EFFECTIVE=$'max_connections\t300\nskip_name_resolve\tON'
    export STUB_STATUS=$'uptime\t100\ninnodb_buffer_pool_wait_free\t0\ninnodb_log_waits\t0\naborted_connects\t0'
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$DBTUNE_STATE_DIR" "${DBTUNE_CONFIG_TARGET%/*}"
    chmod 700 "$DBTUNE_STATE_DIR"
    make_stubs
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/05-i18n.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/15-mariadb-safety.sh"
    source "$BATS_TEST_DIRNAME/../../lib/20-audit.sh"
    source "$BATS_TEST_DIRNAME/../../lib/60-lifecycle.sh"
    source "$BATS_TEST_DIRNAME/../../lib/50-report.sh"
    source "$BATS_TEST_DIRNAME/../support/bats-fd-hygiene.bash"
    dbtune_i18n_set en
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
    export DBTUNE_CONFIG_UID
    export DBTUNE_CONFIG_GID
    DBTUNE_CONFIG_UID=$(id -u)
    DBTUNE_CONFIG_GID=$(id -g)
    write_backup_evidence verified
    cat >"$DBTUNE_STATE_DIR/audit.tsv" <<'EOF'
audit.hostname	test
mariadb.variable.max_connections	200
mariadb.variable.skip_name_resolve	OFF
landmine.scan.status	complete
landmine.scan.method	mariadbd_print_defaults
EOF
    : >"$DBTUNE_STATE_DIR/apps.tsv"
    : >"$DBTUNE_STATE_DIR/databases.tsv"
    cat >"$DBTUNE_STATE_DIR/analysis.tsv" <<'EOF'
rule_id	scope	severity	verdict	proposed_key	proposed_value	evidence	reason_id
R-MAXCONN	server	high	CHANGE	max_connections	300	current=200	reason_max_connections_change
R-PINNED	server	medium	CHANGE	skip_name_resolve	1	current=OFF	reason_skip_name_resolve
EOF
    printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tcom_select_delta\tinterval_seconds\tsample_status\n' >"$DBTUNE_STATE_DIR/samples.tsv"
    printf '2026-07-31T12:00:00Z\t100\t99\t0\t0\t0\t0\t1\t1\t30\t0\t0\t1\t1000\t0\t1\t0\t1\t60\tok\n' >>"$DBTUNE_STATE_DIR/samples.tsv"
    printf 'timestamp\tdatabase\tsize_bytes\n' >"$DBTUNE_STATE_DIR/dbsize.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        lifecycle-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    dbtune_provenance_write_analysis_manifest "$DBTUNE_STATE_DIR/analysis-manifest.tsv" \
        "$DBTUNE_STATE_DIR/analysis.tsv" "$DBTUNE_STATE_DIR/samples.tsv" "$DBTUNE_STATE_DIR/dbsize.tsv"
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
printf '%s\n' "$query" >>"$BATS_TEST_TMPDIR/sql.log"
case $query in
    *"SELECT LOWER(VARIABLE_NAME) FROM information_schema.GLOBAL_VARIABLES"*)
        [[ $STUB_GLOBAL_NAMES == __NO_OUTPUT__ ]] || printf '%s\n' "$STUB_GLOBAL_NAMES"
        exit "$STUB_GLOBAL_STATUS"
        ;;
    *"WSREP_ON"*) printf '%s\t%s\n' "$STUB_WSREP_ON" "$STUB_WSREP_ADDRESS" ;;
    *"information_schema.PROCESSLIST"*) printf '%s\n' "$STUB_MYDUMPER" ;;
    *"LOWER(VARIABLE_NAME), VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES"*) printf '%s\n' "$STUB_EFFECTIVE" ;;
    *"information_schema.GLOBAL_STATUS"*) printf '%s\n' "$STUB_STATUS" ;;
    *) exit 2 ;;
esac
STUB
    cat >"$BATS_TEST_TMPDIR/bin/mariadbd" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/mariadbd.log"
case " $* " in
    *" --version "*) printf '%s\n' 'mariadbd  Ver 15.1 Distrib 11.4.12-MariaDB' ;;
    *" --print-defaults "*)
        printf '%s\n' scan >>"$BATS_TEST_TMPDIR/landmine-scan.log"
        [[ -z $STUB_DEFAULTS_OUTPUT ]] || printf '%b' "$STUB_DEFAULTS_OUTPUT"
        [[ -z $STUB_DEFAULTS_ERROR ]] || printf '%b' "$STUB_DEFAULTS_ERROR" >&2
        exit "$STUB_DEFAULTS_STATUS"
        ;;
    *" --help --verbose "*)
        if [[ $STUB_HELP_HAS_VALIDATE_CONFIG == 1 ]]; then
            printf '%s\n' '  --validate-config'
        else
            printf '%s\n' 'MariaDB server help'
        fi
        ;;
    *" --validate-config "*) printf '%s\n' "$STUB_VALIDATE_OUTPUT"; exit "$STUB_VALIDATE_STATUS" ;;
    *) exit 2 ;;
esac
STUB
    cat >"$BATS_TEST_TMPDIR/bin/chmod" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/chmod.log"
if [[ -n $STUB_FAIL_CHMOD_MATCH && " $* " == *"$STUB_FAIL_CHMOD_MATCH"* ]]; then
    exit 1
fi
exec /bin/chmod "$@"
STUB
    cat >"$BATS_TEST_TMPDIR/bin/mkdir" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/mkdir.log"
if [[ -n $STUB_FAIL_MKDIR_MATCH && " $* " == *"$STUB_FAIL_MKDIR_MATCH"* ]]; then
    exit 1
fi
exec /bin/mkdir "$@"
STUB
    cat >"$BATS_TEST_TMPDIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DBTUNE_STATE_DIR/systemctl.log"
if [[ $1 == restart && $STUB_RESTART_FAIL == 1 ]]; then exit 1; fi
if [[ $1 == start && $STUB_START_FAIL == 1 ]]; then exit 1; fi
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
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/chown.log"
if [[ -n $STUB_FAIL_CHOWN_MATCH && " $* " == *"$STUB_FAIL_CHOWN_MATCH"* ]]; then
    exit 1
fi
if [[ ${STUB_CHOWN_SYMLINK_ATTACK:-0} == 1 && $1 == mysql:mysql ]]; then
    target=${@: -1}
    ln -sf "$STUB_VALIDATE_HELP_VICTIM" "$target/help.log"
    ln -sf "$STUB_VALIDATE_OUTPUT_VICTIM" "$target/output.log"
fi
exit 0
STUB
    cat >"$BATS_TEST_TMPDIR/bin/cp" <<'STUB'
#!/usr/bin/env bash
if [[ -n $STUB_FAIL_CP_MATCH && " $* " == *"$STUB_FAIL_CP_MATCH"* && ! -e $DBTUNE_STATE_DIR/.cp-failed ]]; then
    touch "$DBTUNE_STATE_DIR/.cp-failed"
    exit 1
fi
exec /bin/cp "$@"
STUB
    cat >"$BATS_TEST_TMPDIR/bin/mv" <<'STUB'
#!/usr/bin/env bash
if [[ -n $STUB_FAIL_MV_MATCH && " $* " == *"$STUB_FAIL_MV_MATCH"* && ! -e $DBTUNE_STATE_DIR/.mv-failed ]]; then
    touch "$DBTUNE_STATE_DIR/.mv-failed"
    exit 1
fi
exec /bin/mv "$@"
STUB
    cat >"$BATS_TEST_TMPDIR/bin/free" <<'STUB'
#!/usr/bin/env bash
cat <<'OUT'
              total        used        free      shared  buff/cache   available
Mem:          16000        8000        1000         100        7000        7000
Swap:          2000           0        2000
OUT
STUB
    /bin/chmod +x "$BATS_TEST_TMPDIR/bin/mariadb" "$BATS_TEST_TMPDIR/bin/mariadbd" \
        "$BATS_TEST_TMPDIR/bin/systemctl" "$BATS_TEST_TMPDIR/bin/date" "$BATS_TEST_TMPDIR/bin/chown" \
        "$BATS_TEST_TMPDIR/bin/chmod" "$BATS_TEST_TMPDIR/bin/mkdir" "$BATS_TEST_TMPDIR/bin/cp" \
        "$BATS_TEST_TMPDIR/bin/mv" "$BATS_TEST_TMPDIR/bin/free"
    hash -r
}

write_backup_evidence() {
    local status=${1:-verified}
    local success=${2:-2026-07-31T11:00:00Z}
    local checked=${3:-2026-07-31T11:30:00Z}

    [[ $status != missing ]] || success=none
    [[ $status != unknown ]] || success=unknown
    {
        printf 'schema\t1\n'
        printf 'status\t%s\n' "$status"
        printf 'source\tunit-test-backup-api\n'
        printf 'checked_at\t%s\n' "$checked"
        printf 'last_success\t%s\n' "$success"
    } >"$(dbtune_backup_evidence_file)"
    chmod 600 "$(dbtune_backup_evidence_file)"
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
    local proposal_records_hash

    dbtune_provenance_write_analysis_manifest "$analysis_manifest" \
        "$DBTUNE_STATE_DIR/analysis.tsv" "$DBTUNE_STATE_DIR/samples.tsv" "$DBTUNE_STATE_DIR/dbsize.tsv"
    DBTUNE_AUDIT_FILE="$DBTUNE_STATE_DIR/audit.tsv"
    dbtune_analysis_load "$DBTUNE_STATE_DIR/analysis.tsv"
    dbtune_proposals_load "$DBTUNE_AUDIT_FILE"
    proposal_records_hash=$(dbtune_proposal_records_hash)
    {
        printf 'schema\t1\n'
        printf 'run_id\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" run_id)"
        printf 'audit_hash\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" audit_hash)"
        printf 'samples_hash\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" samples_hash)"
        printf 'analysis_hash\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" analysis_hash)"
        printf 'analysis_fingerprint\t%s\n' "$(dbtune_manifest_value "$analysis_manifest" analysis_fingerprint)"
        printf 'proposal_count\t%s\n' "${#DBTUNE_PROPOSAL_LINES[@]}"
        printf 'proposal_records_hash\t%s\n' "$proposal_records_hash"
        printf 'proposal_hash\t%s\n' "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf")"
    } >"$DBTUNE_STATE_DIR/proposal-manifest.tsv"
}

assert_apply_preflight_unchanged() {
    local expected_state=${1:-proposed}

    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = 'original target' ]
    [ "$(dbtune_state_read)" = "$expected_state" ]
    [ ! -e "$DBTUNE_STATE_DIR/apply/current" ]
    [ ! -e "$DBTUNE_STATE_DIR/apply" ]
    ! compgen -G "$DBTUNE_STATE_DIR/.apply-*" >/dev/null
}

reset_apply_preflight_fixture() {
    rm -rf "$DBTUNE_STATE_DIR/apply" "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    rm -f "$DBTUNE_STATE_DIR"/.apply-* "$BATS_TEST_TMPDIR/sql.log" "$BATS_TEST_TMPDIR/confirmation.log" \
        "$BATS_TEST_TMPDIR/publisher-replaced"
    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    printf 'proposed\n' >"$DBTUNE_STATE_DIR/state"
    write_proposal
    write_manifest
}

write_strict_proposal_case() {
    local name=${1:-}
    local proposal="$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"

    rm -rf "$proposal"
    case $name in
        empty) : >"$proposal" ;;
        no-assignment) printf '# comment\n[mysqld]\n; comment\n' >"$proposal" ;;
        before-section) printf 'max_connections=300\n[mysqld]\nskip_name_resolve=1\n' >"$proposal" ;;
        second-mysqld) printf '[mysqld]\nmax_connections=300\n[mysqld]\nskip_name_resolve=1\n' >"$proposal" ;;
        server-section) printf '[server]\nmax_connections=300\n' >"$proposal" ;;
        client-section) printf '[client]\nmax_connections=300\n' >"$proposal" ;;
        include) printf '[mysqld]\n!include /tmp/unsafe.cnf\n' >"$proposal" ;;
        includedir) printf '[mysqld]\n!includedir /tmp/unsafe\n' >"$proposal" ;;
        bare-option) printf '[mysqld]\nskip_name_resolve\n' >"$proposal" ;;
        empty-key) printf '[mysqld]\n=300\n' >"$proposal" ;;
        empty-value) printf '[mysqld]\nmax_connections=\n' >"$proposal" ;;
        inline-hash) printf '[mysqld]\nmax_connections=300 # comment\n' >"$proposal" ;;
        inline-semicolon) printf '[mysqld]\nmax_connections=300 ; comment\n' >"$proposal" ;;
        multiple-equals) printf '[mysqld]\nmax_connections=300=400\n' >"$proposal" ;;
        canonical-duplicate) printf '[mysqld]\nMax-Connections=300\nmax_connections=400\n' >"$proposal" ;;
        crlf) printf '[mysqld]\r\nmax_connections=300\r\n' >"$proposal" ;;
        control) printf '[mysqld]\nmax_connections=30\0010\n' >"$proposal" ;;
        unsafe-key) printf '[mysqld]\n1unsafe=300\n' >"$proposal" ;;
        sensitive-key) printf '[mysqld]\npassword=secret\n' >"$proposal" ;;
        unreadable) printf '[mysqld]\nmax_connections=300\n' >"$proposal"; chmod 000 "$proposal" ;;
        directory) mkdir "$proposal" ;;
        symlink) printf '[mysqld]\nmax_connections=300\n' >"$BATS_TEST_TMPDIR/symlink-proposal"; ln -s "$BATS_TEST_TMPDIR/symlink-proposal" "$proposal" ;;
        *) return 64 ;;
    esac
}

replace_apply_snapshot() {
    local file=${1:-}
    local replacement="$file.replacement"

    { cat "$file"; printf '# replaced\n'; } >"$replacement"
    chmod 400 "$replacement"
    mv "$replacement" "$file"
}

replace_apply_records() {
    local file=${1:-}
    local replacement="$file.replacement"

    printf 'max_connections\t300\n' >"$replacement"
    chmod 400 "$replacement"
    mv "$replacement" "$file"
    touch "$BATS_TEST_TMPDIR/records-replaced"
}

prepare_apply_a_b() {
    printf 'external\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    TEST_HISTORY_A=$(cat "$DBTUNE_STATE_DIR/apply/current")
    TEST_CYCLE_A=$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_A" cycle_id)
    TEST_HASH_A=$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_A" proposal_hash)
    cp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/applied-a.cnf"

    printf '%s\n' \
        $'rule_id\tscope\tseverity\tverdict\tproposed_key\tproposed_value\tevidence\treason_id' \
        $'R-MAXCONN\tserver\thigh\tCHANGE\tmax_connections\t400\tcurrent=300\treason_max_connections_change' \
        $'R-PINNED\tserver\tmedium\tCHANGE\tskip_name_resolve\t1\tcurrent=OFF\treason_skip_name_resolve' \
        >"$DBTUNE_STATE_DIR/analysis.tsv"
    cat >"$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" <<'CNF'
[mysqld]
max-connections = 400
skip_name_resolve = 1
CNF
    write_manifest
    dbtune_state_write proposed
    cmd_apply >/dev/null
    TEST_HISTORY_B=$(cat "$DBTUNE_STATE_DIR/apply/current")
    TEST_CYCLE_B=$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_B" cycle_id)
    cp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/applied-b.cnf"
}

assert_apply_a_restored_from_b() {
    cmp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/applied-a.cnf"
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$TEST_HISTORY_A" ]
    [ "$(cat "$(dbtune_lifecycle_last_rollback_file)")" = "$TEST_HISTORY_B" ]
    [ "$(dbtune_manifest_value "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" rolled_back_cycle_id)" = "$TEST_CYCLE_B" ]
    [ "$(dbtune_manifest_value "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" restored_cycle_id)" = "$TEST_CYCLE_A" ]
    [ "$(dbtune_manifest_value "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" restored_history)" = "$TEST_HISTORY_A" ]
    [ "$(dbtune_manifest_value "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" restored_backup)" = "$TEST_HISTORY_B/original.cnf" ]
    [ "$(dbtune_state_read)" = rolled_back ]
    [ ! -e "$(dbtune_lifecycle_rollback_intent_file)" ]
}

publish_fixture() {
    local temporary

    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    chmod 644 "$DBTUNE_CONFIG_TARGET"
    dbtune_lifecycle_validate_target_path "$DBTUNE_CONFIG_TARGET"
    PUBLISH_TOPOLOGY=$DBTUNE_LIFECYCLE_TARGET_TOPOLOGY
    PUBLISH_DIRECTORY_IDENTITY=$DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY
    PUBLISH_TARGET_IDENTITY=$DBTUNE_LIFECYCLE_TARGET_IDENTITY
    PUBLISH_TARGET_HASH=$DBTUNE_LIFECYCLE_TARGET_HASH
    PUBLISH_PARENT_IDENTITIES=$DBTUNE_LIFECYCLE_PARENT_IDENTITIES
    temporary=$(mktemp "$DBTUNE_CONFIG_ALLOWED_DIR/.publisher-test.tmp.XXXXXX")
    printf 'published\n' >"$temporary"
    chmod 644 "$temporary"
    PUBLISH_SOURCE=$temporary
    PUBLISH_SOURCE_HASH=$(dbtune_sha256_file "$temporary")
}

run_publish_fixture() {
    dbtune_lifecycle_publish_managed_config "$PUBLISH_SOURCE" "$DBTUNE_CONFIG_TARGET" \
        "$PUBLISH_TOPOLOGY" "$PUBLISH_DIRECTORY_IDENTITY" "$PUBLISH_TARGET_IDENTITY" \
        "$PUBLISH_TARGET_HASH" "$PUBLISH_SOURCE_HASH" "$PUBLISH_PARENT_IDENTITIES"
}

@test "lifecycle lock rejects symlinks without opening their target" {
    printf 'unchanged\n' >"$BATS_TEST_TMPDIR/lock-target"
    ln -s "$BATS_TEST_TMPDIR/lock-target" "$(dbtune_lifecycle_lock_file)"

    run dbtune_with_lifecycle_lock wait test true

    [ "$status" -eq 65 ]
    [[ "$output" == *"safe regular file"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/lock-target")" = unchanged ]
    [ ! -e "$DBTUNE_RACE_LOCK_DIR" ]
}

@test "lifecycle lock accepts a safe existing regular file" {
    : >"$(dbtune_lifecycle_lock_file)"
    chmod 600 "$(dbtune_lifecycle_lock_file)"

    run dbtune_with_lifecycle_lock wait test true

    [ "$status" -eq 0 ]
    [ -f "$(dbtune_lifecycle_lock_file)" ]
    [ ! -L "$(dbtune_lifecycle_lock_file)" ]
    [ "$(file_mode "$(dbtune_lifecycle_lock_file)")" = 600 ]
}

@test "lifecycle lock rejects an externally hard-linked lock file" {
    : >"$(dbtune_lifecycle_lock_file)"
    chmod 600 "$(dbtune_lifecycle_lock_file)"
    ln "$(dbtune_lifecycle_lock_file)" "$BATS_TEST_TMPDIR/lock-alias"

    run dbtune_with_lifecycle_lock wait test true

    [ "$status" -eq 65 ]
    [[ "$output" == *"links=2, expected=1"* ]]
    [ ! -e "$DBTUNE_RACE_LOCK_DIR" ]
    [ -f "$BATS_TEST_TMPDIR/lock-alias" ]
}

@test "apply rejects an unknown live variable before writing" {
    export STUB_GLOBAL_NAMES=max_connections
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"skip_name_resolve"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "strict proposal grammar rejects every ambiguous input before apply preflight" {
    local mode name
    local cases=(
        empty no-assignment before-section second-mysqld server-section client-section include includedir
        bare-option empty-key empty-value inline-hash inline-semicolon multiple-equals canonical-duplicate
        crlf control unsafe-key sensitive-key unreadable directory symlink
    )
    dbtune_lifecycle_confirm_force() {
        touch "$BATS_TEST_TMPDIR/confirmation.log"
    }

    for mode in normal force; do
        for name in "${cases[@]}"; do
            reset_apply_preflight_fixture
            write_strict_proposal_case "$name"

            if [[ $mode == force ]]; then
                run cmd_apply --force
            else
                run cmd_apply
            fi

            [ "$status" -eq 65 ]
            [ ! -e "$BATS_TEST_TMPDIR/sql.log" ]
            [ ! -e "$BATS_TEST_TMPDIR/confirmation.log" ]
            assert_apply_preflight_unchanged
        done
    done
}

@test "partial parser output is never consumed by apply" {
    reset_apply_preflight_fixture
    dbtune_cnf_entries_strict() {
        printf 'max_connections\t300\n'
        return 65
    }

    run cmd_apply

    [ "$status" -eq 65 ]
    [ ! -e "$BATS_TEST_TMPDIR/sql.log" ]
    assert_apply_preflight_unchanged
}

@test "exact live variable output rejects malformed and partial SQL responses" {
    local name
    local cases=(duplicate extra-key extra-field blank-row control partial-failure)

    for name in "${cases[@]}"; do
        reset_apply_preflight_fixture
        export STUB_GLOBAL_STATUS=0
        case $name in
            duplicate) export STUB_GLOBAL_NAMES=$'max_connections\nmax_connections\nskip_name_resolve' ;;
            extra-key) export STUB_GLOBAL_NAMES=$'max_connections\nskip_name_resolve\nunknown_extra' ;;
            extra-field) export STUB_GLOBAL_NAMES=$'max_connections\textra\nskip_name_resolve' ;;
            blank-row) export STUB_GLOBAL_NAMES=$'max_connections\n\nskip_name_resolve' ;;
            control) export STUB_GLOBAL_NAMES=$'max_connections\nskip_name_resolve\001' ;;
            partial-failure)
                export STUB_GLOBAL_NAMES=max_connections
                export STUB_GLOBAL_STATUS=2
                ;;
        esac

        run cmd_apply

        [ "$status" -eq 65 ]
        [ -s "$BATS_TEST_TMPDIR/sql.log" ]
        assert_apply_preflight_unchanged
    done
}

@test "exact live variable command failure without output returns unavailable" {
    reset_apply_preflight_fixture
    export STUB_GLOBAL_NAMES=__NO_OUTPUT__
    export STUB_GLOBAL_STATUS=2

    run cmd_apply

    [ "$status" -eq 69 ]
    [ -s "$BATS_TEST_TMPDIR/sql.log" ]
    assert_apply_preflight_unchanged
}

@test "records path replacement after hash check cannot change the live variable query" {
    reset_apply_preflight_fixture
    dbtune_lifecycle_after_records_hash() {
        [[ -e $BATS_TEST_TMPDIR/records-replaced ]] || replace_apply_records "$1"
    }
    dbtune_sha256_file() {
        local file=${1:-} hash

        if command -v sha256sum >/dev/null 2>&1; then
            hash=$(sha256sum "$file" | awk '{print $1}')
        else
            hash=$(shasum -a 256 "$file" | awk '{print $1}')
        fi
        if [[ $file == "$DBTUNE_STATE_DIR"/.apply-records.* ]]; then
            if [[ -e $BATS_TEST_TMPDIR/records-hashed-once && ! -e $BATS_TEST_TMPDIR/records-replaced ]]; then
                replace_apply_records "$file"
            else
                touch "$BATS_TEST_TMPDIR/records-hashed-once"
            fi
        fi
        printf '%s\n' "$hash"
    }

    run cmd_apply

    [ "$status" -eq 0 ]
    grep -F "'max_connections'" "$BATS_TEST_TMPDIR/sql.log"
    grep -F "'skip_name_resolve'" "$BATS_TEST_TMPDIR/sql.log"
    cmp "$DBTUNE_CONFIG_TARGET" "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
}

@test "proposal snapshot mutation is detected at every copy and publication boundary" {
    local hook
    local hooks=(after-strict-parse before-history-copy before-target-copy before-publisher)

    for hook in "${hooks[@]}"; do
        reset_apply_preflight_fixture
        dbtune_lifecycle_after_strict_parse() { return 0; }
        dbtune_lifecycle_before_history_copy() { return 0; }
        dbtune_lifecycle_before_target_copy() { return 0; }
        dbtune_lifecycle_before_publish() { return 0; }
        case $hook in
            after-strict-parse)
                dbtune_lifecycle_after_strict_parse() { replace_apply_snapshot "$1"; }
                ;;
            before-history-copy)
                dbtune_lifecycle_before_history_copy() { replace_apply_snapshot "$1"; }
                ;;
            before-target-copy)
                dbtune_lifecycle_before_target_copy() { replace_apply_snapshot "$1"; }
                ;;
            before-publisher)
                dbtune_lifecycle_before_publish() {
                    [[ $2 == *'.99-zz-tuning.cnf.tmp.'* && ! -e $BATS_TEST_TMPDIR/publisher-replaced ]] || return 0
                    touch "$BATS_TEST_TMPDIR/publisher-replaced"
                    printf '# replaced\n' >>"$2"
                }
                ;;
        esac

        run cmd_apply

        [ "$status" -eq 65 ]
        [[ "$output" == *changed* ]]
        [ "$(cat "$DBTUNE_CONFIG_TARGET")" = 'original target' ]
        [ "$(dbtune_state_read)" = proposed ]
        [ ! -e "$DBTUNE_STATE_DIR/apply/current" ]
        if [[ $hook == after-strict-parse || $hook == before-history-copy ]]; then
            [ ! -e "$DBTUNE_STATE_DIR/apply" ]
        fi
    done
}

@test "proposal manifest exact schema rejects duplicate unknown missing and malformed records" {
    local name manifest="$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    local cases=(duplicate-first duplicate-last identical-duplicate unknown missing-schema malformed-hash zero-count extra-fields)

    for name in "${cases[@]}"; do
        reset_apply_preflight_fixture
        case $name in
            duplicate-first)
                { printf 'schema\t999\n'; cat "$manifest"; } >"$BATS_TEST_TMPDIR/manifest"; mv "$BATS_TEST_TMPDIR/manifest" "$manifest"
                ;;
            duplicate-last) printf 'schema\t999\n' >>"$manifest" ;;
            identical-duplicate) printf 'schema\t1\n' >>"$manifest" ;;
            unknown) printf 'unexpected\tvalue\n' >>"$manifest" ;;
            missing-schema) awk -F '\t' '$1 != "schema"' "$manifest" >"$BATS_TEST_TMPDIR/manifest"; mv "$BATS_TEST_TMPDIR/manifest" "$manifest" ;;
            malformed-hash) awk -F '\t' 'BEGIN {OFS="\t"} $1 == "proposal_hash" {$2="bad"} {print}' "$manifest" >"$BATS_TEST_TMPDIR/manifest"; mv "$BATS_TEST_TMPDIR/manifest" "$manifest" ;;
            zero-count) awk -F '\t' 'BEGIN {OFS="\t"} $1 == "proposal_count" {$2="0"} {print}' "$manifest" >"$BATS_TEST_TMPDIR/manifest"; mv "$BATS_TEST_TMPDIR/manifest" "$manifest" ;;
            extra-fields) awk -F '\t' 'BEGIN {OFS="\t"} $1 == "schema" {$3="extra"} {print}' "$manifest" >"$BATS_TEST_TMPDIR/manifest"; mv "$BATS_TEST_TMPDIR/manifest" "$manifest" ;;
        esac

        run cmd_apply

        [ "$status" -eq 65 ]
        [ ! -e "$BATS_TEST_TMPDIR/sql.log" ]
        assert_apply_preflight_unchanged
    done
}

@test "apply rejects a proposal changed after manifest creation" {
    printf '# tampered\n' >>"$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"changed"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "degraded samples do not satisfy the apply measurement minimum" {
    export DBTUNE_MIN_APPLY_SAMPLES=2
    printf '2026-07-31T12:05:00Z\t200\t0\t999\t999\t999\t100\t999\t999\t0\t999\t999\t999\t1\t1\t1\t0\t1\t999\tdegraded_interval\n' >>"$DBTUNE_STATE_DIR/samples.tsv"
    write_manifest

    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"Apply is blocked"* ]]
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

@test "config validation establishes the split ownership and mode boundary" {
    export STUB_CHOWN_SYMLINK_ATTACK=1
    export STUB_VALIDATE_HELP_VICTIM="$BATS_TEST_TMPDIR/help-victim"
    export STUB_VALIDATE_OUTPUT_VICTIM="$BATS_TEST_TMPDIR/output-victim"
    printf 'help-safe\n' >"$STUB_VALIDATE_HELP_VICTIM"
    printf 'output-safe\n' >"$STUB_VALIDATE_OUTPUT_VICTIM"

    run dbtune_lifecycle_validate_config

    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_VALIDATE_HELP_VICTIM")" = help-safe ]
    [ "$(cat "$STUB_VALIDATE_OUTPUT_VICTIM")" = output-safe ]
    chowned_dir=$(awk '$1 == "mysql:mysql" {print $2; exit}' "$BATS_TEST_TMPDIR/chown.log")
    [[ $chowned_dir == */data ]]
    validation_parent=${chowned_dir%/data}
    grep -Fx -- "mysql:mysql $chowned_dir" "$BATS_TEST_TMPDIR/chown.log"
    grep -Fx -- "root:mysql $validation_parent" "$BATS_TEST_TMPDIR/chown.log"
    grep -Fx -- "-m 0700 $chowned_dir" "$BATS_TEST_TMPDIR/mkdir.log"
    grep -Fx -- "0710 $validation_parent" "$BATS_TEST_TMPDIR/chmod.log"
    grep -E -- "^0600 ${validation_parent}/help[.]log ${validation_parent}/output[.]log$" "$BATS_TEST_TMPDIR/chmod.log"
    grep -F -- "--datadir=$chowned_dir" "$BATS_TEST_TMPDIR/mariadbd.log"
}

@test "config validation fallback keeps a root-owned capture workspace without a datadir" {
    export STUB_HELP_HAS_VALIDATE_CONFIG=0

    run dbtune_lifecycle_validate_config

    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/chown.log" ]
    if [ -e "$BATS_TEST_TMPDIR/mkdir.log" ]; then
        ! grep -F -- '-m 0700' "$BATS_TEST_TMPDIR/mkdir.log"
    fi
    grep -F -- '0600 ' "$BATS_TEST_TMPDIR/chmod.log"
    ! grep -F -- '--validate-config' "$BATS_TEST_TMPDIR/mariadbd.log"
}

@test "config validation fails closed when capture file mode cannot be established" {
    export STUB_FAIL_CHMOD_MATCH=0600

    run dbtune_lifecycle_validate_config

    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/mariadbd.log" ]
}

@test "config validation fails closed when dedicated datadir mode cannot be established" {
    export STUB_FAIL_MKDIR_MATCH='-m 0700'

    run dbtune_lifecycle_validate_config

    [ "$status" -ne 0 ]
    ! grep -F -- '--validate-config' "$BATS_TEST_TMPDIR/mariadbd.log"
}

@test "config validation fails closed when mysql datadir ownership cannot be established" {
    export STUB_FAIL_CHOWN_MATCH=mysql:mysql

    run dbtune_lifecycle_validate_config

    [ "$status" -ne 0 ]
    ! grep -F -- '--validate-config' "$BATS_TEST_TMPDIR/mariadbd.log"
}

@test "config validation fails closed when parent ownership cannot be established" {
    export STUB_FAIL_CHOWN_MATCH=root:mysql

    run dbtune_lifecycle_validate_config

    [ "$status" -ne 0 ]
    ! grep -F -- '--validate-config' "$BATS_TEST_TMPDIR/mariadbd.log"
}

@test "config validation fails closed when parent mode cannot be established" {
    export STUB_FAIL_CHMOD_MATCH=0710

    run dbtune_lifecycle_validate_config

    [ "$status" -ne 0 ]
    ! grep -F -- '--validate-config' "$BATS_TEST_TMPDIR/mariadbd.log"
}

@test "apply accepts an absent target in the explicit allowed directory" {
    run cmd_apply
    [ "$status" -eq 0 ]
    [ -f "$DBTUNE_CONFIG_TARGET" ]
    [ ! -L "$DBTUNE_CONFIG_TARGET" ]
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 1 ]
}

@test "apply accepts and backs up a regular target in the explicit allowed directory" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    run cmd_apply
    [ "$status" -eq 0 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ "$(cat "$history/original.cnf")" = original ]
}

@test "apply rejects target symlinks and dangling symlinks" {
    printf 'outside\n' >"$BATS_TEST_TMPDIR/outside.cnf"
    ln -s "$BATS_TEST_TMPDIR/outside.cnf" "$DBTUNE_CONFIG_TARGET"
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"symlink"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/outside.cnf")" = outside ]

    rm "$DBTUNE_CONFIG_TARGET"
    ln -s "$BATS_TEST_TMPDIR/missing.cnf" "$DBTUNE_CONFIG_TARGET"
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"dangling symlink"* ]]
    [ -L "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply rejects a symlink in the config parent path" {
    rmdir "$DBTUNE_CONFIG_ALLOWED_DIR"
    mkdir "$BATS_TEST_TMPDIR/real-config"
    ln -s "$BATS_TEST_TMPDIR/real-config" "$DBTUNE_CONFIG_ALLOWED_DIR"

    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"parent component"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/real-config/99-zz-tuning.cnf" ]
}

@test "apply rejects a target outside the explicit allowed directory" {
    mkdir "$BATS_TEST_TMPDIR/outside-config"
    export DBTUNE_CONFIG_TARGET="$BATS_TEST_TMPDIR/outside-config/99-zz-tuning.cnf"

    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"allowed directory"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply rejects an existing target with an unexpected mode" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    chmod 600 "$DBTUNE_CONFIG_TARGET"

    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"ownership or mode"* ]]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
}

@test "apply rejects an existing target with hardlinks" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    ln "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/original-hardlink.cnf"

    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"multiple hard links"* ]]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(cat "$BATS_TEST_TMPDIR/original-hardlink.cnf")" = original ]
}

@test "apply rejects an unexpected config ownership contract" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_CONFIG_UID=$((DBTUNE_CONFIG_UID + 1))

    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"unexpected ownership"* ]]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
}

@test "apply revalidates parent identity immediately before atomic publish" {
    dbtune_lifecycle_before_publish() {
        if [[ ! -e $BATS_TEST_TMPDIR/parent-swapped ]]; then
            mv "$DBTUNE_CONFIG_ALLOWED_DIR" "$BATS_TEST_TMPDIR/original-config-dir"
            mkdir "$DBTUNE_CONFIG_ALLOWED_DIR"
            touch "$BATS_TEST_TMPDIR/parent-swapped"
        fi
    }

    run cmd_apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"directory was replaced during apply"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/original-config-dir/99-zz-tuning.cnf" ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply detects replacement of a validated ancestor while the trusted directory remains" {
    mkdir "$BATS_TEST_TMPDIR/config-parent"
    mv "$DBTUNE_CONFIG_ALLOWED_DIR" "$BATS_TEST_TMPDIR/config-parent/etc"
    export DBTUNE_CONFIG_ALLOWED_DIR="$BATS_TEST_TMPDIR/config-parent/etc"
    export DBTUNE_CONFIG_TARGET="$DBTUNE_CONFIG_ALLOWED_DIR/99-zz-tuning.cnf"
    cat >"$BATS_TEST_TMPDIR/swap-config-parent" <<'STUB'
#!/usr/bin/env bash
[[ -e $BATS_TEST_TMPDIR/parent-swapped ]] && exit 0
mv "$BATS_TEST_TMPDIR/config-parent" "$BATS_TEST_TMPDIR/original-config-parent"
mkdir "$BATS_TEST_TMPDIR/config-parent"
mv "$BATS_TEST_TMPDIR/original-config-parent/etc" "$DBTUNE_CONFIG_ALLOWED_DIR"
touch "$BATS_TEST_TMPDIR/parent-swapped"
STUB
    chmod +x "$BATS_TEST_TMPDIR/swap-config-parent"
    export DBTUNE_PUBLISH_FAULT_HOOK="$BATS_TEST_TMPDIR/swap-config-parent"

    run cmd_apply

    [ "$status" -ne 0 ]
    [[ "$output" == *"config parent was replaced during publication"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply detects a target swap after validation before publication" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    cat >"$BATS_TEST_TMPDIR/swap-config-target" <<'STUB'
#!/usr/bin/env bash
[[ -e $BATS_TEST_TMPDIR/target-swapped ]] && exit 0
mv "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/original-target.cnf"
printf 'replacement\n' >"$DBTUNE_CONFIG_TARGET"
chmod 644 "$DBTUNE_CONFIG_TARGET"
touch "$BATS_TEST_TMPDIR/target-swapped"
STUB
    chmod +x "$BATS_TEST_TMPDIR/swap-config-target"
    export DBTUNE_PUBLISH_FAULT_HOOK="$BATS_TEST_TMPDIR/swap-config-target"

    run cmd_apply

    [ "$status" -ne 0 ]
    [[ "$output" == *"replaced"* || "$output" == *"does not match"* ]]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = replacement ]
    [ "$(cat "$BATS_TEST_TMPDIR/original-target.cnf")" = original ]
}

@test "publisher crash after validation leaves the original target intact" {
    publish_fixture
    export DBTUNE_PUBLISH_CRASH_POINT=after_validation

    run run_publish_fixture

    [ "$status" -eq 99 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 1 ]
    [ "$(cat "$PUBLISH_SOURCE")" = published ]
}

@test "publisher crash after atomic exchange leaves a complete published target" {
    publish_fixture
    export DBTUNE_PUBLISH_CRASH_POINT=after_commit

    run run_publish_fixture

    [ "$status" -eq 99 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = published ]
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 1 ]
    [ "$(cat "$PUBLISH_SOURCE")" = original ]
    [ "$(dbtune_lifecycle_file_links "$PUBLISH_SOURCE")" = 1 ]
}

@test "publisher crash after absent-target commit leaves one complete target inode" {
    dbtune_lifecycle_validate_target_path "$DBTUNE_CONFIG_TARGET"
    PUBLISH_TOPOLOGY=$DBTUNE_LIFECYCLE_TARGET_TOPOLOGY
    PUBLISH_DIRECTORY_IDENTITY=$DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY
    PUBLISH_TARGET_IDENTITY=$DBTUNE_LIFECYCLE_TARGET_IDENTITY
    PUBLISH_TARGET_HASH=$DBTUNE_LIFECYCLE_TARGET_HASH
    PUBLISH_PARENT_IDENTITIES=$DBTUNE_LIFECYCLE_PARENT_IDENTITIES
    PUBLISH_SOURCE=$(mktemp "$DBTUNE_CONFIG_ALLOWED_DIR/.publisher-absent-test.tmp.XXXXXX")
    printf 'published\n' >"$PUBLISH_SOURCE"
    chmod 644 "$PUBLISH_SOURCE"
    PUBLISH_SOURCE_HASH=$(dbtune_sha256_file "$PUBLISH_SOURCE")
    export DBTUNE_PUBLISH_CRASH_POINT=after_commit

    run run_publish_fixture

    [ "$status" -eq 99 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = published ]
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 1 ]
    [ ! -e "$PUBLISH_SOURCE" ]
}

@test "publisher crash after post-validation keeps both exchange endpoints valid" {
    publish_fixture
    export DBTUNE_PUBLISH_CRASH_POINT=after_postvalidation

    run run_publish_fixture

    [ "$status" -eq 99 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = published ]
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 1 ]
    [ "$(cat "$PUBLISH_SOURCE")" = original ]
    [ "$(dbtune_lifecycle_file_links "$PUBLISH_SOURCE")" = 1 ]
}

@test "apply auto-recovers an internal publisher crash after exchange" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_PUBLISH_CRASH_POINT=after_commit
    export DBTUNE_PUBLISH_CRASH_MATCH=.99-zz-tuning.cnf.tmp

    run cmd_apply

    [ "$status" -ne 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 1 ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$(dbtune_lifecycle_intent_file)" ]
}

@test "rollback detects a parent swap after validation before publication" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    cat >"$BATS_TEST_TMPDIR/swap-rollback-parent" <<'STUB'
#!/usr/bin/env bash
mv "$DBTUNE_CONFIG_ALLOWED_DIR" "$BATS_TEST_TMPDIR/deployed-config-dir"
mkdir "$DBTUNE_CONFIG_ALLOWED_DIR"
STUB
    chmod +x "$BATS_TEST_TMPDIR/swap-rollback-parent"
    export DBTUNE_PUBLISH_FAULT_HOOK="$BATS_TEST_TMPDIR/swap-rollback-parent"

    run cmd_rollback

    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/deployed-config-dir/99-zz-tuning.cnf")" != original ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
    [ "$(dbtune_state_read)" = rollback_failed ]
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

@test "force cannot bypass live landmine critical or failed scans in every permitted state" {
    local mode state failure

    dbtune_lifecycle_confirm_force() { :; }
    for mode in normal force; do
        for state in audited analyzed proposed; do
            [[ $mode == force || $state == proposed ]] || continue
            for failure in critical failed; do
                reset_apply_preflight_fixture
                printf '%s\n' "$state" >"$DBTUNE_STATE_DIR/state"
                : >"$BATS_TEST_TMPDIR/landmine-scan.log"
                if [[ $failure == critical ]]; then
                    export STUB_DEFAULTS_OUTPUT='--innodb-change-buffering=all\n'
                    export STUB_DEFAULTS_STATUS=0
                else
                    export STUB_DEFAULTS_OUTPUT=
                    export STUB_DEFAULTS_STATUS=7
                fi

                if [[ $mode == force ]]; then
                    run cmd_apply --force
                else
                    run cmd_apply
                fi

                [ "$status" -eq 65 ]
                [ "$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')" -eq 1 ]
                assert_apply_preflight_unchanged "$state"
                [ ! -e "$DBTUNE_STATE_DIR/systemctl.log" ]
            done
        done
    done
}

@test "live landmine preflight rejects an old audit before scanning or durable mutation" {
    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    awk -F '\t' '$1 !~ /^landmine[.]scan[.]/' "$DBTUNE_STATE_DIR/audit.tsv" >"$BATS_TEST_TMPDIR/old-audit.tsv"
    mv "$BATS_TEST_TMPDIR/old-audit.tsv" "$DBTUNE_STATE_DIR/audit.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        lifecycle-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_manifest

    run cmd_apply

    [ "$status" -eq 65 ]
    [ ! -e "$BATS_TEST_TMPDIR/landmine-scan.log" ]
    assert_apply_preflight_unchanged
}

@test "live landmine scan observes defaults changed after proposal validation" {
    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    export STUB_DEFAULTS_OUTPUT=
    dbtune_lifecycle_after_manifest_check() {
        export STUB_DEFAULTS_OUTPUT='--innodb-change-buffering=all\n'
    }

    run cmd_apply

    [ "$status" -eq 65 ]
    [ "$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')" -eq 1 ]
    assert_apply_preflight_unchanged
}

@test "live landmine warning is bound into new history without bypassing other checks" {
    local history expected_fingerprint

    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    export STUB_DEFAULTS_OUTPUT='--innodb-flush-method=O_DIRECT\n'
    expected_fingerprint=$(printf 'innodb_flush_method\twarning\n' | dbtune_sha256_stream)

    run cmd_apply

    [ "$status" -eq 0 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    grep -Fx $'schema\t1' "$history/manifest.tsv"
    grep -Fx $'landmine_scan_timestamp\t2026-07-31T12:00:00Z' "$history/manifest.tsv"
    grep -Fx $'landmine_scan_method\tmariadbd_print_defaults' "$history/manifest.tsv"
    grep -Fx $'landmine_loaded_fingerprint\t'"$expected_fingerprint" "$history/manifest.tsv"
    grep -Fx $'force\t0' "$history/manifest.tsv"
    [ "$(dbtune_lifecycle_manifest_value "$history" landmine_scan_hash)" = "$(dbtune_sha256_file "$history/loaded-defaults.tsv")" ]
    grep -Fx $'landmine.innodb_flush_method.loaded\t1' "$history/loaded-defaults.tsv"

    reset_apply_preflight_fixture
    export STUB_DEFAULTS_OUTPUT='--innodb-flush-method=O_DIRECT\n'
    export STUB_WSREP_ON=ON
    run cmd_apply
    [ "$status" -eq 65 ]
    assert_apply_preflight_unchanged
}

@test "forced apply binds current audit identity without a valid proposal manifest" {
    local history expected_run_id expected_audit_hash

    printf 'audit.run_id\tartifact-run\n' >>"$DBTUNE_STATE_DIR/audit.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        lifecycle-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    expected_run_id=$(dbtune_manifest_value "$DBTUNE_STATE_DIR/audit-manifest.tsv" run_id)
    expected_audit_hash=$(dbtune_manifest_value "$DBTUNE_STATE_DIR/audit-manifest.tsv" audit_hash)
    rm -f "$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    dbtune_lifecycle_confirm_force() { :; }

    run cmd_apply --force

    [ "$status" -eq 0 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ "$(dbtune_lifecycle_manifest_value "$history" run_id)" = "$expected_run_id" ]
    [ "$(dbtune_lifecycle_manifest_value "$history" audit_hash)" = "$expected_audit_hash" ]
    [ "$(dbtune_lifecycle_manifest_value "$history" force)" = 1 ]
}

@test "force requires an audit manifest authenticating every audit artifact" {
    local case_name state expected_status artifact

    dbtune_lifecycle_confirm_force() { :; }
    cp "$DBTUNE_STATE_DIR/audit.tsv" "$BATS_TEST_TMPDIR/authenticated-audit.tsv"
    cp "$DBTUNE_STATE_DIR/apps.tsv" "$BATS_TEST_TMPDIR/authenticated-apps.tsv"
    cp "$DBTUNE_STATE_DIR/databases.tsv" "$BATS_TEST_TMPDIR/authenticated-databases.tsv"
    cp "$DBTUNE_STATE_DIR/audit-manifest.tsv" "$BATS_TEST_TMPDIR/authenticated-audit-manifest.tsv"
    for state in audited analyzed proposed; do
        for case_name in absent audit-mismatch apps-mismatch databases-mismatch; do
            cp "$BATS_TEST_TMPDIR/authenticated-audit.tsv" "$DBTUNE_STATE_DIR/audit.tsv"
            cp "$BATS_TEST_TMPDIR/authenticated-apps.tsv" "$DBTUNE_STATE_DIR/apps.tsv"
            cp "$BATS_TEST_TMPDIR/authenticated-databases.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
            cp "$BATS_TEST_TMPDIR/authenticated-audit-manifest.tsv" "$DBTUNE_STATE_DIR/audit-manifest.tsv"
            reset_apply_preflight_fixture
            printf '%s\n' "$state" >"$DBTUNE_STATE_DIR/state"
            expected_status=65
            case $case_name in
                absent)
                    rm -f "$DBTUNE_STATE_DIR/audit-manifest.tsv"
                    expected_status=66
                    ;;
                audit-mismatch) artifact=audit.tsv ;;
                apps-mismatch) artifact=apps.tsv ;;
                databases-mismatch) artifact=databases.tsv ;;
            esac
            if [[ $case_name != absent ]]; then
                printf 'stale\tevidence\n' >>"$DBTUNE_STATE_DIR/$artifact"
            fi

            run cmd_apply --force

            [ "$status" -eq "$expected_status" ]
            assert_apply_preflight_unchanged "$state"
        done
    done
}

@test "force revalidates audit provenance at final history preparation" {
    dbtune_lifecycle_confirm_force() { :; }
    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    dbtune_lifecycle_after_manifest_check() {
        printf 'stale\tevidence\n' >>"$DBTUNE_STATE_DIR/apps.tsv"
    }

    run cmd_apply --force

    [ "$status" -eq 65 ]
    assert_apply_preflight_unchanged
}

@test "rollback ignores landmine scanner failure corrupt audit and unsafe current defaults" {
    local history scans_before

    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    scans_before=$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')
    printf 'landmine.scan.status\tfailed\nlandmine.innodb_change_buffering.loaded\t2\n' >>"$DBTUNE_STATE_DIR/audit.tsv"
    export STUB_DEFAULTS_OUTPUT='--innodb-change-buffering=all\n'
    export STUB_DEFAULTS_STATUS=7
    awk -F '\t' '$1 != "schema" && $1 !~ /^landmine_/' "$history/manifest.tsv" >"$BATS_TEST_TMPDIR/old-manifest.tsv"
    mv "$BATS_TEST_TMPDIR/old-manifest.tsv" "$history/manifest.tsv"

    run cmd_rollback

    [ "$status" -eq 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = 'original target' ]
    [ "$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')" -eq "$scans_before" ]
}

@test "new history schema requires exact live landmine metadata" {
    local history

    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    awk -F '\t' '$1 != "landmine_scan_hash"' "$history/manifest.tsv" >"$BATS_TEST_TMPDIR/incomplete-manifest.tsv"
    mv "$BATS_TEST_TMPDIR/incomplete-manifest.tsv" "$history/manifest.tsv"

    run cmd_rollback

    [ "$status" -eq 65 ]
    [ "$(dbtune_state_read)" = applied ]
    cmp "$DBTUNE_CONFIG_TARGET" "$history/proposed.cnf"
}

@test "rollback ignores landmine scanner during failed apply recovery and interrupted continuation" {
    local scans_before

    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    dbtune_lifecycle_before_publish() {
        export STUB_DEFAULTS_OUTPUT='--innodb-change-buffering=all\n'
        export STUB_DEFAULTS_STATUS=7
    }
    export STUB_RESTART_FAIL=1

    run cmd_apply --restart

    [ "$status" -ne 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = 'original target' ]
    [ "$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')" -eq 1 ]

    dbtune_lifecycle_before_publish() { :; }
    export STUB_RESTART_FAIL=0 STUB_DEFAULTS_STATUS=0 STUB_DEFAULTS_OUTPUT=
    prepare_apply_a_b
    export DBTUNE_FAULT_INJECT=after_rollback_intent
    run cmd_rollback
    [ "$status" -eq 99 ]
    unset DBTUNE_FAULT_INJECT
    scans_before=$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')
    printf 'landmine.scan.status\tfailed\n' >>"$DBTUNE_STATE_DIR/audit.tsv"
    export STUB_DEFAULTS_OUTPUT='--innodb-change-buffering=all\n' STUB_DEFAULTS_STATUS=7

    run dbtune_lifecycle_recover_if_needed

    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
    [ "$(wc -l <"$BATS_TEST_TMPDIR/landmine-scan.log" | tr -d ' ')" -eq "$scans_before" ]
}

@test "apply rejects critical version and missing-backup findings" {
    printf 'R-VERSION\tserver\tcritical\tREMOVED\t\t\tinnodb_change_buffering\treason_variable_removed_startup\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    printf 'R-BACKUP\tserver\tcritical\tMISSING\t\t\tbackup unknown\treason_backup_missing\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    write_manifest
    run cmd_apply
    [ "$status" -eq 65 ]
    [ "$output" = '2026-07-31T12:00:00Z [ERROR] Apply is blocked by a critical server finding: R-VERSION: REMOVED - The variable was removed in MariaDB 11 and can prevent the next start. R-BACKUP: MISSING - Confirmed absence of a backup blocks tuning.' ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "critical-analysis rejection resolves exact Slovak reasons" {
    printf 'R-VERSION\tserver\tcritical\tREMOVED\t\t\tinnodb_change_buffering\treason_variable_removed_startup\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    printf 'R-BACKUP\tserver\tcritical\tMISSING\t\t\tbackup unknown\treason_backup_missing\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    write_manifest
    dbtune_i18n_set sk

    run cmd_apply

    [ "$status" -eq 65 ]
    [ "$output" = '2026-07-31T12:00:00Z [ERROR] Apply blokuje kritický serverový nález: R-VERSION: REMOVED - Premenná je od MariaDB 11 odstránená a môže zablokovať ďalší štart. R-BACKUP: MISSING - Potvrdená absencia zálohy blokuje tuning.' ]
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

@test "rollback restores an originally absent target to absent topology" {
    cmd_apply >/dev/null
    [ -f "$DBTUNE_CONFIG_TARGET" ]

    run cmd_rollback
    [ "$status" -eq 0 ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
    [ ! -L "$DBTUNE_CONFIG_TARGET" ]
}

@test "apply A apply B rollback publishes the restored A lineage and preserves the B rollback event" {
    prepare_apply_a_b

    [ "$TEST_HISTORY_B" != "$TEST_HISTORY_A" ]
    [ "$TEST_CYCLE_B" != "$TEST_CYCLE_A" ]
    [ "$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_B" original_source)" = apply_cycle ]
    [ "$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_B" original_cycle_id)" = "$TEST_CYCLE_A" ]
    [ "$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_B" original_cycle_history)" = "$TEST_HISTORY_A" ]
    [ "$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_B" original_backup)" = original.cnf ]
    [ "$(dbtune_lifecycle_manifest_value "$TEST_HISTORY_B" original_hash)" = "$TEST_HASH_A" ]
    cmp "$TEST_HISTORY_B/original.cnf" "$TEST_HISTORY_A/proposed.cnf"

    run cmd_rollback

    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
    grep -F '"event":"rollback_completed"' "$DBTUNE_STATE_DIR/events.log"
    grep -F '"restored_cycle_id":"'"$TEST_CYCLE_A"'"' "$DBTUNE_STATE_DIR/events.log"
    grep -F '"restart_required":"true"' "$DBTUNE_STATE_DIR/events.log"

    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"apply_history: $TEST_HISTORY_A"* ]]
    [[ "$output" == *"last_rollback: $TEST_HISTORY_B"* ]]
    [[ "$output" == *"runcloud_restart_required: true"* ]]
}

@test "rollback recovery after durable intent restores A without partial metadata" {
    prepare_apply_a_b
    export DBTUNE_FAULT_INJECT=after_rollback_intent

    run cmd_rollback

    [ "$status" -eq 99 ]
    cmp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/applied-b.cnf"
    [ ! -e "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$TEST_HISTORY_B" ]
    [ "$(dbtune_state_read)" = applied ]
    [ -r "$(dbtune_lifecycle_rollback_intent_file)" ]

    unset DBTUNE_FAULT_INJECT
    run dbtune_lifecycle_recover_if_needed
    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
}

@test "next locked command recovers rollback after target restore" {
    prepare_apply_a_b
    export DBTUNE_FAULT_INJECT=after_rollback_config

    run cmd_rollback

    [ "$status" -eq 99 ]
    cmp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/applied-a.cnf"
    [ ! -e "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$TEST_HISTORY_B" ]
    [ "$(dbtune_state_read)" = applied ]

    unset DBTUNE_FAULT_INJECT
    run dbtune_with_lifecycle_lock wait rollback-recovery true
    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
}

@test "rollback retry reuses durable completion metadata" {
    prepare_apply_a_b
    export DBTUNE_FAULT_INJECT=after_rollback_metadata

    run cmd_rollback

    [ "$status" -eq 99 ]
    [ -r "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" ]
    [ "$(cat "$(dbtune_lifecycle_last_rollback_file)")" = "$TEST_HISTORY_B" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$TEST_HISTORY_B" ]
    [ "$(dbtune_state_read)" = applied ]

    unset DBTUNE_FAULT_INJECT
    run cmd_rollback
    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
}

@test "rollback retry uses journal after current pointer moves to A" {
    prepare_apply_a_b
    export DBTUNE_FAULT_INJECT=after_rollback_current

    run cmd_rollback

    [ "$status" -eq 99 ]
    [ -r "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$TEST_HISTORY_A" ]
    [ "$(dbtune_state_read)" = applied ]
    [ -r "$(dbtune_lifecycle_rollback_intent_file)" ]

    unset DBTUNE_FAULT_INJECT
    run cmd_rollback
    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
    [ ! -e "$TEST_HISTORY_A/ROLLBACK_COMPLETED.tsv" ]
}

@test "rollback recovery clears journal only after durable rolled back state" {
    prepare_apply_a_b
    export DBTUNE_FAULT_INJECT=after_rollback_state

    run cmd_rollback

    [ "$status" -eq 99 ]
    [ -r "$TEST_HISTORY_B/ROLLBACK_COMPLETED.tsv" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$TEST_HISTORY_A" ]
    [ "$(dbtune_state_read)" = rolled_back ]
    [ -r "$(dbtune_lifecycle_rollback_intent_file)" ]

    unset DBTUNE_FAULT_INJECT
    run dbtune_lifecycle_recover_if_needed
    [ "$status" -eq 0 ]
    assert_apply_a_restored_from_b
    [ -r "$TEST_HISTORY_B/ROLLBACK_EVENT_RECORDED" ]
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

@test "English force confirmation accepts only its exact trusted phrase and records a stable ID" {
    dbtune_i18n_set en
    dbtune_lifecycle_is_interactive() { return 0; }

    run dbtune_lifecycle_confirm_force <<<'APPLY WITHOUT MEASUREMENTS'

    [ "$status" -eq 0 ]
    [[ "$output" == *'Type exactly to continue: APPLY WITHOUT MEASUREMENTS'* ]]
    grep -F '"event":"safety_confirmation"' "$(dbtune_events_file)"
    grep -F '"confirmation_id":"apply_without_measurements"' "$(dbtune_events_file)"
    grep -F '"ui_lang":"en"' "$(dbtune_events_file)"
    ! grep -F 'APPLY WITHOUT MEASUREMENTS' "$(dbtune_events_file)"
}

@test "Slovak force confirmation accepts only its exact trusted phrase and records a stable ID" {
    dbtune_i18n_set sk
    dbtune_lifecycle_is_interactive() { return 0; }

    run dbtune_lifecycle_confirm_force <<<'APLIKUJ BEZ MERANIA'

    [ "$status" -eq 0 ]
    [[ "$output" == *'Pre pokračovanie napíšte presne: APLIKUJ BEZ MERANIA'* ]]
    grep -F '"confirmation_id":"apply_without_measurements"' "$(dbtune_events_file)"
    grep -F '"ui_lang":"sk"' "$(dbtune_events_file)"
    ! grep -F 'APLIKUJ BEZ MERANIA' "$(dbtune_events_file)"
}

@test "force confirmation rejects phrases from the wrong language and different case" {
    dbtune_lifecycle_is_interactive() { return 0; }
    dbtune_i18n_set en

    run dbtune_lifecycle_confirm_force <<<'APLIKUJ BEZ MERANIA'
    [ "$status" -eq 77 ]
    run dbtune_lifecycle_confirm_force <<<'apply without measurements'
    [ "$status" -eq 77 ]

    dbtune_i18n_set sk
    run dbtune_lifecycle_confirm_force <<<'APPLY WITHOUT MEASUREMENTS'
    [ "$status" -eq 77 ]
    [ ! -e "$(dbtune_events_file)" ]
}

@test "apply requires independent backup evidence outside a TTY" {
    rm "$(dbtune_backup_evidence_file)"
    run cmd_apply
    [ "$status" -eq 77 ]
    [[ "$output" == *"backup-evidence.tsv"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "fresh backup evidence exposes its evaluated age and policy" {
    write_backup_evidence verified 2026-07-31T11:59:00Z 2026-07-31T12:00:00Z

    dbtune_backup_evidence_validate "$(dbtune_backup_evidence_file)"

    [ "$DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS" -eq 60 ]
    [ "$DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS" -eq 86400 ]
}

@test "backup evidence exactly at the maximum age is accepted" {
    export DBTUNE_MAX_BACKUP_AGE_SECONDS=3600
    write_backup_evidence verified 2026-07-31T11:00:00Z 2026-07-31T12:00:00Z

    run cmd_apply

    [ "$status" -eq 0 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ "$(dbtune_lifecycle_manifest_value "$history" backup_age_seconds)" -eq 3600 ]
    [ "$(dbtune_lifecycle_manifest_value "$history" backup_max_age_seconds)" -eq 3600 ]
}

@test "stale backup evidence blocks apply and reports age and policy" {
    export DBTUNE_MAX_BACKUP_AGE_SECONDS=3600
    write_backup_evidence verified 2026-07-31T10:59:59Z 2026-07-31T11:30:00Z

    run cmd_apply

    [ "$status" -eq 65 ]
    [[ "$output" == *"reason=expired"* ]]
    [[ "$output" == *"age_seconds=3601"* ]]
    [[ "$output" == *"max_age_seconds=3600"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "future backup evidence blocks apply fail-closed" {
    write_backup_evidence verified 2026-07-31T12:00:01Z 2026-07-31T12:00:00Z

    run cmd_apply

    [ "$status" -eq 65 ]
    [[ "$output" == *"reason=future_last_success"* ]]
    [[ "$output" == *"age_seconds=-1"* ]]
    [[ "$output" == *"max_age_seconds=86400"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "malformed backup timestamp blocks apply fail-closed" {
    write_backup_evidence verified 2026-02-30T11:00:00Z 2026-07-31T11:30:00Z

    run cmd_apply

    [ "$status" -eq 65 ]
    [[ "$output" == *"reason=malformed_last_success"* ]]
    [[ "$output" == *"age_seconds=unknown"* ]]
    [[ "$output" == *"max_age_seconds=86400"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "confirmed missing backup cannot be overridden" {
    write_backup_evidence missing
    run cmd_apply
    [ "$status" -eq 65 ]
    [[ "$output" == *"confirms that no backup exists"* ]]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "backup fallback requires its own exact interactive phrase" {
    dbtune_i18n_set sk
    dbtune_lifecycle_is_interactive() { return 0; }
    run dbtune_lifecycle_check_backup "" <<<"POTVRDZUJEM OBNOVITELNU ZALOHU"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chýba autoritatívny dôkaz poslednej úspešnej zálohy. Overte obnovu mimo Wooptima DB Tuner."* ]]
}

@test "English backup confirmation accepts only its exact trusted phrase and records a stable ID" {
    dbtune_i18n_set en
    dbtune_lifecycle_is_interactive() { return 0; }

    run dbtune_lifecycle_check_backup "" <<<'I CONFIRM A RESTORABLE BACKUP'

    [ "$status" -eq 0 ]
    [[ "$output" == *'Authoritative evidence of the last successful backup is missing. Verify restoration outside Wooptima DB Tuner.'* ]]
    [[ "$output" == *'Type exactly to continue: I CONFIRM A RESTORABLE BACKUP'* ]]
    grep -F '"confirmation_id":"restorable_backup"' "$(dbtune_events_file)"
    grep -F '"ui_lang":"en"' "$(dbtune_events_file)"
    ! grep -F 'I CONFIRM A RESTORABLE BACKUP' "$(dbtune_events_file)"
}

@test "Slovak backup confirmation accepts only its exact trusted phrase and records a stable ID" {
    dbtune_i18n_set sk
    dbtune_lifecycle_is_interactive() { return 0; }

    run dbtune_lifecycle_check_backup "" <<<'POTVRDZUJEM OBNOVITELNU ZALOHU'

    [ "$status" -eq 0 ]
    [[ "$output" == *'Chýba autoritatívny dôkaz poslednej úspešnej zálohy. Overte obnovu mimo Wooptima DB Tuner.'* ]]
    [[ "$output" == *'Pre pokračovanie napíšte presne: POTVRDZUJEM OBNOVITELNU ZALOHU'* ]]
    grep -F '"confirmation_id":"restorable_backup"' "$(dbtune_events_file)"
    grep -F '"ui_lang":"sk"' "$(dbtune_events_file)"
    ! grep -F 'POTVRDZUJEM OBNOVITELNU ZALOHU' "$(dbtune_events_file)"
}

@test "backup confirmation rejects the exact phrase from the wrong language" {
    dbtune_lifecycle_is_interactive() { return 0; }
    dbtune_i18n_set en

    run dbtune_lifecycle_check_backup "" <<<'POTVRDZUJEM OBNOVITELNU ZALOHU'
    [ "$status" -eq 77 ]

    dbtune_i18n_set sk
    run dbtune_lifecycle_check_backup "" <<<'I CONFIRM A RESTORABLE BACKUP'
    [ "$status" -eq 77 ]
    [ ! -e "$(dbtune_events_file)" ]
}

@test "rollback instructions and apply reports follow the selected language" {
    dbtune_i18n_set en
    run cmd_apply
    [ "$status" -eq 0 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    grep -F '# Filesystem-first rollback; does not require a working MariaDB or Wooptima DB Tuner.' "$history/ROLLBACK.txt"
    grep -F 'Configuration restored; restart MariaDB through the RunCloud panel.' "$history/ROLLBACK.txt"
    apply_event=$(grep -F '"event":"apply_completed"' "$(dbtune_events_file)")
    [[ "$apply_event" == *'"restart":"false"'* ]]
    [[ "$apply_event" == *'"force":"false"'* ]]
    [[ "$apply_event" == *'"original":"false"'* ]]

    mkdir "$BATS_TEST_TMPDIR/forced-en"
    run dbtune_lifecycle_mark_unmeasured "$BATS_TEST_TMPDIR/forced-en"
    [ "$status" -eq 0 ]
    grep -F '# APPLY REPORT' "$BATS_TEST_TMPDIR/forced-en/apply-report.md"
    grep -F '**WITHOUT MEASUREMENTS** - the configuration was applied with interactive --force.' "$BATS_TEST_TMPDIR/forced-en/apply-report.md"
    force_event=$(grep -F '"event":"apply_force"' "$(dbtune_events_file)")
    [[ "$force_event" == *'"measurement":"without_measurements"'* ]]
    [[ "$force_event" == *'"ui_lang":"en"'* ]]
    [[ "$force_event" != *'"status_id"'* ]]
    [[ "$force_event" != *'WITHOUT MEASUREMENTS'* ]]

    dbtune_i18n_set sk
    mkdir "$BATS_TEST_TMPDIR/forced-sk"
    run dbtune_lifecycle_mark_unmeasured "$BATS_TEST_TMPDIR/forced-sk"
    [ "$status" -eq 0 ]
    grep -F '# REPORT NASADENIA' "$BATS_TEST_TMPDIR/forced-sk/apply-report.md"
    grep -F '**BEZ MERANIA** - konfigurácia bola aplikovaná cez interaktívny --force.' "$BATS_TEST_TMPDIR/forced-sk/apply-report.md"
}

@test "Slovak rollback instructions use the selected language" {
    dbtune_i18n_set sk

    run cmd_apply

    [ "$status" -eq 0 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    grep -F '# Filesystem-first rollback; nevyžaduje funkčnú MariaDB ani Wooptima DB Tuner.' "$history/ROLLBACK.txt"
    grep -F 'Konfigurácia bola obnovená; reštartujte MariaDB cez RunCloud panel.' "$history/ROLLBACK.txt"
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

@test "verify 24h compares current counters with the successful post-restart baseline" {
    cmd_apply >/dev/null
    cmd_verify --post >/dev/null
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ -s "$history/post-status.tsv" ]
    run cmd_verify --24h
    [ "$status" -eq 0 ]
    [[ "$output" == *$'METRIC\tBASELINE\tCURRENT\tDELTA_OR_RESET'* ]]
    [[ "$output" == *$'uptime\t100\t100\t0'* ]]
}

@test "verify 24h requires a successful post-restart baseline" {
    cmd_apply >/dev/null
    run cmd_verify --24h
    [ "$status" -ne 0 ]
    [[ "$output" == *"verify --post"* ]]
    [ "$(dbtune_state_read)" = applied ]
}

@test "verify rejects a missing changed or symlink target" {
    cmd_apply >/dev/null
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")

    rm "$DBTUNE_CONFIG_TARGET"
    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *"TARGET ERROR"* ]]

    cp "$history/proposed.cnf" "$DBTUNE_CONFIG_TARGET"
    printf '# changed\n' >>"$DBTUNE_CONFIG_TARGET"
    chmod 644 "$DBTUNE_CONFIG_TARGET"
    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *"deployed configuration hash"* ]]

    rm "$DBTUNE_CONFIG_TARGET"
    ln -s "$history/proposed.cnf" "$DBTUNE_CONFIG_TARGET"
    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *"symlink"* ]]
    [ "$(dbtune_state_read)" = applied ]
}

@test "verify rejects an unexpected target mode" {
    cmd_apply >/dev/null
    cmd_verify --post >/dev/null
    [ "$(dbtune_state_read)" = verified ]
    chmod 600 "$DBTUNE_CONFIG_TARGET"
    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *"mode=600"* ]]
    [ "$(dbtune_state_read)" = applied ]
}

@test "verify rejects a hard-linked managed target" {
    cmd_apply >/dev/null
    ln "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/verify-target-alias.cnf"

    run cmd_verify --post

    [ "$status" -ne 0 ]
    [[ "$output" == *"hard-link topology"* ]]
    [ "$(dbtune_state_read)" = applied ]
    cmp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/verify-target-alias.cnf"
}

@test "rollback rejects a hard-linked target before target mutation" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    cp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/deployed-before-rollback.cnf"
    ln "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/rollback-target-alias.cnf"

    run cmd_rollback

    [ "$status" -ne 0 ]
    [[ "$output" == *"multiple hard links"* ]]
    cmp "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/deployed-before-rollback.cnf"
    cmp "$BATS_TEST_TMPDIR/rollback-target-alias.cnf" "$BATS_TEST_TMPDIR/deployed-before-rollback.cnf"
    [ "$(dbtune_lifecycle_file_links "$DBTUNE_CONFIG_TARGET")" = 2 ]
}

@test "health counters use reset-aware deltas from the post-restart baseline" {
    export STUB_STATUS=$'uptime\t100\ninnodb_buffer_pool_wait_free\t5\ninnodb_log_waits\t7\naborted_connects\t9'
    cmd_apply >/dev/null

    run cmd_verify --post
    [ "$status" -eq 0 ]
    [[ "$output" == *"innodb_log_waits baseline=7 current=7 delta=0 reset=false"* ]]

    dbtune_state_write applied
    export STUB_STATUS=$'uptime\t110\ninnodb_buffer_pool_wait_free\t5\ninnodb_log_waits\t8\naborted_connects\t9'
    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *"innodb_log_waits baseline=7 current=8 delta=1 reset=false"* ]]

    export STUB_STATUS=$'uptime\t10\ninnodb_buffer_pool_wait_free\t0\ninnodb_log_waits\t0\naborted_connects\t0'
    run cmd_verify --post
    [ "$status" -eq 0 ]
    [[ "$output" == *"innodb_log_waits baseline=7 current=0 delta=0 reset=true"* ]]
}

@test "verify 24h does not hide growth equal to a pre-restart counter" {
    export STUB_STATUS=$'uptime\t1000\ninnodb_buffer_pool_wait_free\t100\ninnodb_log_waits\t100\naborted_connects\t100'
    cmd_apply >/dev/null
    export STUB_STATUS=$'uptime\t10\ninnodb_buffer_pool_wait_free\t0\ninnodb_log_waits\t0\naborted_connects\t0'
    cmd_verify --post >/dev/null

    export STUB_STATUS=$'uptime\t1000\ninnodb_buffer_pool_wait_free\t100\ninnodb_log_waits\t100\naborted_connects\t100'
    run cmd_verify --24h
    [ "$status" -ne 0 ]
    [[ "$output" == *"innodb_log_waits baseline=0 current=100 delta=100 reset=false"* ]]
    [ "$(dbtune_state_read)" = applied ]
}

@test "event failure does not undo a committed apply state" {
    dbtune_event() { return 1; }
    run cmd_apply
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = applied ]
    [ -r "$DBTUNE_STATE_DIR/apply/current" ]
}

@test "copy publish and chown failures leave the previous state and target" {
    export STUB_FAIL_CP_MATCH=/proposed.cnf
    run cmd_apply
    [ "$status" -ne 0 ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]

    export STUB_FAIL_CP_MATCH=
    export DBTUNE_PUBLISH_FAIL_MATCH=.99-zz-tuning.cnf.tmp
    run cmd_apply
    [ "$status" -ne 0 ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]

    unset DBTUNE_PUBLISH_FAIL_MATCH
    export STUB_FAIL_CHOWN_MATCH=root:root
    run cmd_apply
    [ "$status" -ne 0 ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$DBTUNE_CONFIG_TARGET" ]
}

@test "interrupted apply after intent publication recovers without mutating the target" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_FAULT_INJECT=after_intent

    run cmd_apply
    [ "$status" -eq 99 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_state_read)" = proposed ]
    [ -r "$(dbtune_lifecycle_intent_file)" ]

    unset DBTUNE_FAULT_INJECT
    run dbtune_lifecycle_recover_if_needed
    [ "$status" -eq 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$(dbtune_lifecycle_intent_file)" ]
}

@test "interrupted apply after config install restores the exact previous cycle" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_FAULT_INJECT=after_config

    run cmd_apply
    [ "$status" -eq 99 ]
    cmp "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" "$DBTUNE_CONFIG_TARGET"
    [ "$(dbtune_state_read)" = proposed ]
    [ -r "$(dbtune_lifecycle_intent_file)" ]

    unset DBTUNE_FAULT_INJECT
    run dbtune_lifecycle_recover_if_needed
    [ "$status" -eq 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$DBTUNE_STATE_DIR/apply/current" ]
    [ ! -e "$(dbtune_lifecycle_intent_file)" ]
}

@test "recovery detects a target swap after validation before restore publication" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_FAULT_INJECT=after_config
    run cmd_apply
    [ "$status" -eq 99 ]
    unset DBTUNE_FAULT_INJECT

    cat >"$BATS_TEST_TMPDIR/swap-recovery-target" <<'STUB'
#!/usr/bin/env bash
mv "$DBTUNE_CONFIG_TARGET" "$BATS_TEST_TMPDIR/interrupted-proposal.cnf"
printf 'replacement\n' >"$DBTUNE_CONFIG_TARGET"
chmod 644 "$DBTUNE_CONFIG_TARGET"
STUB
    chmod +x "$BATS_TEST_TMPDIR/swap-recovery-target"
    export DBTUNE_PUBLISH_FAULT_HOOK="$BATS_TEST_TMPDIR/swap-recovery-target"
    run dbtune_lifecycle_recover_if_needed

    [ "$status" -ne 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = replacement ]
    [ "$(dbtune_state_read)" = recovery_required ]
    [ -r "$(dbtune_lifecycle_intent_file)" ]
}

@test "interrupted apply after current publication restores previous bookkeeping" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_FAULT_INJECT=after_current

    run cmd_apply
    [ "$status" -eq 99 ]
    [ -r "$DBTUNE_STATE_DIR/apply/current" ]
    [ "$(dbtune_state_read)" = proposed ]
    cmp "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" "$DBTUNE_CONFIG_TARGET"

    unset DBTUNE_FAULT_INJECT
    run dbtune_lifecycle_recover_if_needed
    [ "$status" -eq 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$DBTUNE_STATE_DIR/apply/current" ]
    [ ! -e "$(dbtune_lifecycle_intent_file)" ]
}

@test "interrupted apply after state publication finalizes the committed cycle" {
    export DBTUNE_FAULT_INJECT=after_state

    run cmd_apply
    [ "$status" -eq 99 ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ "$(dbtune_state_read)" = applied ]
    cmp "$history/proposed.cnf" "$DBTUNE_CONFIG_TARGET"
    [ -r "$(dbtune_lifecycle_intent_file)" ]

    unset DBTUNE_FAULT_INJECT
    run dbtune_lifecycle_recover_if_needed
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = applied ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$history" ]
    cmp "$history/proposed.cnf" "$DBTUNE_CONFIG_TARGET"
    [ ! -e "$(dbtune_lifecycle_intent_file)" ]
}

@test "next locked lifecycle command recovers a published apply intent" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export DBTUNE_FAULT_INJECT=after_config

    run dbtune_dispatch apply
    [ "$status" -eq 99 ]
    cmp "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" "$DBTUNE_CONFIG_TARGET"

    unset DBTUNE_FAULT_INJECT
    run dbtune_dispatch rollback
    [ "$status" -eq 65 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_state_read)" = proposed ]
    [ ! -e "$(dbtune_lifecycle_intent_file)" ]
}

@test "failed restore preserves current and exposes recovery instructions" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export STUB_RESTART_FAIL=1
    export DBTUNE_PUBLISH_FAIL_MATCH=.99-zz-restore
    run cmd_apply --restart
    [ "$status" -ne 0 ]
    [ "$(dbtune_state_read)" = recovery_required ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ -r "$history/RECOVERY_REQUIRED" ]
    [ -r "$history/ROLLBACK.txt" ]

    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"recovery_required: true"* ]]
    [[ "$output" == *"sudo dbtune rollback"* ]]
    [[ "$output" == *"$history/ROLLBACK.txt"* ]]
}

@test "systemctl start failure after restored restart remains recoverable" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    export STUB_RESTART_FAIL=1
    export STUB_START_FAIL=1
    run cmd_apply --restart
    [ "$status" -ne 0 ]
    [ "$(cat "$DBTUNE_CONFIG_TARGET")" = original ]
    [ "$(dbtune_state_read)" = recovery_required ]
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    [ -r "$history/RECOVERY_REQUIRED" ]
}

@test "rollback restore failure records rollback_failed and keeps its pointer" {
    printf 'original\n' >"$DBTUNE_CONFIG_TARGET"
    cmd_apply >/dev/null
    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    export DBTUNE_PUBLISH_FAIL_MATCH=.99-zz-restore
    run cmd_rollback
    [ "$status" -ne 0 ]
    [ "$(dbtune_state_read)" = rollback_failed ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$history" ]
    [ -r "$history/ROLLBACK_FAILED" ]
}

@test "status is filesystem-only and works without mariadb" {
    rm "$BATS_TEST_TMPDIR/bin/mariadb"
    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"state: proposed"* ]]
    [[ "$output" == *"config_present: false"* ]]
}

@test "status booleans remain true or false in both interface languages" {
    dbtune_i18n_set en
    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *$'config_present: false'* ]]
    [[ "$output" == *$'baseline_present: false'* ]]
    [[ "$output" == *$'rollback_available: false'* ]]
    [[ "$output" == *$'recovery_required: false'* ]]
    [[ "$output" != *': ano'* && "$output" != *': nie'* ]]

    dbtune_i18n_set sk
    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *$'config_present: false'* ]]
    [[ "$output" == *$'baseline_present: false'* ]]
    [[ "$output" == *$'rollback_available: false'* ]]
    [[ "$output" == *$'recovery_required: false'* ]]
    [[ "$output" != *': ano'* && "$output" != *': nie'* ]]
}

@test "verify output and recovery explanations follow the selected language" {
    dbtune_i18n_set en
    run cmd_apply
    [ "$status" -eq 0 ]
    rm "$DBTUNE_CONFIG_TARGET"

    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *'TARGET ERROR:'* ]]

    dbtune_i18n_set sk
    run cmd_verify --post
    [ "$status" -ne 0 ]
    [[ "$output" == *'CHYBA CIEĽA:'* ]]

    history=$(cat "$DBTUNE_STATE_DIR/apply/current")
    dbtune_state_write recovery_required
    printf 'phase\ttest\n' >"$history/RECOVERY_REQUIRED"
    dbtune_i18n_set en
    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"recovery_instruction: sudo dbtune rollback; manually: $history/ROLLBACK.txt"* ]]

    dbtune_i18n_set sk
    run cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"recovery_instruction: sudo dbtune rollback; manuálne: $history/ROLLBACK.txt"* ]]
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

    (
        dbtune_test_close_non_std_fds
        dbtune_dispatch apply
    ) >"$BATS_TEST_TMPDIR/apply.out" 2>&1 &
    apply_pid=$!
    for _ in {1..200}; do
        [[ -e $BATS_TEST_TMPDIR/apply-paused ]] && break
        sleep 0.01
    done
    [ -e "$BATS_TEST_TMPDIR/apply-paused" ]

    (
        dbtune_test_close_non_std_fds
        dbtune_dispatch propose
    ) >"$BATS_TEST_TMPDIR/propose.out" 2>&1 &
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

@test "apply rejects reason_sk analysis without mutating lifecycle artifacts" {
    local analysis_hash backup_hash proposal_hash proposal_manifest_hash state_before target_hash

    awk -F '\t' 'BEGIN {OFS="\t"} NR==1 {$8="reason_sk"} {print}' "$DBTUNE_STATE_DIR/analysis.tsv" >"$BATS_TEST_TMPDIR/old-analysis.tsv"
    mv "$BATS_TEST_TMPDIR/old-analysis.tsv" "$DBTUNE_STATE_DIR/analysis.tsv"
    printf 'original target\n' >"$DBTUNE_CONFIG_TARGET"
    analysis_hash=$(dbtune_sha256_file "$DBTUNE_STATE_DIR/analysis.tsv")
    backup_hash=$(dbtune_sha256_file "$(dbtune_backup_evidence_file)")
    proposal_hash=$(dbtune_sha256_file "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf")
    proposal_manifest_hash=$(dbtune_sha256_file "$DBTUNE_STATE_DIR/proposal-manifest.tsv")
    state_before=$(dbtune_state_read)
    target_hash=$(dbtune_sha256_file "$DBTUNE_CONFIG_TARGET")
    dbtune_i18n_set en
    mktemp() {
        printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/mktemp.log"
        command mktemp "$@"
    }

    run cmd_apply

    [ "$status" -eq 65 ]
    [[ "$output" == *'start a new v0.4.0 audit and measurement cycle'* ]]
    [ "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/analysis.tsv")" = "$analysis_hash" ]
    [ "$(dbtune_sha256_file "$(dbtune_backup_evidence_file)")" = "$backup_hash" ]
    [ "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf")" = "$proposal_hash" ]
    [ "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/proposal-manifest.tsv")" = "$proposal_manifest_hash" ]
    [ "$(dbtune_state_read)" = "$state_before" ]
    [ "$(dbtune_sha256_file "$DBTUNE_CONFIG_TARGET")" = "$target_hash" ]
    [ ! -e "$BATS_TEST_TMPDIR/mktemp.log" ]
    [ ! -e "$DBTUNE_STATE_DIR/apply" ]
}

@test "publisher isolates Python from hostile module search paths" {
    mkdir "$BATS_TEST_TMPDIR/pythonpath"
    cat >"$BATS_TEST_TMPDIR/pythonpath/sitecustomize.py" <<'PY'
import os

with open(os.environ["PYTHON_STARTUP_MARKER"], "w", encoding="utf-8") as marker:
    marker.write("loaded\n")
PY
    export PYTHONPATH="$BATS_TEST_TMPDIR/pythonpath"
    export PYTHON_STARTUP_MARKER="$BATS_TEST_TMPDIR/python-startup-marker"

    run cmd_apply

    [ "$status" -eq 0 ]
    [ ! -e "$PYTHON_STARTUP_MARKER" ]
}
