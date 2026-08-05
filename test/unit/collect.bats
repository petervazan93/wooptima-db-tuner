#!/usr/bin/env bats

setup() {
    unset DBTUNE_UI_LANG
    BATS_TEST_TMPDIR=$(CDPATH='' cd -- "$BATS_TEST_TMPDIR" && pwd -P)
    export BATS_TEST_TMPDIR
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd"
    export DBTUNE_SLOW_LOG="$BATS_TEST_TMPDIR/log/slow.log"
    export DBTUNE_LOG_LEVEL=quiet
    export DBTUNE_NOW_EPOCH=1000000
    export DBTUNE_SYSTEMCTL=fake_systemctl
    export DBTUNE_FLOCK=fake_flock
    mkdir -p "$DBTUNE_STATE_DIR" "$DBTUNE_SYSTEMD_DIR" "${DBTUNE_SLOW_LOG%/*}"
    chmod 700 "$DBTUNE_STATE_DIR"
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/05-i18n.sh"
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
    local ui_lang=${2:-en}

    {
        printf 'ui_lang\t%s\n' "$ui_lang"
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
    printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tcom_select_delta\tinterval_seconds\tsample_status\n' >"$file"
    for ((i = 0; i < count; i++)); do
        printf '2026-07-24T00:00:00Z\t%s\t99\t0\t0\t0\t0\t1\t1\t100\t0\t0\t1\t1000\t0\t1\t0\t1\t60\tok\n' "$i" >>"$file"
    done
}

status_snapshot_rows() {
    cat <<'EOF'
Uptime	100
Innodb_buffer_pool_reads	10
Innodb_buffer_pool_read_requests	100
Innodb_data_read	1000
Handler_read_rnd_next	20
Created_tmp_disk_tables	2
Created_tmp_tables	10
Threads_running	3
Threads_connected	8
Qcache_hits	30
Com_select	60
Innodb_log_waits	1
Innodb_buffer_pool_wait_free	0
EOF
}

dbtune_embedded_get() {
    case $1 in
        systemd/dbtune-collect.service) command cat "$BATS_TEST_DIRNAME/../../systemd/dbtune-collect.service" ;;
        systemd/dbtune-collect.timer) command cat "$BATS_TEST_DIRNAME/../../systemd/dbtune-collect.timer" ;;
        *) return 64 ;;
    esac
}

source_tick_dispatch() {
    source "$BATS_TEST_DIRNAME/../../lib/60-lifecycle.sh"
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
}

@test "collector usage defaults to English" {
    run dbtune_collect_usage

    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage:'* ]]
    [[ "$output" == *'--long-query-time SECONDS'* ]]

    run dbtune_msg cli_usage
    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage: dbtune <command> [options]'* ]]
    [[ "$output" == *'Show Wooptima DB Tuner status'* ]]
    [[ "$output" == *'Show Wooptima DB Tuner version'* ]]
}

@test "collector usage supports explicit Slovak" {
    dbtune_i18n_set sk

    run dbtune_collect_usage

    [ "$status" -eq 0 ]
    [[ "$output" == 'Pouzitie:'* ]]
    [[ "$output" == *'--long-query-time SEKUNDY'* ]]

    run dbtune_msg cli_usage
    [ "$status" -eq 0 ]
    [[ "$output" == 'Pouzitie: dbtune <prikaz> [volby]'* ]]
    [[ "$output" == *'Stav Wooptima DB Tuner'* ]]
    [[ "$output" == *'Verzia Wooptima DB Tuner'* ]]
}

@test "delta metrics use counter differences" {
    first=$'100\t10\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2'
    second=$'160\t20\t1200\t16000\t500\t8\t30\t4\t10\t140\t360\t3\t5'

    run dbtune_collect_delta now "$first" "$second" 60 $'7\t100' $'7\t400' 100 $'900000\t12000' 1.25 0
    [ "$status" -eq 0 ]
    [ "$output" = $'now\t160\t95.00\t0.17\t100.00\t5.00\t30.00\t4\t10\t66.67\t2\t3\t5.00\t900000\t12000\t1.25\t0\t60\t60.000000\tok' ]
}

