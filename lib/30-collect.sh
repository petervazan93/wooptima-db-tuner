dbtune_collect_usage() {
    cat <<'USAGE'
Pouzitie:
  dbtune collect start [--days N] [--long-query-time SEKUNDY]
  dbtune collect status
  dbtune collect stop
USAGE
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
        dbtune_log error "--long-query-time musi byt nezaporne cislo"
        return 64
    }
    awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 3600) }' || {
        dbtune_log error "--long-query-time musi byt v rozsahu 0 az 3600"
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

    {
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
        dbtune_log error "Build neobsahuje embedded systemd assety"
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
    if [[ $program_path != /* || $program_path =~ [[:space:]] ]]; then
        dbtune_log error "DBTUNE_PROGRAM_PATH musi byt absolutna cesta bez medzier"
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
                (($# >= 2)) || { dbtune_log error "--days vyzaduje hodnotu"; return 64; }
                days=$2
                shift 2
                ;;
            --days=*) days=${1#*=}; shift ;;
            --long-query-time)
                (($# >= 2)) || { dbtune_log error "--long-query-time vyzaduje hodnotu"; return 64; }
                long_query_time=$2
                shift 2
                ;;
            --long-query-time=*) long_query_time=${1#*=}; shift ;;
            -h|--help) dbtune_collect_usage; return 0 ;;
            *) dbtune_log error "Neznama collect start volba: $1"; return 64 ;;
        esac
    done
    dbtune_require_uint "--days" "$days" 1 3650 || return
    dbtune_collect_validate_long_query_time "$long_query_time" || return
    dbtune_require_state collect_start || return
    dbtune_init_state_dir || return 1

    originals=$(dbtune_sql 'SELECT @@GLOBAL.slow_query_log, @@GLOBAL.slow_query_log_file, @@GLOBAL.long_query_time, @@GLOBAL.log_slow_verbosity;') || return
    IFS=$'\t' read -r original_slow original_file original_long original_verbosity <<<"$originals"
    [[ $original_slow == 0 || $original_slow == 1 ]] || {
        dbtune_log error "MariaDB vratila neplatny povodny stav slow logu"
        return 65
    }
    [[ -n $original_file && -n $original_long ]] || {
        dbtune_log error "MariaDB nevratila povodne slow-log hodnoty"
        return 65
    }

    slow_dir=${slow_log%/*}
    [[ $slow_dir != "$slow_log" ]] || slow_dir=.
    if [[ ! -d $slow_dir ]]; then
        "${DBTUNE_INSTALL:-install}" -d -o "${DBTUNE_MYSQL_USER:-mysql}" -g "${DBTUNE_MYSQL_GROUP:-mysql}" -m 750 "$slow_dir" || return 1
    fi
    started_epoch=$(dbtune_collect_epoch) || return
    dbtune_require_uint "aktualny epoch" "$started_epoch" 1 2147483647 || return
    deadline_epoch=$(awk -v start="$started_epoch" -v days="$days" 'BEGIN { printf "%.0f\n", start + days * 86400 }')
    dbtune_collect_write_config "$days" "$long_query_time" "$slow_log" "$started_epoch" "$deadline_epoch" \
        "$original_slow" "$original_file" "$original_long" "$original_verbosity" || return

    if ! dbtune_collect_install_units || ! dbtune_collect_set_slow_log "$slow_log" "$long_query_time"; then
        dbtune_log error "Spustenie collect zlyhalo pred aktivaciou timeru"
        dbtune_collect_restore_slow_log >/dev/null 2>&1 || true
        rm -f "$(dbtune_collect_config_file)"
        return 1
    fi
    rm -f "$(dbtune_collect_last_uptime_file)"
    if ! dbtune_state_transition collecting; then
        dbtune_collect_restore_slow_log >/dev/null 2>&1 || true
        rm -f "$(dbtune_collect_config_file)"
        return 1
    fi

    systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}
    timer_unit=${DBTUNE_COLLECT_TIMER_UNIT:-dbtune-collect.timer}
    if ! "$systemctl_command" enable --now "$timer_unit"; then
        dbtune_collect_restore_slow_log >/dev/null 2>&1 || true
        dbtune_state_write audited || true
        dbtune_event collect_start_failed reason timer_enable || true
        return 1
    fi
    dbtune_event collect_started days "$days" deadline_epoch "$deadline_epoch" long_query_time "$long_query_time" || true
    printf 'Zber spusteny na %s dni (deadline epoch %s).\n' "$days" "$deadline_epoch"
}

dbtune_collect_status() {
    local state key value

    (($# == 0)) || { dbtune_collect_usage >&2; return 64; }
    state=$(dbtune_state_read) || return
    printf 'state\t%s\n' "$state"
    if [[ -r $(dbtune_collect_config_file) ]]; then
        for key in started_at days deadline_epoch long_query_time slow_log_file; do
            value=$(dbtune_collect_value "$key" 2>/dev/null) || continue
            printf '%s\t%s\n' "$key" "$value"
        done
    fi
}

dbtune_collect_stop() {
    local systemctl_command timer_unit result=0

    (($# == 0)) || { dbtune_collect_usage >&2; return 64; }
    dbtune_require_state collect_stop || return
    systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}
    timer_unit=${DBTUNE_COLLECT_TIMER_UNIT:-dbtune-collect.timer}
    "$systemctl_command" disable --now "$timer_unit" || result=1
    if ! dbtune_collect_restore_slow_log; then
        dbtune_log error "Nepodarilo sa obnovit povodne runtime slow-log hodnoty"
        result=1
    fi
    ((result == 0)) || return 1
    dbtune_state_transition collected || return
    dbtune_event collect_stopped || true
    printf 'Zber zastaveny.\n'
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

    printf '%s\t%s\t%s\n' "$(dbtune_now)" "$status" "$detail" |
        dbtune_atomic_write "$(dbtune_collect_health_file)" 600
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

dbtune_collect_guards() {
    local samples slow_log slow_path free_state free_slow samples_bytes slow_bytes
    local min_free=${DBTUNE_MIN_FREE_KB:-1048576}
    local max_samples=${DBTUNE_MAX_SAMPLES_BYTES:-2147483648}
    local max_slow=${DBTUNE_MAX_SLOW_LOG_BYTES:-2147483648}
    local reason=''

    samples=$(dbtune_collect_samples_file)
    slow_log=$(dbtune_collect_value slow_log_file) || return 1
    slow_path=${slow_log%/*}
    [[ -d $slow_path ]] || slow_path=$DBTUNE_STATE_DIR
    free_state=$(dbtune_collect_available_kb "$DBTUNE_STATE_DIR") || return 1
    free_slow=$(dbtune_collect_available_kb "$slow_path") || return 1
    samples_bytes=$(dbtune_collect_file_bytes "$samples") || return 1
    slow_bytes=$(dbtune_collect_file_bytes "$slow_log") || return 1

    if awk -v a="$free_state" -v b="$free_slow" -v limit="$min_free" 'BEGIN { exit !(a < limit || b < limit) }'; then
        reason=low_disk
    elif awk -v size="$samples_bytes" -v limit="$max_samples" 'BEGIN { exit !(size >= limit) }'; then
        reason=samples_limit
    elif awk -v size="$slow_bytes" -v limit="$max_slow" 'BEGIN { exit !(size >= limit) }'; then
        reason=slow_log_limit
    fi
    [[ -z $reason ]] && return 0

    dbtune_sql 'SET GLOBAL slow_query_log=OFF;' >/dev/null 2>&1 || true
    dbtune_event collect_guard reason "$reason" samples_bytes "$samples_bytes" slow_log_bytes "$slow_bytes" || true
    dbtune_collect_health guard "$reason" || true
    dbtune_log warn "Collect watchdog zastavil slow log: $reason"
    return 1
}

dbtune_collect_status_snapshot() {
    local raw

    raw=$(dbtune_sql "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests','Innodb_data_read','Handler_read_rnd_next','Created_tmp_disk_tables','Created_tmp_tables','Threads_running','Threads_connected','Qcache_hits','Com_select','Innodb_log_waits','Innodb_buffer_pool_wait_free');") || return
    awk -F '\t' '
        { key=tolower($1); value[key]=$2 }
        END {
            if (!("uptime" in value)) exit 1
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                value["uptime"]+0,
                value["innodb_buffer_pool_reads"]+0,
                value["innodb_buffer_pool_read_requests"]+0,
                value["innodb_data_read"]+0,
                value["handler_read_rnd_next"]+0,
                value["created_tmp_disk_tables"]+0,
                value["created_tmp_tables"]+0,
                value["threads_running"]+0,
                value["threads_connected"]+0,
                value["qcache_hits"]+0,
                value["com_select"]+0,
                value["innodb_log_waits"]+0,
                value["innodb_buffer_pool_wait_free"]+0
        }' <<<"$raw"
}

dbtune_collect_cpu_snapshot() {
    local pid stat_file ticks

    pid=$("${DBTUNE_PGREP:-pgrep}" -xo mariadbd 2>/dev/null) || {
        printf '0\t0\n'
        return 0
    }
    stat_file="${DBTUNE_PROC_ROOT:-/proc}/$pid/stat"
    [[ -r $stat_file ]] || { printf '0\t0\n'; return 0; }
    ticks=$(awk '{ print $14 + $15 }' "$stat_file") || return
    printf '%s\t%s\n' "$pid" "$ticks"
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

    awk -F '\t' -v timestamp="$timestamp" -v first="$first" -v second="$second" \
        -v seconds="$seconds" -v cpu_first="$cpu_first" -v cpu_second="$cpu_second" \
        -v hz="$clock_ticks" -v memory="$memory" -v load1="$load1" -v restart="$restart_flag" '
        function delta(a, b) { if (restart || b < a) return 0; return b-a }
        BEGIN {
            split(first, a, "\t"); split(second, b, "\t")
            split(cpu_first, c1, "\t"); split(cpu_second, c2, "\t")
            split(memory, mem, "\t")
            reads=delta(a[2],b[2]); requests=delta(a[3],b[3])
            data_read=delta(a[4],b[4]); rnd=delta(a[5],b[5])
            tmp_disk=delta(a[6],b[6]); tmp_total=delta(a[7],b[7])
            qhits=delta(a[10],b[10]); selects=delta(a[11],b[11])
            log_waits=delta(a[12],b[12]); wait_free=delta(a[13],b[13])
            bp_hit=requests > 0 ? 100*(1-reads/requests) : 100
            if (bp_hit < 0) bp_hit=0; if (bp_hit > 100) bp_hit=100
            tmp_pct=tmp_total > 0 ? 100*tmp_disk/tmp_total : 0
            qcache_pct=(qhits+selects) > 0 ? 100*qhits/(qhits+selects) : 0
            cpu=(!restart && c1[1] == c2[1] && c1[1] != 0 && c2[2] >= c1[2] && hz > 0) ? 100*(c2[2]-c1[2])/(hz*seconds) : 0
            printf "%s\t%.0f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.0f\t%.0f\t%.2f\t%.0f\t%.0f\t%.2f\t%.0f\t%.0f\t%s\t%d\n",
                timestamp,b[1],bp_hit,reads/seconds,data_read/seconds,rnd/seconds,tmp_pct,
                b[8],b[9],qcache_pct,log_waits,wait_free,cpu,mem[1],mem[2],load1,restart
        }'
}

dbtune_collect_append_sample() {
    local line=$1
    local file

    file=$(dbtune_collect_samples_file)
    if [[ ! -s $file ]]; then
        printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\n' >>"$file" || return
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
    awk 'NR > 1 && NF {count++} END {print count+0}' "$file"
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
    if ! dbtune_collect_stop; then
        dbtune_log error "Automaticke zastavenie collect zlyhalo"
        dbtune_event collect_finalize_failed step stop || true
        return 0
    fi
    # Automaticke dokoncenie zamerne pouziva default argumenty.
    # shellcheck disable=SC2119
    if ! declare -F cmd_analyze >/dev/null 2>&1 || ! cmd_analyze; then
        dbtune_log error "Automaticka analyze faza zlyhala alebo nie je dostupna"
        dbtune_event collect_finalize_failed step analyze || true
        return 0
    fi
    # Report nema pri automatickom dokonceni argumenty.
    # shellcheck disable=SC2119
    if ! declare -F cmd_report >/dev/null 2>&1 || ! cmd_report; then
        dbtune_log error "Automaticka report faza zlyhala alebo nie je dostupna"
        dbtune_event collect_finalize_failed step report || true
    fi
    return 0
}

dbtune_collect_tick_body() {
    local now deadline sample_seconds first second cpu_first cpu_second memory load1
    local uptime_first uptime_second restart_flag=0 clock_ticks line slow_log long_query_time
    local previous_uptime='' last_uptime_file sample_count min_auto_samples

    [[ $(dbtune_state_read) == collecting ]] || return 0
    now=$(dbtune_collect_epoch) || { dbtune_collect_health error epoch; return 0; }
    deadline=$(dbtune_collect_value deadline_epoch) || { dbtune_collect_health error config; return 0; }
    if awk -v now="$now" -v deadline="$deadline" 'BEGIN { exit !(now >= deadline) }'; then
        sample_count=$(dbtune_collect_sample_count)
        min_auto_samples=${DBTUNE_MIN_AUTO_SAMPLES:-288}
        dbtune_is_uint "$min_auto_samples" || min_auto_samples=288
        if ((sample_count >= min_auto_samples)); then
            dbtune_collect_finalize
            return 0
        fi
        dbtune_event collect_deadline_extended samples "$sample_count" minimum "$min_auto_samples" || true
    fi
    dbtune_collect_guards || return 0
    sample_seconds=${DBTUNE_SAMPLE_SECONDS:-60}
    if ! dbtune_require_uint "DBTUNE_SAMPLE_SECONDS" "$sample_seconds" 1 3600; then
        dbtune_collect_health error sample_seconds || true
        return 0
    fi

    first=$(dbtune_collect_status_snapshot) || { dbtune_collect_health error sql_first; return 0; }
    cpu_first=$(dbtune_collect_cpu_snapshot) || { dbtune_collect_health error cpu_first; return 0; }
    last_uptime_file=$(dbtune_collect_last_uptime_file)
    if [[ -r $last_uptime_file ]]; then
        IFS= read -r previous_uptime <"$last_uptime_file" || previous_uptime=''
    fi
    "${DBTUNE_SLEEP:-sleep}" "$sample_seconds" || { dbtune_collect_health error sleep; return 0; }
    second=$(dbtune_collect_status_snapshot) || { dbtune_collect_health error sql_second; return 0; }
    cpu_second=$(dbtune_collect_cpu_snapshot) || { dbtune_collect_health error cpu_second; return 0; }
    memory=$(dbtune_collect_memory_snapshot) || { dbtune_collect_health error memory; return 0; }
    load1=$(dbtune_collect_load1) || { dbtune_collect_health error loadavg; return 0; }

    IFS=$'\t' read -r uptime_first _ <<<"$first"
    IFS=$'\t' read -r uptime_second _ <<<"$second"
    if awk -v previous="$previous_uptime" -v first="$uptime_first" -v second="$uptime_second" \
        'BEGIN { exit !((previous != "" && first < previous) || second <= first) }'; then
        restart_flag=1
        slow_log=$(dbtune_collect_value slow_log_file) || slow_log=${DBTUNE_SLOW_LOG:-/var/log/mysql/slow.log}
        long_query_time=$(dbtune_collect_value long_query_time) || long_query_time=2
        if dbtune_collect_set_slow_log "$slow_log" "$long_query_time"; then
            dbtune_event db_restart_detected previous_uptime "$uptime_first" uptime "$uptime_second" || true
        else
            dbtune_event db_restart_detected previous_uptime "$uptime_first" uptime "$uptime_second" slow_log_reenable failed || true
        fi
    fi
    clock_ticks=${DBTUNE_CLK_TCK:-$("${DBTUNE_GETCONF:-getconf}" CLK_TCK 2>/dev/null || printf '100')}
    line=$(dbtune_collect_delta "$(dbtune_now)" "$first" "$second" "$sample_seconds" \
        "$cpu_first" "$cpu_second" "$clock_ticks" "$memory" "$load1" "$restart_flag") || {
        dbtune_collect_health error delta
        return 0
    }
    dbtune_collect_append_sample "$line" || { dbtune_collect_health error append; return 0; }
    printf '%s\n' "$uptime_second" | dbtune_atomic_write "$last_uptime_file" 600 || {
        dbtune_collect_health error uptime_write
        return 0
    }
    dbtune_collect_daily_dbsize || dbtune_event dbsize_snapshot_failed || true
    dbtune_collect_health ok "restart_flag=$restart_flag" || true
    return 0
}

cmd_tick() {
    local lock_file lock_fd

    if (($#)); then
        dbtune_log warn "_tick ignoruje argumenty"
    fi
    dbtune_init_state_dir || return 0
    lock_file=${DBTUNE_COLLECT_LOCK_FILE:-$DBTUNE_STATE_DIR/collect.lock}
    exec {lock_fd}>"$lock_file" || { dbtune_collect_health error lock_open || true; return 0; }
    if ! "${DBTUNE_FLOCK:-flock}" -n "$lock_fd"; then
        dbtune_event tick_skipped reason locked || true
        exec {lock_fd}>&-
        return 0
    fi
    dbtune_collect_tick_body || true
    "${DBTUNE_FLOCK:-flock}" -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    return 0
}
