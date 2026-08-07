# shellcheck shell=bash

dbtune_audit_clean() {
    dbtune_redact "${1-}"
}

dbtune_audit_put() {
    local file=${1:-}
    local key=${2:-}
    local value=${3-}

    [[ -n $file && $key =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 64
    if dbtune_is_sensitive_key "$key"; then
        value='[REDACTED]'
    fi
    printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")" >>"$file"
}

dbtune_audit_scope_put() {
    local file=${1:-}
    local scope=${2:-}
    local key=${3:-}
    local value=${4-}

    [[ -n $file && -n $scope && $scope != *$'\t'* && $scope != *$'\n'* ]] || return 64
    [[ $key =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 64
    if dbtune_is_sensitive_key "$key"; then
        value='[REDACTED]'
    fi
    printf '%s\t%s\t%s\n' "$(dbtune_audit_clean "$scope")" "$key" "$(dbtune_audit_clean "$value")" >>"$file"
}

dbtune_audit_normalize_in_place() {
    local file=${1:-}
    local temporary

    [[ -r $file ]] || return 66
    temporary=$(mktemp "$file.normalized.XXXXXX") || return 1
    if ! chmod 600 "$temporary" || ! dbtune_audit_normalize "$file" >"$temporary" || ! mv -f "$temporary" "$file"; then
        rm -f "$temporary"
        return 65
    fi
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
    local quote char output='' index=0 length escape closed

    expression=${expression#"${expression%%[![:space:]]*}"}
    expression=${expression%"${expression##*[![:space:]]}"}
    if [[ $expression =~ ^(true|TRUE)$ ]]; then
        printf 'true'
        return 0
    fi
    if [[ $expression =~ ^(false|FALSE)$ ]]; then
        printf 'false'
        return 0
    fi

    length=${#expression}
    while ((index < length)); do
        while ((index < length)) && [[ ${expression:index:1} == [[:space:]] ]]; do
            index=$((index + 1))
        done
        quote=${expression:index:1}
        [[ $quote == "'" || $quote == '"' ]] || return 1
        index=$((index + 1))
        escape=0
        closed=0
        while ((index < length)); do
            char=${expression:index:1}
            index=$((index + 1))
            if ((escape)); then
                output+=$char
                escape=0
            elif [[ $char == \\ ]]; then
                output+=$char
                escape=1
            elif [[ $quote == '"' && $char == '$' ]]; then
                return 1
            elif [[ $char == "$quote" ]]; then
                closed=1
                break
            else
                output+=$char
            fi
        done
        ((closed)) || return 1
        while ((index < length)) && [[ ${expression:index:1} == [[:space:]] ]]; do
            index=$((index + 1))
        done
        if ((index == length)); then
            printf '%s' "$output"
            return 0
        fi
        [[ ${expression:index:1} == . ]] || return 1
        index=$((index + 1))
    done
    return 1
}

dbtune_wp_config_code() {
    local file=${1:-}

    [[ -r $file ]] || return 1
    command awk '
        function emit_statement(    start, candidate, position) {
            start=0
            if (match(mask, /(^|[^[:alnum:]_])define[[:space:]]*\(/)) {
                candidate=substr(mask, RSTART, RLENGTH)
                start=RSTART+index(candidate, "define")-1
            }
            if (match(mask, /(^|[^[:alnum:]_])const[[:space:]]+/)) {
                candidate=substr(mask, RSTART, RLENGTH)
                position=RSTART+index(candidate, "const")-1
                if (start==0 || position<start) start=position
            }
            if (match(mask, /\$table_prefix[[:space:]]*=/)) {
                if (start==0 || RSTART<start) start=RSTART
            }
            if (start>0) print substr(statement, start)
            statement=""; mask=""
        }
        BEGIN { quote=""; block=0; escape=0; statement=""; mask=""; php=0 }
        {
            line=$0; sub(/\r$/, "", line); line_comment=0
            for (i=1; i<=length(line); i++) {
                char=substr(line,i,1); next_char=substr(line,i+1,1)
                if (!php) {
                    if (substr(line,i,5)=="<?php") { php=1; statement=""; mask=""; i+=4 }
                    continue
                }
                if (line_comment) break
                if (block) {
                    if (char=="*" && next_char=="/") { block=0; statement=statement " "; mask=mask " "; i++ }
                    continue
                }
                if (quote != "") {
                    statement=statement char
                    mask=mask " "
                    if (escape) escape=0
                    else if (char=="\\") escape=1
                    else if (char==quote) quote=""
                    continue
                }
                if (substr(line,i,5)=="<?php") { statement=""; mask=""; i+=4; continue }
                if (char=="?" && next_char==">") { php=0; statement=""; mask=""; i++; continue }
                if (char=="\"" || char=="\047") { quote=char; statement=statement char; mask=mask " "; continue }
                if (char=="/" && next_char=="*") { block=1; i++; continue }
                if (char=="/" && next_char=="/") { line_comment=1; continue }
                if (char=="#") { line_comment=1; continue }
                statement=statement char
                mask=mask char
                if (char==";") emit_statement()
            }
            if (php) { statement=statement " "; mask=mask " " }
        }
    ' "$file"
}

dbtune_wp_config_parse() {
    local file=${1:-}
    local statement key expression value

    [[ -r $file ]] || return 1
    while IFS= read -r statement || [[ -n $statement ]]; do
        if [[ $statement =~ ^define[[:space:]]*\([[:space:]]*[\'\"](DB_NAME|DISABLE_WP_CRON|MULTISITE|WP_CACHE)[\'\"][[:space:]]*,[[:space:]]*(.*)\)[[:space:]]*\;[[:space:]]*$ ]]; then
            key=${BASH_REMATCH[1]}
            expression=${BASH_REMATCH[2]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")"
            else
                printf '%s\t%s\n' "$key" unresolved
            fi
        elif [[ $statement =~ ^const[[:space:]]+(DB_NAME|DISABLE_WP_CRON|MULTISITE|WP_CACHE)[[:space:]]*=[[:space:]]*(.*)\;[[:space:]]*$ ]]; then
            key=${BASH_REMATCH[1]}
            expression=${BASH_REMATCH[2]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf '%s\t%s\n' "$key" "$(dbtune_audit_clean "$value")"
            else
                printf '%s\t%s\n' "$key" unresolved
            fi
        elif [[ $statement =~ ^\$table_prefix[[:space:]]*=[[:space:]]*(.*)\;[[:space:]]*$ ]]; then
            expression=${BASH_REMATCH[1]}
            if value=$(dbtune_wp_config_value "$expression"); then
                printf 'table_prefix\t%s\n' "$(dbtune_audit_clean "$value")"
            else
                printf 'table_prefix\tunresolved\n'
            fi
        fi
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

dbtune_audit_verified_wp_root() {
    local app=${1:-}
    local candidate candidate_root root=''

    [[ $app == /* && $app != *$'\n'* && $app != *$'\r'* && $app != *$'\t'* ]] || return 1
    for candidate in "$app" "$app/htdocs" "$app/public"; do
        [[ -f $candidate/wp-load.php ]] || continue
        candidate_root=$(cd -P -- "$candidate" 2>/dev/null && pwd -P) || continue
        [[ $candidate_root == /* && $candidate_root != *$'\n'* && $candidate_root != *$'\r'* && $candidate_root != *$'\t'* ]] || continue
        [[ -f $candidate_root/wp-load.php ]] || continue
        [[ -z $root || $root == "$candidate_root" ]] || return 1
        root=$candidate_root
    done
    [[ -n $root ]] || return 1
    printf '%s\n' "$root"
}

dbtune_audit_path_uid() {
    local path=${1:-}
    local uid

    uid=$(stat -c '%u' -- "$path" 2>/dev/null) || uid=$(stat -f '%u' "$path" 2>/dev/null) || return 1
    [[ $uid =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$uid"
}

dbtune_audit_user_for_uid() {
    command id -nu "${1:-}" 2>/dev/null
}

dbtune_audit_uid_for_user() {
    command id -u "${1:-}" 2>/dev/null
}

dbtune_audit_verified_owner() {
    local root=${1:-}
    local uid owner verified_uid

    uid=$(dbtune_audit_path_uid "$root") || return 1
    [[ $uid =~ ^[0-9]+$ ]] || return 1
    ((10#$uid > 0)) || return 1
    owner=$(dbtune_audit_user_for_uid "$uid") || return 1
    [[ $owner =~ ^[A-Za-z_][A-Za-z0-9_-]*$ && $owner != root ]] || return 1
    verified_uid=$(dbtune_audit_uid_for_user "$owner") || return 1
    [[ $verified_uid =~ ^[0-9]+$ ]] || return 1
    ((10#$verified_uid == 10#$uid)) || return 1
    printf '%s\n' "$owner"
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

dbtune_audit_effective_variables() {
    dbtune_audit_mariadb_evidence_schema | command awk -F '\t' '
        $4=="proposal" && $1 ~ /^mariadb[.]variable[.]/ {
            sub(/^mariadb[.]variable[.]/, "", $1)
            print $1
        }
    '
}

dbtune_audit_mariadb_variables() {
    dbtune_audit_mariadb_evidence_schema | command awk -F '\t' '
        $1 ~ /^mariadb[.]variable[.]/ {
            sub(/^mariadb[.]variable[.]/, "", $1)
            print $1
        }
    '
}

dbtune_audit_mariadb_evidence_schema() {
    cat <<'SCHEMA'
mariadb.version	version	all	input
mariadb.dataset_bytes	uint	all	input
mariadb.variable.innodb_buffer_pool_size	positive_uint	all	proposal
mariadb.variable.max_connections	positive_uint	all	proposal
mariadb.variable.innodb_io_capacity	positive_uint	all	proposal
mariadb.variable.innodb_io_capacity_max	positive_uint	all	proposal
mariadb.variable.innodb_read_io_threads	positive_uint	all	proposal
mariadb.variable.innodb_write_io_threads	positive_uint	all	proposal
mariadb.variable.innodb_flush_neighbors	bool	all	proposal
mariadb.variable.innodb_log_file_size	positive_uint	all	proposal
mariadb.variable.innodb_log_buffer_size	positive_uint	all	proposal
mariadb.variable.query_cache_type	query_cache_type	all	proposal
mariadb.variable.query_cache_size	uint	all	proposal
mariadb.variable.innodb_flush_log_at_trx_commit	trx_commit	all	proposal
mariadb.variable.innodb_doublewrite	bool	all	proposal
mariadb.variable.innodb_flush_method	flush_method	pre11	proposal
mariadb.variable.innodb_buffer_pool_dump_at_shutdown	bool	all	proposal
mariadb.variable.innodb_buffer_pool_load_at_startup	bool	all	proposal
mariadb.variable.innodb_max_dirty_pages_pct	percent	all	proposal
mariadb.variable.innodb_max_dirty_pages_pct_lwm	percent	all	proposal
mariadb.variable.innodb_lock_wait_timeout	uint	all	proposal
mariadb.variable.skip_name_resolve	bool	all	proposal
mariadb.variable.thread_cache_size	uint	all	proposal
mariadb.variable.tmp_table_size	positive_uint	all	proposal
mariadb.variable.max_heap_table_size	positive_uint	all	proposal
mariadb.variable.table_definition_cache	positive_uint	all	proposal
mariadb.variable.key_buffer_size	uint	all	proposal
mariadb.variable.slow_query_log	bool	all	proposal
mariadb.variable.slow_query_log_file	text	all	proposal
mariadb.variable.long_query_time	decimal	all	proposal
mariadb.variable.log_slow_verbosity	verbosity	all	proposal
mariadb.variable.datadir	absolute_path	all	input
mariadb.variable.open_files_limit	positive_uint	all	input
mariadb.variable.performance_schema	bool	all	input
mariadb.variable.log_bin	bool	all	input
mariadb.variable.wsrep_on	bool	all	input
mariadb.variable.bind_address	bind_address	all	input
mariadb.status.uptime	uint	all	input
mariadb.status.max_used_connections	uint	all	input
mariadb.status.key_read_requests	uint	all	input
SCHEMA
}

dbtune_audit_mariadb_version_family() {
    local version=${1:-}
    local major minor

    version=${version%%-*}
    IFS=. read -r major minor _ <<<"$version"
    if [[ ! $major =~ ^[0-9]+$ || ! $minor =~ ^[0-9]+$ ]]; then
        printf 'unsupported\n'
    elif ((10#$major == 11)); then
        printf '11.x\n'
    elif ((10#$major == 10 && 10#$minor == 11)); then
        printf '10.11\n'
    elif ((10#$major == 10 && 10#$minor == 6)); then
        printf '10.6\n'
    else
        printf 'unsupported\n'
    fi
}

dbtune_audit_mariadb_evidence_valid() {
    local validator=${1:-}
    local value=${2-}
    local upper=${value^^}

    DBTUNE_AUDIT_EVIDENCE_ERROR=malformed
    if [[ ${value,,} == unknown || ${value,,} == unresolved ]]; then
        DBTUNE_AUDIT_EVIDENCE_ERROR=unknown
        return 1
    fi
    case $validator in
        version)
            [[ $value =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([_-][A-Za-z0-9._-]+)*$ ]] || return 1
            [[ $(dbtune_audit_mariadb_version_family "$value") != unsupported ]] || {
                DBTUNE_AUDIT_EVIDENCE_ERROR=unsupported
                return 1
            }
            ;;
        uint) [[ $value =~ ^[0-9]+$ ]] || return 1 ;;
        positive_uint) [[ $value =~ ^[1-9][0-9]*$ ]] || return 1 ;;
        decimal) [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1 ;;
        percent)
            [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
            command awk -v value="$value" 'BEGIN {exit !(value >= 0 && value <= 100)}' || return 1
            ;;
        bool) [[ $upper == 0 || $upper == 1 || $upper == OFF || $upper == ON ]] || return 1 ;;
        query_cache_type) [[ $upper == 0 || $upper == 1 || $upper == 2 || $upper == OFF || $upper == ON || $upper == DEMAND ]] || return 1 ;;
        trx_commit) [[ $value == 0 || $value == 1 || $value == 2 ]] || return 1 ;;
        flush_method) [[ $upper =~ ^(FSYNC|O_DSYNC|LITTLESYNC|NOSYNC|O_DIRECT|O_DIRECT_NO_FSYNC|ALL_O_DIRECT)$ ]] || return 1 ;;
        absolute_path) [[ $value == /* && $value != *[[:space:]]* ]] || return 1 ;;
        text) [[ -n $value ]] || return 1 ;;
        verbosity) [[ $value =~ ^[A-Za-z0-9_,[:space:]-]*$ ]] || return 1 ;;
        bind_address) [[ -z $value || $value =~ ^[A-Za-z0-9:.*,_/-]+$ ]] || return 1 ;;
        *) return 1 ;;
    esac
    DBTUNE_AUDIT_EVIDENCE_ERROR=none
}

dbtune_audit_quarantine_mariadb_conflicts() {
    local file=${1:-}
    local raw_key value rest canonical key _validator _requirement _role temporary conflict_list=''
    local conflict_count=0
    local -A schema=() seen=() values=() conflicts=()

    [[ -r $file ]] || return 66
    while IFS=$'\t' read -r key _validator _requirement _role; do
        [[ -n $key ]] && schema["$key"]=1
    done < <(dbtune_audit_mariadb_evidence_schema)
    while IFS=$'\t' read -r raw_key value rest || [[ -n ${raw_key:-} ]]; do
        [[ -n $raw_key ]] || continue
        canonical=$(dbtune_audit_key_canonical "$raw_key") || return
        [[ -n ${schema[$canonical]+x} ]] || continue
        if [[ -n ${seen[$canonical]+x} && ${values[$canonical]} != "$value" ]]; then
            if [[ -z ${conflicts[$canonical]+x} ]]; then
                conflicts["$canonical"]=1
                conflict_count=$((conflict_count + 1))
            fi
        else
            seen["$canonical"]=1
            values["$canonical"]=$value
        fi
    done <"$file"
    ((conflict_count > 0)) || return 0

    temporary=$(mktemp "$file.evidence.XXXXXX") || return 1
    chmod 600 "$temporary" || {
        rm -f "$temporary"
        return 1
    }
    while IFS=$'\t' read -r raw_key value rest || [[ -n ${raw_key:-} ]]; do
        [[ -n $raw_key ]] || continue
        canonical=$(dbtune_audit_key_canonical "$raw_key") || {
            rm -f "$temporary"
            return 1
        }
        [[ -n ${conflicts[$canonical]+x} ]] && continue
        printf '%s\t%s\n' "$raw_key" "$value" >>"$temporary"
    done <"$file"
    while IFS=$'\t' read -r key _validator _requirement _role; do
        [[ -n ${conflicts[$key]+x} ]] || continue
        conflict_list+="${conflict_list:+,}$key"
    done < <(dbtune_audit_mariadb_evidence_schema)
    printf 'audit.mariadb_evidence_conflicts\t%s\n' "$conflict_list" >>"$temporary"
    mv -f "$temporary" "$file"
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
    local variables status validated_status comparison dataset_ok=0

    if ! version=$(dbtune_audit_sql 'SELECT VERSION()'); then
        dbtune_audit_put "$out" mariadb.available 0
        dbtune_audit_put "$out" finding.mariadb_unavailable warning
        return 0
    fi
    version=${version%%$'\n'*}
    dbtune_audit_put "$out" mariadb.available 1
    dbtune_audit_put "$out" mariadb.version "$version"

    variables=$(dbtune_audit_mariadb_variables | command awk '
        BEGIN { separator="" }
        /^[a-z][a-z0-9_]*$/ { printf "%s\047%s\047", separator, toupper($0); separator="," }
        END { print "" }
    ')
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
    if validated_status=$(dbtune_status_snapshot_exact "$rows" \
        aborted_connects com_select created_tmp_disk_tables created_tmp_tables handler_read_rnd_next \
        innodb_buffer_pool_pages_data innodb_buffer_pool_pages_free innodb_buffer_pool_read_requests \
        innodb_buffer_pool_reads innodb_buffer_pool_wait_free innodb_data_read innodb_log_waits \
        key_read_requests max_used_connections qcache_hits questions slow_queries threads_connected \
        threads_running uptime); then
        while IFS=$'\t' read -r name value; do
            key=$(dbtune_audit_slug "$name")
            dbtune_audit_put "$out" "mariadb.status.$key" "$value"
            case $key in
                qcache_hits) qcache_hits=$value ;;
                com_select) com_select=$value ;;
            esac
        done <<<"$validated_status"
    else
        dbtune_audit_put "$out" finding.global_status_query_failed warning
    fi
    if dbtune_uint64_valid "$qcache_hits" && dbtune_uint64_valid "$com_select" && [[ $com_select != 0 ]]; then
        comparison=$(dbtune_uint64_compare "$qcache_hits" "$com_select") || comparison=1
        if ((comparison <= 0)); then
            hit_rate=$(command awk -v h="$qcache_hits" -v s="$com_select" 'BEGIN { printf "%.2f", 100*h/s }')
        fi
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
                dbtune_is_sensitive_key "$a" && a='[REDACTED]'
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

dbtune_audit_finalize_app_statuses() {
    local appout=${1:-}
    local dbout=${2:-}
    local records

    [[ -r $appout && -r $dbout ]] || return 66
    records=$(awk -F '\t' '
        function remember(scope) {
            if (!(scope in seen)) {
                seen[scope] = 1
                scopes[++count] = scope
            }
        }
        function add_error(scope, key, value, entry) {
            remember(scope)
            entry = key "=" value
            errors[scope] = errors[scope] (errors[scope] == "" ? "" : ",") entry
            if (key == "audit_error.wp_config") failed[scope] = 1
        }
        FNR == NR {
            remember($1)
            if ($2 ~ /^audit_error\./) add_error($1, $2, $3)
            next
        }
        $2 ~ /^audit_error\./ { add_error($1, $2, $3) }
        END {
            OFS = "\t"
            for (i = 1; i <= count; i++) {
                scope = scopes[i]
                status = failed[scope] ? "failed" : (errors[scope] != "" ? "partial" : "complete")
                print scope, "audit_status", status
                print scope, "source_error", (errors[scope] == "" ? "none" : errors[scope])
            }
        }
    ' "$appout" "$dbout") || return
    if [[ -n $records ]]; then
        printf '%s\n' "$records" >>"$appout"
    fi
    return 0
}

dbtune_audit_collect_apps() {
    local out=${1:-}
    local appout=${2:-}
    local dbout=${3:-}
    local home_root=${DBTUNE_HOME_ROOT:-/home}
    local user_dir app config app_root wp_root owner app_id app_index=0 type key value db_name='' prefix='' disable_cron=unresolved
    local redis_active=0 redis_ping=0 woo object_cache page_cache wp_cache=unresolved
    local multisite=false cron_status site_url optionsq dbq site_url_query
    local -a databases=()

    if [[ ! -d $home_root || ! -r $home_root || ! -x $home_root ]]; then
        dbtune_audit_put "$out" app.discovery_status failed
        dbtune_audit_put "$out" app.count 0
        return 0
    fi
    dbtune_audit_put "$out" app.discovery_status complete

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
            wp_root=$(dbtune_audit_verified_wp_root "$app" || true)
            owner=''
            if [[ -n $wp_root ]]; then
                app_root=$wp_root
                owner=$(dbtune_audit_verified_owner "$wp_root" || true)
            fi
            dbtune_audit_scope_put "$appout" "$app_id" webroot "${wp_root:-unresolved}"
            dbtune_audit_scope_put "$appout" "$app_id" owner "${owner:-unresolved}"
            [[ -n $wp_root ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.wp_root unverified
            [[ -n $owner ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.owner unverified
            db_name=''
            prefix=''
            disable_cron=false
            multisite=false
            wp_cache=false
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
            else
                dbtune_audit_scope_put "$appout" "$app_id" audit_error.wp_config missing
            fi
            [[ -n $db_name ]] || db_name=unresolved
            [[ -n $prefix ]] || prefix=unresolved
            [[ $db_name != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.database unresolved
            [[ $prefix != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.table_prefix unresolved
            [[ $disable_cron != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.disable_wp_cron unresolved
            [[ $multisite != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.multisite unresolved
            [[ $wp_cache != unresolved ]] || dbtune_audit_scope_put "$appout" "$app_id" audit_error.wp_cache unresolved
            site_url=unknown
            if [[ $db_name != unresolved && $prefix != unresolved && $prefix =~ ^[A-Za-z0-9_]+$ ]]; then
                dbq=$(dbtune_sql_quote_identifier "$db_name" || true)
                optionsq=$(dbtune_sql_quote_identifier "${prefix}options" || true)
                site_url_query="SELECT option_value FROM $dbq.$optionsq WHERE option_name IN ('home','siteurl') ORDER BY option_name LIMIT 2"
                if [[ -n $dbq && -n $optionsq ]] && value=$(dbtune_audit_sql "$site_url_query"); then
                    site_url=${value%%$'\n'*}
                    [[ -n $site_url ]] || site_url=unknown
                else
                    dbtune_audit_scope_put "$appout" "$app_id" audit_error.site_url query_failed
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
    dbtune_audit_finalize_app_statuses "$appout" "$dbout"
}

dbtune_audit_collect_platform() {
    local out=${1:-}
    local runcloud=${DBTUNE_RUNCLOUD_CNF:-/etc/mysql/conf.d/runcloud.cnf}
    local key value limit=unknown fpm=0 backup=0 backup_schedules=0 listener=unknown
    local evidence backup_status=unknown backup_source=unknown backup_checked=unknown backup_success=unknown
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
    evidence=$(dbtune_backup_evidence_file)
    if dbtune_backup_evidence_validate "$evidence"; then
        backup_status=$(dbtune_manifest_value "$evidence" status)
        backup_source=$(dbtune_manifest_value "$evidence" source)
        backup_checked=$(dbtune_manifest_value "$evidence" checked_at)
        backup_success=$(dbtune_manifest_value "$evidence" last_success)
        dbtune_audit_put "$out" backup.evidence_file "$evidence"
    elif [[ -e $evidence || -L $evidence ]]; then
        dbtune_audit_put "$out" backup.evidence_error "${DBTUNE_BACKUP_EVIDENCE_ERROR:-invalid}"
    else
        dbtune_audit_put "$out" backup.evidence_error missing
    fi
    dbtune_audit_put "$out" backup.age_seconds "${DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS:-unknown}"
    dbtune_audit_put "$out" backup.max_age_seconds "${DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS:-${DBTUNE_MAX_BACKUP_AGE_SECONDS:-86400}}"
    dbtune_audit_put "$out" backup.status "$backup_status"
    dbtune_audit_put "$out" backup.source "$backup_source"
    dbtune_audit_put "$out" backup.checked_at "$backup_checked"
    dbtune_audit_put "$out" backup.last_success "$backup_success"

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

    dbtune_audit_collect_grants "$out"
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

dbtune_grant_host_classify() {
    local host=${1-}

    [[ -n $host && ${host^^} != NULL && $host != '\N' && ! $host =~ [[:cntrl:]] ]] || return 65
    command awk '
        function canonical_octet(value) {
            return value ~ /^(0|[1-9][0-9]{0,2})$/ && value + 0 <= 255
        }
        function ipv4(value, parts, count, i) {
            count = split(value, parts, ".")
            if (count != 4) return 0
            for (i = 1; i <= count; i++) if (!canonical_octet(parts[i])) return 0
            return 1
        }
        function ipv4_wildcard(value, prefix, parts, count, i) {
            if (value !~ /[.]%$/) return 0
            prefix = substr(value, 1, length(value) - 2)
            count = split(prefix, parts, ".")
            if (count < 1 || count > 3) return 0
            for (i = 1; i <= count; i++) if (!canonical_octet(parts[i])) return 0
            return 1
        }
        function contiguous_mask(value, parts, count, i, bit, octet, zero_seen) {
            if (!ipv4(value)) return 0
            count = split(value, parts, ".")
            for (i = 1; i <= count; i++) {
                octet = parts[i] + 0
                for (bit = 128; bit >= 1; bit /= 2) {
                    if (octet >= bit) {
                        if (zero_seen) return 0
                        octet -= bit
                    } else zero_seen = 1
                }
            }
            return 1
        }
        function ipv4_netmask(value, slash, address, mask) {
            slash = index(value, "/")
            if (!slash || index(substr(value, slash + 1), "/")) return 0
            address = substr(value, 1, slash - 1)
            mask = substr(value, slash + 1)
            return ipv4(address) && contiguous_mask(mask)
        }
        function hex_group(value) {
            return value ~ /^[[:xdigit:]]+$/ && length(value) <= 4
        }
        function ipv6(value, last_colon, tail, expanded, rest, double_at, left, right, groups, count, i, total) {
            if (value !~ /:/ || value ~ /[^[:xdigit:]:.]/) return 0
            if (value ~ /[.]/) {
                last_colon = 0
                for (i = 1; i <= length(value); i++) if (substr(value, i, 1) == ":") last_colon = i
                if (!last_colon) return 0
                tail = substr(value, last_colon + 1)
                if (!ipv4(tail)) return 0
                value = substr(value, 1, last_colon) "0:0"
            }
            double_at = index(value, "::")
            if (double_at) {
                rest = substr(value, double_at + 2)
                if (index(rest, "::")) return 0
                left = substr(value, 1, double_at - 1)
                right = rest
                total = 0
                if (left != "") {
                    count = split(left, groups, ":")
                    for (i = 1; i <= count; i++) if (!hex_group(groups[i])) return 0
                    total += count
                }
                if (right != "") {
                    count = split(right, groups, ":")
                    for (i = 1; i <= count; i++) if (!hex_group(groups[i])) return 0
                    total += count
                }
                return total < 8
            }
            count = split(value, groups, ":")
            if (count != 8) return 0
            for (i = 1; i <= count; i++) if (!hex_group(groups[i])) return 0
            return 1
        }
        function ipv6_wildcard(value, prefix, groups, count, i) {
            if (value !~ /:%$/) return 0
            prefix = substr(value, 1, length(value) - 2)
            count = split(prefix, groups, ":")
            if (count < 1 || count > 7) return 0
            for (i = 1; i <= count; i++) if (!hex_group(groups[i])) return 0
            return 1
        }
        BEGIN {
            host = ARGV[1]
            if (tolower(host) == "localhost" || host == "%" || ipv4(host) || ipv4_wildcard(host) ||
                ipv4_netmask(host) || ipv6(host) || ipv6_wildcard(host)) print "address"
            else print "hostname"
            exit
        }
    ' "$host"
}

dbtune_grant_host_is_local() {
    local host=${1-}

    [[ ${host,,} == localhost || $host == ::1 ]] && return 0
    command awk '
        function canonical_octet(value) {
            return value ~ /^(0|[1-9][0-9]{0,2})$/ && value + 0 <= 255
        }
        BEGIN {
            count = split(ARGV[1], parts, ".")
            if (count != 4 || parts[1] != "127") exit 1
            for (i = 1; i <= count; i++) if (!canonical_octet(parts[i])) exit 1
            exit 0
        }
    ' "$host"
}

dbtune_grant_hex_decode() {
    local hex=${1-}
    local escaped='' pair

    [[ $hex =~ ^([[:xdigit:]]{2})*$ && ${hex^^} != *00* ]] || return 65
    while [[ -n $hex ]]; do
        pair=${hex:0:2}
        escaped+="\\x$pair"
        hex=${hex:2}
    done
    printf '%b' "$escaped"
}

dbtune_audit_collect_grants() {
    local out=${1:-}
    local grants_file='' line user_hex host_hex host class key hostname_count=0 remote_count=0 failed=0
    local -A seen=()

    if ! grants_file=$(mktemp "${TMPDIR:-/tmp}/dbtune-grants.XXXXXX") || ! chmod 600 "$grants_file"; then
        failed=1
    elif ! dbtune_audit_sql 'SELECT HEX(USER), HEX(HOST) FROM mysql.user ORDER BY USER,HOST' >"$grants_file"; then
        failed=1
    else
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line != *$'\t'* || ${line#*$'\t'} == *$'\t'* ]]; then
                failed=1
                break
            fi
            user_hex=${line%%$'\t'*}
            host_hex=${line#*$'\t'}
            key="${user_hex^^}:${host_hex^^}"
            if [[ -n ${seen[$key]+x} ]]; then
                failed=1
                break
            fi
            seen[$key]=1
            if ! dbtune_grant_hex_decode "$user_hex" >/dev/null ||
                ! host=$(dbtune_grant_hex_decode "$host_hex") ||
                ! class=$(dbtune_grant_host_classify "$host"); then
                failed=1
                break
            fi
            [[ $class != hostname ]] || hostname_count=$((hostname_count + 1))
            dbtune_grant_host_is_local "$host" || remote_count=$((remote_count + 1))
        done <"$grants_file"
    fi
    [[ -z $grants_file ]] || rm -f "$grants_file"

    if ((failed)); then
        dbtune_audit_put "$out" security.grants_audited 0
        dbtune_audit_put "$out" security.hostname_grant_count unknown
        dbtune_audit_put "$out" security.remote_grant_count unknown
        dbtune_audit_put "$out" finding.grants_query_failed warning
    else
        dbtune_audit_put "$out" security.grants_audited 1
        dbtune_audit_put "$out" security.hostname_grant_count "$hostname_count"
        dbtune_audit_put "$out" security.remote_grant_count "$remote_count"
    fi
}

dbtune_audit_add_findings() {
    local out=${1:-}
    local scan scan_status=0 key value effective systemd_limit configured_limit

    scan=$(mktemp "${out%/*}/.landmine-scan.XXXXXX") || return 1
    dbtune_loaded_defaults_scan "$scan" || scan_status=$?
    if [[ -r $scan ]]; then
        while IFS=$'\t' read -r key value; do
            dbtune_audit_put "$out" "$key" "$value"
        done <"$scan"
    else
        dbtune_audit_put "$out" landmine.scan.status failed
        dbtune_audit_put "$out" landmine.scan.method mariadbd_print_defaults
        scan_status=69
    fi
    rm -f "$scan"
    ((scan_status == 0)) || dbtune_audit_put "$out" finding.landmine_scan_failed warning

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

dbtune_audit_finalize_status() {
    local audit=${1:-}
    local apps=${2:-}
    local database_file=${3:-}
    local available mariadb_status hardware_status applications_status security_status version family
    local cpu ram storage discovery app_count app_partial app_failed app_status_count
    local grants grants_count hostname_grants hostname_grants_count listener listener_count
    local grant_evidence=0 listener_evidence=0 hardware_evidence=0 findings=0 incomplete=0 failed_count=0
    local evidence_key evidence_value validator requirement _role first_value quarantined_conflicts
    local evidence_present evidence_conflict mariadb_missing='' mariadb_invalid='' mariadb_conflicting='' mariadb_optional=''
    local overall exit_status section status domain failed_sections='' partial_sections='' affected_domains=''
    local -a sections=(mariadb hardware applications security)
    local -A statuses domains affected=()

    [[ -r $audit && -r $apps && -r $database_file ]] || return 66

    available=$(command awk -F '\t' '$1=="mariadb.available" {print $2; exit}' "$audit")
    version=$(command awk -F '\t' '$1=="mariadb.version" {print $2; exit}' "$audit")
    family=$(dbtune_audit_mariadb_version_family "$version")
    quarantined_conflicts=$(command awk -F '\t' '$1=="audit.mariadb_evidence_conflicts" {print $2; exit}' "$audit")
    mariadb_status=failed
    if [[ $available == 1 ]]; then
        mariadb_status=complete
        while IFS=$'\t' read -r evidence_key validator requirement _role; do
            if [[ $requirement == pre11 && $family == 11.x ]]; then
                mariadb_optional+="${mariadb_optional:+,}$evidence_key=deprecated_11x"
                continue
            fi
            evidence_present=0
            evidence_conflict=0
            first_value=''
            if [[ ,$quarantined_conflicts, == *,$evidence_key,* ]]; then
                evidence_conflict=1
            fi
            while IFS= read -r evidence_value; do
                if ((evidence_present == 0)); then
                    first_value=$evidence_value
                elif [[ $first_value != "$evidence_value" ]]; then
                    evidence_conflict=1
                fi
                evidence_present=$((evidence_present + 1))
            done < <(command awk -F '\t' -v key="$evidence_key" '$1==key {print $2}' "$audit")
            if ((evidence_conflict)); then
                mariadb_conflicting+="${mariadb_conflicting:+,}$evidence_key"
            elif ((evidence_present == 0)); then
                mariadb_missing+="${mariadb_missing:+,}$evidence_key"
            elif ! dbtune_audit_mariadb_evidence_valid "$validator" "$first_value"; then
                mariadb_invalid+="${mariadb_invalid:+,}$evidence_key=${DBTUNE_AUDIT_EVIDENCE_ERROR:-malformed}"
            fi
        done < <(dbtune_audit_mariadb_evidence_schema)
        if command awk -F '\t' '
            $1=="finding.global_variables_query_failed" ||
            $1=="finding.global_status_query_failed" ||
            $1=="finding.dataset_query_failed" {bad=1}
            END {exit !bad}
        ' "$audit" || command awk -F '\t' '$2=="audit_error.dataset" {bad=1} END {exit !bad}' "$database_file"; then
            mariadb_status=partial
        fi
        if [[ -n $mariadb_missing || -n $mariadb_invalid || -n $mariadb_conflicting ]]; then
            mariadb_status=partial
        fi
        if ! dbtune_loaded_defaults_validate "$audit" embedded; then
            mariadb_status=partial
        fi
    fi

    cpu=$(command awk -F '\t' '$1=="hw.cpu_count" {print $2; exit}' "$audit")
    ram=$(command awk -F '\t' '$1=="hw.ram_bytes" {print $2; exit}' "$audit")
    storage=$(command awk -F '\t' '$1=="hw.storage_class" {print tolower($2); exit}' "$audit")
    [[ $cpu =~ ^[1-9][0-9]*$ ]] && hardware_evidence=$((hardware_evidence + 1))
    [[ $ram =~ ^[1-9][0-9]*$ ]] && hardware_evidence=$((hardware_evidence + 1))
    [[ -n $storage && $storage != unknown ]] && hardware_evidence=$((hardware_evidence + 1))
    case $hardware_evidence in
        3) hardware_status=complete ;;
        0) hardware_status=failed ;;
        *) hardware_status=partial ;;
    esac

    discovery=$(command awk -F '\t' '$1=="app.discovery_status" {print tolower($2); exit}' "$audit")
    app_count=$(command awk -F '\t' '$1=="app.count" {print $2; exit}' "$audit")
    [[ $app_count =~ ^[0-9]+$ ]] || app_count=0
    read -r _ app_partial app_failed app_status_count < <(command awk -F '\t' '
        $2=="audit_status" {
            count++
            if ($3=="complete") complete++
            else if ($3=="partial") partial++
            else if ($3=="failed") failed++
        }
        END {print complete+0, partial+0, failed+0, count+0}
    ' "$apps")
    if [[ $discovery != complete ]]; then
        applications_status=failed
    elif ((app_count == 0)); then
        applications_status=complete
    elif ((app_status_count == 0 || app_failed == app_count)); then
        applications_status=failed
    elif ((app_partial > 0 || app_failed > 0 || app_status_count < app_count)); then
        applications_status=partial
    else
        applications_status=complete
    fi

    IFS=$'\t' read -r grants_count grants < <(command awk -F '\t' '$1=="security.grants_audited" {count++; if (count==1) value=$2} END {print count+0 "\t" value}' "$audit")
    IFS=$'\t' read -r hostname_grants_count hostname_grants < <(command awk -F '\t' '$1=="security.hostname_grant_count" {count++; if (count==1) value=$2} END {print count+0 "\t" value}' "$audit")
    IFS=$'\t' read -r listener_count listener < <(command awk -F '\t' '$1=="security.port_3306" {count++; if (count==1) value=tolower($2)} END {print count+0 "\t" value}' "$audit")
    [[ $grants_count == 1 && $grants == 1 && $hostname_grants_count == 1 && $hostname_grants =~ ^(0|[1-9][0-9]*)$ ]] && grant_evidence=1
    [[ $listener_count == 1 && $listener =~ ^(local|public|not_listening)$ ]] && listener_evidence=1
    if ((grant_evidence && listener_evidence)); then
        security_status=complete
    elif ((!grant_evidence && !listener_evidence)); then
        security_status=failed
    else
        security_status=partial
    fi

    statuses[mariadb]=$mariadb_status
    statuses[hardware]=$hardware_status
    statuses[applications]=$applications_status
    statuses[security]=$security_status
    domains[mariadb]=server_tuning,database_inventory
    domains[hardware]=capacity_sizing,storage_tuning
    domains[applications]=application_health,application_database
    domains[security]=security

    dbtune_audit_put "$audit" audit.section.mariadb.evidence_schema_version 1
    dbtune_audit_put "$audit" audit.section.mariadb.missing_evidence "${mariadb_missing:-none}"
    dbtune_audit_put "$audit" audit.section.mariadb.invalid_evidence "${mariadb_invalid:-none}"
    dbtune_audit_put "$audit" audit.section.mariadb.conflicting_evidence "${mariadb_conflicting:-none}"
    dbtune_audit_put "$audit" audit.section.mariadb.optional_evidence "${mariadb_optional:-none}"

    for section in "${sections[@]}"; do
        status=${statuses[$section]}
        domain=${domains[$section]}
        dbtune_audit_put "$audit" "audit.section.$section.status" "$status"
        dbtune_audit_put "$audit" "audit.section.$section.domains" "$domain"
        case $status in
            failed)
                failed_count=$((failed_count + 1))
                incomplete=$((incomplete + 1))
                failed_sections+="${failed_sections:+,}$section"
                ;;
            partial)
                incomplete=$((incomplete + 1))
                partial_sections+="${partial_sections:+,}$section"
                ;;
        esac
        if [[ $status != complete ]]; then
            while IFS= read -r domain; do
                [[ -n $domain ]] && affected["$domain"]=1
            done < <(tr ',' '\n' <<<"${domains[$section]}")
        fi
    done
    for domain in server_tuning database_inventory capacity_sizing storage_tuning application_health application_database security; do
        [[ -n ${affected[$domain]+x} ]] || continue
        affected_domains+="${affected_domains:+,}$domain"
    done
    findings=$(command awk -F '\t' '
        FNR==1 {file++}
        (file==1 && $1 ~ /^finding\./) || (file>1 && $2 ~ /^finding(\.|$)/) {count++}
        END {print count+0}
    ' "$audit" "$apps" "$database_file")
    if ((failed_count == ${#sections[@]})); then
        overall=ERROR
        exit_status=1
    elif ((incomplete > 0)); then
        overall=UNKNOWN
        exit_status=2
    elif ((findings > 0)); then
        overall=FINDINGS
        exit_status=0
    else
        overall=PASS
        exit_status=0
    fi

    dbtune_audit_put "$audit" audit.required_sections "$(IFS=,; printf '%s' "${sections[*]}")"
    dbtune_audit_put "$audit" audit.failed_sections "${failed_sections:-none}"
    dbtune_audit_put "$audit" audit.partial_sections "${partial_sections:-none}"
    dbtune_audit_put "$audit" audit.affected_domains "${affected_domains:-none}"
    dbtune_audit_put "$audit" audit.finding_count "$findings"
    dbtune_audit_put "$audit" audit.overall_status "$overall"
    dbtune_audit_put "$audit" audit.exit_status "$exit_status"
}

dbtune_audit_json() {
    local audit=${1:-}
    local apps=${2:-}
    local database_file=${3:-}
    local scope key value
    local -a fields=()
    local -A json_seen=()

    dbtune_audit_validate "$audit" || return
    while IFS=$'\t' read -r key value; do
        dbtune_is_sensitive_key "$key" && continue
        key=$(dbtune_audit_key_canonical "$key") || return
        [[ -n $key && -z ${json_seen[$key]+x} ]] || continue
        json_seen["$key"]=1
        fields+=("$(dbtune_redact "$key")" "$(dbtune_redact "$value")")
    done <"$audit"
    while IFS=$'\t' read -r scope key value; do
        [[ -n $scope && -n $key ]] || continue
        dbtune_is_sensitive_key "$key" && continue
        key="$scope.$key"
        [[ -z ${json_seen[$key]+x} ]] || continue
        json_seen["$key"]=1
        fields+=("$(dbtune_redact "$key")" "$(dbtune_redact "$value")")
    done <"$apps"
    while IFS=$'\t' read -r scope key value; do
        [[ -n $scope && -n $key ]] || continue
        dbtune_is_sensitive_key "$key" && continue
        key="database.$(dbtune_audit_slug "$scope").$key"
        [[ -z ${json_seen[$key]+x} ]] || continue
        json_seen["$key"]=1
        fields+=("$(dbtune_redact "$key")" "$(dbtune_redact "$value")")
    done <"$database_file"
    dbtune_json_emit "${fields[@]}"
}

dbtune_audit_summary() {
    local audit=${1:-}
    local apps=${2:-}
    local database_file=${3:-}
    local version cpu ram dataset storage app_count db_count critical warning
    local overall required failed partial affected finding_count
    local mariadb_missing mariadb_invalid mariadb_conflicting mariadb_optional
    local not_detected not_detected_feminine not_detected_masculine not_available_feminine

    version=$(command awk -F '\t' '$1=="mariadb.version" { print $2; exit }' "$audit")
    cpu=$(command awk -F '\t' '$1=="hw.cpu_count" { print $2; exit }' "$audit")
    ram=$(command awk -F '\t' '$1=="hw.ram_bytes" { printf "%.1f GB", $2/1073741824; exit }' "$audit")
    dataset=$(command awk -F '\t' '$1=="mariadb.dataset_bytes" { printf "%.2f GB", $2/1073741824; exit }' "$audit")
    storage=$(command awk -F '\t' '$1=="hw.storage_class" { print $2; exit }' "$audit")
    app_count=$(command awk -F '\t' '$1=="app.count" { print $2; exit }' "$audit")
    db_count=$(command awk -F '\t' '$2=="size_bytes" { seen[$1]=1 } END { print length(seen) }' "$database_file")
    critical=$(command awk -F '\t' '$1 ~ /^finding\./ && $2=="critical" { n++ } END { print n+0 }' "$audit")
    critical=$((critical + $(command awk -F '\t' '$2 ~ /^finding/ && $3=="critical" { n++ } END { print n+0 }' "$apps")))
    critical=$((critical + $(command awk -F '\t' '$2 ~ /^finding/ && $3=="critical" { n++ } END { print n+0 }' "$database_file")))
    warning=$(command awk -F '\t' '$1 ~ /^finding\./ && $2=="warning" { n++ } END { print n+0 }' "$audit")
    warning=$((warning + $(command awk -F '\t' '$2 ~ /^finding/ && $3=="warning" { n++ } END { print n+0 }' "$apps")))
    warning=$((warning + $(command awk -F '\t' '$2 ~ /^finding/ && $3=="warning" { n++ } END { print n+0 }' "$database_file")))
    overall=$(command awk -F '\t' '$1=="audit.overall_status" {print $2; exit}' "$audit")
    required=$(command awk -F '\t' '$1=="audit.required_sections" {print $2; exit}' "$audit")
    failed=$(command awk -F '\t' '$1=="audit.failed_sections" {print $2; exit}' "$audit")
    partial=$(command awk -F '\t' '$1=="audit.partial_sections" {print $2; exit}' "$audit")
    affected=$(command awk -F '\t' '$1=="audit.affected_domains" {print $2; exit}' "$audit")
    finding_count=$(command awk -F '\t' '$1=="audit.finding_count" {print $2; exit}' "$audit")
    mariadb_missing=$(command awk -F '\t' '$1=="audit.section.mariadb.missing_evidence" {print $2; exit}' "$audit")
    mariadb_invalid=$(command awk -F '\t' '$1=="audit.section.mariadb.invalid_evidence" {print $2; exit}' "$audit")
    mariadb_conflicting=$(command awk -F '\t' '$1=="audit.section.mariadb.conflicting_evidence" {print $2; exit}' "$audit")
    mariadb_optional=$(command awk -F '\t' '$1=="audit.section.mariadb.optional_evidence" {print $2; exit}' "$audit")

    not_detected=$(dbtune_msg audit_value_not_detected) || return
    not_detected_feminine=$(dbtune_msg audit_value_not_detected_feminine) || return
    not_detected_masculine=$(dbtune_msg audit_value_not_detected_masculine) || return
    not_available_feminine=$(dbtune_msg audit_value_not_available_feminine) || return
    dbtune_printf audit_summary_status "$(dbtune_redact "${overall:-ERROR}")"
    dbtune_printf audit_summary_sections \
        "$(dbtune_redact "${required:-$not_detected}")" "$(dbtune_redact "${failed:-$not_detected}")" \
        "$(dbtune_redact "${partial:-$not_detected}")"
    dbtune_printf audit_summary_domains "$(dbtune_redact "${affected:-$not_detected}")"
    dbtune_printf audit_summary_evidence \
        "$(dbtune_redact "${mariadb_missing:-$not_detected}")" "$(dbtune_redact "${mariadb_invalid:-$not_detected}")" \
        "$(dbtune_redact "${mariadb_conflicting:-$not_detected}")" "$(dbtune_redact "${mariadb_optional:-$not_detected}")"
    dbtune_printf audit_summary_server \
        "$(dbtune_redact "${cpu:-$not_detected}")" "$(dbtune_redact "${ram:-$not_detected_feminine}")" \
        "$(dbtune_redact "${storage:-$not_detected}")"
    dbtune_printf audit_summary_mariadb \
        "$(dbtune_redact "${version:-$not_available_feminine}")" "$(dbtune_redact "${dataset:-$not_detected_masculine}")" \
        "$(dbtune_redact "${db_count:-0}")"
    dbtune_printf audit_summary_applications \
        "$(dbtune_redact "${app_count:-0}")" "$(dbtune_redact "${finding_count:-0}")" \
        "$(dbtune_redact "$critical")" "$(dbtune_redact "$warning")"
    dbtune_printf audit_summary_data "$(dbtune_redact "$DBTUNE_STATE_DIR")"
}

cmd_audit() {
    local json=0 argument scratch audit apps databases manifest version
    local run_id old_run_id archive='' current_manifest audit_hash overall_exit

    for argument in "$@"; do
        case $argument in
            --json) json=1 ;;
            *)
                dbtune_log error "$(dbtune_printf audit_invalid_option "$argument")"
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
    if ! dbtune_audit_quarantine_mariadb_conflicts "$audit"; then
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_evidence_isolation_failed)"
        return 65
    fi
    if ! dbtune_audit_normalize_in_place "$audit"; then
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_conflicting_values)"
        return 65
    fi
    version=$(command awk -F '\t' '$1=="mariadb.version" { print $2; exit }' "$audit")
    dbtune_audit_add_findings "$audit" "${version:-0}"
    dbtune_audit_finalize_status "$audit" "$apps" "$databases" || {
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_status_failed)"
        return 1
    }
    if ! dbtune_audit_normalize_in_place "$audit"; then
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_conflicting_values)"
        return 65
    fi

    dbtune_provenance_write_audit_manifest "$manifest" "$run_id" "$audit" "$apps" "$databases" || {
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_manifest_failed)"
        return 1
    }
    current_manifest=$(dbtune_audit_manifest_file) || {
        rm -rf "$scratch"
        return 1
    }
    old_run_id=$(dbtune_manifest_value "$current_manifest" run_id 2>/dev/null || printf 'legacy-%s' "$$")
    archive=$(dbtune_cycle_archive "$old_run_id") || {
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_cycle_archive_failed)"
        return 1
    }

    if ! dbtune_atomic_write "$DBTUNE_STATE_DIR/audit.tsv" 600 <"$audit" ||
        ! dbtune_atomic_write "$DBTUNE_STATE_DIR/apps.tsv" 600 <"$apps" ||
        ! dbtune_atomic_write "$DBTUNE_STATE_DIR/databases.tsv" 600 <"$databases" ||
        ! dbtune_atomic_write "$current_manifest" 600 <"$manifest"; then
        rm -rf "$scratch"
        dbtune_log error "$(dbtune_msg audit_write_failed)"
        return 1
    fi
    rm -rf "$scratch"
    dbtune_cycle_invalidate_downstream || return
    dbtune_state_record_audit "$run_id" "$archive" || return
    audit_hash=$(dbtune_manifest_value "$current_manifest" audit_hash) || return
    overall_exit=$(command awk -F '\t' '$1=="audit.exit_status" {print $2; exit}' "$DBTUNE_STATE_DIR/audit.tsv")
    [[ $overall_exit =~ ^[012]$ ]] || overall_exit=1
    dbtune_event audit_completed run_id "$run_id" audit_hash "$audit_hash" \
        overall_status "$(command awk -F '\t' '$1=="audit.overall_status" {print $2; exit}' "$DBTUNE_STATE_DIR/audit.tsv")" \
        exit_status "$overall_exit" || true

    if ((json)); then
        dbtune_audit_json "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    else
        dbtune_audit_summary "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    fi
    return "$overall_exit"
}