@test "uint64 helpers preserve exact decimal boundaries and deltas" {
    run dbtune_uint64_valid 0
    [ "$status" -eq 0 ]
    run dbtune_uint64_valid 18446744073709551615
    [ "$status" -eq 0 ]
    run dbtune_uint64_valid 18446744073709551616
    [ "$status" -ne 0 ]
    run dbtune_uint64_valid 000000000000000000000000000000000000000000000000000000000000000000001
    [ "$status" -ne 0 ]
    run dbtune_uint64_valid 01
    [ "$status" -ne 0 ]

    run dbtune_uint64_compare 9007199254740992 9007199254740993
    [ "$status" -eq 0 ]
    [ "$output" = -1 ]
    run dbtune_uint64_subtract 9007199254740993 9007199254740992
    [ "$status" -eq 0 ]
    [ "$output" = 1 ]
    run dbtune_uint64_subtract 0 1
    [ "$status" -eq 65 ]
}

@test "uint64 collector deltas remain exact above the AWK integer range" {
    first=$'100\t9007199254740992\t9007199254740992\t9007199254740992\t9007199254740992\t9007199254740992\t9007199254740992\t2\t8\t9007199254740992\t9007199254740992\t9007199254740992\t9007199254740992'
    second=$'160\t9007199254740993\t9007199254740994\t9007199254740993\t9007199254740993\t9007199254740993\t9007199254740994\t2\t8\t9007199254740993\t9007199254740994\t9007199254740993\t9007199254740993'

    run dbtune_collect_delta now "$first" "$second" 60 $'7\t100\t20' $'7\t100\t20' 100 $'900000\t12000' 1.25 0

    [ "$status" -eq 0 ]
    [ "$(awk -F '\t' '{print $10, $11, $12, $18, $20}' <<<"$output")" = '50.00 1 1 2 ok' ]
}

@test "status snapshot rejects every malformed exact-schema response" {
    local key mutation raw
    local -a keys=(Uptime Innodb_buffer_pool_reads Innodb_buffer_pool_read_requests Innodb_data_read Handler_read_rnd_next Created_tmp_disk_tables Created_tmp_tables Threads_running Threads_connected Qcache_hits Com_select Innodb_log_waits Innodb_buffer_pool_wait_free)
    local -a mutations=(missing duplicate unknown extra_field empty signed decimal over_range conflicting)

    for key in "${keys[@]}"; do
        for mutation in "${mutations[@]}"; do
            raw=$(status_snapshot_rows)
            case $mutation in
                missing) raw=$(awk -F '\t' -v key="$key" '$1 != key' <<<"$raw") ;;
                duplicate) raw+=$'\n'"$(awk -F '\t' -v key="$key" '$1 == key' <<<"$raw")" ;;
                unknown) raw+=$'\nUnknown_counter\t1' ;;
                extra_field) raw=$(awk -F '\t' -v OFS='\t' -v key="$key" '$1 == key {$3="extra"} {print}' <<<"$raw") ;;
                empty) raw=$(awk -F '\t' -v OFS='\t' -v key="$key" '$1 == key {$2=""} {print}' <<<"$raw") ;;
                signed) raw=$(awk -F '\t' -v OFS='\t' -v key="$key" '$1 == key {$2="-1"} {print}' <<<"$raw") ;;
                decimal) raw=$(awk -F '\t' -v OFS='\t' -v key="$key" '$1 == key {$2="1.5"} {print}' <<<"$raw") ;;
                over_range) raw=$(awk -F '\t' -v OFS='\t' -v key="$key" '$1 == key {$2="18446744073709551616"} {print}' <<<"$raw") ;;
                conflicting) raw+=$'\n'"$key"$'\t999' ;;
            esac
            export DBTUNE_TEST_STATUS_RAW=$raw
            dbtune_sql() { printf '%s\n' "$DBTUNE_TEST_STATUS_RAW"; }
            run dbtune_collect_status_snapshot
            if [ "$status" -ne 65 ]; then
                printf 'unexpected snapshot result: key=%s mutation=%s status=%s output=%s\n' "$key" "$mutation" "$status" "$output" >&3
                false
            fi
            [ -z "$output" ]
        done
    done
}

