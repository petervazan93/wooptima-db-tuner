# shellcheck shell=bash

dbtune_audit_clean() {
    local value=${1-}

    value=${value//$'\t'/ }
    value=${value//$'\r'/ }
    value=${value//$'\n'/ }
    printf '%s' "$value"
}

dbtune_audit_put() {
    local file=${1:-}
    local key=${2:-}
    local value=${3-}

    [[ -n $file && $key =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 64
    printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")" >>"$file"
}

dbtune_audit_scope_put() {
    local file=${1:-}
    local scope=${2:-}
    local key=${3:-}
    local value=${4-}

    [[ -n $file && -n $scope && $scope != *$'\t'* && $scope != *$'\n'* ]] || return 64
    [[ $key =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 64
    printf '%s\t%s\t%s\n' "$(dbtune_audit_clean "$scope")" "$key" "$(dbtune_audit_clean "$value")" >>"$file"
}

dbtune_audit_slug() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '_'
}

dbtune_version_at_least() {
    local actual=${1:-0}
    local required=${2:-0}
    local actual_major=0 actual_minor=0 required_major=0 required_minor=0

    actual=${actual%%-*}
    required=${required%%-*}
    IFS=. read -r actual_major actual_minor _ <<<"$actual"
    IFS=. read -r required_major required_minor _ <<<"$required"
    [[ $actual_major =~ ^[0-9]+$ ]] || actual_major=0
    [[ $actual_minor =~ ^[0-9]+$ ]] || actual_minor=0
    [[ $required_major =~ ^[0-9]+$ ]] || required_major=0
    [[ $required_minor =~ ^[0-9]+$ ]] || required_minor=0
    ((actual_major > required_major || (actual_major == required_major && actual_minor >= required_minor)))
}

dbtune_sql_quote_literal() {
    local value=${1-}

    [[ $value != *$'\n'* && $value != *$'\r'* ]] || return 64
    value=${value//\\/\\\\}
    value=${value//\'/\'\'}
    printf "'%s'" "$value"
}

dbtune_sql_quote_identifier() {
    local value=${1-}

    [[ -n $value && ${#value} -le 64 ]] || return 64
    [[ $value != *$'\n'* && $value != *$'\r'* && $value != *$'\t'* ]] || return 64
    value=${value//\`/\`\`}
    printf "\`%s\`" "$value"
}

dbtune_wp_config_value() {
    local expression=${1:-}
    local value variable

    expression=${expression%%;*}
    expression=${expression#"${expression%%[![:space:]]*}"}
    expression=${expression%"${expression##*[![:space:]]}"}
    if [[ $expression =~ ^\'([^\']*)\' ]] || [[ $expression =~ ^\"([^\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ $expression =~ ^(true|TRUE)$ ]]; then
        printf 'true'
        return 0
    fi
    if [[ $expression =~ ^(false|FALSE)$ ]]; then
        printf 'false'
        return 0
    fi
    if [[ $expression =~ ^getenv[[:space:]]*\([[:space:]]*[\'\"]([A-Za-z_][A-Za-z0-9_]*)[\'\"] ]]; then
        variable=${BASH_REMATCH[1]}
        value=${!variable-}
        [[ -n $value ]] || return 1
        printf '%s' "$value"
        return 0
    fi
    if [[ $expression =~ ^\$_ENV\[[[:space:]]*[\'\"]([A-Za-z_][A-Za-z0-9_]*)[\'\"][[:space:]]*\] ]]; then
        variable=${BASH_REMATCH[1]}
        value=${!variable-}
        [[ -n $value ]] || return 1
        printf '%s' "$value"
        return 0
    fi
    return 1
}

dbtune_wp_config_parse() {
    local file=${1:-}
    local statement='' line key expression value

    [[ -r $file ]] || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line//$'\r'/}
        [[ $line =~ ^[[:space:]]*(//|#) ]] && continue
        statement+=" $line"
        [[ $line == *';'* ]] || continue
        if [[ $statement =~ define[[:space:]]*\([[:space:]]*[\'\"](DB_NAME|DISABLE_WP_CRON)[\'\"][[:space:]]*,[[:space:]]*(.*)\)[[:space:]]*\; ]]; then
            key=${BASH_REMATCH[1]}
            expression=${BASH_REMATCH[2]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")"
            else
                printf '%s\t%s\n' "$key" unresolved
            fi
        elif [[ $statement =~ const[[:space:]]+(DB_NAME|DISABLE_WP_CRON)[[:space:]]*=[[:space:]]*(.*)\; ]]; then
            key=${BASH_REMATCH[1]}
            expression=${BASH_REMATCH[2]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")"
            else
                printf '%s\t%s\n' "$key" unresolved
            fi
        elif [[ $statement =~ \$table_prefix[[:space:]]*=[[:space:]]*(.*)\; ]]; then
            expression=${BASH_REMATCH[1]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf 'table_prefix\t%s\n' "$(dbtune_audit_clean "$value")"
            else
                printf 'table_prefix\tunresolved\n'
            fi
        fi
        statement=''
    done <"$file"
}

dbtune_audit_find_wp_config() {
    local app=${1:-}
    local candidate

    for candidate in "$app/wp-config.php" "$app/htdocs/wp-config.php" "$app/public/wp-config.php"; do
        if [[ -r $candidate ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

dbtune_audit_scan_landmines() {
    local version=${1:-0}
    local root=${2:-/etc/mysql}
    local file variable severity gate
    local -a files=()

    [[ -d $root ]] || return 0
    while IFS= read -r file; do
        files+=("$file")
    done < <(command grep -RIl --include='*.cnf' '' "$root" 2>/dev/null || true)
    for file in "${files[@]}"; do
        while IFS=$'\t' read -r variable gate severity; do
            dbtune_version_at_least "$version" "$gate" || continue
            if command grep -Eiq "^[[:space:]]*${variable//_/[-_]}[[:space:]]*=" "$file" 2>/dev/null; then
                printf 'landmine.%s.severity\t%s\n' "$variable" "$severity"
                printf 'landmine.%s.file\t%s\n' "$variable" "$file"
            fi
        done <<'LANDMINES'
innodb_file_format	10.3	critical
innodb_file_format_max	10.3	critical
innodb_buffer_pool_instances	10.6	critical
innodb_log_files_in_group	10.6	critical
innodb_change_buffering	11.0	critical
innodb_flush_method	11.0	warning
LANDMINES
    done
}

dbtune_audit_parse_cnf() {
    local file=${1:-}
    local key value normalized

    [[ -r $file ]] || return 0
    while IFS='=' read -r key value; do
        key=${key%%#*}
        key=${key%%;*}
        key=${key#"${key%%[![:space:]]*}"}
        key=${key%"${key##*[![:space:]]}"}
        normalized=${key//-/_}
        case $normalized in
            open_files_limit|max_connections|innodb_buffer_pool_size|innodb_flush_log_at_trx_commit|innodb_lock_wait_timeout|query_cache_size|query_cache_type|performance_schema|bind_address|skip_log_bin|log_bin)
                value=${value%%#*}
                value=${value%%;*}
                value=${value#"${value%%[![:space:]]*}"}
                value=${value%"${value##*[![:space:]]}"}
                printf '%s\t%s\n' "$normalized" "$(dbtune_audit_clean "$value")"
                ;;
        esac
    done <"$file"
}

dbtune_audit_sql() {
    dbtune_sql "$1" 2>/dev/null
}

dbtune_audit_collect_hw() {
    local out=${1:-}
    local cpu=0 mem_total=0 mem_available=0 swap_total=0 swap_used=0
    local name type rota model device_line class=unknown index=0 child child_type child_rota child_model
    local df_line path key

    if command -v nproc >/dev/null 2>&1; then
        cpu=$(nproc 2>/dev/null || printf 0)
    elif command -v getconf >/dev/null 2>&1; then
        cpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 0)
    fi
    dbtune_audit_put "$out" hw.cpu_count "$cpu"

    if command -v free >/dev/null 2>&1; then
        read -r mem_total mem_available swap_total swap_used < <(free -b 2>/dev/null | command awk '
            /^Mem:/ { mt=$2; ma=$7 }
            /^Swap:/ { st=$2; su=$3 }
            END { print mt+0, ma+0, st+0, su+0 }
        ')
    elif [[ -r /proc/meminfo ]]; then
        read -r mem_total mem_available swap_total swap_used < <(command awk '
            /^MemTotal:/ { mt=$2*1024 }
            /^MemAvailable:/ { ma=$2*1024 }
            /^SwapTotal:/ { st=$2*1024 }
            /^SwapFree:/ { sf=$2*1024 }
            END { print mt+0, ma+0, st+0, st-sf }
        ' /proc/meminfo)
    fi
    dbtune_audit_put "$out" hw.ram_bytes "$mem_total"
    dbtune_audit_put "$out" hw.ram_available_bytes "$mem_available"
    dbtune_audit_put "$out" hw.swap_bytes "$swap_total"
    dbtune_audit_put "$out" hw.swap_used_bytes "$swap_used"

    if command -v lsblk >/dev/null 2>&1; then
        while read -r name type rota model; do
            [[ -n $name && $name != loop* ]] || continue
            device_line="$name:$type:$rota:$model"
            if [[ $type == raid* || $type == md ]]; then
                while read -r child child_type child_rota child_model; do
                    [[ -n $child && $child != "$name" && $child_type == disk ]] || continue
                    device_line+=",$child:$child_type:$child_rota:$child_model"
                    if [[ $child == nvme* || ${child_model,,} == *nvme* ]]; then
                        class=nvme
                    elif [[ $class != nvme && $child_rota == 1 ]]; then
                        class=hdd
                    elif [[ $class == unknown ]]; then
                        class=ssd
                    fi
                done < <(lsblk -nr -o NAME,TYPE,ROTA,MODEL "/dev/$name" 2>/dev/null || true)
            elif [[ $type == disk ]]; then
                if [[ $name == nvme* || ${model,,} == *nvme* ]]; then
                    class=nvme
                elif [[ $class != nvme && $rota == 1 ]]; then
                    class=hdd
                elif [[ $class == unknown ]]; then
                    class=ssd
                fi
            fi
            dbtune_audit_put "$out" "hw.disk.$index" "$device_line"
            index=$((index + 1))
        done < <(lsblk -dn -o NAME,TYPE,ROTA,MODEL 2>/dev/null || true)
    elif [[ -d /sys/block ]]; then
        for path in /sys/block/*; do
            [[ -e $path && ${path##*/} != loop* ]] || continue
            name=${path##*/}
            rota=unknown
            IFS= read -r rota <"$path/queue/rotational" 2>/dev/null || true
            device_line="$name:disk:$rota:unknown"
            for child in "$path"/slaves/*; do
                [[ -e $child ]] || continue
                child=${child##*/}
                child_rota=unknown
                IFS= read -r child_rota <"/sys/block/$child/queue/rotational" 2>/dev/null || true
                device_line+=",$child:disk:$child_rota:unknown"
                if [[ $child == nvme* ]]; then
                    class=nvme
                elif [[ $class != nvme && $child_rota == 1 ]]; then
                    class=hdd
                elif [[ $class == unknown ]]; then
                    class=ssd
                fi
            done
            if [[ $name == nvme* ]]; then
                class=nvme
            elif [[ $class != nvme && $rota == 1 ]]; then
                class=hdd
            elif [[ $class == unknown ]]; then
                class=ssd
            fi
            dbtune_audit_put "$out" "hw.disk.$index" "$device_line"
            index=$((index + 1))
        done
    fi
    dbtune_audit_put "$out" hw.storage_class "$class"
    dbtune_audit_put "$out" hw.disk_count "$index"

    for path in / "${DBTUNE_MYSQL_DATADIR:-/var/lib/mysql}"; do
        [[ -e $path ]] || continue
        df_line=$(df -Pk "$path" 2>/dev/null | command awk 'NR==2 { print $2*1024 "\t" $4*1024 "\t" $5 }') || true
        [[ -n $df_line ]] || continue
        key=$(dbtune_audit_slug "$path")
        [[ $path == / ]] && key=root
        dbtune_audit_put "$out" "hw.filesystem.$key" "$df_line"
    done
}

dbtune_audit_collect_mariadb() {
    local out=${1:-}
    local dbout=${2:-}
    local version rows name value key schema total data indexes tables
    local qcache_hits=0 com_select=0 hit_rate=0
    local variables status

    if ! version=$(dbtune_audit_sql 'SELECT VERSION()'); then
        dbtune_audit_put "$out" mariadb.available 0
        dbtune_audit_put "$out" finding.mariadb_unavailable warning
        return 0
    fi
    version=${version%%$'\n'*}
    dbtune_audit_put "$out" mariadb.available 1
    dbtune_audit_put "$out" mariadb.version "$version"

    variables="'DATADIR','INNODB_BUFFER_POOL_SIZE','INNODB_LOG_FILE_SIZE','INNODB_LOG_BUFFER_SIZE','INNODB_FLUSH_LOG_AT_TRX_COMMIT','INNODB_IO_CAPACITY','INNODB_IO_CAPACITY_MAX','INNODB_READ_IO_THREADS','INNODB_WRITE_IO_THREADS','INNODB_FLUSH_METHOD','INNODB_FLUSH_NEIGHBORS','INNODB_MAX_DIRTY_PAGES_PCT','INNODB_MAX_DIRTY_PAGES_PCT_LWM','MAX_CONNECTIONS','OPEN_FILES_LIMIT','PERFORMANCE_SCHEMA','QUERY_CACHE_SIZE','QUERY_CACHE_TYPE','SKIP_NAME_RESOLVE','SLOW_QUERY_LOG','LONG_QUERY_TIME','LOG_BIN','WSREP_ON','BIND_ADDRESS','KEY_BUFFER_SIZE','TMP_TABLE_SIZE','MAX_HEAP_TABLE_SIZE'"
    if ! rows=$(dbtune_audit_sql "SELECT LOWER(VARIABLE_NAME), VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME IN ($variables) ORDER BY VARIABLE_NAME"); then
        rows=''
        dbtune_audit_put "$out" finding.global_variables_query_failed warning
    fi
    while IFS=$'\t' read -r name value; do
        [[ -n $name ]] || continue
        key=$(dbtune_audit_slug "$name")
        dbtune_audit_put "$out" "mariadb.variable.$key" "$value"
        case $key in
            datadir) DBTUNE_MYSQL_DATADIR=$value ;;
            qcache_hits) qcache_hits=$value ;;
            com_select) com_select=$value ;;
        esac
    done <<<"$rows"

    status="'UPTIME','QUESTIONS','COM_SELECT','INNODB_BUFFER_POOL_READS','INNODB_BUFFER_POOL_READ_REQUESTS','INNODB_DATA_READ','INNODB_BUFFER_POOL_PAGES_DATA','INNODB_BUFFER_POOL_PAGES_FREE','INNODB_BUFFER_POOL_WAIT_FREE','INNODB_LOG_WAITS','CREATED_TMP_DISK_TABLES','CREATED_TMP_TABLES','HANDLER_READ_RND_NEXT','QCACHE_HITS','MAX_USED_CONNECTIONS','SLOW_QUERIES','KEY_READ_REQUESTS','ABORTED_CONNECTS','THREADS_RUNNING','THREADS_CONNECTED'"
    if ! rows=$(dbtune_audit_sql "SELECT LOWER(VARIABLE_NAME), VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME IN ($status) ORDER BY VARIABLE_NAME"); then
        rows=''
        dbtune_audit_put "$out" finding.global_status_query_failed warning
    fi
    while IFS=$'\t' read -r name value; do
        [[ -n $name ]] || continue
        key=$(dbtune_audit_slug "$name")
        dbtune_audit_put "$out" "mariadb.status.$key" "$value"
        case $key in
            qcache_hits) qcache_hits=$value ;;
            com_select) com_select=$value ;;
        esac
    done <<<"$rows"
    if [[ $qcache_hits =~ ^[0-9]+$ && $com_select =~ ^[0-9]+$ ]]; then
        hit_rate=$(command awk -v h="$qcache_hits" -v s="$com_select" 'BEGIN { if (h+s == 0) print 0; else printf "%.2f", 100*h/(h+s) }')
    fi
    dbtune_audit_put "$out" mariadb.query_cache_hit_pct "$hit_rate"

    if ! rows=$(dbtune_audit_sql "SELECT TABLE_SCHEMA, COALESCE(SUM(DATA_LENGTH+INDEX_LENGTH),0), COALESCE(SUM(DATA_LENGTH),0), COALESCE(SUM(INDEX_LENGTH),0), COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys') GROUP BY TABLE_SCHEMA ORDER BY TABLE_SCHEMA"); then
        rows=''
        dbtune_audit_put "$out" finding.dataset_query_failed warning
    fi
    while IFS=$'\t' read -r schema total data indexes tables; do
        [[ -n $schema ]] || continue
        if ! dbtune_sql_quote_identifier "$schema" >/dev/null; then
            dbtune_audit_scope_put "$dbout" "$schema" audit_error invalid_identifier
            continue
        fi
        dbtune_audit_scope_put "$dbout" "$schema" size_bytes "${total:-0}"
        dbtune_audit_scope_put "$dbout" "$schema" data_bytes "${data:-0}"
        dbtune_audit_scope_put "$dbout" "$schema" index_bytes "${indexes:-0}"
        dbtune_audit_scope_put "$dbout" "$schema" table_count "${tables:-0}"
    done <<<"$rows"
    total=$(command awk -F '\t' '$2=="size_bytes" { sum += $3 } END { printf "%.0f", sum }' "$dbout")
    dbtune_audit_put "$out" mariadb.dataset_bytes "$total"
}

dbtune_audit_table_exists() {
    local database=${1:-}
    local table=${2:-}
    local db_literal table_literal result

    db_literal=$(dbtune_sql_quote_literal "$database") || return
    table_literal=$(dbtune_sql_quote_literal "$table") || return
    result=$(dbtune_audit_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=$db_literal AND TABLE_NAME=$table_literal") || return 2
    [[ ${result%%$'\n'*} == 1 ]]
}

dbtune_audit_database_metrics() {
    local dbout=${1:-}
    local database=${2:-}
    local prefix=${3:-wp_}
    local dbq tableq rows a b c d key index=0 probe_status

    dbq=$(dbtune_sql_quote_identifier "$database") || {
        dbtune_audit_scope_put "$dbout" "$database" audit_error invalid_identifier
        return 0
    }
    [[ $prefix =~ ^[A-Za-z0-9_]+$ && ${#prefix} -le 48 ]] || {
        dbtune_audit_scope_put "$dbout" "$database" audit_error invalid_table_prefix
        return 0
    }

    tableq=$(dbtune_sql_quote_identifier "${prefix}options") || return 0
    if dbtune_audit_table_exists "$database" "${prefix}options"; then
        rows=$(dbtune_audit_sql "SELECT COALESCE(SUM(LENGTH(option_value)),0), COUNT(*) FROM $dbq.$tableq WHERE autoload IN ('yes','on','auto')" || true)
        IFS=$'\t' read -r a b <<<"${rows%%$'\n'*}"
        dbtune_audit_scope_put "$dbout" "$database" autoload_bytes "${a:-0}"
        dbtune_audit_scope_put "$dbout" "$database" autoload_count "${b:-0}"
        rows=$(dbtune_audit_sql "SELECT option_name, LENGTH(option_value) FROM $dbq.$tableq WHERE autoload IN ('yes','on','auto') ORDER BY LENGTH(option_value) DESC LIMIT 20" || true)
        while IFS=$'\t' read -r a b; do
            [[ -n $a ]] || continue
            dbtune_audit_scope_put "$dbout" "$database" "autoload.top.$index" "$a:${b:-0}"
            index=$((index + 1))
        done <<<"$rows"
        rows=$(dbtune_audit_sql "SELECT option_name, option_value FROM $dbq.$tableq WHERE option_name IN ('woocommerce_custom_orders_table_enabled','woocommerce_custom_orders_table_data_sync_enabled','woocommerce_feature_custom_order_tables_enabled') ORDER BY option_name" || true)
        while IFS=$'\t' read -r a b; do
            [[ -n $a ]] || continue
            dbtune_audit_scope_put "$dbout" "$database" "hpos.$(dbtune_audit_slug "$a")" "$b"
        done <<<"$rows"
        rows=$(dbtune_audit_sql "SELECT COUNT(*), COALESCE(SUM(LENGTH(option_value)),0) FROM $dbq.$tableq WHERE option_name LIKE '\\_transient%'" || true)
        IFS=$'\t' read -r a b <<<"${rows%%$'\n'*}"
        dbtune_audit_scope_put "$dbout" "$database" transient_count "${a:-0}"
        dbtune_audit_scope_put "$dbout" "$database" transient_bytes "${b:-0}"
    else
        probe_status=$?
        if ((probe_status == 2)); then
            dbtune_audit_scope_put "$dbout" "$database" audit_error options_table_probe_failed
        else
            dbtune_audit_scope_put "$dbout" "$database" audit_error options_table_missing
        fi
    fi

    for tableq in "${prefix}wc_orders" "${prefix}woocommerce_sessions"; do
        if dbtune_audit_table_exists "$database" "$tableq"; then
            a=$(dbtune_sql_quote_identifier "$tableq") || continue
            rows=$(dbtune_audit_sql "SELECT COUNT(*) FROM $dbq.$a" || true)
            key=$(dbtune_audit_slug "${tableq#"$prefix"}")
            dbtune_audit_scope_put "$dbout" "$database" "${key}_count" "${rows%%$'\n'*}"
        fi
    done

    if dbtune_audit_table_exists "$database" "${prefix}posts"; then
        tableq=$(dbtune_sql_quote_identifier "${prefix}posts") || return 0
        rows=$(dbtune_audit_sql "SELECT COALESCE(SUM(post_type LIKE 'shop_order%'),0) FROM $dbq.$tableq" || true)
        dbtune_audit_scope_put "$dbout" "$database" legacy_order_count "${rows%%$'\n'*}"
    fi
    if dbtune_audit_table_exists "$database" "${prefix}actionscheduler_actions"; then
        tableq=$(dbtune_sql_quote_identifier "${prefix}actionscheduler_actions") || return 0
        rows=$(dbtune_audit_sql "SELECT status, COUNT(*) FROM $dbq.$tableq GROUP BY status ORDER BY status" || true)
        while IFS=$'\t' read -r a b; do
            [[ -n $a ]] || continue
            dbtune_audit_scope_put "$dbout" "$database" "action_scheduler.$(dbtune_audit_slug "$a")" "$b"
        done <<<"$rows"
    fi

    rows=$(dbtune_audit_sql "SELECT TABLE_NAME, COALESCE(TABLE_ROWS,0), DATA_LENGTH+INDEX_LENGTH, ROUND((DATA_LENGTH+INDEX_LENGTH)/NULLIF(TABLE_ROWS,0)/1024,1) FROM information_schema.TABLES WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") AND TABLE_NAME REGEXP 'log|history|track|event' ORDER BY DATA_LENGTH+INDEX_LENGTH DESC LIMIT 20" || true)
    index=0
    while IFS=$'\t' read -r a b c d; do
        [[ -n $a ]] || continue
        dbtune_audit_scope_put "$dbout" "$database" "log_table.$index" "$a:${b:-0}:${c:-0}:${d:-0}"
        index=$((index + 1))
    done <<<"$rows"

    rows=$(dbtune_audit_sql "SELECT INDEX_NAME, GROUP_CONCAT(CONCAT(COLUMN_NAME,IFNULL(CONCAT('(',SUB_PART,')'),'')) ORDER BY SEQ_IN_INDEX) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") AND TABLE_NAME=$(dbtune_sql_quote_literal "${prefix}postmeta") GROUP BY INDEX_NAME ORDER BY INDEX_NAME" || true)
    index=0
    while IFS=$'\t' read -r a b; do
        [[ -n $a ]] || continue
        dbtune_audit_scope_put "$dbout" "$database" "postmeta.index.$index" "$a:$b"
        if [[ $b == meta_value || $b == meta_value\(* ]]; then
            dbtune_audit_scope_put "$dbout" "$database" rogue_meta_value_index "$a"
        fi
        index=$((index + 1))
    done <<<"$rows"

    rows=$(dbtune_audit_sql "SELECT TABLE_NAME, COALESCE(TABLE_ROWS,0), DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") ORDER BY DATA_LENGTH+INDEX_LENGTH DESC LIMIT 10" || true)
    index=0
    while IFS=$'\t' read -r a b c; do
        [[ -n $a ]] || continue
        dbtune_audit_scope_put "$dbout" "$database" "top_table.$index" "$a:${b:-0}:${c:-0}"
        index=$((index + 1))
    done <<<"$rows"
}

dbtune_audit_collect_apps() {
    local out=${1:-}
    local appout=${2:-}
    local dbout=${3:-}
    local home_root=${DBTUNE_HOME_ROOT:-/home}
    local user_dir app config app_root app_id app_index=0 type key value db_name='' prefix='' disable_cron=unresolved
    local redis_active=0 redis_ping=0 cron_present=0 woo object_cache page_cache
    local -a databases=()

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet redis-server 2>/dev/null; then
        redis_active=1
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet redis 2>/dev/null; then
        redis_active=1
    fi
    if command -v redis-cli >/dev/null 2>&1 && [[ $(redis-cli ping 2>/dev/null || true) == PONG ]]; then
        redis_ping=1
    fi
    if command grep -RqsE 'wp-cron\.php|wp cron event run' "${DBTUNE_CRON_ROOT:-/etc/cron.d}" /etc/crontab 2>/dev/null; then
        cron_present=1
    fi
    dbtune_audit_put "$out" app.redis_service_active "$redis_active"
    dbtune_audit_put "$out" app.redis_ping "$redis_ping"
    dbtune_audit_put "$out" app.system_wp_cron "$cron_present"
    if ((redis_ping)); then
        value=$(redis-cli --raw CONFIG GET maxmemory-policy 2>/dev/null | command awk 'NR==2 { print; exit }' || true)
        dbtune_audit_put "$out" redis.maxmemory_policy "${value:-unknown}"
        value=$(redis-cli --raw INFO stats 2>/dev/null | command awk -F: '$1=="evicted_keys" { sub(/\r$/, "", $2); print $2; exit }' || true)
        dbtune_audit_put "$out" redis.evicted_keys "${value:-unknown}"
        value=$(redis-cli --raw INFO memory 2>/dev/null | command awk -F: '$1=="used_memory" { sub(/\r$/, "", $2); print $2; exit }' || true)
        dbtune_audit_put "$out" redis.used_memory_bytes "${value:-unknown}"
    fi

    for user_dir in "$home_root"/*; do
        [[ -d $user_dir/webapps ]] || continue
        for app in "$user_dir"/webapps/*; do
            [[ -d $app ]] || continue
            app_id="app.$app_index"
            app_index=$((app_index + 1))
            dbtune_audit_scope_put "$appout" "$app_id" path "$app"
            dbtune_audit_scope_put "$appout" "$app_id" owner "${user_dir##*/}"
            config=$(dbtune_audit_find_wp_config "$app" || true)
            if [[ -z $config && ! -f $app/wp-load.php && ! -f $app/htdocs/wp-load.php && ! -f $app/public/wp-load.php ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" type non_wordpress
                dbtune_audit_scope_put "$appout" "$app_id" finding database_mapping_unavailable
                continue
            fi
            type=wordpress
            dbtune_audit_scope_put "$appout" "$app_id" type "$type"
            dbtune_audit_scope_put "$appout" "$app_id" wp_config "${config:-unresolved}"
            app_root=$app
            [[ -f $app/htdocs/wp-load.php ]] && app_root=$app/htdocs
            [[ -f $app/public/wp-load.php ]] && app_root=$app/public
            db_name=''
            prefix=''
            disable_cron=unresolved
            if [[ -n $config ]]; then
                while IFS=$'\t' read -r key value; do
                    case $key in
                        DB_NAME) db_name=$value ;;
                        table_prefix) prefix=$value ;;
                        DISABLE_WP_CRON) disable_cron=$value ;;
                    esac
                done < <(dbtune_wp_config_parse "$config")
            fi
            if command -v wp >/dev/null 2>&1; then
                if [[ -z $db_name || $db_name == unresolved ]]; then
                    db_name=$(wp --path="$app_root" --allow-root --quiet config get DB_NAME 2>/dev/null || true)
                fi
                if [[ -z $prefix || $prefix == unresolved ]]; then
                    prefix=$(wp --path="$app_root" --allow-root --quiet db prefix 2>/dev/null || true)
                fi
            fi
            if [[ -n $db_name && $db_name != unresolved && (-z $prefix || $prefix == unresolved) ]]; then
                value=$(dbtune_audit_sql "SHOW TABLES FROM $(dbtune_sql_quote_identifier "$db_name") LIKE '%options'" || true)
                value=${value%%$'\n'*}
                [[ $value == *options ]] && prefix=${value%options}
            fi
            [[ -n $prefix && $prefix != unresolved ]] || prefix=wp_
            dbtune_audit_scope_put "$appout" "$app_id" database "${db_name:-unresolved}"
            dbtune_audit_scope_put "$appout" "$app_id" table_prefix "$prefix"
            dbtune_audit_scope_put "$appout" "$app_id" disable_wp_cron "$disable_cron"

            object_cache=0
            page_cache=0
            woo=0
            [[ -f $app_root/wp-content/object-cache.php ]] && object_cache=1
            [[ -f $app_root/wp-content/advanced-cache.php ]] && page_cache=1
            [[ -f $app_root/wp-content/plugins/woocommerce/woocommerce.php ]] && woo=1
            if [[ $woo == 0 && -n $db_name && $db_name != unresolved ]] &&
                dbtune_audit_table_exists "$db_name" "${prefix}woocommerce_sessions"; then
                woo=1
            fi
            if [[ -n $config ]] && command grep -Eqs "define[[:space:]]*\([[:space:]]*['\"]WP_CACHE['\"][[:space:]]*,[[:space:]]*(true|TRUE)" "$config" 2>/dev/null; then
                page_cache=1
            fi
            dbtune_audit_scope_put "$appout" "$app_id" object_cache_dropin "$object_cache"
            dbtune_audit_scope_put "$appout" "$app_id" page_cache "$page_cache"
            dbtune_audit_scope_put "$appout" "$app_id" woocommerce "$woo"
            if [[ $object_cache == 0 ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" finding.object_cache critical
            elif [[ $redis_ping == 0 ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" finding.redis_unavailable critical
            fi
            if [[ $disable_cron == true && $cron_present == 0 ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" finding.wp_cron_disabled critical
            fi
            if [[ -n $db_name && $db_name != unresolved ]]; then
                databases+=("$db_name"$'\t'"$prefix")
                dbtune_audit_scope_put "$dbout" "$db_name" "app_id.${app_id##*.}" "$app_id"
            else
                dbtune_audit_scope_put "$appout" "$app_id" finding.database_unresolved warning
            fi
        done
    done
    dbtune_audit_put "$out" app.count "$app_index"

    if ((${#databases[@]})); then
        while IFS=$'\t' read -r db_name prefix; do
            dbtune_audit_database_metrics "$dbout" "$db_name" "$prefix" || {
                dbtune_audit_scope_put "$dbout" "$db_name" audit_error query_failed
            }
        done < <(printf '%s\n' "${databases[@]}" | sort -u)
    fi
    while IFS= read -r db_name; do
        [[ -n $db_name ]] || continue
        if command awk -F '\t' -v db="$db_name" '$1==db && $2 ~ /^app_id\./ { found=1 } END { exit !found }' "$dbout"; then
            dbtune_audit_scope_put "$dbout" "$db_name" application_mapping wordpress
        else
            dbtune_audit_scope_put "$dbout" "$db_name" application_mapping unmapped
        fi
    done < <(command awk -F '\t' '$2=="size_bytes" { print $1 }' "$dbout" | sort -u)
}

dbtune_audit_collect_platform() {
    local out=${1:-}
    local runcloud=${DBTUNE_RUNCLOUD_CNF:-/etc/mysql/conf.d/runcloud.cnf}
    local key value limit=unknown fpm=0 backup=0 backup_schedules=0 grants rows count=0 listener=unknown
    local unattended=${DBTUNE_UNATTENDED_CONFIG:-/etc/apt/apt.conf.d/50unattended-upgrades}

    if [[ -r $runcloud ]]; then
        dbtune_audit_put "$out" runcloud.cnf_present 1
        while IFS=$'\t' read -r key value; do
            dbtune_audit_put "$out" "runcloud.$key" "$value"
        done < <(dbtune_audit_parse_cnf "$runcloud")
        if command grep -Eiq '^[[:space:]]*skip[-_]log[-_]bin([[:space:]]|$)' "$runcloud" 2>/dev/null; then
            dbtune_audit_put "$out" runcloud.skip_log_bin 1
        fi
    else
        dbtune_audit_put "$out" runcloud.cnf_present 0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        limit=$(systemctl show mariadb.service -p LimitNOFILE --value 2>/dev/null || true)
        [[ -n $limit ]] || limit=$(systemctl show mysql.service -p LimitNOFILE --value 2>/dev/null || true)
    fi
    dbtune_audit_put "$out" systemd.limit_nofile "${limit:-unknown}"

    if [[ -r $unattended ]] && command grep -Eqs 'MariaDB:' "$unattended" 2>/dev/null; then
        dbtune_audit_put "$out" unattended.mariadb_origin 1
    else
        dbtune_audit_put "$out" unattended.mariadb_origin 0
    fi
    if command grep -RqsE "^[[:space:]]*[\"']?mariadb-" "${DBTUNE_UNATTENDED_DIR:-/etc/apt/apt.conf.d}" 2>/dev/null; then
        dbtune_audit_put "$out" unattended.mariadb_blacklisted 1
    else
        dbtune_audit_put "$out" unattended.mariadb_blacklisted 0
    fi

    if command -v pgrep >/dev/null 2>&1; then
        backup=$(pgrep -fc '(^|/)(mydumper|mysqldump|mariadb-dump)([[:space:]]|$)' 2>/dev/null || true)
    fi
    [[ $backup =~ ^[0-9]+$ ]] || backup=0
    dbtune_audit_put "$out" backup.process_count "$backup"
    if command grep -RhsE 'mydumper|mariadb-dump|mysqldump' "${DBTUNE_CRON_SCAN_ROOT:-/etc/cron.d}" /etc/crontab 2>/dev/null |
        command awk 'NF >= 6 && $1 !~ /^#/ { print $1 " " $2 " " $3 " " $4 " " $5 }' >"$out.backup"; then
        while IFS= read -r value; do
            [[ -n $value ]] || continue
            dbtune_audit_put "$out" "backup.cron_schedule.$backup_schedules" "$value"
            backup_schedules=$((backup_schedules + 1))
        done <"$out.backup"
        rm -f "$out.backup"
    fi
    dbtune_audit_put "$out" backup.schedule_count "$backup_schedules"

    if command grep -RhsE '^[[:space:]]*pm\.max_children[[:space:]]*=' /etc/php/*/fpm/pool.d /etc/php*rc/fpm.d 2>/dev/null | command awk -F= '{ sum += $2 } END { print sum+0 }' >"$out.fpm"; then
        IFS= read -r fpm <"$out.fpm" || fpm=0
        rm -f "$out.fpm"
    fi
    dbtune_audit_put "$out" php_fpm.max_children_sum "${fpm:-0}"
    if command -v openlitespeed >/dev/null 2>&1 || command -v lshttpd >/dev/null 2>&1; then
        dbtune_audit_put "$out" php_fpm.ols_stack 1
        dbtune_audit_put "$out" finding.php_fpm_formula_unavailable warning
    else
        dbtune_audit_put "$out" php_fpm.ols_stack 0
    fi

    if rows=$(dbtune_audit_sql "SELECT CONCAT(USER,'@',HOST) FROM mysql.user WHERE HOST NOT IN ('localhost','127.0.0.1','::1') ORDER BY USER,HOST"); then
        dbtune_audit_put "$out" security.grants_audited 1
    else
        rows=''
        dbtune_audit_put "$out" security.grants_audited 0
        dbtune_audit_put "$out" finding.grants_query_failed warning
    fi
    while IFS= read -r grants; do
        [[ -n $grants ]] || continue
        dbtune_audit_put "$out" "security.remote_grant.$count" "$grants"
        count=$((count + 1))
    done <<<"$rows"
    dbtune_audit_put "$out" security.remote_grant_count "$count"
    if command -v ss >/dev/null 2>&1; then
        if ss -lnt 2>/dev/null | command awk '$4 ~ /(^|:)(0\.0\.0\.0|\[::\]|\*)?:?3306$/ { found=1 } END { exit !found }'; then
            listener=public
        elif ss -lnt 2>/dev/null | command awk '$4 ~ /:3306$/ { found=1 } END { exit !found }'; then
            listener=local
        else
            listener=not_listening
        fi
    fi
    dbtune_audit_put "$out" security.port_3306 "$listener"
    [[ $listener != public ]] || dbtune_audit_put "$out" finding.public_db_listener warning
    if [[ -e $DBTUNE_ROOT_CNF ]]; then
        dbtune_audit_put "$out" security.root_cnf_present 1
        dbtune_audit_put "$out" security.root_cnf_note contains_credentials_do_not_share
    else
        dbtune_audit_put "$out" security.root_cnf_present 0
    fi
}

dbtune_audit_add_findings() {
    local out=${1:-}
    local version=${2:-0}
    local config_root=${DBTUNE_MYSQL_CONFIG_DIR:-/etc/mysql}
    local key value effective systemd_limit configured_limit

    while IFS=$'\t' read -r key value; do
        dbtune_audit_put "$out" "$key" "$value"
    done < <(dbtune_audit_scan_landmines "$version" "$config_root")

    effective=$(command awk -F '\t' '$1=="mariadb.variable.open_files_limit" { print $2; exit }' "$out")
    systemd_limit=$(command awk -F '\t' '$1=="systemd.limit_nofile" { print $2; exit }' "$out")
    configured_limit=$(command awk -F '\t' '$1=="runcloud.open_files_limit" { print $2; exit }' "$out")
    if [[ $effective =~ ^[0-9]+$ && $configured_limit =~ ^[0-9]+$ && $effective -lt $configured_limit ]] ||
        [[ $effective =~ ^[0-9]+$ && $systemd_limit =~ ^[0-9]+$ && $effective -lt $systemd_limit ]]; then
        dbtune_audit_put "$out" finding.open_files_limited warning
    fi
    if command awk -F '\t' '$1=="mariadb.variable.log_bin" && ($2=="OFF" || $2=="0") { found=1 } END { exit !found }' "$out"; then
        dbtune_audit_put "$out" finding.binlog_disabled warning
    fi
    if command awk -F '\t' '$1=="mariadb.variable.performance_schema" && ($2=="OFF" || $2=="0") { found=1 } END { exit !found }' "$out"; then
        dbtune_audit_put "$out" finding.performance_schema_disabled info
    fi
    if command awk -F '\t' '$1=="mariadb.variable.wsrep_on" && !($2=="OFF" || $2=="0") { found=1 } END { exit !found }' "$out"; then
        dbtune_audit_put "$out" mariadb.galera 1
        dbtune_audit_put "$out" finding.galera critical
    else
        dbtune_audit_put "$out" mariadb.galera 0
    fi
}

dbtune_audit_json() {
    local audit=${1:-}
    local apps=${2:-}
    local database_file=${3:-}
    local scope key value
    local -a fields=()

    while IFS=$'\t' read -r key value; do
        [[ -n $key ]] && fields+=("$key" "$value")
    done <"$audit"
    while IFS=$'\t' read -r scope key value; do
        [[ -n $scope && -n $key ]] && fields+=("$scope.$key" "$value")
    done <"$apps"
    while IFS=$'\t' read -r scope key value; do
        [[ -n $scope && -n $key ]] && fields+=("database.$(dbtune_audit_slug "$scope").$key" "$value")
    done <"$database_file"
    dbtune_json_emit "${fields[@]}"
}

dbtune_audit_summary() {
    local audit=${1:-}
    local apps=${2:-}
    local database_file=${3:-}
    local version cpu ram dataset storage app_count db_count critical warning

    version=$(command awk -F '\t' '$1=="mariadb.version" { print $2; exit }' "$audit")
    cpu=$(command awk -F '\t' '$1=="hw.cpu_count" { print $2; exit }' "$audit")
    ram=$(command awk -F '\t' '$1=="hw.ram_bytes" { printf "%.1f GB", $2/1073741824; exit }' "$audit")
    dataset=$(command awk -F '\t' '$1=="mariadb.dataset_bytes" { printf "%.2f GB", $2/1073741824; exit }' "$audit")
    storage=$(command awk -F '\t' '$1=="hw.storage_class" { print $2; exit }' "$audit")
    app_count=$(command awk -F '\t' '$1=="app.count" { print $2; exit }' "$audit")
    db_count=$(command awk -F '\t' '$2=="size_bytes" { seen[$1]=1 } END { print length(seen) }' "$database_file")
    critical=$(command awk -F '\t' '$1 ~ /^finding\./ && $2=="critical" { n++ } END { print n+0 }' "$audit")
    critical=$((critical + $(command awk -F '\t' '$2 ~ /^finding/ && $3=="critical" { n++ } END { print n+0 }' "$apps")))
    warning=$(command awk -F '\t' '$1 ~ /^finding\./ && $2=="warning" { n++ } END { print n+0 }' "$audit")

    printf 'DBTune audit bol dokonceny.\n'
    printf 'Server: %s CPU, %s RAM, ulozisko %s.\n' "${cpu:-nezistene}" "${ram:-nezistena}" "${storage:-nezistene}"
    printf 'MariaDB: %s, dataset %s, databazy %s.\n' "${version:-nedostupna}" "${dataset:-nezisteny}" "${db_count:-0}"
    printf 'Aplikacie: %s. Kriticke nalezy: %s, varovania: %s.\n' "${app_count:-0}" "$critical" "$warning"
    printf 'Data: %s/{audit,apps,databases}.tsv\n' "$DBTUNE_STATE_DIR"
}

cmd_audit() {
    local json=0 argument scratch audit apps databases version

    for argument in "$@"; do
        case $argument in
            --json) json=1 ;;
            *)
                dbtune_log error "Neznama volba audit: $argument"
                return 64
                ;;
        esac
    done
    dbtune_init_state_dir || return 1
    scratch=$(mktemp -d "$DBTUNE_STATE_DIR/.audit.XXXXXX") || return 1
    chmod 700 "$scratch" || {
        rm -rf "$scratch"
        return 1
    }
    audit="$scratch/audit.tsv"
    apps="$scratch/apps.tsv"
    databases="$scratch/databases.tsv"
    : >"$audit"
    : >"$apps"
    : >"$databases"
    chmod 600 "$audit" "$apps" "$databases"

    dbtune_audit_put "$audit" audit.timestamp "$(dbtune_now)"
    dbtune_audit_put "$audit" audit.hostname "$(hostname 2>/dev/null || printf unknown)"
    dbtune_audit_collect_mariadb "$audit" "$databases"
    dbtune_audit_collect_hw "$audit"
    dbtune_audit_collect_platform "$audit"
    dbtune_audit_collect_apps "$audit" "$apps" "$databases"
    version=$(command awk -F '\t' '$1=="mariadb.version" { print $2; exit }' "$audit")
    dbtune_audit_add_findings "$audit" "${version:-0}"

    if ! dbtune_atomic_write "$DBTUNE_STATE_DIR/audit.tsv" 600 <"$audit" ||
        ! dbtune_atomic_write "$DBTUNE_STATE_DIR/apps.tsv" 600 <"$apps" ||
        ! dbtune_atomic_write "$DBTUNE_STATE_DIR/databases.tsv" 600 <"$databases"; then
        rm -rf "$scratch"
        dbtune_log error "Audit data sa nepodarilo atomicky zapisat"
        return 1
    fi
    rm -rf "$scratch"
    dbtune_state_record_audit || return

    if ((json)); then
        dbtune_audit_json "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    else
        dbtune_audit_summary "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    fi
}
