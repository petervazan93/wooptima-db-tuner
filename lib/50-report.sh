dbtune_report_markdown_file() {
    dbtune_path report.md
}

dbtune_report_json_file() {
    dbtune_path report.json
}

dbtune_proposal_file() {
    dbtune_path proposed-99-zz-tuning.cnf
}

dbtune_report_no_arguments() {
    local command_name=${1:-report}
    shift || true
    if (($#)); then
        dbtune_log error "$(dbtune_printf report_arguments_unsupported "$command_name")"
        return 64
    fi
}

dbtune_report_safe() {
    dbtune_redact "${1:-}"
}

dbtune_markdown_escape() {
    local value
    value=$(dbtune_report_safe "${1:-}")
    value=${value//\\/\\\\}
    value=${value//&/\&amp;}
    value=${value//</\&lt;}
    value=${value//>/\&gt;}
    value=${value//|/\\|}
    value=${value//\`/\\\`}
    value=${value//\[/\\[}
    value=${value//\]/\\]}
    value=${value//\(/\\(}
    value=${value//\)/\\)}
    value=${value//!/\\!}
    value=${value//\*/\\*}
    value=${value//_/\\_}
    value=${value//\~/\\~}
    value=${value//#/\\#}
    printf '%s' "$value"
}

dbtune_analysis_line_is_valid() {
    local line=${1-}
    local without_tabs=${line//$'\t'/}
    ((${#line} - ${#without_tabs} == 7))
}

dbtune_analysis_validate_schema() {
    local file=${1:-}
    local header

    [[ -r $file ]] || return 66
    IFS= read -r header <"$file" || header=''
    case $header in
        $'rule_id\tscope\tseverity\tverdict\tproposed_key\tproposed_value\tevidence\treason_id')
            return 0
            ;;
        $'rule_id\tscope\tseverity\tverdict\tproposed_key\tproposed_value\tevidence\treason_sk')
            dbtune_log error "$(dbtune_msg analysis_old_schema)"
            return 65
            ;;
        *)
            dbtune_log error "$(dbtune_msg analysis_invalid_header)"
            return 65
            ;;
    esac
}

dbtune_analysis_parse() {
    local line=${1-}
    local encoded

    dbtune_analysis_line_is_valid "$line" || return 1
    encoded=${line//$'\t'/$'\034'}
    IFS=$'\034' read -r \
        DBTUNE_ANALYSIS_RULE_ID \
        DBTUNE_ANALYSIS_SCOPE \
        DBTUNE_ANALYSIS_SEVERITY \
        DBTUNE_ANALYSIS_VERDICT \
        DBTUNE_ANALYSIS_PROPOSED_KEY \
        DBTUNE_ANALYSIS_PROPOSED_VALUE \
        DBTUNE_ANALYSIS_EVIDENCE \
        DBTUNE_ANALYSIS_REASON_ID \
        _dbtune_analysis_end <<<"${encoded}"$'\034_'
    DBTUNE_ANALYSIS_REASON_ID=${DBTUNE_ANALYSIS_REASON_ID%$'\r'}
}

dbtune_analysis_verdict_is_valid() {
    case ${1:-} in
        ACTION|CHANGE|CLEANUP|CREDENTIAL-NOTE|DEPRECATED|DISABLED|DROPIN-MISSING|DUPLICATE-WRITES|EXPOSED|FAILED|FREQUENT|KEEP|MEMORY-GUARD|MIGRATE|MISSING|NO-SHRINK|OK|POLICY|PURGE-CANDIDATE|REDIS-DOWN|REDUCE|REMOVED|REVIEW|ROGUE-INDEX|SYSTEMD-LIMIT|TOO-LARGE|UNKNOWN|UNSUPPORTED)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dbtune_analysis_verdict_can_propose() {
    case ${1:-} in
        CHANGE|REDUCE) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_analysis_load() {
    local file=${1:-}
    local line header=1

    DBTUNE_ANALYSIS_LINES=()
    dbtune_analysis_validate_schema "$file" || return
    while IFS= read -r line || [[ -n $line ]]; do
        if ((header)); then
            header=0
            continue
        fi
        [[ -n $line ]] || continue
        if ! dbtune_analysis_line_is_valid "$line"; then
            dbtune_log error "$(dbtune_msg analysis_invalid_record)"
            return 65
        fi
        dbtune_analysis_parse "$line" || return 65
        if ! dbtune_analysis_verdict_is_valid "$DBTUNE_ANALYSIS_VERDICT" ||
            [[ ! $DBTUNE_ANALYSIS_REASON_ID =~ ^reason_[a-z0-9_]+$ ]] ||
            ! dbtune_i18n_lookup "$DBTUNE_ANALYSIS_REASON_ID"; then
            dbtune_log error "$(dbtune_msg analysis_invalid_record)"
            return 65
        fi
        DBTUNE_ANALYSIS_LINES+=("$line")
    done <"$file"
    ((header == 0)) || {
        dbtune_log error "$(dbtune_msg analysis_empty)"
        return 65
    }
}

dbtune_analysis_count() {
    local scope_filter=${1:-all}
    local severity_filter=${2:-all}
    local line count=0

    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        [[ $scope_filter == all || $DBTUNE_ANALYSIS_SCOPE == "$scope_filter" ]] || continue
        [[ $severity_filter == all || $DBTUNE_ANALYSIS_SEVERITY == "$severity_filter" ]] || continue
        count=$((count + 1))
    done
    printf '%s\n' "$count"
}

dbtune_analysis_server_support() {
    local line

    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        if [[ $DBTUNE_ANALYSIS_RULE_ID == R-VERSION && $DBTUNE_ANALYSIS_SCOPE == server &&
            $DBTUNE_ANALYSIS_VERDICT == UNSUPPORTED ]]; then
            printf 'unsupported\n'
            return 0
        fi
    done
    printf 'supported\n'
}

dbtune_security_rule() {
    case ${DBTUNE_ANALYSIS_RULE_ID:-}:${DBTUNE_ANALYSIS_SCOPE:-} in
        R-SEC*:*|*:security|*:security:*) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_audit_value() {
    local file=${1:-}
    local wanted key value candidate
    local -a candidates=()
    shift || true

    [[ -r $file ]] || return 1
    dbtune_audit_validate "$file" || return 65
    for wanted in "$@"; do
        candidates+=("$(dbtune_audit_key_canonical "$wanted")")
    done
    while IFS=$'\t' read -r key value _rest || [[ -n ${key:-} ]]; do
        [[ -n $key && $key != key ]] || continue
        dbtune_is_sensitive_key "$key" && continue
        key=$(dbtune_audit_key_canonical "$key") || return
        for candidate in "${candidates[@]}"; do
            if [[ $key == "$candidate" ]]; then
                printf '%s\n' "${value%$'\r'}"
                return 0
            fi
        done
    done <"$file"
    return 1
}

dbtune_audit_current_value() {
    local file=${1:-}
    local proposed_key=${2:-}
    local key value target

    dbtune_audit_validate "$file" || return 65
    target=$(dbtune_audit_key_canonical "$proposed_key") || return
    while IFS=$'\t' read -r key value _rest || [[ -n ${key:-} ]]; do
        [[ -n $key && $key != key ]] || continue
        dbtune_is_sensitive_key "$key" && continue
        key=$(dbtune_audit_key_canonical "$key") || return
        [[ $key == "$target" ]] || continue
        printf '%s\n' "${value%$'\r'}"
        return 0
    done <"$file"
    return 1
}

dbtune_tsv_row_count() {
    local file=${1:-}
    local kind=${2:-row}
    [[ -r $file ]] || {
        printf '0\n'
        return 0
    }
    awk -F '\t' -v kind="$kind" '
        NR == 1 && ($1 == kind || $1 == kind "_id" || (kind == "database" && ($1 == "db" || $1 == "db_name"))) { header=1; next }
        NF {
            if (!header && NF >= 3) { scoped=1; seen[$1]=1 }
            else count++
        }
        END { if (scoped) print length(seen); else print count + 0 }
    ' "$file"
}

dbtune_tsv_split_row() {
    local encoded
    encoded=${1//$'\t'/$'\034'}
    IFS=$'\034' read -r -a DBTUNE_TSV_FIELDS <<<"$encoded"
}

dbtune_tsv_has_header() {
    local field normalized recognized=0

    for field in "${DBTUNE_TSV_FIELDS[@]}"; do
        normalized=$(dbtune_key_normalize "$field")
        case $normalized in
            app|app_id|name|path|webroot|type|database|database_name|db|db_name|prefix|woocommerce|wordpress|size_bytes|size_mb|size_gb|engine|tables) recognized=$((recognized + 1)) ;;
            *) return 1 ;;
        esac
    done
    ((recognized > 0))
}

dbtune_render_tsv_inventory() {
    local title=${1:-Inventory}
    local file=${2:-}
    local line first=1 header=0 row=0 i key value detail
    local -a headers

    printf '### %s\n\n' "$title"
    if [[ ! -s $file ]]; then
        printf '%s\n\n' "$(dbtune_msg report_inventory_unavailable)"
        return 0
    fi

    headers=()
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        dbtune_tsv_split_row "$line"
        if ((first)); then
            first=0
            if dbtune_tsv_has_header; then
                headers=("${DBTUNE_TSV_FIELDS[@]}")
                header=1
                continue
            fi
        fi
        if ((!header)) && ((${#DBTUNE_TSV_FIELDS[@]} >= 3)) && [[ ${DBTUNE_TSV_FIELDS[1]} == autoload.top.* ]]; then
            continue
        fi
        row=$((row + 1))
        detail=''
        for ((i = 0; i < ${#DBTUNE_TSV_FIELDS[@]}; i++)); do
            value=${DBTUNE_TSV_FIELDS[$i]%$'\r'}
            if ((header)); then
                key=${headers[$i]:-field_$((i + 1))}
            else
                key=field_$((i + 1))
            fi
            dbtune_is_sensitive_key "$key" && continue
            [[ -n $value ]] || continue
            [[ -z $detail ]] || detail+='; '
            detail+="\`$(dbtune_markdown_escape "$key")\`=$(dbtune_markdown_escape "$value")"
        done
        [[ -n $detail ]] || detail=$(dbtune_msg report_inventory_no_safe_values)
        dbtune_printf report_inventory_record "$row" "$detail"
    done <"$file"
    printf '\n'
}

dbtune_samples_count() {
    local file=${1:-}

    dbtune_samples_inspect "$file" count
}

dbtune_samples_stats() {
    local file=${1:-}
    local aliases=${2:-}
    local fallback=${3:-1}

    local p50 p95 p99 maximum

    p50=$(dbtune_tsv_percentile "$file" "$aliases" "$fallback" 50 2>/dev/null || printf 'n/a')
    p95=$(dbtune_tsv_percentile "$file" "$aliases" "$fallback" 95 2>/dev/null || printf 'n/a')
    p99=$(dbtune_tsv_percentile "$file" "$aliases" "$fallback" 99 2>/dev/null || printf 'n/a')
    maximum=$(dbtune_tsv_percentile "$file" "$aliases" "$fallback" 100 2>/dev/null || printf 'n/a')
    if [[ $p50 == n/a ]]; then
        printf 'n/a\tn/a\tn/a\tn/a\n'
    else
        printf '%.2f\t%.2f\t%.2f\t%.2f\n' "$p50" "$p95" "$p99" "$maximum"
    fi
}

dbtune_samples_worst() {
    local file=${1:-}

    dbtune_samples_diagnostics "$file" >/dev/null || return 65
    awk -F '\t' '
        function norm(value) { value=tolower(value); gsub(/-/, "_", value); return value }
        function oneof(value, list, count, parts, i) { count=split(list, parts, ","); for (i=1;i<=count;i++) if (value==parts[i]) return 1; return 0 }
        NR == 1 {
            ts=1; bp=3; miss=4; readbps=5; rnd=6; threads=8; cpu=13; header=0
            for (i=1;i<=NF;i++) {
                name=norm($i)
                if (oneof(name,"timestamp,sampled_at,time,ts")) { ts=i; header=1 }
                if (oneof(name,"bp_hit_pct,bp_hit_ratio,buffer_pool_hit_pct")) bp=i
                if (oneof(name,"bp_miss_s,bp_misses_s,bp_misses_per_s")) miss=i
                if (oneof(name,"data_read_s,data_read_bps,innodb_data_read_bps,data_read_per_s")) readbps=i
                if (oneof(name,"rnd_next_s,handler_rnd_next_s,handler_read_rnd_next_s,handler_read_rnd_next_per_s")) rnd=i
                if (oneof(name,"threads_running,running_threads")) threads=i
                if (oneof(name,"mariadbd_cpu_pct,cpu_pct,db_cpu_pct")) cpu=i
                if (name == "sample_status") status_column=i
                if (name == "restart_flag") restart_column=i
            }
            if (header) next
        }
        {
            if (status_column && $status_column != "ok") next
            if (restart_column && $restart_column != 0) next
            score=($cpu ~ /^-?[0-9]+([.][0-9]+)?$/) ? $cpu+0 : (($miss ~ /^-?[0-9]+([.][0-9]+)?$/) ? $miss+0 : 0)
            printf "%.8f\t%s\t%s\t%s\t%s\t%s\t%s\n", score, $ts, $cpu, $bp, $miss, $readbps, $threads
        }
    ' < <(dbtune_samples_valid_rows "$file") | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | awk -F '\t' 'NR <= 5'
}

dbtune_backup_correlation() {
    local timestamp=${1:-}
    local status source checked success schedules process_count age max_age sample_epoch success_epoch delta relation

    status=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.status 2>/dev/null || printf unknown)
    source=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.source 2>/dev/null || printf unknown)
    checked=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.checked_at 2>/dev/null || printf unknown)
    success=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.last_success 2>/dev/null || printf unknown)
    age=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.age_seconds 2>/dev/null || printf unknown)
    max_age=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.max_age_seconds 2>/dev/null || printf unknown)
    schedules=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.schedule_count 2>/dev/null || printf 0)
    process_count=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" backup.process_count 2>/dev/null || printf 0)
    relation=no_verified_timestamp
    delta=unknown
    if [[ $status == verified ]] && sample_epoch=$(dbtune_iso8601_epoch "$timestamp" 2>/dev/null) &&
        success_epoch=$(dbtune_iso8601_epoch "$success" 2>/dev/null); then
        if ((sample_epoch >= success_epoch)); then
            delta=$((sample_epoch - success_epoch))
        else
            delta=$((success_epoch - sample_epoch))
        fi
        if ((delta <= 900)); then
            relation=near_last_success
        else
            relation=outside_last_success_window
        fi
    fi
    dbtune_report_safe "relation=$relation; status=$status; source=$source; last_success=$success; age_seconds=$age; max_age_seconds=$max_age; delta_seconds=$delta; checked_at=$checked; schedule_count=$schedules; process_count_at_audit=$process_count"
}

dbtune_worst_load() {
    local line score timestamp cpu bp miss readbps threads correlation

    DBTUNE_WORST_LINES=()
    while IFS=$'\t' read -r score timestamp cpu bp miss readbps threads; do
        [[ -n $timestamp ]] || continue
        correlation=$(dbtune_backup_correlation "$timestamp")
        DBTUNE_WORST_LINES+=("$score"$'\t'"$timestamp"$'\t'"$cpu"$'\t'"$bp"$'\t'"$miss"$'\t'"$readbps"$'\t'"$threads"$'\t'"$correlation")
    done < <(dbtune_samples_worst "$DBTUNE_SAMPLES_FILE")
}

dbtune_scoped_value() {
    local file=${1:-}
    local scope=${2:-}
    local wanted=${3:-}

    [[ -r $file ]] || return 1
    awk -F '\t' -v scope="$scope" -v wanted="$wanted" '$1==scope && $2==wanted {sub(/^[^\t]*\t[^\t]*\t/, ""); print; found=1; exit} END {if (!found) exit 1}' "$file"
}

dbtune_action_wp_command() {
    local webroot=${1:-}
    local owner=${2:-}
    local action=${3:-core-version}
    local prefix

    [[ $webroot == /* && $webroot != *$'\n'* && $webroot != *$'\r'* && $webroot != *$'\t'* ]] || return 1
    [[ $owner =~ ^[A-Za-z_][A-Za-z0-9_-]*$ && $owner != root && $owner != unresolved && $owner != unknown ]] || return 1
    prefix="sudo -u $(dbtune_shell_quote "$owner") -- wp --path=$(dbtune_shell_quote "$webroot")"
    case $action in
        redis) printf '%s redis status\n' "$prefix" ;;
        cron) printf '%s cron event list --due-now --fields=hook,next_run_relative\n' "$prefix" ;;
        multisite) printf '%s site list --fields=blog_id,url\n' "$prefix" ;;
        *) printf '%s core version\n' "$prefix" ;;
    esac
}

dbtune_action_version_at_least() {
    local actual=${1:-0}
    local required=${2:-0}
    local actual_major=0 actual_minor=0 actual_patch=0
    local required_major=0 required_minor=0 required_patch=0

    IFS=. read -r actual_major actual_minor actual_patch <<<"$actual"
    IFS=. read -r required_major required_minor required_patch <<<"$required"
    [[ $actual_major =~ ^[0-9]+$ ]] || actual_major=0
    [[ $actual_minor =~ ^[0-9]+$ ]] || actual_minor=0
    [[ $actual_patch =~ ^[0-9]+$ ]] || actual_patch=0
    [[ $required_major =~ ^[0-9]+$ ]] || required_major=0
    [[ $required_minor =~ ^[0-9]+$ ]] || required_minor=0
    [[ $required_patch =~ ^[0-9]+$ ]] || required_patch=0
    ((actual_major > required_major ||
        (actual_major == required_major && actual_minor > required_minor) ||
        (actual_major == required_major && actual_minor == required_minor && actual_patch >= required_patch)))
}

dbtune_action_version_number() {
    local value=${1:-}
    local version=''

    while [[ $value =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; do
        version=${BASH_REMATCH[1]}
        value=${value#*"$version"}
    done
    [[ -n $version ]] || return 1
    printf '%s\n' "$version"
}

dbtune_action_sql_timeout_capability() {
    local audit_file=${1:-}
    local family version core

    family=$(dbtune_audit_value "$audit_file" database.family server.family sql.server_family 2>/dev/null || true)
    case ${family,,} in
        mariadb)
            version=$(dbtune_audit_value "$audit_file" mariadb.version mariadb_version server.mariadb_version 2>/dev/null || true)
            ;;
        mysql|percona)
            family=mysql
            version=$(dbtune_audit_value "$audit_file" mysql.version mysql_version server.mysql_version server.version 2>/dev/null || true)
            ;;
        *)
            version=$(dbtune_audit_value "$audit_file" mariadb.version mariadb_version server.mariadb_version mysql.version mysql_version server.mysql_version server.version 2>/dev/null || true)
            case ${version,,} in
                *mariadb*) family=mariadb ;;
                *mysql*|*percona*) family=mysql ;;
                *) return 1 ;;
            esac
            ;;
    esac
    core=$(dbtune_action_version_number "$version") || return 1
    case $family in
        mariadb)
            case $core in
                10.6.*|10.11.*|11.*) ;;
                *) return 1 ;;
            esac
            printf 'mariadb_max_statement_time\n'
            ;;
        mysql)
            dbtune_action_version_at_least "$core" 5.7.4 || return 1
            printf 'mysql_max_execution_time\n'
            ;;
        *) return 1 ;;
    esac
}

dbtune_action_sql_command() {
    local database=${1:-}
    local prefix=${2:-}
    local rule=${3:-}
    local capability=${4:-unknown}
    local connect_timeout=${5:-5}
    local statement_timeout=${6:-30}
    local table query client timeout_query timeout_milliseconds

    [[ -n $database && $database != unresolved && $database != *$'\n'* && $database != *$'\r'* && $database != *$'\t'* ]] || return 1
    [[ $prefix =~ ^[A-Za-z0-9_]+$ && ${#prefix} -le 48 ]] || return 1
    [[ $connect_timeout =~ ^[1-9][0-9]*$ && $statement_timeout =~ ^[1-9][0-9]*$ ]] || return 1
    ((10#$connect_timeout <= 30 && 10#$statement_timeout <= 60)) || return 1
    case $rule in
        R-APP-AUTOLOAD)
            table="${prefix}options"
            query="SELECT option_name,LENGTH(option_value) AS bytes FROM \`$table\` WHERE autoload IN ('yes','on','auto') ORDER BY bytes DESC LIMIT 20"
            ;;
        R-APP-HPOS)
            table="${prefix}options"
            query="SELECT option_name,option_value FROM \`$table\` WHERE option_name IN ('woocommerce_custom_orders_table_enabled','woocommerce_custom_orders_table_data_sync_enabled','woocommerce_feature_custom_order_tables_enabled') ORDER BY option_name"
            ;;
        R-APP-SESSIONS)
            table="${prefix}woocommerce_sessions"
            query="SELECT COUNT(*) AS session_rows FROM \`$table\`"
            ;;
        R-APP-AS|R-APP-AS-RETENTION)
            table="${prefix}actionscheduler_actions"
            query="SELECT status,COUNT(*) FROM \`$table\` GROUP BY status ORDER BY status"
            ;;
        R-APP-TRANSIENTS)
            table="${prefix}options"
            query="SELECT COUNT(*),COALESCE(SUM(LENGTH(option_value)),0) FROM \`$table\` WHERE option_name LIKE '\\_transient%'"
            ;;
        R-APP-META-INDEX)
            table="${prefix}postmeta"
            query="SELECT INDEX_NAME,NON_UNIQUE,SEQ_IN_INDEX,COLUMN_NAME,SUB_PART,INDEX_TYPE FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='$table' ORDER BY INDEX_NAME,SEQ_IN_INDEX"
            ;;
        R-APP-LOG-TABLE)
            query="SELECT TABLE_NAME,COALESCE(TABLE_ROWS,0),DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME REGEXP 'log|history|track|event' ORDER BY DATA_LENGTH+INDEX_LENGTH DESC LIMIT 20"
            ;;
        *) query='SELECT DATABASE(), NOW()' ;;
    esac
    case $capability in
        mariadb_max_statement_time)
            client=mariadb
            timeout_query="SET SESSION max_statement_time=$statement_timeout; $query"
            ;;
        mysql_max_execution_time)
            client=mysql
            timeout_milliseconds=$((10#$statement_timeout * 1000))
            timeout_query="SET SESSION max_execution_time=$timeout_milliseconds; $query"
            ;;
        *) return 1 ;;
    esac
    printf 'sudo %s --no-defaults --connect-timeout=%s --protocol=socket --user=root --batch --skip-column-names --database=%s --execute=%s\n' \
        "$client" "$connect_timeout" "$(dbtune_shell_quote "$database")" "$(dbtune_shell_quote "$timeout_query")"
}

dbtune_action_parse() {
    local line=${1-}
    local encoded

    encoded=${line//$'\t'/$'\034'}
    IFS=$'\034' read -r DBTUNE_ACTION_RULE_ID DBTUNE_ACTION_SCOPE DBTUNE_ACTION_KIND \
        DBTUNE_ACTION_SAFETY DBTUNE_ACTION_TARGET DBTUNE_ACTION_COMMAND DBTUNE_ACTION_DESTRUCTIVE \
        DBTUNE_ACTION_WARNING_ID DBTUNE_ACTION_CONNECT_TIMEOUT_SECONDS DBTUNE_ACTION_STATEMENT_TIMEOUT_SECONDS \
        DBTUNE_ACTION_TIMEOUT_CAPABILITY _dbtune_action_end <<<"${encoded}"$'\034_'
}

dbtune_actions_load() {
    local line id path webroot owner database prefix command target action safety warning_id
    local sql_action sql_capability action_capability action_connect_timeout action_statement_timeout
    local connect_timeout=5 statement_timeout=30

    DBTUNE_ACTION_LINES=()
    sql_capability=$(dbtune_action_sql_timeout_capability "${DBTUNE_AUDIT_FILE:-}" 2>/dev/null || printf unknown)
    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || return 65
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] || continue
        id=${DBTUNE_ANALYSIS_SCOPE#app:}
        path=$(dbtune_scoped_value "$DBTUNE_APPS_FILE" "$id" path 2>/dev/null || true)
        webroot=$(dbtune_scoped_value "$DBTUNE_APPS_FILE" "$id" webroot 2>/dev/null || true)
        owner=$(dbtune_scoped_value "$DBTUNE_APPS_FILE" "$id" owner 2>/dev/null || true)
        database=$(dbtune_scoped_value "$DBTUNE_APPS_FILE" "$id" database 2>/dev/null || true)
        prefix=$(dbtune_scoped_value "$DBTUNE_APPS_FILE" "$id" table_prefix 2>/dev/null || true)
        target="app=$id; path=${path:-unresolved}; webroot=${webroot:-unresolved}; owner=${owner:-unresolved}; database=${database:-unresolved}; prefix=${prefix:-unresolved}"
        command=''
        safety=read-only
        sql_action=0
        action_connect_timeout=not-applicable
        action_statement_timeout=not-applicable
        action_capability=not-applicable
        warning_id=action_warning_read_only
        if [[ $DBTUNE_ANALYSIS_VERDICT == UNKNOWN && $DBTUNE_ANALYSIS_EVIDENCE == *source_error=* ]]; then
            safety=not-executable
            warning_id=action_warning_source_error
            DBTUNE_ACTION_LINES+=("$DBTUNE_ANALYSIS_RULE_ID"$'\t'"$DBTUNE_ANALYSIS_SCOPE"$'\t'diagnostic$'\t'"$safety"$'\t'"$(dbtune_report_safe "$target")"$'\t\t'false$'\t'"$warning_id"$'\t'"$action_connect_timeout"$'\t'"$action_statement_timeout"$'\t'"$action_capability")
            continue
        fi
        case $DBTUNE_ANALYSIS_RULE_ID in
            R-APP-OBJECT-CACHE|R-APP-REDIS) action=redis ;;
            R-APP-WPCRON) action=cron ;;
            R-APP-MULTISITE) action=multisite ;;
            *) action='core-version' ;;
        esac
        case $DBTUNE_ANALYSIS_RULE_ID in
            R-APP-AUTOLOAD|R-APP-HPOS|R-APP-LOG-TABLE|R-APP-SESSIONS|R-APP-AS|R-APP-AS-RETENTION|R-APP-TRANSIENTS|R-APP-META-INDEX)
                sql_action=1
                action_connect_timeout=$connect_timeout
                action_statement_timeout=$statement_timeout
                action_capability=$sql_capability
                command=$(dbtune_action_sql_command "$database" "$prefix" "$DBTUNE_ANALYSIS_RULE_ID" \
                    "$sql_capability" "$connect_timeout" "$statement_timeout" 2>/dev/null || true)
                ;;
        esac
        if ((sql_action)) && [[ -z $command ]]; then
            safety=not-executable
            warning_id=action_warning_sql_unavailable
        elif [[ -z $command ]] && ! command=$(dbtune_action_wp_command "$webroot" "$owner" "$action" 2>/dev/null); then
            command=''
            safety=not-executable
            warning_id=action_warning_wp_unavailable
        fi
        DBTUNE_ACTION_LINES+=("$DBTUNE_ANALYSIS_RULE_ID"$'\t'"$DBTUNE_ANALYSIS_SCOPE"$'\t'diagnostic$'\t'"$safety"$'\t'"$(dbtune_report_safe "$target")"$'\t'"$(dbtune_report_safe "$command")"$'\t'false$'\t'"$warning_id"$'\t'"$action_connect_timeout"$'\t'"$action_statement_timeout"$'\t'"$action_capability")
    done
}

dbtune_autoload_load() {
    local scope key value name size

    DBTUNE_AUTOLOAD_LINES=()
    [[ -r $DBTUNE_DATABASES_FILE ]] || return 0
    while IFS=$'\t' read -r scope key value; do
        [[ $key == autoload.top.* ]] || continue
        name=${value%:*}
        size=${value##*:}
        if dbtune_is_sensitive_key "$name"; then
            name='[REDACTED]'
        else
            name=$(dbtune_report_safe "$name")
        fi
        [[ $size =~ ^[0-9]+$ ]] || size=unknown
        DBTUNE_AUTOLOAD_LINES+=("$scope"$'\t'"$name"$'\t'"$size")
    done <"$DBTUNE_DATABASES_FILE"
}

dbtune_render_metric() {
    local label=${1:-}
    local aliases=${2:-}
    local fallback=${3:-1}
    local unit=${4:-}
    local p50 p95 p99 maximum

    IFS=$'\t' read -r p50 p95 p99 maximum <<<"$(dbtune_samples_stats "$DBTUNE_SAMPLES_FILE" "$aliases" "$fallback")"
    printf '| %s | %s%s | %s%s | %s%s | %s%s |\n' "$label" "$p50" "$unit" "$p95" "$unit" "$p99" "$unit" "$maximum" "$unit"
}

dbtune_render_audit_fact() {
    local label=${1:-}
    shift
    local value

    value=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" "$@" 2>/dev/null || true)
    [[ -n $value ]] || return 0
    printf -- '- **%s:** %s\n' "$label" "$(dbtune_markdown_escape "$value")"
}

dbtune_render_executive_actions() {
    local severity line shown=0 pass

    for severity in critical high medium low info; do
        for pass in app server; do
            for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
                dbtune_analysis_parse "$line" || continue
                [[ $DBTUNE_ANALYSIS_SEVERITY == "$severity" ]] || continue
                if [[ $pass == app ]]; then
                    [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] || continue
                else
                    [[ $DBTUNE_ANALYSIS_SCOPE != app:* ]] || continue
                fi
                printf -- '- **%s / %s:** %s — %s\n' \
                    "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
                    "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SCOPE")" \
                    "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
                    "$(dbtune_markdown_escape "$(dbtune_msg "$DBTUNE_ANALYSIS_REASON_ID")")"
                shown=$((shown + 1))
                ((shown >= 5)) && return 0
            done
        done
    done
    ((shown)) || dbtune_printf report_no_findings
}

dbtune_render_application_overview() {
    local line found=0

    dbtune_printf report_application_heading
    dbtune_printf report_application_intro
    dbtune_printf report_application_table
    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] || continue
        found=1
        printf '| %s | %s | %s | %s |\n' \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
            "$(dbtune_markdown_escape "${DBTUNE_ANALYSIS_SCOPE#app:}")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
            "$(dbtune_markdown_escape "$(dbtune_msg "$DBTUNE_ANALYSIS_REASON_ID")")"
    done
    ((found)) || dbtune_printf report_application_none
    printf '\n'
}

dbtune_render_server_profile() {
    local line _score timestamp cpu bp miss readbps threads correlation rejected reasons

    dbtune_printf report_server_heading
    dbtune_render_audit_fact "$(dbtune_msg report_label_host)" audit.hostname hostname host.name server.hostname
    dbtune_render_audit_fact "$(dbtune_msg report_label_mariadb)" mariadb_version mariadb.version server.mariadb_version
    dbtune_render_audit_fact "$(dbtune_msg report_label_os)" os os_version server.os
    dbtune_render_audit_fact "$(dbtune_msg report_label_cpu_cores)" hw.cpu_count cpu_count cpu_cores cpu.cores
    dbtune_render_audit_fact "$(dbtune_msg report_label_ram_bytes)" hw.ram_bytes ram_total ram_mb memory_total_mb memory.total_mb
    dbtune_render_audit_fact "$(dbtune_msg report_label_disk)" hw.storage_class disk_type storage_type storage.class
    dbtune_render_audit_fact "$(dbtune_msg report_label_dataset_bytes)" mariadb.dataset_bytes dataset_size dataset_bytes dataset_mb dataset.total_mb
    dbtune_printf report_valid_samples "$(dbtune_samples_count "$DBTUNE_SAMPLES_FILE")"
    rejected=$(dbtune_samples_diagnostic_value "$DBTUNE_SAMPLES_FILE" rejected_rows)
    reasons=$(dbtune_samples_diagnostic_value "$DBTUNE_SAMPLES_FILE" rejected_reasons)
    dbtune_printf report_rejected_samples "$rejected" "$reasons"

    dbtune_printf report_percentiles_heading
    dbtune_printf report_metrics_table
    dbtune_render_metric "$(dbtune_msg report_metric_mariadb_cpu)" 'cpu_pct,mariadbd_cpu_pct,db_cpu_pct' 13 ' %'
    dbtune_render_metric "$(dbtune_msg report_metric_bp_hit)" 'bp_hit_pct,bp_hit_ratio,buffer_pool_hit_pct' 3 ' %'
    dbtune_render_metric "$(dbtune_msg report_metric_bp_misses)" 'bp_misses_s,bp_miss_s,bp_misses_per_s' 4 ''
    dbtune_render_metric "$(dbtune_msg report_metric_data_read)" 'data_read_s,data_read_bps,innodb_data_read_bps,data_read_per_s' 5 ' B/s'
    dbtune_render_metric "$(dbtune_msg report_metric_rnd_next)" 'rnd_next_s,handler_rnd_next_s,handler_read_rnd_next_s,handler_read_rnd_next_per_s' 6 ''
    dbtune_render_metric "$(dbtune_msg report_metric_threads_running)" 'threads_running,running_threads' 8 ''
    dbtune_render_metric "$(dbtune_msg report_metric_disk_temp)" 'tmp_disk_pct,tmp_disk_tables_pct' 7 ' %'
    dbtune_render_metric "$(dbtune_msg report_metric_available_ram)" 'mem_available_kb,memory_available_kb' 14 ' KB'
    dbtune_render_metric "$(dbtune_msg report_metric_swap)" 'swap_used_kb,swap_kb' 15 ' KB'
    dbtune_printf report_worst_heading
    dbtune_printf report_worst_table
    for line in "${DBTUNE_WORST_LINES[@]}"; do
        IFS=$'\t' read -r _score timestamp cpu bp miss readbps threads correlation <<<"$line"
        printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
            "$(dbtune_markdown_escape "$timestamp")" \
            "$(dbtune_markdown_escape "${cpu:-n/a}")" \
            "$(dbtune_markdown_escape "${bp:-n/a}")" \
            "$(dbtune_markdown_escape "${miss:-n/a}")" \
            "$(dbtune_markdown_escape "${readbps:-n/a}")" \
            "$(dbtune_markdown_escape "${threads:-n/a}")" \
            "$(dbtune_markdown_escape "$correlation")"
    done
    printf '\n'
}

dbtune_render_proposed_diff() {
    local line found=0

    dbtune_printf report_proposal_heading
    dbtune_printf report_proposal_table
    for line in "${DBTUNE_PROPOSAL_LINES[@]}"; do
        dbtune_proposal_parse "$line"
        found=1
        printf "| \`%s\` | \`%s\` | \`%s\` | %s | %s |\n" \
            "$(dbtune_markdown_escape "$DBTUNE_PROPOSAL_KEY")" \
            "$(dbtune_markdown_escape "$DBTUNE_PROPOSAL_CURRENT")" \
            "$(dbtune_markdown_escape "$DBTUNE_PROPOSAL_VALUE")" \
            "$(dbtune_markdown_escape "$DBTUNE_PROPOSAL_EVIDENCE")" \
            "$(dbtune_markdown_escape "$(dbtune_msg "$DBTUNE_PROPOSAL_REASON_ID")")"
    done
    ((found)) || dbtune_printf report_proposal_none
    printf '\n'
}

dbtune_render_per_app() {
    local outer_line inner_line action_line autoload_line scope rendered_scopes=$'\n' found=0 action_text autoload_found

    dbtune_printf report_per_app_heading
    for outer_line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$outer_line" || continue
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] || continue
        scope=$DBTUNE_ANALYSIS_SCOPE
        [[ $rendered_scopes != *$'\n'"$scope"$'\n'* ]] || continue
        rendered_scopes+="$scope"$'\n'
        found=1
        printf '### %s\n\n' "$(dbtune_markdown_escape "${scope#app:}")"
        dbtune_printf report_per_app_table
        for inner_line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
            dbtune_analysis_parse "$inner_line" || continue
            [[ $DBTUNE_ANALYSIS_SCOPE == "$scope" ]] || continue
            action_text=''
            for action_line in "${DBTUNE_ACTION_LINES[@]}"; do
                dbtune_action_parse "$action_line"
                [[ $DBTUNE_ACTION_RULE_ID == "$DBTUNE_ANALYSIS_RULE_ID" && $DBTUNE_ACTION_SCOPE == "$scope" ]] || continue
                action_text="type=$DBTUNE_ACTION_KIND; safety=$DBTUNE_ACTION_SAFETY; destructive=$DBTUNE_ACTION_DESTRUCTIVE; target=$DBTUNE_ACTION_TARGET; connect_timeout_seconds=$DBTUNE_ACTION_CONNECT_TIMEOUT_SECONDS; statement_timeout_seconds=$DBTUNE_ACTION_STATEMENT_TIMEOUT_SECONDS; timeout_capability=$DBTUNE_ACTION_TIMEOUT_CAPABILITY; command=\`$DBTUNE_ACTION_COMMAND\`; warning_id=$DBTUNE_ACTION_WARNING_ID; warning=$(dbtune_msg "$DBTUNE_ACTION_WARNING_ID")"
                break
            done
            printf '| %s | %s | %s | %s | %s |\n' \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_EVIDENCE")" \
                "$(dbtune_markdown_escape "$(dbtune_msg "$DBTUNE_ANALYSIS_REASON_ID")")" \
                "$(dbtune_markdown_escape "$action_text")"
        done
        dbtune_printf report_autoload_heading
        dbtune_printf report_autoload_table
        autoload_found=0
        for autoload_line in "${DBTUNE_AUTOLOAD_LINES[@]}"; do
            IFS=$'\t' read -r DBTUNE_AUTOLOAD_SCOPE DBTUNE_AUTOLOAD_NAME DBTUNE_AUTOLOAD_SIZE <<<"$autoload_line"
            [[ $DBTUNE_AUTOLOAD_SCOPE == "${scope#app:}" ]] || continue
            autoload_found=1
            printf '| %s | %s |\n' "$(dbtune_markdown_escape "$DBTUNE_AUTOLOAD_NAME")" "$(dbtune_markdown_escape "$DBTUNE_AUTOLOAD_SIZE")"
        done
        ((autoload_found)) || dbtune_printf report_autoload_unavailable
        printf '\n'
    done
    ((found)) || dbtune_printf report_per_app_none
    dbtune_render_tsv_inventory "$(dbtune_msg report_inventory_apps)" "$DBTUNE_APPS_FILE"
    dbtune_render_tsv_inventory "$(dbtune_msg report_inventory_databases)" "$DBTUNE_DATABASES_FILE"
}

dbtune_render_security() {
    local line found=0

    dbtune_printf report_security_heading
    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        dbtune_security_rule || continue
        found=1
        printf -- '- **%s:** %s. %s\n' \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
            "$(dbtune_markdown_escape "$(dbtune_msg "$DBTUNE_ANALYSIS_REASON_ID")")"
    done
    ((found)) || dbtune_printf report_security_none
    printf '\n'
}

dbtune_render_markdown() {
    local generated_at=${1:-}
    local critical high medium low
    local audit_status required_sections failed_sections partial_sections affected_domains
    local mariadb_missing mariadb_invalid mariadb_conflicting mariadb_optional

    critical=$(dbtune_analysis_count all critical)
    high=$(dbtune_analysis_count all high)
    medium=$(dbtune_analysis_count all medium)
    low=$(dbtune_analysis_count all low)
    audit_status=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.overall_status 2>/dev/null || printf ERROR)
    required_sections=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.required_sections 2>/dev/null || printf unknown)
    failed_sections=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.failed_sections 2>/dev/null || printf unknown)
    partial_sections=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.partial_sections 2>/dev/null || printf unknown)
    affected_domains=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.affected_domains 2>/dev/null || printf unknown)
    mariadb_missing=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.section.mariadb.missing_evidence 2>/dev/null || printf unknown)
    mariadb_invalid=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.section.mariadb.invalid_evidence 2>/dev/null || printf unknown)
    mariadb_conflicting=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.section.mariadb.conflicting_evidence 2>/dev/null || printf unknown)
    mariadb_optional=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" audit.section.mariadb.optional_evidence 2>/dev/null || printf unknown)

    dbtune_printf report_title
    dbtune_printf report_generated "$(dbtune_markdown_escape "$generated_at")" "$(dbtune_markdown_escape "$DBTUNE_ARTIFACT_VERSION")"
    dbtune_printf report_provenance \
        "$(dbtune_markdown_escape "$DBTUNE_RUN_ID")" \
        "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_FINGERPRINT")" \
        "$(dbtune_markdown_escape "$DBTUNE_AUDIT_HASH")" \
        "$(dbtune_markdown_escape "$DBTUNE_SAMPLES_HASH")" \
        "$(dbtune_markdown_escape "$DBTUNE_DBSIZE_HASH")"
    if [[ $DBTUNE_SERVER_SUPPORT == unsupported ]]; then
        dbtune_printf report_unsupported
    fi
    dbtune_printf report_summary_heading
    dbtune_printf report_audit_status "$(dbtune_markdown_escape "$audit_status")"
    dbtune_printf report_required_sections "$(dbtune_markdown_escape "$required_sections")"
    dbtune_printf report_failed_sections "$(dbtune_markdown_escape "$failed_sections")"
    dbtune_printf report_partial_sections "$(dbtune_markdown_escape "$partial_sections")"
    dbtune_printf report_affected_domains "$(dbtune_markdown_escape "$affected_domains")"
    dbtune_printf report_mariadb_missing "$(dbtune_markdown_escape "$mariadb_missing")"
    dbtune_printf report_mariadb_invalid "$(dbtune_markdown_escape "$mariadb_invalid")"
    dbtune_printf report_mariadb_conflicting "$(dbtune_markdown_escape "$mariadb_conflicting")"
    dbtune_printf report_mariadb_optional "$(dbtune_markdown_escape "$mariadb_optional")"
    dbtune_printf report_findings "$critical" "$high" "$medium" "$low"
    dbtune_render_executive_actions
    printf '\n'
    dbtune_render_application_overview
    dbtune_render_server_profile
    dbtune_render_proposed_diff
    dbtune_printf report_safety_warning
    dbtune_render_per_app
    dbtune_render_security
    dbtune_printf report_next_steps_heading
    dbtune_printf report_next_step_apps
    if [[ $DBTUNE_SERVER_SUPPORT == unsupported ]]; then
        dbtune_printf report_next_step_unsupported
    else
        dbtune_printf report_next_step_propose
        dbtune_printf report_next_step_restart
        dbtune_printf report_next_step_verify
    fi
}

dbtune_json_add_audit_value() {
    local json_key=${1:-}
    shift
    local value

    value=$(dbtune_audit_value "$DBTUNE_AUDIT_FILE" "$@" 2>/dev/null || true)
    DBTUNE_JSON_FIELDS+=("$json_key" "$(dbtune_report_safe "$value")")
}

dbtune_json_add_metric() {
    local key=${1:-}
    local aliases=${2:-}
    local fallback=${3:-1}
    local p50 p95 p99 maximum

    IFS=$'\t' read -r p50 p95 p99 maximum <<<"$(dbtune_samples_stats "$DBTUNE_SAMPLES_FILE" "$aliases" "$fallback")"
    DBTUNE_JSON_FIELDS+=("metrics.$key.p50" "$p50" "metrics.$key.p95" "$p95" "metrics.$key.p99" "$p99" "metrics.$key.max" "$maximum")
}

dbtune_render_json() {
    local generated_at=${1:-}
    local line index=0 security_count=0 app_rule_count=0
    local rule_prefix proposal_prefix action_prefix worst_prefix autoload_prefix
    local score timestamp cpu bp miss readbps threads correlation field_index

    DBTUNE_JSON_FIELDS=(
        schema_version fleet-v3
        report.language "$DBTUNE_I18N_LANGUAGE"
        generated_at "$generated_at"
        dbtune_version "$DBTUNE_ARTIFACT_VERSION"
        run_id "$DBTUNE_RUN_ID"
        audit_hash "$DBTUNE_AUDIT_HASH"
        samples_hash "$DBTUNE_SAMPLES_HASH"
        dbsize_input "$DBTUNE_DBSIZE_INPUT"
        dbsize_hash "$DBTUNE_DBSIZE_HASH"
        dbsize_selected_hash "$DBTUNE_DBSIZE_SELECTED_HASH"
        dbsize_selected_rows "$DBTUNE_DBSIZE_SELECTED_ROWS"
        analysis_fingerprint "$DBTUNE_ANALYSIS_FINGERPRINT"
        server.support_status "$DBTUNE_SERVER_SUPPORT"
        findings.critical "$(dbtune_analysis_count all critical)"
        findings.high "$(dbtune_analysis_count all high)"
        findings.medium "$(dbtune_analysis_count all medium)"
        findings.low "$(dbtune_analysis_count all low)"
        samples.count "$(dbtune_samples_count "$DBTUNE_SAMPLES_FILE")"
        samples.rejected "$(dbtune_samples_diagnostic_value "$DBTUNE_SAMPLES_FILE" rejected_rows)"
        samples.rejected_reasons "$(dbtune_samples_diagnostic_value "$DBTUNE_SAMPLES_FILE" rejected_reasons)"
        apps.count "$(dbtune_tsv_row_count "$DBTUNE_APPS_FILE" app)"
        databases.count "$(dbtune_tsv_row_count "$DBTUNE_DATABASES_FILE" database)"
    )
    dbtune_json_add_audit_value audit.overall_status audit.overall_status
    dbtune_json_add_audit_value audit.exit_status audit.exit_status
    dbtune_json_add_audit_value audit.required_sections audit.required_sections
    dbtune_json_add_audit_value audit.failed_sections audit.failed_sections
    dbtune_json_add_audit_value audit.partial_sections audit.partial_sections
    dbtune_json_add_audit_value audit.affected_domains audit.affected_domains
    dbtune_json_add_audit_value audit.section.mariadb.status audit.section.mariadb.status
    dbtune_json_add_audit_value audit.section.mariadb.evidence_schema_version audit.section.mariadb.evidence_schema_version
    dbtune_json_add_audit_value audit.section.mariadb.missing_evidence audit.section.mariadb.missing_evidence
    dbtune_json_add_audit_value audit.section.mariadb.invalid_evidence audit.section.mariadb.invalid_evidence
    dbtune_json_add_audit_value audit.section.mariadb.conflicting_evidence audit.section.mariadb.conflicting_evidence
    dbtune_json_add_audit_value audit.section.mariadb.optional_evidence audit.section.mariadb.optional_evidence
    dbtune_json_add_audit_value audit.section.hardware.status audit.section.hardware.status
    dbtune_json_add_audit_value audit.section.applications.status audit.section.applications.status
    dbtune_json_add_audit_value audit.section.security.status audit.section.security.status
    dbtune_json_add_audit_value server.hostname audit.hostname hostname host.name server.hostname
    dbtune_json_add_audit_value server.mariadb_version mariadb_version mariadb.version server.mariadb_version
    dbtune_json_add_audit_value server.os os os_version server.os
    dbtune_json_add_audit_value server.cpu_cores hw.cpu_count cpu_count cpu_cores cpu.cores
    dbtune_json_add_audit_value server.ram_bytes hw.ram_bytes ram_total ram_mb memory_total_mb memory.total_mb
    dbtune_json_add_audit_value server.storage_class hw.storage_class disk_type storage_type storage.class
    dbtune_json_add_audit_value server.dataset_bytes mariadb.dataset_bytes dataset_size dataset_bytes dataset_mb dataset.total_mb
    dbtune_json_add_metric cpu_pct 'cpu_pct,mariadbd_cpu_pct,db_cpu_pct' 13
    dbtune_json_add_metric bp_hit_pct 'bp_hit_pct,bp_hit_ratio,buffer_pool_hit_pct' 3
    dbtune_json_add_metric bp_misses_s 'bp_misses_s,bp_miss_s,bp_misses_per_s' 4
    dbtune_json_add_metric data_read_bps 'data_read_s,data_read_bps,innodb_data_read_bps,data_read_per_s' 5
    dbtune_json_add_metric threads_running 'threads_running,running_threads' 8

    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        printf -v rule_prefix 'rule.%03d' "$index"
        DBTUNE_JSON_FIELDS+=(
            "$rule_prefix.id" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_RULE_ID")"
            "$rule_prefix.scope" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_SCOPE")"
            "$rule_prefix.severity" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_SEVERITY")"
            "$rule_prefix.verdict" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_VERDICT")"
            "$rule_prefix.proposed_key" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_PROPOSED_KEY")"
            "$rule_prefix.proposed_value" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_PROPOSED_VALUE")"
            "$rule_prefix.evidence" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_EVIDENCE")"
            "$rule_prefix.reason_id" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_REASON_ID")"
            "$rule_prefix.reason" "$(dbtune_report_safe "$(dbtune_msg "$DBTUNE_ANALYSIS_REASON_ID")")"
        )
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] && app_rule_count=$((app_rule_count + 1))
        dbtune_security_rule && security_count=$((security_count + 1))
        index=$((index + 1))
    done
    DBTUNE_JSON_FIELDS+=(rules.count "$index" app_rules.count "$app_rule_count" security_findings.count "$security_count")
    index=0
    for line in "${DBTUNE_PROPOSAL_LINES[@]}"; do
        dbtune_proposal_parse "$line"
        printf -v proposal_prefix 'proposal.%03d' "$index"
        DBTUNE_JSON_FIELDS+=(
            "$proposal_prefix.rule_id" "$(dbtune_report_safe "$DBTUNE_PROPOSAL_RULE_ID")"
            "$proposal_prefix.key" "$(dbtune_report_safe "$DBTUNE_PROPOSAL_KEY")"
            "$proposal_prefix.current" "$(dbtune_report_safe "$DBTUNE_PROPOSAL_CURRENT")"
            "$proposal_prefix.value" "$(dbtune_report_safe "$DBTUNE_PROPOSAL_VALUE")"
            "$proposal_prefix.evidence" "$(dbtune_report_safe "$DBTUNE_PROPOSAL_EVIDENCE")"
            "$proposal_prefix.reason_id" "$(dbtune_report_safe "$DBTUNE_PROPOSAL_REASON_ID")"
            "$proposal_prefix.reason" "$(dbtune_report_safe "$(dbtune_msg "$DBTUNE_PROPOSAL_REASON_ID")")"
        )
        index=$((index + 1))
    done
    DBTUNE_JSON_FIELDS+=(proposals.count "$index" proposals.hash "$(dbtune_proposal_records_hash)")
    index=0
    for line in "${DBTUNE_ACTION_LINES[@]}"; do
        dbtune_action_parse "$line"
        printf -v action_prefix 'action.%03d' "$index"
        DBTUNE_JSON_FIELDS+=(
            "$action_prefix.rule_id" "$DBTUNE_ACTION_RULE_ID"
            "$action_prefix.scope" "$DBTUNE_ACTION_SCOPE"
            "$action_prefix.type" "$DBTUNE_ACTION_KIND"
            "$action_prefix.safety" "$DBTUNE_ACTION_SAFETY"
            "$action_prefix.target" "$DBTUNE_ACTION_TARGET"
            "$action_prefix.command" "$DBTUNE_ACTION_COMMAND"
            "$action_prefix.destructive" "$DBTUNE_ACTION_DESTRUCTIVE"
            "$action_prefix.warning_id" "$DBTUNE_ACTION_WARNING_ID"
            "$action_prefix.warning" "$(dbtune_msg "$DBTUNE_ACTION_WARNING_ID")"
            "$action_prefix.connect_timeout_seconds" "$DBTUNE_ACTION_CONNECT_TIMEOUT_SECONDS"
            "$action_prefix.statement_timeout_seconds" "$DBTUNE_ACTION_STATEMENT_TIMEOUT_SECONDS"
            "$action_prefix.timeout_capability" "$DBTUNE_ACTION_TIMEOUT_CAPABILITY"
        )
        index=$((index + 1))
    done
    DBTUNE_JSON_FIELDS+=(actions.count "$index")
    index=0
    for line in "${DBTUNE_WORST_LINES[@]}"; do
        IFS=$'\t' read -r score timestamp cpu bp miss readbps threads correlation <<<"$line"
        printf -v worst_prefix 'worst_window.%03d' "$index"
        DBTUNE_JSON_FIELDS+=(
            "$worst_prefix.timestamp" "$timestamp"
            "$worst_prefix.cpu_pct" "$cpu"
            "$worst_prefix.bp_hit_pct" "$bp"
            "$worst_prefix.bp_misses_s" "$miss"
            "$worst_prefix.data_read_bps" "$readbps"
            "$worst_prefix.threads_running" "$threads"
            "$worst_prefix.backup_correlation" "$correlation"
        )
        index=$((index + 1))
    done
    DBTUNE_JSON_FIELDS+=(worst_windows.count "$index")
    index=0
    for line in "${DBTUNE_AUTOLOAD_LINES[@]}"; do
        IFS=$'\t' read -r DBTUNE_AUTOLOAD_SCOPE DBTUNE_AUTOLOAD_NAME DBTUNE_AUTOLOAD_SIZE <<<"$line"
        printf -v autoload_prefix 'autoload.%03d' "$index"
        DBTUNE_JSON_FIELDS+=(
            "$autoload_prefix.scope" "$DBTUNE_AUTOLOAD_SCOPE"
            "$autoload_prefix.name" "$DBTUNE_AUTOLOAD_NAME"
            "$autoload_prefix.bytes" "$DBTUNE_AUTOLOAD_SIZE"
        )
        index=$((index + 1))
    done
    DBTUNE_JSON_FIELDS+=(autoload.count "$index" actions.warning_id actions_warning_summary actions.warning "$(dbtune_msg actions_warning_summary)")
    for ((field_index = 1; field_index < ${#DBTUNE_JSON_FIELDS[@]}; field_index += 2)); do
        DBTUNE_JSON_FIELDS[field_index]=$(dbtune_report_safe "${DBTUNE_JSON_FIELDS[$field_index]}")
    done
    dbtune_json_emit "${DBTUNE_JSON_FIELDS[@]}"
}

dbtune_cnf_comment() {
    dbtune_report_safe "${1:-}"
}

dbtune_proposal_parse() {
    local line=${1-}
    local encoded

    encoded=${line//$'\t'/$'\034'}
    IFS=$'\034' read -r \
        DBTUNE_PROPOSAL_RULE_ID \
        _dbtune_proposal_scope \
        DBTUNE_PROPOSAL_SEVERITY \
        _dbtune_proposal_verdict \
        DBTUNE_PROPOSAL_KEY \
        DBTUNE_PROPOSAL_VALUE \
        DBTUNE_PROPOSAL_EVIDENCE \
        DBTUNE_PROPOSAL_REASON_ID \
        DBTUNE_PROPOSAL_CURRENT \
        _dbtune_proposal_end <<<"${encoded}"$'\034_'
}

dbtune_proposal_current_validator() {
    local proposed_key=${1:-}
    local schema_key validator _requirement role
    local target="mariadb.variable.$proposed_key"

    while IFS=$'\t' read -r schema_key validator _requirement role; do
        if [[ $schema_key == "$target" && $role == proposal ]]; then
            printf '%s\n' "$validator"
            return 0
        fi
    done < <(dbtune_audit_mariadb_evidence_schema)
    return 1
}

dbtune_proposals_load() {
    local audit_file=${1:-}
    local line canonical current index validator
    local -A seen=()

    [[ -r $audit_file ]] || return 66
    DBTUNE_PROPOSAL_LINES=()
    if [[ ${DBTUNE_SERVER_SUPPORT:-supported} == unsupported ]]; then
        for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
            dbtune_analysis_parse "$line" || return 65
            if ! dbtune_analysis_verdict_can_propose "$DBTUNE_ANALYSIS_VERDICT" &&
                [[ -n $DBTUNE_ANALYSIS_PROPOSED_KEY || -n $DBTUNE_ANALYSIS_PROPOSED_VALUE ]]; then
                dbtune_log error "$(dbtune_printf proposal_verdict_fields "$DBTUNE_ANALYSIS_RULE_ID" "$DBTUNE_ANALYSIS_VERDICT")"
                return 65
            fi
            if [[ -n $DBTUNE_ANALYSIS_PROPOSED_KEY || -n $DBTUNE_ANALYSIS_PROPOSED_VALUE ]]; then
                dbtune_log error "$(dbtune_msg proposal_unsupported_analysis)"
                return 65
            fi
        done
        return 0
    fi
    for index in "${!DBTUNE_ANALYSIS_LINES[@]}"; do
        line=${DBTUNE_ANALYSIS_LINES[$index]}
        dbtune_analysis_parse "$line" || return 65
        if ! dbtune_analysis_verdict_can_propose "$DBTUNE_ANALYSIS_VERDICT" &&
            [[ -n $DBTUNE_ANALYSIS_PROPOSED_KEY || -n $DBTUNE_ANALYSIS_PROPOSED_VALUE ]]; then
            dbtune_log error "$(dbtune_printf proposal_verdict_fields "$DBTUNE_ANALYSIS_RULE_ID" "$DBTUNE_ANALYSIS_VERDICT")"
            return 65
        fi
        if [[ -z $DBTUNE_ANALYSIS_PROPOSED_KEY && -z $DBTUNE_ANALYSIS_PROPOSED_VALUE ]]; then
            continue
        fi
        if [[ $DBTUNE_ANALYSIS_SCOPE != server || -z $DBTUNE_ANALYSIS_PROPOSED_KEY || -z $DBTUNE_ANALYSIS_PROPOSED_VALUE ]]; then
            dbtune_log error "$(dbtune_printf proposal_invalid_record "$DBTUNE_ANALYSIS_RULE_ID")"
            return 65
        fi
        if ! dbtune_proposal_key_is_safe "$DBTUNE_ANALYSIS_PROPOSED_KEY" ||
            ! dbtune_proposal_value_is_safe "$DBTUNE_ANALYSIS_PROPOSED_VALUE"; then
            dbtune_log error "$(dbtune_printf proposal_unsafe_record "$DBTUNE_ANALYSIS_RULE_ID")"
            return 65
        fi
        canonical=$(dbtune_key_normalize "$DBTUNE_ANALYSIS_PROPOSED_KEY")
        if [[ -n ${seen[$canonical]+x} ]]; then
            dbtune_log error "$(dbtune_printf proposal_duplicate_key "$DBTUNE_ANALYSIS_PROPOSED_KEY")"
            return 65
        fi
        current=$(dbtune_audit_current_value "$audit_file" "$canonical" 2>/dev/null || true)
        if [[ -z $current || ${current,,} == unknown || ${current,,} == unresolved ]]; then
            dbtune_log error "$(dbtune_printf proposal_current_unknown "$canonical")"
            return 65
        fi
        validator=$(dbtune_proposal_current_validator "$canonical" 2>/dev/null || true)
        if [[ -z $validator ]] || ! dbtune_audit_mariadb_evidence_valid "$validator" "$current"; then
            dbtune_log error "$(dbtune_printf proposal_current_invalid "$canonical")"
            return 65
        fi
        if [[ $validator == bool ]]; then
            case ${current^^} in
                ON|1) current=1 ;;
                OFF|0) current=0 ;;
            esac
        fi
        seen["$canonical"]=1
        line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
            "$DBTUNE_ANALYSIS_RULE_ID" "$DBTUNE_ANALYSIS_SCOPE" "$DBTUNE_ANALYSIS_SEVERITY" \
            "$DBTUNE_ANALYSIS_VERDICT" "$canonical" "$DBTUNE_ANALYSIS_PROPOSED_VALUE" \
            "$DBTUNE_ANALYSIS_EVIDENCE" "$DBTUNE_ANALYSIS_REASON_ID")
        DBTUNE_ANALYSIS_LINES[index]=$line
        DBTUNE_PROPOSAL_LINES+=("$line"$'\t'"$current")
    done
}

dbtune_proposal_stream() {
    local line

    for line in "${DBTUNE_PROPOSAL_LINES[@]}"; do
        printf '%s\n' "$line"
    done
}

dbtune_proposal_records_hash() {
    dbtune_proposal_stream | dbtune_sha256_stream
}

dbtune_proposal_template() {
    if declare -F dbtune_embedded_get >/dev/null 2>&1; then
        dbtune_embedded_get templates/tuning.cnf.tmpl
    else
        printf '%s\n' '@HEADER@' '[mysqld]' '@RULES@'
    fi
}

dbtune_render_proposal_header() {
    local generated_at=${1:-}

    printf '%s\n' '# proposed-99-zz-tuning.cnf'
    dbtune_printf cnf_generated "$DBTUNE_ARTIFACT_VERSION" "$generated_at"
    dbtune_printf cnf_load_order
    dbtune_printf cnf_rollback
    printf '%s\n' '#'
    dbtune_printf cnf_baseline_intro
    printf '%s\n' \
        '# innodb_flush_log_at_trx_commit = 1' \
        '# innodb_doublewrite = 1' \
        '# innodb_flush_method = O_DIRECT' \
        '# innodb_buffer_pool_dump_at_shutdown = 1' \
        '# innodb_buffer_pool_load_at_startup = 1' \
        '# innodb_flush_neighbors = 0' \
        '# innodb_max_dirty_pages_pct = 60' \
        '# innodb_max_dirty_pages_pct_lwm = 10' \
        '# innodb_lock_wait_timeout = 30' \
        '# thread_cache_size = 64' \
        '# tmp_table_size = 64M' \
        '# max_heap_table_size = 64M' \
        '# table_definition_cache = 2000' \
        '# slow_query_log = 1' \
        '# slow_query_log_file = /var/log/mysql/slow.log' \
        '# long_query_time = 2' \
        '# log_slow_verbosity = query_plan' \
        ''
}

dbtune_render_proposal_rules() {
    local line

    for line in "${DBTUNE_PROPOSAL_LINES[@]}"; do
        dbtune_proposal_parse "$line"
        printf '# %s [%s]: %s\n' \
            "$(dbtune_cnf_comment "$DBTUNE_PROPOSAL_RULE_ID")" \
            "$(dbtune_cnf_comment "$DBTUNE_PROPOSAL_SEVERITY")" \
            "$(dbtune_cnf_comment "$(dbtune_msg "$DBTUNE_PROPOSAL_REASON_ID")")"
        [[ -z $DBTUNE_PROPOSAL_EVIDENCE ]] || printf '# %s: %s\n' "$(dbtune_msg cnf_evidence)" "$(dbtune_cnf_comment "$DBTUNE_PROPOSAL_EVIDENCE")"
        printf '%s = %s\n\n' "$DBTUNE_PROPOSAL_KEY" "$DBTUNE_PROPOSAL_VALUE"
    done
}

dbtune_render_proposal() {
    local generated_at=${1:-}
    local line

    while IFS= read -r line || [[ -n $line ]]; do
        case $line in
            '@HEADER@') dbtune_render_proposal_header "$generated_at" ;;
            '@RULES@') dbtune_render_proposal_rules ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < <(dbtune_proposal_template)
}

# Called without arguments by both the CLI dispatcher and collector.
# shellcheck disable=SC2120
cmd_report() {
    local generated_at markdown json report_file json_file analysis_manifest

    dbtune_report_no_arguments report "$@" || return
    dbtune_init_state_dir || return
    DBTUNE_AUDIT_FILE=$(dbtune_path audit.tsv) || return
    DBTUNE_APPS_FILE=$(dbtune_path apps.tsv) || return
    DBTUNE_DATABASES_FILE=$(dbtune_path databases.tsv) || return
    DBTUNE_SAMPLES_FILE=$(dbtune_path samples.tsv) || return
    DBTUNE_ANALYSIS_FILE=$(dbtune_path analysis.tsv) || return
    dbtune_analysis_validate_schema "$DBTUNE_ANALYSIS_FILE" || return
    dbtune_provenance_validate_analysis || return
    dbtune_audit_validate "$DBTUNE_AUDIT_FILE" || return 65
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    DBTUNE_RUN_ID=$(dbtune_manifest_value "$analysis_manifest" run_id) || return 65
    DBTUNE_AUDIT_HASH=$(dbtune_manifest_value "$analysis_manifest" audit_hash) || return 65
    DBTUNE_SAMPLES_HASH=$(dbtune_manifest_value "$analysis_manifest" samples_hash) || return 65
    DBTUNE_DBSIZE_INPUT=$(dbtune_manifest_value "$analysis_manifest" dbsize_input) || return 65
    DBTUNE_DBSIZE_HASH=$(dbtune_manifest_value "$analysis_manifest" dbsize_hash) || return 65
    DBTUNE_DBSIZE_SELECTED_HASH=$(dbtune_manifest_value "$analysis_manifest" dbsize_selected_hash) || return 65
    DBTUNE_DBSIZE_SELECTED_ROWS=$(dbtune_manifest_value "$analysis_manifest" dbsize_selected_rows) || return 65
    DBTUNE_ANALYSIS_FINGERPRINT=$(dbtune_manifest_value "$analysis_manifest" analysis_fingerprint) || return 65
    for report_file in "$DBTUNE_AUDIT_FILE" "$DBTUNE_SAMPLES_FILE" "$DBTUNE_ANALYSIS_FILE"; do
        if [[ ! -r $report_file ]]; then
            dbtune_log error "$(dbtune_printf report_required_input_missing "$report_file")"
            return 66
        fi
    done

    dbtune_analysis_load "$DBTUNE_ANALYSIS_FILE" || return
    DBTUNE_SERVER_SUPPORT=$(dbtune_analysis_server_support) || return
    dbtune_proposals_load "$DBTUNE_AUDIT_FILE" || return
    dbtune_actions_load || return
    dbtune_autoload_load || return
    dbtune_worst_load || return
    generated_at=$(dbtune_now)
    markdown=$(dbtune_render_markdown "$generated_at") || return
    json=$(dbtune_render_json "$generated_at") || return
    report_file=$(dbtune_report_markdown_file) || return
    json_file=$(dbtune_report_json_file) || return
    printf '%s\n' "$markdown" | dbtune_atomic_write "$report_file" 600 || return
    printf '%s\n' "$json" | dbtune_atomic_write "$json_file" 600 || return

    command cat "$report_file"
    dbtune_printf report_saved "$(dbtune_report_safe "$report_file")" "$(dbtune_report_safe "$json_file")"
}

cmd_propose() {
    local analysis_file proposal_file generated_at proposal state manifest_file analysis_manifest
    local temporary temporary_manifest run_id audit_hash samples_hash analysis_hash analysis_fingerprint proposal_hash proposal_records_hash

    dbtune_report_no_arguments propose "$@" || return
    state=$(dbtune_state_read) || return
    if [[ $state != analyzed && $state != proposed ]]; then
        dbtune_log error "$(dbtune_printf core_command_state_disallowed propose "$state")"
        return 65
    fi
    dbtune_init_state_dir || return
    analysis_file=$(dbtune_path analysis.tsv) || return
    dbtune_analysis_validate_schema "$analysis_file" || return
    dbtune_provenance_validate_analysis || return
    DBTUNE_AUDIT_FILE=$(dbtune_path audit.tsv) || return
    dbtune_audit_validate "$DBTUNE_AUDIT_FILE" || return 65
    if [[ ! -r $analysis_file ]]; then
        dbtune_log error "$(dbtune_printf report_required_input_missing "$analysis_file")"
        return 66
    fi
    dbtune_analysis_load "$analysis_file" || return
    DBTUNE_SERVER_SUPPORT=$(dbtune_analysis_server_support) || return
    if [[ $DBTUNE_SERVER_SUPPORT == unsupported ]]; then
        dbtune_log error "$(dbtune_msg proposal_unsupported_family)"
        return 65
    fi
    dbtune_proposals_load "$DBTUNE_AUDIT_FILE" || return
    generated_at=$(dbtune_now)
    proposal=$(dbtune_render_proposal "$generated_at") || return
    proposal_file=$(dbtune_proposal_file) || return
    temporary=$(mktemp "$DBTUNE_STATE_DIR/.proposal.tmp.XXXXXX") || return 1
    temporary_manifest=$(mktemp "$DBTUNE_STATE_DIR/.proposal-manifest.tmp.XXXXXX") || {
        rm -f "$temporary"
        return 1
    }
    printf '%s\n' "$proposal" >"$temporary" || {
        rm -f "$temporary" "$temporary_manifest"
        return 1
    }
    chmod 600 "$temporary" "$temporary_manifest" || {
        rm -f "$temporary" "$temporary_manifest"
        return 1
    }
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    run_id=$(dbtune_manifest_value "$analysis_manifest" run_id) || return 65
    audit_hash=$(dbtune_manifest_value "$analysis_manifest" audit_hash) || return 65
    samples_hash=$(dbtune_manifest_value "$analysis_manifest" samples_hash) || return 65
    analysis_hash=$(dbtune_manifest_value "$analysis_manifest" analysis_hash) || return 65
    analysis_fingerprint=$(dbtune_manifest_value "$analysis_manifest" analysis_fingerprint) || return 65
    proposal_hash=$(dbtune_sha256_file "$temporary") || return
    proposal_records_hash=$(dbtune_proposal_records_hash) || return
    manifest_file=$(dbtune_path proposal-manifest.tsv) || return
    {
        printf 'schema\t1\n'
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'samples_hash\t%s\n' "$samples_hash"
        printf 'analysis_hash\t%s\n' "$analysis_hash"
        printf 'analysis_fingerprint\t%s\n' "$analysis_fingerprint"
        printf 'proposal_count\t%s\n' "${#DBTUNE_PROPOSAL_LINES[@]}"
        printf 'proposal_records_hash\t%s\n' "$proposal_records_hash"
        printf 'proposal_hash\t%s\n' "$proposal_hash"
    } >"$temporary_manifest"
    if ! dbtune_atomic_write "$proposal_file" 600 <"$temporary" ||
        ! dbtune_atomic_write "$manifest_file" 600 <"$temporary_manifest"; then
        rm -f "$temporary" "$temporary_manifest" "$proposal_file" "$manifest_file"
        return 1
    fi
    rm -f "$temporary" "$temporary_manifest"
    if [[ $state == analyzed ]]; then
        dbtune_state_transition proposed || return
    fi
    dbtune_event proposal_completed run_id "$run_id" audit_hash "$audit_hash" \
        samples_hash "$samples_hash" analysis_hash "$analysis_hash" proposal_hash "$proposal_hash" || true
    dbtune_printf proposal_saved "$(dbtune_report_safe "$proposal_file")"
}
