dbtune_lifecycle_target() {
    printf '%s\n' "${DBTUNE_CONFIG_TARGET:-/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf}"
}

dbtune_lifecycle_proposal() {
    printf '%s/proposed-99-zz-tuning.cnf\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_current_file() {
    printf '%s/apply/current\n' "$DBTUNE_STATE_DIR"
}

dbtune_lifecycle_force_phrase() {
    printf '%s\n' 'APLIKUJ BEZ MERANIA'
}

dbtune_lifecycle_backup_phrase() {
    printf '%s\n' 'POTVRDZUJEM OBNOVITELNU ZALOHU'
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
                dbtune_log error "Neznama volba apply: $1"
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
        dbtune_log error "--force je povoleny iba interaktivne na TTY"
        return 77
    fi
    printf 'Pre pokracovanie napiste presne: %s\n> ' "$phrase" >&2
    IFS= read -r answer || return 77
    if [[ $answer != "$phrase" ]]; then
        dbtune_log error "Potvrdzovacia fraza nesuhlasi"
        return 77
    fi
}

dbtune_lifecycle_confirm_backup() {
    local phrase answer

    phrase=$(dbtune_lifecycle_backup_phrase)
    if ! dbtune_lifecycle_is_interactive; then
        dbtune_log error "Apply vyzaduje overeny backup-evidence.tsv alebo interaktivne potvrdenie na TTY"
        return 77
    fi
    printf 'Chyba autoritativny dokaz poslednej uspesnej zalohy. Overte obnovu mimo dbtune.\n' >&2
    printf 'Pre pokracovanie napiste presne: %s\n> ' "$phrase" >&2
    IFS= read -r answer || return 77
    if [[ $answer != "$phrase" ]]; then
        dbtune_log error "Potvrdenie obnovitelnej zalohy nesuhlasi"
        return 77
    fi
}

dbtune_lifecycle_check_backup() {
    local evidence=${1:-}
    local status

    DBTUNE_APPLY_BACKUP_MODE=interactive
    DBTUNE_APPLY_BACKUP_SOURCE=operator
    DBTUNE_APPLY_BACKUP_LAST_SUCCESS=unknown
    if [[ -n $evidence ]] && dbtune_backup_evidence_validate "$evidence"; then
        status=$(dbtune_manifest_value "$evidence" status) || return 65
        if [[ $status == verified ]]; then
            DBTUNE_APPLY_BACKUP_MODE=artifact
            DBTUNE_APPLY_BACKUP_SOURCE=$(dbtune_manifest_value "$evidence" source) || return 65
            DBTUNE_APPLY_BACKUP_LAST_SUCCESS=$(dbtune_manifest_value "$evidence" last_success) || return 65
            return 0
        fi
        if [[ $status == missing ]]; then
            dbtune_log error "Apply je zablokovany: autoritativny backup evidence potvrdzuje absenciu zalohy"
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
    IFS= read -r count < <(awk -F '\t' 'NR==1 {ok=($1=="timestamp" && $17=="restart_flag"); next} NF==17 {n++} END {if (!ok) exit 1; print n+0}' "$samples") || return 1
    ((count >= ${DBTUNE_MIN_APPLY_SAMPLES:-288})) || return 1
    awk -F '\t' 'NR==1 {exit !(NF==8 && $1=="rule_id" && $2=="scope" && $5=="proposed_key" && $8=="reason_sk")}' "$analysis"
}

dbtune_lifecycle_manifest_value_from() {
    local manifest=${1:-}
    local key=${2:-}

    awk -F '\t' -v wanted="$key" '$1==wanted {print $2; found=1; exit} END {if (!found) exit 1}' "$manifest"
}

