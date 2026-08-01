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
        dbtune_log error "Neplatny nazov state suboru: ${1:-<prazdny>}"
        return 64
    fi
    printf '%s/%s\n' "$DBTUNE_STATE_DIR" "$1"
}

dbtune_init_state_dir() {
    if [[ -d $DBTUNE_STATE_DIR ]]; then
        chmod 700 "$DBTUNE_STATE_DIR" 2>/dev/null || return 1
    else
        install -d -m 700 "$DBTUNE_STATE_DIR" || return 1
    fi
}

dbtune_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

dbtune_redact() {
    printf '%s' "${1:-}" | sed -E \
        -e 's/(((db[_-]?)?password|passwd|pwd)[[:space:]]*[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
        -e 's/(--password([=[:space:]]+))[^[:space:]]+/\1[REDACTED]/g' \
        -e 's/(^|[[:space:]])-p[^[:space:]]+/\1-p[REDACTED]/g'
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
        dbtune_log error "Atomicky zapis vyzaduje cielovu cestu"
        return 64
    }
    [[ $mode =~ ^0?[0-7]{3}$ ]] || {
        dbtune_log error "Neplatny mode pre atomicky zapis: $mode"
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
        dbtune_log error "$name musi byt cele nezaporne cislo"
        return 64
    fi
    if ! dbtune_is_uint "$minimum" || ! dbtune_is_uint "$maximum" || ((minimum > maximum)); then
        dbtune_log error "Interny rozsah pre $name je neplatny"
        return 70
    fi
    if ((value < minimum || value > maximum)); then
        dbtune_log error "$name musi byt v rozsahu $minimum az $maximum"
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
        dbtune_log error "JSON emitter ocakava dvojice kluc hodnota"
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

dbtune_sha256_file() {
    local file=${1:-}

    [[ -r $file ]] || return 66
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        dbtune_log error "Chyba sha256sum aj shasum"
        return 69
    fi
}

dbtune_event() {
    local event_type=${1:-}
    local line lock_file
    local -a fields

    [[ -n $event_type ]] || {
        dbtune_log error "Event vyzaduje typ"
        return 64
    }
    shift
    if (($# % 2 != 0)); then
        dbtune_log error "Event ocakava dvojice kluc hodnota"
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
    if command -v flock >/dev/null 2>&1; then
        (
            flock -x 9 || exit 1
            printf '%s\n' "$line" >>"$(dbtune_events_file)"
        ) 9>"$lock_file"
    else
        printf '%s\n' "$line" >>"$(dbtune_events_file)"
    fi
    chmod 600 "$(dbtune_events_file)" 2>/dev/null || true
}

dbtune_state_is_valid() {
    case ${1:-} in
        idle|audited|collecting|collected|analyzed|proposed|applied|verified|rolled_back) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_state_read() {
    local file state

    file=$(dbtune_state_file)
    if [[ ! -e $file ]]; then
        printf 'idle\n'
        return 0
    fi
    IFS= read -r state <"$file" || true
    if ! dbtune_state_is_valid "$state"; then
        dbtune_log error "State subor obsahuje neplatny stav: ${state:-<prazdny>}"
        return 65
    fi
    printf '%s\n' "$state"
}

dbtune_state_write() {
    local state=${1:-}

    if ! dbtune_state_is_valid "$state"; then
        dbtune_log error "Nie je mozne zapisat neplatny stav: ${state:-<prazdny>}"
        return 64
    fi
    dbtune_init_state_dir || return 1
    printf '%s\n' "$state" | dbtune_atomic_write "$(dbtune_state_file)" 600
}

dbtune_state_can_transition() {
    local from=${1:-}
    local to=${2:-}

    [[ $from == "$to" ]] && return 0
    case "$from:$to" in
        idle:audited|audited:collecting|collecting:collected|collected:analyzed|analyzed:proposed|proposed:applied|analyzed:applied|applied:verified|applied:rolled_back|verified:rolled_back) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_state_transition() {
    local target=${1:-}
    local current

    current=$(dbtune_state_read) || return
    if ! dbtune_state_can_transition "$current" "$target"; then
        dbtune_log error "Neplatny prechod stavu: $current -> ${target:-<prazdny>}"
        return 65
    fi
    dbtune_state_write "$target" || return
    dbtune_event state_transition from "$current" to "$target"
}

dbtune_state_record_audit() {
    local current

    current=$(dbtune_state_read) || return
    if [[ $current == idle ]]; then
        dbtune_state_transition audited
    else
        dbtune_event audit_completed state "$current"
    fi
}

dbtune_state_guard() {
    local operation=${1:-}
    local state=${2:-}

    [[ -n $state ]] || state=$(dbtune_state_read) || return
    case $operation in
        audit|status|version|help|collect_status) return 0 ;;
        collect_start) [[ $state == audited ]] ;;
        collect_stop|_tick) [[ $state == collecting ]] ;;
        analyze) [[ $state == collected ]] ;;
        report) [[ $state == analyzed || $state == proposed || $state == applied || $state == verified || $state == rolled_back ]] ;;
        propose) [[ $state == analyzed || $state == proposed ]] ;;
        apply) [[ $state == proposed ]] ;;
        verify) [[ $state == applied || $state == verified ]] ;;
        rollback) [[ $state == applied || $state == verified ]] ;;
        *) return 64 ;;
    esac
}

dbtune_require_state() {
    local operation=${1:-}
    local state

    state=$(dbtune_state_read) || return
    if ! dbtune_state_guard "$operation" "$state"; then
        dbtune_log error "Prikaz '$operation' nie je povoleny v stave '$state'"
        return 65
    fi
}

dbtune_sql_client() {
    if command -v mariadb >/dev/null 2>&1; then
        command -v mariadb
    elif command -v mysql >/dev/null 2>&1; then
        command -v mysql
    else
        dbtune_log error "Nenasiel sa klient mariadb ani mysql"
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
        dbtune_event sql_auth method socket
        return 0
    fi
    if [[ -r $DBTUNE_ROOT_CNF ]] && "$client" --defaults-extra-file="$DBTUNE_ROOT_CNF" \
        --connect-timeout="$connect_timeout" --protocol=socket --batch --skip-column-names \
        --execute="SET SESSION max_statement_time=$statement_timeout; SELECT 1" >/dev/null 2>&1; then
        DBTUNE_SQL_AUTH_METHOD=defaults
        DBTUNE_SQL_DEFAULTS_FILE=$DBTUNE_ROOT_CNF
        dbtune_sql_save_auth || return
        dbtune_event sql_auth method defaults file "$DBTUNE_ROOT_CNF"
        return 0
    fi
    dbtune_log error "MariaDB root auth zlyhal cez unix_socket aj defaults-extra-file"
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
        dbtune_log error "SQL wrapper vyzaduje query"
        return 64
    }
    if [[ ! $connect_timeout =~ ^[1-9][0-9]*$ || ! $statement_timeout =~ ^[1-9][0-9]*([.][0-9]+)?$ ]]; then
        dbtune_log error "SQL timeout musi byt kladne cislo"
        return 64
    fi
    if ! command awk -v connect="$connect_timeout" -v statement="$statement_timeout" \
        'BEGIN { exit !(connect <= 30 && statement <= 60) }'; then
        dbtune_log error "SQL connect timeout moze byt najviac 30s a statement timeout 60s"
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
            dbtune_log error "Neznamy SQL auth kontrakt"
            return 70
            ;;
    esac
    [[ -z $database ]] || options+=("$database")
    printf '%s\n' "$query" | "$client" "${options[@]}"
}
