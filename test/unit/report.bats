#!/usr/bin/env bats

# shellcheck disable=SC1091

setup() {
    BATS_TEST_TMPDIR=$(CDPATH='' cd -- "$BATS_TEST_TMPDIR" && pwd -P)
    export BATS_TEST_TMPDIR
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/50-report.sh"
    mkdir -p "$DBTUNE_STATE_DIR"
    chmod 700 "$DBTUNE_STATE_DIR"

    # shellcheck disable=SC2329
    dbtune_embedded_get() {
        [ "${1:-}" = templates/tuning.cnf.tmpl ] || return 64
        command cat "$BATS_TEST_DIRNAME/../../templates/tuning.cnf.tmpl"
    }

    cat >"$DBTUNE_STATE_DIR/audit.tsv" <<'EOF'
audit.hostname	shop-01
mariadb.version	11.4.12-MariaDB
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
audit.section.mariadb.status	complete
audit.section.mariadb.evidence_schema_version	1
audit.section.mariadb.missing_evidence	none
audit.section.mariadb.invalid_evidence	none
audit.section.mariadb.conflicting_evidence	none
audit.section.mariadb.optional_evidence	mariadb.variable.innodb_flush_method=deprecated_11x
audit.section.hardware.status	complete
audit.section.applications.status	complete
audit.section.security.status	complete
audit.required_sections	mariadb,hardware,applications,security
audit.failed_sections	none
audit.partial_sections	none
audit.affected_domains	none
audit.finding_count	0
audit.overall_status	PASS
audit.exit_status	0
EOF
    cat >"$DBTUNE_STATE_DIR/apps.tsv" <<'EOF'
shop-a	path	/home/runcloud/webapps/shop-a
shop-a	webroot	/home/runcloud/webapps/shop-a
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
    printf 'timestamp\tdatabase\tsize_bytes\n' >"$DBTUNE_STATE_DIR/dbsize.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
}

write_analysis_manifest() {
    dbtune_provenance_write_analysis_manifest "$DBTUNE_STATE_DIR/analysis-manifest.tsv" \
        "$DBTUNE_STATE_DIR/analysis.tsv" "$DBTUNE_STATE_DIR/samples.tsv" "$DBTUNE_STATE_DIR/dbsize.tsv"
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
    grep -F '"server.support_status":"supported"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"run_id":"report-run"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"dbsize_hash":"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"analysis_fingerprint":"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.overall_status":"PASS"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.exit_status":"0"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.section.security.status":"complete"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.section.mariadb.evidence_schema_version":"1"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.section.mariadb.invalid_evidence":"none"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '_Run: `report-run`' "$DBTUNE_STATE_DIR/report.md"
    grep -F '**Celkový stav auditu:** PASS.' "$DBTUNE_STATE_DIR/report.md"
    grep -F '"apps.count":"1"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"databases.count":"1"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"samples.rejected":"0"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"samples.rejected_reasons":"truncated=0,extra_fields=0,non_numeric=0,invalid_timestamp=0,invalid_value=0,non_monotonic=0"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"metrics.cpu_pct.p95":"75.00"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"proposal.001.key":"max_connections"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.safety":"read-only"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.001.connect_timeout_seconds":"5"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.001.statement_timeout_seconds":"30"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.001.timeout_capability":"mariadb_max_statement_time"' "$DBTUNE_STATE_DIR/report.json"
    grep -F -- '--connect-timeout=5' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'SET SESSION max\_statement\_time=30' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'large\_option' "$DBTUNE_STATE_DIR/report.md"
    grep -F '\[REDACTED\]' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'near\_last\_success' "$DBTUNE_STATE_DIR/report.md"
    grep -F -- '--database=' "$DBTUNE_STATE_DIR/report.md"
    [ "$(grep -o '"action\.[0-9][0-9][0-9]\.destructive":"false"' "$DBTUNE_STATE_DIR/report.json" | wc -l | tr -d ' ')" = 3 ]
    ! grep -E '"action\.[0-9]+\.command":"[^"]*(DELETE|DROP|UPDATE)' "$DBTUNE_STATE_DIR/report.json"
    if command -v jq >/dev/null 2>&1; then
        jq -e 'type == "object" and ([paths | length] | max) == 1' "$DBTUNE_STATE_DIR/report.json"
    fi
}

