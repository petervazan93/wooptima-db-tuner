#!/usr/bin/env bats

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
    export DBTUNE_SLOW_LOG="$BATS_TEST_TMPDIR/log/slow.log"
    export DBTUNE_LOG_LEVEL=quiet
    export DBTUNE_NOW_EPOCH=1000000
    export DBTUNE_SYSTEMCTL=fake_systemctl
    export DBTUNE_FLOCK=fake_flock
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

fake_flock() {
    if [[ -z ${DBTUNE_RACE_LOCK_DIR:-} ]]; then
        return 0
    fi
    case $1 in
        -n)
            mkdir "$DBTUNE_RACE_LOCK_DIR" 2>/dev/null
            ;;
        -x)
            while ! mkdir "$DBTUNE_RACE_LOCK_DIR" 2>/dev/null; do
                sleep 0.01
            done
            ;;
        -u)
            rmdir "$DBTUNE_RACE_LOCK_DIR" 2>/dev/null || true
            ;;
    esac
}

write_collect_config() {
    local deadline=${1:-2000000}

    {
        printf 'slow_log_file\t%s\n' "$DBTUNE_SLOW_LOG"
        printf 'long_query_time\t0.5\n'
        printf 'deadline_epoch\t%s\n' "$deadline"
        printf 'original_slow_query_log\t1\n'
        printf 'original_slow_query_log_file\t/var/lib/mysql/original-slow.log\n'
        printf 'original_long_query_time\t10.000000\n'
    } >"$(dbtune_collect_config_file)"
}

retryable_restore_sql() {
    printf '%s\n' "$1" >>"$BATS_TEST_TMPDIR/sql.log"
    [[ -e $BATS_TEST_TMPDIR/allow-restore ]]
}

write_sample_rows() {
    local count=$1 file

    file=$(dbtune_collect_samples_file)
    printf 'header\n' >"$file"
    for ((i = 0; i < count; i++)); do
        printf 'sample-%s\n' "$i" >>"$file"
    done
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
    [ "$output" = $'state\taudited\nhealth_timestamp\tunknown\nhealth_status\tunknown\nhealth_detail\t\nlast_sample_age_seconds\tunknown\nsample_state\tmissing\nguard_state\tnone' ]
    [ ! -e "$BATS_TEST_TMPDIR/sql.log" ]
    [ ! -e "$BATS_TEST_TMPDIR/systemctl.log" ]
}

@test "stop disables activations and waits for an active tick lock" {
    dbtune_state_write collecting
    write_collect_config
    export DBTUNE_RACE_LOCK_DIR="$BATS_TEST_TMPDIR/held-lock"
    dbtune_collect_tick_body() {
        touch "$BATS_TEST_TMPDIR/tick-entered"
        while [[ ! -e $BATS_TEST_TMPDIR/tick-release ]]; do
            sleep 0.01
        done
    }

    cmd_tick >"$BATS_TEST_TMPDIR/tick.out" &
    tick_pid=$!
    for _ in {1..200}; do
        [[ -e $BATS_TEST_TMPDIR/tick-entered ]] && break
        sleep 0.01
    done
    [ -e "$BATS_TEST_TMPDIR/tick-entered" ]

    cmd_collect stop >"$BATS_TEST_TMPDIR/stop.out" &
    stop_pid=$!
    for _ in {1..200}; do
        [[ -e $BATS_TEST_TMPDIR/systemctl.log ]] && grep -q 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log" && break
        sleep 0.01
    done
    grep -q 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    kill -0 "$stop_pid"
    [ "$(dbtune_state_read)" = collecting ]

    touch "$BATS_TEST_TMPDIR/tick-release"
    wait "$tick_pid"
    wait "$stop_pid"
    [ "$(dbtune_state_read)" = collected ]
    grep -F 'SET GLOBAL slow_query_log=1' "$BATS_TEST_TMPDIR/sql.log"
}

