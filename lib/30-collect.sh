dbtune_collect_usage() {
    dbtune_msg collect_usage
}

dbtune_collect_config_file() {
    printf '%s\n' "${DBTUNE_COLLECT_CONFIG_FILE:-$DBTUNE_STATE_DIR/collect.tsv}"
}

dbtune_collect_samples_file() {
    printf '%s\n' "${DBTUNE_SAMPLES_FILE:-$DBTUNE_STATE_DIR/samples.tsv}"
}

dbtune_collect_dbsize_file() {
    printf '%s\n' "${DBTUNE_DBSIZE_FILE:-$DBTUNE_STATE_DIR/dbsize.tsv}"
}

dbtune_collect_health_file() {
    printf '%s\n' "${DBTUNE_COLLECT_HEALTH_FILE:-$DBTUNE_STATE_DIR/collect-health.tsv}"
}

dbtune_collect_last_uptime_file() {
    printf '%s\n' "${DBTUNE_LAST_UPTIME_FILE:-$DBTUNE_STATE_DIR/collect-last-uptime}"
}

dbtune_collect_lock_file() {
    printf '%s\n' "${DBTUNE_COLLECT_LOCK_FILE:-$DBTUNE_STATE_DIR/collect.lock}"
}

dbtune_collect_value() {
    local key=${1:-}
    local file

    file=$(dbtune_collect_config_file)
    [[ -n $key && -r $file ]] || return 1
    awk -F '\t' -v wanted="$key" '$1 == wanted { sub(/^[^\t]*\t/, ""); print; found=1; exit } END { if (!found) exit 1 }' "$file"
}

dbtune_collect_epoch() {
    if [[ -n ${DBTUNE_NOW_EPOCH:-} ]]; then
        printf '%s\n' "$DBTUNE_NOW_EPOCH"
    else
        "${DBTUNE_DATE:-date}" +%s
    fi
}

dbtune_collect_sql_quote() {
    local value=${1-}

    value=${value//\\/\\\\}
    value=${value//\'/\'\'}
    printf "'%s'" "$value"
}

dbtune_collect_validate_long_query_time() {
    local value=${1:-}

    [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || {
        dbtune_log error "$(dbtune_msg collect_long_query_nonnegative)"
        return 64
    }
    awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 3600) }' || {
        dbtune_log error "$(dbtune_msg collect_long_query_range)"
        return 64
    }
}

dbtune_collect_write_config() {
    local days=$1
    local long_query_time=$2
    local slow_log=$3
    local started_epoch=$4
    local deadline_epoch=$5
    local original_slow=$6
    local original_file=$7
    local original_long=$8
    local original_verbosity=$9
    local ui_lang=$DBTUNE_I18N_LANGUAGE

    case $ui_lang in
        en|sk) ;;
        *) return 64 ;;
    esac

    {
        printf 'ui_lang\t%s\n' "$ui_lang"
        printf 'days\t%s\n' "$days"
        printf 'long_query_time\t%s\n' "$long_query_time"
        printf 'slow_log_file\t%s\n' "$slow_log"
        printf 'started_epoch\t%s\n' "$started_epoch"
        printf 'deadline_epoch\t%s\n' "$deadline_epoch"
        printf 'started_at\t%s\n' "$(dbtune_now)"
        printf 'original_slow_query_log\t%s\n' "$original_slow"
        printf 'original_slow_query_log_file\t%s\n' "$original_file"
        printf 'original_long_query_time\t%s\n' "$original_long"
        printf 'original_log_slow_verbosity\t%s\n' "$original_verbosity"
    } | dbtune_atomic_write "$(dbtune_collect_config_file)" 600
}

dbtune_collect_set_slow_log() {
    local slow_log=$1
    local long_query_time=$2
    local quoted_file

    quoted_file=$(dbtune_collect_sql_quote "$slow_log")
    dbtune_sql "SET GLOBAL slow_query_log=OFF; SET GLOBAL slow_query_log_file=$quoted_file; SET GLOBAL long_query_time=$long_query_time; SET GLOBAL slow_query_log=ON;"
}

dbtune_collect_restore_slow_log() {
    local original_slow original_file original_long quoted_file

    original_slow=$(dbtune_collect_value original_slow_query_log) || return 1
    original_file=$(dbtune_collect_value original_slow_query_log_file) || return 1
    original_long=$(dbtune_collect_value original_long_query_time) || return 1
    [[ $original_slow == 0 || $original_slow == 1 ]] || return 1
    dbtune_collect_validate_long_query_time "$original_long" || return
    quoted_file=$(dbtune_collect_sql_quote "$original_file")
    dbtune_sql "SET GLOBAL slow_query_log=OFF; SET GLOBAL slow_query_log_file=$quoted_file; SET GLOBAL long_query_time=$original_long; SET GLOBAL slow_query_log=$original_slow;"
}

dbtune_collect_asset() {
    local asset=$1

    if ! declare -F dbtune_embedded_get >/dev/null 2>&1; then
        dbtune_log error "$(dbtune_msg collect_assets_missing)"
        return 69
    fi
    dbtune_embedded_get "$asset"
}

