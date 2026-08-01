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
backup.status	verified
backup.source	unit-test-backup
backup.checked_at	2026-07-01T10:15:00Z
backup.last_success	2026-07-01T10:06:00Z
backup.schedule_count	1
backup.process_count	0
EOF
    cat >"$DBTUNE_STATE_DIR/apps.tsv" <<'EOF'
shop-a	path	/home/runcloud/webapps/shop-a
shop-a	owner	runcloud
shop-a	type	wordpress
shop-a	database	shop_db
shop-a	table_prefix	wp_
shop-a	woocommerce	1
EOF
    cat >"$DBTUNE_STATE_DIR/databases.tsv" <<'EOF'
shop-a	size_bytes	4294967296
shop-a	table_count	120
shop-a	autoload.top.0	large_option:1048576
shop-a	autoload.top.1	api_token:512
EOF
    cat >"$DBTUNE_STATE_DIR/samples.tsv" <<'EOF'
timestamp	uptime	bp_hit_pct	bp_misses_s	data_read_s	rnd_next_s	tmp_disk_pct	threads_running	threads_connected	qcache_hit_pct	log_waits_delta	wait_free_delta	cpu_pct	mem_available_kb	swap_used_kb	load1	restart_flag	qcache_queries_delta	interval_seconds	sample_status
2026-07-01T10:00:00Z	1000	99.9	1	1024	100	10	2	4	30	0	0	5	12000000	0	0.2	0	10	300	ok
2026-07-01T10:05:00Z	1300	80	200	4096000	9000	40	12	20	10	1	0	75	9000000	64	4.2	0	10	300	ok
2026-07-01T10:10:00Z	1600	95	40	2048000	3000	25	7	12	22	0	0	30	10000000	64	2.1	0	10	300	ok
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
R-APP-AUTOLOAD	app:shop-a	high	TOO-LARGE			autoload=4M	Skontrolujte top autoload options.
R-BP-SIZE	server	high	Pool je malý	innodb_buffer_pool_size	4G	dataset 4 GB; burst 80 %	Pool musí absorbovať bursty.
R-MAXCONN	server	medium	Limit je privysoký	max_connections	200	FPM 120; peak 80	Zníži OOM riziko.
R-SEC	server	high	MariaDB počúva verejne			bind-address=0.0.0.0	Obmedzte bind-address.
R-APP-SQL	app:shop-a	high	Diagnostika			app SQL	Iba aplikačné odporúčanie.
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
    grep -F '"proposal.001.key":"max_connections"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.safety":"read-only"' "$DBTUNE_STATE_DIR/report.json"
    grep -F 'large_option' "$DBTUNE_STATE_DIR/report.md"
    grep -F '[REDACTED]' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'near_last_success' "$DBTUNE_STATE_DIR/report.md"
    grep -F -- '--database=' "$DBTUNE_STATE_DIR/report.md"
    [ "$(grep -o '"action\.[0-9][0-9][0-9]\.destructive":"false"' "$DBTUNE_STATE_DIR/report.json" | wc -l | tr -d ' ')" = 3 ]
    ! grep -E '"action\.[0-9]+\.command":"[^"]*(DELETE|DROP|UPDATE)' "$DBTUNE_STATE_DIR/report.json"
    if command -v jq >/dev/null 2>&1; then
        jq -e 'type == "object" and ([paths | length] | max) == 1' "$DBTUNE_STATE_DIR/report.json"
    fi
}

@test "report metrics exclude degraded and restart samples" {
    printf 'degraded\t1900\t0\t999\t999\t999\t100\t999\t999\t0\t999\t999\t999\t1\t1\t1\t0\t1\t999\tdegraded_interval\n' >>"$DBTUNE_STATE_DIR/samples.tsv"
    printf 'restart\t10\t0\t888\t888\t888\t100\t888\t888\t0\t0\t0\t888\t1\t1\t1\t1\t0\t60\tok\n' >>"$DBTUNE_STATE_DIR/samples.tsv"

    run dbtune_samples_count "$DBTUNE_STATE_DIR/samples.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = 3 ]
    run dbtune_samples_stats "$DBTUNE_STATE_DIR/samples.tsv" cpu_pct 13
    [ "$status" -eq 0 ]
    [ "$output" = $'30.00\t75.00\t75.00\t75.00' ]
    run dbtune_samples_worst "$DBTUNE_STATE_DIR/samples.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" != *degraded* ]]
    [[ "$output" != *restart* ]]
}

