dbtune_runtime_environment_contract() {
    cat <<'CONTRACT'
DBTUNE_ARTIFACT_PROFILE	immutable
DBTUNE_ARTIFACT_VERSION	immutable
DBTUNE_UI_LANG	operator
DBTUNE_STATE_DIR	operator
DBTUNE_CONFIG_TARGET	operator
DBTUNE_CONFIG_ALLOWED_DIR	operator
DBTUNE_ROOT_CNF	operator
DBTUNE_LOG_LEVEL	operator
DBTUNE_MAX_BACKUP_AGE_SECONDS	operator
DBTUNE_BACKUP_EVIDENCE_FILE	test-only
DBTUNE_BACKUP_EVIDENCE_UID	test-only
DBTUNE_CLK_TCK	test-only
DBTUNE_COLLECT_CONFIG_FILE	test-only
DBTUNE_COLLECT_HEALTH_FILE	test-only
DBTUNE_COLLECT_LOCK_FILE	test-only
DBTUNE_COLLECT_SERVICE_PATH	test-only
DBTUNE_COLLECT_TIMER_PATH	test-only
DBTUNE_COLLECT_TIMER_UNIT	test-only
DBTUNE_CONFIG_GID	test-only
DBTUNE_CONFIG_MODE	test-only
DBTUNE_CONFIG_UID	test-only
DBTUNE_CRONTAB_FILE	test-only
DBTUNE_CRON_ROOT	test-only
DBTUNE_CRON_SCAN_ROOT	test-only
DBTUNE_DATE	test-only
DBTUNE_DBSIZE_DATE_FILE	test-only
DBTUNE_DBSIZE_FILE	test-only
DBTUNE_DF	test-only
DBTUNE_EVENT_FLOCK	test-only
DBTUNE_FAULT_INJECT	test-only
DBTUNE_FLOCK	test-only
DBTUNE_FREE	test-only
DBTUNE_GETCONF	test-only
DBTUNE_HOME_ROOT	test-only
DBTUNE_INSTALL	test-only
DBTUNE_LAST_UPTIME_FILE	test-only
DBTUNE_MAX_SAMPLES_BYTES	test-only
DBTUNE_MAX_SAMPLE_INTERVAL_SECONDS	test-only
DBTUNE_MAX_SLOW_LOG_BYTES	test-only
DBTUNE_MIN_APPLY_SAMPLES	test-only
DBTUNE_MIN_AUTO_SAMPLES	test-only
DBTUNE_MIN_FREE_KB	test-only
DBTUNE_MONOTONIC	test-only
DBTUNE_MYSQL_CONFIG_DIR	test-only
DBTUNE_MYSQL_DATADIR	test-only
DBTUNE_MYSQL_GROUP	test-only
DBTUNE_MYSQL_USER	test-only
DBTUNE_NOW_EPOCH	test-only
DBTUNE_NOW_HHMM	test-only
DBTUNE_PGREP	test-only
DBTUNE_PROC_ROOT	test-only
DBTUNE_PROGRAM_PATH	test-only
DBTUNE_PUBLISH_CRASH_MATCH	test-only
DBTUNE_PUBLISH_CRASH_POINT	test-only
DBTUNE_PUBLISH_FAIL_MATCH	test-only
DBTUNE_PUBLISH_FAULT_HOOK	test-only
DBTUNE_PYTHON	test-only
DBTUNE_RESTART_SKEW_SECONDS	test-only
DBTUNE_RUNCLOUD_CNF	test-only
DBTUNE_SAMPLES_FILE	test-only
DBTUNE_SAMPLE_SECONDS	test-only
DBTUNE_SERVER_SUPPORT	test-only
DBTUNE_SLEEP	test-only
DBTUNE_SLOW_LOG	test-only
DBTUNE_SQL_CONNECT_TIMEOUT	test-only
DBTUNE_SQL_STATEMENT_TIMEOUT	test-only
DBTUNE_STALE_SAMPLE_SECONDS	test-only
DBTUNE_STAT	test-only
DBTUNE_STATE_UID	test-only
DBTUNE_SYNC	test-only
DBTUNE_SYSTEMCTL	test-only
DBTUNE_SYSTEMD_DIR	test-only
DBTUNE_TODAY	test-only
DBTUNE_UNATTENDED_CONFIG	test-only
DBTUNE_UNATTENDED_DIR	test-only
DBTUNE_WC	test-only
DBTUNE_ACTION_COMMAND	internal
DBTUNE_ACTION_CONNECT_TIMEOUT_SECONDS	internal
DBTUNE_ACTION_DESTRUCTIVE	internal
DBTUNE_ACTION_KIND	internal
DBTUNE_ACTION_LINES	internal
DBTUNE_ACTION_RULE_ID	internal
DBTUNE_ACTION_SAFETY	internal
DBTUNE_ACTION_SCOPE	internal
DBTUNE_ACTION_STATEMENT_TIMEOUT_SECONDS	internal
DBTUNE_ACTION_TARGET	internal
DBTUNE_ACTION_TIMEOUT_CAPABILITY	internal
DBTUNE_ACTION_WARNING_ID	internal
DBTUNE_ANALYSIS_EVIDENCE	internal
DBTUNE_ANALYSIS_FILE	internal
DBTUNE_ANALYSIS_FINGERPRINT	internal
DBTUNE_ANALYSIS_LINES	internal
DBTUNE_ANALYSIS_PROPOSED_KEY	internal
DBTUNE_ANALYSIS_PROPOSED_VALUE	internal
DBTUNE_ANALYSIS_REASON_ID	internal
DBTUNE_ANALYSIS_RULE_ID	internal
DBTUNE_ANALYSIS_SCOPE	internal
DBTUNE_ANALYSIS_SEVERITY	internal
DBTUNE_ANALYSIS_VERDICT	internal
DBTUNE_APPLY_BACKUP_AGE_SECONDS	internal
DBTUNE_APPLY_BACKUP_LAST_SUCCESS	internal
DBTUNE_APPLY_BACKUP_MAX_AGE_SECONDS	internal
DBTUNE_APPLY_BACKUP_MODE	internal
DBTUNE_APPLY_BACKUP_SOURCE	internal
DBTUNE_APPLY_RECORDS_HASH	internal
DBTUNE_APPLY_RECORD_COUNT	internal
DBTUNE_APPLY_SNAPSHOT_HASH	internal
DBTUNE_APPS_FILE	internal
DBTUNE_AUDIT_EVIDENCE_ERROR	internal
DBTUNE_AUDIT_FILE	internal
DBTUNE_AUDIT_HASH	internal
DBTUNE_AUDIT_QUERY_TIMEOUT_SECONDS	internal
DBTUNE_AUTOLOAD_LINES	internal
DBTUNE_AUTOLOAD_NAME	internal
DBTUNE_AUTOLOAD_SCOPE	internal
DBTUNE_AUTOLOAD_SIZE	internal
DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS	internal
DBTUNE_BACKUP_EVIDENCE_ERROR	internal
DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS	internal
DBTUNE_DATABASES_FILE	internal
DBTUNE_DBSIZE_HASH	internal
DBTUNE_DBSIZE_INPUT	internal
DBTUNE_DBSIZE_SELECTED_HASH	internal
DBTUNE_DBSIZE_SELECTED_ROWS	internal
DBTUNE_DEFAULT_DAYS	internal
DBTUNE_I18N_LANGUAGE	internal
DBTUNE_I18N_MESSAGE	internal
DBTUNE_JSON_FIELDS	internal
DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY	internal
DBTUNE_LIFECYCLE_INTENT_HISTORY	internal
DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT	internal
DBTUNE_LIFECYCLE_INTENT_PREVIOUS_STATE	internal
DBTUNE_LIFECYCLE_INTENT_PROPOSAL_HASH	internal
DBTUNE_LIFECYCLE_PARENT_IDENTITIES	internal
DBTUNE_LIFECYCLE_RESTORED_BACKUP	internal
DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID	internal
DBTUNE_LIFECYCLE_RESTORED_HISTORY	internal
DBTUNE_LIFECYCLE_RESTORED_SOURCE	internal
DBTUNE_LIFECYCLE_TARGET_HASH	internal
DBTUNE_LIFECYCLE_TARGET_IDENTITY	internal
DBTUNE_LIFECYCLE_TARGET_TOPOLOGY	internal
DBTUNE_PROGRAM	internal
DBTUNE_PROPOSAL_CURRENT	internal
DBTUNE_PROPOSAL_EVIDENCE	internal
DBTUNE_PROPOSAL_KEY	internal
DBTUNE_PROPOSAL_LINES	internal
DBTUNE_PROPOSAL_REASON_ID	internal
DBTUNE_PROPOSAL_RULE_ID	internal
DBTUNE_PROPOSAL_SEVERITY	internal
DBTUNE_PROPOSAL_VALUE	internal
DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED	internal
DBTUNE_ROLLBACK_COMPLETION_START_STATUS	internal
DBTUNE_ROLLBACK_INTENT_CREATED_AT	internal
DBTUNE_ROLLBACK_INTENT_CYCLE_ID	internal
DBTUNE_ROLLBACK_INTENT_HISTORY	internal
DBTUNE_ROLLBACK_INTENT_PREVIOUS_CURRENT	internal
DBTUNE_ROLLBACK_INTENT_PREVIOUS_STATE	internal
DBTUNE_ROLLBACK_INTENT_PROPOSAL_HASH	internal
DBTUNE_ROLLBACK_INTENT_RESTORED_BACKUP	internal
DBTUNE_ROLLBACK_INTENT_RESTORED_CYCLE_ID	internal
DBTUNE_ROLLBACK_INTENT_RESTORED_HASH	internal
DBTUNE_ROLLBACK_INTENT_RESTORED_HISTORY	internal
DBTUNE_ROLLBACK_INTENT_RESTORED_SOURCE	internal
DBTUNE_RUN_ID	internal
DBTUNE_SAMPLES_HASH	internal
DBTUNE_SQL_AUTH_METHOD	internal
DBTUNE_SQL_DEFAULTS_FILE	internal
DBTUNE_STATE_LOCK_IDENTITY	internal
DBTUNE_TSV_FIELDS	internal
DBTUNE_WORST_LINES	internal
CONTRACT
}

