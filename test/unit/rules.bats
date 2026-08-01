#!/usr/bin/env bats

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    mkdir -p "$DBTUNE_STATE_DIR"
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/40-rules.sh"
}

make_audit() {
    local file=$1
    local version=${2:-10.6.18}
    local dataset=${3:-8589934592}
    local ram_kb=${4:-16777216}
    local pool=${5:-128M}

    cat >"$file" <<EOF
key	value
mariadb_version	$version
dataset_bytes	$dataset
ram_total_kb	$ram_kb
innodb_buffer_pool_size	$pool
pm_max_children_sum	160
max_used_connections	170
max_connections	4096
storage_class	nvme
skip-log-bin	1
query_cache_type	1
query_cache_size	128M
backup_enabled	1
backup_interval_hours	6
bind_address	127.0.0.1
wildcard_grants	0
EOF
}

make_samples() {
    local file=$1
    local hit=$2
    local threads=$3
    local count=$4
    local log_waits=${5:-0}
    local mem_available_kb=${6:-12582912}

    awk -v hit="$hit" -v threads="$threads" -v count="$count" -v waits="$log_waits" -v available="$mem_available_kb" 'BEGIN {
        OFS="\t"
        print "timestamp","uptime","bp_hit_pct","bp_misses_s","data_read_s","rnd_next_s","tmp_disk_pct","threads_running","threads_connected","qcache_hit_pct","log_waits_delta","wait_free_delta","cpu_pct","mem_available_kb","swap_used_kb","load1","restart_flag"
        for (i=1; i<=count; i++) print "2026-07-24T00:00:00Z",i*300,99.9,1,1024,100,20,threads,50,hit,(i==1 ? waits : 0),0,5,available,0,1,0
    }' >"$file"
}

analysis_value() {
    local file=$1
    local rule=$2
    local key=$3
    awk -F '\t' -v rule="$rule" -v key="$key" '$1==rule && $5==key {print $6; exit}' "$file"
}

@test "nearest-rank percentile is deterministic" {
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 1 4
    awk -F '\t' 'NR>1 {$8=NR-1; print}' OFS='\t' "$BATS_TEST_TMPDIR/samples.tsv" >"$BATS_TEST_TMPDIR/body.tsv"
    awk 'NR==1 {print}' "$BATS_TEST_TMPDIR/samples.tsv" >"$BATS_TEST_TMPDIR/ordered.tsv"
    cat "$BATS_TEST_TMPDIR/body.tsv" >>"$BATS_TEST_TMPDIR/ordered.tsv"

    run dbtune_rules_percentile "$BATS_TEST_TMPDIR/ordered.tsv" threads_running 50
    [ "$status" -eq 0 ]
    [ "$output" = 2 ]
    run dbtune_rules_percentile "$BATS_TEST_TMPDIR/ordered.tsv" threads_running 95
    [ "$status" -eq 0 ]
    [ "$output" = 4 ]
}

@test "10.6 formulas and analysis contract produce expected proposals" {
    run dbtune_rules_analyze "$BATS_TEST_DIRNAME/../fixtures/audit-10.6.tsv" "$BATS_TEST_DIRNAME/../fixtures/samples-7d.tsv" "" "" "" 10
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' 'NF != 8 {exit 1}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-BP-SIZE innodb_buffer_pool_size)" = 8G ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-MAXCONN max_connections)" = 220 ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-IO-CAP innodb_io_capacity)" = 2000 ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-LOG-BUF innodb_log_buffer_size)" = 64M ]
}

@test "query cache matrix keeps exact 20 percent and 8 threads boundary" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 20 8 10
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' '$1=="R-QCACHE" {print $4; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = KEEP ]
    [ -z "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-QCACHE query_cache_type)" ]
}

@test "query cache matrix disables below 20 percent or above 8 threads" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples-low.tsv" 19.99 1 10
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples-low.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/low.tsv"
    [ "$(analysis_value "$BATS_TEST_TMPDIR/low.tsv" R-QCACHE query_cache_type)" = 0 ]

    make_samples "$BATS_TEST_TMPDIR/samples-busy.tsv" 20 8.01 10
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples-busy.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/busy.tsv"
    [ "$(analysis_value "$BATS_TEST_TMPDIR/busy.tsv" R-QCACHE query_cache_type)" = 0 ]
}

@test "buffer pool never shrinks an existing larger pool" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv" 10.6.18 1073741824 16777216 8G
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10 0 62914560
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' '$1=="R-BP-SIZE" {print $4 FS $5 FS $6; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = $'NO-SHRINK\t\t' ]
}

