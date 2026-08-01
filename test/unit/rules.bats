#!/usr/bin/env bats

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    mkdir -p "$DBTUNE_STATE_DIR"
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/20-audit.sh"
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
backup.status	verified
backup.source	unit-test
backup.last_success	2026-07-23T02:00:00Z
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
    local connected=${7:-50}
    local qcache_queries=${8:-1}

    awk -v hit="$hit" -v threads="$threads" -v count="$count" -v waits="$log_waits" -v available="$mem_available_kb" -v connected="$connected" -v qcache_queries="$qcache_queries" 'BEGIN {
        OFS="\t"
        print "timestamp","uptime","bp_hit_pct","bp_misses_s","data_read_s","rnd_next_s","tmp_disk_pct","threads_running","threads_connected","qcache_hit_pct","log_waits_delta","wait_free_delta","cpu_pct","mem_available_kb","swap_used_kb","load1","restart_flag","qcache_queries_delta","interval_seconds","sample_status"
        for (i=1; i<=count; i++) print "2026-07-24T00:00:00Z",i*300,99.9,1,1024,100,20,threads,connected,hit,(i==1 ? waits : 0),0,5,available,0,1,0,qcache_queries,300,"ok"
    }' >"$file"
}

analysis_value() {
    local file=$1
    local rule=$2
    local key=$3
    awk -F '\t' -v rule="$rule" -v key="$key" '$1==rule && $5==key {print $6; exit}' "$file"
}

write_current_audit_manifest() {
    : >"$DBTUNE_STATE_DIR/apps.tsv"
    : >"$DBTUNE_STATE_DIR/databases.tsv"
    dbtune_provenance_write_audit_manifest "$DBTUNE_STATE_DIR/audit-manifest.tsv" \
        test-run "$DBTUNE_STATE_DIR/audit.tsv" "$DBTUNE_STATE_DIR/apps.tsv" "$DBTUNE_STATE_DIR/databases.tsv"
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

@test "audit effective variables exactly cover the rules proposal contract" {
    run diff <(dbtune_audit_effective_variables | LC_ALL=C sort -u) <(dbtune_rules_proposable_variables | LC_ALL=C sort -u)
    [ "$status" -eq 0 ]
}

@test "missing current values block ordinary and explicit durability proposals" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 10 10 20
    awk -F '\t' '$1 != "max_connections" && $1 != "query_cache_type" && $1 != "query_cache_size" {print}' OFS='\t' \
        "$BATS_TEST_TMPDIR/audit.tsv" >"$BATS_TEST_TMPDIR/missing.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/missing.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "" "" 20 >"$BATS_TEST_TMPDIR/analysis.tsv"

    run awk -F '\t' '$1=="R-MAXCONN" || $1=="R-QCACHE" || $1=="R-TRXCOMMIT" {if ($5!="" || $6!="") bad=1} END {print bad+0}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = 0 ]
    run awk -F '\t' '$1=="R-TRXCOMMIT" {print $4, $7}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [[ "$output" == 'UNKNOWN '* ]]
    [[ "$output" == *'durability_exception=explicit'* ]]
    [[ "$output" == *'proposal_blocked=missing-current'* ]]
    run awk -F '\t' '$1=="R-PINNED" && $7 ~ /durability_exception=explicit/ {print $4, $7; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [[ "$output" == 'UNKNOWN '* ]]
    [[ "$output" == *'current=missing'* ]]
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

@test "max connections requires an authoritative non-OLS worker limit" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 1 10 0 12582912 2
    awk -F '\t' '$1 != "pm_max_children_sum" && $1 != "max_used_connections" {print} END {print "max_used_connections\t3"}' OFS='\t' "$BATS_TEST_TMPDIR/audit.tsv" >"$BATS_TEST_TMPDIR/missing.tsv"
    awk -F '\t' '$1 == "pm_max_children_sum" {$2=0} $1 == "max_used_connections" {$2=3} {print}' OFS='\t' "$BATS_TEST_TMPDIR/audit.tsv" >"$BATS_TEST_TMPDIR/zero.tsv"
    awk -F '\t' '$1 == "max_used_connections" {$2=3} {print} END {print "php_fpm.ols_stack\t1"}' OFS='\t' "$BATS_TEST_TMPDIR/audit.tsv" >"$BATS_TEST_TMPDIR/ols.tsv"

    for audit in missing zero ols; do
        dbtune_rules_analyze "$BATS_TEST_TMPDIR/$audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/$audit-analysis.tsv"
        [ "$(awk -F '\t' '$1=="R-MAXCONN" {print ($4=="UNKNOWN" && $5=="" && $6=="") ? "yes" : "no"}' "$BATS_TEST_TMPDIR/$audit-analysis.tsv")" = yes ]
    done
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

@test "query cache ignores idle windows when active windows have 100 percent hits" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 100 2 10
    awk -F '\t' 'BEGIN {OFS="\t"} NR>1 && NR<=6 {$10=0; $18=0} {print}' "$BATS_TEST_TMPDIR/samples.tsv" >"$BATS_TEST_TMPDIR/mixed.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/mixed.tsv" "" "" "" 5 >"$BATS_TEST_TMPDIR/analysis.tsv"
    run awk -F '\t' '$1=="R-QCACHE" {print $4, $5, $7; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == 'KEEP  '* ]]
    [[ "$output" == *'qcache_hit_p50=100.00%'* ]]
    [[ "$output" == *'active_windows=5'* ]]
    [[ "$output" == *'idle_windows=5'* ]]
}

