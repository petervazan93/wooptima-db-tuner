dbtune_rules_version_family() {
    dbtune_audit_mariadb_version_family "${1:-}"
}

dbtune_rules_variable_gate() {
    local version=${1:-}
    local variable=${2:-}
    local family

    family=$(dbtune_rules_version_family "$version") || return
    if [[ $family == unsupported ]]; then
        printf 'unsupported\n'
        return 0
    fi

    awk -v version="$version" -v variable="$variable" 'BEGIN {
        split(version, v, ".")
        major = v[1] + 0
        minor = v[2] + 0
        gsub(/-/, "_", variable)
        if (variable == "innodb_change_buffering") {
            print (major >= 11 ? "removed" : "static")
        } else if (variable == "innodb_buffer_pool_instances" || variable == "innodb_log_files_in_group") {
            print "removed"
        } else if (variable == "innodb_flush_method" && major >= 11) {
            print "deprecated"
        } else if (variable == "innodb_log_file_size") {
            print ((major > 10 || (major == 10 && minor >= 9)) ? "dynamic" : "restart")
        } else if (variable == "innodb_read_io_threads" || variable == "innodb_write_io_threads") {
            print ((major > 10 || (major == 10 && minor >= 11)) ? "dynamic" : "restart")
        } else if (variable == "query_cache_type") {
            print "restart-if-disabled-at-startup"
        } else {
            print "dynamic"
        }
    }'
}

dbtune_rules_percentile() {
    local file=${1:-}
    local column=${2:-}
    local percentile=${3:-}

    dbtune_tsv_percentile "$file" "$column" 1 "$percentile"
}

dbtune_rules_proposable_variables() {
    dbtune_audit_effective_variables
}