dbtune_runtime_prepare_environment() {
    builtin local name declaration exported_names exported_function_declarations line function_name
    builtin local function_details function_source extdebug_enabled=0
    builtin local safe_path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

    [[ $DBTUNE_ARTIFACT_PROFILE == production ]] || return 0
    exported_function_declarations=$(builtin declare -Fx) || return 65
    builtin shopt -q extdebug && extdebug_enabled=1
    builtin shopt -s extdebug || return 65
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        function_name=${line##* }
        [[ $function_name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 65
        function_details=$(builtin declare -F "$function_name") || return 65
        function_source=${function_details##* }
        if [[ $function_source == "${BASH_SOURCE[0]}" ]]; then
            # shellcheck disable=SC2163 # The function name comes from declare output.
            builtin export -n -f "$function_name" || return 65
            builtin declare -F "$function_name" >/dev/null || return 65
        else
            builtin unset -f "$function_name" || return 65
            ! builtin declare -F "$function_name" >/dev/null || return 65
        fi
    done <<<"$exported_function_declarations"
    ((extdebug_enabled == 1)) || builtin shopt -u extdebug || return 65

    declaration=$(builtin declare -p DBTUNE_ARTIFACT_PROFILE 2>/dev/null) || return 65
    [[ $declaration =~ ^declare\ -[^[:space:]]*r && $DBTUNE_ARTIFACT_PROFILE == production ]] || return 65
    declaration=$(builtin declare -p DBTUNE_ARTIFACT_VERSION 2>/dev/null) || return 65
    [[ $declaration =~ ^declare\ -[^[:space:]]*r && $DBTUNE_ARTIFACT_VERSION == 0.4.2 ]] || return 65
    for name in PATH LC_ALL LANG; do
        declaration=$(builtin declare -p "$name" 2>/dev/null || true)
        [[ ! $declaration =~ ^declare\ -[^[:space:]]*r ]] || return 65
    done

    PATH=$safe_path || return 65
    LC_ALL=C || return 65
    LANG=C || return 65
    builtin export PATH LC_ALL LANG
    [[ $PATH == "$safe_path" && $LC_ALL == C && $LANG == C ]] || return 65

    exported_names=$(builtin compgen -e) || return 65
    while IFS= read -r name; do
        [[ $name == DBTUNE_* ]] || continue
        case $name in
            DBTUNE_ARTIFACT_PROFILE|DBTUNE_ARTIFACT_VERSION|DBTUNE_UI_LANG|DBTUNE_STATE_DIR|\
            DBTUNE_CONFIG_TARGET|DBTUNE_CONFIG_ALLOWED_DIR|DBTUNE_ROOT_CNF|DBTUNE_LOG_LEVEL|\
            DBTUNE_MAX_BACKUP_AGE_SECONDS) continue ;;
        esac
        builtin unset "$name" 2>/dev/null || return 65
        [[ -z ${!name+x} ]] || return 65
    done <<<"$exported_names"

    DBTUNE_PROGRAM=dbtune || return 65
    DBTUNE_DEFAULT_DAYS=7 || return 65
    DBTUNE_SQL_AUTH_METHOD= || return 65
    DBTUNE_SQL_DEFAULTS_FILE= || return 65
    builtin export -n DBTUNE_PROGRAM DBTUNE_DEFAULT_DAYS DBTUNE_SQL_AUTH_METHOD DBTUNE_SQL_DEFAULTS_FILE 2>/dev/null || return 65
    [[ $DBTUNE_PROGRAM == dbtune && $DBTUNE_DEFAULT_DAYS == 7 && -z $DBTUNE_SQL_AUTH_METHOD &&
        -z $DBTUNE_SQL_DEFAULTS_FILE ]] || return 65
}

dbtune_runtime_command_path() {
    local name=${1:-} path directory current uid gid mode stat_path

    [[ $name =~ ^[A-Za-z0-9._+-]+$ ]] || return 64
    path=$(builtin type -P -- "$name") || return 69
    [[ $path == /* && -f $path && ! -L $path && -x $path ]] || return 69
    directory=${path%/*}
    case $directory in
        /usr/bin|/bin|/usr/sbin|/sbin|/usr/local/bin|/usr/local/sbin) ;;
        *) return 69 ;;
    esac
    if ((EUID == 0)); then
        stat_path=/usr/bin/stat
        [[ -f $stat_path && ! -L $stat_path && -x $stat_path ]] || return 69
        if "$stat_path" -c '%u %g %a' "$path" >/dev/null 2>&1; then
            read -r uid gid mode < <("$stat_path" -c '%u %g %a' "$path") || return 69
        else
            read -r uid gid mode < <("$stat_path" -f '%u %g %Lp' "$path") || return 69
        fi
        [[ $uid == 0 && $mode =~ ^[0-7]{3,4}$ ]] || return 69
        (((8#$mode & 0022) == 0)) || return 69
        current=$directory
        while :; do
            [[ -d $current && ! -L $current ]] || return 69
            if "$stat_path" -c '%u %g %a' "$current" >/dev/null 2>&1; then
                read -r uid gid mode < <("$stat_path" -c '%u %g %a' "$current") || return 69
            else
                read -r uid gid mode < <("$stat_path" -f '%u %g %Lp' "$current") || return 69
            fi
            [[ $uid == 0 && $mode =~ ^[0-7]{3,4}$ ]] || return 69
            (((8#$mode & 0022) == 0)) || return 69
            [[ $current == / ]] && break
            current=${current%/*}
            [[ -n $current ]] || current=/
        done
    fi
    builtin printf '%s\n' "$path"
}

dbtune_state_dir() {
    printf '%s\n' "$DBTUNE_STATE_DIR"
}

dbtune_state_file() {
    printf '%s/state\n' "$DBTUNE_STATE_DIR"
}

dbtune_events_file() {
    printf '%s/events.log\n' "$DBTUNE_STATE_DIR"
}

dbtune_auth_method_file() {
    printf '%s/sql-auth\n' "$DBTUNE_STATE_DIR"
}

dbtune_path() {
    if (($# != 1)) || [[ -z ${1:-} || $1 == */* || $1 == .* ]]; then
        dbtune_log error "$(dbtune_printf core_invalid_state_file_name "${1:-$(dbtune_msg core_value_empty)}")"
        return 64
    fi
    printf '%s/%s\n' "$DBTUNE_STATE_DIR" "$1"
}

dbtune_path_is_canonical_absolute() {
    local path=${1:-}

    [[ $path == /* && $path != / && $path != */ && $path != *//* && $path != *$'\n'* ]] || return 1
    [[ $path != */./* && $path != */. && $path != */../* && $path != */.. ]]
}

dbtune_file_identity() {
    local path=${1:-}

    [[ -n $path ]] || return 64
    if stat -c '%d:%i' "$path" >/dev/null 2>&1; then
        stat -c '%d:%i' "$path"
    else
        stat -f '%d:%i' "$path"
    fi
}

dbtune_file_inode() {
    local path=${1:-}

    [[ -n $path ]] || return 64
    if stat -L -c '%i' "$path" >/dev/null 2>&1; then
        stat -L -c '%i' "$path"
    else
        stat -L -f '%i' "$path"
    fi
}

dbtune_file_links() {
    local path=${1:-}

    [[ -n $path ]] || return 64
    if stat -c '%h' "$path" >/dev/null 2>&1; then
        stat -c '%h' "$path"
    else
        stat -f '%l' "$path"
    fi
}

dbtune_validate_single_link_file() {
    local file=${1:-}
    local label=${2:-$(dbtune_msg core_label_managed_file)}
    local links

    if [[ -L $file || ! -f $file ]]; then
        dbtune_log error "$(dbtune_printf core_unsafe_regular_file "$label" "$file")"
        return 65
    fi
    links=$(dbtune_file_links "$file") || return 1
    if [[ $links != 1 ]]; then
        dbtune_log error "$(dbtune_printf core_unexpected_hardlink_topology "$label" "$file" "$links")"
        return 65
    fi
}

dbtune_state_expected_uid() {
    printf '%s\n' "${DBTUNE_STATE_UID:-$EUID}"
}

dbtune_validate_state_parent_components() {
    local directory=${1:-}
    local expected_uid=${2:-}
    local component current='' uid gid mode
    local -a components

    dbtune_path_is_canonical_absolute "$directory" || {
        dbtune_log error "$(dbtune_printf core_state_dir_canonical_absolute "${directory:-$(dbtune_msg core_value_empty)}")"
        return 65
    }
    [[ $expected_uid =~ ^[0-9]+$ ]] || return 64
    IFS=/ read -r -a components <<<"${directory%/*}"
    for component in "${components[@]}"; do
        [[ -n $component ]] || continue
        current+="/$component"
        if [[ -L $current || ! -d $current ]]; then
            dbtune_log error "$(dbtune_printf core_state_parent_unsafe "$current")"
            return 65
        fi
        read -r uid gid mode < <(dbtune_file_stat "$current") || return 1
        if [[ ! $uid =~ ^[0-9]+$ || ! $mode =~ ^[0-7]{3,4}$ ||
            ($uid != 0 && $uid != "$expected_uid") ]]; then
            dbtune_log error "$(dbtune_printf core_state_parent_untrusted_metadata "$current" "$uid" "$gid" "$mode")"
            return 65
        fi
        if (((8#$mode & 0022) != 0 && ((8#$mode & 01000) == 0 || uid != 0))); then
            dbtune_log error "$(dbtune_printf core_state_parent_untrusted_writable "$current" "$uid" "$gid" "$mode")"
            return 65
        fi
    done
}

dbtune_validate_state_dir() {
    local expected_uid=${1:-}
    local expected_identity=${2:-}
    local expected_mode=${3:-}
    local uid gid mode identity

    dbtune_validate_state_parent_components "$DBTUNE_STATE_DIR" "$expected_uid" || return
    if [[ -L $DBTUNE_STATE_DIR || ! -d $DBTUNE_STATE_DIR ]]; then
        dbtune_log error "$(dbtune_printf core_state_path_unsafe "$DBTUNE_STATE_DIR")"
        return 65
    fi
    read -r uid gid mode < <(dbtune_file_stat "$DBTUNE_STATE_DIR") || return 1
    if [[ $uid != "$expected_uid" ]]; then
        dbtune_log error "$(dbtune_printf core_state_dir_wrong_owner "$DBTUNE_STATE_DIR" "$uid" "$gid")"
        return 65
    fi
    if [[ -n $expected_mode && $mode != "$expected_mode" ]]; then
        dbtune_log error "$(dbtune_printf core_state_dir_wrong_mode "$DBTUNE_STATE_DIR" "$mode")"
        return 65
    fi
    identity=$(dbtune_file_identity "$DBTUNE_STATE_DIR") || return 1
    if [[ -n $expected_identity && $identity != "$expected_identity" ]]; then
        dbtune_log error "$(dbtune_printf core_state_dir_replaced "$DBTUNE_STATE_DIR")"
        return 65
    fi
}

dbtune_init_state_dir() {
    local expected_uid identity

    expected_uid=$(dbtune_state_expected_uid) || return 1
    [[ $expected_uid =~ ^[0-9]+$ ]] || return 64
    dbtune_validate_state_parent_components "$DBTUNE_STATE_DIR" "$expected_uid" || return
    if [[ -L $DBTUNE_STATE_DIR ]]; then
        dbtune_log error "$(dbtune_printf core_state_path_symlink "$DBTUNE_STATE_DIR")"
        return 65
    elif [[ -e $DBTUNE_STATE_DIR ]]; then
        dbtune_validate_state_dir "$expected_uid" "" 700 || return
    else
        install -d -m 700 "$DBTUNE_STATE_DIR" || return 1
    fi
    dbtune_validate_state_dir "$expected_uid" "" 700 || return
    identity=$(dbtune_file_identity "$DBTUNE_STATE_DIR") || return 1
    dbtune_validate_state_dir "$expected_uid" "$identity" 700 || return
}

dbtune_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

dbtune_sanitize_text() {
    local input=${1-}
    local output='' char sequence
    local code next_code expected valid index=0 offset length

    if [[ ! $input =~ [[:cntrl:]] ]]; then
        printf '%s' "$input"
        return 0
    fi
    local LC_ALL=C

    length=${#input}
    while ((index < length)); do
        char=${input:index:1}
        printf -v code '%d' "'$char"
        if ((code < 32 || code == 127 || (code >= 128 && code <= 159))); then
            output+=' '
            index=$((index + 1))
            continue
        fi
        expected=1
        if ((code >= 194 && code <= 223)); then
            expected=2
        elif ((code >= 224 && code <= 239)); then
            expected=3
        elif ((code >= 240 && code <= 244)); then
            expected=4
        fi
        if ((expected > 1 && index + expected <= length)); then
            valid=1
            for ((offset = 1; offset < expected; offset++)); do
                char=${input:index+offset:1}
                printf -v next_code '%d' "'$char"
                if ((next_code < 128 || next_code > 191)); then
                    valid=0
                    break
                fi
            done
            if ((valid)); then
                sequence=${input:index:expected}
                if ((code == 194)); then
                    char=${input:index+1:1}
                    printf -v next_code '%d' "'$char"
                    if ((next_code >= 128 && next_code <= 159)); then
                        output+=' '
                        index=$((index + expected))
                        continue
                    fi
                fi
                output+=$sequence
                index=$((index + expected))
                continue
            fi
        fi
        output+=${input:index:1}
        index=$((index + 1))
    done
    printf '%s' "$output"
}

dbtune_key_normalize() {
    printf '%s' "${1:-}" | LC_ALL=C tr '[:upper:]-' '[:lower:]_'
}

dbtune_is_sensitive_key() {
    local key compact
    key=$(dbtune_sanitize_text "${1:-}")
    key=${key,,}
    key=${key//[!a-z0-9]/_}
    compact=${key//_/}
    case $key in
        *password*|*passwd*|pwd|pwd_*|*_pwd|*_pwd_*|*credential*|*secret*|*token*|*salt*|*private_key*) return 0 ;;
    esac
    case $compact in
        *privatekey*|*apikey*|*accesskey*|*authkey*|*clientkey*|*consumerkey*|*signingkey*|*encryptionkey*) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_proposal_key_is_safe() {
    local key=${1:-}
    [[ $key =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] && ! dbtune_is_sensitive_key "$key"
}

dbtune_proposal_value_is_safe() {
    [[ ${1:-} =~ ^[[:alnum:]_./,:+-]+$ ]]
}

dbtune_cnf_entries_strict() (
    local file=${1:-}
    local records key value extra status=0

    umask 077
    [[ -r $file ]] || return 65
    dbtune_validate_single_link_file "$file" >/dev/null 2>&1 || return 65
    records=$(mktemp "${TMPDIR:-/tmp}/dbtune-cnf-records.XXXXXX") || return 1
    trap 'rm -f "$records"' EXIT HUP INT TERM
    LC_ALL=C awk -v output="$records" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function reject() { bad=1 }
        {
            line=$0
            if (line ~ /[[:cntrl:]]/) { reject(); next }
            stripped=trim(line)
            if (stripped == "" || stripped ~ /^[#;]/) next
            if (stripped ~ /^\[/) {
                if (stripped != "[mysqld]" || section_seen) { reject(); next }
                section_seen=1
                active=1
                next
            }
            equals=gsub(/=/, "&", stripped)
            if (!active || stripped ~ /^!/ || equals != 1) { reject(); next }
            separator=index(stripped, "=")
            raw_key=trim(substr(stripped, 1, separator - 1))
            value=trim(substr(stripped, separator + 1))
            if (raw_key !~ /^[A-Za-z][A-Za-z0-9_-]*$/ || value == "") { reject(); next }
            canonical=tolower(raw_key)
            gsub(/-/, "_", canonical)
            if (canonical in seen) { reject(); next }
            seen[canonical]=1
            keys[++count]=canonical
            values[count]=value
        }
        END {
            if (bad || !section_seen || count < 1) exit 65
            for (position=1; position<=count; position++) print keys[position] "\t" values[position] > output
            close(output)
        }
    ' "$file" || status=$?
    ((status == 0)) || return 65
    while IFS=$'\t' read -r key value extra || [[ -n $key || -n $value || -n $extra ]]; do
        [[ -n $key && -n $value && -z $extra ]] || return 65
        dbtune_proposal_key_is_safe "$key" && dbtune_proposal_value_is_safe "$value" || return 65
    done <"$records"
    command cat "$records"
)

dbtune_redact() {
    local value lower key quote char prefix suffix
    local index key_start key_end value_start value_end escaped

    value=$(dbtune_sanitize_text "${1:-}")
    lower=${value,,}
    case $lower in
        *pass*|*pwd*|*credential*|*secret*|*token*|*salt*|*api*key*|*access*key*|*auth*key*|\
        *client*key*|*consumer*key*|*private*key*|*signing*key*|*encryption*key*|*' -p'*) ;;
        *)
            printf '%s' "$value"
            return 0
            ;;
    esac
    index=0
    while ((index < ${#value})); do
        char=${value:index:1}
        if [[ $char != = && $char != : ]]; then
            index=$((index + 1))
            continue
        fi
        key_end=$index
        while ((key_end > 0)) && [[ ${value:key_end-1:1} == [[:space:]] ]]; do
            key_end=$((key_end - 1))
        done
        key_start=$key_end
        quote=''
        if ((key_end > 0)) && [[ ${value:key_end-1:1} == "'" || ${value:key_end-1:1} == '"' ]]; then
            quote=${value:key_end-1:1}
            key_end=$((key_end - 1))
            key_start=$key_end
            while ((key_start > 0)) && [[ ${value:key_start-1:1} != "$quote" ]]; do
                key_start=$((key_start - 1))
            done
        else
            while ((key_start > 0)) && [[ ${value:key_start-1:1} == [[:alnum:]_.\ -] ]]; do
                key_start=$((key_start - 1))
            done
        fi
        key=${value:key_start:key_end-key_start}
        if ! dbtune_is_sensitive_key "$key"; then
            index=$((index + 1))
            continue
        fi
        value_start=$((index + 1))
        while ((value_start < ${#value})) && [[ ${value:value_start:1} == [[:space:]] ]]; do
            value_start=$((value_start + 1))
        done
        value_end=$value_start
        quote=${value:value_start:1}
        if [[ $quote == "'" || $quote == '"' ]]; then
            value_end=$((value_start + 1))
            escaped=0
            while ((value_end < ${#value})); do
                char=${value:value_end:1}
                value_end=$((value_end + 1))
                if ((escaped)); then
                    escaped=0
                elif [[ $char == \\ ]]; then
                    escaped=1
                elif [[ $char == "$quote" ]]; then
                    break
                fi
            done
        else
            while ((value_end < ${#value})); do
                char=${value:value_end:1}
                case $char in
                    [[:space:]]|\;|,) break ;;
                esac
                value_end=$((value_end + 1))
            done
        fi
        prefix=${value:0:value_start}
        suffix=${value:value_end}
        value="${prefix}[REDACTED]${suffix}"
        index=$((${#prefix} + 10))
    done
    printf '%s' "$value" | sed -E \
        -e 's/(--password([=[:space:]]+))[^[:space:]]+/\1[REDACTED]/Ig' \
        -e 's/(^|[[:space:]])-p[^[:space:]]+/\1-p[REDACTED]/g'
}

dbtune_audit_key_canonical() {
    local key flat suffix

    key=$(dbtune_key_normalize "${1:-}")
    flat=${key//./_}
    case $flat in
        version|mariadb|mariadb_version|mariadb_server_version|server_mariadb_version)
            printf 'mariadb.version\n'
            ;;
        mysql_version|server_mysql_version)
            printf 'mysql.version\n'
            ;;
        server_version)
            printf 'server.version\n'
            ;;
        database_family|server_family|sql_server_family)
            printf 'database.family\n'
            ;;
        hostname|host_name|server_hostname|audit_hostname)
            printf 'audit.hostname\n'
            ;;
        os|os_version|server_os)
            printf 'audit.os\n'
            ;;
        cpu_count|cpu_cores|cpu_cores_count|hw_cpu_count)
            printf 'hw.cpu_count\n'
            ;;
        hw_ram_bytes|memory_total_bytes|memory_total_mb|ram_total|ram_total_bytes|ram_bytes|ram_mb)
            printf 'hw.ram_bytes\n'
            ;;
        memory_total_kb|mem_total_kb|ram_kb|ram_total_kb)
            printf 'ram_total_kb\n'
            ;;
        hw_ram_available_bytes|mem_available_bytes|memory_available_bytes)
            printf 'hw.ram_available_bytes\n'
            ;;
        mariadb_dataset_bytes|database_size_bytes|total_dataset_bytes|db_size_bytes|dataset_size|dataset_bytes|dataset_mb|dataset_total_mb)
            printf 'mariadb.dataset_bytes\n'
            ;;
        php_fpm_max_children_sum|php_fpm_max_children|pm_max_children|fpm_max_children_sum|pm_max_children_sum)
            printf 'php_fpm.max_children_sum\n'
            ;;
        max_connections_used|peak_connections|max_used_connections)
            printf 'mariadb.status.max_used_connections\n'
            ;;
        hw_storage_class|disk_type|disk_class|storage_type|storage_class)
            printf 'hw.storage_class\n'
            ;;
        runcloud_skip_log_bin|skip_log_bin)
            printf 'runcloud.skip_log_bin\n'
            ;;
        security_remote_grant_count|remote_grant_count)
            printf 'security.remote_grant_count\n'
            ;;
        security_port_3306|port_3306)
            printf 'security.port_3306\n'
            ;;
        security_root_cnf_present|root_cnf_present)
            printf 'security.root_cnf_present\n'
            ;;
        limit_nofile|systemd_limit_nofile)
            printf 'systemd.limit_nofile\n'
            ;;
        unattended_mariadb|unattended_mariadb_origin)
            printf 'unattended.mariadb_origin\n'
            ;;
        backup|backup_enabled)
            printf 'backup.enabled\n'
            ;;
        mariadb_variable_*|mysql_variable_*|variables_*|variable_*)
            suffix=$flat
            suffix=${suffix#mariadb_variable_}
            suffix=${suffix#mysql_variable_}
            suffix=${suffix#variables_}
            suffix=${suffix#variable_}
            printf 'mariadb.variable.%s\n' "$suffix"
            ;;
        mariadb_status_*|mysql_status_*|status_*)
            suffix=$flat
            suffix=${suffix#mariadb_status_}
            suffix=${suffix#mysql_status_}
            suffix=${suffix#status_}
            printf 'mariadb.status.%s\n' "$suffix"
            ;;
        buffer_pool_size)
            printf 'mariadb.variable.innodb_buffer_pool_size\n'
            ;;
        innodb_*|max_connections|query_cache_type|query_cache_size|skip_name_resolve|thread_cache_size|tmp_table_size|max_heap_table_size|table_definition_cache|key_buffer_size|slow_query_log|slow_query_log_file|long_query_time|log_slow_verbosity|open_files_limit|performance_schema|log_bin|wsrep_on|bind_address|datadir)
            printf 'mariadb.variable.%s\n' "$flat"
            ;;
        uptime|questions|com_select|created_tmp_disk_tables|created_tmp_tables|handler_read_rnd_next|qcache_hits|slow_queries|key_read_requests|aborted_connects|threads_running|threads_connected)
            printf 'mariadb.status.%s\n' "$flat"
            ;;
        effective_open_files_limit)
            printf 'mariadb.variable.open_files_limit\n'
            ;;
        audit_*|backup_*|app_*|finding_*|hw_*|mariadb_*|php_fpm_*|redis_*|runcloud_*|security_*|systemd_*|unattended_*)
            if [[ $key == "$flat" ]]; then
                suffix=${flat#*_}
                printf '%s.%s\n' "${flat%%_*}" "$suffix"
            else
                printf '%s\n' "$key"
            fi
            ;;
        *)
            printf '%s\n' "$key"
            ;;
    esac
}

dbtune_audit_normalize() {
    local file=${1:-}
    local raw_key value rest canonical diagnostic line=0
    local -a order=()
    local -A seen=() values=() first_lines=()

    [[ -r $file ]] || return 66
    while IFS=$'\t' read -r raw_key value rest || [[ -n ${raw_key:-} ]]; do
        line=$((line + 1))
        value=${value%$'\r'}
        [[ -n $raw_key ]] || continue
        if [[ $(dbtune_key_normalize "$raw_key") == key && $(dbtune_key_normalize "$value") == value ]]; then
            continue
        fi
        canonical=$(dbtune_audit_key_canonical "$raw_key") || return
        [[ -n $canonical ]] || continue
        if [[ ! $canonical =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
            dbtune_eprintf core_invalid_audit_key "$line"
            return 65
        fi
        if [[ -n ${seen[$canonical]+x} ]]; then
            if [[ ${values[$canonical]} != "$value" ]]; then
                diagnostic=$canonical
                dbtune_is_sensitive_key "$raw_key" && diagnostic='[REDACTED]'
                dbtune_eprintf core_conflicting_audit_value \
                    "$diagnostic" "${first_lines[$canonical]}" "$line"
                return 65
            fi
            continue
        fi
        seen["$canonical"]=1
        values["$canonical"]=$value
        first_lines["$canonical"]=$line
        order+=("$canonical")
    done <"$file"

    for canonical in "${order[@]}"; do
        printf '%s\t%s\n' "$canonical" "${values[$canonical]}"
    done
}

dbtune_audit_validate() {
    dbtune_audit_normalize "${1:-}" >/dev/null
}

dbtune_log() {
    local level=${1:-info}
    local message=${2:-}
    local threshold=20
    local value=20

    case $DBTUNE_LOG_LEVEL in
        debug) threshold=10 ;;
        info) threshold=20 ;;
        warn) threshold=30 ;;
        error) threshold=40 ;;
        quiet) threshold=100 ;;
    esac
    case $level in
        debug) value=10 ;;
        info) value=20 ;;
        warn) value=30 ;;
        error) value=40 ;;
        *) level=info ;;
    esac
    ((value < threshold)) && return 0
    printf '%s [%s] %s\n' "$(dbtune_now)" "${level^^}" "$(dbtune_redact "$message")" >&2
}