@test "status snapshot accepts canonical uint64 boundaries without coercion" {
    dbtune_sql() {
        status_snapshot_rows | awk -F '\t' -v OFS='\t' '$1 == "Uptime" {$2="0"} $1 == "Com_select" {$2="18446744073709551615"} {print}'
    }

    run dbtune_collect_status_snapshot

    [ "$status" -eq 0 ]
    [ "$(awk -F '\t' '{print $1, $11}' <<<"$output")" = '0 18446744073709551615' ]
}

@test "every unaccounted cumulative counter reset degrades the sample" {
    local column
    local first=$'100\t10\t100\t1000\t20\t2\t10\t3\t8\t30\t60\t1\t1'
    local second

    for column in 2 3 4 5 6 7 10 11 12 13; do
        second=$(awk -F '\t' -v OFS='\t' -v column="$column" '{for (i=1;i<=NF;i++) $i=(i==column ? $i-1 : $i+10); print}' <<<"$first")
        run dbtune_collect_delta now "$first" "$second" 60 $'7\t100\t20' $'7\t200\t20' 100 $'900000\t12000' 1.25 0
        [ "$status" -eq 0 ]
        [ "$(awk -F '\t' '{print $20}' <<<"$output")" = degraded_counter_reset ]
    done
}

@test "restart identity is authoritative or degraded and never inferred from uptime alone" {
    run dbtune_collect_restart_status 100 1000 999000 10 20 110 170 1100 1000000 $'0\t0\t0' $'0\t0\t0'
    [ "$output" = degraded_restart_identity ]
    run dbtune_collect_restart_status 100 1000 999000 10 20 110 170 1100 1000000 $'10\t100\t20' $'0\t0\t0'
    [ "$output" = degraded_restart_identity ]
    run dbtune_collect_restart_status 100 1000 999000 10 20 110 170 1100 1000000 $'10\t100\t0' $'10\t100\t0'
    [ "$output" = degraded_restart_identity ]
    run dbtune_collect_restart_status 100 1000 999000 bad 20 110 170 1100 1000000 $'10\t100\t20' $'10\t100\t20'
    [ "$output" = degraded_restart_identity ]
    run dbtune_collect_restart_status 100 1000 999000 10 0 110 170 1100 1000000 $'10\t100\t20' $'10\t100\t20'
    [ "$output" = degraded_restart_identity ]
    run dbtune_collect_restart_status 100 1000 999000 10 20 110 170 1100 1000000 $'10\t100\t20' $'10\t100\t21'
    [ "$output" = restart ]
    run dbtune_collect_restart_status 100 1000 999000 10 20 110 170 1100 1000000 $'10\t100\t20' $'11\t100\t20'
    [ "$output" = restart ]

    run dbtune_collect_restart_status 10 1000 999000 10 20 70 130 1100 1000000 $'10\t100\t20' $'11\t100\t20'
    [ "$output" = restart ]
}

@test "counter inconsistent deltas are degraded and inspector rejects representable corruption" {
    local first=$'100\t10\t100\t1000\t20\t2\t10\t3\t8\t30\t60\t1\t1'
    local second
    local file

    for second in \
        $'160\t11\t110\t1010\t30\t3\t20\t3\t8\t32\t61\t2\t2' \
        $'160\t12\t101\t1010\t30\t3\t20\t3\t8\t31\t61\t2\t2' \
        $'160\t11\t110\t1010\t30\t4\t11\t3\t8\t31\t61\t2\t2'; do
        run dbtune_collect_delta now "$first" "$second" 60 $'7\t100\t20' $'7\t200\t20' 100 $'900000\t12000' 1.25 0
        [ "$status" -eq 0 ]
        [ "$(awk -F '\t' '{print $20}' <<<"$output")" = degraded_counter_inconsistent ]
    done

    file=$(dbtune_collect_samples_file)
    dbtune_collect_sample_header >"$file"
    {
        printf '2026-07-24T00:00:00Z\t300\t101\t1\t1024\t100\t20\t2\t5\t30\t0\t0\t5\t12000000\t0\t1\t0\t10\t60\tok\n'
        printf '2026-07-24T00:01:00Z\t360\t99\t1\t1024\t100\t101\t2\t5\t30\t0\t0\t5\t12000000\t0\t1\t0\t10\t60\tok\n'
        printf '2026-07-24T00:02:00Z\t420\t99\t1\t1024\t100\t20\t2\t5\t101\t0\t0\t5\t12000000\t0\t1\t0\t10\t60\tok\n'
        printf '2026-07-24T00:03:00Z\t480\t99\t1\t1024\t100\t20\t2\t5\t30\t0\t0\t5\t12000000\t0\t1\t0\t0\t60\tok\n'
    } >>"$file"
    run dbtune_samples_diagnostics "$file"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'valid_rows\t0'* ]]
    [[ "$output" == *$'rejected_rows\t4'* ]]
}