@test "six month growth is used only with at least five daily points" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv" 10.11.13 5368709120 67108864 128M
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10 0 62914560
    cat >"$BATS_TEST_TMPDIR/dbsize-4.tsv" <<'EOF'
date	db	size_bytes
2026-07-01	shop	5368709120
2026-07-02	shop	5476083302
2026-07-03	shop	5583457484
2026-07-04	shop	5690831667
EOF
    cp "$BATS_TEST_TMPDIR/dbsize-4.tsv" "$BATS_TEST_TMPDIR/dbsize-5.tsv"
    printf '%s\n' $'2026-07-05\tshop\t5798205849' >>"$BATS_TEST_TMPDIR/dbsize-5.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize-4.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/four.tsv"
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize-5.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/five.tsv"
    [ "$(analysis_value "$BATS_TEST_TMPDIR/four.tsv" R-BP-SIZE innodb_buffer_pool_size)" = 7G ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/five.tsv" R-BP-SIZE innodb_buffer_pool_size)" = 31232M ]
}

@test "version families expose removed deprecated and dynamic gates" {
    run dbtune_rules_version_family 10.6.18-MariaDB
    [ "$output" = 10.6 ]
    run dbtune_rules_version_family 10.11.13-MariaDB
    [ "$output" = 10.11 ]
    run dbtune_rules_version_family 11.4.12-MariaDB
    [ "$output" = 11.x ]

    run dbtune_rules_variable_gate 11.4.12 innodb_change_buffering
    [ "$output" = removed ]
    run dbtune_rules_variable_gate 11.4.12 innodb_flush_method
    [ "$output" = deprecated ]
    run dbtune_rules_variable_gate 10.6.18 innodb_log_file_size
    [ "$output" = restart ]
    run dbtune_rules_variable_gate 10.11.13 innodb_write_io_threads
    [ "$output" = dynamic ]
}

@test "11.x analysis warns about static landmines without proposing them" {
    run dbtune_rules_analyze "$BATS_TEST_DIRNAME/../fixtures/audit-11.4.tsv" "$BATS_TEST_DIRNAME/../fixtures/samples-7d.tsv" "" "" "" 10
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' '$1=="R-VERSION" && $4=="REMOVED" {count++} END {print count+0}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$output" = 2 ]
    run awk -F '\t' '$1=="R-VERSION" && $4=="DEPRECATED" && $7 ~ /flush_method/ {print $5}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$output" = "" ]
}

@test "minimum samples rejects analysis and preserves collected state" {
    cp "$BATS_TEST_DIRNAME/../fixtures/audit-10.6.tsv" "$DBTUNE_STATE_DIR/audit.tsv"
    cp "$BATS_TEST_DIRNAME/../fixtures/samples-7d.tsv" "$DBTUNE_STATE_DIR/samples.tsv"
    dbtune_state_write collected

    run cmd_analyze --min-samples 13
    [ "$status" -eq 65 ]
    [ "$(dbtune_state_read)" = collected ]
    [ ! -e "$DBTUNE_STATE_DIR/analysis.tsv" ]
}

@test "successful cmd_analyze transitions collected to analyzed" {
    cp "$BATS_TEST_DIRNAME/../fixtures/audit-10.6.tsv" "$DBTUNE_STATE_DIR/audit.tsv"
    cp "$BATS_TEST_DIRNAME/../fixtures/samples-7d.tsv" "$DBTUNE_STATE_DIR/samples.tsv"
    dbtune_state_write collected

    run cmd_analyze --min-samples 10
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = analyzed ]
    [ "$(awk -F '\t' 'NR==1 {print NF}' "$DBTUNE_STATE_DIR/analysis.tsv")" = 8 ]
}

@test "per-app rules emit recommendations without server config proposals" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10
    cat >"$BATS_TEST_TMPDIR/apps.tsv" <<'EOF'
app_id	is_wp	is_woocommerce	redis_active	object_cache	disable_wp_cron	system_wp_cron	autoload_mb	hpos_enabled	orders_in_posts	hpos_sync_enabled	max_log_kb_per_row	woocommerce_sessions	action_scheduler_failed	action_scheduler_retention_days	transient_count	transient_bytes	rogue_meta_value_index	redis_maxmemory_policy
shop-a	1	1	0	0	1	0	3.5	0	90000	0	26	600000	12	30	2000	20971520	1	allkeys-lru
EOF
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "$BATS_TEST_TMPDIR/apps.tsv" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' '$2=="app:shop-a" && $3=="critical" {count++} $2 ~ /^app:/ && ($5!="" || $6!="") {bad=1} END {print count+0, bad+0}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = "2 0" ]
    run awk -F '\t' '$2=="app:shop-a" {seen[$1]=1} END {print (seen["R-APP-AUTOLOAD"] && seen["R-APP-HPOS"] && seen["R-APP-LOG-TABLE"] && seen["R-APP-SESSIONS"] && seen["R-APP-AS"] && seen["R-APP-TRANSIENTS"] && seen["R-APP-META-INDEX"] && seen["R-APP-REDIS"]) ? "yes" : "no"}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$output" = yes ]
}

