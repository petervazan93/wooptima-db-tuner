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
        dbtune_log error "Prikaz '$command_name' neocakava argumenty"
        return 64
    fi
}

dbtune_key_normalize() {
    printf '%s' "${1:-}" | LC_ALL=C tr '[:upper:]-' '[:lower:]_'
}

dbtune_is_sensitive_key() {
    local key
    key=$(dbtune_key_normalize "${1:-}")
    case $key in
        *password*|*passwd*|*credential*|*secret*|*token*|*salt*|*private_key*) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_report_safe() {
    dbtune_redact "${1:-}"
}

dbtune_markdown_escape() {
    local value
    value=$(dbtune_report_safe "${1:-}")
    value=${value//\\/\\\\}
    value=${value//|/\\|}
    value=${value//\`/\\\`}
    value=${value//$'\r'/}
    value=${value//$'\n'/<br>}
    printf '%s' "$value"
}

dbtune_analysis_line_is_valid() {
    local line=${1-}
    local without_tabs=${line//$'\t'/}
    ((${#line} - ${#without_tabs} == 7))
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
        DBTUNE_ANALYSIS_REASON \
        _dbtune_analysis_end <<<"${encoded}"$'\034_'
    DBTUNE_ANALYSIS_REASON=${DBTUNE_ANALYSIS_REASON%$'\r'}
}

dbtune_analysis_load() {
    local file=${1:-}
    local line

    DBTUNE_ANALYSIS_LINES=()
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        [[ $line == rule_id$'\t'* ]] && continue
        if ! dbtune_analysis_line_is_valid "$line"; then
            dbtune_log warn "Preskakujem neplatny analysis.tsv zaznam (ocakava sa 8 poli)"
            continue
        fi
        DBTUNE_ANALYSIS_LINES+=("$line")
    done <"$file"
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

dbtune_security_rule() {
    case ${DBTUNE_ANALYSIS_RULE_ID:-}:${DBTUNE_ANALYSIS_SCOPE:-} in
        R-SEC*:*|*:security|*:security:*) return 0 ;;
        *) return 1 ;;
    esac
}

dbtune_audit_value() {
    local file=${1:-}
    local wanted key value normalized candidate
    shift || true

    [[ -r $file ]] || return 1
    while IFS=$'\t' read -r key value _rest || [[ -n ${key:-} ]]; do
        [[ -n $key && $key != key ]] || continue
        dbtune_is_sensitive_key "$key" && continue
        normalized=$(dbtune_key_normalize "$key")
        for wanted in "$@"; do
            candidate=$(dbtune_key_normalize "$wanted")
            if [[ $normalized == "$candidate" ]]; then
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
    local key value normalized target

    target=$(dbtune_key_normalize "$proposed_key")
    while IFS=$'\t' read -r key value _rest || [[ -n ${key:-} ]]; do
        [[ -n $key && $key != key ]] || continue
        dbtune_is_sensitive_key "$key" && continue
        normalized=$(dbtune_key_normalize "$key")
        case $normalized in
            "$target"|variable."$target"|variables."$target"|mariadb."$target"|mariadb.variable."$target"|mysql.variable."$target")
                printf '%s\n' "${value%$'\r'}"
                return 0
                ;;
            *."$target")
                value=${value%$'\r'}
                [[ -n $value ]] && printf '%s\n' "$value" && return 0
                ;;
        esac
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
    local title=${1:-Inventár}
    local file=${2:-}
    local line first=1 header=0 row=0 i key value detail
    local -a headers

    printf '### %s\n\n' "$title"
    if [[ ! -s $file ]]; then
        printf '_Údaje nie sú dostupné._\n\n'
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
        [[ -n $detail ]] || detail='_bez bezpečne zobraziteľných hodnôt_'
        printf -- '- Záznam %s: %s\n' "$row" "$detail"
    done <"$file"
    printf '\n'
}

dbtune_samples_count() {
    local file=${1:-}
    awk -F '\t' '
        function norm(value) { value=tolower(value); gsub(/-/, "_", value); return value }
        NR == 1 {
            first=norm($1)
            header=(first == "timestamp" || first == "sampled_at" || first == "time" || first == "ts")
            if (header) {
                for (i=1; i<=NF; i++) {
                    name=norm($i)
                    if (name == "sample_status") status_column=i
                    if (name == "restart_flag") restart_column=i
                }
                next
            }
        }
        NF {
            if (status_column && $status_column != "ok") next
            if (restart_column && $restart_column != 0) next
            count++
        }
        END { print count + 0 }
    ' "$file"
}

dbtune_samples_stats() {
    local file=${1:-}
    local aliases=${2:-}
    local fallback=${3:-1}

    awk -F '\t' -v aliases="$aliases" -v fallback="$fallback" '
        function norm(value) { value=tolower(value); gsub(/-/, "_", value); return value }
        BEGIN { count=split(aliases, wanted, ","); column=fallback }
        NR == 1 {
            found=0; header=(norm($1) == "timestamp" || norm($1) == "sampled_at" || norm($1) == "time" || norm($1) == "ts")
            for (i=1; i<=NF; i++) {
                name=norm($i)
                if (name == "sample_status") status_column=i
                if (name == "restart_flag") restart_column=i
                for (j=1; j<=count; j++) if (name == wanted[j]) { column=i; found=1 }
            }
            if (header) { if (!found) column=0; next }
        }
        column > 0 && (!status_column || $status_column == "ok") && (!restart_column || $restart_column == 0) && $column ~ /^-?[0-9]+([.][0-9]+)?$/ { print $column + 0 }
    ' "$file" | LC_ALL=C sort -n | awk '
        { values[NR]=$1 }
        END {
            if (!NR) { print "n/a\tn/a\tn/a\tn/a"; exit }
            p50=int((NR-1)*0.50+0.999999)+1
            p95=int((NR-1)*0.95+0.999999)+1
            p99=int((NR-1)*0.99+0.999999)+1
            printf "%.2f\t%.2f\t%.2f\t%.2f\n", values[p50], values[p95], values[p99], values[NR]
        }
    '
}

dbtune_samples_worst() {
    local file=${1:-}

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
    ' "$file" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | awk -F '\t' 'NR <= 5'
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
                    "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_REASON")"
                shown=$((shown + 1))
                ((shown >= 5)) && return 0
            done
        done
    done
    ((shown)) || printf -- '- Analýza neobsahuje žiadne nálezy.\n'
}

dbtune_render_application_overview() {
    local line found=0

    printf '## Aplikačná vrstva — RIEŠ PRVÚ\n\n'
    printf 'Object cache dotazy odstráni; databázový tuning ich iba zlacní. Najprv vyriešte aplikačné nálezy, až potom aplikujte serverový návrh.\n\n'
    printf '| Závažnosť | Aplikácia | Verdikt | Dôvod |\n|---|---|---|---|\n'
    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] || continue
        found=1
        printf '| %s | %s | %s | %s |\n' \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
            "$(dbtune_markdown_escape "${DBTUNE_ANALYSIS_SCOPE#app:}")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_REASON")"
    done
    ((found)) || printf '| info | — | Bez aplikačných nálezov | — |\n'
    printf '\n'
}

dbtune_render_server_profile() {
    local _score timestamp cpu bp miss readbps threads

    printf '## Server, hardvér a profil záťaže\n\n'
    dbtune_render_audit_fact 'Host' audit.hostname hostname host.name server.hostname
    dbtune_render_audit_fact 'MariaDB' mariadb_version mariadb.version server.mariadb_version
    dbtune_render_audit_fact 'Operačný systém' os os_version server.os
    dbtune_render_audit_fact 'CPU jadrá' hw.cpu_count cpu_count cpu_cores cpu.cores
    dbtune_render_audit_fact 'RAM (bajty)' hw.ram_bytes ram_total ram_mb memory_total_mb memory.total_mb
    dbtune_render_audit_fact 'Disk' hw.storage_class disk_type storage_type storage.class
    dbtune_render_audit_fact 'Dataset (bajty)' mariadb.dataset_bytes dataset_size dataset_bytes dataset_mb dataset.total_mb
    printf -- '- **Počet validných vzoriek:** %s\n\n' "$(dbtune_samples_count "$DBTUNE_SAMPLES_FILE")"

    printf '### Percentily krátkych okien\n\n'
    printf '| Metrika | p50 | p95 | p99 | Maximum |\n|---|---:|---:|---:|---:|\n'
    dbtune_render_metric 'MariaDB CPU' 'cpu_pct,mariadbd_cpu_pct,db_cpu_pct' 13 ' %'
    dbtune_render_metric 'Buffer pool hit ratio' 'bp_hit_pct,bp_hit_ratio,buffer_pool_hit_pct' 3 ' %'
    dbtune_render_metric 'Buffer pool missy/s' 'bp_misses_s,bp_miss_s,bp_misses_per_s' 4 ''
    dbtune_render_metric 'Čítanie dát/s' 'data_read_s,data_read_bps,innodb_data_read_bps,data_read_per_s' 5 ' B/s'
    dbtune_render_metric 'Handler_read_rnd_next/s' 'rnd_next_s,handler_rnd_next_s,handler_read_rnd_next_s,handler_read_rnd_next_per_s' 6 ''
    dbtune_render_metric 'Threads_running' 'threads_running,running_threads' 8 ''
    dbtune_render_metric 'Diskové temp tabuľky' 'tmp_disk_pct,tmp_disk_tables_pct' 7 ' %'
    dbtune_render_metric 'Dostupná RAM' 'mem_available_kb,memory_available_kb' 14 ' KB'
    dbtune_render_metric 'Použitý swap' 'swap_used_kb,swap_kb' 15 ' KB'
    printf '\n### Najhoršie okná\n\n'
    printf '| Čas | CPU %% | BP hit %% | Missy/s | Čítanie B/s | Threads running |\n|---|---:|---:|---:|---:|---:|\n'
    while IFS=$'\t' read -r _score timestamp cpu bp miss readbps threads; do
        [[ -n $timestamp ]] || continue
        printf '| %s | %s | %s | %s | %s | %s |\n' \
            "$(dbtune_markdown_escape "$timestamp")" \
            "$(dbtune_markdown_escape "${cpu:-n/a}")" \
            "$(dbtune_markdown_escape "${bp:-n/a}")" \
            "$(dbtune_markdown_escape "${miss:-n/a}")" \
            "$(dbtune_markdown_escape "${readbps:-n/a}")" \
            "$(dbtune_markdown_escape "${threads:-n/a}")"
    done < <(dbtune_samples_worst "$DBTUNE_SAMPLES_FILE")
    printf '\n'
}

dbtune_render_proposed_diff() {
    local line current found=0

    printf '## Návrh konfigurácie: aktuálna → navrhnutá hodnota\n\n'
    printf '| Kľúč | Aktuálna hodnota | Navrhnutá hodnota | Evidencia | Odôvodnenie |\n|---|---|---|---|---|\n'
    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        [[ $DBTUNE_ANALYSIS_SCOPE == server && -n $DBTUNE_ANALYSIS_PROPOSED_KEY ]] || continue
        current=$(dbtune_audit_current_value "$DBTUNE_AUDIT_FILE" "$DBTUNE_ANALYSIS_PROPOSED_KEY" 2>/dev/null || true)
        [[ -n $current ]] || current='nezistená'
        found=1
        printf "| \`%s\` | \`%s\` | \`%s\` | %s | %s |\n" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_PROPOSED_KEY")" \
            "$(dbtune_markdown_escape "$current")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_PROPOSED_VALUE")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_EVIDENCE")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_REASON")"
    done
    ((found)) || printf '| — | — | — | Analýza nenavrhla žiadnu serverovú zmenu. | — |\n'
    printf '\n'
}

dbtune_render_per_app() {
    local outer_line inner_line scope seen=$'\n' found=0

    printf '## Per-app sekcie\n\n'
    for outer_line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$outer_line" || continue
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] || continue
        scope=$DBTUNE_ANALYSIS_SCOPE
        [[ $seen != *$'\n'"$scope"$'\n'* ]] || continue
        seen+="$scope"$'\n'
        found=1
        printf '### %s\n\n' "$(dbtune_markdown_escape "${scope#app:}")"
        printf '| Závažnosť | Verdikt | Evidencia | Odporúčanie |\n|---|---|---|---|\n'
        for inner_line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
            dbtune_analysis_parse "$inner_line" || continue
            [[ $DBTUNE_ANALYSIS_SCOPE == "$scope" ]] || continue
            printf '| %s | %s | %s | %s |\n' \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_EVIDENCE")" \
                "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_REASON")"
        done
        printf '\n'
    done
    ((found)) || printf '_Bez per-app nálezov._\n\n'
    dbtune_render_tsv_inventory 'Inventár aplikácií' "$DBTUNE_APPS_FILE"
    dbtune_render_tsv_inventory 'Databázy' "$DBTUNE_DATABASES_FILE"
}

dbtune_render_security() {
    local line found=0

    printf '## Bezpečnostné nálezy\n\n'
    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        dbtune_security_rule || continue
        found=1
        printf -- '- **%s:** %s. %s\n' \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_SEVERITY")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_VERDICT")" \
            "$(dbtune_markdown_escape "$DBTUNE_ANALYSIS_REASON")"
    done
    ((found)) || printf -- '- Bez samostatných bezpečnostných nálezov v analýze.\n'
    printf '\n'
}

dbtune_render_markdown() {
    local generated_at=${1:-}
    local critical high medium low

    critical=$(dbtune_analysis_count all critical)
    high=$(dbtune_analysis_count all high)
    medium=$(dbtune_analysis_count all medium)
    low=$(dbtune_analysis_count all low)

    printf '# dbtune report\n\n'
    printf '_Vygenerované: %s | dbtune %s_\n\n' "$(dbtune_markdown_escape "$generated_at")" "$(dbtune_markdown_escape "$DBTUNE_VERSION")"
    printf "_Run: \`%s\` | audit SHA-256: \`%s\` | samples SHA-256: \`%s\`_\n\n" \
        "$(dbtune_markdown_escape "$DBTUNE_RUN_ID")" \
        "$(dbtune_markdown_escape "$DBTUNE_AUDIT_HASH")" \
        "$(dbtune_markdown_escape "$DBTUNE_SAMPLES_HASH")"
    printf '## Executive summary\n\n'
    printf '**Nálezy:** critical %s, high %s, medium %s, low %s.\n\n' "$critical" "$high" "$medium" "$low"
    dbtune_render_executive_actions
    printf '\n'
    dbtune_render_application_overview
    dbtune_render_server_profile
    dbtune_render_proposed_diff
    dbtune_render_per_app
    dbtune_render_security
    printf '## Ďalší postup\n\n'
    printf '1. Vyriešte aplikačné nálezy, najmä object cache, autoload, HPOS a wp-cron.\n'
    printf "2. Skontrolujte diff a vytvorte gated serverový súbor príkazom \`dbtune propose\`.\n"
    printf '3. Pred reštartom validujte názvy premenných a konfiguráciu; reštart vykonajte cez RunCloud panel.\n'
    printf "4. Po reštarte spustite \`dbtune verify --post\` a po 24 hodinách \`dbtune verify --24h\`.\n"
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
    local rule_prefix

    DBTUNE_JSON_FIELDS=(
        schema_version fleet-v2
        generated_at "$generated_at"
        dbtune_version "$DBTUNE_VERSION"
        run_id "$DBTUNE_RUN_ID"
        audit_hash "$DBTUNE_AUDIT_HASH"
        samples_hash "$DBTUNE_SAMPLES_HASH"
        findings.critical "$(dbtune_analysis_count all critical)"
        findings.high "$(dbtune_analysis_count all high)"
        findings.medium "$(dbtune_analysis_count all medium)"
        findings.low "$(dbtune_analysis_count all low)"
        samples.count "$(dbtune_samples_count "$DBTUNE_SAMPLES_FILE")"
        apps.count "$(dbtune_tsv_row_count "$DBTUNE_APPS_FILE" app)"
        databases.count "$(dbtune_tsv_row_count "$DBTUNE_DATABASES_FILE" database)"
    )
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
            "$rule_prefix.reason_sk" "$(dbtune_report_safe "$DBTUNE_ANALYSIS_REASON")"
        )
        [[ $DBTUNE_ANALYSIS_SCOPE == app:* ]] && app_rule_count=$((app_rule_count + 1))
        dbtune_security_rule && security_count=$((security_count + 1))
        index=$((index + 1))
    done
    DBTUNE_JSON_FIELDS+=(rules.count "$index" app_rules.count "$app_rule_count" security_findings.count "$security_count")
    dbtune_json_emit "${DBTUNE_JSON_FIELDS[@]}"
}

