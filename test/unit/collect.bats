#!/usr/bin/env bats

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
    export DBTUNE_SLOW_LOG="$BATS_TEST_TMPDIR/log/slow.log"
    export DBTUNE_LOG_LEVEL=quiet
    export DBTUNE_NOW_EPOCH=1000000
    export DBTUNE_SYSTEMCTL=fake_systemctl
    mkdir -p "$DBTUNE_STATE_DIR" "$DBTUNE_SYSTEMD_DIR" "${DBTUNE_SLOW_LOG%/*}"
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/30-collect.sh"
    dbtune_sql() {
        printf '%s\n' "$1" >>"$BATS_TEST_TMPDIR/sql.log"
        if [[ $1 == SELECT\ @@GLOBAL.slow_query_log* ]]; then
            printf '0\t/var/lib/mysql/original-slow.log\t10.000000\tquery_plan\n'
        fi
    }
}

fake_systemctl() {
    printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl.log"
}

dbtune_embedded_get() {
    case $1 in
        systemd/dbtune-collect.service) command cat "$BATS_TEST_DIRNAME/../../systemd/dbtune-collect.service" ;;
        systemd/dbtune-collect.timer) command cat "$BATS_TEST_DIRNAME/../../systemd/dbtune-collect.timer" ;;
        *) return 64 ;;
    esac
}

@test "delta metrics use counter differences" {
    first=$'100\t10\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2'
    second=$'160\t20\t1200\t16000\t500\t8\t30\t4\t10\t140\t360\t3\t5'

    run dbtune_collect_delta now "$first" "$second" 60 $'7\t100' $'7\t400' 100 $'900000\t12000' 1.25 0
    [ "$status" -eq 0 ]
    [ "$output" = $'now\t160\t95.00\t0.17\t100.00\t5.00\t30.00\t4\t10\t40.00\t2\t3\t5.00\t900000\t12000\t1.25\t0' ]
}

@test "uptime reset zeroes deltas and marks restart" {
    first=$'500\t100\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2'
    second=$'20\t2\t30\t400\t10\t1\t2\t1\t3\t4\t8\t0\t0'

    run dbtune_collect_delta now "$first" "$second" 60 $'7\t500' $'8\t20' 100 $'900000\t12000' 0.50 1
    [ "$status" -eq 0 ]
    [[ "$output" == $'now\t20\t100.00\t0.00\t0.00\t0.00\t0.00\t1\t3\t0.00\t0\t0\t0.00\t900000\t12000\t0.50\t1' ]]
}

@test "sample header is exact and idempotent" {
    dbtune_collect_append_sample 'one'
    dbtune_collect_append_sample 'two'

    run awk 'END { print NR }' "$(dbtune_collect_samples_file)"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
    run awk 'NR == 1 { print }' "$(dbtune_collect_samples_file)"
    [ "$output" = $'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag' ]
}

@test "start validates arguments" {
    dbtune_state_write audited

    run cmd_collect start --days 0
    [ "$status" -eq 64 ]
    run cmd_collect start --long-query-time nope
    [ "$status" -eq 64 ]
    run cmd_collect start --unknown
    [ "$status" -eq 64 ]
}

@test "start saves runtime values and enables embedded timer" {
    dbtune_state_write audited

    run cmd_collect start --days 3 --long-query-time 0.5
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collecting ]
    [ "$(dbtune_collect_value days)" = 3 ]
    [ "$(dbtune_collect_value deadline_epoch)" = 1259200 ]
    grep -F 'ExecStart=/usr/local/bin/dbtune _tick' "$DBTUNE_SYSTEMD_DIR/dbtune-collect.service"
    grep -F 'OnCalendar=*:0/5' "$DBTUNE_SYSTEMD_DIR/dbtune-collect.timer"
    grep -F 'enable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    grep -F 'SET GLOBAL slow_query_log=ON' "$BATS_TEST_TMPDIR/sql.log"
}

@test "status does not invoke SQL or systemctl" {
    dbtune_state_write audited
    rm -f "$BATS_TEST_TMPDIR/sql.log" "$BATS_TEST_TMPDIR/systemctl.log"

    run cmd_collect status
    [ "$status" -eq 0 ]
    [ "$output" = $'state\taudited' ]
    [ ! -e "$BATS_TEST_TMPDIR/sql.log" ]
    [ ! -e "$BATS_TEST_TMPDIR/systemctl.log" ]
}

@test "stop disables timer restores values and transitions" {
    dbtune_state_write collecting
    cat >"$(dbtune_collect_config_file)" <<'CONFIG'
original_slow_query_log	1
original_slow_query_log_file	/var/lib/mysql/original-slow.log
original_long_query_time	10.000000
CONFIG

    run cmd_collect stop
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collected ]
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    grep -F "SET GLOBAL slow_query_log_file='/var/lib/mysql/original-slow.log'" "$BATS_TEST_TMPDIR/sql.log"
    grep -F 'SET GLOBAL slow_query_log=1' "$BATS_TEST_TMPDIR/sql.log"
}
