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

dbtune_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        dbtune_log error "Chyba sha256sum aj shasum"
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

dbtune_backup_evidence_validate() {
    local file=${1:-}
    local uid gid mode expected_uid

    [[ -f $file && ! -L $file ]] || return 66
    read -r uid gid mode < <(dbtune_file_stat "$file") || return 1
    expected_uid=${DBTUNE_BACKUP_EVIDENCE_UID:-0}
    [[ $expected_uid =~ ^[0-9]+$ ]] || return 64
    [[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ && $uid == "$expected_uid" && ($mode == 400 || $mode == 600) ]] || return 65
    awk -F '\t' '
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
    ' "$file"
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
        dbtune_log error "Chyba audit provenance manifest: $manifest"
        return 66
    }
    run_id=$(dbtune_manifest_value "$manifest" run_id) || return 65
    [[ $run_id =~ ^[A-Za-z0-9._-]+$ ]] || return 65
    for expected in audit.tsv apps.tsv databases.tsv; do
        actual=$(dbtune_manifest_value "$manifest" "$expected") || return 65
        [[ $actual =~ ^[0-9a-f]{64}$ && -r $DBTUNE_STATE_DIR/$expected ]] || return 65
        if [[ $(dbtune_sha256_file "$DBTUNE_STATE_DIR/$expected") != "$actual" ]]; then
            dbtune_log error "Audit artefakt $expected nezodpoveda runu $run_id"
            return 65
        fi
    done
    audit_file_hash=$(dbtune_manifest_value "$manifest" audit.tsv) || return 65
    apps_hash=$(dbtune_manifest_value "$manifest" apps.tsv) || return 65
    databases_hash=$(dbtune_manifest_value "$manifest" databases.tsv) || return 65
    audit_hash=$(dbtune_provenance_audit_hash "$audit_file_hash" "$apps_hash" "$databases_hash") || return
    expected=$(dbtune_manifest_value "$manifest" audit_hash) || return 65
    if [[ $expected != "$audit_hash" ]]; then
        dbtune_log error "Audit hash nezodpoveda artefaktom runu $run_id"
        return 65
    fi
}

dbtune_provenance_write_analysis_manifest() {
    local output=${1:-}
    local analysis=${2:-}
    local samples=${3:-}
    local audit_manifest run_id audit_hash samples_hash analysis_hash

    audit_manifest=$(dbtune_audit_manifest_file) || return
    run_id=$(dbtune_manifest_value "$audit_manifest" run_id) || return 65
    audit_hash=$(dbtune_manifest_value "$audit_manifest" audit_hash) || return 65
    samples_hash=$(dbtune_sha256_file "$samples") || return
    analysis_hash=$(dbtune_sha256_file "$analysis") || return
    {
        printf 'schema\t1\n'
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'samples_hash\t%s\n' "$samples_hash"
        printf 'analysis_hash\t%s\n' "$analysis_hash"
    } | dbtune_atomic_write "$output" 600
}

dbtune_provenance_validate_analysis() {
    local audit_manifest analysis_manifest samples analysis
    local key audit_value analysis_value actual

    dbtune_provenance_validate_audit || return
    audit_manifest=$(dbtune_audit_manifest_file) || return
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    samples=$(dbtune_path samples.tsv) || return
    analysis=$(dbtune_path analysis.tsv) || return
    [[ -r $analysis_manifest && -r $samples && -r $analysis ]] || {
        dbtune_log error "Chyba analysis provenance alebo jeho vstup"
        return 66
    }
    for key in run_id audit_hash; do
        audit_value=$(dbtune_manifest_value "$audit_manifest" "$key") || return 65
        analysis_value=$(dbtune_manifest_value "$analysis_manifest" "$key") || return 65
        if [[ $analysis_value != "$audit_value" ]]; then
            dbtune_log error "Analysis patri inemu audit runu ($key)"
            return 65
        fi
    done
    for key in samples_hash analysis_hash; do
        analysis_value=$(dbtune_manifest_value "$analysis_manifest" "$key") || return 65
        [[ $analysis_value =~ ^[0-9a-f]{64}$ ]] || return 65
        if [[ $key == samples_hash ]]; then
            actual=$(dbtune_sha256_file "$samples") || return
        else
            actual=$(dbtune_sha256_file "$analysis") || return
        fi
        if [[ $actual != "$analysis_value" ]]; then
            dbtune_log error "Stale alebo zmeneny analysis vstup: $key"
            return 65
        fi
    done
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

dbtune_with_lifecycle_lock() {
    local mode=${1:-wait}
    local operation=${2:-operation}
    local function_name=${3:-}
    local lock_fd status=0 flock_command=${DBTUNE_FLOCK:-flock}
    shift 3 || true

    dbtune_init_state_dir || return 1
    if ! command -v "$flock_command" >/dev/null 2>&1; then
        dbtune_log error "Lifecycle lock vyzaduje flock"
        [[ $mode == skip ]] && return 75
        return 69
    fi
    exec {lock_fd}>"$(dbtune_lifecycle_lock_file)" || return 1
    if [[ $mode == skip ]]; then
        if ! "$flock_command" -n "$lock_fd"; then
            exec {lock_fd}>&-
            return 75
        fi
    elif ! "$flock_command" -x "$lock_fd"; then
        exec {lock_fd}>&-
        dbtune_log error "Nepodarilo sa ziskat lifecycle lock pre $operation"
        return 1
    fi
    "$function_name" "$@" || status=$?
    "$flock_command" -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    return "$status"
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
        idle|audited|collecting|collected|analyzed|proposed|applied|verified|rolled_back|recovery_required|rollback_failed) return 0 ;;
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
        idle:audited|audited:collecting|collecting:collected|collected:analyzed|analyzed:proposed|proposed:applied|analyzed:applied|applied:verified|applied:rolled_back|verified:rolled_back|recovery_required:rolled_back|rollback_failed:rolled_back|recovery_required:rollback_failed) return 0 ;;
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