@test "shared nearest-rank p95 selects sample 19 at the 20-sample edge" {
    local sample_file="$BATS_TEST_TMPDIR/twenty.tsv"
    local value

    printf 'timestamp\tuptime\tbp_hit_pct\tbp_misses_s\tdata_read_s\trnd_next_s\ttmp_disk_pct\tthreads_running\tthreads_connected\tqcache_hit_pct\tlog_waits_delta\twait_free_delta\tcpu_pct\tmem_available_kb\tswap_used_kb\tload1\trestart_flag\tqcache_queries_delta\tinterval_seconds\tsample_status\n' >"$sample_file"
    for value in {1..20}; do
        printf 'sample-%s\t%s\t99\t0\t0\t0\t0\t%s\t1\t30\t0\t0\t%s\t1000\t0\t1\t0\t1\t60\tok\n' \
            "$value" "$value" "$value" "$value" >>"$sample_file"
    done

    run dbtune_samples_stats "$sample_file" cpu_pct 13
    [ "$status" -eq 0 ]
    [ "$output" = $'10.00\t19.00\t20.00\t20.00' ]
}

@test "action commands shell-quote scope and reject unsafe table prefixes" {
    run dbtune_action_sql_command "shop';touch /tmp/not-run" wp_ R-APP-AUTOLOAD
    [ "$status" -eq 0 ]
    [[ "$output" == *"--database='shop'\\'';touch /tmp/not-run'"* ]]
    [[ "$output" == *'FROM `wp_options`'* ]]

    run dbtune_action_sql_command shop 'wp_;DROP' R-APP-AUTOLOAD
    [ "$status" -ne 0 ]

    run dbtune_action_wp_command "/home/shop app';touch" runcloud cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"--path='/home/shop app'\\'';touch'"* ]]
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
    cmd_report >/dev/null

    run cmd_propose
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = proposed ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/proposal-manifest.tsv" run_id)" = report-run ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/proposal-manifest.tsv" proposal_count)" = 2 ]
    grep -F '"proposals.count":"2"' "$DBTUNE_STATE_DIR/report.json"
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/proposal-manifest.tsv" proposal_records_hash)" = \
        "$(grep -o '"proposals.hash":"[0-9a-f]*"' "$DBTUNE_STATE_DIR/report.json" | cut -d'"' -f4)" ]
    ! grep -F 'current":"unknown' "$DBTUNE_STATE_DIR/report.json"
    ! grep -F '`nezistená`' "$DBTUNE_STATE_DIR/report.md"
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

@test "report and propose fail closed on canonical duplicate or unsafe proposal" {
    DBTUNE_LOG_LEVEL=error
    write_analysis
    printf 'R-DUP\tserver\tlow\tCHANGE\tmax-connections\t300\tduplicate\tDuplicate.\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    write_analysis_manifest
    dbtune_state_write analyzed

    run cmd_report
    [ "$status" -eq 65 ]
    [[ "$output" == *"Kanonicky duplicitny"* ]]
    run cmd_propose
    [ "$status" -eq 65 ]
    [ ! -e "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" ]

    write_analysis
    printf 'R-BAD\tserver\thigh\tCHANGE\tunsafe;key\t1\tx\tx\n' >>"$DBTUNE_STATE_DIR/analysis.tsv"
    write_analysis_manifest
    run cmd_report
    [ "$status" -eq 65 ]
    [[ "$output" == *"Nebezpecny proposal"* ]]
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