@test "proposal renderer consumes only server proposal records" {
    cat >"$BATS_TEST_TMPDIR/analysis.tsv" <<'EOF'
rule_id	scope	severity	verdict	proposed_key	proposed_value	evidence	reason_sk
R-A	server	high	CHANGE	max_connections	220	x	x
R-B	app:shop	critical	CHANGE	evil_app_key	1	x	x
R-C	server	info	OK			x	x
EOF
    run dbtune_rules_emit_server_proposal "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *'max_connections = 220'* ]]
    [[ "$output" != *evil_app_key* ]]
}

@test "production audit scoped TSV contract feeds server and app rules" {
    cat >"$BATS_TEST_TMPDIR/audit.tsv" <<'EOF'
mariadb.version	11.4.12-MariaDB
hw.ram_bytes	17179869184
hw.ram_available_bytes	12884901888
hw.storage_class	nvme
mariadb.dataset_bytes	4294967296
mariadb.variable.innodb_buffer_pool_size	128M
mariadb.variable.max_connections	4096
mariadb.variable.innodb_flush_log_at_trx_commit	2
mariadb.variable.log_bin	OFF
mariadb.status.max_used_connections	90
mariadb.status.key_read_requests	0
php_fpm.max_children_sum	160
runcloud.skip_log_bin	1
app.redis_ping	0
app.system_wp_cron	0
redis.maxmemory_policy	allkeys-lru
backup.schedule_count	1
security.remote_grant_count	1
security.port_3306	public
landmine.innodb_change_buffering.severity	critical
EOF
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10
    cat >"$BATS_TEST_TMPDIR/apps.tsv" <<'EOF'
app.0	type	wordpress
app.0	database	shop_db
app.0	woocommerce	1
app.0	object_cache_dropin	0
app.0	disable_wp_cron	true
EOF
    cat >"$BATS_TEST_TMPDIR/databases.tsv" <<'EOF'
app.0	autoload_bytes	4194304
app.0	legacy_order_count	90000
app.0	hpos.woocommerce_custom_orders_table_enabled	no
app.0	woocommerce_sessions_count	600000
app.0	action_scheduler.failed	12
app.0	log_table.0	email_log:1000:26214400:25.0
app.0	rogue_meta_value_index	idx_meta_value
EOF

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"

    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-BP-SIZE innodb_buffer_pool_size)" = 5376M ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-MAXCONN max_connections)" = 220 ]
    [ "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-TRXCOMMIT innodb_flush_log_at_trx_commit)" = 1 ]
    run awk -F '\t' '$2=="app:app.0" {seen[$1]=1} END {print (seen["R-APP-OBJECT-CACHE"] && seen["R-APP-WPCRON"] && seen["R-APP-AUTOLOAD"] && seen["R-APP-HPOS"] && seen["R-APP-LOG-TABLE"] && seen["R-APP-SESSIONS"] && seen["R-APP-AS"] && seen["R-APP-META-INDEX"] && seen["R-APP-REDIS"]) ? "yes" : "no"}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$output" = yes ]
    run awk -F '\t' '$1=="R-VERSION" && $4=="REMOVED" || $1=="R-SEC" && $4=="EXPOSED" {n++} END {print n+0}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$output" = 2 ]
}

@test "app scoped database metrics do not collide for a shared database" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10
    cat >"$BATS_TEST_TMPDIR/apps.tsv" <<'EOF'
app.0	type	wordpress
app.0	database	shared
app.0	table_prefix	a_
app.0	disable_wp_cron	true
app.0	system_wp_cron	1
app.1	type	wordpress
app.1	database	shared
app.1	table_prefix	b_
app.1	disable_wp_cron	true
app.1	system_wp_cron	unknown
EOF
    cat >"$BATS_TEST_TMPDIR/databases.tsv" <<'EOF'
app.0	autoload_bytes	4194304
app.1	autoload_bytes	512
EOF

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' '$1=="R-APP-AUTOLOAD" { print $2 ":" $4 } $1=="R-APP-WPCRON" { print $2 ":" $4 }' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *'app:app.0:TOO-LARGE'* ]]
    [[ "$output" != *'app:app.1:TOO-LARGE'* ]]
    [[ "$output" == *'app:app.1:UNKNOWN'* ]]
    [[ "$output" != *'app:app.0:UNKNOWN'* ]]
}