dbtune_collect_install_units() {
    local systemd_dir service_path timer_path program_path service_dir timer_dir
    local systemctl_command

    systemd_dir=${DBTUNE_SYSTEMD_DIR:-/etc/systemd/system}
    service_path=${DBTUNE_COLLECT_SERVICE_PATH:-$systemd_dir/dbtune-collect.service}
    timer_path=${DBTUNE_COLLECT_TIMER_PATH:-$systemd_dir/dbtune-collect.timer}
    program_path=${DBTUNE_PROGRAM_PATH:-/usr/local/bin/dbtune}
    systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}
    if [[ $DBTUNE_ARTIFACT_PROFILE == production ]]; then
        program_path=$(dbtune_runtime_command_path dbtune) || return
        systemctl_command=$(dbtune_runtime_command_path systemctl) || return
    fi
    if [[ $program_path != /* || $program_path =~ [[:space:]] ]]; then
        dbtune_log error "$(dbtune_msg collect_program_path_invalid)"
        return 64
    fi

    service_dir=${service_path%/*}
    timer_dir=${timer_path%/*}
    [[ $service_dir != "$service_path" ]] || service_dir=.
    [[ $timer_dir != "$timer_path" ]] || timer_dir=.
    "${DBTUNE_INSTALL:-install}" -d -m 755 "$service_dir" "$timer_dir" || return 1
    dbtune_collect_asset systemd/dbtune-collect.service |
        awk -v program="$program_path" '/^ExecStart=/ { $0="ExecStart=" program " _tick" } { print }' |
        dbtune_atomic_write "$service_path" 644 || return 1
    dbtune_collect_asset systemd/dbtune-collect.timer |
        dbtune_atomic_write "$timer_path" 644 || return 1
    "$systemctl_command" daemon-reload
}

dbtune_collect_preflight_samples_file() {
    local file header expected

    file=$(dbtune_collect_samples_file)
    [[ -s $file ]] || return 0
    IFS= read -r header <"$file" || return 65
    expected=$(dbtune_collect_sample_header)
    [[ $header == "$expected" ]] && return 0
    printf '%s\n' "$(dbtune_msg collect_sample_header_unsupported)" >&2
    return 65
}

dbtune_collect_start() {
    local days=${DBTUNE_DEFAULT_DAYS:-7}
    local long_query_time=2
    local slow_log=${DBTUNE_SLOW_LOG:-/var/log/mysql/slow.log}
    local slow_dir started_epoch deadline_epoch originals
    local original_slow original_file original_long original_verbosity
    local systemctl_command timer_unit

    while (($#)); do
        case $1 in
            --days)
                (($# >= 2)) || { dbtune_log error "$(dbtune_msg collect_days_value_required)"; return 64; }
                days=$2
                shift 2
                ;;
            --days=*) days=${1#*=}; shift ;;
            --long-query-time)
                (($# >= 2)) || { dbtune_log error "$(dbtune_msg collect_long_query_value_required)"; return 64; }
                long_query_time=$2
                shift 2
                ;;
            --long-query-time=*) long_query_time=${1#*=}; shift ;;
            -h|--help) dbtune_collect_usage; return 0 ;;
            *) dbtune_log error "$(dbtune_printf collect_unknown_start_option "$1")"; return 64 ;;
        esac
    done
    dbtune_require_uint "--days" "$days" 1 3650 || return
    dbtune_collect_validate_long_query_time "$long_query_time" || return
    dbtune_collect_preflight_samples_file || return
    dbtune_require_state collect_start || return
    dbtune_init_state_dir || return 1

    originals=$(dbtune_sql 'SELECT @@GLOBAL.slow_query_log, @@GLOBAL.slow_query_log_file, @@GLOBAL.long_query_time, @@GLOBAL.log_slow_verbosity;') || return
    IFS=$'\t' read -r original_slow original_file original_long original_verbosity <<<"$originals"
    [[ $original_slow == 0 || $original_slow == 1 ]] || {
        dbtune_log error "$(dbtune_msg collect_original_slow_invalid)"
        return 65
    }
    [[ -n $original_file && -n $original_long ]] || {
        dbtune_log error "$(dbtune_msg collect_original_slow_missing)"
        return 65
    }

    slow_dir=${slow_log%/*}
    [[ $slow_dir != "$slow_log" ]] || slow_dir=.
    if [[ ! -d $slow_dir ]]; then
        "${DBTUNE_INSTALL:-install}" -d -o "${DBTUNE_MYSQL_USER:-mysql}" -g "${DBTUNE_MYSQL_GROUP:-mysql}" -m 750 "$slow_dir" || return 1
    fi
    started_epoch=$(dbtune_collect_epoch) || return
    dbtune_require_uint "$(dbtune_msg collect_current_epoch_label)" "$started_epoch" 1 2147483647 || return
    deadline_epoch=$(awk -v start="$started_epoch" -v days="$days" 'BEGIN { printf "%.0f\n", start + days * 86400 }')
    dbtune_collect_write_config "$days" "$long_query_time" "$slow_log" "$started_epoch" "$deadline_epoch" \
        "$original_slow" "$original_file" "$original_long" "$original_verbosity" || return

    if ! dbtune_collect_install_units || ! dbtune_collect_set_slow_log "$slow_log" "$long_query_time"; then
        dbtune_log error "$(dbtune_msg collect_start_failed)"
        dbtune_collect_restore_slow_log >/dev/null 2>&1 || true
        rm -f "$(dbtune_collect_config_file)"
        return 1
    fi
    rm -f "$(dbtune_collect_last_uptime_file)" "$(dbtune_collect_health_file)"
    if ! dbtune_state_transition collecting; then
        dbtune_collect_restore_slow_log >/dev/null 2>&1 || true
        rm -f "$(dbtune_collect_config_file)"
        return 1
    fi

    systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}
    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || systemctl_command=$(dbtune_runtime_command_path systemctl) || return
    timer_unit=${DBTUNE_COLLECT_TIMER_UNIT:-dbtune-collect.timer}
    if ! "$systemctl_command" enable --now "$timer_unit"; then
        dbtune_collect_restore_slow_log >/dev/null 2>&1 || true
        dbtune_state_write audited || true
        dbtune_event collect_start_failed reason timer_enable || true
        return 1
    fi
    dbtune_event collect_started days "$days" deadline_epoch "$deadline_epoch" long_query_time "$long_query_time" || true
    dbtune_printf collect_started "$days" "$deadline_epoch"
}

dbtune_collect_status() {
    local state key value health_timestamp=unknown health_status=unknown health_detail=''
    local now sample_epoch='' sample_age=unknown sample_state=missing guard_state=none sample_count=0
    local stale_seconds=${DBTUNE_STALE_SAMPLE_SECONDS:-900}
    local identity_file samples_file diagnostics

    (($# == 0)) || { dbtune_collect_usage >&2; return 64; }
    state=$(dbtune_state_read) || return
    printf 'state\t%s\n' "$state"
    if [[ -r $(dbtune_collect_config_file) ]]; then
        for key in started_at days deadline_epoch long_query_time slow_log_file; do
            value=$(dbtune_collect_value "$key" 2>/dev/null) || continue
            printf '%s\t%s\n' "$key" "$value"
        done
    fi
    if [[ -r $(dbtune_collect_health_file) ]]; then
        IFS=$'\t' read -r health_timestamp health_status health_detail _ <"$(dbtune_collect_health_file)" || true
    fi
    printf 'health_timestamp\t%s\n' "${health_timestamp:-unknown}"
    printf 'health_status\t%s\n' "${health_status:-unknown}"
    printf 'health_detail\t%s\n' "${health_detail:-}"

    identity_file=$(dbtune_collect_last_uptime_file)
    if [[ -r $identity_file ]]; then
        IFS=$'\t' read -r _ _ sample_epoch _ _ <"$identity_file" || sample_epoch=''
    fi
    samples_file=$(dbtune_collect_samples_file)
    sample_count=$(dbtune_collect_sample_count 2>/dev/null) || sample_count=0
    if diagnostics=$(dbtune_samples_diagnostics "$samples_file" 2>/dev/null); then
        while IFS=$'\t' read -r key value; do
            printf 'sample_%s\t%s\n' "$key" "$value"
        done <<<"$diagnostics"
    else
        printf 'sample_valid_rows\t0\n'
        printf 'sample_rejected_rows\t0\n'
        printf 'sample_excluded_status_rows\t0\n'
        printf 'sample_excluded_restart_rows\t0\n'
        printf 'sample_rejected_reasons\tunavailable\n'
    fi
    if ! dbtune_is_uint "$sample_epoch" && ((sample_count > 0)); then
        sample_epoch=$(dbtune_collect_file_epoch "$samples_file" 2>/dev/null) || sample_epoch=''
    fi
    now=$(dbtune_collect_epoch 2>/dev/null) || now=''
    if dbtune_is_uint "$sample_epoch" && dbtune_is_uint "$now"; then
        if ((now >= sample_epoch)); then
            sample_age=$((now - sample_epoch))
        else
            sample_age=0
        fi
        dbtune_is_uint "$stale_seconds" || stale_seconds=900
        if ((sample_age > stale_seconds)); then
            sample_state=stale
        else
            sample_state=fresh
        fi
    fi
    case $health_status in
        guard) guard_state=triggered ;;
        restore_pending) guard_state=restore_pending ;;
        incomplete) guard_state=deadline_incomplete ;;
    esac
    printf 'last_sample_age_seconds\t%s\n' "$sample_age"
    printf 'sample_state\t%s\n' "$sample_state"
    printf 'guard_state\t%s\n' "$guard_state"
}

dbtune_collect_disable_timer() {
    local systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}
    local timer_unit=${DBTUNE_COLLECT_TIMER_UNIT:-dbtune-collect.timer}

    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || systemctl_command=$(dbtune_runtime_command_path systemctl) || return
    "$systemctl_command" disable --now "$timer_unit"
}

dbtune_collect_finish_locked() {
    local result=$1
    local detail=$2
    local restore_result=0 transition_result=0 restore_label=ok

    if ! dbtune_collect_restore_slow_log; then
        dbtune_log error "$(dbtune_msg collect_restore_failed)"
        restore_result=1
    fi
    if ((restore_result == 0)) && [[ $(dbtune_state_read) == collecting ]]; then
        dbtune_state_transition collected || transition_result=1
    fi
    if ((restore_result != 0)); then
        restore_label=failed
        dbtune_collect_health restore_pending "$detail restore=failed" || true
        dbtune_event collect_restore_pending result "$result" detail "$detail" || true
    else
        dbtune_collect_health "$result" "$detail restore=ok" || true
    fi
    dbtune_event collect_finished result "$result" detail "$detail" restore "$restore_label" || true
    ((restore_result == 0 && transition_result == 0))
}

dbtune_collect_stop() {
    local result=0 lock_file lock_identity lock_fd lock_status timer_result=ok
    local flock_command=${DBTUNE_FLOCK:-flock}

    (($# == 0)) || { dbtune_collect_usage >&2; return 64; }
    dbtune_init_state_dir || return
    dbtune_require_state collect_stop || return
    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || flock_command=$(dbtune_runtime_command_path flock) || return
    if ! dbtune_collect_disable_timer; then
        result=1
        timer_result=failed
    fi
    lock_file=$(dbtune_collect_lock_file)
    dbtune_open_state_lock lock_fd "$lock_file" "$(dbtune_msg collect_label_collector_lock)" || {
        lock_status=$?
        dbtune_collect_health error stop_lock_open || true
        return "$lock_status"
    }
    lock_identity=$DBTUNE_STATE_LOCK_IDENTITY
    if ! "$flock_command" -x "$lock_fd"; then
        dbtune_collect_health error stop_lock || true
        exec {lock_fd}>&-
        return 1
    fi
    if ! dbtune_validate_state_lock "$lock_file" "$(dbtune_msg collect_label_collector_lock)" "$lock_identity"; then
        "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
        exec {lock_fd}>&-
        return 65
    fi
    dbtune_collect_finish_locked stopped "reason=manual timer=$timer_result" || result=1
    "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    dbtune_event collect_stopped || true
    ((result == 0)) || return 1
    dbtune_printf collect_stopped
}

cmd_collect() {
    local subcommand=${1:-}

    [[ -n $subcommand ]] || { dbtune_collect_usage >&2; return 64; }
    shift
    case $subcommand in
        start) dbtune_collect_start "$@" ;;
        status) dbtune_collect_status "$@" ;;
        stop) dbtune_collect_stop "$@" ;;
        *) dbtune_collect_usage >&2; return 64 ;;
    esac
}

dbtune_collect_health() {
    local status=$1
    local detail=${2:-}

    printf '%s\t%s\t%s\t%s\n' "$(dbtune_now)" "$status" "$detail" "$(dbtune_collect_epoch)" |
        dbtune_atomic_write "$(dbtune_collect_health_file)" 600
}

dbtune_collect_file_epoch() {
    local file=$1

    "${DBTUNE_STAT:-stat}" -c %Y "$file" 2>/dev/null ||
        "${DBTUNE_STAT:-stat}" -f %m "$file" 2>/dev/null
}

dbtune_collect_file_bytes() {
    local file=$1

    if [[ -f $file ]]; then
        "${DBTUNE_WC:-wc}" -c <"$file" | awk '{ print $1 }'
    else
        printf '0\n'
    fi
}

dbtune_collect_available_kb() {
    local path=$1

    "${DBTUNE_DF:-df}" -Pk "$path" | awk 'NR > 1 { value=$4 } END { if (value == "") exit 1; print value }'
}

dbtune_collect_guard_stop() {
    local reason=$1
    local detail=${2:-}
    local timer_result=ok

    dbtune_collect_disable_timer || timer_result=failed
    dbtune_event collect_guard reason "$reason" detail "$detail" timer "$timer_result" || true
    dbtune_collect_finish_locked guard "reason=$reason $detail timer=$timer_result" || true
    dbtune_log warn "$(dbtune_printf collect_watchdog_stopped "$reason")"
    return 1
}

dbtune_collect_guards() {
    local samples slow_log slow_path free_state free_slow samples_bytes slow_bytes
    local min_free=${DBTUNE_MIN_FREE_KB:-1048576}
    local max_samples=${DBTUNE_MAX_SAMPLES_BYTES:-2147483648}
    local max_slow=${DBTUNE_MAX_SLOW_LOG_BYTES:-2147483648}
    local reason=''

    samples=$(dbtune_collect_samples_file)
    slow_log=$(dbtune_collect_value slow_log_file) || {
        dbtune_collect_guard_stop guard_check_failed step=config
        return 1
    }
    slow_path=${slow_log%/*}
    [[ -d $slow_path ]] || slow_path=$DBTUNE_STATE_DIR
    free_state=$(dbtune_collect_available_kb "$DBTUNE_STATE_DIR") || {
        dbtune_collect_guard_stop guard_check_failed step=state_disk
        return 1
    }
    free_slow=$(dbtune_collect_available_kb "$slow_path") || {
        dbtune_collect_guard_stop guard_check_failed step=slow_log_disk
        return 1
    }
    samples_bytes=$(dbtune_collect_file_bytes "$samples") || {
        dbtune_collect_guard_stop guard_check_failed step=samples_size
        return 1
    }
    slow_bytes=$(dbtune_collect_file_bytes "$slow_log") || {
        dbtune_collect_guard_stop guard_check_failed step=slow_log_size
        return 1
    }

    if awk -v a="$free_state" -v b="$free_slow" -v limit="$min_free" 'BEGIN { exit !(a < limit || b < limit) }'; then
        reason=low_disk
    elif awk -v size="$samples_bytes" -v limit="$max_samples" 'BEGIN { exit !(size >= limit) }'; then
        reason=samples_limit
    elif awk -v size="$slow_bytes" -v limit="$max_slow" 'BEGIN { exit !(size >= limit) }'; then
        reason=slow_log_limit
    fi
    [[ -z $reason ]] && return 0

    dbtune_collect_guard_stop "$reason" "samples_bytes=$samples_bytes slow_log_bytes=$slow_bytes"
}

dbtune_collect_status_snapshot() {
    local raw validated line
    local -a values=()

    raw=$(dbtune_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests','Innodb_data_read','Handler_read_rnd_next','Created_tmp_disk_tables','Created_tmp_tables','Threads_running','Threads_connected','Qcache_hits','Com_select','Innodb_log_waits','Innodb_buffer_pool_wait_free');") || return
    validated=$(dbtune_status_snapshot_exact "$raw" uptime innodb_buffer_pool_reads \
        innodb_buffer_pool_read_requests innodb_data_read handler_read_rnd_next \
        created_tmp_disk_tables created_tmp_tables threads_running threads_connected \
        qcache_hits com_select innodb_log_waits innodb_buffer_pool_wait_free) || return 65
    while IFS=$'\t' read -r _ line; do
        values+=("$line")
    done <<<"$validated"
    (IFS=$'\t'; printf '%s\n' "${values[*]}")
}

dbtune_collect_cpu_snapshot() {
    local pid stat_file values

    pid=$("${DBTUNE_PGREP:-pgrep}" -xo mariadbd 2>/dev/null) || {
        printf '0\t0\t0\n'
        return 0
    }
    stat_file="${DBTUNE_PROC_ROOT:-/proc}/$pid/stat"
    [[ -r $stat_file ]] || { printf '0\t0\t0\n'; return 0; }
    values=$(awk '{ print $14 + $15 "\t" $22 }' "$stat_file") || return
    printf '%s\t%s\n' "$pid" "$values"
}

dbtune_collect_monotonic() {
    local value

    if [[ -n ${DBTUNE_MONOTONIC:-} ]]; then
        printf '%s\n' "$DBTUNE_MONOTONIC"
        return 0
    fi
    read -r value _ <"${DBTUNE_PROC_ROOT:-/proc}/uptime" || return
    printf '%s\n' "$value"
}

dbtune_collect_interval_seconds() {
    local first=${1:-}
    local second=${2:-}

    [[ $first =~ ^[0-9]+([.][0-9]+)?$ && $second =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v first="$first" -v second="$second" 'BEGIN {
        if (second <= first) exit 1
        printf "%.6f\n", second-first
    }'
}

dbtune_collect_interval_status() {
    local interval=${1:-}
    local sample_seconds=${2:-}
    local maximum=${DBTUNE_MAX_SAMPLE_INTERVAL_SECONDS:-}

    if [[ -z $maximum ]]; then
        maximum=$(awk -v seconds="$sample_seconds" 'BEGIN { print seconds*2 }')
    fi
    if [[ ! $interval =~ ^[0-9]+([.][0-9]+)?$ || ! $maximum =~ ^[0-9]+([.][0-9]+)?$ ]] ||
        ! awk -v interval="$interval" -v maximum="$maximum" 'BEGIN { exit !(interval > 0 && maximum > 0 && interval <= maximum) }'; then
        printf 'degraded_interval\n'
    else
        printf 'ok\n'
    fi
}

dbtune_collect_restart_detected() {
    local previous_uptime=$1 previous_monotonic=$2 previous_epoch=$3
    local previous_pid=$4 previous_start=$5 uptime_first=$6 uptime_second=$7
    local monotonic_now=$8 now=$9 cpu_first=${10} cpu_second=${11}
    local current_pid current_start second_pid second_start elapsed='' skew

    IFS=$'\t' read -r current_pid _ current_start <<<"$cpu_first"
    IFS=$'\t' read -r second_pid _ second_start <<<"$cpu_second"
    if [[ $previous_pid =~ ^[1-9][0-9]*$ && $previous_start =~ ^[1-9][0-9]*$ &&
        $current_pid =~ ^[1-9][0-9]*$ && $current_start =~ ^[1-9][0-9]*$ ]] &&
        [[ $previous_pid != "$current_pid" || $previous_start != "$current_start" ]]; then
        return 0
    fi
    if [[ $current_pid =~ ^[1-9][0-9]*$ && $current_start =~ ^[1-9][0-9]*$ &&
        $second_pid =~ ^[1-9][0-9]*$ && $second_start =~ ^[1-9][0-9]*$ ]] &&
        [[ $current_pid != "$second_pid" || $current_start != "$second_start" ]]; then
        return 0
    fi
    if awk -v first="$uptime_first" -v second="$uptime_second" 'BEGIN { exit !(second <= first) }'; then
        return 0
    fi
    if [[ $previous_uptime =~ ^[0-9]+([.][0-9]+)?$ ]] &&
        awk -v previous="$previous_uptime" -v current="$uptime_first" 'BEGIN { exit !(current < previous) }'; then
        return 0
    fi

    if [[ $previous_uptime =~ ^[0-9]+([.][0-9]+)?$ && $previous_monotonic =~ ^[0-9]+([.][0-9]+)?$ &&
        $monotonic_now =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        elapsed=$(awk -v current="$monotonic_now" -v previous="$previous_monotonic" 'BEGIN { if (current >= previous) print current-previous }')
    elif [[ $previous_uptime =~ ^[0-9]+([.][0-9]+)?$ ]] && dbtune_is_uint "$previous_epoch" && dbtune_is_uint "$now" &&
        ((now >= previous_epoch)); then
        elapsed=$((now - previous_epoch))
    fi
    skew=${DBTUNE_RESTART_SKEW_SECONDS:-5}
    [[ $skew =~ ^[0-9]+([.][0-9]+)?$ ]] || skew=5
    if [[ -n $elapsed ]] && awk -v previous="$previous_uptime" -v current="$uptime_first" \
        -v elapsed="$elapsed" -v skew="$skew" 'BEGIN { exit !(current + skew < previous + elapsed) }'; then
        return 0
    fi
    return 1
}

dbtune_collect_cpu_identity_valid() {
    local snapshot=${1-} pid ticks start extra

    IFS=$'\t' read -r pid ticks start extra <<<"$snapshot"
    [[ -z $extra && $pid =~ ^[1-9][0-9]*$ && $start =~ ^[1-9][0-9]*$ ]] || return 1
    dbtune_uint64_valid "$pid" && dbtune_uint64_valid "$ticks" && dbtune_uint64_valid "$start"
}

dbtune_collect_restart_status() {
    local previous_uptime=$1 previous_monotonic=$2 previous_epoch=$3
    local previous_pid=$4 previous_start=$5 uptime_first=$6 uptime_second=$7
    local monotonic_now=$8 now=$9 cpu_first=${10} cpu_second=${11}
    local first_pid first_start second_pid second_start

    if dbtune_collect_cpu_identity_valid "$cpu_first" && dbtune_collect_cpu_identity_valid "$cpu_second"; then
        IFS=$'\t' read -r first_pid _ first_start <<<"$cpu_first"
        IFS=$'\t' read -r second_pid _ second_start <<<"$cpu_second"
        if [[ $first_pid != "$second_pid" || $first_start != "$second_start" ]]; then
            printf 'restart\n'
            return 0
        fi
    else
        printf 'degraded_restart_identity\n'
        return 0
    fi
    if dbtune_uint64_valid "$previous_pid" && dbtune_uint64_valid "$previous_start" &&
        [[ $previous_pid != 0 && $previous_start != 0 ]]; then
        if [[ $previous_pid != "$first_pid" || $previous_start != "$first_start" ]]; then
            printf 'restart\n'
            return 0
        fi
    else
        printf 'degraded_restart_identity\n'
        return 0
    fi
    if dbtune_collect_restart_detected "$previous_uptime" "$previous_monotonic" "$previous_epoch" \
        "$previous_pid" "$previous_start" "$uptime_first" "$uptime_second" "$monotonic_now" \
        "$now" "$cpu_first" "$cpu_second"; then
        printf 'restart\n'
    else
        printf 'ok\n'
    fi
}

dbtune_collect_identity_valid() {
    local uptime=$1 monotonic=$2 epoch=$3 cpu=$4

    dbtune_uint64_valid "$uptime" && dbtune_is_uint "$epoch" &&
        [[ $monotonic =~ ^[0-9]+([.][0-9]+)?$ ]] && dbtune_collect_cpu_identity_valid "$cpu"
}

dbtune_collect_ensure_slow_log() {
    local trigger=$1 slow_log long_query_time runtime runtime_enabled runtime_file runtime_long
    local needs_heal=0 verification=ok

    slow_log=$(dbtune_collect_value slow_log_file) || return 1
    long_query_time=$(dbtune_collect_value long_query_time) || return 1
    if runtime=$(dbtune_sql 'SELECT @@GLOBAL.slow_query_log, @@GLOBAL.slow_query_log_file, @@GLOBAL.long_query_time;'); then
        IFS=$'\t' read -r runtime_enabled runtime_file runtime_long <<<"$runtime"
        [[ $runtime_enabled == 1 && $runtime_file == "$slow_log" ]] || needs_heal=1
        if ! awk -v actual="$runtime_long" -v wanted="$long_query_time" 'BEGIN { exit !(actual == wanted) }'; then
            needs_heal=1
        fi
    else
        needs_heal=1
        verification=failed
    fi
    if ((needs_heal == 0)); then
        printf 'ok\n'
        return 0
    fi
    dbtune_collect_set_slow_log "$slow_log" "$long_query_time" || return 1
    dbtune_event collect_slow_log_self_healed trigger "$trigger" verification "$verification" || true
    printf 'healed\n'
}

dbtune_collect_memory_snapshot() {
    "${DBTUNE_FREE:-free}" -k | awk '
        $1 == "Mem:" { available=$7 }
        $1 == "Swap:" { swap=$3 }
        END { if (available == "") exit 1; printf "%s\t%s\n", available+0, swap+0 }'
}

dbtune_collect_load1() {
    local load1

    read -r load1 _ <"${DBTUNE_PROC_ROOT:-/proc}/loadavg" || return
    printf '%s\n' "$load1"
}

dbtune_collect_delta() {
    local timestamp=$1 first=$2 second=$3 seconds=$4 cpu_first=$5 cpu_second=$6
    local clock_ticks=$7 memory=$8 load1=$9 restart_flag=${10}
    local sample_status=${11:-ok} comparison name high low difference reset_names=''
    local -a a=() b=() deltas=()
    local -a cumulative=(2 3 4 5 6 7 10 11 12 13)
    local -a names=(buffer_pool_reads buffer_pool_read_requests innodb_data_read handler_read_rnd_next created_tmp_disk_tables created_tmp_tables qcache_hits com_select innodb_log_waits innodb_buffer_pool_wait_free)

    IFS=$'\t' read -r -a a <<<"$first"
    IFS=$'\t' read -r -a b <<<"$second"
    ((${#a[@]} == 13 && ${#b[@]} == 13)) || return 65
    if ((restart_flag)); then
        deltas=(0 0 0 0 0 0 0 0 0 0)
    else
        for name in "${!cumulative[@]}"; do
            low=${a[${cumulative[$name]}-1]}
            high=${b[${cumulative[$name]}-1]}
            comparison=$(dbtune_uint64_compare "$high" "$low") || return 65
            if ((comparison < 0)); then
                deltas+=(0)
                [[ -z $reset_names ]] || reset_names+=,
                reset_names+=${names[$name]}
            else
                difference=$(dbtune_uint64_subtract "$high" "$low") || return
                deltas+=("$difference")
            fi
        done
        if [[ -n $reset_names ]]; then
            sample_status=degraded_counter_reset
            dbtune_log warn "counter reset: $reset_names"
        elif [[ $(dbtune_uint64_compare "${deltas[0]}" "${deltas[1]}") == 1 ||
            $(dbtune_uint64_compare "${deltas[4]}" "${deltas[5]}") == 1 ||
            $(dbtune_uint64_compare "${deltas[6]}" "${deltas[7]}") == 1 ]]; then
            sample_status=degraded_counter_inconsistent
        fi
    fi

    awk -F '\t' -v timestamp="$timestamp" -v first="$first" -v second="$second" \
        -v seconds="$seconds" -v cpu_first="$cpu_first" -v cpu_second="$cpu_second" \
        -v hz="$clock_ticks" -v memory="$memory" -v load1="$load1" -v restart="$restart_flag" \
        -v sample_status="$sample_status" -v reads="${deltas[0]}" -v requests="${deltas[1]}" \
        -v data_read="${deltas[2]}" -v rnd="${deltas[3]}" -v tmp_disk="${deltas[4]}" \
        -v tmp_total="${deltas[5]}" -v qhits="${deltas[6]}" -v selects="${deltas[7]}" \
        -v log_waits="${deltas[8]}" -v wait_free="${deltas[9]}" '
        BEGIN {
            split(first, a, "\t"); split(second, b, "\t")
            split(cpu_first, c1, "\t"); split(cpu_second, c2, "\t")
            split(memory, mem, "\t")
            valid_interval=(sample_status == "ok" && seconds > 0)
            bp_hit=requests > 0 ? 100*(1-reads/requests) : 100
            if (bp_hit < 0) bp_hit=0; if (bp_hit > 100) bp_hit=100
            tmp_pct=tmp_total > 0 ? 100*tmp_disk/tmp_total : 0
            qcache_pct=selects > 0 ? 100*qhits/selects : 0
            cpu=(valid_interval && !restart && c1[1] == c2[1] && c1[1] != 0 && c2[2] >= c1[2] && hz > 0) ? 100*(c2[2]-c1[2])/(hz*seconds) : 0
            printf "%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s\t%.2f\t%s\t%s\t%.2f\t%s\t%s\t%s\t%d\t%s\t%.6f\t%s\n",
                timestamp,b[1],bp_hit,valid_interval ? reads/seconds : 0,valid_interval ? data_read/seconds : 0,valid_interval ? rnd/seconds : 0,tmp_pct,
                b[8],b[9],qcache_pct,log_waits,wait_free,cpu,mem[1],mem[2],load1,restart,selects,seconds,sample_status
        }'
}

dbtune_collect_sample_header() {
    printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tcom_select_delta\tinterval_seconds\tsample_status\n'
}

dbtune_collect_legacy_sample_header() {
    printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\n'
}

dbtune_collect_append_sample() {
    local line=$1
    local file header expected

    file=$(dbtune_collect_samples_file)
    expected=$(dbtune_collect_sample_header)
    if [[ ! -s $file ]]; then
        printf '%s\n' "$expected" >>"$file" || return
    else
        IFS= read -r header <"$file" || return 1
        if [[ $header != "$expected" ]]; then
            dbtune_log error "$(dbtune_msg collect_sample_header_unsupported)"
            return 65
        fi
    fi
    printf '%s\n' "$line" >>"$file"
}

dbtune_collect_sample_count() {
    local file

    file=$(dbtune_collect_samples_file)
    [[ -r $file ]] || {
        printf '0\n'
        return 0
    }
    dbtune_samples_inspect "$file" count
}

dbtune_collect_daily_dbsize() {
    local today last_file dbsize_file rows timestamp database size

    today=${DBTUNE_TODAY:-$("${DBTUNE_DATE:-date}" -u +%F)}
    last_file=${DBTUNE_DBSIZE_DATE_FILE:-$DBTUNE_STATE_DIR/dbsize-date}
    dbsize_file=$(dbtune_collect_dbsize_file)
    if [[ -r $last_file ]] && [[ $(<"$last_file") == "$today" ]]; then
        return 0
    fi
    rows=$(dbtune_sql "SELECT TABLE_SCHEMA, COALESCE(SUM(DATA_LENGTH+INDEX_LENGTH),0) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys') GROUP BY TABLE_SCHEMA ORDER BY TABLE_SCHEMA;") || return
    if [[ ! -s $dbsize_file ]]; then
        printf 'timestamp\tdatabase\tsize_bytes\n' >>"$dbsize_file" || return
    fi
    timestamp=$(dbtune_now)
    while IFS=$'\t' read -r database size; do
        [[ -n $database ]] || continue
        printf '%s\t%s\t%s\n' "$timestamp" "$database" "$size" >>"$dbsize_file" || return
    done <<<"$rows"
    printf '%s\n' "$today" | dbtune_atomic_write "$last_file" 600
}

dbtune_collect_finalize() {
    local samples=$1 timer_result=ok

    dbtune_collect_disable_timer || timer_result=failed
    if ! dbtune_collect_finish_locked complete "reason=deadline samples=$samples timer=$timer_result"; then
        dbtune_log error "$(dbtune_msg collect_auto_stop_failed)"
        dbtune_event collect_finalize_failed step stop || true
        return 0
    fi
    # Automatic completion intentionally uses default arguments.
    # shellcheck disable=SC2119
    if ! declare -F cmd_analyze >/dev/null 2>&1 || ! cmd_analyze; then
        dbtune_log error "$(dbtune_msg collect_auto_analyze_failed)"
        dbtune_event collect_finalize_failed step analyze || true
        return 0
    fi
    # Automatic report generation takes no arguments.
    # shellcheck disable=SC2119
    if ! declare -F cmd_report >/dev/null 2>&1 || ! cmd_report; then
        dbtune_log error "$(dbtune_msg collect_auto_report_failed)"
        dbtune_event collect_finalize_failed step report || true
    fi
    return 0
}

dbtune_collect_restore_language() {
    local ui_lang

    ui_lang=$(dbtune_collect_value ui_lang 2>/dev/null) || ui_lang=en
    dbtune_i18n_set "$ui_lang"
}

dbtune_collect_tick_body() {
    local now deadline sample_seconds first second cpu_first cpu_second memory load1
    local uptime_first uptime_second restart_flag=0 clock_ticks line
    local previous_uptime='' previous_monotonic='' previous_epoch='' previous_pid='' previous_start=''
    local current_pid current_start monotonic_first='' monotonic_second='' sample_epoch
    local last_uptime_file sample_count min_auto_samples slow_log_result=failed restart_trigger=periodic timer_result
    local health_status='' interval_seconds=0 sample_status=degraded_interval interval_status
    local restart_status=degraded_restart_identity

    [[ $(dbtune_state_read) == collecting ]] || return 0
    if [[ -r $(dbtune_collect_health_file) ]]; then
        IFS=$'\t' read -r _ health_status _ _ <"$(dbtune_collect_health_file)" || health_status=''
    fi
    if [[ $health_status == restore_pending ]]; then
        dbtune_event tick_skipped reason restore_pending || true
        return 0
    fi
    now=$(dbtune_collect_epoch) || { dbtune_collect_health error epoch; return 0; }
    deadline=$(dbtune_collect_value deadline_epoch) || { dbtune_collect_health error config; return 0; }
    if awk -v now="$now" -v deadline="$deadline" 'BEGIN { exit !(now >= deadline) }'; then
        sample_count=$(dbtune_collect_sample_count)
        min_auto_samples=${DBTUNE_MIN_AUTO_SAMPLES:-288}
        dbtune_is_uint "$min_auto_samples" || min_auto_samples=288
        if ((sample_count >= min_auto_samples)); then
            dbtune_collect_finalize "$sample_count"
            return 0
        fi
        timer_result=ok
        dbtune_collect_disable_timer || timer_result=failed
        dbtune_collect_finish_locked incomplete "reason=deadline samples=$sample_count minimum=$min_auto_samples timer=$timer_result" || true
        dbtune_event collect_deadline_incomplete samples "$sample_count" minimum "$min_auto_samples" || true
        return 0
    fi
    dbtune_collect_guards || return 0
    sample_seconds=${DBTUNE_SAMPLE_SECONDS:-60}
    if ! dbtune_require_uint "DBTUNE_SAMPLE_SECONDS" "$sample_seconds" 1 3600; then
        dbtune_collect_health error sample_seconds || true
        return 0
    fi

    first=$(dbtune_collect_status_snapshot) || { dbtune_collect_health error sql_first; return 0; }
    cpu_first=$(dbtune_collect_cpu_snapshot) || { dbtune_collect_health error cpu_first; return 0; }
    monotonic_first=$(dbtune_collect_monotonic 2>/dev/null) || monotonic_first=''
    last_uptime_file=$(dbtune_collect_last_uptime_file)
    if [[ -r $last_uptime_file ]]; then
        IFS=$'\t' read -r previous_uptime previous_monotonic previous_epoch previous_pid previous_start <"$last_uptime_file" || previous_uptime=''
    fi
    "${DBTUNE_SLEEP:-sleep}" "$sample_seconds" || { dbtune_collect_health error sleep; return 0; }
    second=$(dbtune_collect_status_snapshot) || { dbtune_collect_health error sql_second; return 0; }
    cpu_second=$(dbtune_collect_cpu_snapshot) || { dbtune_collect_health error cpu_second; return 0; }
    monotonic_second=$(dbtune_collect_monotonic 2>/dev/null) || monotonic_second=$monotonic_first
    memory=$(dbtune_collect_memory_snapshot) || { dbtune_collect_health error memory; return 0; }
    load1=$(dbtune_collect_load1) || { dbtune_collect_health error loadavg; return 0; }

    IFS=$'\t' read -r uptime_first _ <<<"$first"
    IFS=$'\t' read -r uptime_second _ <<<"$second"
    restart_status=$(dbtune_collect_restart_status "$previous_uptime" "$previous_monotonic" "$previous_epoch" \
        "$previous_pid" "$previous_start" "$uptime_first" "$uptime_second" "$monotonic_first" \
        "$now" "$cpu_first" "$cpu_second") || restart_status=degraded_restart_identity
    if [[ $restart_status == restart ]]; then
        restart_flag=1
        restart_trigger=restart
        dbtune_event db_restart_detected previous_uptime "${previous_uptime:-unknown}" uptime "$uptime_second" \
            previous_pid "${previous_pid:-unknown}" current_pid "${cpu_second%%$'\t'*}" || true
    fi
    interval_seconds=$(dbtune_collect_interval_seconds "$monotonic_first" "$monotonic_second" 2>/dev/null) || interval_seconds=0
    interval_status=$(dbtune_collect_interval_status "$interval_seconds" "$sample_seconds")
    if [[ $restart_status == degraded_restart_identity ]]; then
        sample_status=degraded_restart_identity
    else
        sample_status=$interval_status
    fi
    if ! slow_log_result=$(dbtune_collect_ensure_slow_log "$restart_trigger"); then
        slow_log_result=failed
        dbtune_event collect_slow_log_self_heal_failed trigger "$restart_trigger" || true
    fi
    clock_ticks=${DBTUNE_CLK_TCK:-$("${DBTUNE_GETCONF:-getconf}" CLK_TCK 2>/dev/null || printf '100')}
    line=$(dbtune_collect_delta "$(dbtune_now)" "$first" "$second" "$interval_seconds" \
        "$cpu_first" "$cpu_second" "$clock_ticks" "$memory" "$load1" "$restart_flag" "$sample_status") || {
        dbtune_collect_health error delta
        return 0
    }
    dbtune_collect_append_sample "$line" || { dbtune_collect_health error append; return 0; }
    sample_epoch=$(dbtune_collect_epoch) || sample_epoch=$now
    if dbtune_collect_identity_valid "$uptime_second" "$monotonic_second" "$sample_epoch" "$cpu_second"; then
        IFS=$'\t' read -r current_pid _ current_start <<<"$cpu_second"
        printf '%s\t%s\t%s\t%s\t%s\n' "$uptime_second" "$monotonic_second" "$sample_epoch" \
            "$current_pid" "$current_start" | dbtune_atomic_write "$last_uptime_file" 600 || {
            dbtune_collect_health error uptime_write
            return 0
        }
    fi
    dbtune_collect_daily_dbsize || dbtune_event dbsize_snapshot_failed || true
    if [[ $slow_log_result == failed ]]; then
        dbtune_collect_health error "restart_flag=$restart_flag sample_status=$sample_status interval_seconds=$interval_seconds slow_log=failed" || true
    elif [[ $sample_status != ok ]]; then
        dbtune_collect_health degraded "restart_flag=$restart_flag sample_status=$sample_status interval_seconds=$interval_seconds slow_log=$slow_log_result" || true
    else
        dbtune_collect_health ok "restart_flag=$restart_flag sample_status=$sample_status interval_seconds=$interval_seconds slow_log=$slow_log_result" || true
    fi
    return 0
}

cmd_tick() {
    local lock_file lock_identity lock_fd flock_command=${DBTUNE_FLOCK:-flock}

    if (($#)); then
        dbtune_log warn "$(dbtune_msg collect_tick_arguments_ignored)"
    fi
    dbtune_init_state_dir || return 0
    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || flock_command=$(dbtune_runtime_command_path flock) || return 0
    lock_file=$(dbtune_collect_lock_file)
    dbtune_open_state_lock lock_fd "$lock_file" "$(dbtune_msg collect_label_collector_lock)" || {
        dbtune_collect_health error lock_open || true
        return 0
    }
    lock_identity=$DBTUNE_STATE_LOCK_IDENTITY
    if ! "$flock_command" -n "$lock_fd"; then
        dbtune_event tick_skipped reason locked || true
        exec {lock_fd}>&-
        return 0
    fi
    if ! dbtune_validate_state_lock "$lock_file" "$(dbtune_msg collect_label_collector_lock)" "$lock_identity"; then
        "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
        exec {lock_fd}>&-
        return 0
    fi
    dbtune_collect_tick_body || true
    "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    return 0
}