@test "uptime reset zeroes deltas and marks restart" {
    first=$'500\t100\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2'
    second=$'20\t2\t30\t400\t10\t1\t2\t1\t3\t4\t8\t0\t0'

    run dbtune_collect_delta now "$first" "$second" 60 $'7\t500' $'8\t20' 100 $'900000\t12000' 0.50 1
    [ "$status" -eq 0 ]
    [[ "$output" == $'now\t20\t100.00\t0.00\t0.00\t0.00\t0.00\t1\t3\t0.00\t0\t0\t0.00\t900000\t12000\t0.50\t1\t0\t60.000000\tok' ]]
}

@test "sample header is exact and idempotent" {
    dbtune_collect_append_sample 'one'
    dbtune_collect_append_sample 'two'

    run awk 'END { print NR }' "$(dbtune_collect_samples_file)"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
    run awk 'NR == 1 { print }' "$(dbtune_collect_samples_file)"
    [ "$output" = $'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tcom_select_delta\tinterval_seconds\tsample_status' ]
}

@test "old sample headers fail start before SQL timer config slow-log or state mutation" {
    local file before after header sql_before timer_before config_before
    file=$(dbtune_collect_samples_file)
    for header in \
        $'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tqcache_queries_delta\tinterval_seconds\tsample_status' \
        "$(dbtune_collect_legacy_sample_header)"; do
        printf '%s\nold-row\n' "$header" >"$file"
        before=$(dbtune_sha256_file "$file")
        printf 'unchanged-sql\n' >"$BATS_TEST_TMPDIR/sql.log"
        printf 'unchanged-timer\n' >"$BATS_TEST_TMPDIR/systemctl.log"
        printf 'unchanged-config\n' >"$(dbtune_collect_config_file)"
        sql_before=$(dbtune_sha256_file "$BATS_TEST_TMPDIR/sql.log")
        timer_before=$(dbtune_sha256_file "$BATS_TEST_TMPDIR/systemctl.log")
        config_before=$(dbtune_sha256_file "$(dbtune_collect_config_file)")
        dbtune_state_write audited

        run cmd_collect start

        [ "$status" -eq 65 ]
        [[ "$output" == *'new'*'cycle'* ]]
        after=$(dbtune_sha256_file "$file")
        [ "$after" = "$before" ]
        [ "$(dbtune_state_read)" = audited ]
        [ "$(dbtune_sha256_file "$(dbtune_collect_config_file)")" = "$config_before" ]
        [ "$(dbtune_sha256_file "$BATS_TEST_TMPDIR/sql.log")" = "$sql_before" ]
        [ "$(dbtune_sha256_file "$BATS_TEST_TMPDIR/systemctl.log")" = "$timer_before" ]
    done
}

@test "interval validity rejects non-increasing and overly long measurements" {
    run dbtune_collect_interval_seconds 100 175
    [ "$status" -eq 0 ]
    [ "$output" = 75.000000 ]
    run dbtune_collect_interval_seconds 100 100
    [ "$status" -ne 0 ]

    run dbtune_collect_interval_status 120 60
    [ "$output" = ok ]
    run dbtune_collect_interval_status 120.000001 60
    [ "$output" = degraded_interval ]
    run dbtune_collect_interval_status 0 60
    [ "$output" = degraded_interval ]

    first=$'100\t10\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2'
    second=$'221\t20\t1200\t16000\t500\t8\t30\t4\t10\t140\t360\t3\t5'
    run dbtune_collect_delta now "$first" "$second" 121 $'7\t100' $'7\t400' 100 $'900000\t12000' 1.25 0 degraded_interval
    [ "$status" -eq 0 ]
    [ "$(awk -F '\t' '{print $4, $5, $6, $13, $19, $20}' <<<"$output")" = '0.00 0.00 0.00 0.00 121.000000 degraded_interval' ]
}

