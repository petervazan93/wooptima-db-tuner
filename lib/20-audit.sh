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
    local quote char previous='' output='' index

    expression=${expression#"${expression%%[![:space:]]*}"}
    expression=${expression%"${expression##*[![:space:]]}"}
    quote=${expression:0:1}
    if [[ $quote == "'" || $quote == '"' ]]; then
        for ((index = 1; index < ${#expression}; index++)); do
            char=${expression:index:1}
            if [[ $char == "$quote" && $previous != \\ ]]; then
                printf '%s' "$output"
                return 0
            fi
            output+=$char
            if [[ $char == \\ && $previous == \\ ]]; then
                previous=''
            else
                previous=$char
            fi
        done
        return 1
    fi
    if [[ $expression =~ ^(true|TRUE)$ ]]; then
        printf 'true'
        return 0
    fi
    if [[ $expression =~ ^(false|FALSE)$ ]]; then
        printf 'false'
        return 0
    fi
    return 1
}

dbtune_wp_config_code() {
    local file=${1:-}

    [[ -r $file ]] || return 1
    command awk '
        BEGIN { quote=""; block=0; escape=0 }
        {
            line=$0; output=""; line_comment=0
            for (i=1; i<=length(line); i++) {
                char=substr(line,i,1); next_char=substr(line,i+1,1)
                if (line_comment) break
                if (block) {
                    if (char=="*" && next_char=="/") { block=0; i++ }
                    continue
                }
                if (quote != "") {
                    output=output char
                    if (escape) escape=0
                    else if (char=="\\") escape=1
                    else if (char==quote) quote=""
                    continue
                }
                if (char=="\"" || char=="\047") { quote=char; output=output char; continue }
                if (char=="/" && next_char=="*") { block=1; i++; continue }
                if (char=="/" && next_char=="/") { line_comment=1; continue }
                if (char=="#") { line_comment=1; continue }
                output=output char
            }
            print output
        }
    ' "$file"
}

dbtune_wp_config_parse() {
    local file=${1:-}
    local statement='' line key expression value

    [[ -r $file ]] || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line//$'\r'/}
        statement+=" $line"
        [[ $line == *';'* ]] || continue
        if [[ $statement =~ define[[:space:]]*\([[:space:]]*[\'\"](DB_NAME|DISABLE_WP_CRON|MULTISITE|WP_CACHE)[\'\"][[:space:]]*,[[:space:]]*(.*)\)[[:space:]]*\; ]]; then
            key=${BASH_REMATCH[1]}
            expression=${BASH_REMATCH[2]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")"
            else
                printf '%s\t%s\n' "$key" unresolved
            fi
        elif [[ $statement =~ const[[:space:]]+(DB_NAME|DISABLE_WP_CRON|MULTISITE|WP_CACHE)[[:space:]]*=[[:space:]]*(.*)\; ]]; then
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
    done < <(dbtune_wp_config_code "$file")
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
    DBTUNE_SQL_STATEMENT_TIMEOUT="${DBTUNE_AUDIT_QUERY_TIMEOUT_SECONDS:-5}" dbtune_sql "$1" 2>/dev/null
}

dbtune_audit_storage_class() {
    local datadir=${1:-/var/lib/mysql}
    local source rows name type rota model class=unknown uncertain=0

    command -v findmnt >/dev/null 2>&1 || return 1
    source=$(findmnt -n -o SOURCE --target "$datadir" 2>/dev/null) || return 1
    source=${source%%\[*}
    [[ $source == /dev/* ]] || return 1
    rows=$(lsblk -nr -s -o NAME,TYPE,ROTA,MODEL "$source" 2>/dev/null) || return 1
    while read -r name type rota model; do
        [[ $type == disk ]] || continue
        if [[ $rota == 1 ]]; then
            class=hdd
        elif [[ $rota == 0 && $class != hdd && ($name == nvme* || ${model,,} == *nvme*) ]]; then
            [[ $class == unknown ]] && class=nvme
        elif [[ $rota == 0 && $class != hdd ]]; then
            class=ssd
        else
            uncertain=1
        fi
    done <<<"$rows"
    ((uncertain == 0)) || class=unknown
    printf '%s\t%s\n' "$source" "$class"
}

dbtune_audit_collect_hw() {
    local out=${1:-}
    local cpu=0 mem_total=0 mem_available=0 swap_total=0 swap_used=0
    local name type rota model device_line class=unknown index=0 child child_type child_rota child_model
    local df_line path key storage_result mount_source leaf_index=0

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
                done < <(lsblk -nr -o NAME,TYPE,ROTA,MODEL "/dev/$name" 2>/dev/null || true)
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
            done
            dbtune_audit_put "$out" "hw.disk.$index" "$device_line"
            index=$((index + 1))
        done
    fi
    if storage_result=$(dbtune_audit_storage_class "${DBTUNE_MYSQL_DATADIR:-/var/lib/mysql}"); then
        IFS=$'\t' read -r mount_source class <<<"$storage_result"
        dbtune_audit_put "$out" hw.datadir_mount_source "$mount_source"
        while read -r name type rota model; do
            [[ $type == disk ]] || continue
            dbtune_audit_put "$out" "hw.datadir_leaf.$leaf_index" "$name:$type:$rota:$model"
            leaf_index=$(command awk -v n="$leaf_index" 'BEGIN { print n+1 }')
        done < <(lsblk -nr -s -o NAME,TYPE,ROTA,MODEL "$mount_source" 2>/dev/null || true)
    else
        dbtune_audit_put "$out" hw.datadir_mount_source unknown
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
    local qcache_hits=unknown com_select=unknown hit_rate=unknown
    local variables status dataset_ok=0

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

    if rows=$(dbtune_audit_sql "SELECT TABLE_SCHEMA, COALESCE(SUM(DATA_LENGTH+INDEX_LENGTH),0), COALESCE(SUM(DATA_LENGTH),0), COALESCE(SUM(INDEX_LENGTH),0), COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys') GROUP BY TABLE_SCHEMA ORDER BY TABLE_SCHEMA"); then
        dataset_ok=1
    else
        rows=''
        dbtune_audit_put "$out" finding.dataset_query_failed warning
    fi
    while IFS=$'\t' read -r schema total data indexes tables; do
        [[ -n $schema ]] || continue
        if ! dbtune_sql_quote_identifier "$schema" >/dev/null; then
            dbtune_audit_scope_put "$dbout" "$schema" audit_error invalid_identifier
            continue
        fi
        if [[ $total =~ ^[0-9]+$ && $data =~ ^[0-9]+$ && $indexes =~ ^[0-9]+$ && $tables =~ ^[0-9]+$ ]]; then
            dbtune_audit_scope_put "$dbout" "$schema" size_bytes "$total"
            dbtune_audit_scope_put "$dbout" "$schema" data_bytes "$data"
            dbtune_audit_scope_put "$dbout" "$schema" index_bytes "$indexes"
            dbtune_audit_scope_put "$dbout" "$schema" table_count "$tables"
        else
            dbtune_audit_scope_put "$dbout" "$schema" audit_error.dataset invalid_result
        fi
    done <<<"$rows"
    if ((dataset_ok)); then
        total=$(command awk -F '\t' '$2=="size_bytes" && $3 ~ /^[0-9]+$/ { sum += $3 } END { printf "%.0f", sum+0 }' "$dbout")
    else
        total=unknown
    fi
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
    local scope=${2:-}
    local database=${3:-}
    local prefix=${4:-wp_}
    local dbq tableq rows a b c d key index=0 probe_status table_name

    dbq=$(dbtune_sql_quote_identifier "$database") || {
        dbtune_audit_scope_put "$dbout" "$scope" audit_error.database invalid_identifier
        return 0
    }
    [[ $prefix =~ ^[A-Za-z0-9_]+$ && ${#prefix} -le 48 ]] || {
        dbtune_audit_scope_put "$dbout" "$scope" audit_error.prefix invalid_table_prefix
        return 0
    }

    tableq=$(dbtune_sql_quote_identifier "${prefix}options") || return 0
    if dbtune_audit_table_exists "$database" "${prefix}options"; then
        if rows=$(dbtune_audit_sql "SELECT COALESCE(SUM(LENGTH(option_value)),0), COUNT(*) FROM $dbq.$tableq WHERE autoload IN ('yes','on','auto')"); then
            IFS=$'\t' read -r a b <<<"${rows%%$'\n'*}"
            if [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]]; then
                dbtune_audit_scope_put "$dbout" "$scope" autoload_bytes "$a"
                dbtune_audit_scope_put "$dbout" "$scope" autoload_count "$b"
            else
                dbtune_audit_scope_put "$dbout" "$scope" autoload_bytes unknown
                dbtune_audit_scope_put "$dbout" "$scope" autoload_count unknown
                dbtune_audit_scope_put "$dbout" "$scope" audit_error.autoload invalid_result
            fi
        else
            dbtune_audit_scope_put "$dbout" "$scope" autoload_bytes unknown
            dbtune_audit_scope_put "$dbout" "$scope" autoload_count unknown
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.autoload query_failed
        fi
        if rows=$(dbtune_audit_sql "SELECT option_name, LENGTH(option_value) FROM $dbq.$tableq WHERE autoload IN ('yes','on','auto') ORDER BY LENGTH(option_value) DESC LIMIT 20"); then
            while IFS=$'\t' read -r a b; do
                [[ -n $a ]] || continue
                dbtune_audit_scope_put "$dbout" "$scope" "autoload.top.$index" "$a:${b:-unknown}"
                index=$(command awk -v n="$index" 'BEGIN { print n+1 }')
            done <<<"$rows"
        else
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.autoload_top query_failed
        fi
        if rows=$(dbtune_audit_sql "SELECT option_name, option_value FROM $dbq.$tableq WHERE option_name IN ('woocommerce_custom_orders_table_enabled','woocommerce_custom_orders_table_data_sync_enabled','woocommerce_feature_custom_order_tables_enabled') ORDER BY option_name"); then
            while IFS=$'\t' read -r a b; do
                [[ -n $a ]] || continue
                dbtune_audit_scope_put "$dbout" "$scope" "hpos.$(dbtune_audit_slug "$a")" "$b"
            done <<<"$rows"
        else
            dbtune_audit_scope_put "$dbout" "$scope" hpos.status unknown
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.hpos query_failed
        fi
        if rows=$(dbtune_audit_sql "SELECT COUNT(*), COALESCE(SUM(LENGTH(option_value)),0) FROM $dbq.$tableq WHERE option_name LIKE '\\_transient%'"); then
            IFS=$'\t' read -r a b <<<"${rows%%$'\n'*}"
            if [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]]; then
                dbtune_audit_scope_put "$dbout" "$scope" transient_count "$a"
                dbtune_audit_scope_put "$dbout" "$scope" transient_bytes "$b"
            else
                dbtune_audit_scope_put "$dbout" "$scope" transient_count unknown
                dbtune_audit_scope_put "$dbout" "$scope" transient_bytes unknown
                dbtune_audit_scope_put "$dbout" "$scope" audit_error.transients invalid_result
            fi
        else
            dbtune_audit_scope_put "$dbout" "$scope" transient_count unknown
            dbtune_audit_scope_put "$dbout" "$scope" transient_bytes unknown
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.transients query_failed
        fi
    else
        probe_status=$?
        if ((probe_status == 2)); then
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.options_table probe_failed
        else
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.options_table missing
        fi
        dbtune_audit_scope_put "$dbout" "$scope" autoload_bytes unknown
        dbtune_audit_scope_put "$dbout" "$scope" transient_count unknown
    fi

    for table_name in "${prefix}wc_orders" "${prefix}woocommerce_sessions"; do
        key=$(dbtune_audit_slug "${table_name#"$prefix"}")
        if dbtune_audit_table_exists "$database" "$table_name"; then
            if rows=$(dbtune_audit_sql "SELECT COALESCE(TABLE_ROWS,0) FROM information_schema.TABLES WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") AND TABLE_NAME=$(dbtune_sql_quote_literal "$table_name")"); then
                rows=${rows%%$'\n'*}
                [[ $rows =~ ^[0-9]+$ ]] || rows=unknown
                dbtune_audit_scope_put "$dbout" "$scope" "${key}_count" "$rows"
                dbtune_audit_scope_put "$dbout" "$scope" "${key}_count_accuracy" estimated
                [[ $rows != unknown ]] || dbtune_audit_scope_put "$dbout" "$scope" "audit_error.${key}_count" invalid_result
            else
                dbtune_audit_scope_put "$dbout" "$scope" "${key}_count" unknown
                dbtune_audit_scope_put "$dbout" "$scope" "audit_error.${key}_count" query_failed
            fi
        else
            probe_status=$?
            ((probe_status != 2)) || dbtune_audit_scope_put "$dbout" "$scope" "audit_error.${key}_probe" query_failed
        fi
    done

    if dbtune_audit_table_exists "$database" "${prefix}posts"; then
        tableq=$(dbtune_sql_quote_identifier "${prefix}posts") || return 0
        if rows=$(dbtune_audit_sql "SELECT COUNT(*) FROM $dbq.$tableq WHERE post_type LIKE 'shop_order%'"); then
            rows=${rows%%$'\n'*}
            [[ $rows =~ ^[0-9]+$ ]] || rows=unknown
            dbtune_audit_scope_put "$dbout" "$scope" legacy_order_count "$rows"
            [[ $rows != unknown ]] || dbtune_audit_scope_put "$dbout" "$scope" audit_error.legacy_orders invalid_result
        else
            dbtune_audit_scope_put "$dbout" "$scope" legacy_order_count unknown
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.legacy_orders query_failed
        fi
    fi
    if dbtune_audit_table_exists "$database" "${prefix}actionscheduler_actions"; then
        tableq=$(dbtune_sql_quote_identifier "${prefix}actionscheduler_actions") || return 0
        if rows=$(dbtune_audit_sql "SELECT status, COUNT(*) FROM $dbq.$tableq GROUP BY status ORDER BY status"); then
            while IFS=$'\t' read -r a b; do
                [[ -n $a ]] || continue
                dbtune_audit_scope_put "$dbout" "$scope" "action_scheduler.$(dbtune_audit_slug "$a")" "${b:-unknown}"
            done <<<"$rows"
        else
            dbtune_audit_scope_put "$dbout" "$scope" action_scheduler.status unknown
            dbtune_audit_scope_put "$dbout" "$scope" audit_error.action_scheduler query_failed
        fi
    fi

    if ! rows=$(dbtune_audit_sql "SELECT TABLE_NAME, COALESCE(TABLE_ROWS,0), DATA_LENGTH+INDEX_LENGTH, ROUND((DATA_LENGTH+INDEX_LENGTH)/NULLIF(TABLE_ROWS,0)/1024,1) FROM information_schema.TABLES WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") AND TABLE_NAME REGEXP 'log|history|track|event' ORDER BY DATA_LENGTH+INDEX_LENGTH DESC LIMIT 20"); then
        rows=''
        dbtune_audit_scope_put "$dbout" "$scope" audit_error.log_tables query_failed
    fi
    index=0
    while IFS=$'\t' read -r a b c d; do
        [[ -n $a ]] || continue
        dbtune_audit_scope_put "$dbout" "$scope" "log_table.$index" "$a:${b:-unknown}:${c:-unknown}:${d:-unknown}"
        index=$(command awk -v n="$index" 'BEGIN { print n+1 }')
    done <<<"$rows"

    if ! rows=$(dbtune_audit_sql "SELECT INDEX_NAME, GROUP_CONCAT(CONCAT(COLUMN_NAME,IFNULL(CONCAT('(',SUB_PART,')'),'')) ORDER BY SEQ_IN_INDEX) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") AND TABLE_NAME=$(dbtune_sql_quote_literal "${prefix}postmeta") GROUP BY INDEX_NAME ORDER BY INDEX_NAME"); then
        rows=''
        dbtune_audit_scope_put "$dbout" "$scope" audit_error.postmeta_indexes query_failed
    fi
    index=0
    while IFS=$'\t' read -r a b; do
        [[ -n $a ]] || continue
        dbtune_audit_scope_put "$dbout" "$scope" "postmeta.index.$index" "$a:$b"
        if [[ $b == meta_value || $b == meta_value\(* ]]; then
            dbtune_audit_scope_put "$dbout" "$scope" rogue_meta_value_index "$a"
        fi
        index=$(command awk -v n="$index" 'BEGIN { print n+1 }')
    done <<<"$rows"

    if ! rows=$(dbtune_audit_sql "SELECT TABLE_NAME, COALESCE(TABLE_ROWS,0), DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES WHERE TABLE_SCHEMA=$(dbtune_sql_quote_literal "$database") ORDER BY DATA_LENGTH+INDEX_LENGTH DESC LIMIT 10"); then
        rows=''
        dbtune_audit_scope_put "$dbout" "$scope" audit_error.top_tables query_failed
    fi
    index=0
    while IFS=$'\t' read -r a b c; do
        [[ -n $a ]] || continue
        dbtune_audit_scope_put "$dbout" "$scope" "top_table.$index" "$a:${b:-unknown}:${c:-unknown}"
        index=$(command awk -v n="$index" 'BEGIN { print n+1 }')
    done <<<"$rows"
}

dbtune_audit_app_cron_status() {
    local app=${1:-}
    local app_root=${2:-}
    local site_url=${3:-unknown}
    local cron_root=${DBTUNE_CRON_ROOT:-/etc/cron.d}
    local crontab_file=${DBTUNE_CRONTAB_FILE:-/etc/crontab}
    local line candidates=0 site_base=${site_url%/}

    while IFS= read -r line; do
        [[ $line =~ ^[[:space:]]*# ]] && continue
        candidates=1
        if [[ $line == *"$app_root/"* || $line == *"$app_root "* || $line == *"$app/"* || $line == *"$app "* ]] ||
            [[ $site_base != unknown && -n $site_base && ($line == *"$site_base/"* || $line == *"$site_base "*) ]]; then
            printf '1\n'
            return 0
        fi
    done < <(command grep -RhsE 'wp-cron\.php|wp cron event run' "$cron_root" "$crontab_file" 2>/dev/null || true)
    if ((candidates)); then
        printf 'unknown\n'
    else
        printf '0\n'
    fi
}

dbtune_audit_collect_apps() {
    local out=${1:-}
    local appout=${2:-}
    local dbout=${3:-}
    local home_root=${DBTUNE_HOME_ROOT:-/home}
    local user_dir app config app_root app_id app_index=0 type key value db_name='' prefix='' disable_cron=unresolved
    local redis_active=0 redis_ping=0 woo object_cache page_cache wp_cache=unresolved
    local multisite=false cron_status site_url optionsq dbq
    local -a databases=()

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet redis-server 2>/dev/null; then
        redis_active=1
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet redis 2>/dev/null; then
        redis_active=1
    fi
    if command -v redis-cli >/dev/null 2>&1 && [[ $(redis-cli ping 2>/dev/null || true) == PONG ]]; then
        redis_ping=1
    fi
    dbtune_audit_put "$out" app.redis_service_active "$redis_active"
    dbtune_audit_put "$out" app.redis_ping "$redis_ping"
    dbtune_audit_put "$out" app.system_wp_cron unknown
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
            multisite=false
            wp_cache=unresolved
            if [[ -n $config ]]; then
                while IFS=$'\t' read -r key value; do
                    case $key in
                        DB_NAME) db_name=$value ;;
                        table_prefix) prefix=$value ;;
                        DISABLE_WP_CRON) disable_cron=$value ;;
                        MULTISITE) multisite=$value ;;
                        WP_CACHE) wp_cache=$value ;;
                    esac
                done < <(dbtune_wp_config_parse "$config")
            fi
            [[ -n $db_name ]] || db_name=unresolved
            [[ -n $prefix ]] || prefix=unresolved
            site_url=unknown
            if [[ $db_name != unresolved && $prefix != unresolved && $prefix =~ ^[A-Za-z0-9_]+$ ]]; then
                dbq=$(dbtune_sql_quote_identifier "$db_name" || true)
                optionsq=$(dbtune_sql_quote_identifier "${prefix}options" || true)
                if [[ -n $dbq && -n $optionsq ]] && value=$(dbtune_audit_sql "SELECT option_value FROM $dbq.$optionsq WHERE option_name IN ('home','siteurl') ORDER BY option_name LIMIT 2"); then
                    site_url=${value%%$'\n'*}
                    [[ -n $site_url ]] || site_url=unknown
                fi
            fi
            cron_status=$(dbtune_audit_app_cron_status "$app" "$app_root" "$site_url")
            dbtune_audit_scope_put "$appout" "$app_id" database "${db_name:-unresolved}"
            dbtune_audit_scope_put "$appout" "$app_id" table_prefix "$prefix"
            dbtune_audit_scope_put "$appout" "$app_id" disable_wp_cron "$disable_cron"
            dbtune_audit_scope_put "$appout" "$app_id" system_wp_cron "$cron_status"
            if [[ $site_url == unknown ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" site_url_status unresolved
            else
                dbtune_audit_scope_put "$appout" "$app_id" site_url_status resolved
            fi
            dbtune_audit_scope_put "$appout" "$app_id" multisite "$multisite"

            object_cache=0
            page_cache=0
            woo=0
            [[ -f $app_root/wp-content/object-cache.php ]] && object_cache=1
            [[ -f $app_root/wp-content/advanced-cache.php ]] && page_cache=1
            [[ -f $app_root/wp-content/plugins/woocommerce/woocommerce.php ]] && woo=1
            if [[ $woo == 0 && $db_name != unresolved && $prefix != unresolved ]] &&
                dbtune_audit_table_exists "$db_name" "${prefix}woocommerce_sessions"; then
                woo=1
            fi
            if [[ $wp_cache == true ]]; then
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
            if [[ $disable_cron == true && $cron_status == 0 ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" finding.wp_cron_disabled critical
            elif [[ $disable_cron == true && $cron_status == unknown ]]; then
                dbtune_audit_scope_put "$appout" "$app_id" finding.wp_cron_mapping_unknown warning
            fi
            if [[ $db_name != unresolved && $prefix != unresolved ]]; then
                if [[ $multisite == true ]]; then
                    dbtune_audit_scope_put "$appout" "$app_id" multisite_metrics unsupported
                    dbtune_audit_scope_put "$appout" "$app_id" finding.multisite_metrics_unknown warning
                elif [[ $multisite == unresolved ]]; then
                    dbtune_audit_scope_put "$appout" "$app_id" multisite_metrics unknown
                    dbtune_audit_scope_put "$appout" "$app_id" finding.multisite_metrics_unknown warning
                else
                    databases+=("$app_id"$'\t'"$db_name"$'\t'"$prefix")
                fi
                dbtune_audit_scope_put "$dbout" "$db_name" "app_id.${app_id##*.}" "$app_id"
            else
                [[ $db_name != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" finding.database_unresolved warning
                [[ $prefix != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" finding.table_prefix_unresolved warning
            fi
        done
    done
    dbtune_audit_put "$out" app.count "$app_index"

    if ((${#databases[@]})); then
        while IFS=$'\t' read -r app_id db_name prefix; do
            dbtune_audit_database_metrics "$dbout" "$app_id" "$db_name" "$prefix" || {
                dbtune_audit_scope_put "$dbout" "$app_id" audit_error.metrics query_failed
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
    local -A json_seen=()

    while IFS=$'\t' read -r key value; do
        [[ -n $key && -z ${json_seen[$key]+x} ]] || continue
        json_seen["$key"]=1
        fields+=("$key" "$value")
    done <"$audit"
    while IFS=$'\t' read -r scope key value; do
        [[ -n $scope && -n $key ]] || continue
        key="$scope.$key"
        [[ -z ${json_seen[$key]+x} ]] || continue
        json_seen["$key"]=1
        fields+=("$key" "$value")
    done <"$apps"
    while IFS=$'\t' read -r scope key value; do
        [[ -n $scope && -n $key ]] || continue
        key="database.$(dbtune_audit_slug "$scope").$key"
        [[ -z ${json_seen[$key]+x} ]] || continue
        json_seen["$key"]=1
        fields+=("$key" "$value")
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
    local json=0 argument scratch audit apps databases manifest version
    local run_id old_run_id archive='' current_manifest audit_hash

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
    manifest="$scratch/audit-manifest.tsv"
    : >"$audit"
    : >"$apps"
    : >"$databases"
    chmod 600 "$audit" "$apps" "$databases"

    run_id=$(dbtune_run_id) || {
        rm -rf "$scratch"
        return 1
    }
    dbtune_audit_put "$audit" audit.run_id "$run_id"
    dbtune_audit_put "$audit" audit.timestamp "$(dbtune_now)"
    dbtune_audit_put "$audit" audit.hostname "$(hostname 2>/dev/null || printf unknown)"
    dbtune_audit_put "$audit" audit.sql_connect_timeout_seconds "${DBTUNE_SQL_CONNECT_TIMEOUT:-5}"
    dbtune_audit_put "$audit" audit.sql_statement_timeout_seconds "${DBTUNE_AUDIT_QUERY_TIMEOUT_SECONDS:-5}"
    dbtune_audit_put "$audit" audit.exact_full_table_counts disabled
    dbtune_audit_collect_mariadb "$audit" "$databases"
    dbtune_audit_collect_hw "$audit"
    dbtune_audit_collect_platform "$audit"
    dbtune_audit_collect_apps "$audit" "$apps" "$databases"
    version=$(command awk -F '\t' '$1=="mariadb.version" { print $2; exit }' "$audit")
    dbtune_audit_add_findings "$audit" "${version:-0}"

    dbtune_provenance_write_audit_manifest "$manifest" "$run_id" "$audit" "$apps" "$databases" || {
        rm -rf "$scratch"
        dbtune_log error "Audit provenance sa nepodarilo vytvorit"
        return 1
    }
    current_manifest=$(dbtune_audit_manifest_file) || {
        rm -rf "$scratch"
        return 1
    }
    old_run_id=$(dbtune_manifest_value "$current_manifest" run_id 2>/dev/null || printf 'legacy-%s' "$$")
    archive=$(dbtune_cycle_archive "$old_run_id") || {
        rm -rf "$scratch"
        dbtune_log error "Predchadzajuci meraci cyklus sa nepodarilo archivovat"
        return 1
    }

    if ! dbtune_atomic_write "$DBTUNE_STATE_DIR/audit.tsv" 600 <"$audit" ||
        ! dbtune_atomic_write "$DBTUNE_STATE_DIR/apps.tsv" 600 <"$apps" ||
        ! dbtune_atomic_write "$DBTUNE_STATE_DIR/databases.tsv" 600 <"$databases" ||
        ! dbtune_atomic_write "$current_manifest" 600 <"$manifest"; then
        rm -rf "$scratch"
        dbtune_log error "Audit data sa nepodarilo atomicky zapisat"
        return 1
    fi
    rm -rf "$scratch"
    dbtune_cycle_invalidate_downstream || return
    dbtune_state_record_audit "$run_id" "$archive" || return
    audit_hash=$(dbtune_manifest_value "$current_manifest" audit_hash) || return
    dbtune_event audit_completed run_id "$run_id" audit_hash "$audit_hash" || true

    if ((json)); then
        dbtune_audit_json "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    else
        dbtune_audit_summary "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    fi
}