@test "query cache is unknown without enough active windows and emits no proposal" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 100 2 10
    awk -F '\t' 'BEGIN {OFS="\t"} NR>3 {$10=0; $18=0} {print}' "$BATS_TEST_TMPDIR/samples.tsv" >"$BATS_TEST_TMPDIR/sparse.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/sparse.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"
    run awk -F '\t' '$1=="R-QCACHE" {print $3, $4, $5, $6, $7; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == 'medium UNKNOWN   '* ]]
    [[ "$output" == *'active_windows=2'* ]]
    [ -z "$(analysis_value "$BATS_TEST_TMPDIR/analysis.tsv" R-QCACHE query_cache_type)" ]
}

@test "legacy samples remain analyzable but query cache is unknown without a denominator" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples-v2.tsv" 100 2 10
    cut -f1-17 "$BATS_TEST_TMPDIR/samples-v2.tsv" >"$BATS_TEST_TMPDIR/samples-v1.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples-v1.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"
    run awk -F '\t' '$1=="R-QCACHE" {print $4, $5, $7; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == 'UNKNOWN  '* ]]
    [[ "$output" == *'unavailable_windows=10'* ]]
}

@test "degraded interval rows are excluded from rule metrics and valid sample count" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 100 2 10
    printf 'bad\t9999\t0\t99999\t99999\t99999\t100\t999\t999\t0\t999\t999\t999\t1\t1\t1\t0\t1\t999\tdegraded_interval\n' >>"$BATS_TEST_TMPDIR/samples.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"
    run awk -F '\t' '$1=="R-QCACHE" {print $4, $7; exit}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == 'KEEP '* ]]
    [[ "$output" == *'active_windows=10'* ]]
    [[ "$output" == *'degraded_windows=1'* ]]
    [[ "$output" == *'threads_running_p95=2.00'* ]]
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

@test "dbsize growth uses elapsed calendar days rather than point count" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv" 10.11.13 5368709120 67108864 128M
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10 0 62914560
    cat >"$BATS_TEST_TMPDIR/dbsize-4d.tsv" <<'EOF'
timestamp	database	size_bytes
2026-07-01T00:00:00Z	shop	5368709120
2026-07-02T00:00:00Z	shop	5476083302
2026-07-03T00:00:00Z	shop	5583457484
2026-07-04T00:00:00Z	shop	5690831666
2026-07-05T00:00:00Z	shop	5798205848
EOF
    cat >"$BATS_TEST_TMPDIR/dbsize-28d.tsv" <<'EOF'
timestamp	database	size_bytes
2026-07-01T00:00:00Z	shop	5368709120
2026-07-08T00:00:00Z	shop	5476083302
2026-07-15T00:00:00Z	shop	5583457484
2026-07-22T00:00:00Z	shop	5690831666
2026-07-29T00:00:00Z	shop	5798205848
EOF

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize-4d.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/4d.tsv"
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize-28d.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/28d.tsv"

    run awk -F '\t' '$1=="R-BP-SIZE" {print $7}' "$BATS_TEST_TMPDIR/4d.tsv"
    [[ "$output" == *'growth_elapsed_days=4'* ]]
    [[ "$output" == *'growth_180d=18.00G'* ]]
    run awk -F '\t' '$1=="R-BP-SIZE" {print $7}' "$BATS_TEST_TMPDIR/28d.tsv"
    [[ "$output" == *'growth_elapsed_days=28'* ]]
    [[ "$output" == *'growth_180d=2.57G'* ]]
}