@test "failed manual restore remains recoverable and stop retries it" {
    dbtune_state_write collecting
    write_collect_config
    dbtune_sql() {
        printf '%s\n' "$1" >>"$BATS_TEST_TMPDIR/sql.log"
        [[ -e $BATS_TEST_TMPDIR/allow-restore ]]
    }

    run cmd_collect stop
    [ "$status" -eq 1 ]
    [ "$(dbtune_state_read)" = collecting ]
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = restore_pending ]
    sql_lines=$(awk 'END { print NR }' "$BATS_TEST_TMPDIR/sql.log")
    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(awk 'END { print NR }' "$BATS_TEST_TMPDIR/sql.log")" -eq "$sql_lines" ]

    touch "$BATS_TEST_TMPDIR/allow-restore"
    run cmd_collect stop
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collected ]
}

@test "guard restore failure pauses collection and retry stop succeeds" {
    dbtune_state_write collecting
    write_collect_config
    export DBTUNE_MIN_FREE_KB=999999999999
    dbtune_sql() { retryable_restore_sql "$@"; }

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collecting ]
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = restore_pending ]
    grep -F 'reason=low_disk' "$(dbtune_collect_health_file)"
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"

    sql_lines=$(awk 'END { print NR }' "$BATS_TEST_TMPDIR/sql.log")
    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(awk 'END { print NR }' "$BATS_TEST_TMPDIR/sql.log")" -eq "$sql_lines" ]

    touch "$BATS_TEST_TMPDIR/allow-restore"
    run cmd_collect stop
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collected ]
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = stopped ]
}

@test "incomplete deadline restore failure remains paused and retryable" {
    dbtune_state_write collecting
    write_collect_config 999999
    dbtune_sql() { retryable_restore_sql "$@"; }
    cmd_analyze() { touch "$BATS_TEST_TMPDIR/analyzed"; }
    cmd_report() { touch "$BATS_TEST_TMPDIR/reported"; }

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collecting ]
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = restore_pending ]
    grep -F 'reason=deadline samples=0 minimum=288' "$(dbtune_collect_health_file)"
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    [ ! -e "$BATS_TEST_TMPDIR/analyzed" ]
    [ ! -e "$BATS_TEST_TMPDIR/reported" ]

    touch "$BATS_TEST_TMPDIR/allow-restore"
    run cmd_collect stop
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collected ]
}

@test "auto finalize restore failure does not run analysis or report" {
    dbtune_state_write collecting
    write_collect_config 999999
    write_sample_rows 288
    dbtune_sql() { retryable_restore_sql "$@"; }
    cmd_analyze() { touch "$BATS_TEST_TMPDIR/analyzed"; }
    cmd_report() { touch "$BATS_TEST_TMPDIR/reported"; }

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collecting ]
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = restore_pending ]
    grep -F 'reason=deadline samples=288' "$(dbtune_collect_health_file)"
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    [ ! -e "$BATS_TEST_TMPDIR/analyzed" ]
    [ ! -e "$BATS_TEST_TMPDIR/reported" ]
}

@test "tick detects restart identity when new uptime passed old uptime and self heals" {
    dbtune_state_write collecting
    write_collect_config
    printf '100\t1000\t999700\t111\t10\n' >"$(dbtune_collect_last_uptime_file)"
    export DBTUNE_MONOTONIC=1300
    export DBTUNE_SLEEP=true
    dbtune_collect_guards() { return 0; }
    dbtune_collect_status_snapshot() {
        local count_file="$BATS_TEST_TMPDIR/status-count" count=0
        [[ -r $count_file ]] && read -r count <"$count_file"
        count=$((count + 1))
        printf '%s\n' "$count" >"$count_file"
        if ((count == 1)); then
            printf '299\t10\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2\n'
        else
            printf '359\t20\t1200\t16000\t500\t8\t30\t4\t10\t140\t360\t3\t5\n'
        fi
    }
    dbtune_collect_cpu_snapshot() {
        local count_file="$BATS_TEST_TMPDIR/cpu-count" count=0
        [[ -r $count_file ]] && read -r count <"$count_file"
        count=$((count + 1))
        printf '%s\n' "$count" >"$count_file"
        printf '222\t%s\t20\n' "$((count * 100))"
    }
    dbtune_collect_memory_snapshot() { printf '900000\t12000\n'; }
    dbtune_collect_load1() { printf '0.5\n'; }
    dbtune_collect_daily_dbsize() { return 0; }
    dbtune_sql() {
        printf '%s\n' "$1" >>"$BATS_TEST_TMPDIR/sql.log"
        if [[ $1 == 'SELECT @@GLOBAL.slow_query_log, @@GLOBAL.slow_query_log_file, @@GLOBAL.long_query_time;' ]]; then
            printf '0\t/var/lib/mysql/default-slow.log\t10.000000\n'
        fi
    }

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(awk -F '\t' 'END { print $17 }' "$(dbtune_collect_samples_file)")" -eq 1 ]
    grep -F 'SET GLOBAL slow_query_log=ON' "$BATS_TEST_TMPDIR/sql.log"
    grep -F '"event":"db_restart_detected"' "$(dbtune_events_file)"
    grep -F '"event":"collect_slow_log_self_healed"' "$(dbtune_events_file)"
    grep -F $'\tok\trestart_flag=1 slow_log=healed\t' "$(dbtune_collect_health_file)"
}

