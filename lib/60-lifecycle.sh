dbtune_lifecycle_target() {
    printf '%s\n' "${DBTUNE_CONFIG_TARGET:-/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf}"
}

dbtune_lifecycle_allowed_directory() {
    printf '%s\n' "${DBTUNE_CONFIG_ALLOWED_DIR:-/etc/mysql/mariadb.conf.d}"
}

dbtune_lifecycle_path_is_canonical_absolute() {
    local path=${1:-}

    [[ $path == /* && $path != / && $path != */ && $path != *//* && $path != *$'\n'* ]] || return 1
    [[ $path != */./* && $path != */. && $path != */../* && $path != */.. ]]
}

dbtune_lifecycle_file_identity() {
    local path=${1:-}

    [[ -n $path ]] || return 64
    if stat -c '%d:%i' "$path" >/dev/null 2>&1; then
        stat -c '%d:%i' "$path"
    else
        stat -f '%d:%i' "$path"
    fi
}

dbtune_lifecycle_file_links() {
    local path=${1:-}

    [[ -n $path ]] || return 64
    if stat -c '%h' "$path" >/dev/null 2>&1; then
        stat -c '%h' "$path"
    else
        stat -f '%l' "$path"
    fi
}

dbtune_lifecycle_validate_parent_components() {
    local directory=${1:-}
    local component current=''
    local -a components

    dbtune_lifecycle_path_is_canonical_absolute "$directory" || return 1
    IFS=/ read -r -a components <<<"$directory"
    for component in "${components[@]}"; do
        [[ -n $component ]] || continue
        current+="/$component"
        if [[ -L $current || ! -d $current ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_config_parent_unsafe "$current")"
            return 65
        fi
    done
}

dbtune_lifecycle_parent_identity_chain() {
    local directory=${1:-}
    local component current='' separator=''
    local -a components

    dbtune_lifecycle_path_is_canonical_absolute "$directory" || return 65
    IFS=/ read -r -a components <<<"$directory"
    for component in "${components[@]}"; do
        [[ -n $component ]] || continue
        current+="/$component"
        printf '%s%s' "$separator" "$(dbtune_lifecycle_file_identity "$current")" || return
        separator=,
    done
    printf '\n'
}

dbtune_lifecycle_validate_target_path() {
    local target=${1:-}
    local expected_topology=${2:-any}
    local expected_directory_identity=${3:-}
    local expected_target_identity=${4:-}
    local expected_target_hash=${5:-}
    local allowed directory base uid gid mode links expected_uid expected_gid expected_mode

    allowed=$(dbtune_lifecycle_allowed_directory)
    if ! dbtune_lifecycle_path_is_canonical_absolute "$target" ||
        ! dbtune_lifecycle_path_is_canonical_absolute "$allowed"; then
        dbtune_log error "$(dbtune_msg lifecycle_target_paths_absolute)"
        return 65
    fi
    directory=${target%/*}
    base=${target##*/}
    if [[ $directory != "$allowed" || ! $base =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]cnf$ ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_target_allowed "$allowed")"
        return 65
    fi
    dbtune_lifecycle_validate_parent_components "$allowed" || return
    DBTUNE_LIFECYCLE_PARENT_IDENTITIES=$(dbtune_lifecycle_parent_identity_chain "$allowed") || return

    expected_uid=${DBTUNE_CONFIG_UID:-0}
    expected_gid=${DBTUNE_CONFIG_GID:-0}
    expected_mode=${DBTUNE_CONFIG_MODE:-644}
    [[ $expected_uid =~ ^[0-9]+$ && $expected_gid =~ ^[0-9]+$ && $expected_mode =~ ^[0-7]{3,4}$ ]] || return 64
    expected_mode=${expected_mode#0}
    read -r uid gid mode < <(dbtune_file_stat "$allowed") || return 1
    if [[ $uid != "$expected_uid" || $gid != "$expected_gid" || ${mode: -2:1} == [2367] || ${mode: -1} == [2367] ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_allowed_dir_metadata "$allowed" "$uid" "$gid" "$mode")"
        return 65
    fi
    DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY=$(dbtune_lifecycle_file_identity "$allowed") || return
    if [[ -n $expected_directory_identity && $DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY != "$expected_directory_identity" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_allowed_dir_replaced_apply)"
        return 65
    fi

    DBTUNE_LIFECYCLE_TARGET_IDENTITY=
    DBTUNE_LIFECYCLE_TARGET_HASH=
    if [[ -L $target ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_target_symlink "$target")"
        return 65
    elif [[ -e $target ]]; then
        if [[ ! -f $target ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_target_not_regular "$target")"
            return 65
        fi
        read -r uid gid mode < <(dbtune_file_stat "$target") || return 1
        if [[ $uid != "$expected_uid" || $gid != "$expected_gid" || $mode != "$expected_mode" ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_target_metadata "$target" "$uid" "$gid" "$mode")"
            return 65
        fi
        links=$(dbtune_lifecycle_file_links "$target") || return 1
        if [[ $links != 1 ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_target_hardlinks "$target")"
            return 65
        fi
        DBTUNE_LIFECYCLE_TARGET_TOPOLOGY=regular
        DBTUNE_LIFECYCLE_TARGET_IDENTITY=$(dbtune_lifecycle_file_identity "$target") || return
        DBTUNE_LIFECYCLE_TARGET_HASH=$(dbtune_sha256_file "$target") || return
    else
        DBTUNE_LIFECYCLE_TARGET_TOPOLOGY=absent
    fi
    if [[ $expected_topology != any && $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY != "$expected_topology" ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_target_topology_changed "$expected_topology" "$DBTUNE_LIFECYCLE_TARGET_TOPOLOGY")"
        return 65
    fi
    if [[ -n $expected_target_identity && $DBTUNE_LIFECYCLE_TARGET_IDENTITY != "$expected_target_identity" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_target_replaced)"
        return 65
    fi
    if [[ -n $expected_target_hash && $DBTUNE_LIFECYCLE_TARGET_HASH != "$expected_target_hash" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_target_changed)"
        return 65
    fi
}

dbtune_lifecycle_proposal() {
    printf '%s/proposed-99-zz-tuning.cnf\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_current_file() {
    printf '%s/apply/current\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_last_rollback_file() {
    printf '%s/apply/last-rollback\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_intent_file() {
    printf '%s/apply-intent.tsv\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_rollback_intent_file() {
    printf '%s/rollback-intent.tsv\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_sync() {
    local sync_command=${DBTUNE_SYNC:-sync}

    "$sync_command"
}

dbtune_lifecycle_fault_inject() {
    local boundary=${1:-}

    if [[ ${DBTUNE_FAULT_INJECT:-} == "$boundary" ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_fault_injection "$boundary")"
        return 99
    fi
}

dbtune_lifecycle_force_phrase() {
    dbtune_msg lifecycle_force_phrase
    printf '\n'
}

dbtune_lifecycle_backup_phrase() {
    dbtune_msg lifecycle_backup_phrase
    printf '\n'
}

dbtune_lifecycle_bool() {
    case ${1:-} in
        0) printf 'false\n' ;;
        1) printf 'true\n' ;;
        *) return 64 ;;
    esac
}

dbtune_lifecycle_is_interactive() {
    [[ -t 0 ]]
}

dbtune_lifecycle_parse_args() {
    local restart=0
    local force=0

    while (($#)); do
        case $1 in
            --restart) restart=1 ;;
            --force) force=1 ;;
            *)
                dbtune_log error "$(dbtune_printf lifecycle_apply_unknown_option "$1")"
                return 64
                ;;
        esac
        shift
    done
    printf '%s\t%s\n' "$restart" "$force"
}

dbtune_lifecycle_confirm_force() {
    local phrase answer

    phrase=$(dbtune_lifecycle_force_phrase)
    if ! dbtune_lifecycle_is_interactive; then
        dbtune_log error "$(dbtune_msg lifecycle_force_tty)"
        return 77
    fi
    dbtune_eprintf lifecycle_confirmation_prompt "$phrase"
    IFS= read -r answer || return 77
    if [[ $answer != "$phrase" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_force_confirmation_mismatch)"
        return 77
    fi
    dbtune_event safety_confirmation confirmation_id apply_without_measurements ui_lang "$DBTUNE_I18N_LANGUAGE" || true
}

dbtune_lifecycle_confirm_backup() {
    local phrase answer

    phrase=$(dbtune_lifecycle_backup_phrase)
    if ! dbtune_lifecycle_is_interactive; then
        dbtune_log error "$(dbtune_msg lifecycle_backup_tty)"
        return 77
    fi
    dbtune_eprintf lifecycle_backup_missing_intro
    dbtune_eprintf lifecycle_confirmation_prompt "$phrase"
    IFS= read -r answer || return 77
    if [[ $answer != "$phrase" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_backup_confirmation_mismatch)"
        return 77
    fi
    dbtune_event safety_confirmation confirmation_id restorable_backup ui_lang "$DBTUNE_I18N_LANGUAGE" || true
}

dbtune_lifecycle_log_backup_rejection() {
    dbtune_log error "$(dbtune_printf lifecycle_backup_rejected \
        "${DBTUNE_BACKUP_EVIDENCE_ERROR:-invalid}" \
        "${DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS:-unknown}" \
        "${DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS:-${DBTUNE_MAX_BACKUP_AGE_SECONDS:-86400}}")"
}

dbtune_lifecycle_check_backup() {
    local evidence=${1:-}
    local status

    DBTUNE_APPLY_BACKUP_MODE=interactive
    DBTUNE_APPLY_BACKUP_SOURCE=operator
    DBTUNE_APPLY_BACKUP_LAST_SUCCESS=unknown
    DBTUNE_APPLY_BACKUP_AGE_SECONDS=unknown
    DBTUNE_APPLY_BACKUP_MAX_AGE_SECONDS=${DBTUNE_MAX_BACKUP_AGE_SECONDS:-86400}
    if [[ -n $evidence ]]; then
        if ! dbtune_backup_evidence_validate "$evidence"; then
            dbtune_lifecycle_log_backup_rejection
            return 65
        fi
        status=$(dbtune_manifest_value "$evidence" status) || return 65
        if [[ $status == verified ]]; then
            DBTUNE_APPLY_BACKUP_MODE=artifact
            DBTUNE_APPLY_BACKUP_SOURCE=$(dbtune_manifest_value "$evidence" source) || return 65
            DBTUNE_APPLY_BACKUP_LAST_SUCCESS=$(dbtune_manifest_value "$evidence" last_success) || return 65
            DBTUNE_APPLY_BACKUP_AGE_SECONDS=$DBTUNE_BACKUP_EVIDENCE_AGE_SECONDS
            DBTUNE_APPLY_BACKUP_MAX_AGE_SECONDS=$DBTUNE_BACKUP_EVIDENCE_MAX_AGE_SECONDS
            return 0
        fi
        if [[ $status == missing ]]; then
            dbtune_log error "$(dbtune_msg lifecycle_backup_confirmed_missing)"
            return 65
        fi
    fi
    dbtune_lifecycle_confirm_backup
}

dbtune_lifecycle_has_measurement() {
    local samples="$DBTUNE_STATE_DIR/samples.tsv"
    local analysis="$DBTUNE_STATE_DIR/analysis.tsv"
    local count

    [[ -s $samples && -s $analysis ]] || return 1
    dbtune_provenance_validate_analysis >/dev/null 2>&1 || return 1
    count=$(dbtune_samples_inspect "$samples" count) || return 1
    ((count >= ${DBTUNE_MIN_APPLY_SAMPLES:-288})) || return 1
    awk -F '\t' 'NR==1 {exit !(NF==8 && $1=="rule_id" && $2=="scope" && $5=="proposed_key" && $8=="reason_id")}' "$analysis"
}

dbtune_lifecycle_manifest_value_from() {
    local manifest=${1:-}
    local key=${2:-}

    awk -F '\t' -v wanted="$key" '$1==wanted {print $2; found=1; exit} END {if (!found) exit 1}' "$manifest"
}

dbtune_lifecycle_proposal_manifest_schema() {
    printf '%s\n' schema run_id audit_hash samples_hash analysis_hash analysis_fingerprint \
        proposal_hash proposal_count proposal_records_hash
}

dbtune_lifecycle_require_snapshot_hash() {
    local snapshot=${1:-}
    local expected_hash=${2:-}
    local actual_hash

    [[ $expected_hash =~ ^[0-9a-f]{64}$ ]] || return 65
    actual_hash=$(dbtune_sha256_file "$snapshot") || return 65
    if [[ $actual_hash != "$expected_hash" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_proposal_changed)"
        return 65
    fi
}

dbtune_lifecycle_prepare_proposal_snapshot() {
    local source=${1:-}
    local snapshot=${2:-}
    local records=${3:-}
    local status=0

    [[ -n $snapshot && -n $records && $snapshot != "$records" ]] || return 64
    [[ -r $source ]] || return 65
    dbtune_validate_single_link_file "$source" >/dev/null 2>&1 || return 65
    if ! command cp "$source" "$snapshot" || ! command chmod 400 "$snapshot"; then
        return 1
    fi
    dbtune_validate_single_link_file "$snapshot" >/dev/null 2>&1 || return 65
    dbtune_cnf_entries_strict "$snapshot" >"$records" || status=$?
    if ((status != 0)); then
        dbtune_log error "$(dbtune_msg lifecycle_proposal_invalid)"
        return 65
    fi
    command chmod 400 "$records" || return 1
    DBTUNE_APPLY_RECORD_COUNT=$(LC_ALL=C awk 'NF {count++} END {print count+0}' "$records") || return
    ((DBTUNE_APPLY_RECORD_COUNT > 0)) || return 65
    DBTUNE_APPLY_SNAPSHOT_HASH=$(dbtune_sha256_file "$snapshot") || return
    DBTUNE_APPLY_RECORDS_HASH=$(dbtune_sha256_file "$records") || return
    [[ $DBTUNE_APPLY_SNAPSHOT_HASH =~ ^[0-9a-f]{64}$ &&
        $DBTUNE_APPLY_RECORDS_HASH =~ ^[0-9a-f]{64}$ ]] || return 65
}

dbtune_lifecycle_validate_proposal_manifest() {
    local manifest="$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    local proposal=${1:-$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf}
    local records=${2:-}
    local analysis_manifest analysis key expected actual proposal_count proposal_records_hash
    local schema

    [[ -r $manifest ]] || {
        dbtune_log error "$(dbtune_printf lifecycle_proposal_manifest_missing "$manifest")"
        return 66
    }
    schema=$(dbtune_lifecycle_proposal_manifest_schema) || return
    if ! dbtune_manifest_validate_exact "$manifest" "$schema"; then
        dbtune_log error "$(dbtune_msg lifecycle_proposal_manifest_invalid)"
        return 65
    fi
    dbtune_provenance_validate_analysis || return
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    for key in run_id audit_hash samples_hash analysis_hash analysis_fingerprint; do
        expected=$(dbtune_manifest_value "$analysis_manifest" "$key") || return 65
        actual=$(dbtune_manifest_value "$manifest" "$key") || {
            dbtune_log error "$(dbtune_printf lifecycle_proposal_manifest_key_missing "$key")"
            return 65
        }
        if [[ $actual != "$expected" ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_proposal_other_run "$key")"
            return 65
        fi
    done
    expected=$(dbtune_manifest_value "$manifest" proposal_hash) || {
        dbtune_log error "$(dbtune_msg lifecycle_proposal_hash_missing)"
        return 65
    }
    [[ $expected =~ ^[0-9a-f]{64}$ && -r $proposal ]] || return 65
    if [[ $expected != "$DBTUNE_APPLY_SNAPSHOT_HASH" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_proposal_changed)"
        return 65
    fi
    proposal_count=$(dbtune_manifest_value "$manifest" proposal_count) || {
        dbtune_log error "$(dbtune_msg lifecycle_proposal_count_missing)"
        return 65
    }
    proposal_records_hash=$(dbtune_manifest_value "$manifest" proposal_records_hash) || {
        dbtune_log error "$(dbtune_msg lifecycle_proposal_records_hash_missing)"
        return 65
    }
    [[ $proposal_count =~ ^[1-9][0-9]*$ && $proposal_records_hash =~ ^[0-9a-f]{64}$ ]] || return 65
    DBTUNE_AUDIT_FILE=$(dbtune_path audit.tsv) || return
    analysis=$(dbtune_path analysis.tsv) || return
    dbtune_analysis_load "$analysis" || return
    dbtune_proposals_load "$DBTUNE_AUDIT_FILE" || return
    if ((${#DBTUNE_PROPOSAL_LINES[@]} != proposal_count)) ||
        [[ $(dbtune_proposal_records_hash) != "$proposal_records_hash" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_proposal_records_mismatch)"
        return 65
    fi
    dbtune_lifecycle_validate_proposal_records "$records" || return
}

dbtune_lifecycle_validate_proposal_records() {
    local records=${1:-}
    local line key value
    local -A expected=() actual=()

    for line in "${DBTUNE_PROPOSAL_LINES[@]}"; do
        dbtune_proposal_parse "$line"
        expected["$DBTUNE_PROPOSAL_KEY"]=$DBTUNE_PROPOSAL_VALUE
    done
    while IFS=$'\t' read -r key value; do
        [[ -n $key ]] || continue
        if [[ -n ${actual[$key]+x} ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_cnf_duplicate "$key")"
            return 65
        fi
        actual["$key"]=$value
    done <"$records"
    if ((${#expected[@]} != ${#actual[@]})); then
        dbtune_log error "$(dbtune_msg lifecycle_cnf_count_mismatch)"
        return 65
    fi
    for key in "${!expected[@]}"; do
        if [[ -z ${actual[$key]+x} || ${actual[$key]} != "${expected[$key]}" ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_cnf_record_mismatch "$key")"
            return 65
        fi
    done
}

dbtune_lifecycle_check_apply_inputs() {
    local force=${1:-0}
    local proposal=${2:-}
    local records=${3:-}
    local analysis state

    [[ -n $proposal ]] || proposal=$(dbtune_lifecycle_proposal)
    state=$(dbtune_state_read) || return
    if ((force == 0)) && [[ $state != proposed ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_apply_state_required "$state")"
        return 65
    fi
    if ((force == 1)) && [[ $state != audited && $state != analyzed && $state != proposed ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_force_state_required "$state")"
        return 65
    fi
    if [[ ! -s $proposal ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_proposal_missing "$proposal")"
        return 66
    fi
    analysis=$(dbtune_path analysis.tsv) || return
    if [[ -s $analysis ]]; then
        dbtune_analysis_validate_schema "$analysis" || return
    fi
    if ! dbtune_lifecycle_has_measurement && ((force == 0)); then
        dbtune_log error "$(dbtune_msg lifecycle_measurement_missing)"
        return 65
    fi
    if ((force == 0)); then
        dbtune_lifecycle_validate_proposal_manifest "$proposal" "$records" || return
    fi
}

dbtune_lifecycle_check_time_window() {
    local force=${1:-0}
    local clock hour minute total

    ((force == 1)) && return 0
    clock=${DBTUNE_NOW_HHMM:-}
    [[ -n $clock ]] || clock=$(date '+%H%M') || return 1
    if [[ ! $clock =~ ^[0-2][0-9][0-5][0-9]$ ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_invalid_clock "$clock")"
        return 70
    fi
    hour=${clock:0:2}
    minute=${clock:2:2}
    total=$((10#$hour * 60 + 10#$minute))
    if ((total >= 330 && total <= 450)); then
        dbtune_log error "$(dbtune_msg lifecycle_blocked_time_window)"
        return 75
    fi
}

dbtune_lifecycle_config_entries() {
    local proposal=${1:-}

    awk '
        /^[[:space:]]*\[/ {
            section=$0
            gsub(/[[:space:]]/, "", section)
            active=(tolower(section) == "[mysqld]")
            next
        }
        active {
            line=$0
            sub(/[[:space:]]*[#;].*$/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == "" || line ~ /^!/) next
            split(line, parts, "=")
            name=parts[1]
            gsub(/[[:space:]]/, "", name)
            if (name !~ /^[A-Za-z][A-Za-z0-9_-]*$/) next
            value="1"
            if (index(line, "=") > 0) {
                value=substr(line, index(line, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            }
            normalized=tolower(name)
            gsub(/-/, "_", normalized)
            values[normalized]=value
            order[++count]=normalized
        }
        END {
            for (i=1; i<=count; i++) last[order[i]]=i
            for (i=1; i<=count; i++)
                if (last[order[i]] == i) print order[i] "\t" values[order[i]]
        }
    ' "$proposal"
}

dbtune_lifecycle_validate_variable_names() {
    local records=${1:-}
    local expected_records_hash=${2:-}
    local records_capture records_hash query list='' separator='' name value extra output_file command_status=0 malformed=0
    local -A requested=() found=()

    records_capture=$(command cat "$records") || return 65
    [[ -n $records_capture && $expected_records_hash =~ ^[0-9a-f]{64}$ ]] || return 65
    records_hash=$(printf '%s\n' "$records_capture" | dbtune_sha256_stream) || return
    [[ $records_hash == "$expected_records_hash" ]] || return 65
    dbtune_lifecycle_after_records_hash "$records" || return
    while IFS=$'\t' read -r name value extra; do
        [[ -n $name && -n $value && -z $extra ]] || return 65
        requested["$name"]=1
        list+="${separator}'$name'"
        separator=,
    done <<<"$records_capture"
    if ((${#requested[@]} == 0)); then
        dbtune_log error "$(dbtune_msg lifecycle_no_active_variables)"
        return 65
    fi

    query="SELECT LOWER(VARIABLE_NAME) FROM information_schema.GLOBAL_VARIABLES WHERE LOWER(VARIABLE_NAME) IN ($list)"
    output_file=$(mktemp "$DBTUNE_STATE_DIR/.variables.XXXXXX") || return 1
    dbtune_sql "$query" >"$output_file" || command_status=$?
    if ! LC_ALL=C awk -F '\t' 'NF != 1 || $0 == "" || $0 ~ /[[:cntrl:]]/ {exit 1}' "$output_file"; then
        rm -f "$output_file"
        dbtune_log error "$(dbtune_msg lifecycle_live_variable_check_failed)"
        return 65
    fi
    if ((command_status != 0)) && [[ ! -s $output_file ]]; then
        rm -f "$output_file"
        dbtune_log error "$(dbtune_msg lifecycle_live_variable_check_failed)"
        return 69
    fi
    while IFS= read -r name; do
        name=${name,,}
        if ! dbtune_proposal_key_is_safe "$name" || [[ -z ${requested[$name]+x} || -n ${found[$name]+x} ]]; then
            malformed=1
            break
        fi
        found["$name"]=1
    done <"$output_file"
    rm -f "$output_file"
    if ((malformed == 1)); then
        dbtune_log error "$(dbtune_msg lifecycle_live_variable_check_failed)"
        return 65
    fi

    if ((${#requested[@]} != ${#found[@]})); then
        for name in "${!requested[@]}"; do
            if [[ -z ${found[$name]+x} ]]; then
                dbtune_log error "$(dbtune_printf lifecycle_unknown_variable "$name")"
                return 65
            fi
        done
        return 65
    fi
    if ((command_status != 0)); then
        dbtune_log error "$(dbtune_msg lifecycle_live_variable_check_failed)"
        return 69
    fi
    for name in "${!requested[@]}"; do
        if [[ -z ${found[$name]+x} ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_unknown_variable "$name")"
            return 65
        fi
    done
}

dbtune_lifecycle_reject_galera() {
    local result wsrep_on cluster_address

    result=$(dbtune_sql "SELECT CONCAT(COALESCE((SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME='WSREP_ON'),'OFF'), CHAR(9), COALESCE((SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME='WSREP_CLUSTER_ADDRESS'),''))") || return
    IFS=$'\t' read -r wsrep_on cluster_address <<<"$result"
    wsrep_on=${wsrep_on^^}
    if [[ $wsrep_on == ON || $wsrep_on == 1 || -n $cluster_address ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_galera_rejected)"
        return 65
    fi
}

dbtune_lifecycle_reject_mydumper() {
    local count

    count=$(dbtune_sql "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE ID <> CONNECTION_ID() AND (LOWER(COALESCE(USER,'')) LIKE '%mydumper%' OR LOWER(COALESCE(INFO,'')) LIKE '%mydumper%' OR COALESCE(INFO,'') LIKE '%SQL_NO_CACHE%')") || return
    if [[ ! $count =~ ^[0-9]+$ ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_mydumper_invalid)"
        return 70
    fi
    if ((count > 0)); then
        dbtune_log error "$(dbtune_msg lifecycle_mydumper_running)"
        return 75
    fi
}

dbtune_lifecycle_reject_critical_analysis() {
    local analysis="$DBTUNE_STATE_DIR/analysis.tsv"
    local records findings='' rule_id verdict reason_id reason

    [[ -r $analysis ]] || return 66
    records=$(awk -F '\t' 'BEGIN {OFS="\t"}
        NR > 1 && $2 == "server" && $3 == "critical" &&
        (($1 == "R-VERSION" && ($4 == "UNSUPPORTED" || $4 == "REMOVED")) ||
         ($1 == "R-BACKUP" && $4 == "MISSING")) {
            print $1, $4, $8
        }
    ' "$analysis")
    [[ -n $records ]] || return 0
    while IFS=$'\t' read -r rule_id verdict reason_id; do
        reason=$(dbtune_msg "$reason_id") || return
        [[ -z $findings ]] || findings+=$'\n'
        findings+="$rule_id: $verdict - $reason"
    done <<<"$records"
    dbtune_log error "$(dbtune_printf lifecycle_critical_finding "$findings")"
    return 65
}

dbtune_lifecycle_new_history() {
    local root stamp history suffix=0

    root="$DBTUNE_STATE_DIR/apply"
    install -d -m 700 "$root" || return 1
    stamp=$(date -u '+%Y%m%dT%H%M%SZ') || return 1
    history="$root/$stamp-$$"
    while [[ -e $history ]]; do
        ((suffix += 1))
        history="$root/$stamp-$$-$suffix"
    done
    install -d -m 700 "$history" || return 1
    printf '%s\n' "$history"
}

dbtune_lifecycle_discard_uncommitted_history() {
    local history=${1:-}
    local root="$DBTUNE_STATE_DIR/apply"
    local cycle_id=${history##*/}

    [[ ${history%/*} == "$root" && $cycle_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ &&
        -d $history && ! -L $history ]] || return 65
    rm -rf "$history" || return 1
    rmdir "$root" 2>/dev/null || true
}

dbtune_lifecycle_shell_quote() {
    local value=${1-}

    printf "'%s'" "${value//\'/\'\\\'\'}"
}

dbtune_lifecycle_write_rollback_instructions() {
    local history=${1:-}
    local target=${2:-}
    local had_original=${3:-0}
    local target_q history_q backup_q removed_q

    target_q=$(dbtune_lifecycle_shell_quote "$target")
    history_q=$(dbtune_lifecycle_shell_quote "$history")
    backup_q=$(dbtune_lifecycle_shell_quote "$history/original.cnf")
    removed_q=$(dbtune_lifecycle_shell_quote "$history/rollback-deployed.cnf")
    {
        dbtune_printf lifecycle_rollback_intro
        printf 'sudo test -d %s\n' "$history_q"
        printf 'sudo test ! -L %s\n' "$target_q"
        printf 'if sudo test -e %s; then sudo test -f %s && sudo mv %s %s; fi\n' "$target_q" "$target_q" "$target_q" "$removed_q"
        if ((had_original == 1)); then
            printf 'sudo install -o root -g root -m 0644 %s %s\n' "$backup_q" "$target_q"
        fi
        printf 'if sudo systemctl is-active --quiet mariadb; then\n'
        dbtune_printf lifecycle_rollback_restored_shell
        printf 'else\n'
        printf '  sudo systemctl start mariadb\n'
        printf 'fi\n'
    } | dbtune_atomic_write "$history/ROLLBACK.txt" 600
}

dbtune_lifecycle_prepare_history() {
    local history=${1:-}
    local target=${2:-}
    local proposal=${3:-}
    local backup_evidence=${4:-}
    local expected_topology=${5:-}
    local expected_directory_identity=${6:-}
    local expected_target_identity=${7:-}
    local expected_target_hash=${8:-}
    local expected_parent_identities=${9:-}
    local previous_current=${10:-}
    local expected_proposal_hash=${11:-}
    local expected_records_hash=${12:-}
    local expected_record_count=${13:-}
    local had_original=0 original_hash=absent proposal_hash expected_hash run_id=unmeasured audit_hash=unmeasured
    local backup_hash=interactive
    local cycle_id original_source=absent original_cycle_id=- original_cycle_history=- original_backup=absent
    local source_target source_hash source_snapshot_hash
    local proposal_manifest="$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    local proposal_schema

    cycle_id=${history##*/}
    [[ ${history%/*} == "$DBTUNE_STATE_DIR/apply" && $cycle_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 65
    [[ $expected_records_hash =~ ^[0-9a-f]{64}$ && $expected_record_count =~ ^[1-9][0-9]*$ ]] || return 65
    dbtune_lifecycle_validate_target_path "$target" "$expected_topology" \
        "$expected_directory_identity" "$expected_target_identity" "$expected_target_hash" || return
    if [[ $DBTUNE_LIFECYCLE_PARENT_IDENTITIES != "$expected_parent_identities" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_parent_replaced_prepare)"
        return 65
    fi
    if [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == regular ]]; then
        cp -p "$target" "$history/original.cnf" || return 1
        chmod 600 "$history/original.cnf" || return 1
        dbtune_lifecycle_validate_target_path "$target" regular \
            "$expected_directory_identity" "$expected_target_identity" "$expected_target_hash" || return
        original_hash=$(dbtune_sha256_file "$history/original.cnf") || return
        [[ $original_hash == "$expected_target_hash" ]] || {
            dbtune_log error "$(dbtune_msg lifecycle_original_backup_mismatch)"
            return 65
        }
        had_original=1
        original_source=external
        original_backup=original.cnf
        if [[ -n $previous_current ]]; then
            original_cycle_id=$(dbtune_lifecycle_cycle_id "$previous_current") || return
            source_target=$(dbtune_lifecycle_manifest_value "$previous_current" target)
            source_hash=$(dbtune_lifecycle_manifest_value "$previous_current" proposal_hash)
            if [[ -f $previous_current/proposed.cnf && ! -L $previous_current/proposed.cnf ]]; then
                source_snapshot_hash=$(dbtune_sha256_file "$previous_current/proposed.cnf") || return
            fi
            if [[ $source_target == "$target" && $source_hash == "$original_hash" &&
                $source_snapshot_hash == "$original_hash" ]]; then
                original_source=apply_cycle
                original_cycle_history=$previous_current
            else
                original_cycle_id=-
            fi
        fi
    fi
    dbtune_lifecycle_before_history_copy "$proposal" || return
    dbtune_lifecycle_require_snapshot_hash "$proposal" "$expected_proposal_hash" || return
    cp "$proposal" "$history/proposed.cnf" || return 1
    chmod 600 "$history/proposed.cnf" || return 1
    if [[ $DBTUNE_APPLY_BACKUP_MODE == artifact ]]; then
        cp "$backup_evidence" "$history/backup-evidence.tsv" || return 1
        chmod 600 "$history/backup-evidence.tsv" || return 1
        backup_hash=$(dbtune_sha256_file "$history/backup-evidence.tsv") || return
    else
        {
            printf 'schema\t1\n'
            printf 'status\tunknown\n'
            printf 'source\toperator\n'
            printf 'checked_at\t%s\n' "$(dbtune_now)"
            printf 'last_success\tunknown\n'
            printf 'guard\tinteractive-confirmation\n'
        } | dbtune_atomic_write "$history/backup-confirmation.tsv" 600 || return 1
    fi
    proposal_hash=$(dbtune_sha256_file "$history/proposed.cnf") || return
    [[ $proposal_hash == "$expected_proposal_hash" ]] || {
        dbtune_log error "$(dbtune_msg lifecycle_proposal_changed)"
        return 65
    }
    proposal_schema=$(dbtune_lifecycle_proposal_manifest_schema) || return
    if dbtune_manifest_validate_exact "$proposal_manifest" "$proposal_schema"; then
        expected_hash=$(dbtune_manifest_value "$proposal_manifest" proposal_hash 2>/dev/null || true)
    fi
    if [[ $expected_hash == "$proposal_hash" ]]; then
        run_id=$(dbtune_manifest_value "$proposal_manifest" run_id 2>/dev/null || printf unknown)
        audit_hash=$(dbtune_manifest_value "$proposal_manifest" audit_hash 2>/dev/null || printf unknown)
    fi
    {
        printf 'cycle_id\t%s\n' "$cycle_id"
        printf 'target\t%s\n' "$target"
        printf 'directory_identity\t%s\n' "$expected_directory_identity"
        printf 'parent_identities\t%s\n' "$expected_parent_identities"
        printf 'had_original\t%s\n' "$had_original"
        printf 'original_hash\t%s\n' "$original_hash"
        printf 'original_source\t%s\n' "$original_source"
        printf 'original_cycle_id\t%s\n' "$original_cycle_id"
        printf 'original_cycle_history\t%s\n' "$original_cycle_history"
        printf 'original_backup\t%s\n' "$original_backup"
        printf 'created_at\t%s\n' "$(dbtune_now)"
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'proposal_hash\t%s\n' "$proposal_hash"
        printf 'proposal_records_hash\t%s\n' "$expected_records_hash"
        printf 'proposal_count\t%s\n' "$expected_record_count"
        printf 'backup_guard\t%s\n' "$DBTUNE_APPLY_BACKUP_MODE"
        printf 'backup_source\t%s\n' "$DBTUNE_APPLY_BACKUP_SOURCE"
        printf 'backup_last_success\t%s\n' "$DBTUNE_APPLY_BACKUP_LAST_SUCCESS"
        printf 'backup_age_seconds\t%s\n' "$DBTUNE_APPLY_BACKUP_AGE_SECONDS"
        printf 'backup_max_age_seconds\t%s\n' "$DBTUNE_APPLY_BACKUP_MAX_AGE_SECONDS"
        printf 'backup_evidence_hash\t%s\n' "$backup_hash"
    } | dbtune_atomic_write "$history/manifest.tsv" 600 || return 1
    dbtune_lifecycle_write_rollback_instructions "$history" "$target" "$had_original" || return 1
    printf '%s\n' "$had_original"
}

dbtune_lifecycle_install_config() {
    local proposal=${1:-}
    local target=${2:-}
    local expected_topology=${3:-}
    local expected_directory_identity=${4:-}
    local expected_target_identity=${5:-}
    local expected_target_hash=${6:-}
    local expected_parent_identities=${7:-}
    local expected_proposal_hash=${8:-}
    local expected_records_hash=${9:-}
    local expected_record_count=${10:-}
    local directory temporary status

    directory=${target%/*}
    [[ $expected_records_hash =~ ^[0-9a-f]{64}$ && $expected_record_count =~ ^[1-9][0-9]*$ ]] || return 65
    dbtune_lifecycle_validate_target_path "$target" "$expected_topology" \
        "$expected_directory_identity" "$expected_target_identity" "$expected_target_hash" || return
    dbtune_lifecycle_before_target_copy "$proposal" || return
    dbtune_lifecycle_require_snapshot_hash "$proposal" "$expected_proposal_hash" || return
    temporary=$(mktemp "$directory/.99-zz-tuning.cnf.tmp.XXXXXX") || return 1
    if ! command cat "$proposal" >"$temporary" || ! chown root:root "$temporary" || ! chmod 0644 "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if dbtune_lifecycle_publish_managed_config "$temporary" "$target" "$expected_topology" \
        "$expected_directory_identity" "$expected_target_identity" "$expected_target_hash" \
        "$expected_proposal_hash" "$expected_parent_identities"; then
        :
    else
        status=$?
        rm -f "$temporary"
        return "$status"
    fi
}

dbtune_lifecycle_require_publisher() {
    local python=${DBTUNE_PYTHON:-python3}

    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || python=$(dbtune_runtime_command_path python3) || return 69
    if ! command -v "$python" >/dev/null 2>&1 || ! "$python" -I -E -s - <<'PY'
import ctypes
import os
import sys

dir_fd_operations = (os.open, os.stat, os.link, os.rename, os.unlink)
follow_operations = (os.stat, os.link)
if not all(operation in os.supports_dir_fd for operation in dir_fd_operations):
    sys.exit(1)
if not all(operation in os.supports_follow_symlinks for operation in follow_operations):
    sys.exit(1)
libc = ctypes.CDLL(None)
if sys.platform.startswith("linux") and not hasattr(libc, "renameat2"):
    sys.exit(1)
if sys.platform == "darwin" and not hasattr(libc, "renameatx_np"):
    sys.exit(1)
if not sys.platform.startswith("linux") and sys.platform != "darwin":
    sys.exit(1)
PY
    then
        dbtune_log error "$(dbtune_msg lifecycle_publisher_required)"
        return 69
    fi
}

dbtune_lifecycle_publish_managed_config() {
    local source=${1:--}
    local target=${2:-}
    local expected_topology=${3:-}
    local expected_directory_identity=${4:-}
    local expected_target_identity=${5:-}
    local expected_target_hash=${6:-}
    local expected_source_hash=${7:-}
    local expected_parent_identities=${8:-}
    local directory base source_base=- python expected_uid expected_gid expected_mode status=0
    local fail_match='' fault_hook='' crash_point='' crash_match=''
    local message_not_regular message_metadata message_hardlinks message_replaced message_changed
    local message_open_dir message_dir_replaced message_parent_chain message_parent_replaced
    local message_topology message_fault_hook message_atomic_flags message_fault_before message_failed

    directory=${target%/*}
    base=${target##*/}
    expected_uid=${DBTUNE_CONFIG_UID:-0}
    expected_gid=${DBTUNE_CONFIG_GID:-0}
    expected_mode=${DBTUNE_CONFIG_MODE:-644}
    if [[ $source != - ]]; then
        [[ ${source%/*} == "$directory" ]] || return 64
        source_base=${source##*/}
        [[ $expected_source_hash =~ ^[0-9a-f]{64}$ ]] || return 64
    fi
    [[ $expected_topology == absent || $expected_topology == regular ]] || return 64
    [[ $expected_directory_identity =~ ^[0-9]+:[0-9]+$ ]] || return 64
    python=${DBTUNE_PYTHON:-python3}
    if [[ $DBTUNE_ARTIFACT_PROFILE == production ]]; then
        python=$(dbtune_runtime_command_path python3) || return 69
    else
        fail_match=${DBTUNE_PUBLISH_FAIL_MATCH:-}
        fault_hook=${DBTUNE_PUBLISH_FAULT_HOOK:-}
        crash_point=${DBTUNE_PUBLISH_CRASH_POINT:-}
        crash_match=${DBTUNE_PUBLISH_CRASH_MATCH:-}
    fi
    dbtune_lifecycle_require_publisher || return
    message_not_regular=$(dbtune_msg lifecycle_publisher_not_regular) || return
    message_metadata=$(dbtune_msg lifecycle_publisher_metadata) || return
    message_hardlinks=$(dbtune_msg lifecycle_publisher_hardlinks) || return
    message_replaced=$(dbtune_msg lifecycle_publisher_replaced) || return
    message_changed=$(dbtune_msg lifecycle_publisher_changed) || return
    message_open_dir=$(dbtune_msg lifecycle_publisher_open_dir_identity) || return
    message_dir_replaced=$(dbtune_msg lifecycle_publisher_dir_replaced) || return
    message_parent_chain=$(dbtune_msg lifecycle_publisher_parent_chain) || return
    message_parent_replaced=$(dbtune_msg lifecycle_publisher_parent_replaced) || return
    message_topology=$(dbtune_msg lifecycle_publisher_topology_changed) || return
    message_fault_hook=$(dbtune_msg lifecycle_publisher_fault_hook) || return
    message_atomic_flags=$(dbtune_msg lifecycle_publisher_atomic_flags) || return
    message_fault_before=$(dbtune_msg lifecycle_publisher_fault_before) || return
    message_failed=$(dbtune_msg lifecycle_publisher_failed) || return

    dbtune_lifecycle_validate_parent_components "$directory" || return
    if [[ -z $expected_parent_identities ]]; then
        expected_parent_identities=$(dbtune_lifecycle_parent_identity_chain "$directory") || return
    elif [[ $(dbtune_lifecycle_parent_identity_chain "$directory") != "$expected_parent_identities" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_parent_replaced_validation)"
        return 65
    fi
    dbtune_lifecycle_before_publish "$target" "$source" || return
    "$python" -I -E -s - "$directory" "$base" "$source_base" \
        "$expected_directory_identity" "$expected_parent_identities" "$expected_topology" "$expected_target_identity" \
        "$expected_target_hash" "$expected_source_hash" "$expected_uid" "$expected_gid" \
        "$expected_mode" "$message_not_regular" "$message_metadata" "$message_hardlinks" \
        "$message_replaced" "$message_changed" "$message_open_dir" "$message_dir_replaced" \
        "$message_parent_chain" "$message_parent_replaced" "$message_topology" "$message_fault_hook" \
        "$message_atomic_flags" "$message_fault_before" "$message_failed" \
        "$fail_match" "$fault_hook" "$crash_point" "$crash_match" <<'PY' || status=$?
import ctypes
import errno
import hashlib
import os
import stat
import subprocess
import sys

(
    directory,
    target,
    source,
    expected_directory_identity,
    expected_parent_identities,
    expected_topology,
    expected_target_identity,
    expected_target_hash,
    expected_source_hash,
    expected_uid,
    expected_gid,
    expected_mode,
    message_not_regular,
    message_metadata,
    message_hardlinks,
    message_replaced,
    message_changed,
    message_open_dir,
    message_dir_replaced,
    message_parent_chain,
    message_parent_replaced,
    message_topology,
    message_fault_hook,
    message_atomic_flags,
    message_fault_before,
    message_failed,
    fail_match,
    fault_hook,
    crash_point,
    crash_match,
) = sys.argv[1:]
expected_uid = int(expected_uid)
expected_gid = int(expected_gid)
expected_mode = int(expected_mode, 8)
expected_parent_identities = expected_parent_identities.split(",")
directory_fd = None
source_fd = None
commit = "none"
libc = ctypes.CDLL(None, use_errno=True)


class UnsafePublication(Exception):
    pass


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


def hash_fd(fd):
    digest = hashlib.sha256()
    os.lseek(fd, 0, os.SEEK_SET)
    while True:
        block = os.read(fd, 131072)
        if not block:
            break
        digest.update(block)
    return digest.hexdigest()


def rename_with_flags(old_name, new_name, linux_flags, darwin_flags):
    old_name = os.fsencode(old_name)
    new_name = os.fsencode(new_name)
    if sys.platform.startswith("linux"):
        function = libc.renameat2
        function.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
        function.restype = ctypes.c_int
        result = function(directory_fd, old_name, directory_fd, new_name, linux_flags)
    elif sys.platform == "darwin":
        function = libc.renameatx_np
        function.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
        function.restype = ctypes.c_int
        result = function(directory_fd, old_name, directory_fd, new_name, darwin_flags)
    else:
        raise OSError(errno.ENOSYS, message_atomic_flags)
    if result != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def exchange(old_name, new_name):
    rename_with_flags(old_name, new_name, 2, 2)


def rename_noreplace(old_name, new_name):
    rename_with_flags(old_name, new_name, 1, 4)


def crash_at(point):
    if crash_point == point and (not crash_match or crash_match in source):
        os._exit(99)


def open_regular(name, expected_identity, expected_hash, links=1):
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(name, flags, dir_fd=directory_fd)
    details = os.fstat(fd)
    if not stat.S_ISREG(details.st_mode):
        os.close(fd)
        raise UnsafePublication(message_not_regular % name)
    if details.st_uid != expected_uid or details.st_gid != expected_gid or stat.S_IMODE(details.st_mode) != expected_mode:
        os.close(fd)
        raise UnsafePublication(message_metadata % name)
    if links is not None and details.st_nlink != links:
        os.close(fd)
        raise UnsafePublication(message_hardlinks % name)
    if expected_identity and identity(details) != expected_identity:
        os.close(fd)
        raise UnsafePublication(message_replaced % name)
    if expected_hash and hash_fd(fd) != expected_hash:
        os.close(fd)
        raise UnsafePublication(message_changed % name)
    return fd, details


def require_parent_identity():
    opened = os.fstat(directory_fd)
    current = os.stat(directory, follow_symlinks=False)
    if not stat.S_ISDIR(opened.st_mode) or identity(opened) != expected_directory_identity:
        raise UnsafePublication(message_open_dir)
    if not stat.S_ISDIR(current.st_mode) or identity(current) != expected_directory_identity:
        raise UnsafePublication(message_dir_replaced)
    components = [component for component in directory.split("/") if component]
    if len(components) != len(expected_parent_identities):
        raise UnsafePublication(message_parent_chain)
    current_path = ""
    for component, expected_identity in zip(components, expected_parent_identities):
        current_path += "/" + component
        details = os.stat(current_path, follow_symlinks=False)
        if not stat.S_ISDIR(details.st_mode) or identity(details) != expected_identity:
            raise UnsafePublication(message_parent_replaced % current_path)


def require_absent(name):
    try:
        os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    raise UnsafePublication(message_topology % name)


def rollback_commit():
    global commit
    try:
        if commit == "exchange":
            exchange(source, target)
            commit = "none"
        elif commit == "move":
            require_absent(source)
            rename_noreplace(target, source)
            commit = "none"
    except (OSError, UnsafePublication):
        pass


try:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_fd = os.open(directory, flags)
    require_parent_identity()

    if expected_topology == "regular":
        target_fd, _ = open_regular(target, expected_target_identity, expected_target_hash)
        os.close(target_fd)
    else:
        require_absent(target)

    if source != "-":
        source_fd, source_details = open_regular(source, "", expected_source_hash)

    require_parent_identity()
    if fault_hook:
        result = subprocess.run((fault_hook, directory, target, source), check=False)
        if result.returncode != 0:
            raise UnsafePublication(message_fault_hook)
    require_parent_identity()
    if expected_topology == "regular":
        target_fd, _ = open_regular(target, expected_target_identity, expected_target_hash)
        os.close(target_fd)
    else:
        require_absent(target)
    if source != "-":
        checked_source_fd, _ = open_regular(source, identity(source_details), expected_source_hash)
        os.close(checked_source_fd)

    crash_at("after_validation")
    if fail_match and fail_match in source:
        raise OSError(message_fault_before)
    if source == "-":
        if expected_topology == "regular":
            os.unlink(target, dir_fd=directory_fd)
            commit = "remove"
    elif expected_topology == "regular":
        exchange(source, target)
        commit = "exchange"
    else:
        rename_noreplace(source, target)
        commit = "move"
    crash_at("after_commit")

    require_parent_identity()
    if commit == "exchange":
        displaced_fd, _ = open_regular(source, expected_target_identity, expected_target_hash)
        os.close(displaced_fd)
        published_fd, _ = open_regular(target, identity(source_details), expected_source_hash)
        os.close(published_fd)
    elif commit == "move":
        require_absent(source)
        published_fd, _ = open_regular(target, identity(source_details), expected_source_hash)
        os.close(published_fd)
    elif commit == "remove":
        require_absent(target)
    else:
        require_absent(target)
    crash_at("after_postvalidation")

    if commit == "exchange":
        os.unlink(source, dir_fd=directory_fd)
    commit = "done"
    require_parent_identity()
    sys.exit(0)
except (OSError, UnsafePublication) as error:
    rollback_commit()
    print(message_failed % error, file=sys.stderr)
    sys.exit(65)
finally:
    if source_fd is not None:
        os.close(source_fd)
    if directory_fd is not None:
        os.close(directory_fd)
PY
    return "$status"
}

dbtune_lifecycle_validation_output_ok() {
    local output_file=${1:-}
    local line lower
    local bad=0

    while IFS= read -r line || [[ -n $line ]]; do
        lower=${line,,}
        case $lower in
            *"can't lock aria control file"*"error: 11"*|*"innodb: unable to lock ./ibdata1 error: 11"*|*"plugin 'aria' registration as a storage engine failed."|*"[error] failed to initialize plugins."|*"[error] aborting"|*"[error] aborting.")
                continue
                ;;
        esac
        if [[ $lower =~ unknown[[:space:]]+(variable|option) || $lower == *"invalid value"* || $lower == *"invalid argument"* || $lower == *"invalid option"* || $lower == *"is invalid"* || $lower == *"error while setting value"* || $lower == *"incorrect value"* || $lower == *"failed to set value"* || $lower == *"[error]"* ]]; then
            printf '%s\n' "$line" >&2
            bad=1
        fi
    done <"$output_file"
    ((bad == 0))
}

dbtune_lifecycle_validation_has_tolerated_error() {
    local output_file=${1:-}
    local line lower

    while IFS= read -r line || [[ -n $line ]]; do
        lower=${line,,}
        case $lower in
            *"can't lock aria control file"*"error: 11"*|*"innodb: unable to lock ./ibdata1 error: 11"*) return 0 ;;
        esac
    done <"$output_file"
    return 1
}

dbtune_lifecycle_validate_config() {
    local server validate_dir validate_datadir output_file probe_file command_status=0 probe_status=0

    if command -v mariadbd >/dev/null 2>&1; then
        server=$(command -v mariadbd)
    elif command -v mysqld >/dev/null 2>&1; then
        server=$(command -v mysqld)
    else
        dbtune_log error "$(dbtune_msg lifecycle_validation_server_missing)"
        return 69
    fi
    validate_dir=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-validate.XXXXXX") || return 1
    validate_datadir="$validate_dir/data"
    output_file="$validate_dir/output.log"
    probe_file="$validate_dir/help.log"

    if ! : >"$probe_file" || ! : >"$output_file" ||
        ! chmod 0600 "$probe_file" "$output_file"; then
        rm -rf "$validate_dir"
        return 1
    fi

    "$server" --help --verbose >"$probe_file" 2>&1 || probe_status=$?
    if grep -q -- '--validate-config' "$probe_file"; then
        if ! mkdir -m 0700 "$validate_datadir" ||
            ! chown mysql:mysql "$validate_datadir" ||
            ! chown root:mysql "$validate_dir" ||
            ! chmod 0710 "$validate_dir"; then
            rm -rf "$validate_dir"
            return 1
        fi
        "$server" --validate-config --user=mysql --datadir="$validate_datadir" \
            >"$output_file" 2>&1 || command_status=$?
    else
        cp "$probe_file" "$output_file" || {
            rm -rf "$validate_dir"
            return 1
        }
        command_status=$probe_status
    fi
    if ! dbtune_lifecycle_validation_output_ok "$output_file"; then
        rm -rf "$validate_dir"
        dbtune_log error "$(dbtune_msg lifecycle_validation_invalid)"
        return 65
    fi
    if ((command_status != 0)) && ! dbtune_lifecycle_validation_has_tolerated_error "$output_file"; then
        rm -rf "$validate_dir"
        dbtune_log error "$(dbtune_msg lifecycle_validation_failed)"
        return 65
    fi
    if ((command_status != 0)); then
        dbtune_log warn "$(dbtune_printf lifecycle_validation_tolerated "$command_status")"
    fi
    rm -rf "$validate_dir"
}

dbtune_lifecycle_manifest_value() {
    local history=${1:-}
    local key=${2:-}

    awk -F '\t' -v wanted="$key" '$1 == wanted {sub(/^[^\t]*\t/, ""); print; exit}' "$history/manifest.tsv"
}

dbtune_lifecycle_cycle_id() {
    local history=${1:-}
    local cycle_id

    if [[ ${history%/*} != "$DBTUNE_STATE_DIR/apply" || ! ${history##*/} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ||
        ! -d $history || -L $history || ! -f $history/manifest.tsv || -L $history/manifest.tsv ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_history_identity_invalid "${history:-$(dbtune_msg core_value_empty)}")"
        return 65
    fi
    cycle_id=$(dbtune_lifecycle_manifest_value "$history" cycle_id)
    [[ -n $cycle_id ]] || cycle_id=${history##*/}
    if [[ $cycle_id != "${history##*/}" ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_cycle_id_mismatch "$history")"
        return 65
    fi
    printf '%s\n' "$cycle_id"
}

dbtune_lifecycle_resolve_restore_lineage() {
    local history=${1:-}
    local had_original original_hash original_backup source source_cycle_id source_history source_target source_hash snapshot_hash

    DBTUNE_LIFECYCLE_RESTORED_SOURCE=
    DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID=-
    DBTUNE_LIFECYCLE_RESTORED_HISTORY=-
    DBTUNE_LIFECYCLE_RESTORED_BACKUP=absent
    had_original=$(dbtune_lifecycle_manifest_value "$history" had_original)
    original_hash=$(dbtune_lifecycle_manifest_value "$history" original_hash)
    original_backup=$(dbtune_lifecycle_manifest_value "$history" original_backup)
    source=$(dbtune_lifecycle_manifest_value "$history" original_source)
    [[ $had_original =~ ^[01]$ ]] || return 65
    [[ -n $original_backup ]] || original_backup=$([[ $had_original == 1 ]] && printf original.cnf || printf absent)
    if [[ -z $source ]]; then
        source=$([[ $had_original == 1 ]] && printf legacy_backup || printf absent)
    fi
    if ((had_original == 1)); then
        [[ $original_backup == original.cnf ]] || return 65
        DBTUNE_LIFECYCLE_RESTORED_BACKUP="$history/original.cnf"
        [[ $original_hash =~ ^[0-9a-f]{64}$ && -f $DBTUNE_LIFECYCLE_RESTORED_BACKUP &&
            ! -L $DBTUNE_LIFECYCLE_RESTORED_BACKUP ]] || return 65
        [[ $(dbtune_sha256_file "$DBTUNE_LIFECYCLE_RESTORED_BACKUP") == "$original_hash" ]] || return 65
    elif [[ $original_hash != absent || $original_backup != absent ]]; then
        return 65
    fi
    case $source in
        apply_cycle)
            ((had_original == 1)) || return 65
            source_cycle_id=$(dbtune_lifecycle_manifest_value "$history" original_cycle_id)
            source_history=$(dbtune_lifecycle_manifest_value "$history" original_cycle_history)
            [[ -n $source_cycle_id && $source_history != "$history" ]] || return 65
            [[ $(dbtune_lifecycle_cycle_id "$source_history") == "$source_cycle_id" ]] || return 65
            source_target=$(dbtune_lifecycle_manifest_value "$source_history" target)
            source_hash=$(dbtune_lifecycle_manifest_value "$source_history" proposal_hash)
            [[ -f $source_history/proposed.cnf && ! -L $source_history/proposed.cnf ]] || return 65
            snapshot_hash=$(dbtune_sha256_file "$source_history/proposed.cnf") || return
            if [[ $source_target != "$(dbtune_lifecycle_manifest_value "$history" target)" ||
                $source_hash != "$original_hash" || $snapshot_hash != "$original_hash" ]]; then
                dbtune_log error "$(dbtune_msg lifecycle_source_cycle_mismatch)"
                return 65
            fi
            DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID=$source_cycle_id
            DBTUNE_LIFECYCLE_RESTORED_HISTORY=$source_history
            ;;
        external|legacy_backup)
            ((had_original == 1)) || return 65
            ;;
        absent)
            ((had_original == 0)) || return 65
            ;;
        *)
            dbtune_log error "$(dbtune_printf lifecycle_backup_source_unknown "$source")"
            return 65
            ;;
    esac
    DBTUNE_LIFECYCLE_RESTORED_SOURCE=$source
}

dbtune_lifecycle_restore_config() {
    local history=${1:-}
    local target manifest_directory_identity manifest_parent_identities had_original original_hash removed directory temporary
    local topology directory_identity target_identity target_hash backup_hash proposal_hash status

    target=$(dbtune_lifecycle_manifest_value "$history" target) || return 1
    manifest_directory_identity=$(dbtune_lifecycle_manifest_value "$history" directory_identity 2>/dev/null || true)
    had_original=$(dbtune_lifecycle_manifest_value "$history" had_original) || return 1
    [[ -n $target && $had_original =~ ^[01]$ ]] || return 65
    dbtune_lifecycle_validate_target_path "$target" any "$manifest_directory_identity" || return
    manifest_parent_identities=$(dbtune_lifecycle_manifest_value "$history" parent_identities 2>/dev/null || true)
    if [[ -n $manifest_parent_identities && $DBTUNE_LIFECYCLE_PARENT_IDENTITIES != "$manifest_parent_identities" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_parent_replaced_apply)"
        return 65
    fi
    [[ -n $manifest_parent_identities ]] || manifest_parent_identities=$DBTUNE_LIFECYCLE_PARENT_IDENTITIES
    topology=$DBTUNE_LIFECYCLE_TARGET_TOPOLOGY
    directory_identity=$DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY
    target_identity=$DBTUNE_LIFECYCLE_TARGET_IDENTITY
    target_hash=$DBTUNE_LIFECYCLE_TARGET_HASH
    original_hash=$(dbtune_lifecycle_manifest_value "$history" original_hash 2>/dev/null || true)
    proposal_hash=$(dbtune_lifecycle_manifest_value "$history" proposal_hash 2>/dev/null || true)
    if [[ $topology == regular ]]; then
        if [[ $target_hash != "$proposal_hash" ]] &&
            { ((had_original == 0)) || [[ $target_hash != "$original_hash" ]]; }; then
            dbtune_log error "$(dbtune_msg lifecycle_target_snapshot_mismatch)"
            return 65
        fi
    elif ((had_original == 1)); then
        dbtune_log error "$(dbtune_msg lifecycle_original_target_missing)"
        return 65
    fi
    if ((had_original == 1)); then
        if [[ ! -f $history/original.cnf || -L $history/original.cnf ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_original_config_missing "$history")"
            return 66
        fi
        backup_hash=$(dbtune_sha256_file "$history/original.cnf") || return
        if [[ -n $original_hash && $original_hash != "$backup_hash" ]]; then
            dbtune_log error "$(dbtune_msg lifecycle_original_config_hash_invalid)"
            return 65
        fi
    fi
    removed="$history/rollback-deployed.cnf"
    if [[ -e $removed || -L $removed ]]; then
        removed="$history/rollback-deployed-$(date -u '+%Y%m%dT%H%M%SZ').cnf"
    fi
    if ((had_original == 0)); then
        if [[ $topology == regular ]]; then
            cp -p "$target" "$removed" || return 1
            if [[ $(dbtune_sha256_file "$removed") != "$target_hash" ]]; then
                rm -f "$removed"
                return 65
            fi
        fi
        dbtune_lifecycle_publish_managed_config - "$target" "$topology" "$directory_identity" \
            "$target_identity" "$target_hash" "" "$manifest_parent_identities"
        return
    fi

    directory=${target%/*}
    temporary=$(mktemp "$directory/.99-zz-restore.tmp.XXXXXX") || return 1
    if ! command cat "$history/original.cnf" >"$temporary" || ! chown root:root "$temporary" || ! chmod 0644 "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if [[ $topology == regular ]]; then
        if ! cp -p "$target" "$removed"; then
            rm -f "$temporary"
            return 1
        fi
        if [[ $(dbtune_sha256_file "$removed") != "$target_hash" ]]; then
            rm -f "$temporary"
            return 65
        fi
    fi
    if dbtune_lifecycle_publish_managed_config "$temporary" "$target" "$topology" \
        "$directory_identity" "$target_identity" "$target_hash" "$backup_hash" \
        "$manifest_parent_identities"; then
        :
    else
        status=$?
        rm -f "$temporary"
        return "$status"
    fi
    dbtune_lifecycle_validate_target_path "$target" regular "$directory_identity" || return
    if [[ $DBTUNE_LIFECYCLE_TARGET_HASH != "$backup_hash" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_restored_config_mismatch)"
        return 65
    fi
}

dbtune_lifecycle_capture_memory() {
    local output

    output=$(free -m) || return 1
    awk '
        /^Mem:/ {print "mem_total_mb\t" $2; print "mem_used_mb\t" $3; print "mem_available_mb\t" $7}
        /^Swap:/ {print "swap_total_mb\t" $2; print "swap_used_mb\t" $3; print "swap_free_mb\t" $4}
    ' <<<"$output"
}

dbtune_lifecycle_capture_status() {
    dbtune_sql "SELECT LOWER(VARIABLE_NAME), VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME IN ('UPTIME','QUESTIONS','COM_SELECT','INNODB_BUFFER_POOL_READS','INNODB_BUFFER_POOL_READ_REQUESTS','INNODB_DATA_READ','INNODB_BUFFER_POOL_PAGES_DATA','INNODB_BUFFER_POOL_PAGES_FREE','INNODB_BUFFER_POOL_WAIT_FREE','INNODB_LOG_WAITS','CREATED_TMP_DISK_TABLES','CREATED_TMP_TABLES','HANDLER_READ_RND_NEXT','QCACHE_HITS','MAX_USED_CONNECTIONS','SLOW_QUERIES','ABORTED_CONNECTS') ORDER BY VARIABLE_NAME"
}

dbtune_lifecycle_capture_baseline() {
    local history=${1:-}
    local status memory

    status=$(dbtune_lifecycle_capture_status) || return 1
    memory=$(dbtune_lifecycle_capture_memory) || return 1
    [[ -n $status && -n $memory ]] || return 1
    printf '%s\n' "$status" | dbtune_atomic_write "$history/baseline-status.tsv" 600 || return 1
    printf '%s\n' "$memory" | dbtune_atomic_write "$history/baseline-memory.tsv" 600 || return 1
}

dbtune_lifecycle_publish_current() {
    local history=${1:-}
    local current_file

    current_file=$(dbtune_lifecycle_current_file)
    printf '%s\n' "$history" | dbtune_atomic_write "$current_file" 600
}

dbtune_lifecycle_publish_rollback() {
    local history=${1:-}
    local start_status=${2:-0}
    local restart_required=${3:-0}
    local cycle_id record

    cycle_id=$(dbtune_lifecycle_cycle_id "$history") || return
    record="$history/ROLLBACK_COMPLETED.tsv"
    if [[ -e $record || -L $record ]]; then
        dbtune_lifecycle_read_rollback_completion "$history" || return
    else
        {
            printf 'schema\t1\n'
            printf 'rolled_back_cycle_id\t%s\n' "$cycle_id"
            printf 'rolled_back_history\t%s\n' "$history"
            printf 'restored_source\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_SOURCE"
            printf 'restored_cycle_id\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID"
            printf 'restored_history\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_HISTORY"
            printf 'restored_backup\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_BACKUP"
            printf 'restored_hash\t%s\n' "$DBTUNE_ROLLBACK_INTENT_RESTORED_HASH"
            printf 'service_start_status\t%s\n' "$start_status"
            printf 'restart_required\t%s\n' "$restart_required"
            printf 'created_at\t%s\n' "$DBTUNE_ROLLBACK_INTENT_CREATED_AT"
        } | dbtune_atomic_write "$record" 600 || return 1
        dbtune_lifecycle_read_rollback_completion "$history" || return
    fi
    printf '%s\n' "$history" | dbtune_atomic_write "$(dbtune_lifecycle_last_rollback_file)" 600
}

dbtune_lifecycle_publish_rollback_intent() {
    local history=${1:-}
    local previous_state=${2:-}
    local previous_current=${3:-}
    local intent cycle_id proposal_hash restored_hash

    dbtune_state_is_valid "$previous_state" || return 65
    [[ $previous_state != collecting && $previous_state != rolled_back ]] || return 65
    [[ $previous_current == "$history" ]] || return 65
    cycle_id=$(dbtune_lifecycle_cycle_id "$history") || return
    proposal_hash=$(dbtune_lifecycle_manifest_value "$history" proposal_hash)
    restored_hash=$(dbtune_lifecycle_manifest_value "$history" original_hash)
    [[ $proposal_hash =~ ^[0-9a-f]{64}$ ]] || return 65
    [[ $restored_hash == absent || $restored_hash =~ ^[0-9a-f]{64}$ ]] || return 65
    intent=$(dbtune_lifecycle_rollback_intent_file)
    [[ ! -e $intent && ! -L $intent ]] || return 65
    {
        printf 'schema\t1\n'
        printf 'history\t%s\n' "$history"
        printf 'cycle_id\t%s\n' "$cycle_id"
        printf 'previous_state\t%s\n' "$previous_state"
        printf 'previous_current\t%s\n' "$previous_current"
        printf 'proposal_hash\t%s\n' "$proposal_hash"
        printf 'restored_source\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_SOURCE"
        printf 'restored_cycle_id\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID"
        printf 'restored_history\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_HISTORY"
        printf 'restored_backup\t%s\n' "$DBTUNE_LIFECYCLE_RESTORED_BACKUP"
        printf 'restored_hash\t%s\n' "$restored_hash"
        printf 'created_at\t%s\n' "$(dbtune_now)"
    } | dbtune_atomic_write "$intent" 600 || return 1
    dbtune_lifecycle_sync
}

dbtune_lifecycle_read_rollback_intent() {
    local intent actual_cycle actual_proposal actual_restored

    intent=$(dbtune_lifecycle_rollback_intent_file)
    [[ -f $intent && ! -L $intent ]] || return 66
    if ! awk -F '\t' '
        NF != 2 || seen[$1]++ { bad=1; next }
        $1 == "schema" { schema=$2; next }
        $1 == "history" { history=$2; next }
        $1 == "cycle_id" { cycle=$2; next }
        $1 == "previous_state" { state=$2; next }
        $1 == "previous_current" { current=$2; next }
        $1 == "proposal_hash" { proposal=$2; next }
        $1 == "restored_source" { source=$2; next }
        $1 == "restored_cycle_id" { restored_cycle=$2; next }
        $1 == "restored_history" { restored_history=$2; next }
        $1 == "restored_backup" { backup=$2; next }
        $1 == "restored_hash" { restored_hash=$2; next }
        $1 == "created_at" { created=$2; next }
        { bad=1 }
        END {
            timestamp="^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
            hash="^[0-9a-f]{64}$"
            exit (bad || length(seen) != 12 || schema != "1" || history == "" || cycle == "" ||
                state == "" || current == "" || proposal !~ hash || source == "" || restored_cycle == "" ||
                restored_history == "" || backup == "" || (restored_hash != "absent" && restored_hash !~ hash) ||
                created !~ timestamp)
        }
    ' "$intent"; then
        dbtune_log error "$(dbtune_printf lifecycle_rollback_intent_invalid "$intent")"
        return 65
    fi
    DBTUNE_ROLLBACK_INTENT_HISTORY=$(dbtune_manifest_value "$intent" history) || return 65
    DBTUNE_ROLLBACK_INTENT_CYCLE_ID=$(dbtune_manifest_value "$intent" cycle_id) || return 65
    DBTUNE_ROLLBACK_INTENT_PREVIOUS_STATE=$(dbtune_manifest_value "$intent" previous_state) || return 65
    DBTUNE_ROLLBACK_INTENT_PREVIOUS_CURRENT=$(dbtune_manifest_value "$intent" previous_current) || return 65
    DBTUNE_ROLLBACK_INTENT_PROPOSAL_HASH=$(dbtune_manifest_value "$intent" proposal_hash) || return 65
    DBTUNE_ROLLBACK_INTENT_RESTORED_SOURCE=$(dbtune_manifest_value "$intent" restored_source) || return 65
    DBTUNE_ROLLBACK_INTENT_RESTORED_CYCLE_ID=$(dbtune_manifest_value "$intent" restored_cycle_id) || return 65
    DBTUNE_ROLLBACK_INTENT_RESTORED_HISTORY=$(dbtune_manifest_value "$intent" restored_history) || return 65
    DBTUNE_ROLLBACK_INTENT_RESTORED_BACKUP=$(dbtune_manifest_value "$intent" restored_backup) || return 65
    DBTUNE_ROLLBACK_INTENT_RESTORED_HASH=$(dbtune_manifest_value "$intent" restored_hash) || return 65
    DBTUNE_ROLLBACK_INTENT_CREATED_AT=$(dbtune_manifest_value "$intent" created_at) || return 65
    dbtune_state_is_valid "$DBTUNE_ROLLBACK_INTENT_PREVIOUS_STATE" || return 65
    [[ $DBTUNE_ROLLBACK_INTENT_PREVIOUS_STATE != collecting &&
        $DBTUNE_ROLLBACK_INTENT_PREVIOUS_STATE != rolled_back ]] || return 65
    [[ $DBTUNE_ROLLBACK_INTENT_PREVIOUS_CURRENT == "$DBTUNE_ROLLBACK_INTENT_HISTORY" ]] || return 65
    actual_cycle=$(dbtune_lifecycle_cycle_id "$DBTUNE_ROLLBACK_INTENT_HISTORY") || return
    actual_proposal=$(dbtune_lifecycle_manifest_value "$DBTUNE_ROLLBACK_INTENT_HISTORY" proposal_hash)
    actual_restored=$(dbtune_lifecycle_manifest_value "$DBTUNE_ROLLBACK_INTENT_HISTORY" original_hash)
    [[ $actual_cycle == "$DBTUNE_ROLLBACK_INTENT_CYCLE_ID" &&
        $actual_proposal == "$DBTUNE_ROLLBACK_INTENT_PROPOSAL_HASH" &&
        $actual_restored == "$DBTUNE_ROLLBACK_INTENT_RESTORED_HASH" ]] || return 65
    [[ -f $DBTUNE_ROLLBACK_INTENT_HISTORY/proposed.cnf &&
        ! -L $DBTUNE_ROLLBACK_INTENT_HISTORY/proposed.cnf &&
        $(dbtune_sha256_file "$DBTUNE_ROLLBACK_INTENT_HISTORY/proposed.cnf") == "$actual_proposal" ]] || return 65
    dbtune_lifecycle_resolve_restore_lineage "$DBTUNE_ROLLBACK_INTENT_HISTORY" || return
    if [[ $DBTUNE_LIFECYCLE_RESTORED_SOURCE != "$DBTUNE_ROLLBACK_INTENT_RESTORED_SOURCE" ||
        $DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID != "$DBTUNE_ROLLBACK_INTENT_RESTORED_CYCLE_ID" ||
        $DBTUNE_LIFECYCLE_RESTORED_HISTORY != "$DBTUNE_ROLLBACK_INTENT_RESTORED_HISTORY" ||
        $DBTUNE_LIFECYCLE_RESTORED_BACKUP != "$DBTUNE_ROLLBACK_INTENT_RESTORED_BACKUP" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_rollback_lineage_mismatch)"
        return 65
    fi
}

dbtune_lifecycle_clear_rollback_intent() {
    local history=${1:-}
    local intent

    intent=$(dbtune_lifecycle_rollback_intent_file)
    [[ -e $intent || -L $intent ]] || return 0
    dbtune_lifecycle_read_rollback_intent || return
    [[ $DBTUNE_ROLLBACK_INTENT_HISTORY == "$history" ]] || return 65
    rm -f "$intent" || return 1
    dbtune_lifecycle_sync
}

dbtune_lifecycle_read_rollback_completion() {
    local history=${1:-}
    local record cycle_id

    record="$history/ROLLBACK_COMPLETED.tsv"
    [[ -f $record && ! -L $record ]] || return 66
    if ! awk -F '\t' '
        NF != 2 || seen[$1]++ { bad=1; next }
        $1 == "schema" { schema=$2; next }
        $1 == "rolled_back_cycle_id" { cycle=$2; next }
        $1 == "rolled_back_history" { history=$2; next }
        $1 == "restored_source" { source=$2; next }
        $1 == "restored_cycle_id" { restored_cycle=$2; next }
        $1 == "restored_history" { restored_history=$2; next }
        $1 == "restored_backup" { backup=$2; next }
        $1 == "restored_hash" { hash=$2; next }
        $1 == "service_start_status" { status=$2; next }
        $1 == "restart_required" { restart=$2; next }
        $1 == "created_at" { created=$2; next }
        { bad=1 }
        END {
            timestamp="^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
            exit (bad || length(seen) != 11 || schema != "1" || cycle == "" || history == "" ||
                source == "" || restored_cycle == "" || restored_history == "" || backup == "" ||
                hash == "" || status !~ /^[0-9]+$/ || restart !~ /^[01]$/ || created !~ timestamp)
        }
    ' "$record"; then
        dbtune_log error "$(dbtune_printf lifecycle_rollback_completion_invalid "$record")"
        return 65
    fi
    cycle_id=$(dbtune_lifecycle_cycle_id "$history") || return
    DBTUNE_ROLLBACK_COMPLETION_START_STATUS=$(dbtune_manifest_value "$record" service_start_status) || return 65
    DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED=$(dbtune_manifest_value "$record" restart_required) || return 65
    [[ $DBTUNE_ROLLBACK_COMPLETION_START_STATUS =~ ^[0-9]+$ &&
        $DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED =~ ^[01]$ ]] || return 65
    if [[ $(dbtune_manifest_value "$record" schema) != 1 ||
        $(dbtune_manifest_value "$record" rolled_back_cycle_id) != "$cycle_id" ||
        $(dbtune_manifest_value "$record" rolled_back_history) != "$history" ||
        $(dbtune_manifest_value "$record" restored_source) != "$DBTUNE_LIFECYCLE_RESTORED_SOURCE" ||
        $(dbtune_manifest_value "$record" restored_cycle_id) != "$DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID" ||
        $(dbtune_manifest_value "$record" restored_history) != "$DBTUNE_LIFECYCLE_RESTORED_HISTORY" ||
        $(dbtune_manifest_value "$record" restored_backup) != "$DBTUNE_LIFECYCLE_RESTORED_BACKUP" ||
        $(dbtune_manifest_value "$record" restored_hash) != "$DBTUNE_ROLLBACK_INTENT_RESTORED_HASH" ||
        $(dbtune_manifest_value "$record" created_at) != "$DBTUNE_ROLLBACK_INTENT_CREATED_AT" ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_rollback_completion_mismatch "$record")"
        return 65
    fi
}

dbtune_lifecycle_publish_intent() {
    local history=${1:-}
    local previous_state=${2:-}
    local previous_current=${3:-}
    local intent proposal_hash

    dbtune_state_is_valid "$previous_state" || return 65
    [[ ${history%/*} == "$DBTUNE_STATE_DIR/apply" && -d $history && ! -L $history ]] || return 65
    [[ -f $history/manifest.tsv && ! -L $history/manifest.tsv ]] || return 65
    if [[ -n $previous_current ]]; then
        if [[ ${previous_current%/*} != "$DBTUNE_STATE_DIR/apply" || ! -d $previous_current ||
            -L $previous_current || ! -f $previous_current/manifest.tsv || -L $previous_current/manifest.tsv ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_previous_pointer_unsafe "$previous_current")"
            return 65
        fi
    else
        previous_current=-
    fi
    proposal_hash=$(dbtune_lifecycle_manifest_value "$history" proposal_hash) || return 65
    [[ $proposal_hash =~ ^[0-9a-f]{64}$ ]] || return 65
    intent=$(dbtune_lifecycle_intent_file)
    {
        printf 'schema\t1\n'
        printf 'history\t%s\n' "$history"
        printf 'previous_state\t%s\n' "$previous_state"
        printf 'previous_current\t%s\n' "$previous_current"
        printf 'proposal_hash\t%s\n' "$proposal_hash"
        printf 'created_at\t%s\n' "$(dbtune_now)"
    } | dbtune_atomic_write "$intent" 600 || return 1
    dbtune_lifecycle_sync
}

dbtune_lifecycle_read_intent() {
    local intent manifest_hash snapshot_hash

    intent=$(dbtune_lifecycle_intent_file)
    [[ -f $intent && ! -L $intent ]] || return 66
    if ! awk -F '\t' '
        NF != 2 || seen[$1]++ { bad=1; next }
        $1 == "schema" { schema=$2; next }
        $1 == "history" { history=$2; next }
        $1 == "previous_state" { state=$2; next }
        $1 == "previous_current" { current=$2; next }
        $1 == "proposal_hash" { hash=$2; next }
        $1 == "created_at" { created=$2; next }
        { bad=1 }
        END {
            timestamp="^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
            exit (bad || length(seen) != 6 || schema != "1" || history == "" || state == "" ||
                current == "" || hash !~ /^[0-9a-f]{64}$/ || created !~ timestamp)
        }
    ' "$intent"; then
        dbtune_log error "$(dbtune_printf lifecycle_apply_intent_invalid "$intent")"
        return 65
    fi
    DBTUNE_LIFECYCLE_INTENT_HISTORY=$(dbtune_manifest_value "$intent" history) || return 65
    DBTUNE_LIFECYCLE_INTENT_PREVIOUS_STATE=$(dbtune_manifest_value "$intent" previous_state) || return 65
    DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT=$(dbtune_manifest_value "$intent" previous_current) || return 65
    DBTUNE_LIFECYCLE_INTENT_PROPOSAL_HASH=$(dbtune_manifest_value "$intent" proposal_hash) || return 65
    dbtune_state_is_valid "$DBTUNE_LIFECYCLE_INTENT_PREVIOUS_STATE" || return 65
    if [[ ${DBTUNE_LIFECYCLE_INTENT_HISTORY%/*} != "$DBTUNE_STATE_DIR/apply" ||
        ! -d $DBTUNE_LIFECYCLE_INTENT_HISTORY || -L $DBTUNE_LIFECYCLE_INTENT_HISTORY ||
        ! -f $DBTUNE_LIFECYCLE_INTENT_HISTORY/manifest.tsv || -L $DBTUNE_LIFECYCLE_INTENT_HISTORY/manifest.tsv ||
        ! -f $DBTUNE_LIFECYCLE_INTENT_HISTORY/proposed.cnf || -L $DBTUNE_LIFECYCLE_INTENT_HISTORY/proposed.cnf ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_apply_intent_history_invalid)"
        return 65
    fi
    if [[ $DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT != - ]] &&
        [[ ${DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT%/*} != "$DBTUNE_STATE_DIR/apply" ||
            ! -d $DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT || -L $DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT ||
            ! -f $DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT/manifest.tsv ||
            -L $DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT/manifest.tsv ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_apply_intent_pointer_invalid)"
        return 65
    fi
    manifest_hash=$(dbtune_lifecycle_manifest_value "$DBTUNE_LIFECYCLE_INTENT_HISTORY" proposal_hash) || return 65
    snapshot_hash=$(dbtune_sha256_file "$DBTUNE_LIFECYCLE_INTENT_HISTORY/proposed.cnf") || return
    if [[ $manifest_hash != "$DBTUNE_LIFECYCLE_INTENT_PROPOSAL_HASH" ||
        $snapshot_hash != "$DBTUNE_LIFECYCLE_INTENT_PROPOSAL_HASH" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_apply_intent_snapshot_mismatch)"
        return 65
    fi
}

dbtune_lifecycle_clear_intent() {
    local history=${1:-}
    local intent

    intent=$(dbtune_lifecycle_intent_file)
    [[ -e $intent || -L $intent ]] || return 0
    dbtune_lifecycle_read_intent || return
    [[ $DBTUNE_LIFECYCLE_INTENT_HISTORY == "$history" ]] || return 65
    rm -f "$intent" || return 1
    dbtune_lifecycle_sync
}

dbtune_lifecycle_read_current() {
    local current_file history

    current_file=$(dbtune_lifecycle_current_file)
    [[ -r $current_file ]] || {
        dbtune_log error "$(dbtune_printf lifecycle_current_missing "$current_file")"
        return 66
    }
    IFS= read -r history <"$current_file" || return 1
    if [[ $history != "$DBTUNE_STATE_DIR"/apply/* || ! -d $history || ! -r $history/manifest.tsv ]]; then
        dbtune_log error "$(dbtune_printf lifecycle_history_invalid "${history:-$(dbtune_msg core_value_empty)}")"
        return 65
    fi
    printf '%s\n' "$history"
}

dbtune_lifecycle_mark_recovery_required() {
    local history=${1:-}
    local phase=${2:-unknown}

    {
        printf 'phase\t%s\n' "$phase"
        printf 'created_at\t%s\n' "$(dbtune_now)"
        printf 'instructions\t%s/ROLLBACK.txt\n' "$history"
    } | dbtune_atomic_write "$history/RECOVERY_REQUIRED" 600 || true
    dbtune_lifecycle_publish_current "$history" || true
    dbtune_state_write recovery_required || true
    dbtune_event recovery_required phase "$phase" history "$history" || true
    dbtune_log error "$(dbtune_printf lifecycle_recovery_critical "$history")"
}

dbtune_lifecycle_restore_previous_pointer() {
    local previous_current=${1:-}

    if [[ -n $previous_current ]]; then
        dbtune_lifecycle_publish_current "$previous_current"
    else
        rm -f "$(dbtune_lifecycle_current_file)"
    fi
}

dbtune_lifecycle_mark_rollback_failed() {
    local history=${1:-}

    {
        printf 'created_at\t%s\n' "$(dbtune_now)"
        printf 'instructions\t%s/ROLLBACK.txt\n' "$history"
    } | dbtune_atomic_write "$history/ROLLBACK_FAILED" 600 || true
    dbtune_state_write rollback_failed || dbtune_state_write recovery_required || true
    dbtune_event rollback_failed history "$history" || true
    dbtune_log error "$(dbtune_printf lifecycle_rollback_failed "$history")"
}

dbtune_lifecycle_restore_rollback_target() {
    local history=$DBTUNE_ROLLBACK_INTENT_HISTORY
    local target directory_identity had_original

    target=$(dbtune_lifecycle_manifest_value "$history" target) || return 65
    directory_identity=$(dbtune_lifecycle_manifest_value "$history" directory_identity) || return 65
    had_original=$(dbtune_lifecycle_manifest_value "$history" had_original) || return 65
    dbtune_lifecycle_validate_target_path "$target" any "$directory_identity" || return
    if ((had_original == 1)) && [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == regular &&
        $DBTUNE_LIFECYCLE_TARGET_HASH == "$DBTUNE_ROLLBACK_INTENT_RESTORED_HASH" ]]; then
        return 0
    fi
    if ((had_original == 0)) && [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == absent ]]; then
        return 0
    fi
    if [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY != regular ||
        $DBTUNE_LIFECYCLE_TARGET_HASH != "$DBTUNE_ROLLBACK_INTENT_PROPOSAL_HASH" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_rollback_target_mismatch)"
        return 65
    fi
    dbtune_lifecycle_restore_config "$history" || return
    dbtune_lifecycle_validate_target_path "$target" any "$directory_identity" || return
    if ((had_original == 1)); then
        [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == regular &&
            $DBTUNE_LIFECYCLE_TARGET_HASH == "$DBTUNE_ROLLBACK_INTENT_RESTORED_HASH" ]] || return 65
    else
        [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == absent ]] || return 65
    fi
}

dbtune_lifecycle_prepare_rollback_service() {
    local history=${1:-}
    local systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}

    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || systemctl_command=$(dbtune_runtime_command_path systemctl) || return

    DBTUNE_ROLLBACK_COMPLETION_START_STATUS=0
    DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED=0
    rm -f "$history/SERVICE_START_FAILED"
    if "$systemctl_command" is-active --quiet mariadb; then
        DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED=1
        dbtune_printf lifecycle_rollback_restart_required
        printf '%s\n' "$(dbtune_now)" | dbtune_atomic_write "$history/RESTART_REQUIRED" 600 || return 1
    else
        "$systemctl_command" start mariadb || DBTUNE_ROLLBACK_COMPLETION_START_STATUS=$?
        rm -f "$history/RESTART_REQUIRED"
        if ((DBTUNE_ROLLBACK_COMPLETION_START_STATUS != 0)); then
            printf '%s\n' "$(dbtune_now)" | dbtune_atomic_write "$history/SERVICE_START_FAILED" 600 || true
        fi
    fi
}

dbtune_lifecycle_record_rollback_event() {
    local history=${1:-}
    local marker="$history/ROLLBACK_EVENT_RECORDED"

    [[ -e $marker || -L $marker ]] && return 0
    if dbtune_event rollback_completed history "$history" cycle_id "$DBTUNE_ROLLBACK_INTENT_CYCLE_ID" \
        restored_source "$DBTUNE_LIFECYCLE_RESTORED_SOURCE" restored_cycle_id "$DBTUNE_LIFECYCLE_RESTORED_CYCLE_ID" \
        restored_history "$DBTUNE_LIFECYCLE_RESTORED_HISTORY" restored_backup "$DBTUNE_LIFECYCLE_RESTORED_BACKUP" \
        service_start_status "$DBTUNE_ROLLBACK_COMPLETION_START_STATUS" \
        restart_required "$(dbtune_lifecycle_bool "$DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED")"; then
        printf '%s\n' "$(dbtune_now)" | dbtune_atomic_write "$marker" 600 || return 1
    fi
}

dbtune_lifecycle_continue_rollback() {
    local report_service_status=${1:-0}
    local history=$DBTUNE_ROLLBACK_INTENT_HISTORY
    local current desired_current state

    if ! dbtune_lifecycle_restore_rollback_target; then
        dbtune_lifecycle_mark_rollback_failed "$history"
        dbtune_lifecycle_sync || true
        return 1
    fi
    rm -f "$history/RECOVERY_REQUIRED" "$history/ROLLBACK_FAILED"
    dbtune_lifecycle_sync || return 1
    dbtune_lifecycle_fault_inject after_rollback_config || return

    if [[ -e $history/ROLLBACK_COMPLETED.tsv || -L $history/ROLLBACK_COMPLETED.tsv ]]; then
        dbtune_lifecycle_read_rollback_completion "$history" || return
        printf '%s\n' "$history" | dbtune_atomic_write "$(dbtune_lifecycle_last_rollback_file)" 600 || return 1
    else
        dbtune_lifecycle_prepare_rollback_service "$history" || return
        dbtune_lifecycle_publish_rollback "$history" "$DBTUNE_ROLLBACK_COMPLETION_START_STATUS" \
            "$DBTUNE_ROLLBACK_COMPLETION_RESTART_REQUIRED" || return
    fi
    dbtune_lifecycle_sync || return 1
    dbtune_lifecycle_fault_inject after_rollback_metadata || return

    desired_current=$history
    if [[ $DBTUNE_LIFECYCLE_RESTORED_HISTORY != - ]]; then
        desired_current=$DBTUNE_LIFECYCLE_RESTORED_HISTORY
    fi
    current=$(dbtune_lifecycle_read_current) || return
    if [[ $current == "$history" ]]; then
        dbtune_lifecycle_publish_current "$desired_current" || return
    elif [[ $current != "$desired_current" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_rollback_pointer_mismatch)"
        return 65
    fi
    dbtune_lifecycle_sync || return 1
    dbtune_lifecycle_fault_inject after_rollback_current || return

    state=$(dbtune_state_read) || return
    if [[ $state != rolled_back ]]; then
        if [[ $state != "$DBTUNE_ROLLBACK_INTENT_PREVIOUS_STATE" &&
            $state != rollback_failed && $state != recovery_required ]]; then
            dbtune_log error "$(dbtune_printf lifecycle_rollback_state_mismatch "$state")"
            return 65
        fi
        dbtune_state_transition rolled_back || dbtune_state_write rolled_back || return
    fi
    dbtune_lifecycle_sync || return 1
    dbtune_lifecycle_fault_inject after_rollback_state || return

    if [[ -e $(dbtune_lifecycle_intent_file) || -L $(dbtune_lifecycle_intent_file) ]]; then
        dbtune_lifecycle_read_intent || return
        [[ $DBTUNE_LIFECYCLE_INTENT_HISTORY == "$history" ]] || return 65
        dbtune_lifecycle_clear_intent "$history" || return
    fi
    dbtune_lifecycle_record_rollback_event "$history" || return
    dbtune_lifecycle_sync || return 1
    dbtune_lifecycle_clear_rollback_intent "$history" || return
    if ((DBTUNE_ROLLBACK_COMPLETION_START_STATUS != 0)); then
        dbtune_log error "$(dbtune_msg lifecycle_service_start_failed)"
        ((report_service_status == 0)) || return "$DBTUNE_ROLLBACK_COMPLETION_START_STATUS"
    fi
}

dbtune_lifecycle_recover_rollback_if_needed() {
    local intent

    intent=$(dbtune_lifecycle_rollback_intent_file)
    [[ -e $intent || -L $intent ]] || return 0
    dbtune_lifecycle_read_rollback_intent || return
    dbtune_lifecycle_continue_rollback 0
}

dbtune_lifecycle_recover_failed_apply() {
    local history=${1:-}
    local previous_state=${2:-}
    local previous_current=${3:-}
    local phase=${4:-unknown}

    if ! dbtune_lifecycle_restore_config "$history"; then
        dbtune_lifecycle_mark_recovery_required "$history" "$phase"
        return 1
    fi
    rm -f "$history/RECOVERY_REQUIRED" "$history/ROLLBACK_FAILED"
    if ! dbtune_lifecycle_restore_previous_pointer "$previous_current" || ! dbtune_state_write "$previous_state"; then
        dbtune_lifecycle_mark_recovery_required "$history" "${phase}_bookkeeping"
        return 1
    fi
    if ! dbtune_lifecycle_sync || ! dbtune_lifecycle_clear_intent "$history"; then
        dbtune_lifecycle_mark_recovery_required "$history" "${phase}_journal"
        return 1
    fi
    dbtune_event apply_restored phase "$phase" history "$history" || true
}

dbtune_lifecycle_recover_apply_if_needed() {
    local intent history previous_state previous_current proposal_hash
    local target directory_identity had_original original_hash state current=''
    local original_matches=0 proposal_matches=0

    intent=$(dbtune_lifecycle_intent_file)
    [[ -e $intent || -L $intent ]] || return 0
    dbtune_lifecycle_read_intent || return
    history=$DBTUNE_LIFECYCLE_INTENT_HISTORY
    previous_state=$DBTUNE_LIFECYCLE_INTENT_PREVIOUS_STATE
    previous_current=$DBTUNE_LIFECYCLE_INTENT_PREVIOUS_CURRENT
    proposal_hash=$DBTUNE_LIFECYCLE_INTENT_PROPOSAL_HASH
    [[ $previous_current != - ]] || previous_current=''

    target=$(dbtune_lifecycle_manifest_value "$history" target) || return 65
    directory_identity=$(dbtune_lifecycle_manifest_value "$history" directory_identity) || return 65
    had_original=$(dbtune_lifecycle_manifest_value "$history" had_original) || return 65
    original_hash=$(dbtune_lifecycle_manifest_value "$history" original_hash) || return 65
    [[ $had_original =~ ^[01]$ ]] || return 65
    dbtune_lifecycle_validate_target_path "$target" any "$directory_identity" || return
    if ((had_original == 1)) && [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == regular &&
        $DBTUNE_LIFECYCLE_TARGET_HASH == "$original_hash" ]]; then
        original_matches=1
    elif ((had_original == 0)) && [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == absent ]]; then
        original_matches=1
    fi
    if [[ $DBTUNE_LIFECYCLE_TARGET_TOPOLOGY == regular &&
        $DBTUNE_LIFECYCLE_TARGET_HASH == "$proposal_hash" ]]; then
        proposal_matches=1
    fi

    state=$(dbtune_state_read) || return
    if [[ -r $(dbtune_lifecycle_current_file) ]]; then
        IFS= read -r current <"$(dbtune_lifecycle_current_file)" || current=''
    fi
    if ((proposal_matches == 1)) && [[ $state == applied && $current == "$history" ]]; then
        dbtune_lifecycle_sync || return 1
        dbtune_lifecycle_clear_intent "$history" || return
        dbtune_event apply_recovered action finalized history "$history" || true
        return 0
    fi
    if [[ $state == recovery_required && $current == "$history" ]]; then
        return 0
    fi
    if ((original_matches == 0 && proposal_matches == 0)); then
        dbtune_lifecycle_mark_recovery_required "$history" interrupted_apply_target_changed
        dbtune_lifecycle_sync || true
        return 1
    fi
    if ((proposal_matches == 1)) && ! dbtune_lifecycle_restore_config "$history"; then
        dbtune_lifecycle_mark_recovery_required "$history" interrupted_apply
        dbtune_lifecycle_sync || true
        return 1
    fi
    if ! dbtune_lifecycle_restore_previous_pointer "$previous_current" || ! dbtune_state_write "$previous_state" ||
        ! dbtune_lifecycle_sync || ! dbtune_lifecycle_clear_intent "$history"; then
        dbtune_lifecycle_mark_recovery_required "$history" interrupted_apply_bookkeeping
        dbtune_lifecycle_sync || true
        return 1
    fi
    dbtune_event apply_recovered action restored history "$history" || true
}

dbtune_lifecycle_recover_if_needed() {
    dbtune_lifecycle_recover_rollback_if_needed || return
    dbtune_lifecycle_recover_apply_if_needed
}

dbtune_lifecycle_mark_unmeasured() {
    local history=${1:-}
    local report="$DBTUNE_STATE_DIR/report.md"
    local stamp

    stamp=$(dbtune_msg lifecycle_without_measurements) || return

    {
        dbtune_printf lifecycle_apply_report_title
        dbtune_printf lifecycle_apply_report_forced "$stamp"
    } | dbtune_atomic_write "$history/apply-report.md" 600 || return 1
    if [[ -f $report ]]; then
        dbtune_printf lifecycle_report_forced_note "$stamp" >>"$report" || return 1
    fi
    dbtune_event apply_force measurement without_measurements ui_lang "$DBTUNE_I18N_LANGUAGE" || true
}

dbtune_lifecycle_print_runcloud_instructions() {
    local history=${1:-}
    local target=${2:-}

    dbtune_printf lifecycle_config_written "$target"
    dbtune_printf lifecycle_runcloud_restart
    dbtune_printf lifecycle_redo_start_delay
    dbtune_printf lifecycle_run_verify
    dbtune_printf lifecycle_emergency_commands "$history"
}

dbtune_lifecycle_after_manifest_check() {
    return 0
}

dbtune_lifecycle_after_strict_parse() {
    return 0
}

dbtune_lifecycle_before_history_copy() {
    return 0
}

dbtune_lifecycle_after_records_hash() {
    return 0
}

dbtune_lifecycle_before_target_copy() {
    return 0
}

dbtune_lifecycle_before_publish() {
    return 0
}

dbtune_lifecycle_apply_snapshot() {
    local restart=${1:-0}
    local force=${2:-0}
    local proposal=${3:-}
    local records=${4:-}
    local backup_evidence=${5:-}
    local target history had_original previous_state previous_current='' unmeasured=0
    local target_topology directory_identity target_identity target_hash parent_identities
    local systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}
    local status=0

    [[ $DBTUNE_ARTIFACT_PROFILE != production ]] || systemctl_command=$(dbtune_runtime_command_path systemctl) || return

    dbtune_lifecycle_has_measurement || unmeasured=1
    if ((force == 1)); then
        dbtune_lifecycle_confirm_force || return
    fi
    dbtune_lifecycle_check_backup "$backup_evidence" || return
    dbtune_lifecycle_check_time_window "$force" || return
    dbtune_lifecycle_require_publisher || return

    target=$(dbtune_lifecycle_target)
    dbtune_lifecycle_validate_target_path "$target" || return
    target_topology=$DBTUNE_LIFECYCLE_TARGET_TOPOLOGY
    directory_identity=$DBTUNE_LIFECYCLE_DIRECTORY_IDENTITY
    target_identity=$DBTUNE_LIFECYCLE_TARGET_IDENTITY
    target_hash=$DBTUNE_LIFECYCLE_TARGET_HASH
    parent_identities=$DBTUNE_LIFECYCLE_PARENT_IDENTITIES
    dbtune_init_state_dir || return 1
    dbtune_lifecycle_require_snapshot_hash "$proposal" "$DBTUNE_APPLY_SNAPSHOT_HASH" || return
    dbtune_lifecycle_validate_variable_names "$records" "$DBTUNE_APPLY_RECORDS_HASH" || return
    dbtune_lifecycle_reject_galera || return
    dbtune_lifecycle_reject_mydumper || return
    if [[ -r $DBTUNE_STATE_DIR/analysis.tsv ]]; then
        dbtune_lifecycle_reject_critical_analysis || return
    fi

    history=$(dbtune_lifecycle_new_history) || return
    previous_state=$(dbtune_state_read) || return
    if [[ -r $(dbtune_lifecycle_current_file) ]]; then
        IFS= read -r previous_current <"$(dbtune_lifecycle_current_file)" || previous_current=''
    fi
    if had_original=$(dbtune_lifecycle_prepare_history "$history" "$target" "$proposal" "$backup_evidence" \
        "$target_topology" "$directory_identity" "$target_identity" "$target_hash" \
        "$parent_identities" "$previous_current" "$DBTUNE_APPLY_SNAPSHOT_HASH" \
        "$DBTUNE_APPLY_RECORDS_HASH" "$DBTUNE_APPLY_RECORD_COUNT"); then
        :
    else
        status=$?
        dbtune_lifecycle_discard_uncommitted_history "$history" || return
        return "$status"
    fi
    dbtune_lifecycle_capture_baseline "$history" || {
        dbtune_log error "$(dbtune_msg lifecycle_baseline_failed)"
        return 1
    }
    dbtune_lifecycle_publish_intent "$history" "$previous_state" "$previous_current" || return
    dbtune_lifecycle_fault_inject after_intent || return
    if dbtune_lifecycle_install_config "$proposal" "$target" "$target_topology" \
        "$directory_identity" "$target_identity" "$target_hash" "$parent_identities" \
        "$DBTUNE_APPLY_SNAPSHOT_HASH" "$DBTUNE_APPLY_RECORDS_HASH" "$DBTUNE_APPLY_RECORD_COUNT"; then
        :
    else
        status=$?
        dbtune_log error "$(dbtune_msg lifecycle_atomic_write_failed)"
        dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" install || true
        return "$status"
    fi
    dbtune_lifecycle_fault_inject after_config || return
    if ! dbtune_lifecycle_validate_target_path "$target" regular "$directory_identity" ||
        [[ $DBTUNE_LIFECYCLE_TARGET_HASH != "$DBTUNE_APPLY_SNAPSHOT_HASH" ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_final_check_failed)"
        dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" publish || true
        return 65
    fi
    if ! dbtune_lifecycle_validate_config; then
        dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" validation || true
        dbtune_event apply_validation_failed target "$target" history "$history" || true
        return 65
    fi

    if ((force == 1 && unmeasured == 1)); then
        if ! dbtune_lifecycle_mark_unmeasured "$history"; then
            dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" force_report || true
            return 1
        fi
    fi
    if ! dbtune_lifecycle_publish_current "$history"; then
        dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" current_publish || true
        return 1
    fi
    dbtune_lifecycle_fault_inject after_current || return
    if [[ $previous_state == audited ]]; then
        dbtune_state_write applied || {
            dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" state_commit || true
            return 1
        }
        dbtune_event state_transition from "$previous_state" to applied || true
    elif ! dbtune_state_transition applied; then
        dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" state_commit || true
        return 1
    fi
    dbtune_lifecycle_fault_inject after_state || return
    if ! dbtune_lifecycle_sync || ! dbtune_lifecycle_clear_intent "$history"; then
        dbtune_log error "$(dbtune_msg lifecycle_intent_finalize_failed)"
        return 1
    fi
    if ((restart == 1)); then
        if ! "$systemctl_command" restart mariadb || ! "$systemctl_command" is-active --quiet mariadb; then
            dbtune_log error "$(dbtune_msg lifecycle_restart_failed)"
            if dbtune_lifecycle_recover_failed_apply "$history" "$previous_state" "$previous_current" restart; then
                if ! "$systemctl_command" start mariadb; then
                    dbtune_lifecycle_mark_recovery_required "$history" service_start
                fi
            fi
            dbtune_event apply_restart_failed target "$target" history "$history" || true
            return 1
        fi
    else
        dbtune_lifecycle_print_runcloud_instructions "$history" "$target"
    fi
    dbtune_event apply_completed target "$target" history "$history" \
        restart "$(dbtune_lifecycle_bool "$restart")" force "$(dbtune_lifecycle_bool "$force")" \
        original "$(dbtune_lifecycle_bool "$had_original")" ui_lang "$DBTUNE_I18N_LANGUAGE" || true
}

cmd_apply() {
    local parsed restart force analysis proposal snapshot records backup_file backup_snapshot='' status=0

    parsed=$(dbtune_lifecycle_parse_args "$@") || return
    IFS=$'\t' read -r restart force <<<"$parsed"
    dbtune_init_state_dir || return 1
    analysis=$(dbtune_path analysis.tsv) || return
    if [[ -s $analysis ]]; then
        dbtune_analysis_validate_schema "$analysis" || return
    fi
    proposal=$(dbtune_lifecycle_proposal)
    snapshot=$(mktemp "$DBTUNE_STATE_DIR/.apply-proposal.XXXXXX") || return 1
    records=$(mktemp "$DBTUNE_STATE_DIR/.apply-records.XXXXXX") || {
        rm -f "$snapshot"
        return 1
    }
    if dbtune_lifecycle_prepare_proposal_snapshot "$proposal" "$snapshot" "$records"; then
        :
    else
        status=$?
        rm -f "$snapshot" "$records"
        return "$status"
    fi
    dbtune_lifecycle_after_strict_parse "$snapshot" "$records" || {
        status=$?
        rm -f "$snapshot" "$records"
        return "$status"
    }
    if ! dbtune_lifecycle_require_snapshot_hash "$snapshot" "$DBTUNE_APPLY_SNAPSHOT_HASH"; then
        rm -f "$snapshot" "$records"
        return 65
    fi
    backup_file=$(dbtune_backup_evidence_file)
    if dbtune_backup_evidence_validate "$backup_file"; then
        backup_snapshot=$(mktemp "$DBTUNE_STATE_DIR/.apply-backup-evidence.XXXXXX") || {
            rm -f "$snapshot" "$records"
            return 1
        }
        if ! cp "$backup_file" "$backup_snapshot" || ! chmod 400 "$backup_snapshot"; then
            rm -f "$snapshot" "$records" "$backup_snapshot"
            return 1
        fi
        if ! dbtune_backup_evidence_validate "$backup_snapshot"; then
            dbtune_lifecycle_log_backup_rejection
            rm -f "$snapshot" "$records" "$backup_snapshot"
            return 65
        fi
    elif [[ -e $backup_file || -L $backup_file ]]; then
        dbtune_lifecycle_log_backup_rejection
        rm -f "$snapshot" "$records"
        return 65
    fi
    if dbtune_lifecycle_check_apply_inputs "$force" "$snapshot" "$records"; then
        :
    else
        status=$?
        rm -f "$snapshot" "$records" "$backup_snapshot"
        return "$status"
    fi
    dbtune_lifecycle_after_manifest_check || {
        status=$?
        rm -f "$snapshot" "$records" "$backup_snapshot"
        return "$status"
    }
    dbtune_lifecycle_apply_snapshot "$restart" "$force" "$snapshot" "$records" "$backup_snapshot" || status=$?
    rm -f "$snapshot" "$records" "$backup_snapshot"
    return "$status"
}

dbtune_lifecycle_canonical_value() {
    local value=${1-}

    value=${value%$'\r'}
    value=${value#\'}
    value=${value%\'}
    value=${value#\"}
    value=${value%\"}
    case ${value^^} in
        ON|TRUE|YES) printf '1\n'; return ;;
        OFF|FALSE|NO) printf '0\n'; return ;;
    esac
    if [[ $value =~ ^([0-9]+)([KkMmGgTt])$ ]]; then
        awk -v number="${BASH_REMATCH[1]}" -v unit="${BASH_REMATCH[2]^^}" 'BEGIN {
            multiplier=1
            if (unit == "K") multiplier=1024
            if (unit == "M") multiplier=1024^2
            if (unit == "G") multiplier=1024^3
            if (unit == "T") multiplier=1024^4
            printf "%.0f\n", number*multiplier
        }'
        return
    fi
    if [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        awk -v number="$value" 'BEGIN {printf "%.12g\n", number}'
        return
    fi
    printf '%s\n' "${value,,}"
}

dbtune_lifecycle_verify_target() {
    local history=${1:-}
    local target expected_hash snapshot_hash actual_hash uid gid mode links
    local expected_uid=${DBTUNE_CONFIG_UID:-0}
    local expected_gid=${DBTUNE_CONFIG_GID:-0}
    local expected_mode=${DBTUNE_CONFIG_MODE:-644}

    target=$(dbtune_lifecycle_manifest_value "$history" target) || return 65
    expected_hash=$(dbtune_lifecycle_manifest_value "$history" proposal_hash) || return 65
    if [[ ! -f $target || -L $target ]]; then
        dbtune_printf lifecycle_target_missing "$target"
        return 1
    fi
    links=$(dbtune_lifecycle_file_links "$target") || return 1
    if [[ $links != 1 ]]; then
        dbtune_printf lifecycle_target_hardlink_error "$target" "$links"
        return 1
    fi
    read -r uid gid mode < <(dbtune_file_stat "$target") || return 1
    if [[ $uid != "$expected_uid" || $gid != "$expected_gid" || $mode != "$expected_mode" ]]; then
        dbtune_printf lifecycle_target_metadata_error \
            "$uid" "$gid" "$mode" "$expected_uid" "$expected_gid" "$expected_mode"
        return 1
    fi
    [[ $expected_hash =~ ^[0-9a-f]{64}$ && -f $history/proposed.cnf && ! -L $history/proposed.cnf ]] || return 65
    snapshot_hash=$(dbtune_sha256_file "$history/proposed.cnf") || return
    actual_hash=$(dbtune_sha256_file "$target") || return
    if [[ $snapshot_hash != "$expected_hash" || $actual_hash != "$expected_hash" ]]; then
        dbtune_printf lifecycle_target_hash_error
        return 1
    fi
    dbtune_printf lifecycle_target_ok "$target" "$uid" "$gid" "$mode" "$actual_hash"
}

dbtune_lifecycle_verify_values() {
    local proposal=${1:-}
    local names='' separator='' name expected actual output_file query
    local -A expected_values=() actual_values=()
    local failures=0 missing missing_upper

    missing=$(dbtune_msg lifecycle_value_missing) || return
    missing_upper=$(dbtune_msg lifecycle_value_missing_upper) || return

    while IFS=$'\t' read -r name expected; do
        [[ -n $name ]] || continue
        expected_values["$name"]=$expected
        names+="${separator}'$name'"
        separator=,
    done < <(dbtune_lifecycle_config_entries "$proposal")
    query="SELECT LOWER(VARIABLE_NAME), VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES WHERE LOWER(VARIABLE_NAME) IN ($names)"
    output_file=$(mktemp "$DBTUNE_STATE_DIR/.effective.XXXXXX") || return 1
    if ! dbtune_sql "$query" >"$output_file"; then
        rm -f "$output_file"
        return 69
    fi
    while IFS=$'\t' read -r name actual; do
        [[ -n $name ]] && actual_values["${name,,}"]=$actual
    done <"$output_file"
    rm -f "$output_file"

    for name in "${!expected_values[@]}"; do
        expected=$(dbtune_lifecycle_canonical_value "${expected_values[$name]}")
        actual=$(dbtune_lifecycle_canonical_value "${actual_values[$name]-$missing}")
        if [[ $expected != "$actual" ]]; then
            dbtune_printf lifecycle_value_mismatch "$name" "${expected_values[$name]}" "${actual_values[$name]-$missing_upper}"
            failures=1
        else
            dbtune_printf lifecycle_value_ok "$name" "${actual_values[$name]}"
        fi
    done
    ((failures == 0))
}

dbtune_lifecycle_tsv_value() {
    local file=${1:-}
    local key=${2:-}

    awk -F '\t' -v wanted="$key" 'tolower($1) == tolower(wanted) {print $2; exit}' "$file"
}

dbtune_lifecycle_verify_health() {
    local history=${1:-}
    local mode=${2:---post}
    local baseline_status="$history/baseline-status.tsv"
    local current_status="$history/verify-status.tsv"
    local current_memory="$history/verify-memory.tsv"
    local metric before value delta reset baseline_uptime current_uptime missing_upper
    local baseline_swap current_swap available total
    local status memory
    local failures=0

    missing_upper=$(dbtune_msg lifecycle_value_missing_upper) || return

    if [[ -r $history/post-status.tsv ]]; then
        baseline_status="$history/post-status.tsv"
    elif [[ $mode == --24h ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_verify_post_required)"
        return 66
    fi
    status=$(dbtune_lifecycle_capture_status) || return 1
    memory=$(dbtune_lifecycle_capture_memory) || return 1
    [[ -n $status && -n $memory ]] || return 1
    printf '%s\n' "$status" | dbtune_atomic_write "$current_status" 600 || return 1
    printf '%s\n' "$memory" | dbtune_atomic_write "$current_memory" 600 || return 1
    baseline_uptime=$(dbtune_lifecycle_tsv_value "$baseline_status" uptime)
    current_uptime=$(dbtune_lifecycle_tsv_value "$current_status" uptime)
    for metric in innodb_buffer_pool_wait_free innodb_log_waits aborted_connects; do
        before=$(dbtune_lifecycle_tsv_value "$baseline_status" "$metric")
        value=$(dbtune_lifecycle_tsv_value "$current_status" "$metric")
        delta=$(dbtune_msg lifecycle_value_missing_upper)
        reset=false
        if [[ $before =~ ^[0-9]+$ && $value =~ ^[0-9]+$ && $baseline_uptime =~ ^[0-9]+$ && $current_uptime =~ ^[0-9]+$ ]]; then
            if ((current_uptime < baseline_uptime || value < before)); then
                delta=$value
                reset=true
            else
                delta=$((value - before))
            fi
        fi
        dbtune_printf lifecycle_health_line "$metric" "${before:-$missing_upper}" "${value:-$missing_upper}" "$delta" "$reset"
        if [[ ! $delta =~ ^[0-9]+$ ]] || ((delta != 0)); then
            failures=1
        fi
    done
    baseline_swap=$(dbtune_lifecycle_tsv_value "$history/baseline-memory.tsv" swap_used_mb)
    current_swap=$(dbtune_lifecycle_tsv_value "$current_memory" swap_used_mb)
    available=$(dbtune_lifecycle_tsv_value "$current_memory" mem_available_mb)
    total=$(dbtune_lifecycle_tsv_value "$current_memory" mem_total_mb)
    dbtune_printf lifecycle_memory_line "$available" "$current_swap" "$baseline_swap"
    if [[ ! $baseline_swap =~ ^[0-9]+$ || ! $current_swap =~ ^[0-9]+$ || ! $available =~ ^[0-9]+$ || ! $total =~ ^[0-9]+$ ]]; then
        failures=1
    elif ((current_swap > baseline_swap || available * 20 < total)); then
        failures=1
    fi
    ((failures == 0))
}

dbtune_lifecycle_verify_24h_comparison() {
    local history=${1:-}
    local baseline="$history/post-status.tsv"
    local current="$history/verify-status.tsv"
    local metric before after delta

    [[ -r $baseline && -r $current ]] || return 66
    dbtune_printf lifecycle_verify_table_header
    while IFS=$'\t' read -r metric before; do
        after=$(dbtune_lifecycle_tsv_value "$current" "$metric")
        [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || continue
        if ((after >= before)); then
            delta=$((after - before))
        else
            delta="reset:$after"
        fi
        printf '%s\t%s\t%s\t%s\n' "$metric" "$before" "$after" "$delta"
    done <"$baseline"
}

cmd_verify() {
    local mode=${1:-}
    local history proposal state failures=0

    if (($# != 1)) || [[ $mode != --post && $mode != --24h ]]; then
        dbtune_log error "$(dbtune_msg lifecycle_verify_usage)"
        return 64
    fi
    history=$(dbtune_lifecycle_read_current) || return
    proposal="$history/proposed.cnf"
    [[ -s $proposal ]] || return 66
    dbtune_lifecycle_verify_target "$history" || failures=1
    dbtune_lifecycle_verify_values "$proposal" || failures=1
    dbtune_lifecycle_verify_health "$history" "$mode" || failures=1
    if [[ $mode == --24h ]]; then
        dbtune_lifecycle_verify_24h_comparison "$history" || failures=1
    fi
    if ((failures != 0)); then
        state=$(dbtune_state_read) || return
        if [[ $state == verified ]]; then
            dbtune_state_write applied || return
        fi
        dbtune_event verify_failed mode "$mode" history "$history" || true
        return 1
    fi
    if [[ $mode == --post ]]; then
        dbtune_atomic_write "$history/post-status.tsv" 600 <"$history/verify-status.tsv" || return 1
    fi
    dbtune_state_transition verified || return
    dbtune_event verify_completed mode "$mode" history "$history" || true
}

cmd_rollback() {
    local history previous_state rollback_intent

    (($# == 0)) || {
        dbtune_log error "$(dbtune_msg lifecycle_rollback_no_options)"
        return 64
    }
    rollback_intent=$(dbtune_lifecycle_rollback_intent_file)
    if [[ -e $rollback_intent || -L $rollback_intent ]]; then
        dbtune_lifecycle_read_rollback_intent || return
        dbtune_lifecycle_continue_rollback 1
        return
    fi
    history=$(dbtune_lifecycle_read_current) || return
    previous_state=$(dbtune_state_read) || return
    dbtune_lifecycle_resolve_restore_lineage "$history" || return
    dbtune_lifecycle_publish_rollback_intent "$history" "$previous_state" "$history" || return
    dbtune_lifecycle_fault_inject after_rollback_intent || return
    dbtune_lifecycle_read_rollback_intent || return
    dbtune_lifecycle_continue_rollback 1
}

cmd_status() {
    local state target current_file history='-' rollback=false baseline=false restart_required=false
    local recovery=false recovery_instruction='-' last_rollback='-'
    local candidate

    (($# == 0)) || {
        dbtune_log error "$(dbtune_msg lifecycle_status_no_options)"
        return 64
    }
    state=$(dbtune_state_read) || return
    target=$(dbtune_lifecycle_target)
    current_file=$(dbtune_lifecycle_current_file)
    if [[ -r $current_file ]]; then
        IFS= read -r history <"$current_file" || history='-'
    elif [[ $state == recovery_required || $state == rollback_failed ]]; then
        for candidate in "$DBTUNE_STATE_DIR"/apply/*; do
            [[ -d $candidate ]] || continue
            if [[ -r $candidate/RECOVERY_REQUIRED || -r $candidate/ROLLBACK_FAILED ]]; then
                history=$candidate
            fi
        done
    fi
    if [[ $history != - ]]; then
        [[ -r $history/ROLLBACK.txt ]] && rollback=true
        [[ -r $history/baseline-status.tsv && -r $history/baseline-memory.tsv ]] && baseline=true
        [[ -r $history/RESTART_REQUIRED ]] && restart_required=true
        if [[ $state == recovery_required || $state == rollback_failed || -r $history/RECOVERY_REQUIRED || -r $history/ROLLBACK_FAILED ]]; then
            recovery=true
            recovery_instruction=$(dbtune_printf lifecycle_recovery_manual "$history")
        elif [[ -r $history/SERVICE_START_FAILED ]]; then
            recovery=true
            recovery_instruction='sudo systemctl start mariadb'
        fi
    fi
    if [[ -r $(dbtune_lifecycle_last_rollback_file) ]]; then
        IFS= read -r last_rollback <"$(dbtune_lifecycle_last_rollback_file)" || last_rollback='-'
        if [[ $last_rollback != - ]] && ! dbtune_lifecycle_cycle_id "$last_rollback" >/dev/null; then
            last_rollback=-
        fi
    fi
    if [[ $state == rolled_back && $last_rollback != - ]]; then
        [[ -r $last_rollback/RESTART_REQUIRED ]] && restart_required=true
        if [[ -r $last_rollback/SERVICE_START_FAILED ]]; then
            recovery=true
            recovery_instruction='sudo systemctl start mariadb'
        fi
    fi
    printf 'state: %s\n' "$state"
    printf 'config_target: %s\n' "$target"
    printf 'config_present: %s\n' "$([[ -f $target ]] && printf true || printf false)"
    printf 'apply_history: %s\n' "$history"
    printf 'baseline_present: %s\n' "$baseline"
    printf 'rollback_instructions: %s\n' "$rollback"
    printf 'rollback_available: %s\n' "$rollback"
    printf 'last_rollback: %s\n' "$last_rollback"
    printf 'runcloud_restart_required: %s\n' "$restart_required"
    printf 'recovery_required: %s\n' "$recovery"
    printf 'recovery_instruction: %s\n' "$recovery_instruction"
}