@test "sample validation rejects malformed rows with diagnostics" {
    local file valid

    file=$(dbtune_collect_samples_file)
    dbtune_collect_sample_header >"$file"
    valid=$'2026-07-24T00:00:00Z\t300\t99\t1\t1024\t100\t20\t2\t5\t30\t0\t0\t5\t12000000\t0\t1\t0\t10\t60\tok'
    {
        printf '%s\n' "$valid"
        printf '2026-07-24T00:01:00Z\t360\t99\n'
        printf '%s\textra\n' "$valid"
        printf '2026-07-24T00:02:00Z\t420\t99\t1\t1024\t100\t20\t2\t5\t30\tnot-a-counter\t0\t5\t12000000\t0\t1\t0\t10\t60\tok\n'
        printf '2026-07-24T00:03:00Z\t480\t99\t1\t1024\t100\t20\t2\t5\t30\t0\t0\t5\t12000000\t0\t1\t0\t10\t0\tok\n'
        printf '2026-07-24T00:04:00Z\t540\t99\t0\t0\t0\t0\t1\t1\t0\t0\t0\t0\t12000000\t0\t1\t0\t0\t0\tdegraded_interval\n'
        printf '2026-07-24T00:05:00Z\t10\t99\t0\t0\t0\t0\t1\t1\t0\t0\t0\t0\t12000000\t0\t1\t1\t0\t60\tok\n'
    } >>"$file"

    run dbtune_collect_sample_count
    [ "$status" -eq 0 ]
    [ "$output" = 1 ]
    run dbtune_samples_diagnostics "$file"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'valid_rows\t1'* ]]
    [[ "$output" == *$'rejected_rows\t4'* ]]
    [[ "$output" == *$'excluded_status_rows\t1'* ]]
    [[ "$output" == *$'excluded_restart_rows\t1'* ]]
    [[ "$output" == *'truncated=1,extra_fields=1,non_numeric=1,invalid_timestamp=0,invalid_value=0,non_monotonic=1'* ]]

    dbtune_state_write collecting
    run cmd_collect status
    [ "$status" -eq 0 ]
    [[ "$output" == *$'sample_valid_rows\t1'* ]]
    [[ "$output" == *$'sample_rejected_rows\t4'* ]]
    [[ "$output" == *$'sample_rejected_reasons\ttruncated=1,extra_fields=1,non_numeric=1,invalid_timestamp=0,invalid_value=0,non_monotonic=1'* ]]
}

@test "sample validation enforces Gregorian calendar dates and leap years" {
    local file timestamp
    local row=$'\t300\t99\t1\t1024\t100\t20\t2\t5\t30\t0\t0\t5\t12000000\t0\t1\t0\t10\t60\tok'

    file=$(dbtune_collect_samples_file)
    dbtune_collect_sample_header >"$file"
    for timestamp in 2024-02-29T00:00:00Z 2000-02-29T00:00:00Z \
        2026-02-29T00:00:00Z 2026-02-31T00:00:00Z 2026-04-31T00:00:00Z 2100-02-29T00:00:00Z; do
        printf '%s%s\n' "$timestamp" "$row" >>"$file"
    done

    run dbtune_samples_diagnostics "$file"

    [ "$status" -eq 0 ]
    [[ "$output" == *$'valid_rows\t2'* ]]
    [[ "$output" == *$'rejected_rows\t4'* ]]
    [[ "$output" == *'invalid_timestamp=4'* ]]
}