dbtune_lifecycle_validate_proposal_manifest() {
    local manifest="$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    local proposal=${1:-$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf}
    local analysis_manifest key expected actual

    [[ -r $manifest ]] || {
        dbtune_log error "Chyba proposal manifest: $manifest"
        return 66
    }
    dbtune_provenance_validate_analysis || return
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    for key in run_id audit_hash samples_hash analysis_hash; do
        expected=$(dbtune_manifest_value "$analysis_manifest" "$key") || return 65
        actual=$(dbtune_manifest_value "$manifest" "$key") || {
            dbtune_log error "Proposal manifest nema provenance zaznam $key"
            return 65
        }
        if [[ $actual != "$expected" ]]; then
            dbtune_log error "Proposal patri inemu analysis runu ($key)"
            return 65
        fi
    done
    expected=$(dbtune_manifest_value "$manifest" proposal_hash) || {
        dbtune_log error "Proposal manifest nema proposal_hash"
        return 65
    }
    [[ $expected =~ ^[0-9a-f]{64}$ && -r $proposal ]] || return 65
    actual=$(dbtune_sha256_file "$proposal") || return
    if [[ $actual != "$expected" ]]; then
        dbtune_log error "Proposal snapshot sa zmenil alebo nezodpoveda manifestu"
        return 65
    fi
}

dbtune_lifecycle_check_apply_inputs() {
    local force=${1:-0}
    local proposal=${2:-}
    local state

    [[ -n $proposal ]] || proposal=$(dbtune_lifecycle_proposal)
    state=$(dbtune_state_read) || return
    if ((force == 0)) && [[ $state != proposed ]]; then
        dbtune_log error "Apply vyzaduje aktualny stav proposed; aktualny stav je '$state'"
        return 65
    fi
    if ((force == 1)) && [[ $state != audited && $state != analyzed && $state != proposed ]]; then
        dbtune_log error "Vynuteny apply vyzaduje stav audited, analyzed alebo proposed; aktualny stav je '$state'"
        return 65
    fi
    if [[ ! -s $proposal ]]; then
        dbtune_log error "Chyba navrh konfiguracie: $proposal"
        return 66
    fi
    if ! dbtune_lifecycle_has_measurement && ((force == 0)); then
        dbtune_log error "Apply je zablokovany: chyba samples.tsv alebo analysis.tsv; preset bez merania je hadanie"
        return 65
    fi
    if ((force == 0)); then
        dbtune_lifecycle_validate_proposal_manifest "$proposal" || return
    fi
}