@test "report exposes failed and partial audit sections and affected domains" {
    local updated="$BATS_TEST_TMPDIR/audit.tsv"
    write_analysis
    awk -F '\t' 'BEGIN {OFS="\t"}
        $1=="audit.section.mariadb.status" {$2="partial"}
        $1=="audit.section.mariadb.missing_evidence" {$2="mariadb.variable.innodb_io_capacity_max"}
        $1=="audit.section.security.status" {$2="failed"}
        $1=="audit.failed_sections" {$2="security"}
        $1=="audit.partial_sections" {$2="mariadb"}
        $1=="audit.affected_domains" {$2="server_tuning,database_inventory,security"}
        $1=="audit.overall_status" {$2="UNKNOWN"}
        $1=="audit.exit_status" {$2="2"}
        {print}
    ' "$DBTUNE_STATE_DIR/audit.tsv" >"$updated"
    mv "$updated" "$DBTUNE_STATE_DIR/audit.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_analysis_manifest

    run cmd_report

    [ "$status" -eq 0 ]
    grep -F '**Celkový stav auditu:** UNKNOWN.' "$DBTUNE_STATE_DIR/report.md"
    grep -F '**Zlyhané sekcie:** security' "$DBTUNE_STATE_DIR/report.md"
    grep -F '**Čiastočné sekcie:** mariadb' "$DBTUNE_STATE_DIR/report.md"
    grep -F '**Ovplyvnené domény odporúčaní:** server\_tuning,database\_inventory,security' "$DBTUNE_STATE_DIR/report.md"
    grep -F '"audit.overall_status":"UNKNOWN"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.failed_sections":"security"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.partial_sections":"mariadb"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.affected_domains":"server_tuning,database_inventory,security"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"audit.section.mariadb.missing_evidence":"mariadb.variable.innodb_io_capacity_max"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '**MariaDB chýbajúce dôkazy:** mariadb.variable.innodb\_io\_capacity\_max' "$DBTUNE_STATE_DIR/report.md"
}

@test "report metrics exclude degraded and restart samples" {
    printf '2026-07-24T01:00:00Z\t1900\t0\t999\t999\t999\t100\t999\t999\t0\t999\t999\t999\t1\t1\t1\t0\t1\t999\tdegraded_interval\n' >>"$DBTUNE_STATE_DIR/samples.tsv"
    printf '2026-07-24T01:05:00Z\t10\t0\t888\t888\t888\t100\t888\t888\t0\t0\t0\t888\t1\t1\t1\t1\t0\t60\tok\n' >>"$DBTUNE_STATE_DIR/samples.tsv"

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
        printf '2026-07-24T00:00:00Z\t%s\t99\t0\t0\t0\t0\t%s\t1\t30\t0\t0\t%s\t1000\t0\t1\t0\t1\t60\tok\n' \
            "$value" "$value" "$value" >>"$sample_file"
    done

    run dbtune_samples_stats "$sample_file" cpu_pct 13
    [ "$status" -eq 0 ]
    [ "$output" = $'10.00\t19.00\t20.00\t20.00' ]
}

