#!/usr/bin/env bats

# shellcheck disable=SC1091

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/50-report.sh"
    mkdir -p "$DBTUNE_STATE_DIR"

    # shellcheck disable=SC2329
    dbtune_embedded_get() {
        [ "${1:-}" = templates/tuning.cnf.tmpl ] || return 64
        command cat "$BATS_TEST_DIRNAME/../../templates/tuning.cnf.tmpl"
    }

    cat >"$DBTUNE_STATE_DIR/audit.tsv" <<'EOF'
audit.hostname	shop-01
mariadb.version	11.4.12
hw.cpu_count	8
hw.ram_bytes	17179869184
hw.storage_class	nvme
mariadb.dataset_bytes	4294967296
mariadb.variable.innodb_buffer_pool_size	128M
mariadb.variable.max_connections	4096
EOF
    cat >"$DBTUNE_STATE_DIR/apps.tsv" <<'EOF'
app.0	path	/home/runcloud/webapps/shop-a
app.0	type	wordpress
app.0	woocommerce	1
EOF
    cat >"$DBTUNE_STATE_DIR/databases.tsv" <<'EOF'
shop_db	size_bytes	4294967296
shop_db	table_count	120
EOF
    cat >"$DBTUNE_STATE_DIR/samples.tsv" <<'EOF'
timestamp	uptime	bp_hit_pct	bp_misses_s	data_read_s	rnd_next_s	tmp_disk_pct	threads_running	threads_connected	qcache_hit_pct	log_waits_delta	wait_free_delta	cpu_pct	mem_available_kb	swap_used_kb	load1	restart_flag
2026-07-01T10:00:00Z	1000	99.9	1	1024	100	10	2	4	30	0	0	5	12000000	0	0.2	0
2026-07-01T10:05:00Z	1300	80	200	4096000	9000	40	12	20	10	1	0	75	9000000	64	4.2	0
2026-07-01T10:10:00Z	1600	95	40	2048000	3000	25	7	12	22	0	0	30	10000000	64	2.1	0
EOF
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
}

write_analysis_manifest() {
    dbtune_provenance_write_analysis_manifest "$DBTUNE_STATE_DIR/analysis-manifest.tsv" \
        "$DBTUNE_STATE_DIR/analysis.tsv" "$DBTUNE_STATE_DIR/samples.tsv"
}

write_analysis() {
    cat >"$DBTUNE_STATE_DIR/analysis.tsv" <<'EOF'
rule_id	scope	severity	verdict	proposed_key	proposed_value	evidence	reason_sk
R-OC	app:shop-a	critical	Chýba object cache			Redis inactive | drop-in chýba	Zapnite Redis object cache "hneď".
R-BP-SIZE	server	high	Pool je malý	innodb_buffer_pool_size	4G	dataset 4 GB; burst 80 %	Pool musí absorbovať bursty.
R-MAXCONN	server	medium	Limit je privysoký	max_connections	200	FPM 120; peak 80	Zníži OOM riziko.
R-SEC	server	high	MariaDB počúva verejne			bind-address=0.0.0.0	Obmedzte bind-address.
R-APP-SQL	app:shop-a	high	Nikdy do CNF	query_cache_type	DROP TABLE wp_posts	app SQL	Iba aplikačné odporúčanie.
R-DUP	server	low	Duplicitný návrh	max-connections	300	duplicitný kľúč	Musí sa preskočiť.
EOF
    write_analysis_manifest
}

