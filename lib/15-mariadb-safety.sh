dbtune_landmine_catalog() {
    cat <<'CATALOG'
innodb_file_format	10.3	critical	reason_variable_removed_startup
innodb_file_format_max	10.3	critical	reason_variable_removed_startup
innodb_buffer_pool_instances	10.6	critical	reason_variable_removed_config
innodb_log_files_in_group	10.6	critical	reason_variable_removed_config
innodb_change_buffering	11.0	critical	reason_variable_removed_startup
innodb_flush_method	11.0	warning	reason_flush_method_deprecated
CATALOG
}

dbtune_loaded_defaults_publish_failed() {
    local output=${1:-}
    local method=${2:-mariadbd_print_defaults}

    printf 'landmine.scan.status\tfailed\nlandmine.scan.method\t%s\n' "$method" |
        dbtune_atomic_write "$output" 600
}

dbtune_loaded_defaults_command_path() {
    if [[ $DBTUNE_ARTIFACT_PROFILE == production ]]; then
        dbtune_runtime_command_path "${1:-}"
    else
        builtin type -P -- "${1:-}" || return 69
    fi
}

dbtune_loaded_defaults_scan() {
    local output=${1:-}
    local daemon method=mariadbd_print_defaults name version_output version line token option gate severity _reason
    local stdout_file stderr_file snapshot status=0
    local -a tokens=()
    local -A gates=() severities=() known=() loaded=()

    [[ -n $output ]] || return 64
    if daemon=$(dbtune_loaded_defaults_command_path mariadbd 2>/dev/null); then
        name=mariadbd
    else
        if ! daemon=$(dbtune_loaded_defaults_command_path mysqld 2>/dev/null); then
            dbtune_loaded_defaults_publish_failed "$output" "$method" || return 1
            return 69
        fi
        name=mysqld
        method=mysqld_print_defaults
    fi

    stdout_file=$(mktemp "${TMPDIR:-/tmp}/dbtune-loaded-defaults-out.XXXXXX") || return 1
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/dbtune-loaded-defaults-err.XXXXXX") || {
        rm -f "$stdout_file"
        return 1
    }
    snapshot=$(mktemp "${TMPDIR:-/tmp}/dbtune-loaded-defaults-snapshot.XXXXXX") || {
        rm -f "$stdout_file" "$stderr_file"
        return 1
    }
    chmod 600 "$stdout_file" "$stderr_file" "$snapshot" || {
        rm -f "$stdout_file" "$stderr_file" "$snapshot"
        return 1
    }

    if ! version_output=$("$daemon" --version 2>"$stderr_file"); then
        status=69
    elif [[ $version_output =~ Distrib[[:space:]]+([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        version=${BASH_REMATCH[1]}
    elif [[ $version_output =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        version=${BASH_REMATCH[1]}
    else
        status=65
    fi
    if ((status == 0)) && ! "$daemon" --print-defaults >"$stdout_file" 2>"$stderr_file"; then
        status=69
    fi

    if ((status == 0)); then
        while IFS=$'\t' read -r option gate severity _reason; do
            known["$option"]=1
            gates["$option"]=$gate
            severities["$option"]=$severity
        done < <(dbtune_landmine_catalog)
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line =~ [[:cntrl:]] ]]; then
                status=65
                break
            fi
            [[ -n $line ]] || continue
            if [[ $line == "$name would have been started with the following arguments:" ||
                $line == "$daemon would have been started with the following arguments:" ]]; then
                continue
            fi
            read -r -a tokens <<<"$line"
            for token in "${tokens[@]}"; do
                if [[ ! $token =~ ^--([A-Za-z][A-Za-z0-9_-]*)(=([^[:space:][:cntrl:]]*))?$ ]]; then
                    status=65
                    break 2
                fi
                option=${BASH_REMATCH[1],,}
                option=${option//-/_}
                [[ -n ${known[$option]+x} ]] || continue
                dbtune_version_at_least "$version" "${gates[$option]}" || continue
                loaded["$option"]=1
            done
        done <"$stdout_file"
    fi

    if ((status == 0)); then
        {
            printf 'landmine.scan.status\tcomplete\n'
            printf 'landmine.scan.method\t%s\n' "$method"
            while IFS=$'\t' read -r option _gate severity _reason; do
                [[ -n ${loaded[$option]+x} ]] || continue
                printf 'landmine.%s.loaded\t1\n' "$option"
                printf 'landmine.%s.severity\t%s\n' "$option" "$severity"
                printf 'finding.landmine.%s\t%s\n' "$option" "$severity"
            done < <(dbtune_landmine_catalog)
        } >"$snapshot"
    else
        printf 'landmine.scan.status\tfailed\nlandmine.scan.method\t%s\n' "$method" >"$snapshot"
    fi
    if ! dbtune_atomic_write "$output" 600 <"$snapshot"; then
        rm -f "$stdout_file" "$stderr_file" "$snapshot"
        return 1
    fi
    rm -f "$stdout_file" "$stderr_file" "$snapshot"
    return "$status"
}

dbtune_loaded_defaults_validate() {
    local file=${1:-}
    local embedded=${2:-snapshot}
    local key value rest name status='' method='' severity _reason
    local -A known=() severities=() seen=() loaded=() evidence_severity=() findings=()

    [[ -r $file ]] || return 65
    while IFS=$'\t' read -r name _gate severity _reason; do
        known["$name"]=1
        severities["$name"]=$severity
    done < <(dbtune_landmine_catalog)
    while IFS=$'\t' read -r key value rest || [[ -n ${key:-} ]]; do
        value=${value%$'\r'}
        if [[ $key != landmine.* && $key != finding.landmine.* ]]; then
            [[ $embedded == embedded ]] && continue
            return 65
        fi
        [[ -n $key && -z $rest && -z ${seen[$key]+x} ]] || return 65
        seen["$key"]=1
        case $key in
            landmine.scan.status)
                [[ $value == complete || $value == failed ]] || return 65
                status=$value
                ;;
            landmine.scan.method)
                [[ $value == mariadbd_print_defaults || $value == mysqld_print_defaults ]] || return 65
                method=$value
                ;;
            landmine.*.loaded)
                name=${key#landmine.}
                name=${name%.loaded}
                [[ -n ${known[$name]+x} && $value == 1 ]] || return 65
                loaded["$name"]=1
                ;;
            landmine.*.severity)
                name=${key#landmine.}
                name=${name%.severity}
                [[ -n ${known[$name]+x} && $value == "${severities[$name]}" ]] || return 65
                evidence_severity["$name"]=$value
                ;;
            finding.landmine.*)
                name=${key#finding.landmine.}
                [[ -n ${known[$name]+x} && $value == "${severities[$name]}" ]] || return 65
                findings["$name"]=$value
                ;;
            *) return 65 ;;
        esac
    done <"$file"
    [[ -n $status && -n $method ]] || return 65
    [[ $status == complete ]] || return 65
    for name in "${!known[@]}"; do
        if [[ -n ${loaded[$name]+x} ]]; then
            [[ -n ${evidence_severity[$name]+x} && -n ${findings[$name]+x} ]] || return 65
        elif [[ -n ${evidence_severity[$name]+x} || -n ${findings[$name]+x} ]]; then
            return 65
        fi
    done
}

dbtune_loaded_defaults_assert_safe() {
    local file=${1:-}
    local embedded=${2:-snapshot}
    local name _gate severity _reason

    dbtune_loaded_defaults_validate "$file" "$embedded" || return 65
    while IFS=$'\t' read -r name _gate severity _reason; do
        [[ $severity == critical ]] || continue
        if command awk -F '\t' -v key="landmine.$name.loaded" '$1==key && $2=="1" {found=1} END {exit !found}' "$file"; then
            return 65
        fi
    done < <(dbtune_landmine_catalog)
}

dbtune_loaded_defaults_fingerprint() {
    local file=${1:-}

    dbtune_loaded_defaults_validate "$file" "${2:-snapshot}" || return 65
    command awk -F '\t' '
        $1 ~ /^landmine[.][a-z0-9_]+[.]loaded$/ && $2=="1" {
            name=$1
            sub(/^landmine[.]/, "", name)
            sub(/[.]loaded$/, "", name)
            loaded[name]=1
        }
        $1 ~ /^landmine[.][a-z0-9_]+[.]severity$/ {
            name=$1
            sub(/^landmine[.]/, "", name)
            sub(/[.]severity$/, "", name)
            severity[name]=$2
        }
        END {for (name in loaded) print name "\t" severity[name]}
    ' "$file" | LC_ALL=C sort | dbtune_sha256_stream
}