dbtune_cnf_comment() {
    local value
    value=$(dbtune_report_safe "${1:-}")
    value=${value//$'\r'/ }
    value=${value//$'\n'/ }
    value=${value//$'\t'/ }
    printf '%s' "$value"
}

dbtune_proposal_key_is_safe() {
    local key=${1:-}
    [[ $key =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] && ! dbtune_is_sensitive_key "$key"
}

dbtune_proposal_value_is_safe() {
    [[ ${1:-} =~ ^[[:alnum:]_./,:+-]+$ ]]
}

dbtune_proposal_template() {
    if declare -F dbtune_embedded_get >/dev/null 2>&1; then
        dbtune_embedded_get templates/tuning.cnf.tmpl
    else
        printf '%s\n' '# dbtune @DBTUNE_VERSION@, vygenerovane @GENERATED_AT@' '[mysqld]' '@RULES@'
    fi
}

dbtune_render_proposal_rules() {
    local line canonical seen=$'\n'

    for line in "${DBTUNE_ANALYSIS_LINES[@]}"; do
        dbtune_analysis_parse "$line" || continue
        [[ $DBTUNE_ANALYSIS_SCOPE == server && -n $DBTUNE_ANALYSIS_PROPOSED_KEY ]] || continue
        if ! dbtune_proposal_key_is_safe "$DBTUNE_ANALYSIS_PROPOSED_KEY" || ! dbtune_proposal_value_is_safe "$DBTUNE_ANALYSIS_PROPOSED_VALUE"; then
            dbtune_log warn "Preskakujem nebezpecny navrh z pravidla $DBTUNE_ANALYSIS_RULE_ID"
            continue
        fi
        canonical=$(dbtune_key_normalize "$DBTUNE_ANALYSIS_PROPOSED_KEY")
        if [[ $seen == *$'\n'"$canonical"$'\n'* ]]; then
            dbtune_log warn "Preskakujem duplicitny navrh kluca $DBTUNE_ANALYSIS_PROPOSED_KEY"
            continue
        fi
        seen+="$canonical"$'\n'
        printf '# %s [%s]: %s\n' \
            "$(dbtune_cnf_comment "$DBTUNE_ANALYSIS_RULE_ID")" \
            "$(dbtune_cnf_comment "$DBTUNE_ANALYSIS_SEVERITY")" \
            "$(dbtune_cnf_comment "$DBTUNE_ANALYSIS_REASON")"
        [[ -z $DBTUNE_ANALYSIS_EVIDENCE ]] || printf '# Evidencia: %s\n' "$(dbtune_cnf_comment "$DBTUNE_ANALYSIS_EVIDENCE")"
        printf '%s = %s\n\n' "$DBTUNE_ANALYSIS_PROPOSED_KEY" "$DBTUNE_ANALYSIS_PROPOSED_VALUE"
    done
}

dbtune_render_proposal() {
    local generated_at=${1:-}
    local line

    while IFS= read -r line || [[ -n $line ]]; do
        line=${line//@DBTUNE_VERSION@/$DBTUNE_VERSION}
        line=${line//@GENERATED_AT@/$generated_at}
        if [[ $line == '@RULES@' ]]; then
            dbtune_render_proposal_rules
        else
            printf '%s\n' "$line"
        fi
    done < <(dbtune_proposal_template)
}

# Funkciu vola CLI dispatcher aj collector bez argumentov.
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
    dbtune_provenance_validate_analysis || return
    analysis_manifest=$(dbtune_analysis_manifest_file) || return
    DBTUNE_RUN_ID=$(dbtune_manifest_value "$analysis_manifest" run_id) || return 65
    DBTUNE_AUDIT_HASH=$(dbtune_manifest_value "$analysis_manifest" audit_hash) || return 65
    DBTUNE_SAMPLES_HASH=$(dbtune_manifest_value "$analysis_manifest" samples_hash) || return 65
    for report_file in "$DBTUNE_AUDIT_FILE" "$DBTUNE_SAMPLES_FILE" "$DBTUNE_ANALYSIS_FILE"; do
        if [[ ! -r $report_file ]]; then
            dbtune_log error "Chyba povinny vstup: $report_file"
            return 66
        fi
    done

    dbtune_analysis_load "$DBTUNE_ANALYSIS_FILE"
    generated_at=$(dbtune_now)
    markdown=$(dbtune_render_markdown "$generated_at") || return
    json=$(dbtune_render_json "$generated_at") || return
    report_file=$(dbtune_report_markdown_file) || return
    json_file=$(dbtune_report_json_file) || return
    printf '%s\n' "$markdown" | dbtune_atomic_write "$report_file" 600 || return
    printf '%s\n' "$json" | dbtune_atomic_write "$json_file" 600 || return

    command cat "$report_file"
    printf '\nReport uložený: %s\nJSON uložený: %s\n' "$report_file" "$json_file"
}

cmd_propose() {
    local analysis_file proposal_file generated_at proposal state manifest_file analysis_manifest
    local temporary temporary_manifest run_id audit_hash samples_hash analysis_hash proposal_hash

    dbtune_report_no_arguments propose "$@" || return
    state=$(dbtune_state_read) || return
    if [[ $state != analyzed && $state != proposed ]]; then
        dbtune_log error "Prikaz 'propose' nie je povoleny v stave '$state'"
        return 65
    fi
    dbtune_init_state_dir || return
    dbtune_provenance_validate_analysis || return
    analysis_file=$(dbtune_path analysis.tsv) || return
    if [[ ! -r $analysis_file ]]; then
        dbtune_log error "Chyba povinny vstup: $analysis_file"
        return 66
    fi
    dbtune_analysis_load "$analysis_file"
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
    proposal_hash=$(dbtune_sha256_file "$temporary") || return
    manifest_file=$(dbtune_path proposal-manifest.tsv) || return
    {
        printf 'schema\t1\n'
        printf 'run_id\t%s\n' "$run_id"
        printf 'audit_hash\t%s\n' "$audit_hash"
        printf 'samples_hash\t%s\n' "$samples_hash"
        printf 'analysis_hash\t%s\n' "$analysis_hash"
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
    printf 'Návrh uložený: %s\n' "$proposal_file"
}