dbtune_log_debug() { dbtune_log debug "$*"; }
dbtune_log_info() { dbtune_log info "$*"; }
dbtune_log_warn() { dbtune_log warn "$*"; }
dbtune_log_error() { dbtune_log error "$*"; }

dbtune_atomic_write() {
    local target=${1:-}
    local mode=${2:-600}
    local directory base temporary

    [[ -n $target ]] || {
        dbtune_log error "$(dbtune_msg core_atomic_target_required)"
        return 64
    }
    [[ $mode =~ ^0?[0-7]{3}$ ]] || {
        dbtune_log error "$(dbtune_printf core_atomic_mode_invalid "$mode")"
        return 64
    }

    directory=${target%/*}
    [[ $directory != "$target" ]] || directory=.
    base=${target##*/}
    [[ -d $directory ]] || install -d -m 700 "$directory" || return 1
    temporary=$(mktemp "$directory/.${base}.tmp.XXXXXX") || return 1
    if ! chmod "$mode" "$temporary" || ! command cat >"$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if ! mv -f "$temporary" "$target"; then
        rm -f "$temporary"
        return 1
    fi
}

dbtune_is_uint() {
    [[ ${1:-} =~ ^(0|[1-9][0-9]*)$ ]]
}

dbtune_require_uint() {
    local name=${1:-argument}
    local value=${2:-}
    local minimum=${3:-0}
    local maximum=${4:-2147483647}

    if ! dbtune_is_uint "$value"; then
        dbtune_log error "$(dbtune_printf core_uint_required "$name")"
        return 64
    fi
    if ! dbtune_is_uint "$minimum" || ! dbtune_is_uint "$maximum" || ((minimum > maximum)); then
        dbtune_log error "$(dbtune_printf core_uint_internal_range "$name")"
        return 70
    fi
    if ((value < minimum || value > maximum)); then
        dbtune_log error "$(dbtune_printf core_uint_range "$name" "$minimum" "$maximum")"
        return 64
    fi
}