@test "collector lock rejects symlinks before flock for tick and stop" {
    dbtune_state_write collecting
    write_collect_config
    printf 'unchanged\n' >"$BATS_TEST_TMPDIR/collect-lock-target"
    ln -s "$BATS_TEST_TMPDIR/collect-lock-target" "$(dbtune_collect_lock_file)"
    fake_flock() { touch "$BATS_TEST_TMPDIR/collect-flock-called"; }
    dbtune_collect_tick_body() { touch "$BATS_TEST_TMPDIR/tick-body-called"; }

    run cmd_tick
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/collect-lock-target")" = unchanged ]
    [ ! -e "$BATS_TEST_TMPDIR/collect-flock-called" ]
    [ ! -e "$BATS_TEST_TMPDIR/tick-body-called" ]

    run cmd_collect stop
    [ "$status" -eq 65 ]
    [ "$(cat "$BATS_TEST_TMPDIR/collect-lock-target")" = unchanged ]
    [ ! -e "$BATS_TEST_TMPDIR/collect-flock-called" ]
    [ "$(dbtune_state_read)" = collecting ]
}

@test "tick rates and CPU use the real monotonic interval including second snapshot delay" {
    dbtune_state_write collecting
    write_collect_config
    export DBTUNE_SAMPLE_SECONDS=60
    export DBTUNE_SLEEP=true
    dbtune_collect_guards() { return 0; }
    dbtune_collect_status_snapshot() {
        local count=0 count_file="$BATS_TEST_TMPDIR/status-count"
        [[ -r $count_file ]] && read -r count <"$count_file"
        count=$((count + 1)); printf '%s\n' "$count" >"$count_file"
        if ((count == 1)); then
            printf '100\t10\t1000\t10000\t200\t5\t20\t2\t8\t100\t300\t1\t2\n'
        else
            printf '175\t25\t1300\t17500\t575\t8\t30\t4\t10\t150\t350\t3\t5\n'
        fi
    }
    dbtune_collect_cpu_snapshot() {
        local count=0 count_file="$BATS_TEST_TMPDIR/cpu-count"
        [[ -r $count_file ]] && read -r count <"$count_file"
        count=$((count + 1)); printf '%s\n' "$count" >"$count_file"
        ((count == 1)) && printf '7\t100\t20\n' || printf '7\t7600\t20\n'
    }
    dbtune_collect_monotonic() {
        local count=0 count_file="$BATS_TEST_TMPDIR/monotonic-count"
        [[ -r $count_file ]] && read -r count <"$count_file"
        count=$((count + 1)); printf '%s\n' "$count" >"$count_file"
        ((count == 1)) && printf '100\n' || printf '175\n'
    }
    dbtune_collect_memory_snapshot() { printf '900000\t12000\n'; }
    dbtune_collect_load1() { printf '0.5\n'; }
    dbtune_collect_ensure_slow_log() { printf 'ok\n'; }
    dbtune_collect_daily_dbsize() { return 0; }
    printf '40\t40\t999900\t7\t20\n' >"$(dbtune_collect_last_uptime_file)"
    export DBTUNE_CLK_TCK=100

    run cmd_tick
    [ "$status" -eq 0 ]
    run awk -F '\t' 'END {print $4, $5, $6, $13, $18, $19, $20}' "$(dbtune_collect_samples_file)"
    [ "$output" = '0.20 100.00 5.00 100.00 50 75.000000 ok' ]
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
    [ "$output" = 'Collection started for 3 days (deadline epoch 1259200).' ]
    [ "$(dbtune_state_read)" = collecting ]
    [ "$(dbtune_collect_value days)" = 3 ]
    [ "$(dbtune_collect_value deadline_epoch)" = 1259200 ]
    [ "$(dbtune_collect_value ui_lang)" = en ]
    grep -F 'ExecStart=/usr/local/bin/dbtune _tick' "$DBTUNE_SYSTEMD_DIR/dbtune-collect.service"
    grep -Fx 'Description=Wooptima DB Tuner MariaDB metrics collection tick' "$DBTUNE_SYSTEMD_DIR/dbtune-collect.service"
    grep -F 'OnCalendar=*:0/5' "$DBTUNE_SYSTEMD_DIR/dbtune-collect.timer"
    grep -Fx 'Description=Run Wooptima DB Tuner collection every five minutes' "$DBTUNE_SYSTEMD_DIR/dbtune-collect.timer"
    grep -F 'enable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    grep -F 'SET GLOBAL slow_query_log=ON' "$BATS_TEST_TMPDIR/sql.log"
}