@test "disk guard disables timer and terminates collection" {
    dbtune_state_write collecting
    write_collect_config
    export DBTUNE_MIN_FREE_KB=999999999999

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collected ]
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = guard ]
    grep -F 'reason=low_disk' "$(dbtune_collect_health_file)"
    [ ! -e "$(dbtune_collect_samples_file)" ]
}

@test "sample and slow log size guards terminate with their reason" {
    export DBTUNE_MIN_FREE_KB=0
    for expected in samples_limit slow_log_limit; do
        dbtune_state_write collecting
        write_collect_config
        rm -f "$(dbtune_collect_samples_file)" "$DBTUNE_SLOW_LOG" "$(dbtune_collect_health_file)"
        export DBTUNE_MAX_SAMPLES_BYTES=2147483648
        export DBTUNE_MAX_SLOW_LOG_BYTES=2147483648
        if [[ $expected == samples_limit ]]; then
            printf 'oversized sample file\n' >"$(dbtune_collect_samples_file)"
            export DBTUNE_MAX_SAMPLES_BYTES=1
        else
            printf 'oversized slow log\n' >"$DBTUNE_SLOW_LOG"
            export DBTUNE_MAX_SLOW_LOG_BYTES=1
        fi

        run cmd_tick
        [ "$status" -eq 0 ]
        [ "$(dbtune_state_read)" = collected ]
        [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = guard ]
        grep -F "reason=$expected" "$(dbtune_collect_health_file)"
    done
}

@test "deadline with too few samples is terminal and skips analysis" {
    dbtune_state_write collecting
    write_collect_config 999999
    cmd_analyze() { touch "$BATS_TEST_TMPDIR/analyzed"; }

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = collected ]
    [ "$(awk -F '\t' '{ print $2 }' "$(dbtune_collect_health_file)")" = incomplete ]
    grep -F 'samples=0 minimum=288' "$(dbtune_collect_health_file)"
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    [ ! -e "$BATS_TEST_TMPDIR/analyzed" ]
    [ ! -e "$(dbtune_collect_samples_file)" ]
}

@test "status reports health sample age stale and guard state" {
    dbtune_state_write collected
    printf '200\t1300\t999900\t222\t20\n' >"$(dbtune_collect_last_uptime_file)"
    dbtune_collect_health guard 'reason=slow_log_limit'
    export DBTUNE_STALE_SAMPLE_SECONDS=50

    run cmd_collect status
    [ "$status" -eq 0 ]
    [[ "$output" == *$'health_timestamp\t'* ]]
    [[ "$output" == *$'health_status\tguard'* ]]
    [[ "$output" == *$'health_detail\treason=slow_log_limit'* ]]
    [[ "$output" == *$'last_sample_age_seconds\t100'* ]]
    [[ "$output" == *$'sample_state\tstale'* ]]
    [[ "$output" == *$'guard_state\ttriggered'* ]]
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