dbtune_lifecycle_check_time_window() {
    local force=${1:-0}
    local clock hour minute total

    ((force == 1)) && return 0
    clock=${DBTUNE_NOW_HHMM:-}
    [[ -n $clock ]] || clock=$(date '+%H%M') || return 1
    if [[ ! $clock =~ ^[0-2][0-9][0-5][0-9]$ ]]; then
        dbtune_log error "Neplatny lokalny cas z date: $clock"
        return 70
    fi
    hour=${clock:0:2}
    minute=${clock:2:2}
    total=$((10#$hour * 60 + 10#$minute))
    if ((total >= 330 && total <= 450)); then
        dbtune_log error "Apply je medzi 05:30 a 07:30 lokalne blokovany kvoli unattended-upgrades; pouzite interaktivny --force"
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

dbtune_lifecycle_variable_names() {
    local proposal=${1:-}

    dbtune_lifecycle_config_entries "$proposal" | awk -F '\t' '{print $1}'
}

dbtune_lifecycle_validate_variable_names() {
    local proposal=${1:-}
    local query list='' separator='' name output_file
    local -A requested=() found=()

    while IFS= read -r name; do
        [[ -n $name ]] || continue
        requested["$name"]=1
        list+="${separator}'$name'"
        separator=,
    done < <(dbtune_lifecycle_variable_names "$proposal")
    if ((${#requested[@]} == 0)); then
        dbtune_log error "Navrh nema ziadne aktivne premenne v sekcii [mysqld]"
        return 65
    fi

    query="SELECT LOWER(VARIABLE_NAME) FROM information_schema.GLOBAL_VARIABLES WHERE LOWER(VARIABLE_NAME) IN ($list)"
    output_file=$(mktemp "$DBTUNE_STATE_DIR/.variables.XXXXXX") || return 1
    if ! dbtune_sql "$query" >"$output_file"; then
        rm -f "$output_file"
        dbtune_log error "Ziva kontrola nazvov premennych zlyhala"
        return 69
    fi
    while IFS= read -r name; do
        name=${name,,}
        [[ -n $name ]] && found["$name"]=1
    done <"$output_file"
    rm -f "$output_file"

    for name in "${!requested[@]}"; do
        if [[ -z ${found[$name]+x} ]]; then
            dbtune_log error "Neznama alebo neaktivna MariaDB premenna: $name"
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
        dbtune_log error "Galera/wsrep je aktivna alebo nakonfigurovana; apply sa odmieta"
        return 65
    fi
}

dbtune_lifecycle_reject_mydumper() {
    local count

    count=$(dbtune_sql "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE ID <> CONNECTION_ID() AND (LOWER(COALESCE(USER,'')) LIKE '%mydumper%' OR LOWER(COALESCE(INFO,'')) LIKE '%mydumper%' OR COALESCE(INFO,'') LIKE '%SQL_NO_CACHE%')") || return
    if [[ ! $count =~ ^[0-9]+$ ]]; then
        dbtune_log error "Kontrola mydumper procesu vratila neplatny vysledok"
        return 70
    fi
    if ((count > 0)); then
        dbtune_log error "Bezi mydumper backup; config ani restart pokyn sa nevykona"
        return 75
    fi
}

dbtune_lifecycle_reject_critical_analysis() {
    local analysis="$DBTUNE_STATE_DIR/analysis.tsv"
    local findings

    [[ -r $analysis ]] || return 66
    findings=$(awk -F '\t' '
        NR > 1 && $2 == "server" && $3 == "critical" &&
        (($1 == "R-VERSION" && ($4 == "UNSUPPORTED" || $4 == "REMOVED")) ||
         ($1 == "R-BACKUP" && $4 == "MISSING")) {
            print $1 ": " $4 " - " $8
        }
    ' "$analysis")
    if [[ -n $findings ]]; then
        dbtune_log error "Apply blokuje kriticky serverovy nalez: $findings"
        return 65
    fi
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
        printf '# Filesystem-first rollback; nevyzaduje funkcnu MariaDB ani dbtune.\n'
        printf 'sudo test -d %s\n' "$history_q"
        printf 'sudo test ! -e %s || sudo mv %s %s\n' "$target_q" "$target_q" "$removed_q"
        if ((had_original == 1)); then
            printf 'sudo install -o root -g root -m 0644 %s %s\n' "$backup_q" "$target_q"
        fi
        printf 'if sudo systemctl is-active --quiet mariadb; then\n'
        printf '  printf "Config je obnoveny; restartujte MariaDB cez RunCloud panel.\\n"\n'
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
    local had_original=0 proposal_hash expected_hash run_id=unmeasured audit_hash=unmeasured
    local backup_hash=interactive
    local proposal_manifest="$DBTUNE_STATE_DIR/proposal-manifest.tsv"

    if [[ -e $target ]]; then
        cp -p "$target" "$history/original.cnf" || return 1
        chmod 600 "$history/original.cnf" || return 1
        had_original=1
    fi
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
    expected_hash=$(dbtune_manifest_value "$proposal_manifest" proposal_hash 2>/dev/null || true)
    if [[ $expected_hash == "$proposal_hash" ]]; then
        run_id=$(dbtune_manifest_value "$proposal_manifest" run_id 2>/dev/null || printf unknown)
        audit_hash=$(dbtune_manifest_value "$proposal_manifest" audit_hash 2>/dev/null || printf unknown)
    fi
    {
        printf 'target\t%s\n' "$target"
        printf 'had_original\t%s\n' "$had_original"
        printf 'created_at\t%s\n' "$(dbtune_now)"
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'proposal_hash\t%s\n' "$proposal_hash"
        printf 'backup_guard\t%s\n' "$DBTUNE_APPLY_BACKUP_MODE"
        printf 'backup_source\t%s\n' "$DBTUNE_APPLY_BACKUP_SOURCE"
        printf 'backup_last_success\t%s\n' "$DBTUNE_APPLY_BACKUP_LAST_SUCCESS"
        printf 'backup_evidence_hash\t%s\n' "$backup_hash"
    } | dbtune_atomic_write "$history/manifest.tsv" 600 || return 1
    dbtune_lifecycle_write_rollback_instructions "$history" "$target" "$had_original" || return 1
    printf '%s\n' "$had_original"
}

dbtune_lifecycle_install_config() {
    local proposal=${1:-}
    local target=${2:-}
    local directory temporary

    directory=${target%/*}
    [[ $directory != "$target" ]] || directory=.
    install -d -m 755 "$directory" || return 1
    temporary=$(mktemp "$directory/.99-zz-tuning.cnf.tmp.XXXXXX") || return 1
    if ! command cat "$proposal" >"$temporary" || ! chown root:root "$temporary" || ! chmod 0644 "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if ! mv -f "$temporary" "$target"; then
        rm -f "$temporary"
        return 1
    fi
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
    local server validate_dir output_file probe_file command_status=0 probe_status=0

    if command -v mariadbd >/dev/null 2>&1; then
        server=$(command -v mariadbd)
    elif command -v mysqld >/dev/null 2>&1; then
        server=$(command -v mysqld)
    else
        dbtune_log error "Nenasiel sa mariadbd ani mysqld pre validaciu"
        return 69
    fi
    validate_dir=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-validate.XXXXXX") || return 1
    output_file="$validate_dir/output.log"
    probe_file="$validate_dir/help.log"
    chown mysql:mysql "$validate_dir" 2>/dev/null || true

    "$server" --help --verbose >"$probe_file" 2>&1 || probe_status=$?
    if grep -q -- '--validate-config' "$probe_file"; then
        "$server" --validate-config --user=mysql --datadir="$validate_dir" >"$output_file" 2>&1 || command_status=$?
    else
        cp "$probe_file" "$output_file" || {
            rm -rf "$validate_dir"
            return 1
        }
        command_status=$probe_status
    fi
    if ! dbtune_lifecycle_validation_output_ok "$output_file"; then
        rm -rf "$validate_dir"
        dbtune_log error "mariadbd validacia nasla neplatnu konfiguraciu"
        return 65
    fi
    if ((command_status != 0)) && ! dbtune_lifecycle_validation_has_tolerated_error "$output_file"; then
        rm -rf "$validate_dir"
        dbtune_log error "mariadbd validacia zlyhala bez dokumentovanej lock/engine init chyby"
        return 65
    fi
    if ((command_status != 0)); then
        dbtune_log warn "mariadbd vratil $command_status, ale vystup obsahoval iba dokumentovane lock/engine init chyby"
    fi
    rm -rf "$validate_dir"
}

dbtune_lifecycle_manifest_value() {
    local history=${1:-}
    local key=${2:-}

    awk -F '\t' -v wanted="$key" '$1 == wanted {sub(/^[^\t]*\t/, ""); print; exit}' "$history/manifest.tsv"
}

dbtune_lifecycle_restore_config() {
    local history=${1:-}
    local target had_original removed directory temporary

    target=$(dbtune_lifecycle_manifest_value "$history" target) || return 1
    had_original=$(dbtune_lifecycle_manifest_value "$history" had_original) || return 1
    [[ -n $target && $had_original =~ ^[01]$ ]] || return 65
    if ((had_original == 1)) && [[ ! -f $history/original.cnf ]]; then
        dbtune_log error "V apply historii chyba povodny config: $history/original.cnf"
        return 66
    fi
    removed="$history/rollback-deployed.cnf"
    if [[ -e $target ]]; then
        if [[ -e $removed ]]; then
            removed="$history/rollback-deployed-$(date -u '+%Y%m%dT%H%M%SZ').cnf"
        fi
        mv "$target" "$removed" || return 1
    fi
    if ((had_original == 1)); then
        directory=${target%/*}
        [[ $directory != "$target" ]] || directory=.
        temporary=$(mktemp "$directory/.99-zz-restore.tmp.XXXXXX") || return 1
        if ! command cat "$history/original.cnf" >"$temporary" || ! chown root:root "$temporary" || ! chmod 0644 "$temporary" || ! mv -f "$temporary" "$target"; then
            rm -f "$temporary"
            return 1
        fi
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

dbtune_lifecycle_read_current() {
    local current_file history

    current_file=$(dbtune_lifecycle_current_file)
    [[ -r $current_file ]] || {
        dbtune_log error "Chyba zaznam aktualneho apply: $current_file"
        return 66
    }
    IFS= read -r history <"$current_file" || return 1
    if [[ $history != "$DBTUNE_STATE_DIR"/apply/* || ! -d $history || ! -r $history/manifest.tsv ]]; then
        dbtune_log error "Neplatna apply historia: ${history:-<prazdna>}"
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
    dbtune_log error "KRITICKE: obnova konfiguracie zlyhala; pouzite $history/ROLLBACK.txt"
}

dbtune_lifecycle_restore_previous_pointer() {
    local previous_current=${1:-}

    if [[ -n $previous_current ]]; then
        dbtune_lifecycle_publish_current "$previous_current"
    else
        rm -f "$(dbtune_lifecycle_current_file)"
    fi
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
    dbtune_event apply_restored phase "$phase" history "$history" || true
}

dbtune_lifecycle_mark_unmeasured() {
    local history=${1:-}
    local report="$DBTUNE_STATE_DIR/report.md"
    local stamp='BEZ MERANIA'

    {
        printf '# APPLY REPORT\n\n'
        printf '**%s** - konfiguracia bola aplikovana cez interaktivny --force.\n' "$stamp"
    } | dbtune_atomic_write "$history/apply-report.md" 600 || return 1
    if [[ -f $report ]]; then
        printf '\n> **%s** - apply bol vynuteny bez kompletneho measurement/analysis artefaktu.\n' "$stamp" >>"$report" || return 1
    fi
    dbtune_event apply_force measurement "$stamp" || true
}

dbtune_lifecycle_print_runcloud_instructions() {
    local history=${1:-}
    local target=${2:-}

    printf 'Config bol zapisany do %s.\n' "$target"
    printf 'Restartujte cez RunCloud: Services -> MariaDB -> Restart.\n'
    printf 'Pri zmene redo logu moze prvy start trvat dlhsie.\n'
    printf 'Po restarte spustite: dbtune verify --post\n'
    printf 'Nudzove doslovne prikazy: %s/ROLLBACK.txt\n' "$history"
}

dbtune_lifecycle_after_manifest_check() {
    return 0
}

dbtune_lifecycle_apply_snapshot() {
    local restart=${1:-0}
    local force=${2:-0}
    local proposal=${3:-}
    local backup_evidence=${4:-}
    local target history had_original previous_state previous_current='' unmeasured=0
    local systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}

    dbtune_lifecycle_has_measurement || unmeasured=1
    if ((force == 1)); then
        dbtune_lifecycle_confirm_force || return
    fi
    dbtune_lifecycle_check_backup "$backup_evidence" || return
    dbtune_lifecycle_check_time_window "$force" || return

    target=$(dbtune_lifecycle_target)
    dbtune_init_state_dir || return 1
    dbtune_lifecycle_validate_variable_names "$proposal" || return
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
    had_original=$(dbtune_lifecycle_prepare_history "$history" "$target" "$proposal" "$backup_evidence") || return
    dbtune_lifecycle_capture_baseline "$history" || {
        dbtune_log error "Nepodarilo sa ulozit baseline; config sa nezapisal"
        return 1
    }
    if ! dbtune_lifecycle_install_config "$proposal" "$target"; then
        dbtune_log error "Atomicky zapis konfiguracie zlyhal"
        return 1
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
    if ((restart == 1)); then
        if ! "$systemctl_command" restart mariadb || ! "$systemctl_command" is-active --quiet mariadb; then
            dbtune_log error "Restart MariaDB zlyhal; obnovujem povodny config a spustam sluzbu"
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
    dbtune_event apply_completed target "$target" history "$history" restart "$restart" force "$force" original "$had_original" || true
}

cmd_apply() {
    local parsed restart force proposal snapshot backup_file backup_snapshot='' status=0

    parsed=$(dbtune_lifecycle_parse_args "$@") || return
    IFS=$'\t' read -r restart force <<<"$parsed"
    dbtune_init_state_dir || return 1
    proposal=$(dbtune_lifecycle_proposal)
    [[ -s $proposal ]] || {
        dbtune_log error "Chyba navrh konfiguracie: $proposal"
        return 66
    }
    snapshot=$(mktemp "$DBTUNE_STATE_DIR/.apply-proposal.XXXXXX") || return 1
    if ! cp "$proposal" "$snapshot" || ! chmod 400 "$snapshot"; then
        rm -f "$snapshot"
        return 1
    fi
    backup_file=$(dbtune_backup_evidence_file)
    if dbtune_backup_evidence_validate "$backup_file"; then
        backup_snapshot=$(mktemp "$DBTUNE_STATE_DIR/.apply-backup-evidence.XXXXXX") || {
            rm -f "$snapshot"
            return 1
        }
        if ! cp "$backup_file" "$backup_snapshot" || ! chmod 400 "$backup_snapshot" ||
            ! dbtune_backup_evidence_validate "$backup_snapshot"; then
            rm -f "$snapshot" "$backup_snapshot"
            return 1
        fi
    fi
    if dbtune_lifecycle_check_apply_inputs "$force" "$snapshot"; then
        :
    else
        status=$?
        rm -f "$snapshot" "$backup_snapshot"
        return "$status"
    fi
    dbtune_lifecycle_after_manifest_check || {
        status=$?
        rm -f "$snapshot" "$backup_snapshot"
        return "$status"
    }
    dbtune_lifecycle_apply_snapshot "$restart" "$force" "$snapshot" "$backup_snapshot" || status=$?
    rm -f "$snapshot" "$backup_snapshot"
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
    local target expected_hash snapshot_hash actual_hash uid gid mode
    local expected_uid=${DBTUNE_CONFIG_UID:-0}
    local expected_gid=${DBTUNE_CONFIG_GID:-0}
    local expected_mode=${DBTUNE_CONFIG_MODE:-644}

    target=$(dbtune_lifecycle_manifest_value "$history" target) || return 65
    expected_hash=$(dbtune_lifecycle_manifest_value "$history" proposal_hash) || return 65
    if [[ ! -f $target || -L $target ]]; then
        printf 'TARGET CHYBA: %s nie je regularny subor alebo je symlink\n' "$target"
        return 1
    fi
    read -r uid gid mode < <(dbtune_file_stat "$target") || return 1
    if [[ $uid != "$expected_uid" || $gid != "$expected_gid" || $mode != "$expected_mode" ]]; then
        printf 'TARGET CHYBA: owner=%s:%s mode=%s, ocakavane=%s:%s %s\n' \
            "$uid" "$gid" "$mode" "$expected_uid" "$expected_gid" "$expected_mode"
        return 1
    fi
    [[ $expected_hash =~ ^[0-9a-f]{64}$ && -f $history/proposed.cnf && ! -L $history/proposed.cnf ]] || return 65
    snapshot_hash=$(dbtune_sha256_file "$history/proposed.cnf") || return
    actual_hash=$(dbtune_sha256_file "$target") || return
    if [[ $snapshot_hash != "$expected_hash" || $actual_hash != "$expected_hash" ]]; then
        printf 'TARGET CHYBA: hash nasadeneho configu nezodpoveda apply snapshotu\n'
        return 1
    fi
    printf 'TARGET OK: %s owner=%s:%s mode=%s hash=%s\n' "$target" "$uid" "$gid" "$mode" "$actual_hash"
}

dbtune_lifecycle_verify_values() {
    local proposal=${1:-}
    local names='' separator='' name expected actual output_file query
    local -A expected_values=() actual_values=()
    local failures=0

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
        actual=$(dbtune_lifecycle_canonical_value "${actual_values[$name]-<chyba>}")
        if [[ $expected != "$actual" ]]; then
            printf 'MISMATCH %s: proposal=%s effective=%s\n' "$name" "${expected_values[$name]}" "${actual_values[$name]-CHYBA}"
            failures=1
        else
            printf 'OK %s=%s\n' "$name" "${actual_values[$name]}"
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
    local metric before value delta reset baseline_uptime current_uptime
    local baseline_swap current_swap available total
    local status memory
    local failures=0

    if [[ -r $history/post-status.tsv ]]; then
        baseline_status="$history/post-status.tsv"
    elif [[ $mode == --24h ]]; then
        dbtune_log error "verify --24h vyzaduje uspesny verify --post po restarte"
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
        delta=CHYBA
        reset=nie
        if [[ $before =~ ^[0-9]+$ && $value =~ ^[0-9]+$ && $baseline_uptime =~ ^[0-9]+$ && $current_uptime =~ ^[0-9]+$ ]]; then
            if ((current_uptime < baseline_uptime || value < before)); then
                delta=$value
                reset=ano
            else
                delta=$((value - before))
            fi
        fi
        printf '%s baseline=%s current=%s delta=%s reset=%s\n' "$metric" "${before:-CHYBA}" "${value:-CHYBA}" "$delta" "$reset"
        if [[ ! $delta =~ ^[0-9]+$ ]] || ((delta != 0)); then
            failures=1
        fi
    done
    baseline_swap=$(dbtune_lifecycle_tsv_value "$history/baseline-memory.tsv" swap_used_mb)
    current_swap=$(dbtune_lifecycle_tsv_value "$current_memory" swap_used_mb)
    available=$(dbtune_lifecycle_tsv_value "$current_memory" mem_available_mb)
    total=$(dbtune_lifecycle_tsv_value "$current_memory" mem_total_mb)
    printf 'memory_available_mb=%s swap_used_mb=%s baseline_swap_used_mb=%s\n' "$available" "$current_swap" "$baseline_swap"
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
    printf 'METRIC\tBASELINE\tCURRENT\tDELTA_OR_RESET\n'
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
        dbtune_log error "Pouzitie: dbtune verify --post|--24h"
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
    local history start_status=0 restart_required=0
    local systemctl_command=${DBTUNE_SYSTEMCTL:-systemctl}

    (($# == 0)) || {
        dbtune_log error "rollback nema volby"
        return 64
    }
    history=$(dbtune_lifecycle_read_current) || return
    if ! dbtune_lifecycle_restore_config "$history"; then
        {
            printf 'created_at\t%s\n' "$(dbtune_now)"
            printf 'instructions\t%s/ROLLBACK.txt\n' "$history"
        } | dbtune_atomic_write "$history/ROLLBACK_FAILED" 600 || true
        dbtune_lifecycle_publish_current "$history" || true
        dbtune_state_write rollback_failed || dbtune_state_write recovery_required || true
        dbtune_event rollback_failed history "$history" || true
        dbtune_log error "Filesystem rollback zlyhal; pouzite $history/ROLLBACK.txt"
        return 1
    fi
    rm -f "$history/RECOVERY_REQUIRED" "$history/ROLLBACK_FAILED" "$history/SERVICE_START_FAILED"
    if "$systemctl_command" is-active --quiet mariadb; then
        restart_required=1
        printf 'Config bol obnoveny. Restartujte MariaDB manualne cez RunCloud panel, aby sa obnovili aj efektivne hodnoty.\n'
        printf '%s\n' "$(dbtune_now)" | dbtune_atomic_write "$history/RESTART_REQUIRED" 600 || return 1
    else
        "$systemctl_command" start mariadb || start_status=$?
        rm -f "$history/RESTART_REQUIRED"
    fi
    dbtune_state_transition rolled_back || dbtune_state_write rolled_back || return
    dbtune_event rollback_completed history "$history" service_start_status "$start_status" restart_required "$restart_required" || true
    if ((start_status != 0)); then
        printf '%s\n' "$(dbtune_now)" | dbtune_atomic_write "$history/SERVICE_START_FAILED" 600 || true
        dbtune_log error "Config bol obnoveny, ale systemctl start mariadb zlyhal"
        return "$start_status"
    fi
}

cmd_status() {
    local state target current_file history='-' rollback='nie' baseline='nie' restart_required='nie'
    local recovery='nie' recovery_instruction='-'
    local candidate

    (($# == 0)) || {
        dbtune_log error "status nema volby"
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
        [[ -r $history/ROLLBACK.txt ]] && rollback=ano
        [[ -r $history/baseline-status.tsv && -r $history/baseline-memory.tsv ]] && baseline=ano
        [[ -r $history/RESTART_REQUIRED ]] && restart_required=ano
        if [[ $state == recovery_required || $state == rollback_failed || -r $history/RECOVERY_REQUIRED || -r $history/ROLLBACK_FAILED ]]; then
            recovery=ano
            recovery_instruction="sudo dbtune rollback; manualne: $history/ROLLBACK.txt"
        elif [[ -r $history/SERVICE_START_FAILED ]]; then
            recovery=ano
            recovery_instruction='sudo systemctl start mariadb'
        fi
    fi
    printf 'state: %s\n' "$state"
    printf 'config_target: %s\n' "$target"
    printf 'config_present: %s\n' "$([[ -f $target ]] && printf ano || printf nie)"
    printf 'apply_history: %s\n' "$history"
    printf 'baseline_present: %s\n' "$baseline"
    printf 'rollback_instructions: %s\n' "$rollback"
    printf 'rollback_available: %s\n' "$rollback"
    printf 'runcloud_restart_required: %s\n' "$restart_required"
    printf 'recovery_required: %s\n' "$recovery"
    printf 'recovery_instruction: %s\n' "$recovery_instruction"
}