@test "start confirmation supports explicit Slovak" {
    dbtune_i18n_set sk
    dbtune_state_write audited

    run cmd_collect start --days 3 --long-query-time 0.5

    [ "$status" -eq 0 ]
    [ "$output" = 'Zber spusteny na 3 dni (deadline epoch 1259200).' ]
    [ "$(dbtune_collect_value ui_lang)" = sk ]
}

@test "tick restores the persisted language before diagnostics and automatic reporting" {
    source_tick_dispatch
    dbtune_state_write collecting
    write_collect_config 999999 sk
    write_sample_rows 288
    dbtune_i18n_set en
    export DBTUNE_LOG_LEVEL=warn
    cmd_analyze() {
        printf '%s\n' "$DBTUNE_I18N_LANGUAGE" >"$BATS_TEST_TMPDIR/analyze-language"
    }
    cmd_report() {
        dbtune_printf report_title >"$BATS_TEST_TMPDIR/automatic-report.md"
    }

    run dbtune_main _tick unexpected

    [ "$status" -eq 0 ]
    [[ "$output" == *'_tick ignoruje argumenty'* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/analyze-language")" = sk ]
    [ "$(cat "$BATS_TEST_TMPDIR/automatic-report.md")" = '# Wooptima DB Tuner správa' ]
}

@test "public tick restores persisted language before lifecycle lock diagnostics" {
    source_tick_dispatch
    dbtune_state_write collecting
    write_collect_config 999999 sk
    export DBTUNE_UI_LANG=en
    export DBTUNE_LOG_LEVEL=error
    export DBTUNE_FLOCK="$BATS_TEST_TMPDIR/missing-flock"

    run dbtune_main _tick

    [ "$status" -eq 0 ]
    [[ "$output" == *'Lifecycle lock vyzaduje flock'* ]]
    [[ "$output" != *'Lifecycle lock requires flock'* ]]
}

@test "status does not invoke SQL or systemctl" {
    dbtune_state_write audited
    rm -f "$BATS_TEST_TMPDIR/sql.log" "$BATS_TEST_TMPDIR/systemctl.log"

    run cmd_collect status
    [ "$status" -eq 0 ]
    [ "$output" = $'state\taudited\nhealth_timestamp\tunknown\nhealth_status\tunknown\nhealth_detail\t\nsample_valid_rows\t0\nsample_rejected_rows\t0\nsample_excluded_status_rows\t0\nsample_excluded_restart_rows\t0\nsample_rejected_reasons\tunavailable\nlast_sample_age_seconds\tunknown\nsample_state\tmissing\nguard_state\tnone' ]
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
    dbtune_collect_monotonic() {
        local count_file="$BATS_TEST_TMPDIR/monotonic-count" count=0
        [[ -r $count_file ]] && read -r count <"$count_file"
        count=$((count + 1))
        printf '%s\n' "$count" >"$count_file"
        ((count == 1)) && printf '1300\n' || printf '1360\n'
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
    grep -F $'\tok\trestart_flag=1 sample_status=ok interval_seconds=60.000000 slow_log=healed\t' "$(dbtune_collect_health_file)"
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
    [ "$output" = 'Collection stopped.' ]
    [ "$(dbtune_state_read)" = collected ]
    grep -F 'disable --now dbtune-collect.timer' "$BATS_TEST_TMPDIR/systemctl.log"
    grep -F "SET GLOBAL slow_query_log_file='/var/lib/mysql/original-slow.log'" "$BATS_TEST_TMPDIR/sql.log"
    grep -F 'SET GLOBAL slow_query_log=1' "$BATS_TEST_TMPDIR/sql.log"
}

@test "stop confirmation supports explicit Slovak" {
    dbtune_i18n_set sk
    dbtune_state_write collecting
    write_collect_config

    run cmd_collect stop

    [ "$status" -eq 0 ]
    [ "$output" = 'Zber zastaveny.' ]
}