dbtune_rules_analyze() {
    local audit_file=${1:-}
    local samples_file=${2:-}
    local dbsize_file=${3:-}
    local apps_file=${4:-}
    local databases_file=${5:-}
    local min_samples=${6:-288}
    local p95_threads p50_qcache p05_available diagnostics rejected excluded_status excluded_restart
    local normalized_audit result

    [[ -r $audit_file && -r $samples_file ]] || return 66
    diagnostics=$(dbtune_samples_diagnostics "$samples_file") || return 65
    rejected=$(awk -F '\t' '$1 == "rejected_rows" { print $2 }' <<<"$diagnostics")
    excluded_status=$(awk -F '\t' '$1 == "excluded_status_rows" { print $2 }' <<<"$diagnostics")
    excluded_restart=$(awk -F '\t' '$1 == "excluded_restart_rows" { print $2 }' <<<"$diagnostics")
    if ((rejected > 0)); then
        printf 'dbtune: odmietnute vzorky: %s; %s\n' "$rejected" \
            "$(awk -F '\t' '$1 == "rejected_reasons" { print $2 }' <<<"$diagnostics")" >&2
    fi
    p95_threads=$(dbtune_tsv_percentile "$samples_file" threads_running 8 95) || return 65
    p05_available=$(dbtune_tsv_percentile "$samples_file" mem_available_kb 14 5) || return 65
    p50_qcache=$(dbtune_tsv_percentile "$samples_file" qcache_hit_pct 10 50 qcache-active 2>/dev/null || printf '0')
    normalized_audit=$(mktemp "${TMPDIR:-/tmp}/dbtune-audit-normalized.XXXXXX") || return 1
    if ! chmod 600 "$normalized_audit" || ! dbtune_audit_normalize "$audit_file" >"$normalized_audit"; then
        rm -f "$normalized_audit"
        return 65
    fi
    awk -v audit_file="$normalized_audit" -v samples_file=<(dbtune_samples_valid_rows "$samples_file") \
        -v dbsize_file="$dbsize_file" -v apps_file="$apps_file" \
        -v databases_file="$databases_file" -v min_samples="$min_samples" \
        -v shared_p95_threads="$p95_threads" -v shared_p50_qcache="$p50_qcache" \
        -v shared_p05_available="$p05_available" -v shared_rejected_count="$rejected" \
        -v shared_excluded_count="$((excluded_status + excluded_restart))" '
    BEGIN {
        FS = OFS = "\t"
        gib = 1073741824
        mib = 1048576
        load_audit(audit_file)
        load_samples(samples_file)
        if (sample_count < min_samples) {
            printf "dbtune: malo vzoriek: %d, minimum: %d\n", sample_count, min_samples > "/dev/stderr"
            exit 65
        }
        load_dbsize(dbsize_file)
        load_table(apps_file, "app")
        load_table(databases_file, "database")

        print "rule_id", "scope", "severity", "verdict", "proposed_key", "proposed_value", "evidence", "reason_sk"
        server_rules()
        app_rules()
    }

    function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
    }

    function norm(value) {
        value = tolower(trim(value))
        gsub(/[^a-z0-9]+/, "_", value)
        sub(/^_+/, "", value)
        sub(/_+$/, "", value)
        return value
    }

    function canon(key) {
        if (key ~ /^mariadb_variable_/) return substr(key, 18)
        if (key ~ /^mariadb_status_/) return substr(key, 16)
        if (key == "version" || key == "mariadb" || key == "mariadb_server_version") return "mariadb_version"
        if (key == "hw_ram_bytes" || key == "memory_total_bytes") return "ram_total_bytes"
        if (key == "hw_ram_available_bytes") return "mem_available_bytes"
        if (key == "memory_total_kb" || key == "mem_total_kb" || key == "ram_kb") return "ram_total_kb"
        if (key == "mariadb_dataset_bytes") return "dataset_bytes"
        if (key == "database_size_bytes" || key == "total_dataset_bytes" || key == "db_size_bytes") return "dataset_bytes"
        if (key == "buffer_pool_size") return "innodb_buffer_pool_size"
        if (key == "php_fpm_max_children_sum") return "pm_max_children_sum"
        if (key == "php_fpm_max_children" || key == "pm_max_children" || key == "fpm_max_children_sum") return "pm_max_children_sum"
        if (key == "max_connections_used" || key == "peak_connections") return "max_used_connections"
        if (key == "hw_storage_class") return "storage_class"
        if (key == "disk_class" || key == "storage_type") return "storage_class"
        if (key == "runcloud_skip_log_bin") return "skip_log_bin"
        if (key == "security_remote_grant_count") return "remote_grant_count"
        if (key == "security_port_3306") return "port_3306"
        if (key == "security_root_cnf_present") return "root_cnf_present"
        if (key == "limit_nofile") return "systemd_limit_nofile"
        if (key == "effective_open_files_limit") return "open_files_limit"
        if (key == "unattended_mariadb") return "unattended_mariadb_origin"
        if (key == "backup") return "backup_enabled"
        return key
    }

    function load_audit(file, line, pos, key, value) {
        while ((getline line < file) > 0) {
            sub(/\r$/, "", line)
            pos = index(line, "\t")
            if (!pos) continue
            key = canon(norm(substr(line, 1, pos - 1)))
            value = trim(substr(line, pos + 1))
            if (key == "key" && norm(value) == "value") continue
            audit[key] = value
            present[key] = 1
        }
        close(file)
    }

    function require_sample_columns(header, columns, required, n, i) {
        n = split("timestamp uptime bp_hit_pct bp_misses_s data_read_s rnd_next_s tmp_disk_pct threads_running threads_connected qcache_hit_pct log_waits_delta wait_free_delta cpu_pct mem_available_kb swap_used_kb load1 restart_flag", required, " ")
        for (i = 1; i <= n; i++) if (!(required[i] in columns)) return 0
        return 1
    }

    function load_samples(file, line, fields, header, n, i, value, status, restart, denominator, hit_text) {
        if ((getline line < file) <= 0) {
            print "dbtune: samples.tsv je prazdny" > "/dev/stderr"
            exit 65
        }
        sub(/\r$/, "", line)
        n = split(line, fields, "\t")
        for (i = 1; i <= n; i++) header[norm(fields[i])] = i
        if (!require_sample_columns(line, header)) {
            print "dbtune: samples.tsv nema pozadovanu hlavicku" > "/dev/stderr"
            exit 65
        }
        while ((getline line < file) > 0) {
            sub(/\r$/, "", line)
            if (line == "") continue
            n = split(line, fields, "\t")
            if (fields[header["timestamp"]] == "") continue
            status = ("sample_status" in header) ? trim(fields[header["sample_status"]]) : "ok"
            restart = numeric(fields[header["restart_flag"]])
            if (status != "ok" || restart != 0) {
                degraded_sample_count++
                continue
            }
            sample_count++
            value = numeric(fields[header["threads_running"]]); threads_running[sample_count] = value
            value = numeric(fields[header["threads_connected"]]); threads_connected[sample_count] = value
            value = numeric(fields[header["mem_available_kb"]]); mem_available[sample_count] = value
            value = numeric(fields[header["log_waits_delta"]]); log_waits_total += value
            value = numeric(fields[header["wait_free_delta"]]); wait_free_total += value
            if (threads_connected[sample_count] > peak_connected) peak_connected = threads_connected[sample_count]
            if (!("qcache_queries_delta" in header)) {
                qcache_unavailable_count++
                continue
            }
            denominator = trim(fields[header["qcache_queries_delta"]])
            hit_text = trim(fields[header["qcache_hit_pct"]])
            if (denominator !~ /^[0-9]+([.][0-9]+)?$/ || hit_text !~ /^[0-9]+([.][0-9]+)?$/ || hit_text + 0 < 0 || hit_text + 0 > 100) {
                qcache_unavailable_count++
            } else if (denominator + 0 > 0) {
                qcache_hit[++qcache_active_count] = hit_text + 0
            } else {
                qcache_idle_count++
            }
        }
        close(file)
        degraded_sample_count = shared_excluded_count + 0
        rejected_sample_count = shared_rejected_count + 0
        p95_threads = shared_p95_threads + 0
        p50_qcache = shared_p50_qcache + 0
        p05_available_kb = shared_p05_available + 0
    }

    function load_dbsize(file, line, fields, date, database, timestamp, size_text, size, n, i, key, elapsed, delta, magnitude, threshold, valid_delta, valid_days) {
        if (file == "" || (getline line < file) <= 0) return
        while ((getline line < file) > 0) {
            sub(/\r$/, "", line)
            n = split(line, fields, "\t")
            timestamp = trim(fields[1])
            database = trim(fields[2])
            date = substr(timestamp, 1, 10)
            size_text = trim(fields[3])
            if (n < 3 || timestamp == "" || database == "" || date_ordinal(date) <= 0 || size_text !~ /^[0-9]+([.][0-9]+)?$/) continue
            size = size_text + 0
            key = timestamp SUBSEP database
            if (!(key in snapshot_size)) {
                snapshot_count[timestamp]++
                if (!(timestamp in snapshot_seen)) {
                    snapshot_seen[timestamp] = 1
                    snapshot_day[timestamp] = date
                    snapshots[++snapshot_total] = timestamp
                }
            }
            snapshot_size[key] = size
        }
        close(file)
        for (i = 1; i <= snapshot_total; i++) {
            timestamp = snapshots[i]
            date = snapshot_day[timestamp]
            if (snapshot_count[timestamp] > day_database_count[date]) day_database_count[date] = snapshot_count[timestamp]
        }
        for (i = 1; i <= snapshot_total; i++) {
            timestamp = snapshots[i]
            date = snapshot_day[timestamp]
            if (snapshot_count[timestamp] == day_database_count[date] && (!(date in day_snapshot) || timestamp > day_snapshot[date]))
                day_snapshot[date] = timestamp
        }
        for (key in snapshot_size) {
            split(key, fields, SUBSEP)
            timestamp = fields[1]
            database = fields[2]
            date = snapshot_day[timestamp]
            if (day_snapshot[date] == timestamp) day_size[date] += snapshot_size[key]
        }
        for (date in day_snapshot) {
            day_seen[date] = 1
            dates[++day_count] = date
        }
        sort_text(dates, day_count)
        if (day_count > 0) latest_dbsize = day_size[dates[day_count]]
        if (day_count >= 5) {
            growth_elapsed_days = date_ordinal(dates[day_count]) - date_ordinal(dates[1])
            for (i = 2; i <= day_count; i++) {
                elapsed = date_ordinal(dates[i]) - date_ordinal(dates[i - 1])
                if (elapsed <= 0) continue
                delta = day_size[dates[i]] - day_size[dates[i - 1]]
                magnitude = delta < 0 ? -delta : delta
                threshold = max(gib, day_size[dates[i - 1]] * 0.25)
                if (magnitude > threshold) {
                    discontinuity_count++
                    if (magnitude > discontinuity_largest) {
                        discontinuity_largest = magnitude
                        discontinuity_date = dates[i]
                    }
                    continue
                }
                valid_delta += delta
                valid_days += elapsed
            }
            growth_valid_days = valid_days
            daily_growth = valid_days > 0 ? valid_delta / valid_days : 0
            if (daily_growth < 0) daily_growth = 0
            growth_180 = daily_growth * 180
        }
    }

    function date_ordinal(date, parts, offsets, year, month, day, days, limit) {
        if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
        split(date, parts, "-")
        year = parts[1] + 0
        month = parts[2] + 0
        day = parts[3] + 0
        if (year < 1 || month < 1 || month > 12) return 0
        split("0 31 59 90 120 151 181 212 243 273 304 334", offsets, " ")
        limit = month == 2 ? (is_leap_year(year) ? 29 : 28) : (month == 4 || month == 6 || month == 9 || month == 11 ? 30 : 31)
        if (day < 1 || day > limit) return 0
        days = 365 * (year - 1) + int((year - 1) / 4) - int((year - 1) / 100) + int((year - 1) / 400)
        days += offsets[month] + day
        if (month > 2 && is_leap_year(year)) days++
        return days
    }

    function is_leap_year(year) {
        return year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
    }

    function load_table(file, kind, first, fields, columns, line, n, i, id, key, value, pos, flatkey, parts, count) {
        if (file == "" || (getline first < file) <= 0) return
        sub(/\r$/, "", first)
        n = split(first, fields, "\t")
        if (n == 3 && norm(fields[1]) != "scope" && norm(fields[2]) != "key") {
            load_scoped(kind, fields[1], fields[2], fields[3])
            while ((getline line < file) > 0) {
                sub(/\r$/, "", line)
                if (split(line, fields, "\t") == 3) load_scoped(kind, fields[1], fields[2], fields[3])
            }
            close(file)
            return
        }
        if (n == 2 && norm(fields[1]) == "key" && norm(fields[2]) == "value") {
            while ((getline line < file) > 0) {
                sub(/\r$/, "", line)
                pos = index(line, "\t")
                if (!pos) continue
                flatkey = substr(line, 1, pos - 1)
                value = trim(substr(line, pos + 1))
                gsub(/^app[:.]/, "", flatkey)
                count = split(flatkey, parts, /[.:]/)
                if (count < 2) continue
                id = parts[1]
                key = ""
                for (i = 2; i <= count; i++) key = key (key == "" ? "" : "_") parts[i]
                add_app(id, key, value)
            }
            close(file)
            return
        }
        for (i = 1; i <= n; i++) columns[i] = norm(fields[i])
        while ((getline line < file) > 0) {
            sub(/\r$/, "", line)
            if (line == "") continue
            n = split(line, fields, "\t")
            id = ""
            for (i = 1; i <= n; i++) {
                key = columns[i]
                if (key == "app_id" || key == "app" || key == "app_name" || key == "path") id = fields[i]
            }
            if (id == "") {
                for (i = 1; i <= n; i++) if (columns[i] == "database" || columns[i] == "db") id = fields[i]
            }
            if (id == "") continue
            for (i = 1; i <= n; i++) add_app(id, columns[i], fields[i])
        }
        close(file)
    }

    function load_scoped(kind, scope, key, value, parts, kbrow) {
        key = norm(key)
        if (kind == "app") {
            add_app(scope, key, value)
            if (key == "type" && tolower(value) == "wordpress") add_app(scope, "is_wp", "1")
            return
        }
        if (scope in app_seen) {
            add_app(scope, key, value)
            if (key ~ /^log_table_/) {
                split(value, parts, ":")
                kbrow = numeric(parts[4])
                if (kbrow > numeric(av(scope, "max_log_kb_per_row"))) add_app(scope, "max_log_kb_per_row", kbrow)
            }
            return
        }
    }

    function add_app(id, key, value) {
        id = trim(id)
        key = norm(key)
        if (id == "" || key == "") return
        if (!(id in app_seen)) {
            app_seen[id] = 1
            app_ids[++app_count] = id
        }
        app[id SUBSEP key] = trim(value)
    }

    function ag(key, fallback) {
        key = canon(norm(key))
        return (key in present) ? audit[key] : fallback
    }

    function av(id, k1, k2, k3, k4, k5, value) {
        if ((id SUBSEP norm(k1)) in app) return app[id SUBSEP norm(k1)]
        if (k2 != "" && (id SUBSEP norm(k2)) in app) return app[id SUBSEP norm(k2)]
        if (k3 != "" && (id SUBSEP norm(k3)) in app) return app[id SUBSEP norm(k3)]
        if (k4 != "" && (id SUBSEP norm(k4)) in app) return app[id SUBSEP norm(k4)]
        if (k5 != "" && (id SUBSEP norm(k5)) in app) return app[id SUBSEP norm(k5)]
        return ""
    }

    function app_source_error(id, sources, include_failed, requested, count, i, key, value, result, status) {
        status = tolower(av(id, "audit_status"))
        count = split(sources, requested, " ")
        for (i = 1; i <= count; i++) {
            key = "audit_error_" requested[i]
            value = av(id, key)
            if (value != "") result = result (result == "" ? "" : ",") "audit_error." requested[i] "=" value
        }
        if (result == "" && include_failed && status == "failed") {
            result = av(id, "source_error")
            if (result == "none") result = "audit_status=failed"
        }
        return result
    }

    function numeric(value) {
        value = trim(value)
        gsub(/,/, ".", value)
        return value ~ /^-?[0-9]+([.][0-9]+)?$/ ? value + 0 : 0
    }

    function bytes(value, number, unit) {
        value = toupper(trim(value))
        gsub(/[[:space:]]/, "", value)
        if (value ~ /^[0-9]+([.][0-9]+)?$/) return value + 0
        unit = substr(value, length(value), 1)
        number = substr(value, 1, length(value) - 1) + 0
        if (unit == "K") return number * 1024
        if (unit == "M") return number * 1048576
        if (unit == "G") return number * 1073741824
        if (unit == "T") return number * 1099511627776
        return 0
    }

    function truth(value) {
        value = tolower(trim(value))
        return value == "1" || value == "yes" || value == "true" || value == "on" || value == "enabled" || value == "active"
    }

    function falsehood(value) {
        value = tolower(trim(value))
        return value == "0" || value == "no" || value == "false" || value == "off" || value == "disabled" || value == "inactive"
    }

    function sort_text(values, count, i, j, swap) {
        for (i = 2; i <= count; i++) {
            swap = values[i]
            j = i - 1
            while (j >= 1 && values[j] > swap) { values[j + 1] = values[j]; j-- }
            values[j + 1] = swap
        }
    }

    function min(a, b) { return a < b ? a : b }
    function max(a, b) { return a > b ? a : b }
    function ceil(value) { return value == int(value) ? value : int(value) + 1 }

    function clean(value) {
        gsub(/[\t\r\n]+/, " ", value)
        gsub(/[[:space:]]+/, " ", value)
        return trim(value)
    }

    function emit(rule, scope, severity, verdict, key, value, evidence, reason) {
        print clean(rule), clean(scope), clean(severity), clean(verdict), clean(key), clean(value), clean(evidence), clean(reason)
    }

    function format_size(value) {
        if (value >= gib && int(value / gib) == value / gib) return sprintf("%dG", value / gib)
        return sprintf("%dM", int(value / mib))
    }

    function same_size(current, target) {
        return current != "" && bytes(current) == bytes(target)
    }

    function setting(rule, key, target, severity, evidence, reason, current) {
        current = ag(key, "")
        if (current == "" || tolower(current) == "unknown") {
            emit(rule, "server", severity, "UNKNOWN", "", "", evidence "; current=missing; proposal_blocked=missing-current", reason)
            return
        }
        if (tolower(current) == tolower(target)) emit(rule, "server", "info", "OK", "", "", evidence "; current=" current, reason)
        else emit(rule, "server", severity, "CHANGE", key, target, evidence "; current=" current, reason)
    }

    function size_setting(rule, key, target, severity, evidence, reason, current) {
        current = ag(key, "")
        if (current == "" || tolower(current) == "unknown") {
            emit(rule, "server", severity, "UNKNOWN", "", "", evidence "; current=missing; proposal_blocked=missing-current", reason)
            return
        }
        if (same_size(current, target)) emit(rule, "server", "info", "OK", "", "", evidence "; current=" current, reason)
        else emit(rule, "server", severity, "CHANGE", key, target, evidence "; current=" current, reason)
    }

    function durability_setting(rule, key, target, severity, evidence, reason, current) {
        current = ag(key, "")
        evidence = evidence "; durability_exception=explicit"
        if (current == "" || tolower(current) == "unknown") {
            emit(rule, "server", severity, "UNKNOWN", "", "", evidence "; current=missing; proposal_blocked=missing-current", reason)
            return
        }
        if (tolower(current) == tolower(target)) emit(rule, "server", "info", "OK", "", "", evidence "; current=" current, reason)
        else emit(rule, "server", severity, "CHANGE", key, target, evidence "; current=" current, reason)
    }

    function version_parts(version) {
        split(version, version_number, ".")
        if (version_number[1] !~ /^[0-9]+$/ || version_number[2] !~ /^[0-9]+$/) {
            version_major = version_minor = 0
            version_family = "unsupported"
            return
        }
        version_major = version_number[1] + 0
        version_minor = version_number[2] + 0
        if (version_major == 11) version_family = "11.x"
        else if (version_major == 10 && version_minor == 11) version_family = "10.11"
        else if (version_major == 10 && version_minor == 6) version_family = "10.6"
        else version_family = "unsupported"
    }

    function buffer_pool_rule(dataset, ram, current, raw, ram_cap, reserve, available, safe_cap, target, step, evidence) {
        dataset = bytes(ag("dataset_bytes", "0"))
        if (latest_dbsize > dataset) dataset = latest_dbsize
        ram = bytes(ag("ram_total_bytes", "0"))
        if (ram <= 0) ram = numeric(ag("ram_total_kb", "0")) * 1024
        current = bytes(ag("innodb_buffer_pool_size", "0"))
        if (!("innodb_buffer_pool_size" in present) || current <= 0) {
            emit("R-BP-SIZE", "server", "high", "UNKNOWN", "", "", "current=missing; proposal_blocked=missing-current", "Chyba efektivna hodnota buffer poolu; zmena sa nesmie navrhnut naslepo.")
            return
        }
        if (dataset <= 0 || ram <= 0) {
            emit("R-BP-SIZE", "server", "high", "UNKNOWN", "", "", "dataset_bytes=" dataset "; ram_bytes=" ram, "Chybaju data pre bezpecny vypocet buffer poolu.")
            return
        }
        raw = (dataset + growth_180) * 1.3
        ram_cap = ram * 0.5
        target = min(raw, ram_cap)
        step = 256 * mib
        target = ceil(target / step) * step
        if (target > ram_cap) target = int(ram_cap / step) * step

        available = p05_available_kb * 1024
        if (available <= 0) available = bytes(ag("mem_available_bytes", "0"))
        if (available <= 0) available = numeric(ag("mem_available_kb", "0")) * 1024
        reserve = max(gib, ram * 0.1)
        if (available > 0) {
            safe_cap = current + max(0, available - reserve)
            if (target > safe_cap) target = int(safe_cap / step) * step
        }
        evidence = sprintf("dataset=%.2fG; growth_points=%d; growth_elapsed_days=%d; growth_valid_days=%d; growth_180d=%.2fG; discontinuities=%d; ram=%.2fG; mem_available_p05=%.2fG", dataset / gib, day_count, growth_elapsed_days, growth_valid_days, growth_180 / gib, discontinuity_count, ram / gib, available / gib)
        if (target <= current && current > 0) {
            emit("R-BP-SIZE", "server", "info", "NO-SHRINK", "", "", evidence "; current=" format_size(current), "Existujuci pool sa automaticky nezmensuje; zmensovanie je rusiva operacia.")
        } else if (target < step) {
            emit("R-BP-SIZE", "server", "high", "MEMORY-GUARD", "", "", evidence, "MemAvailable guard nedovoluje bezpecne zvysenie poolu.")
        } else {
            emit("R-BP-SIZE", "server", "high", "CHANGE", "innodb_buffer_pool_size", format_size(target), evidence, "Pool je min((dataset plus kladny sestmesacny rast) krat 1,3; RAM krat 0,5), s MemAvailable guardom a zaokruhlenim na 256M.")
        }
    }

    function growth_evidence_rule() {
        if (discontinuity_count > 0)
            emit("R-BP-GROWTH", "server", "medium", "REVIEW", "", "", sprintf("discontinuities=%d; largest_jump=%.2fG; date=%s; excluded_from_growth=true", discontinuity_count, discontinuity_largest / gib, discontinuity_date), "Skok nad adaptivny prah 25 percent, minimalne 1 GiB, vyzera ako import alebo diskontinuita; z projekcie rastu je vyluceny.")
    }

    function max_connections_rule(workers, peak, formula, peak_floor, target, current, current_text, evidence, ols, worker_status) {
        workers = numeric(ag("pm_max_children_sum", "0"))
        peak = max(numeric(ag("max_used_connections", "0")), peak_connected)
        ols = truth(ag("php_fpm_ols_stack", ""))
        if (ols || !("pm_max_children_sum" in present) || workers <= 0) {
            worker_status = ols ? "ols-unavailable" : (("pm_max_children_sum" in present) ? "invalid" : "missing")
            evidence = sprintf("pm.max_children_sum=%d; worker_limit=%s; ols_stack=%s; measured_peak=%d", workers, worker_status, ag("php_fpm_ols_stack", "unknown"), peak)
            emit("R-MAXCONN", "server", "high", "UNKNOWN", "", "", evidence, "Bez autoritativneho limitu PHP-FPM alebo OLS workerov sa max_connections nesmie odhadovat ani pri nizkom peaku.")
            return
        }
        formula = max(100, ceil(workers * 1.25 + 20))
        peak_floor = ceil(peak * 1.25)
        target = max(formula, peak_floor)
        evidence = sprintf("pm.max_children_sum=%d; measured_peak=%d; formula=%d; peak_floor=%d", workers, peak, formula, peak_floor)
        current_text = ag("max_connections", "")
        if (current_text !~ /^[0-9]+$/) {
            emit("R-MAXCONN", "server", "high", "UNKNOWN", "", "", evidence "; current=missing; proposal_blocked=missing-current", "Chyba efektivna hodnota max_connections; zmena sa nesmie navrhnut naslepo.")
            return
        }
        current = numeric(current_text)
        if (current == target) emit("R-MAXCONN", "server", "info", "OK", "", "", evidence, "Limit pokryva PHP-FPM aj 25-percentnu rezervu nad nameranym peakom.")
        else emit("R-MAXCONN", "server", "high", "CHANGE", "max_connections", target, evidence, "Pouziva sa vacsia hodnota zo vzorca PHP-FPM a 25-percentnej rezervy nad realnym peakom.")
    }

    function io_rule(storage, capacity, capacity_max, threads, neighbors, dynamic) {
        storage = tolower(ag("storage_class", ""))
        if (storage == "" && truth(ag("storage_nvme", ""))) storage = "nvme"
        if (storage == "" && truth(ag("storage_rotational", ""))) storage = "hdd"
        if (storage == "" && falsehood(ag("storage_rotational", ""))) storage = "ssd"
        if (storage ~ /nvme/) { capacity = 2000; capacity_max = 6000; threads = 8; neighbors = 0 }
        else if (storage ~ /ssd|sata/) { capacity = 1000; capacity_max = 2000; threads = 4; neighbors = 0 }
        else if (storage ~ /hdd|rot/) { capacity = 200; capacity_max = 400; threads = 4; neighbors = 1 }
        else {
            emit("R-IO-CAP", "server", "high", "UNKNOWN", "", "", "storage_class=unknown", "Bez triedy uloziska sa IO kapacity nesmu hadat.")
            return
        }
        dynamic = (version_major > 10 || (version_major == 10 && version_minor >= 11)) ? "dynamic" : "restart"
        setting("R-IO-CAP", "innodb_io_capacity", capacity, "medium", "storage=" storage, "Kapacita zodpoveda triede uloziska.")
        setting("R-IO-CAP", "innodb_io_capacity_max", capacity_max, "medium", "storage=" storage, "Spickova IO kapacita zodpoveda triede uloziska.")
        setting("R-IO-CAP", "innodb_read_io_threads", threads, "medium", "storage=" storage "; gate=" dynamic, "NVMe pouziva osem IO vlakien, ostatne uloziska styri.")
        setting("R-IO-CAP", "innodb_write_io_threads", threads, "medium", "storage=" storage "; gate=" dynamic, "NVMe pouziva osem IO vlakien, ostatne uloziska styri.")
        setting("R-IO-CAP", "innodb_flush_neighbors", neighbors, "medium", "storage=" storage, "Susedne stranky sa oplati flushovat iba na rotacnom disku.")
    }

    function qcache_rule(hit, threads, evidence) {
        hit = p50_qcache
        threads = p95_threads
        evidence = sprintf("qcache_hit_p50=%.2f%%; active_windows=%d; required=%d; idle_windows=%d; unavailable_windows=%d; degraded_windows=%d; rejected_windows=%d; threads_running_p95=%.2f", hit, qcache_active_count, min_samples, qcache_idle_count, qcache_unavailable_count, degraded_sample_count, rejected_sample_count, threads)
        if (qcache_active_count < min_samples) {
            emit("R-QCACHE", "server", "medium", "UNKNOWN", "", "", evidence, "Query cache nema dost aktivnych okien s nenulovym poctom query; idle okna sa do hit-rate percentilu nerataju.")
            return
        }
        if (hit < 20 || threads > 8) {
            setting("R-QCACHE", "query_cache_type", "0", "high", evidence, "Query cache sa vypina pri hit rate pod 20 percent alebo p95 Threads_running nad 8.")
            size_setting("R-QCACHE", "query_cache_size", "0", "high", evidence, "Pri vypnutom query cache sa uvolni aj jeho pamat.")
        } else {
            emit("R-QCACHE", "server", "info", "KEEP", "", "", evidence, "Hit rate aspon 20 percent a p95 Threads_running najviac 8 hovoria query cache ponechat.")
        }
    }

    function gate_rules() {
        if (version_family == "unsupported") {
            emit("R-VERSION", "server", "critical", "UNSUPPORTED", "", "", "version=" ag("mariadb_version", "unknown"), "Podporovane su MariaDB 10.6, 10.11 a 11.x.")
            return
        }
        if (version_major >= 11 && (present["config_innodb_change_buffering"] || present["landmine_innodb_change_buffering_severity"] || truth(ag("landmine_innodb_change_buffering", ""))))
            emit("R-VERSION", "server", "critical", "REMOVED", "", "", "innodb_change_buffering; family=" version_family, "Premenna je od MariaDB 11 odstranena a moze zablokovat dalsi start.")
        if (present["config_innodb_buffer_pool_instances"] || present["landmine_innodb_buffer_pool_instances_severity"] || truth(ag("landmine_innodb_buffer_pool_instances", "")))
            emit("R-VERSION", "server", "critical", "REMOVED", "", "", "innodb_buffer_pool_instances; family=" version_family, "Odstranena premenna patri prec z konfiguracie pred restartom.")
        if (present["config_innodb_log_files_in_group"] || present["landmine_innodb_log_files_in_group_severity"] || truth(ag("landmine_innodb_log_files_in_group", "")))
            emit("R-VERSION", "server", "critical", "REMOVED", "", "", "innodb_log_files_in_group; family=" version_family, "Odstranena premenna patri prec z konfiguracie pred restartom.")
        if (version_major >= 11)
            emit("R-VERSION", "server", "medium", "DEPRECATED", "", "", "innodb_flush_method; family=" version_family, "V MariaDB 11.x je flush_method deprecated; existujucu hodnotu over a nepridavaj novu naslepo.")
    }

    function pinned_rules() {
        durability_setting("R-PINNED", "innodb_doublewrite", "1", "high", "durability", "Doublewrite chrani stranky pri torn write.")
        if (version_major < 11) setting("R-PINNED", "innodb_flush_method", "O_DIRECT", "medium", "family=" version_family, "O_DIRECT obmedzi dvojite cachovanie dat.")
        setting("R-PINNED", "innodb_buffer_pool_dump_at_shutdown", "1", "medium", "warmup", "Dump a load poolu skracuje warm-up po restarte.")
        setting("R-PINNED", "innodb_buffer_pool_load_at_startup", "1", "medium", "warmup", "Dump a load poolu skracuje warm-up po restarte.")
        setting("R-PINNED", "innodb_max_dirty_pages_pct", "60", "medium", "flush", "Limit spinych stranok obmedzuje narazovy flush.")
        setting("R-PINNED", "innodb_max_dirty_pages_pct_lwm", "10", "medium", "flush", "Low-water mark spusti priebezny flush skor.")
        setting("R-PINNED", "innodb_lock_wait_timeout", "30", "medium", "connections", "Kratsi timeout neblokuje PHP-FPM workery 200 sekund.")
        setting("R-PINNED", "skip_name_resolve", "1", "medium", "local clients", "Lokalne aplikacie nepotrebuju reverzne DNS.")
        setting("R-PINNED", "thread_cache_size", "64", "low", "connections", "Cache obmedzi cenu vytvarania vlakien.")
        size_setting("R-PINNED", "tmp_table_size", "64M", "medium", "LONGTEXT remains disk-backed", "64M pomoze tabulkam bez BLOB/TEXT, ale LONGTEXT zostane na disku.")
        size_setting("R-PINNED", "max_heap_table_size", "64M", "medium", "must match tmp_table_size", "Limit musi sediet s tmp_table_size.")
        setting("R-PINNED", "table_definition_cache", "2000", "low", "wordpress tables", "Viac WP databaz potrebuje rezervu definicii tabuliek.")
    }

    function operational_rules(key_reads, backup_interval, bind, wildcard, configured, effective, backup_status, backup_source, backup_success, backup_evidence) {
        key_reads = numeric(ag("key_read_requests", "0"))
        if (key_reads > 0) emit("R-MYISAM", "server", "info", "KEEP", "", "", "Key_read_requests=" key_reads, "MyISAM sa pouziva, key buffer sa nesmie plosne zmensit.")
        else size_setting("R-MYISAM", "key_buffer_size", "32M", "low", "Key_read_requests=0", "Moderny WordPress MyISAM bezne nepouziva.")

        setting("R-SLOWLOG", "slow_query_log", "1", "medium", "persistent early warning", "Trvaly slow log je vcasny diagnosticky signal.")
        setting("R-SLOWLOG", "slow_query_log_file", "/var/log/mysql/slow.log", "medium", "covered by logrotate", "Cesta /var/log/mysql je pokryta MariaDB logrotate.")
        setting("R-SLOWLOG", "long_query_time", "2", "medium", "production threshold", "Dve sekundy su bezpecny trvaly produkcny prah.")
        setting("R-SLOWLOG", "log_slow_verbosity", "query_plan", "low", "mariadb-dumpslow compatible", "query_plan zachova uzitocny detail bez EXPLAIN vystupu.")

        if (truth(ag("unattended_mariadb_origin", "")) && !truth(ag("unattended_mariadb_blacklisted", "")))
            emit("R-UNATT", "server", "high", "ACTION", "", "", "MariaDB origin allowed; package blacklist missing", "Zakaz automaticky restart MariaDB a bezpecnostne aktualizacie planuj rucne.")
        else emit("R-UNATT", "server", "info", "OK", "", "", "unattended-upgrades audited", "Nenasiel sa nekontrolovany automaticky MariaDB upgrade.")

        configured = numeric(ag("configured_open_files_limit", ag("runcloud_open_files_limit", "0")))
        effective = numeric(ag("open_files_limit", "0"))
        if (numeric(ag("systemd_limit_nofile", "0")) > 0 && (effective < configured || effective < numeric(ag("systemd_limit_nofile", "0"))))
            emit("R-OPENFILES", "server", "medium", "SYSTEMD-LIMIT", "", "", "configured=" configured "; effective=" effective "; LimitNOFILE=" ag("systemd_limit_nofile", "unknown"), "open_files_limit sa riesi systemd drop-inom, nie MariaDB cnf.")
        else emit("R-OPENFILES", "server", "info", "OK", "", "", "effective=" effective, "Efektivny open files limit nie je zjavne zrezany.")

        bind = tolower(ag("bind_address", "")); wildcard = numeric(ag("remote_grant_count", ag("wildcard_grants", "0")))
        if (bind == "0.0.0.0" || bind == "*" || tolower(ag("port_3306", "")) == "public" || wildcard > 0)
            emit("R-SEC", "server", "high", "EXPOSED", "", "", "bind_address=" bind "; remote_grants=" wildcard "; listener=" ag("port_3306", "unknown"), "Ak nie je externy DB klient, obmedz listener a granty na localhost.")
        else emit("R-SEC", "server", "info", "OK", "", "", "bind_address=" bind "; remote_grants=" wildcard, "Audit nenasiel verejny listener ani vzdialeny grant.")
        if (truth(ag("root_cnf_present", "")) || truth(ag("root_cnf_has_password", ag("root_cnf_plaintext_password", ""))))
            emit("R-SEC", "server", "low", "CREDENTIAL-NOTE", "", "", "root.cnf contains a managed credential", "Heslo z root.cnf nikdy nevypisuj; pri rotacii ho zmen naraz v MariaDB aj v RunCloud subore.")

        backup_interval = numeric(ag("backup_interval_hours", "0"))
        backup_status = tolower(trim(ag("backup_status", "unknown")))
        backup_source = trim(ag("backup_source", "unknown"))
        backup_success = trim(ag("backup_last_success", "unknown"))
        backup_evidence = "status=" backup_status "; source=" backup_source "; checked_at=" ag("backup_checked_at", "unknown") "; last_success=" backup_success "; age_seconds=" ag("backup_age_seconds", "unknown") "; max_age_seconds=" ag("backup_max_age_seconds", "unknown") "; evidence_error=" ag("backup_evidence_error", "none") "; schedule_count=" ag("backup_schedule_count", "unknown") "; interval_hours=" backup_interval
        if (backup_status == "missing" && backup_source != "" && backup_source != "unknown")
            emit("R-BACKUP", "server", "critical", "MISSING", "", "", backup_evidence, "Potvrdena absencia zalohy blokuje tuning.")
        else if (backup_status != "verified" || backup_source == "" || backup_source == "unknown" || backup_success == "" || backup_success == "unknown" || backup_success == "none")
            emit("R-BACKUP", "server", "medium", "UNKNOWN", "", "", backup_evidence, "Stav zalohy nie je autoritativne overeny; pocet lokalnych planov sam o sebe zalohu nepotvrdzuje.")
        else if (backup_interval > 0 && backup_interval <= 3)
            emit("R-BACKUP", "server", "medium", "FREQUENT", "", "", backup_evidence, "Casty mydumper full scan moze vytvarat IO spicky; over realnu potrebu.")
        else emit("R-BACKUP", "server", "info", "OK", "", "", backup_evidence, "Zaloha je autoritativne overena.")
    }

    function server_rules(dataset, log_size, log_gate) {
        version_parts(ag("mariadb_version", "0.0"))
        gate_rules()
        if (version_family == "unsupported") return
        growth_evidence_rule()
        buffer_pool_rule()
        max_connections_rule()
        io_rule()
        dataset = bytes(ag("dataset_bytes", "0")); if (latest_dbsize > dataset) dataset = latest_dbsize
        log_size = dataset > 10 * gib ? "1G" : "512M"
        log_gate = (version_major > 10 || (version_major == 10 && version_minor >= 9)) ? "dynamic" : "restart"
        size_setting("R-LOG-FILE", "innodb_log_file_size", log_size, "medium", sprintf("dataset=%.2fG; gate=%s", dataset / gib, log_gate), "Dataset nad 10G pouziva 1G redo subor, mensi dataset 512M.")
        size_setting("R-LOG-BUF", "innodb_log_buffer_size", log_waits_total > 0 ? "64M" : "32M", log_waits_total > 0 ? "high" : "medium", "sum_log_waits_delta=" log_waits_total, "64M je odovodnene iba rastom Innodb_log_waits.")
        qcache_rule()
        if (truth(ag("skip_log_bin", "")) || falsehood(ag("log_bin", "")))
            durability_setting("R-TRXCOMMIT", "innodb_flush_log_at_trx_commit", "1", "critical", "skip-log-bin; no PITR", "Bez binlogu je redo jedina ochrana potvrdenych objednavok.")
        else emit("R-TRXCOMMIT", "server", "info", "REVIEW", "", "", "binary log enabled", "Pri zapnutom binlogu posud durability spolu so sync_binlog a PITR politikou.")
        pinned_rules()
        operational_rules()
    }

    function app_emit(rule, id, severity, verdict, evidence, reason) {
        emit(rule, "app:" id, severity, verdict, "", "", evidence, reason)
    }

    function app_unknown(rule, id, source) {
        app_emit(rule, id, "medium", "UNKNOWN", "audit_status=" tolower(av(id, "audit_status")) "; source_error=" source, "Zdrojove auditne data pre toto pravidlo nie su dostupne; nalez sa nesmie vyhodnotit ako zdravy ani prazdny.")
    }

    function app_rules(i, id, is_wp, is_woo, redis, cache, disabled_cron, system_cron, autoload, autoload_mb, hpos, orders, sync, kbrow, sessions, failed, retention, transient_count, transient_bytes, policy, meta_index, multisite, source, raw) {
        for (i = 1; i <= app_count; i++) {
            id = app_ids[i]
            is_wp = av(id, "is_wp", "wordpress", "wp_detected", "type")
            is_woo = av(id, "is_woocommerce", "woocommerce", "woo_detected")
            if (tolower(is_wp) == "wordpress") is_wp = 1
            if (!truth(is_wp) && !truth(is_woo)) continue

            multisite = av(id, "multisite_metrics")
            source = app_source_error(id, "multisite database table_prefix", 1)
            if (source != "") app_unknown("R-APP-MULTISITE", id, source)
            else if (tolower(multisite) == "unsupported" || tolower(multisite) == "unknown")
                app_emit("R-APP-MULTISITE", id, "medium", "UNKNOWN", "multisite_metrics=" multisite, "Multisite site prefixy neboli enumerovane; aplikacne DB metriky sa nesmu hodnotit ako zdrave.")

            redis = av(id, "redis_active", "redis_running", "redis")
            if (redis == "") redis = ag("app_redis_ping", ag("app_redis_service_active", ""))
            cache = av(id, "object_cache", "object_cache_dropin", "object_cache_php")
            source = app_source_error(id, "wp_root", 1)
            if (source != "") app_unknown("R-APP-OBJECT-CACHE", id, source)
            else if (truth(cache) && truth(redis))
                app_emit("R-APP-OBJECT-CACHE", id, "info", "OK", "redis=probe-success; dropin=present", "Persistent object cache ma drop-in aj uspesny Redis probe.")
            else if (falsehood(redis))
                app_emit("R-APP-OBJECT-CACHE", id, "critical", "REDIS-DOWN", "redis=" redis "; dropin=" (cache == "" ? "unknown" : cache), "Redis probe zlyhal; aplikacnu vrstvu ries pred DB tuningom.")
            else if (falsehood(cache) && truth(redis))
                app_emit("R-APP-OBJECT-CACHE", id, "critical", "DROPIN-MISSING", "redis=" redis "; dropin=" cache, "Redis sam nestaci; WordPress potrebuje wp-content/object-cache.php drop-in.")
            else
                app_emit("R-APP-OBJECT-CACHE", id, "medium", "UNKNOWN", "redis=" (redis == "" ? "unknown" : redis) "; dropin=" (cache == "" ? "unknown" : cache), "Drop-in aj Redis probe musia byt potvrdene; neznamy stav nie je zdravy stav.")

            disabled_cron = av(id, "disable_wp_cron", "wp_cron_disabled")
            system_cron = av(id, "system_wp_cron", "wp_cron_system", "cron_present")
            if (system_cron == "") system_cron = ag("app_system_wp_cron", "")
            source = app_source_error(id, "wp_config disable_wp_cron", 1)
            if (source == "" && truth(disabled_cron) && tolower(system_cron) == "unknown") source = app_source_error(id, "site_url", 0)
            if (source != "") app_unknown("R-APP-WPCRON", id, source)
            else if (truth(disabled_cron) && falsehood(system_cron)) app_emit("R-APP-WPCRON", id, "critical", "DISABLED", "DISABLE_WP_CRON=true; system_cron=false", "WP cron nebezi vobec, co ohrozuje objednavky a Action Scheduler.")
            else if (truth(disabled_cron) && tolower(system_cron) == "unknown") app_emit("R-APP-WPCRON", id, "medium", "UNKNOWN", "DISABLE_WP_CRON=true; app cron mapping=unknown", "Globalny cron nie je dokaz pre tuto aplikaciu; namapuj URL alebo webroot konkretneho wp-cron behu.")

            raw = av(id, "autoload_bytes", "autoload_size_bytes")
            autoload = bytes(raw)
            autoload_mb = numeric(av(id, "autoload_mb", "autoload_size_mb"))
            if (autoload <= 0 && autoload_mb > 0) autoload = autoload_mb * mib
            source = app_source_error(id, "wp_config database table_prefix options_table autoload metrics", 1)
            if (source == "" && tolower(raw) == "unknown") source = "autoload=unknown"
            if (source != "") app_unknown("R-APP-AUTOLOAD", id, source)
            else if (autoload > 3 * mib) app_emit("R-APP-AUTOLOAD", id, "high", "TOO-LARGE", sprintf("autoload=%.2fM; inspect_top20", autoload / mib), "Autoload nad 3 MB ries prioritne a skontroluj top 20 options.")
            else if (autoload >= mib) app_emit("R-APP-AUTOLOAD", id, "medium", "REVIEW", sprintf("autoload=%.2fM; inspect_top20", autoload / mib), "Autoload 1 az 3 MB vyzaduje kontrolu najvacsich options.")
            else if (autoload > 0) app_emit("R-APP-AUTOLOAD", id, "info", "OK", sprintf("autoload=%.2fM", autoload / mib), "Autoload je pod 1 MB.")

            hpos = av(id, "hpos_enabled", "woocommerce_hpos_enabled", "hpos_woocommerce_custom_orders_table_enabled", "hpos_woocommerce_feature_custom_order_tables_enabled")
            orders = numeric(av(id, "orders_in_posts", "shop_orders_in_posts", "postmeta_orders", "legacy_order_count"))
            sync = av(id, "hpos_sync_enabled", "hpos_data_sync", "data_sync_enabled", "hpos_woocommerce_custom_orders_table_data_sync_enabled")
            source = app_source_error(id, "wp_config database table_prefix options_table hpos legacy_orders metrics", 1)
            if (source != "") app_unknown("R-APP-HPOS", id, source)
            else if (falsehood(hpos) && orders > 0) app_emit("R-APP-HPOS", id, "high", "MIGRATE", "HPOS=off; legacy_orders=" orders, "Objednavky v posts/postmeta su kandidat na samostatnu HPOS migraciu.")
            else if (truth(hpos) && truth(sync)) app_emit("R-APP-HPOS", id, "medium", "DUPLICATE-WRITES", "HPOS=on; sync=on", "Po overeni migracie vypni kompatibilny sync, inak sa objednavky zapisuju dvakrat.")

            kbrow = numeric(av(id, "max_log_kb_per_row", "log_kb_per_row", "kb_per_row"))
            source = app_source_error(id, "wp_config database table_prefix log_tables metrics", 1)
            if (source != "") app_unknown("R-APP-LOG-TABLE", id, source)
            else if (kbrow > 20) app_emit("R-APP-LOG-TABLE", id, "high", "PURGE-CANDIDATE", "max_kb_per_row=" kbrow, "Log tabulka nad 20 KB na riadok pravdepodobne drzi cele payloady.")

            sessions = numeric(av(id, "woocommerce_sessions", "session_rows", "sessions", "woocommerce_sessions_count"))
            source = app_source_error(id, "wp_config database table_prefix woocommerce_sessions_probe woocommerce_sessions_count metrics", 1)
            if (source != "") app_unknown("R-APP-SESSIONS", id, source)
            else if (sessions >= 500000) app_emit("R-APP-SESSIONS", id, "medium", "CLEANUP", "session_rows=" sessions, "WooCommerce sessions su problem od priblizne 500 tisic riadkov.")

            failed = numeric(av(id, "action_scheduler_failed", "as_failed", "failed_actions"))
            source = app_source_error(id, "wp_config database table_prefix action_scheduler metrics", 1)
            if (source != "") app_unknown("R-APP-AS", id, source)
            else if (failed > 0) app_emit("R-APP-AS", id, "medium", "FAILED", "failed_actions=" failed, "Zlyhane Action Scheduler akcie retention neodstrani; najdi chybny plugin alebo hook.")
            retention = numeric(av(id, "action_scheduler_retention_days", "as_retention_days"))
            if (source != "") app_unknown("R-APP-AS-RETENTION", id, source)
            else if (retention > 7) app_emit("R-APP-AS-RETENTION", id, "low", "REDUCE", "retention_days=" retention, "Skrat retention dokoncenej historie na 7 dni, nie na 1 den.")

            transient_count = numeric(av(id, "transient_count", "transients"))
            transient_bytes = bytes(av(id, "transient_bytes", "transients_bytes"))
            source = app_source_error(id, "wp_config database table_prefix options_table transients metrics", 1)
            if (source != "") app_unknown("R-APP-TRANSIENTS", id, source)
            else if (transient_count >= 1000 || transient_bytes >= 10 * mib) app_emit("R-APP-TRANSIENTS", id, "medium", "CLEANUP", sprintf("count=%d; size=%.2fM", transient_count, transient_bytes / mib), "Velky objem DB transientov prever a odstran iba expirovane zaznamy.")

            meta_index = av(id, "rogue_meta_value_index", "meta_value_index")
            source = app_source_error(id, "wp_config database table_prefix postmeta_indexes metrics", 1)
            if (source != "") app_unknown("R-APP-META-INDEX", id, source)
            else if (meta_index != "" && !falsehood(meta_index)) app_emit("R-APP-META-INDEX", id, "medium", "ROGUE-INDEX", "standalone meta_value index detected", "Samostatny index meta_value je velky a malo selektivny; pred odstraneni over pouzitie.")

            policy = tolower(av(id, "redis_maxmemory_policy", "redis_policy"))
            if (policy == "") policy = tolower(ag("redis_maxmemory_policy", ""))
            if (policy != "" && policy != "volatile-lru") app_emit("R-APP-REDIS", id, "medium", "POLICY", "maxmemory-policy=" policy, "Pre eshop pouzi volatile-lru, aby tlak na pamat nevyhadzoval session data.")
        }
    }
    ' </dev/null
    result=$?
    rm -f "$normalized_audit"
    return "$result"
}