dbtune_json_escape() {
    local input=${1-}
    local output=''
    local char code i

    for ((i = 0; i < ${#input}; i++)); do
        char=${input:i:1}
        case $char in
            '"') output+='\"' ;;
            \\) output+="\\\\" ;;
            $'\b') output+='\b' ;;
            $'\f') output+='\f' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *)
                printf -v code '%d' "'$char"
                if ((code < 32)); then
                    printf -v char '\\u%04x' "$code"
                fi
                output+=$char
                ;;
        esac
    done
    printf '%s' "$output"
}

dbtune_json_emit() {
    local output='{'
    local separator=''
    local key value

    if (($# % 2 != 0)); then
        dbtune_log error "$(dbtune_msg core_json_pairs_required)"
        return 64
    fi
    while (($#)); do
        key=$1
        value=$2
        shift 2
        output+="${separator}\"$(dbtune_json_escape "$key")\":\"$(dbtune_json_escape "$value")\""
        separator=','
    done
    printf '%s}\n' "$output"
}

dbtune_shell_quote() {
    local value=${1-}

    printf "'%s'" "${value//\'/\'\\\'\'}"
}

dbtune_uint64_valid() {
    local value=${1:-}
    local LC_ALL=C

    [[ $value =~ ^(0|[1-9][0-9]*)$ ]] || return 1
    ((${#value} < 20)) && return 0
    ((${#value} == 20)) || return 1
    # String ordering is intentional after equal-length canonical validation.
    # shellcheck disable=SC2071
    [[ $value < 18446744073709551615 || $value == 18446744073709551615 ]]
}

dbtune_uint64_compare() {
    local left=${1:-} right=${2:-}
    local LC_ALL=C

    dbtune_uint64_valid "$left" && dbtune_uint64_valid "$right" || return 65
    if ((${#left} < ${#right})); then
        printf '%s\n' -1
    elif ((${#left} > ${#right})); then
        printf '%s\n' 1
    elif [[ $left == "$right" ]]; then
        printf '%s\n' 0
    elif [[ $left < $right ]]; then
        printf '%s\n' -1
    else
        printf '%s\n' 1
    fi
}

dbtune_uint64_subtract() {
    local high=${1:-} low=${2:-}
    local comparison high_index low_index high_digit low_digit digit borrow=0 result=''

    comparison=$(dbtune_uint64_compare "$high" "$low") || return
    ((comparison >= 0)) || return 65
    high_index=$((${#high} - 1))
    low_index=$((${#low} - 1))
    while ((high_index >= 0)); do
        high_digit=${high:high_index:1}
        if ((low_index >= 0)); then
            low_digit=${low:low_index:1}
        else
            low_digit=0
        fi
        digit=$((high_digit - borrow - low_digit))
        if ((digit < 0)); then
            digit=$((digit + 10))
            borrow=1
        else
            borrow=0
        fi
        result="$digit$result"
        high_index=$((high_index - 1))
        low_index=$((low_index - 1))
    done
    while ((${#result} > 1)) && [[ ${result:0:1} == 0 ]]; do
        result=${result:1}
    done
    printf '%s\n' "$result"
}

dbtune_uint64_add() {
    local left=${1:-} right=${2:-}
    local left_index right_index left_digit right_digit digit carry=0 result=''

    dbtune_uint64_valid "$left" && dbtune_uint64_valid "$right" || return 65
    left_index=$((${#left} - 1))
    right_index=$((${#right} - 1))
    while ((left_index >= 0 || right_index >= 0 || carry)); do
        if ((left_index >= 0)); then left_digit=${left:left_index:1}; else left_digit=0; fi
        if ((right_index >= 0)); then right_digit=${right:right_index:1}; else right_digit=0; fi
        digit=$((left_digit + right_digit + carry))
        carry=$((digit / 10))
        result="$((digit % 10))$result"
        left_index=$((left_index - 1))
        right_index=$((right_index - 1))
    done
    dbtune_uint64_valid "$result" || return 65
    printf '%s\n' "$result"
}

dbtune_status_snapshot_exact() {
    local raw=${1-} line key value normalized expected_key
    local -a expected_keys=("${@:2}")
    local -A allowed=() seen=() values=()

    for expected_key in "${expected_keys[@]}"; do
        allowed[$expected_key]=1
    done
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line == *$'\t'* ]] || return 65
        key=${line%%$'\t'*}
        value=${line#*$'\t'}
        [[ $value != *$'\t'* ]] || return 65
        normalized=${key,,}
        [[ -n ${allowed[$normalized]+x} && -z ${seen[$normalized]+x} ]] || return 65
        dbtune_uint64_valid "$value" || return 65
        seen[$normalized]=1
        values[$normalized]=$value
    done <<<"$raw"
    for expected_key in "${expected_keys[@]}"; do
        [[ -n ${seen[$expected_key]+x} ]] || return 65
    done
    for expected_key in "${expected_keys[@]}"; do
        printf '%s\t%s\n' "$expected_key" "${values[$expected_key]}"
    done
}

dbtune_samples_inspect() {
    local file=${1:-}
    local mode=${2:-diagnostics}

    [[ -r $file ]] || return 66
    [[ $mode == diagnostics || $mode == count || $mode == rows ]] || return 64
    awk -F '\t' -v mode="$mode" '
        function is_number(value) { return value ~ /^[0-9]+([.][0-9]+)?$/ }
        function is_uint(value, max, i, digit, limit) {
            if (value !~ /^(0|[1-9][0-9]*)$/ || length(value) > 20) return 0
            if (length(value) < 20) return 1
            max="18446744073709551615"
            for (i=1; i<=20; i++) {
                digit=substr(value, i, 1)+0; limit=substr(max, i, 1)+0
                if (digit < limit) return 1
                if (digit > limit) return 0
            }
            return 1
        }
        function is_timestamp(value, year, month, day, hour, minute, second, leap, month_days) {
            if (value !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/) return 0
            year=substr(value, 1, 4)+0
            month=substr(value, 6, 2)+0; day=substr(value, 9, 2)+0
            hour=substr(value, 12, 2)+0; minute=substr(value, 15, 2)+0; second=substr(value, 18, 2)+0
            if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) return 0
            split("31 28 31 30 31 30 31 31 30 31 30 31", month_days, " ")
            leap=(year%400==0 || (year%4==0 && year%100!=0))
            if (leap) month_days[2]=29
            return day >= 1 && day <= month_days[month]
        }
        function row_reason(legacy_extended, status, i) {
            if (NF < expected_fields) return "truncated"
            if (NF > expected_fields) return "extra_fields"
            if (!is_timestamp($1)) return "invalid_timestamp"
            for (i=2; i<=17; i++) if (!is_number($i)) return "non_numeric"
            if (!is_uint($2) || !is_uint($8) || !is_uint($9) || !is_uint($11) ||
                !is_uint($12) || !is_uint($14) || !is_uint($15) || !is_uint($17)) return "invalid_value"
            if ($3 > 100 || $7 > 100 || $10 > 100 || $17 > 1) return "invalid_value"
            if (expected_fields == 17) return ""
            status=$20
            if (status != "ok" && status != "degraded_interval" &&
                status != "degraded_counter_reset" && status != "degraded_counter_inconsistent" &&
                status != "degraded_restart_identity") return "invalid_value"
            legacy_extended=($18 == "" && $19 == "")
            if (($18 == "") != ($19 == "")) return "non_numeric"
            if (legacy_extended) return status == "ok" ? "" : "non_numeric"
            if (!is_uint($18) || !is_number($19)) return "non_numeric"
            if ($19 <= 0 && status == "ok") return "non_monotonic"
            if (new_schema && $18 == "0" && $10 + 0 != 0) return "invalid_value"
            return ""
        }
        BEGIN {
            OFS="\t"
            canonical="timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tcom_select_delta\tinterval_seconds\tsample_status"
            old20="timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tqcache_queries_delta\tinterval_seconds\tsample_status"
            legacy="timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag"
        }
        NR == 1 {
            sub(/\r$/, "")
            if ($0 == canonical) { expected_fields=20; new_schema=1 }
            else if ($0 == old20) expected_fields=20
            else if ($0 == legacy) expected_fields=17
            else { bad_header=1; exit 65 }
            if (mode == "rows") print
            next
        }
        $0 != "" {
            sub(/\r$/, "", $NF)
            reason=row_reason()
            if (reason != "") {
                rejected++
                rejected_reason[reason]++
                next
            }
            status=(expected_fields == 20) ? $20 : "ok"
            if (status != "ok") excluded_status++
            else if ($17 != 0) excluded_restart++
            else {
                valid++
                if (mode == "rows") print
            }
        }
        END {
            if (bad_header) exit 65
            if (!expected_fields) exit 65
            if (mode == "count") print valid+0
            else if (mode == "diagnostics") {
                print "valid_rows", valid+0
                print "rejected_rows", rejected+0
                print "excluded_status_rows", excluded_status+0
                print "excluded_restart_rows", excluded_restart+0
                printf "rejected_reasons\ttruncated=%d,extra_fields=%d,non_numeric=%d,invalid_timestamp=%d,invalid_value=%d,non_monotonic=%d\n",
                    rejected_reason["truncated"]+0, rejected_reason["extra_fields"]+0,
                    rejected_reason["non_numeric"]+0, rejected_reason["invalid_timestamp"]+0,
                    rejected_reason["invalid_value"]+0, rejected_reason["non_monotonic"]+0
            }
        }
    ' "$file"
}

dbtune_samples_valid_rows() {
    dbtune_samples_inspect "${1:-}" rows
}

dbtune_samples_diagnostics() {
    dbtune_samples_inspect "${1:-}" diagnostics
}

dbtune_samples_diagnostic_value() {
    local file=${1:-}
    local wanted=${2:-}

    dbtune_samples_diagnostics "$file" | awk -F '\t' -v wanted="$wanted" '$1 == wanted { print $2; found=1; exit } END { if (!found) exit 1 }'
}

dbtune_tsv_percentile() {
    local file=${1:-}
    local aliases=${2:-}
    local fallback=${3:-1}
    local percentile=${4:-}
    local filter=${5:-valid}

    [[ -r $file && -n $aliases && $fallback =~ ^[1-9][0-9]*$ ]] || return 64
    [[ $percentile =~ ^[0-9]+([.][0-9]+)?$ ]] || return 64
    [[ $filter == valid || $filter == qcache-active ]] || return 64
    dbtune_samples_diagnostics "$file" >/dev/null || return 65
    awk -F '\t' -v aliases="$aliases" -v fallback="$fallback" -v filter="$filter" '
        function norm(value) { value=tolower(value); gsub(/-/, "_", value); return value }
        BEGIN { wanted_count=split(aliases, wanted, ","); column=fallback }
        NR == 1 {
            found=0
            header=(norm($1) == "timestamp" || norm($1) == "sampled_at" || norm($1) == "time" || norm($1) == "ts")
            for (i=1; i<=NF; i++) {
                name=norm($i)
                if (name == "sample_status") status_column=i
                if (name == "restart_flag") restart_column=i
                if (name == "com_select_delta" || name == "qcache_queries_delta") qcache_queries_column=i
                for (j=1; j<=wanted_count; j++) if (name == wanted[j]) { column=i; found=1 }
            }
            if (header) { if (!found) column=0; next }
        }
        column > 0 && (!status_column || $status_column == "ok") &&
        (!restart_column || $restart_column == 0) &&
        (filter != "qcache-active" || (qcache_queries_column && $qcache_queries_column ~ /^[0-9]+([.][0-9]+)?$/ && $qcache_queries_column + 0 > 0)) &&
        (filter != "qcache-active" || ($column + 0 >= 0 && $column + 0 <= 100)) &&
        $column ~ /^-?[0-9]+([.][0-9]+)?$/ { print $column + 0 }
    ' < <(dbtune_samples_valid_rows "$file") | LC_ALL=C sort -n | awk -v percentile="$percentile" '
        { values[NR]=$1 }
        END {
            if (!NR || percentile < 0 || percentile > 100) exit 65
            rank=int((percentile * NR + 99.999999) / 100)
            if (rank < 1) rank=1
            if (rank > NR) rank=NR
            printf "%.6g\n", values[rank]
        }
    '
}

dbtune_sha256_file() {
    local file=${1:-}

    [[ -r $file ]] || return 66
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        dbtune_log error "$(dbtune_msg core_hash_tool_missing)"
        return 69
    fi
}

dbtune_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        dbtune_log error "$(dbtune_msg core_hash_tool_missing)"
        return 69
    fi
}

dbtune_file_stat() {
    local file=${1:-}

    [[ -n $file ]] || return 64
    if stat -c '%u %g %a' "$file" >/dev/null 2>&1; then
        stat -c '%u %g %a' "$file"
    else
        stat -f '%u %g %Lp' "$file"
    fi
}

dbtune_backup_evidence_file() {
    printf '%s\n' "${DBTUNE_BACKUP_EVIDENCE_FILE:-$DBTUNE_STATE_DIR/backup-evidence.tsv}"
}

dbtune_iso8601_epoch() {
    local timestamp=${1:-}

    awk -v timestamp="$timestamp" 'BEGIN {
        if (timestamp !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) exit 1
        year=substr(timestamp,1,4)+0; month=substr(timestamp,6,2)+0; day=substr(timestamp,9,2)+0
        hour=substr(timestamp,12,2)+0; minute=substr(timestamp,15,2)+0; second=substr(timestamp,18,2)+0
        if (year < 1970 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) exit 1
        leap=(year%400==0 || (year%4==0 && year%100!=0))
        split("31 28 31 30 31 30 31 31 30 31 30 31", month_days, " ")
        if (leap) month_days[2]=29
        if (day < 1 || day > month_days[month]) exit 1
        days=365*(year-1)+int((year-1)/4)-int((year-1)/100)+int((year-1)/400)
        for (i=1; i<month; i++) days+=month_days[i]
        days+=day
        printf "%.0f\n", (days-719163)*86400+hour*3600+minute*60+second
    }'
}

dbtune_backup_evidence_validate() {
    local file=${1:-}
    local uid gid mode expected_uid max_age now_epoch checked_epoch success_epoch
    local status checked success

    DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS=unknown
    DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS=${DBTUNE_MAX_BACKUP_AGE_SECONDS:-86400}
    DBTUNE_BACKUP_EVIDENCE_ERROR=invalid

    max_age=$DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS
    if [[ ! $max_age =~ ^[1-9][0-9]{0,9}$ ]] || ((max_age > 2147483647)); then
        DBTUNE_BACKUP_EVIDENCE_ERROR=invalid_max_age_policy
        return 64
    fi

    if [[ ! -f $file || -L $file ]]; then
        DBTUNE_BACKUP_EVIDENCE_ERROR=unsafe_or_missing_file
        return 66
    fi
    read -r uid gid mode < <(dbtune_file_stat "$file") || return 1
    expected_uid=${DBTUNE_BACKUP_EVIDENCE_UID:-0}
    if [[ ! $expected_uid =~ ^[0-9]+$ ]]; then
        DBTUNE_BACKUP_EVIDENCE_ERROR=invalid_expected_uid
        return 64
    fi
    if [[ ! $uid =~ ^[0-9]+$ || ! $gid =~ ^[0-9]+$ || $uid != "$expected_uid" || ($mode != 400 && $mode != 600) ]]; then
        DBTUNE_BACKUP_EVIDENCE_ERROR=unsafe_permissions
        return 65
    fi
    if ! awk -F '\t' '
        NF != 2 || seen[$1]++ { bad=1; next }
        $1 == "schema" { schema=$2; next }
        $1 == "status" { status=$2; next }
        $1 == "source" { source=$2; next }
        $1 == "checked_at" { checked=$2; next }
        $1 == "last_success" { success=$2; next }
        { bad=1 }
        END {
            timestamp="^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
            if (bad || length(seen) != 5 || schema != "1" || checked !~ timestamp) exit 1
            if (source == "" || source == "unknown") exit 1
            if (status == "verified") exit !(success ~ timestamp)
            if (status == "missing") exit !(success == "none")
            if (status == "unknown") exit !(success == "unknown")
            exit 1
        }
    ' "$file"; then
        DBTUNE_BACKUP_EVIDENCE_ERROR=invalid_contract
        return 65
    fi

    status=$(dbtune_manifest_value "$file" status) || return 65
    checked=$(dbtune_manifest_value "$file" checked_at) || return 65
    success=$(dbtune_manifest_value "$file" last_success) || return 65
    checked_epoch=$(dbtune_iso8601_epoch "$checked") || {
        DBTUNE_BACKUP_EVIDENCE_ERROR=malformed_checked_at
        return 65
    }
    if [[ -n ${DBTUNE_NOW_EPOCH:-} ]]; then
        now_epoch=$DBTUNE_NOW_EPOCH
        if [[ ! $now_epoch =~ ^[0-9]{1,12}$ ]]; then
            DBTUNE_BACKUP_EVIDENCE_ERROR=invalid_current_time
            return 70
        fi
    else
        now_epoch=$(dbtune_iso8601_epoch "$(dbtune_now)") || {
            DBTUNE_BACKUP_EVIDENCE_ERROR=invalid_current_time
            return 70
        }
    fi
    if ((checked_epoch > now_epoch)); then
        DBTUNE_BACKUP_EVIDENCE_ERROR=future_checked_at
        return 65
    fi
    if [[ $status == verified ]]; then
        success_epoch=$(dbtune_iso8601_epoch "$success") || {
            DBTUNE_BACKUP_EVIDENCE_ERROR=malformed_last_success
            return 65
        }
        DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS=$((now_epoch - success_epoch))
        if ((success_epoch > now_epoch)); then
            DBTUNE_BACKUP_EVIDENCE_ERROR=future_last_success
            return 65
        fi
        if ((success_epoch > checked_epoch)); then
            DBTUNE_BACKUP_EVIDENCE_ERROR=last_success_after_checked_at
            return 65
        fi
        if ((DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS > max_age)); then
            DBTUNE_BACKUP_EVIDENCE_ERROR=expired
            return 65
        fi
    fi
    # shellcheck disable=SC2034 # Read by lifecycle and audit after validation.
    DBTUNE_BACKUP_EVIDENCE_ERROR=none
}

dbtune_run_id() {
    local stamp random

    stamp=$(date -u '+%Y%m%dT%H%M%SZ') || return 1
    printf -v random '%05d%05d' "$RANDOM" "$RANDOM"
    printf '%s-%s-%s\n' "$stamp" "$$" "$random"
}

dbtune_manifest_value() {
    local manifest=${1:-}
    local key=${2:-}

    [[ -r $manifest && -n $key ]] || return 1
    awk -F '\t' -v wanted="$key" '$1 == wanted {sub(/^[^\t]*\t/, ""); print; found=1; exit} END {if (!found) exit 1}' "$manifest"
}

dbtune_manifest_validate_exact() (
    local manifest=${1:-}
    local schema=${2:-}
    local schema_file

    [[ -r $manifest && -n $schema ]] || return 65
    dbtune_validate_single_link_file "$manifest" >/dev/null 2>&1 || return 65
    umask 077
    schema_file=$(mktemp "${TMPDIR:-/tmp}/dbtune-manifest-schema.XXXXXX") || return 1
    trap 'rm -f "$schema_file"' EXIT HUP INT TERM
    printf '%s\n' "$schema" >"$schema_file" || return 1
    LC_ALL=C awk -F '\t' '
        FILENAME == ARGV[1] {
            if (NF != 1 || $1 == "" || $1 ~ /[[:cntrl:]]/ || $1 in required) schema_bad=1
            required[$1]=1
            next
        }
        NF != 2 || $1 ~ /[[:cntrl:]]/ || $2 ~ /[[:cntrl:]]/ || !($1 in required) || ($1 in seen) { bad=1; next }
        { seen[$1]=1 }
        END {
            if (schema_bad || bad) exit 65
            for (name in required) if (!(name in seen)) exit 65
        }
    ' "$schema_file" "$manifest" || return 65
)

dbtune_audit_manifest_file() {
    dbtune_path audit-manifest.tsv
}

dbtune_analysis_manifest_file() {
    dbtune_path analysis-manifest.tsv
}

dbtune_provenance_audit_hash() {
    local audit_hash=${1:-}
    local apps_hash=${2:-}
    local databases_hash=${3:-}

    printf 'audit.tsv\t%s\napps.tsv\t%s\ndatabases.tsv\t%s\n' \
        "$audit_hash" "$apps_hash" "$databases_hash" | dbtune_sha256_stream
}

dbtune_provenance_write_audit_manifest() {
    local output=${1:-}
    local run_id=${2:-}
    local audit=${3:-}
    local apps=${4:-}
    local databases=${5:-}
    local audit_file_hash apps_hash databases_hash audit_hash

    [[ -n $output && $run_id =~ ^[A-Za-z0-9._-]+$ ]] || return 64
    audit_file_hash=$(dbtune_sha256_file "$audit") || return
    apps_hash=$(dbtune_sha256_file "$apps") || return
    databases_hash=$(dbtune_sha256_file "$databases") || return
    audit_hash=$(dbtune_provenance_audit_hash "$audit_file_hash" "$apps_hash" "$databases_hash") || return
    {
        printf 'schema\t1\n'
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'audit.tsv\t%s\n' "$audit_file_hash"
        printf 'apps.tsv\t%s\n' "$apps_hash"
        printf 'databases.tsv\t%s\n' "$databases_hash"
    } | dbtune_atomic_write "$output" 600
}

dbtune_provenance_validate_audit() {
    local manifest audit apps databases run_id expected actual
    local audit_file_hash apps_hash databases_hash audit_hash

    manifest=$(dbtune_audit_manifest_file) || return
    audit=$(dbtune_path audit.tsv) || return
    apps=$(dbtune_path apps.tsv) || return
    databases=$(dbtune_path databases.tsv) || return
    [[ -r $manifest ]] || {
        dbtune_log error "$(dbtune_printf core_audit_manifest_missing "$manifest")"
        return 66
    }
    run_id=$(dbtune_manifest_value "$manifest" run_id) || return 65
    [[ $run_id =~ ^[A-Za-z0-9._-]+$ ]] || return 65
    for expected in audit.tsv apps.tsv databases.tsv; do
        actual=$(dbtune_manifest_value "$manifest" "$expected") || return 65
        [[ $actual =~ ^[0-9a-f]{64}$ && -r $DBTUNE_STATE_DIR/$expected ]] || return 65
        if [[ $(dbtune_sha256_file "$DBTUNE_STATE_DIR/$expected") != "$actual" ]]; then
            dbtune_log error "$(dbtune_printf core_audit_artifact_mismatch "$expected" "$run_id")"
            return 65
        fi
    done
    audit_file_hash=$(dbtune_manifest_value "$manifest" audit.tsv) || return 65
    apps_hash=$(dbtune_manifest_value "$manifest" apps.tsv) || return 65
    databases_hash=$(dbtune_manifest_value "$manifest" databases.tsv) || return 65
    audit_hash=$(dbtune_provenance_audit_hash "$audit_file_hash" "$apps_hash" "$databases_hash") || return
    expected=$(dbtune_manifest_value "$manifest" audit_hash) || return 65
    if [[ $expected != "$audit_hash" ]]; then
        dbtune_log error "$(dbtune_printf core_audit_hash_mismatch "$run_id")"
        return 65
    fi
}

dbtune_dbsize_selected_rows() {
    local file=${1:-}

    [[ -r $file ]] || return 66
    awk -F '\t' '
        BEGIN { OFS="\t" }
        NR == 1 {
            if (!(($1 == "timestamp" || $1 == "date") &&
                ($2 == "database" || $2 == "db") && $3 == "size_bytes" && NF == 3)) exit 65
            next
        }
        {
            timestamp=trim($1); database=trim($2); size=trim($3); date=substr(timestamp, 1, 10)
            if (NF < 3 || timestamp == "" || database == "" || !valid_date(date) ||
                size !~ /^[0-9]+([.][0-9]+)?$/) next
            key=timestamp SUBSEP database
            if (!(key in snapshot_size)) {
                snapshot_count[timestamp]++
                if (!(timestamp in snapshot_seen)) {
                    snapshot_seen[timestamp]=1
                    snapshot_day[timestamp]=date
                    snapshots[++snapshot_total]=timestamp
                }
            }
            snapshot_size[key]=size
        }
        END {
            if (NR == 0) exit 65
            for (i=1; i<=snapshot_total; i++) {
                timestamp=snapshots[i]; date=snapshot_day[timestamp]
                if (snapshot_count[timestamp] > day_database_count[date])
                    day_database_count[date]=snapshot_count[timestamp]
            }
            for (i=1; i<=snapshot_total; i++) {
                timestamp=snapshots[i]; date=snapshot_day[timestamp]
                if (snapshot_count[timestamp] == day_database_count[date] &&
                    (!(date in day_snapshot) || timestamp > day_snapshot[date]))
                    day_snapshot[date]=timestamp
            }
            for (key in snapshot_size) {
                split(key, fields, SUBSEP)
                timestamp=fields[1]; database=fields[2]; date=snapshot_day[timestamp]
                if (day_snapshot[date] == timestamp)
                    rows[++row_count]=timestamp OFS database OFS snapshot_size[key]
            }
            sort_text(rows, row_count)
            print "timestamp", "database", "size_bytes"
            for (i=1; i<=row_count; i++) print rows[i]
        }
        function trim(value) {
            sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
            return value
        }
        function valid_date(date, parts, year, month, day, limit) {
            if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
            split(date, parts, "-"); year=parts[1]+0; month=parts[2]+0; day=parts[3]+0
            if (year < 1 || month < 1 || month > 12) return 0
            limit=31
            if (month == 2) limit=leap(year) ? 29 : 28
            else if (month == 4 || month == 6 || month == 9 || month == 11) limit=30
            return day >= 1 && day <= limit
        }
        function leap(year) { return year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) }
        function sort_text(values, count, i, j, value) {
            for (i=2; i<=count; i++) {
                value=values[i]; j=i-1
                while (j >= 1 && values[j] > value) { values[j+1]=values[j]; j-- }
                values[j+1]=value
            }
        }
    ' "$file"
}

dbtune_provenance_analysis_fingerprint() {
    local run_id=${1:-}
    local audit_hash=${2:-}
    local samples_hash=${3:-}
    local dbsize_input=${4:-}
    local dbsize_hash=${5:-}
    local dbsize_selected_hash=${6:-}
    local analysis_hash=${7:-}

    printf 'run_id\t%s\naudit_hash\t%s\nsamples_hash\t%s\ndbsize_input\t%s\ndbsize_hash\t%s\ndbsize_selected_hash\t%s\nanalysis_hash\t%s\n' \
        "$run_id" "$audit_hash" "$samples_hash" "$dbsize_input" "$dbsize_hash" \
        "$dbsize_selected_hash" "$analysis_hash" | dbtune_sha256_stream
}

dbtune_provenance_write_analysis_manifest() {
    local output=${1:-}
    local analysis=${2:-}
    local samples=${3:-}
    local dbsize=${4:-}
    local audit_manifest run_id audit_hash samples_hash dbsize_hash dbsize_selected_hash selected
    local analysis_hash analysis_fingerprint row row_count=0

    audit_manifest=$(dbtune_audit_manifest_file) || return
    run_id=$(dbtune_manifest_value "$audit_manifest" run_id) || return 65
    audit_hash=$(dbtune_manifest_value "$audit_manifest" audit_hash) || return 65
    samples_hash=$(dbtune_sha256_file "$samples") || return
    dbsize_hash=$(dbtune_sha256_file "$dbsize") || return
    selected=$(dbtune_dbsize_selected_rows "$dbsize") || return
    dbsize_selected_hash=$(printf '%s\n' "$selected" | awk 'NR > 1' | dbtune_sha256_stream) || return
    analysis_hash=$(dbtune_sha256_file "$analysis") || return
    analysis_fingerprint=$(dbtune_provenance_analysis_fingerprint "$run_id" "$audit_hash" \
        "$samples_hash" "$dbsize" "$dbsize_hash" "$dbsize_selected_hash" "$analysis_hash") || return
    {
        printf 'schema\t2\n'
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'samples_hash\t%s\n' "$samples_hash"
        printf 'dbsize_input\t%s\n' "$dbsize"
        printf 'dbsize_hash\t%s\n' "$dbsize_hash"
        printf 'dbsize_selected_hash\t%s\n' "$dbsize_selected_hash"
        while IFS= read -r row; do
            row_count=$((row_count + 1))
            printf 'dbsize_selected_row.%06d\t%s\n' "$row_count" "$row"
        done < <(printf '%s\n' "$selected" | awk 'NR > 1')
        printf 'dbsize_selected_rows\t%s\n' "$row_count"
        printf 'analysis_hash\t%s\n' "$analysis_hash"
        printf 'analysis_fingerprint\t%s\n' "$analysis_fingerprint"
    } | dbtune_atomic_write "$output" 600
}

dbtune_provenance_validate_analysis() {
    local audit_manifest analysis_manifest samples dbsize analysis
    local key audit_value analysis_value actual dbsize_input selected selected_hash selected_count
    local analysis_fingerprint

    dbtune_provenance_validate_audit || return
    audit_manifest=$(dbtune_audit_manifest_file) || return
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    samples=$(dbtune_path samples.tsv) || return
    dbsize=$(dbtune_path dbsize.tsv) || return
    analysis=$(dbtune_path analysis.tsv) || return
    [[ -r $analysis_manifest && -r $samples && -r $dbsize && -r $analysis ]] || {
        dbtune_log error "$(dbtune_msg core_analysis_input_missing)"
        return 66
    }
    for key in run_id audit_hash; do
        audit_value=$(dbtune_manifest_value "$audit_manifest" "$key") || return 65
        analysis_value=$(dbtune_manifest_value "$analysis_manifest" "$key") || return 65
        if [[ $analysis_value != "$audit_value" ]]; then
            dbtune_log error "$(dbtune_printf core_analysis_other_run "$key")"
            return 65
        fi
    done
    dbsize_input=$(dbtune_manifest_value "$analysis_manifest" dbsize_input) || return 65
    [[ $dbsize_input == "$dbsize" ]] || {
        dbtune_log error "$(dbtune_msg core_analysis_other_dbsize)"
        return 65
    }
    for key in samples_hash dbsize_hash analysis_hash; do
        analysis_value=$(dbtune_manifest_value "$analysis_manifest" "$key") || return 65
        [[ $analysis_value =~ ^[0-9a-f]{64}$ ]] || return 65
        if [[ $key == samples_hash ]]; then
            actual=$(dbtune_sha256_file "$samples") || return
        elif [[ $key == dbsize_hash ]]; then
            actual=$(dbtune_sha256_file "$dbsize") || return
        else
            actual=$(dbtune_sha256_file "$analysis") || return
        fi
        if [[ $actual != "$analysis_value" ]]; then
            dbtune_log error "$(dbtune_printf core_analysis_stale_input "$key")"
            return 65
        fi
    done
    selected=$(dbtune_dbsize_selected_rows "$dbsize") || return
    selected_hash=$(printf '%s\n' "$selected" | awk 'NR > 1' | dbtune_sha256_stream) || return
    analysis_value=$(dbtune_manifest_value "$analysis_manifest" dbsize_selected_hash) || return 65
    [[ $analysis_value =~ ^[0-9a-f]{64}$ && $selected_hash == "$analysis_value" ]] || return 65
    actual=$(awk -F '\t' '$1 ~ /^dbsize_selected_row\.[0-9][0-9][0-9][0-9][0-9][0-9]$/ {sub(/^[^\t]*\t/, ""); print}' \
        "$analysis_manifest" | dbtune_sha256_stream) || return
    [[ $actual == "$selected_hash" ]] || {
        dbtune_log error "$(dbtune_msg core_analysis_dbsize_rows_mismatch)"
        return 65
    }
    selected_count=$(dbtune_manifest_value "$analysis_manifest" dbsize_selected_rows) || return 65
    [[ $selected_count =~ ^[0-9]+$ ]] || return 65
    actual=$(awk -F '\t' '$1 ~ /^dbsize_selected_row\.[0-9][0-9][0-9][0-9][0-9][0-9]$/ {count++} END {print count+0}' "$analysis_manifest")
    [[ $actual == "$selected_count" ]] || return 65
    analysis_fingerprint=$(dbtune_provenance_analysis_fingerprint \
        "$(dbtune_manifest_value "$analysis_manifest" run_id)" \
        "$(dbtune_manifest_value "$analysis_manifest" audit_hash)" \
        "$(dbtune_manifest_value "$analysis_manifest" samples_hash)" \
        "$dbsize_input" \
        "$(dbtune_manifest_value "$analysis_manifest" dbsize_hash)" \
        "$selected_hash" \
        "$(dbtune_manifest_value "$analysis_manifest" analysis_hash)") || return
    analysis_value=$(dbtune_manifest_value "$analysis_manifest" analysis_fingerprint) || return 65
    [[ $analysis_value =~ ^[0-9a-f]{64}$ && $analysis_value == "$analysis_fingerprint" ]] || {
        dbtune_log error "$(dbtune_msg core_analysis_fingerprint_mismatch)"
        return 65
    }
}

dbtune_cycle_archive() {
    local run_id=${1:-legacy}
    local root archive name found=0 suffix=0
    local -a artifacts=(
        audit.tsv apps.tsv databases.tsv audit-manifest.tsv
        collect.tsv samples.tsv dbsize.tsv dbsize-date collect-health.tsv collect-last-uptime
        analysis.tsv analysis-manifest.tsv report.md report.json
        proposed-99-zz-tuning.cnf proposal-manifest.tsv
    )

    [[ $run_id =~ ^[A-Za-z0-9._-]+$ ]] || run_id=legacy
    root="$DBTUNE_STATE_DIR/runs"
    archive="$root/$run_id"
    for name in "${artifacts[@]}"; do
        [[ -e $DBTUNE_STATE_DIR/$name ]] && found=1
    done
    ((found)) || return 0
    install -d -m 700 "$root" || return 1
    while [[ -e $archive ]]; do
        suffix=$((suffix + 1))
        archive="$root/$run_id-$suffix"
    done
    install -d -m 700 "$archive" || return 1
    for name in "${artifacts[@]}"; do
        [[ ! -e $DBTUNE_STATE_DIR/$name ]] || cp -p "$DBTUNE_STATE_DIR/$name" "$archive/$name" || return 1
    done
    printf '%s\n' "$archive"
}

dbtune_cycle_invalidate_downstream() {
    rm -f \
        "$DBTUNE_STATE_DIR/collect.tsv" \
        "$DBTUNE_STATE_DIR/samples.tsv" \
        "$DBTUNE_STATE_DIR/dbsize.tsv" \
        "$DBTUNE_STATE_DIR/dbsize-date" \
        "$DBTUNE_STATE_DIR/collect-health.tsv" \
        "$DBTUNE_STATE_DIR/collect-last-uptime" \
        "$DBTUNE_STATE_DIR/analysis.tsv" \
        "$DBTUNE_STATE_DIR/analysis-manifest.tsv" \
        "$DBTUNE_STATE_DIR/report.md" \
        "$DBTUNE_STATE_DIR/report.json" \
        "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" \
        "$DBTUNE_STATE_DIR/proposal-manifest.tsv"
}

dbtune_lifecycle_lock_file() {
    printf '%s/.lifecycle.lock\n' "$DBTUNE_STATE_DIR"
}

dbtune_validate_state_lock_path() {
    local lock_file=${1:-}
    local label=${2:-$(dbtune_msg core_label_state_lock)}
    local directory base

    directory=${lock_file%/*}
    base=${lock_file##*/}
    if [[ $directory != "$DBTUNE_STATE_DIR" || ! $base =~ ^[A-Za-z0-9.][A-Za-z0-9._-]*[.]lock$ ]]; then
        dbtune_log error "$(dbtune_printf core_lock_path_invalid "$label" "$lock_file")"
        return 65
    fi
}

dbtune_validate_state_lock() {
    local lock_file=${1:-}
    local label=${2:-$(dbtune_msg core_label_state_lock)}
    local expected_identity=${3:-}
    local expected_links=${4:-1}
    local uid gid mode links identity expected_uid

    [[ $expected_links =~ ^[12]$ ]] || return 64
    dbtune_validate_state_lock_path "$lock_file" "$label" || return
    expected_uid=$(dbtune_state_expected_uid) || return 1
    if [[ -L $lock_file || ! -f $lock_file ]]; then
        dbtune_log error "$(dbtune_printf core_unsafe_regular_file "$label" "$lock_file")"
        return 65
    fi
    read -r uid gid mode < <(dbtune_file_stat "$lock_file") || return 1
    links=$(dbtune_file_links "$lock_file") || return 1
    identity=$(dbtune_file_identity "$lock_file") || return 1
    if [[ $uid != "$expected_uid" || $mode != 600 || $links != "$expected_links" ]]; then
        dbtune_log error "$(dbtune_printf core_lock_metadata_invalid "$label" "$lock_file" "$uid" "$gid" "$mode" "$links" "$expected_links")"
        return 65
    fi
    if [[ -n $expected_identity && $identity != "$expected_identity" ]]; then
        dbtune_log error "$(dbtune_printf core_lock_replaced "$label" "$lock_file")"
        return 65
    fi
    DBTUNE_STATE_LOCK_IDENTITY=$identity
}

dbtune_open_state_lock() {
    local output_variable=${1:-}
    local lock_file=${2:-}
    local label=${3:-$(dbtune_msg core_label_state_lock)}
    local temporary identity inode fd_inode opened_fd status

    [[ $output_variable =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 64
    dbtune_validate_state_lock_path "$lock_file" "$label" || return
    temporary=$(mktemp "$DBTUNE_STATE_DIR/.state.lock.open.XXXXXX") || return 1
    chmod 600 "$temporary" || {
        rm -f "$temporary"
        return 1
    }
    identity=$(dbtune_file_identity "$temporary") || {
        rm -f "$temporary"
        return 1
    }
    if ! command ln -P "$temporary" "$lock_file" 2>/dev/null; then
        rm -f "$temporary"
        dbtune_validate_state_lock "$lock_file" "$label" || return
        identity=$DBTUNE_STATE_LOCK_IDENTITY
        temporary=$(mktemp "$DBTUNE_STATE_DIR/.state.lock.open.XXXXXX") || return 1
        rm -f "$temporary"
        if ! command ln -P "$lock_file" "$temporary" 2>/dev/null || [[ -L $temporary || ! -f $temporary ]] ||
            [[ $(dbtune_file_identity "$temporary") != "$identity" ]]; then
            rm -f "$temporary"
            dbtune_log error "$(dbtune_printf core_lock_open_failed "$label" "$lock_file")"
            return 65
        fi
    fi
    dbtune_validate_state_lock "$lock_file" "$label" "$identity" 2 || {
        status=$?
        rm -f "$temporary"
        return "$status"
    }
    inode=${identity##*:}
    if ! exec {opened_fd}>>"$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if [[ -e /proc/$BASHPID/fd/$opened_fd ]]; then
        fd_inode=$(dbtune_file_inode "/proc/$BASHPID/fd/$opened_fd") || fd_inode=
    else
        fd_inode=$(dbtune_file_inode "/dev/fd/$opened_fd") || fd_inode=
    fi
    rm -f "$temporary"
    if [[ $fd_inode != "$inode" ]] || ! dbtune_validate_state_lock "$lock_file" "$label" "$identity"; then
        exec {opened_fd}>&-
        dbtune_log error "$(dbtune_printf core_open_lock_identity_invalid "$label")"
        return 65
    fi
    printf -v "$output_variable" '%s' "$opened_fd"
}

dbtune_with_lifecycle_lock() {
    local mode=${1:-wait}
    local operation=${2:-operation}
    local function_name=${3:-}
    local lock_file lock_identity lock_fd status=0 flock_command=${DBTUNE_FLOCK:-flock}
    shift 3 || true

    dbtune_init_state_dir || return
    if [[ $DBTUNE_ARTIFACT_PROFILE == production ]]; then
        flock_command=$(dbtune_runtime_command_path flock) || {
            [[ $mode == skip ]] && return 75
            return 69
        }
    fi
    if [[ $operation == _tick ]] && declare -F dbtune_collect_restore_language >/dev/null 2>&1; then
        dbtune_collect_restore_language || return
    fi
    if ! command -v "$flock_command" >/dev/null 2>&1; then
        dbtune_log error "$(dbtune_msg core_lifecycle_flock_required)"
        [[ $mode == skip ]] && return 75
        return 69
    fi
    lock_file=$(dbtune_lifecycle_lock_file) || return
    dbtune_open_state_lock lock_fd "$lock_file" "$(dbtune_msg core_label_lifecycle_lock)" || return
    lock_identity=$DBTUNE_STATE_LOCK_IDENTITY
    if [[ $mode == skip ]]; then
        if ! "$flock_command" -n "$lock_fd"; then
            exec {lock_fd}>&-
            return 75
        fi
    elif ! "$flock_command" -x "$lock_fd"; then
        exec {lock_fd}>&-
        dbtune_log error "$(dbtune_printf core_lifecycle_lock_failed "$operation")"
        return 1
    fi
    if ! dbtune_validate_state_lock "$lock_file" "$(dbtune_msg core_label_lifecycle_lock)" "$lock_identity"; then
        "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
        exec {lock_fd}>&-
        return 65
    fi
    if declare -F dbtune_lifecycle_recover_if_needed >/dev/null 2>&1; then
        dbtune_lifecycle_recover_if_needed || status=$?
    fi
    if ((status == 0)); then
        "$function_name" "$@" || status=$?
    fi
    "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    return "$status"
}

dbtune_event() {
    local event_type=${1:-}
    local line lock_file lock_identity lock_fd flock_command=${DBTUNE_EVENT_FLOCK:-flock}
    local locked=0 status=0
    local -a fields

    if [[ $DBTUNE_ARTIFACT_PROFILE == production ]]; then
        flock_command=$(dbtune_runtime_command_path flock) || return 69
    fi

    [[ -n $event_type ]] || {
        dbtune_log error "$(dbtune_msg core_event_type_required)"
        return 64
    }
    shift
    if (($# % 2 != 0)); then
        dbtune_log error "$(dbtune_msg core_event_pairs_required)"
        return 64
    fi
    dbtune_init_state_dir || return 1
    fields=(timestamp "$(dbtune_now)" event "$(dbtune_redact "$event_type")")
    while (($#)); do
        fields+=("$1" "$(dbtune_redact "$2")")
        shift 2
    done
    line=$(dbtune_json_emit "${fields[@]}") || return
    lock_file="$DBTUNE_STATE_DIR/.events.lock"
    dbtune_open_state_lock lock_fd "$lock_file" "$(dbtune_msg core_label_event_lock)" || return
    lock_identity=$DBTUNE_STATE_LOCK_IDENTITY
    if command -v "$flock_command" >/dev/null 2>&1; then
        if ! "$flock_command" -x "$lock_fd"; then
            exec {lock_fd}>&-
            return 1
        fi
        locked=1
    fi
    dbtune_validate_state_lock "$lock_file" "$(dbtune_msg core_label_event_lock)" "$lock_identity" || status=$?
    ((status != 0)) || printf '%s\n' "$line" >>"$(dbtune_events_file)" || status=$?
    ((locked == 0)) || "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    ((status == 0)) || return "$status"
    chmod 600 "$(dbtune_events_file)" 2>/dev/null || true
}

dbtune_state_is_valid() {
    case ${1:-} in
        idle|audited|collecting|collected|analyzed|proposed|applied|verified|rolled_back|recovery_required|rollback_failed) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_state_read() {
    local file state

    file=$(dbtune_state_file)
    if [[ ! -e $file && ! -L $file ]]; then
        printf 'idle\n'
        return 0
    fi
    dbtune_validate_single_link_file "$file" "$(dbtune_msg core_label_state_file)" || return
    IFS= read -r state <"$file" || true
    if ! dbtune_state_is_valid "$state"; then
        dbtune_log error "$(dbtune_printf core_state_file_invalid "${state:-$(dbtune_msg core_value_empty)}")"
        return 65
    fi
    printf '%s\n' "$state"
}

dbtune_state_write() {
    local state=${1:-}
    local file

    if ! dbtune_state_is_valid "$state"; then
        dbtune_log error "$(dbtune_printf core_state_write_invalid "${state:-$(dbtune_msg core_value_empty)}")"
        return 64
    fi
    dbtune_init_state_dir || return 1
    file=$(dbtune_state_file)
    if [[ -e $file || -L $file ]]; then
        dbtune_validate_single_link_file "$file" "$(dbtune_msg core_label_state_file)" || return
    fi
    printf '%s\n' "$state" | dbtune_atomic_write "$file" 600 || return
    dbtune_validate_single_link_file "$file" "$(dbtune_msg core_label_published_state_file)"
}

dbtune_state_can_transition() {
    local from=${1:-}
    local to=${2:-}

    [[ $from == "$to" ]] && return 0
    case "$from:$to" in
        idle:audited|audited:collecting|collecting:collected|collected:analyzed|analyzed:proposed|proposed:applied|analyzed:applied|applied:verified|applied:rolled_back|verified:rolled_back|recovery_required:rolled_back|rollback_failed:rolled_back|recovery_required:rollback_failed) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_state_transition() {
    local target=${1:-}
    local current

    current=$(dbtune_state_read) || return
    if ! dbtune_state_can_transition "$current" "$target"; then
        dbtune_log error "$(dbtune_printf core_state_transition_invalid "$current" "${target:-$(dbtune_msg core_value_empty)}")"
        return 65
    fi
    dbtune_state_write "$target" || return
    dbtune_event state_transition from "$current" to "$target" || true
}

dbtune_state_record_audit() {
    local run_id=${1:-unknown}
    local archive=${2:-}
    local current

    current=$(dbtune_state_read) || return
    dbtune_state_write audited || return
    dbtune_event audit_cycle_started previous_state "$current" run_id "$run_id" archive "${archive:-none}" || true
}

dbtune_state_guard() {
    local operation=${1:-}
    local state=${2:-}

    [[ -n $state ]] || state=$(dbtune_state_read) || return
    case $operation in
        audit) [[ $state != collecting && $state != recovery_required && $state != rollback_failed ]] ;;
        status|version|help|collect_status) return 0 ;;
        collect_start) [[ $state == audited ]] ;;
        collect_stop|_tick) [[ $state == collecting ]] ;;
        analyze) [[ $state == collected ]] ;;
        report) [[ $state == analyzed || $state == proposed || $state == applied || $state == verified || $state == rolled_back ]] ;;
        propose) [[ $state == analyzed || $state == proposed ]] ;;
        apply) [[ $state == proposed ]] ;;
        verify) [[ $state == applied || $state == verified ]] ;;
        rollback)
            [[ $state == applied || $state == verified || $state == recovery_required || $state == rollback_failed ]] ||
                { [[ $state != collecting && $state != rolled_back ]] && [[ -r $DBTUNE_STATE_DIR/apply/current ]]; }
            ;;
        *) return 64 ;;
    esac
}

dbtune_require_state() {
    local operation=${1:-}
    local state

    state=$(dbtune_state_read) || return
    if ! dbtune_state_guard "$operation" "$state"; then
        dbtune_log error "$(dbtune_printf core_command_state_disallowed "$operation" "$state")"
        return 65
    fi
}

dbtune_sql_client() {
    if command -v mariadb >/dev/null 2>&1; then
        command -v mariadb
    elif command -v mysql >/dev/null 2>&1; then
        command -v mysql
    else
        dbtune_log error "$(dbtune_msg core_sql_client_missing)"
        return 69
    fi
}

dbtune_sql_load_auth() {
    local file method defaults_file

    [[ -z $DBTUNE_SQL_AUTH_METHOD ]] || return 0
    file=$(dbtune_auth_method_file)
    [[ -r $file ]] || return 1
    IFS=$'\t' read -r method defaults_file <"$file" || return 1
    case $method in
        socket)
            DBTUNE_SQL_AUTH_METHOD=socket
            DBTUNE_SQL_DEFAULTS_FILE=''
            ;;
        defaults)
            [[ -r $defaults_file ]] || return 1
            DBTUNE_SQL_AUTH_METHOD=defaults
            DBTUNE_SQL_DEFAULTS_FILE=$defaults_file
            ;;
        *) return 1 ;;
    esac
}

dbtune_sql_save_auth() {
    dbtune_init_state_dir || return 1
    printf '%s\t%s\n' "$DBTUNE_SQL_AUTH_METHOD" "$DBTUNE_SQL_DEFAULTS_FILE" |
        dbtune_atomic_write "$(dbtune_auth_method_file)" 600
}

dbtune_sql_probe() {
    local client connect_timeout=${DBTUNE_SQL_CONNECT_TIMEOUT:-5}
    local statement_timeout=${DBTUNE_SQL_STATEMENT_TIMEOUT:-5}

    [[ $connect_timeout =~ ^[1-9][0-9]*$ && $statement_timeout =~ ^[1-9][0-9]*([.][0-9]+)?$ ]] || return 64
    command awk -v connect="$connect_timeout" -v statement="$statement_timeout" \
        'BEGIN { exit !(connect <= 30 && statement <= 60) }' || return 64
    client=$(dbtune_sql_client) || return
    if "$client" --connect-timeout="$connect_timeout" --protocol=socket --user=root --batch --skip-column-names \
        --execute="SET SESSION max_statement_time=$statement_timeout; SELECT 1" >/dev/null 2>&1; then
        DBTUNE_SQL_AUTH_METHOD=socket
        DBTUNE_SQL_DEFAULTS_FILE=''
        dbtune_sql_save_auth || return
        dbtune_event sql_auth method socket || true
        return 0
    fi
    if [[ -r $DBTUNE_ROOT_CNF ]] && "$client" --defaults-extra-file="$DBTUNE_ROOT_CNF" \
        --connect-timeout="$connect_timeout" --protocol=socket --batch --skip-column-names \
        --execute="SET SESSION max_statement_time=$statement_timeout; SELECT 1" >/dev/null 2>&1; then
        DBTUNE_SQL_AUTH_METHOD=defaults
        DBTUNE_SQL_DEFAULTS_FILE=$DBTUNE_ROOT_CNF
        dbtune_sql_save_auth || return
        dbtune_event sql_auth method defaults file "$DBTUNE_ROOT_CNF" || true
        return 0
    fi
    dbtune_log error "$(dbtune_msg core_sql_auth_failed)"
    return 77
}

dbtune_sql_ensure_auth() {
    dbtune_sql_load_auth && return 0
    dbtune_sql_probe
}

dbtune_sql() {
    local query=${1:-}
    local database=${2:-}
    local client normalized
    local connect_timeout=${DBTUNE_SQL_CONNECT_TIMEOUT:-5}
    local statement_timeout=${DBTUNE_SQL_STATEMENT_TIMEOUT:-5}
    local -a options=()

    [[ -n $query ]] || {
        dbtune_log error "$(dbtune_msg core_sql_query_required)"
        return 64
    }
    if [[ ! $connect_timeout =~ ^[1-9][0-9]*$ || ! $statement_timeout =~ ^[1-9][0-9]*([.][0-9]+)?$ ]]; then
        dbtune_log error "$(dbtune_msg core_sql_timeout_positive)"
        return 64
    fi
    if ! command awk -v connect="$connect_timeout" -v statement="$statement_timeout" \
        'BEGIN { exit !(connect <= 30 && statement <= 60) }'; then
        dbtune_log error "$(dbtune_msg core_sql_timeout_max)"
        return 64
    fi
    dbtune_sql_ensure_auth || return
    client=$(dbtune_sql_client) || return
    normalized=${query^^}
    if [[ $normalized =~ ^[[:space:]]*(SELECT|SHOW|EXPLAIN|WITH)([[:space:]\(]|$) ]]; then
        query="SET SESSION max_statement_time=$statement_timeout;
$query"
    fi
    case $DBTUNE_SQL_AUTH_METHOD in
        socket)
            options=(--connect-timeout="$connect_timeout" --protocol=socket --user=root --batch --skip-column-names)
            ;;
        defaults)
            options=(--defaults-extra-file="$DBTUNE_SQL_DEFAULTS_FILE" --connect-timeout="$connect_timeout" --protocol=socket --batch --skip-column-names)
            ;;
        *)
            dbtune_log error "$(dbtune_msg core_sql_auth_unknown)"
            return 70
            ;;
    esac
    [[ -z $database ]] || options+=("$database")
    printf '%s\n' "$query" | "$client" "${options[@]}"
}