@test "dbsize duplicate retries are idempotent and partial late snapshots are ignored" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv" 10.11.13 5368709120 67108864 128M
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10 0 62914560
    cat >"$BATS_TEST_TMPDIR/dbsize.tsv" <<'EOF'
timestamp	database	size_bytes
2026-07-01T00:00:00Z	shop	5000000000
2026-07-01T00:00:00Z	logs	100000000
2026-07-02T00:00:00Z	shop	5100000000
2026-07-02T00:00:00Z	logs	100000000
2026-07-03T00:00:00Z	shop	5200000000
2026-07-03T00:00:00Z	logs	100000000
2026-07-04T00:00:00Z	shop	5300000000
2026-07-04T00:00:00Z	logs	100000000
2026-07-05T00:00:00Z	shop	5400000000
2026-07-05T00:00:00Z	logs	100000000
EOF
    cp "$BATS_TEST_TMPDIR/dbsize.tsv" "$BATS_TEST_TMPDIR/dbsize-retry.tsv"
    awk 'NR>1 {print}' "$BATS_TEST_TMPDIR/dbsize.tsv" >>"$BATS_TEST_TMPDIR/dbsize-retry.tsv"
    printf '%s\n' $'2026-07-05T23:00:00Z\tshop\t50000000000' >>"$BATS_TEST_TMPDIR/dbsize-retry.tsv"

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/original.tsv"
    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize-retry.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/retry.tsv"
    run cmp "$BATS_TEST_TMPDIR/original.tsv" "$BATS_TEST_TMPDIR/retry.tsv"
    [ "$status" -eq 0 ]
}

@test "dbsize import is review evidence and excluded from automatic growth" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv" 10.11.13 10737418240 134217728 128M
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10 0 125829120
    cat >"$BATS_TEST_TMPDIR/dbsize-import.tsv" <<'EOF'
timestamp	database	size_bytes
2026-07-01T00:00:00Z	shop	10737418240
2026-07-02T00:00:00Z	shop	10844792422
2026-07-03T00:00:00Z	shop	53794465382
2026-07-04T00:00:00Z	shop	53901839564
2026-07-05T00:00:00Z	shop	54009213746
EOF

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "$BATS_TEST_TMPDIR/dbsize-import.tsv" "" "" 10 >"$BATS_TEST_TMPDIR/import.tsv"
    run awk -F '\t' '$1=="R-BP-GROWTH" {print $3, $4, $7}' "$BATS_TEST_TMPDIR/import.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == 'medium REVIEW '* ]]
    [[ "$output" == *'excluded_from_growth=true'* ]]
    run awk -F '\t' '$1=="R-BP-SIZE" {print $7}' "$BATS_TEST_TMPDIR/import.tsv"
    [[ "$output" == *'growth_180d=18.00G'* ]]
    [[ "$output" == *'discontinuities=1'* ]]
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
    write_current_audit_manifest
    dbtune_state_write collected

    run cmd_analyze --min-samples 13
    [ "$status" -eq 65 ]
    [ "$(dbtune_state_read)" = collected ]
    [ ! -e "$DBTUNE_STATE_DIR/analysis.tsv" ]
}