# Funkciu vola CLI dispatcher aj collector bez argumentov.
# shellcheck disable=SC2120
cmd_analyze() {
    local min_samples=288
    local output temporary manifest temporary_manifest run_id audit_hash samples_hash dbsize_hash dbsize_hash_before
    local audit_file samples_file dbsize_file apps_file databases_file

    while [[ $# -gt 0 ]]; do
        case $1 in
            --min-samples)
                [[ $# -ge 2 ]] || {
                    dbtune_log error "Pouzitie: dbtune analyze [--min-samples N]"
                    return 64
                }
                min_samples=$2
                shift 2
                ;;
            *)
                dbtune_log error "Neznama analyze volba: $1"
                return 64
                ;;
        esac
    done
    [[ $min_samples =~ ^[1-9][0-9]*$ ]] || {
        dbtune_log error "--min-samples musi byt kladne cele cislo"
        return 64
    }

    audit_file=$(dbtune_path audit.tsv) || return
    samples_file=$(dbtune_path samples.tsv) || return
    dbsize_file=$(dbtune_path dbsize.tsv) || return
    apps_file=$(dbtune_path apps.tsv) || return
    databases_file=$(dbtune_path databases.tsv) || return
    output=$(dbtune_path analysis.tsv) || return
    manifest=$(dbtune_analysis_manifest_file) || return
    dbtune_provenance_validate_audit || return
    dbsize_hash_before=$(dbtune_sha256_file "$dbsize_file") || {
        dbtune_log error "Chyba povinny dbsize vstup: $dbsize_file"
        return 66
    }
    temporary=$(mktemp "$DBTUNE_STATE_DIR/.analysis.tmp.XXXXXX") || return 1
    temporary_manifest=$(mktemp "$DBTUNE_STATE_DIR/.analysis-manifest.tmp.XXXXXX") || {
        rm -f "$temporary"
        return 1
    }

    if ! dbtune_rules_analyze "$audit_file" "$samples_file" "$dbsize_file" "$apps_file" "$databases_file" "$min_samples" >"$temporary"; then
        rm -f "$temporary" "$temporary_manifest"
        dbtune_log error "Analyza zlyhala; analysis.tsv nebol zmeneny"
        return 65
    fi
    dbsize_hash=$(dbtune_sha256_file "$dbsize_file") || {
        rm -f "$temporary" "$temporary_manifest"
        return 66
    }
    if [[ $dbsize_hash != "$dbsize_hash_before" ]]; then
        rm -f "$temporary" "$temporary_manifest"
        dbtune_log error "dbsize.tsv sa pocas analyzy zmenil; analysis.tsv nebol zmeneny"
        return 65
    fi
    if ! dbtune_provenance_write_analysis_manifest "$temporary_manifest" "$temporary" "$samples_file" "$dbsize_file" ||
        ! dbtune_atomic_write "$output" 600 <"$temporary" ||
        ! dbtune_atomic_write "$manifest" 600 <"$temporary_manifest"; then
        rm -f "$temporary" "$temporary_manifest"
        return 1
    fi
    rm -f "$temporary" "$temporary_manifest"
    rm -f "$DBTUNE_STATE_DIR/report.md" "$DBTUNE_STATE_DIR/report.json" \
        "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" "$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    dbtune_state_transition analyzed || return
    run_id=$(dbtune_manifest_value "$manifest" run_id) || return
    audit_hash=$(dbtune_manifest_value "$manifest" audit_hash) || return
    samples_hash=$(dbtune_manifest_value "$manifest" samples_hash) || return
    dbsize_hash=$(dbtune_manifest_value "$manifest" dbsize_hash) || return
    dbtune_event analysis_completed samples_min "$min_samples" output "$output" \
        run_id "$run_id" audit_hash "$audit_hash" samples_hash "$samples_hash" dbsize_hash "$dbsize_hash" || true
}