@test "report is valid escaped flat JSON and keeps app section first" {
    write_analysis

    run cmd_report
    [ "$status" -eq 0 ]
    [ -s "$DBTUNE_STATE_DIR/report.md" ]
    [ -s "$DBTUNE_STATE_DIR/report.json" ]
    [[ "$output" == *"Report uložený: $DBTUNE_STATE_DIR/report.md"* ]]

    app_line=$(grep -n '^## Aplikačná vrstva' "$DBTUNE_STATE_DIR/report.md" | cut -d: -f1)
    server_line=$(grep -n '^## Server' "$DBTUNE_STATE_DIR/report.md" | cut -d: -f1)
    [ "$app_line" -lt "$server_line" ]
    grep -F 'dataset 4 GB; burst 80 %' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'Zapnite Redis object cache \"hneď\".' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"schema_version":"fleet-v2"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"run_id":"report-run"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '_Run: `report-run`' "$DBTUNE_STATE_DIR/report.md"
    grep -F '"apps.count":"1"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"databases.count":"1"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"metrics.cpu_pct.p95":"75.00"' "$DBTUNE_STATE_DIR/report.json"
    if command -v jq >/dev/null 2>&1; then
        jq -e 'type == "object" and ([paths | length] | max) == 1' "$DBTUNE_STATE_DIR/report.json"
    fi
}

@test "report escapes hostile TSV text and does not expose sensitive audit values" {
    local expected
    write_analysis
    printf 'password\tdont-print-me\n' >>"$DBTUNE_STATE_DIR/audit.tsv"
    printf 'R-ESC\tapp:shop-a\tmedium\tPipe | tick ` and slash \\\t\t\tevidence | cell\tpassword=secret\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_analysis_manifest

    cmd_report >/dev/null
    expected="Pipe \\| tick \\\` and slash \\\\"
    grep -F "$expected" "$DBTUNE_STATE_DIR/report.md"
    grep -F 'password=[REDACTED]' "$DBTUNE_STATE_DIR/report.json"
    run grep -F 'dont-print-me' "$DBTUNE_STATE_DIR/report.md"
    [ "$status" -ne 0 ]
    run grep -F 'dont-print-me' "$DBTUNE_STATE_DIR/report.json"
    [ "$status" -ne 0 ]
    if command -v jq >/dev/null 2>&1; then
        jq -e . "$DBTUNE_STATE_DIR/report.json" >/dev/null
    fi
}

@test "proposal contains only server rules and no duplicate canonical keys" {
    write_analysis
    dbtune_state_write analyzed

    run cmd_propose
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = proposed ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/proposal-manifest.tsv" run_id)" = report-run ]
    proposal="$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    grep -Fx '[mysqld]' "$proposal"
    grep -F 'innodb_buffer_pool_size = 4G' "$proposal"
    grep -F 'max_connections = 200' "$proposal"
    run grep -F 'query_cache_type' "$proposal"
    [ "$status" -ne 0 ]
    run grep -F 'DROP TABLE' "$proposal"
    [ "$status" -ne 0 ]
    [ "$(awk -F= '/^[[:space:]]*[A-Za-z][A-Za-z0-9_-]*[[:space:]]*=/{key=$1; gsub(/[[:space:]-]/,"",key); key=tolower(key); count[key]++} END{for(key in count) if(count[key]>1) duplicate++} END{print duplicate+0}' "$proposal")" -eq 0 ]
}

@test "repeated proposal preserves proposed state and deterministic keys" {
    write_analysis
    dbtune_state_write analyzed
    cmd_propose >/dev/null
    first_keys=$(awk -F= '/^[[:space:]]*[A-Za-z][A-Za-z0-9_-]*[[:space:]]*=/{gsub(/[[:space:]]/,"",$1); print $1"="$2}' "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf")

    cmd_propose >/dev/null
    [ "$(dbtune_state_read)" = proposed ]
    second_keys=$(awk -F= '/^[[:space:]]*[A-Za-z][A-Za-z0-9_-]*[[:space:]]*=/{gsub(/[[:space:]]/,"",$1); print $1"="$2}' "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf")
    [ "$first_keys" = "$second_keys" ]
}

@test "report and propose reject analysis after an audit input changes" {
    write_analysis
    dbtune_state_write analyzed
    printf 'hw.ram_bytes\t34359738368\n' >>"$DBTUNE_STATE_DIR/audit.tsv"

    run cmd_report
    [ "$status" -eq 65 ]
    [ ! -e "$DBTUNE_STATE_DIR/report.md" ]
    run cmd_propose
    [ "$status" -eq 65 ]
    [ ! -e "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" ]
}