@test "action commands shell-quote scope and reject unsafe table prefixes" {
    run dbtune_action_sql_command "shop';touch /tmp/not-run" wp_ R-APP-AUTOLOAD mariadb_max_statement_time 5 30
    [ "$status" -eq 0 ]
    [[ "$output" == *"--database='shop'\\'';touch /tmp/not-run'"* ]]
    [[ "$output" == *'FROM `wp_options`'* ]]
    [[ "$output" == *'--no-defaults --connect-timeout=5'* ]]
    [[ "$output" == *'SET SESSION max_statement_time=30'* ]]
    [[ "$output" != *--password* ]]
    [[ "$output" != *MYSQL_PWD* ]]

    run dbtune_action_sql_command shop wp_ R-APP-META-INDEX mysql_max_execution_time 5 30
    [ "$status" -eq 0 ]
    [[ "$output" == *'FROM information_schema.STATISTICS'* ]]
    [[ "$output" != *'SHOW INDEX'* ]]

    run dbtune_action_sql_command shop 'wp_;DROP' R-APP-AUTOLOAD mariadb_max_statement_time 5 30
    [ "$status" -ne 0 ]

    run dbtune_action_wp_command "/home/shop app';touch" 'deploy-user' cron
    [ "$status" -eq 0 ]
    [[ "$output" == "sudo -u 'deploy-user' -- wp "* ]]
    [[ "$output" == *"--path='/home/shop app'\\'';touch'"* ]]
    [[ "$output" != *--allow-root* ]]

    run dbtune_action_wp_command /home/shop '' cron
    [ "$status" -ne 0 ]
    [ -z "$output" ]

    run dbtune_action_wp_command /home/shop root cron
    [ "$status" -ne 0 ]
    [ -z "$output" ]

    run dbtune_action_wp_command /home/shop 'bad owner;touch' cron
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "SQL actions render supported MySQL execution timeouts without credentials" {
    printf 'mysql.version\t8.0.36-MySQL\n' >"$BATS_TEST_TMPDIR/mysql-audit.tsv"
    DBTUNE_AUDIT_FILE="$BATS_TEST_TMPDIR/mysql-audit.tsv"
    DBTUNE_APPS_FILE="$DBTUNE_STATE_DIR/apps.tsv"
    DBTUNE_ANALYSIS_LINES=(
        $'R-APP-AUTOLOAD\tapp:shop-a\thigh\tCHECK\t\t\tautoload\tcheck'
    )

    dbtune_actions_load
    dbtune_action_parse "${DBTUNE_ACTION_LINES[0]}"

    [ "$DBTUNE_ACTION_SAFETY" = read-only ]
    [ "$DBTUNE_ACTION_CONNECT_TIMEOUT_SECONDS" = 5 ]
    [ "$DBTUNE_ACTION_STATEMENT_TIMEOUT_SECONDS" = 30 ]
    [ "$DBTUNE_ACTION_TIMEOUT_CAPABILITY" = mysql_max_execution_time ]
    [[ "$DBTUNE_ACTION_COMMAND" == 'sudo mysql --no-defaults --connect-timeout=5 '* ]]
    [[ "$DBTUNE_ACTION_COMMAND" == *'SET SESSION max_execution_time=30000'* ]]
    [[ "$DBTUNE_ACTION_COMMAND" != *--password* ]]
    [[ "$DBTUNE_ACTION_COMMAND" != *MYSQL_PWD* ]]

    DBTUNE_AUTOLOAD_LINES=()
    DBTUNE_DATABASES_FILE="$DBTUNE_STATE_DIR/databases.tsv"
    run dbtune_render_per_app
    [ "$status" -eq 0 ]
    [[ "$output" == *'connect\_timeout\_seconds=5; statement\_timeout\_seconds=30; timeout\_capability=mysql\_max\_execution\_time'* ]]
    [[ "$output" == *'SET SESSION max\_execution\_time=30000'* ]]
}

@test "SQL actions with unknown timeout capability render non-executable" {
    printf 'server.version\tcustom-unknown\n' >"$BATS_TEST_TMPDIR/unknown-audit.tsv"
    DBTUNE_AUDIT_FILE="$BATS_TEST_TMPDIR/unknown-audit.tsv"
    DBTUNE_APPS_FILE="$DBTUNE_STATE_DIR/apps.tsv"
    DBTUNE_ANALYSIS_LINES=(
        $'R-APP-AUTOLOAD\tapp:shop-a\thigh\tCHECK\t\t\tautoload\tcheck'
    )

    dbtune_actions_load
    dbtune_action_parse "${DBTUNE_ACTION_LINES[0]}"

    [ "$DBTUNE_ACTION_SAFETY" = not-executable ]
    [ -z "$DBTUNE_ACTION_COMMAND" ]
    [ "$DBTUNE_ACTION_CONNECT_TIMEOUT_SECONDS" = 5 ]
    [ "$DBTUNE_ACTION_STATEMENT_TIMEOUT_SECONDS" = 30 ]
    [ "$DBTUNE_ACTION_TIMEOUT_CAPABILITY" = unknown ]
    [[ "$DBTUNE_ACTION_WARNING" == *'capability je unknown'* ]]

    DBTUNE_AUTOLOAD_LINES=()
    DBTUNE_DATABASES_FILE="$DBTUNE_STATE_DIR/databases.tsv"
    run dbtune_render_per_app
    [ "$status" -eq 0 ]
    [[ "$output" == *'safety=not-executable'* ]]
    [[ "$output" == *'connect\_timeout\_seconds=5; statement\_timeout\_seconds=30; timeout\_capability=unknown'* ]]
    [[ "$output" == *'Neexekvovatelna SQL diagnostika'* ]]
}

@test "unsupported MariaDB report suppresses proposals and executable SQL actions" {
    awk -F '\t' 'BEGIN {OFS="\t"} $1 == "mariadb.version" {$2="12.0.0-MariaDB"} {print}' \
        "$DBTUNE_STATE_DIR/audit.tsv" >"$BATS_TEST_TMPDIR/audit.tsv"
    mv "$BATS_TEST_TMPDIR/audit.tsv" "$DBTUNE_STATE_DIR/audit.tsv"
    cat >"$DBTUNE_STATE_DIR/analysis.tsv" <<'EOF'
rule_id	scope	severity	verdict	proposed_key	proposed_value	evidence	reason_sk
R-VERSION	server	critical	UNSUPPORTED			version=12.0.0-MariaDB	Rodina nebola schvalena.
R-APP-AUTOLOAD	app:shop-a	high	CHECK			autoload=4M	Skontrolujte autoload.
EOF
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_analysis_manifest

    run cmd_report

    [ "$status" -eq 0 ]
    grep -F 'Nepodporovaná MariaDB' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'Serverové tuning odporúčania a návrh konfigurácie sú potlačené' "$DBTUNE_STATE_DIR/report.md"
    grep -F '"server.support_status":"unsupported"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"proposals.count":"0"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.safety":"not-executable"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.command":""' "$DBTUNE_STATE_DIR/report.json"
    run grep -F 'dbtune propose' "$DBTUNE_STATE_DIR/report.md"
    [ "$status" -ne 0 ]

    dbtune_state_write analyzed
    run cmd_propose
    [ "$status" -eq 65 ]
    [ ! -e "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" ]
}

@test "per-app actions use each verified webroot and diagnose missing or invalid owners" {
    DBTUNE_APPS_FILE="$BATS_TEST_TMPDIR/action-apps.tsv"
    cat >"$DBTUNE_APPS_FILE" <<'EOF'
shop-one	path	/home/one/webapps/shop
shop-one	webroot	/home/one/webapps/shop/htdocs
shop-one	owner	owner-one
shop-two	path	/home/two/webapps/shop app
shop-two	webroot	/home/two/webapps/shop app/public
shop-two	owner	owner-two
shop-missing	path	/home/missing/webapps/shop
shop-missing	webroot	/home/missing/webapps/shop
shop-invalid	path	/home/invalid/webapps/shop
shop-invalid	webroot	/home/invalid/webapps/shop
shop-invalid	owner	bad owner
shop-no-root	path	/home/no-root/webapps/shop
shop-no-root	owner	owner-three
EOF
    DBTUNE_ANALYSIS_LINES=(
        $'R-APP-WPCRON\tapp:shop-one\thigh\tCHECK\t\t\tone\tone'
        $'R-APP-REDIS\tapp:shop-two\thigh\tCHECK\t\t\ttwo\ttwo'
        $'R-APP-WPCRON\tapp:shop-missing\thigh\tCHECK\t\t\tmissing\tmissing'
        $'R-APP-REDIS\tapp:shop-invalid\thigh\tCHECK\t\t\tinvalid\tinvalid'
        $'R-APP-WPCRON\tapp:shop-no-root\thigh\tCHECK\t\t\tno-root\tno-root'
    )

    dbtune_actions_load

    [ "${#DBTUNE_ACTION_LINES[@]}" -eq 5 ]
    dbtune_action_parse "${DBTUNE_ACTION_LINES[0]}"
    [ "$DBTUNE_ACTION_SCOPE" = app:shop-one ]
    [[ "$DBTUNE_ACTION_COMMAND" == *"-u 'owner-one' -- wp --path='/home/one/webapps/shop/htdocs'"* ]]
    [[ "$DBTUNE_ACTION_COMMAND" == *'cron event list'* ]]
    dbtune_action_parse "${DBTUNE_ACTION_LINES[1]}"
    [ "$DBTUNE_ACTION_SCOPE" = app:shop-two ]
    [[ "$DBTUNE_ACTION_COMMAND" == *"-u 'owner-two' -- wp --path='/home/two/webapps/shop app/public'"* ]]
    [[ "$DBTUNE_ACTION_COMMAND" == *'redis status'* ]]
    dbtune_action_parse "${DBTUNE_ACTION_LINES[2]}"
    [ "$DBTUNE_ACTION_SAFETY" = not-executable ]
    [ -z "$DBTUNE_ACTION_COMMAND" ]
    [[ "$DBTUNE_ACTION_WARNING" == Neexekvovatelna* ]]
    dbtune_action_parse "${DBTUNE_ACTION_LINES[3]}"
    [ "$DBTUNE_ACTION_SAFETY" = not-executable ]
    [ -z "$DBTUNE_ACTION_COMMAND" ]
    dbtune_action_parse "${DBTUNE_ACTION_LINES[4]}"
    [ "$DBTUNE_ACTION_SAFETY" = not-executable ]
    [ -z "$DBTUNE_ACTION_COMMAND" ]
    [[ "${DBTUNE_ACTION_LINES[*]}" != *--allow-root* ]]
}

@test "report renders an unavailable WP-CLI action as non-executable" {
    cat >"$DBTUNE_STATE_DIR/apps.tsv" <<'EOF'
shop-a	path	/home/runcloud/webapps/shop-a
shop-a	webroot	/home/runcloud/webapps/shop-a
shop-a	type	wordpress
shop-a	database	shop_db
shop-a	table_prefix	wp_
EOF
    cat >"$DBTUNE_STATE_DIR/analysis.tsv" <<'EOF'
rule_id	scope	severity	verdict	proposed_key	proposed_value	evidence	reason_sk
R-APP-WPCRON	app:shop-a	high	CHECK			owner missing	Overte vlastnika.
EOF
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_analysis_manifest

    run cmd_report

    [ "$status" -eq 0 ]
    grep -F '"action.000.safety":"not-executable"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.command":""' "$DBTUNE_STATE_DIR/report.json"
    grep -F 'Neexekvovatelna diagnostika' "$DBTUNE_STATE_DIR/report.md"
    run grep -F -- '--allow-root' "$DBTUNE_STATE_DIR/report.md"
    [ "$status" -ne 0 ]
}

@test "report preserves source-error UNKNOWN findings and suppresses executable actions" {
    cat >>"$DBTUNE_STATE_DIR/apps.tsv" <<'EOF'
shop-a	audit_status	partial
shop-a	source_error	audit_error.autoload=query_failed
EOF
    cat >"$DBTUNE_STATE_DIR/analysis.tsv" <<'EOF'
rule_id	scope	severity	verdict	proposed_key	proposed_value	evidence	reason_sk
R-APP-AUTOLOAD	app:shop-a	medium	UNKNOWN			audit_status=partial; source_error=audit_error.autoload=query_failed	Zdrojovy SQL audit zlyhal.
EOF
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_analysis_manifest

    run cmd_report

    [ "$status" -eq 0 ]
    grep -F 'UNKNOWN' "$DBTUNE_STATE_DIR/report.md"
    grep -F 'source\_error=audit\_error.autoload=query\_failed' "$DBTUNE_STATE_DIR/report.md"
    grep -F '"rule.000.verdict":"UNKNOWN"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"rule.000.evidence":"audit_status=partial; source_error=audit_error.autoload=query_failed"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.safety":"not-executable"' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"action.000.command":""' "$DBTUNE_STATE_DIR/report.json"
    grep -F 'auditny zdroj zlyhal' "$DBTUNE_STATE_DIR/report.md"
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

@test "report formats neutralize controls HTML Markdown and quoted secrets" {
    local hostile
    write_analysis
    printf 'mariadb.variable.thread_cache_size\t16\n' >>"$DBTUNE_STATE_DIR/audit.tsv"
    hostile=$'ANSI \033[31mred\033[0m\rrewrite <b>html</b> [link](https://evil) | table *bold* _emphasis_ ~~strike~~ # heading; UTF-8 žluťoučký; "CLIENT.SECRET" = "never expose this"'
    printf 'R-HOSTILE\tserver\tmedium\tCHANGE\tthread_cache_size\t32\t%s\t%s\n' "$hostile" "$hostile" >>"$DBTUNE_STATE_DIR/analysis.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        report-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
    write_analysis_manifest

    cmd_report >/dev/null
    dbtune_state_write analyzed
    cmd_propose >/dev/null

    grep -F '&lt;b&gt;html&lt;/b&gt;' "$DBTUNE_STATE_DIR/report.md"
    grep -F '\[link\]\(https://evil\)' "$DBTUNE_STATE_DIR/report.md"
    grep -F '\| table \*bold\* \_emphasis\_ \~\~strike\~\~ \# heading; UTF-8 žluťoučký; "CLIENT.SECRET" = \[REDACTED\]' "$DBTUNE_STATE_DIR/report.md"
    grep -F '\"CLIENT.SECRET\" = [REDACTED]' "$DBTUNE_STATE_DIR/report.json"
    grep -F '"CLIENT.SECRET" = [REDACTED]' "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    for file in "$DBTUNE_STATE_DIR/report.md" "$DBTUNE_STATE_DIR/report.json" "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"; do
        run grep -F 'never expose this' "$file"
        [ "$status" -ne 0 ]
        run grep -F $'\033' "$file"
        [ "$status" -ne 0 ]
        run grep -F $'\r' "$file"
        [ "$status" -ne 0 ]
    done
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