@test "successful cmd_analyze transitions collected to analyzed" {
    cp "$BATS_TEST_DIRNAME/../fixtures/audit-10.6.tsv" "$DBTUNE_STATE_DIR/audit.tsv"
    cp "$BATS_TEST_DIRNAME/../fixtures/samples-7d.tsv" "$DBTUNE_STATE_DIR/samples.tsv"
    write_current_audit_manifest
    dbtune_state_write collected

    run cmd_analyze --min-samples 10
    [ "$status" -eq 0 ]
    [ "$(dbtune_state_read)" = analyzed ]
    [ "$(awk -F '\t' 'NR==1 {print NF}' "$DBTUNE_STATE_DIR/analysis.tsv")" = 8 ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/analysis-manifest.tsv" run_id)" = test-run ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/analysis-manifest.tsv" samples_hash)" = "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/samples.tsv")" ]
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

@test "object cache is OK only with both drop-in and successful Redis probe" {
    make_audit "$BATS_TEST_TMPDIR/audit.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10
    cat >"$BATS_TEST_TMPDIR/apps.tsv" <<'EOF'
app_id	is_wp	object_cache_dropin	redis_active
both-up	1	1	1
redis-down	1	1	0
dropin-missing	1	0	1
both-down	1	0	0
redis-unknown	1	1	unknown
dropin-unknown	1	unknown	1
EOF

    dbtune_rules_analyze "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "$BATS_TEST_TMPDIR/apps.tsv" "" 10 >"$BATS_TEST_TMPDIR/analysis.tsv"
    run awk -F '\t' '$1=="R-APP-OBJECT-CACHE" {print $2, $3, $4}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *'app:both-up info OK'* ]]
    [[ "$output" == *'app:redis-down critical REDIS-DOWN'* ]]
    [[ "$output" == *'app:dropin-missing critical DROPIN-MISSING'* ]]
    [[ "$output" == *'app:both-down critical REDIS-DOWN'* ]]
    [[ "$output" == *'app:redis-unknown medium UNKNOWN'* ]]
    [[ "$output" == *'app:dropin-unknown medium UNKNOWN'* ]]
}

@test "backup rule obeys verified missing unknown tri-state contract" {
    make_audit "$BATS_TEST_TMPDIR/verified.tsv"
    make_samples "$BATS_TEST_TMPDIR/samples.tsv" 30 2 10
    cp "$BATS_TEST_TMPDIR/verified.tsv" "$BATS_TEST_TMPDIR/missing.tsv"
    printf '%s\n' $'backup.status\tmissing' >>"$BATS_TEST_TMPDIR/missing.tsv"
    cp "$BATS_TEST_TMPDIR/verified.tsv" "$BATS_TEST_TMPDIR/unknown.tsv"
    printf '%s\n' $'backup.status\tunknown' >>"$BATS_TEST_TMPDIR/unknown.tsv"
    awk -F '\t' '$1 != "backup.last_success" {print}' "$BATS_TEST_TMPDIR/verified.tsv" >"$BATS_TEST_TMPDIR/verified-no-success.tsv"
    awk -F '\t' '$1 != "backup.source" {print}' "$BATS_TEST_TMPDIR/missing.tsv" >"$BATS_TEST_TMPDIR/missing-no-source.tsv"
    awk -F '\t' '$1 !~ /^backup[._](status|source|last_success)$/' "$BATS_TEST_TMPDIR/verified.tsv" >"$BATS_TEST_TMPDIR/schedule-only.tsv"
    printf '%s\n' $'backup.schedule_count\t4' >>"$BATS_TEST_TMPDIR/schedule-only.tsv"

    for status in verified missing unknown verified-no-success missing-no-source schedule-only; do
        dbtune_rules_analyze "$BATS_TEST_TMPDIR/$status.tsv" "$BATS_TEST_TMPDIR/samples.tsv" "" "" "" 10 >"$BATS_TEST_TMPDIR/$status-analysis.tsv"
    done
    [ "$(awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/verified-analysis.tsv")" = 'info OK' ]
    [ "$(awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/missing-analysis.tsv")" = 'critical MISSING' ]
    [ "$(awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/unknown-analysis.tsv")" = 'medium UNKNOWN' ]
    [ "$(awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/verified-no-success-analysis.tsv")" = 'medium UNKNOWN' ]
    [ "$(awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/missing-no-source-analysis.tsv")" = 'medium UNKNOWN' ]
    [ "$(awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/schedule-only-analysis.tsv")" = 'medium UNKNOWN' ]
    run awk -F '\t' '$1=="R-BACKUP" {print $7}' "$BATS_TEST_TMPDIR/verified-analysis.tsv"
    [[ "$output" == *'source=unit-test'* ]]
    [[ "$output" == *'last_success=2026-07-23T02:00:00Z'* ]]
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
    run awk -F '\t' '$1=="R-BACKUP" {print $3, $4}' "$BATS_TEST_TMPDIR/analysis.tsv"
    [ "$output" = 'medium UNKNOWN' ]
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
