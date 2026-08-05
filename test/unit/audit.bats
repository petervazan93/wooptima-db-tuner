#!/usr/bin/env bats

setup() {
    unset DBTUNE_UI_LANG
    BATS_TEST_TMPDIR=$(CDPATH='' cd -- "$BATS_TEST_TMPDIR" && pwd -P)
    export BATS_TEST_TMPDIR
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    export DBTUNE_HOME_ROOT="$BATS_TEST_TMPDIR/home"
    export DBTUNE_MYSQL_CONFIG_DIR="$BATS_TEST_TMPDIR/mysql"
    export DBTUNE_RUNCLOUD_CNF="$BATS_TEST_TMPDIR/mysql/runcloud.cnf"
    export DBTUNE_UNATTENDED_CONFIG="$BATS_TEST_TMPDIR/unattended"
    export DBTUNE_UNATTENDED_DIR="$BATS_TEST_TMPDIR/apt"
    export DBTUNE_CRON_ROOT="$BATS_TEST_TMPDIR/cron.d"
    export DBTUNE_ROOT_CNF="$BATS_TEST_TMPDIR/root.cnf"
    export DBTUNE_BACKUP_EVIDENCE_UID
    DBTUNE_BACKUP_EVIDENCE_UID=$(id -u)
    mkdir -p "$DBTUNE_STATE_DIR" "$DBTUNE_HOME_ROOT" "$DBTUNE_MYSQL_CONFIG_DIR" "$DBTUNE_UNATTENDED_DIR" "$DBTUNE_CRON_ROOT"
    chmod 700 "$DBTUNE_STATE_DIR"
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/05-i18n.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/20-audit.sh"
}

file_mode() {
    if [[ $(uname -s) == Darwin ]]; then
        stat -f '%Lp' "$1"
    else
        stat -c '%a' "$1"
    fi
}

append_complete_mariadb_evidence() {
    local file=$1
    local version=${2:-11.4.12-MariaDB}

    cat >>"$file" <<EOF
mariadb.version	$version
mariadb.dataset_bytes	1073741824
mariadb.variable.innodb_buffer_pool_size	1073741824
mariadb.variable.max_connections	300
mariadb.variable.innodb_io_capacity	200
mariadb.variable.innodb_io_capacity_max	2000
mariadb.variable.innodb_read_io_threads	4
mariadb.variable.innodb_write_io_threads	4
mariadb.variable.innodb_flush_neighbors	0
mariadb.variable.innodb_log_file_size	100663296
mariadb.variable.innodb_log_buffer_size	16777216
mariadb.variable.query_cache_type	OFF
mariadb.variable.query_cache_size	0
mariadb.variable.innodb_flush_log_at_trx_commit	1
mariadb.variable.innodb_doublewrite	ON
mariadb.variable.innodb_flush_method	O_DIRECT
mariadb.variable.innodb_buffer_pool_dump_at_shutdown	ON
mariadb.variable.innodb_buffer_pool_load_at_startup	ON
mariadb.variable.innodb_max_dirty_pages_pct	90.000000
mariadb.variable.innodb_max_dirty_pages_pct_lwm	0.000000
mariadb.variable.innodb_lock_wait_timeout	50
mariadb.variable.skip_name_resolve	ON
mariadb.variable.thread_cache_size	64
mariadb.variable.tmp_table_size	16777216
mariadb.variable.max_heap_table_size	16777216
mariadb.variable.table_definition_cache	400
mariadb.variable.key_buffer_size	134217728
mariadb.variable.slow_query_log	OFF
mariadb.variable.slow_query_log_file	server-slow.log
mariadb.variable.long_query_time	10.000000
mariadb.variable.datadir	/var/lib/mysql/
mariadb.variable.open_files_limit	32768
mariadb.variable.performance_schema	OFF
mariadb.variable.log_bin	OFF
mariadb.variable.wsrep_on	OFF
mariadb.status.uptime	86400
mariadb.status.max_used_connections	120
mariadb.status.key_read_requests	0
EOF
    printf '%s\t\n' mariadb.variable.log_slow_verbosity mariadb.variable.bind_address >>"$file"
}

complete_mariadb_variable_rows() {
    command awk -F '\t' '$1 ~ /^mariadb[.]variable[.]/ {sub(/^mariadb[.]variable[.]/, "", $1); print $1 "\t" $2}' \
        <(append_complete_mariadb_evidence /dev/stdout)
}

@test "wp-config parser handles variants without leaking DB_PASSWORD" {
    export WORDPRESS_DB_NAME=woo_environment
    export WORDPRESS_DB_PASSWORD=environment-secret-must-never-appear

    run dbtune_wp_config_parse "$BATS_TEST_DIRNAME/../fixtures/wp-config-variants.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *$'DB_NAME\twoo_classic'* ]]
    [[ "$output" == *$'DB_NAME\twoo_custom'* ]]
    [[ "$output" == *$'DB_NAME\twoo_const'* ]]
    [[ "$output" == *$'DB_NAME\tunresolved'* ]]
    [[ "$output" == *$'DB_NAME\twoo_multiline'* ]]
    [[ "$output" == *$'table_prefix\tshop_'* ]]
    [[ "$output" != *secret* ]]
    [[ "$output" != *DB_PASSWORD* ]]
}

@test "wp-config parser ignores all PHP comments and never dereferences root env" {
    export ROOT_DATABASE_SECRET=root-environment-secret

    run dbtune_wp_config_parse "$BATS_TEST_DIRNAME/../fixtures/wp-config-hardened.php"

    [ "$status" -eq 0 ]
    [[ "$output" == *$'DB_NAME\tshop//primary#blue/*literal*/'* ]]
    [[ "$output" == *$'table_prefix\tsecure_'* ]]
    [[ "$output" == *$'MULTISITE\tfalse'* ]]
    [[ "$output" == *$'WP_CACHE\ttrue'* ]]
    [[ "$output" != *commented_before* ]]
    [[ "$output" != *commented_after* ]]
    [[ "$output" != *secret* ]]
    [[ "$output" != *DB_PASSWORD* ]]

    run dbtune_wp_config_value "getenv('ROOT_DATABASE_SECRET')"
    [ "$status" -ne 0 ]
    [[ "$output" != *root-environment-secret* ]]
}

@test "wp-config parser handles every statement and semicolons inside strings" {
    export WORDPRESS_MULTISITE=environment-value-must-never-appear

    run dbtune_wp_config_parse "$BATS_TEST_DIRNAME/../fixtures/wp-config-multiple-statements.php"

    [ "$status" -eq 0 ]
    [ "$output" = $'DB_NAME\tshop;primary_db\ntable_prefix\tstore_\nDISABLE_WP_CRON\ttrue\nMULTISITE\tunresolved\nWP_CACHE\tfalse\nDB_NAME\tunresolved\ntable_prefix\tunresolved\nDISABLE_WP_CRON\tfalse\nDB_NAME\tmulti_line\ntable_prefix\tmulti_line_\nWP_CACHE\tunresolved' ]
    [[ "$output" != *commented* ]]
    [[ "$output" != *environment-value* ]]
    [[ "$output" != *secret* ]]
    [[ "$output" != *DB_PASSWORD* ]]
}

@test "wp-config parser ignores code-like statements inside string literals" {
    run dbtune_wp_config_parse "$BATS_TEST_DIRNAME/../fixtures/wp-config-string-decoys.php"

    [ "$status" -eq 0 ]
    [ "$output" = $'DB_NAME\treal_database\ntable_prefix\treal_\nWP_CACHE\tfalse' ]
    [[ "$output" != *fake* ]]
    [[ "$output" != *MULTISITE* ]]
}

@test "redaction covers whitespace around password separators" {
    run dbtune_redact 'password = first DB_PASSWORD   :   second passwd=third'
    [ "$status" -eq 0 ]
    [[ "$output" != *first* ]]
    [[ "$output" != *second* ]]
    [[ "$output" != *third* ]]
}

@test "audit normalization canonicalizes aliases and collapses identical duplicates" {
    cat >"$BATS_TEST_TMPDIR/aliases.tsv" <<'EOF'
mariadb_version	11.4.12-MariaDB
mariadb.version	11.4.12-MariaDB
memory_total_bytes	17179869184
hw.ram-bytes	17179869184
max_connections	300
mariadb.variable.max-connections	300
backup_status	verified
backup.status	verified
EOF

    run dbtune_audit_normalize "$BATS_TEST_TMPDIR/aliases.tsv"

    [ "$status" -eq 0 ]
    [ "$output" = $'mariadb.version\t11.4.12-MariaDB\nhw.ram_bytes\t17179869184\nmariadb.variable.max_connections\t300\nbackup.status\tverified' ]
}

@test "audit normalization rejects conflicting aliases in every order without exposing values" {
    local first second

    for first in mariadb_version mariadb.version; do
        if [[ $first == mariadb_version ]]; then second=mariadb.version; else second=mariadb_version; fi
        printf '%s\tdo-not-leak-first\n%s\tdo-not-leak-second\n' "$first" "$second" >"$BATS_TEST_TMPDIR/conflict.tsv"

        run dbtune_audit_normalize "$BATS_TEST_TMPDIR/conflict.tsv"

        [ "$status" -eq 65 ]
        [[ "$output" == *'key=mariadb.version'* ]]
        [[ "$output" == *'first_line=1; duplicate_line=2'* ]]
        [[ "$output" != *'do-not-leak-first'* ]]
        [[ "$output" != *'do-not-leak-second'* ]]
    done
}

@test "SQL wrapper applies connect and read-only statement timeouts but preserves SET GLOBAL" {
    local stub_dir="$BATS_TEST_TMPDIR/sql-stubs"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/mariadb" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DBTUNE_STATE_DIR/client-args.log"
command cat >>"$DBTUNE_STATE_DIR/client-input.log"
EOF
    chmod +x "$stub_dir/mariadb"
    PATH="$stub_dir:$PATH"
    DBTUNE_SQL_AUTH_METHOD=socket

    dbtune_sql 'SELECT 1'
    dbtune_sql 'SET GLOBAL slow_query_log=OFF;'

    run grep -F -- '--connect-timeout=5' "$DBTUNE_STATE_DIR/client-args.log"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    run grep -F 'SET SESSION max_statement_time=5;' "$DBTUNE_STATE_DIR/client-input.log"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    run grep -F 'SET GLOBAL slow_query_log=OFF;' "$DBTUNE_STATE_DIR/client-input.log"
    [ "$status" -eq 0 ]
}

@test "autoload audit includes yes on and auto values" {
    dbtune_audit_sql() {
        case $1 in
            *"TABLE_NAME='wp_options'"*) printf '1\n' ;;
            *"SUM(LENGTH(option_value))"*)
                [[ $1 == *"autoload IN ('yes','on','auto')"* ]] || return 99
                printf '3145728\t42\n'
                ;;
            *"SELECT option_name, LENGTH(option_value)"*)
                [[ $1 == *"autoload IN ('yes','on','auto')"* ]] || return 99
                printf 'large_option\t1048576\n'
                ;;
            *"option_name IN"*) printf 'woocommerce_custom_orders_table_enabled\tyes\n' ;;
            *"option_name LIKE"*) printf '5\t1000\n' ;;
            *"information_schema.TABLES"*) printf '' ;;
            *"information_schema.STATISTICS"*) printf '' ;;
            *) printf '0\n' ;;
        esac
    }

    dbtune_audit_database_metrics "$BATS_TEST_TMPDIR/databases.tsv" app.0 shop wp_

    run grep -F $'app.0\tautoload_bytes\t3145728' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.0\tautoload_count\t42' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
}

@test "autoload audit redacts quoted and separated credential option names" {
    dbtune_audit_sql() {
        case $1 in
            *"TABLE_NAME='wp_options'"*) printf '1\n' ;;
            *"SUM(LENGTH(option_value))"*) printf '3\t30\n' ;;
            *"SELECT option_name, LENGTH(option_value)"*)
                printf "'CLIENT.SECRET'\t20\nregular_option\t10\n"
                ;;
            *"option_name IN"*|*"information_schema.TABLES"*|*"information_schema.STATISTICS"*) printf '' ;;
            *"option_name LIKE"*) printf '0\t0\n' ;;
            *) printf '0\n' ;;
        esac
    }

    dbtune_audit_database_metrics "$BATS_TEST_TMPDIR/databases.tsv" app.0 shop wp_

    grep -F $'app.0\tautoload.top.0\t[REDACTED]:20' "$BATS_TEST_TMPDIR/databases.tsv"
    grep -F $'app.0\tautoload.top.1\tregular_option:10' "$BATS_TEST_TMPDIR/databases.tsv"
    run grep -F 'CLIENT.SECRET' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -ne 0 ]
}

@test "MariaDB audit query includes every rules-proposable effective variable" {
    dbtune_audit_sql() {
        case $1 in
            'SELECT VERSION()') printf '11.4.12-MariaDB\n' ;;
            *information_schema.GLOBAL_VARIABLES*) printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/variables-query" ;;
            *) printf '' ;;
        esac
    }
    : >"$BATS_TEST_TMPDIR/audit.tsv"
    : >"$BATS_TEST_TMPDIR/databases.tsv"

    dbtune_audit_collect_mariadb "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    while IFS= read -r variable; do
        run grep -F "'${variable^^}'" "$BATS_TEST_TMPDIR/variables-query"
        [ "$status" -eq 0 ]
    done < <(dbtune_audit_effective_variables)
}

@test "MariaDB audit preserves uint64 query-cache evidence and rejects inexact snapshots" {
    local malformed
    for malformed in none missing duplicate conflicting unknown extra empty signed decimal over_range; do
        : >"$BATS_TEST_TMPDIR/audit.tsv"
        : >"$BATS_TEST_TMPDIR/databases.tsv"
        dbtune_audit_sql() {
            case $1 in
                'SELECT VERSION()') printf '11.4.12-MariaDB\n' ;;
                *GLOBAL_VARIABLES*) complete_mariadb_variable_rows ;;
                *GLOBAL_STATUS*)
                    rows=$'aborted_connects\t0\ncom_select\t9007199254740993\ncreated_tmp_disk_tables\t0\ncreated_tmp_tables\t0\nhandler_read_rnd_next\t0\ninnodb_buffer_pool_pages_data\t0\ninnodb_buffer_pool_pages_free\t0\ninnodb_buffer_pool_read_requests\t0\ninnodb_buffer_pool_reads\t0\ninnodb_buffer_pool_wait_free\t0\ninnodb_data_read\t0\ninnodb_log_waits\t0\nkey_read_requests\t0\nmax_used_connections\t0\nqcache_hits\t9007199254740992\nquestions\t0\nslow_queries\t0\nthreads_connected\t0\nthreads_running\t0\nuptime\t18446744073709551615'
                    case $malformed in
                        none) ;;
                        missing) rows=$(awk -F '\t' '$1 != "qcache_hits"' <<<"$rows") ;;
                        duplicate) rows+=$'\nqcache_hits\t9007199254740992' ;;
                        conflicting) rows+=$'\nqcache_hits\t1' ;;
                        unknown) rows+=$'\nunknown_counter\t1' ;;
                        extra) rows=$(awk -F '\t' -v OFS='\t' '$1 == "qcache_hits" {$3="extra"} {print}' <<<"$rows") ;;
                        empty) rows=$(awk -F '\t' -v OFS='\t' '$1 == "qcache_hits" {$2=""} {print}' <<<"$rows") ;;
                        signed) rows=$(awk -F '\t' -v OFS='\t' '$1 == "qcache_hits" {$2="-1"} {print}' <<<"$rows") ;;
                        decimal) rows=$(awk -F '\t' -v OFS='\t' '$1 == "qcache_hits" {$2="1.5"} {print}' <<<"$rows") ;;
                        over_range) rows=$(awk -F '\t' -v OFS='\t' '$1 == "qcache_hits" {$2="18446744073709551616"} {print}' <<<"$rows") ;;
                    esac
                    printf '%s\n' "$rows"
                    ;;
                *GROUP\ BY\ TABLE_SCHEMA*) printf '' ;;
            esac
        }

        dbtune_audit_collect_mariadb "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

        if [[ $malformed == none ]]; then
            [ "$(awk -F '\t' '$1 == "mariadb.status.uptime" {print $2}' "$BATS_TEST_TMPDIR/audit.tsv")" = 18446744073709551615 ]
            [ "$(awk -F '\t' '$1 == "mariadb.query_cache_hit_pct" {print $2}' "$BATS_TEST_TMPDIR/audit.tsv")" = 100.00 ]
        else
            [ "$(awk -F '\t' '$1 == "mariadb.query_cache_hit_pct" {print $2}' "$BATS_TEST_TMPDIR/audit.tsv")" = unknown ]
            run awk -F '\t' '$1 == "mariadb.status.uptime" {found=1} END {exit found}' "$BATS_TEST_TMPDIR/audit.tsv"
            [ "$status" -eq 0 ]
        fi
    done
}

@test "landmine scan applies MariaDB version gates" {
    cat >"$DBTUNE_MYSQL_CONFIG_DIR/99-old.cnf" <<'EOF'
[mysqld]
innodb_change_buffering = all
innodb_buffer_pool_instances = 8
innodb_log_files_in_group = 2
EOF

    run dbtune_audit_scan_landmines 10.6.18 "$DBTUNE_MYSQL_CONFIG_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *'landmine.innodb_buffer_pool_instances.severity'* ]]
    [[ "$output" == *'landmine.innodb_log_files_in_group.severity'* ]]
    [[ "$output" != *'landmine.innodb_change_buffering.severity'* ]]

    run dbtune_audit_scan_landmines 11.4.12 "$DBTUNE_MYSQL_CONFIG_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'landmine.innodb_change_buffering.severity\tcritical'* ]]
}

@test "hardware audit ignores unrelated NVMe and classifies the datadir HDD RAID" {
    local stub_dir="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/nproc" <<'EOF'
#!/usr/bin/env bash
printf '12\n'
EOF
    cat >"$stub_dir/free" <<'EOF'
#!/usr/bin/env bash
printf '              total        used        free      shared  buff/cache   available\n'
printf 'Mem:    68719476736 1000 2000 0 3000 60000000000\n'
printf 'Swap:    4294967296  536870912 3758096384\n'
EOF
    cat >"$stub_dir/lsblk" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *'-s'* && $* == *'/dev/md2'* ]]; then
    printf 'md2 raid1 1 raid\n'
    printf 'sda disk 1 ST_HDD\n'
    printf 'sdb disk 1 ST_HDD\n'
elif [[ $* == *'/dev/md2'* ]]; then
    printf 'md2 raid1 0 raid\n'
    printf 'sda disk 1 ST_HDD\n'
    printf 'sdb disk 1 ST_HDD\n'
else
    printf 'nvme0n1 disk 0 Samsung_NVMe\n'
    printf 'md2 raid1 0 raid\n'
fi
EOF
    cat >"$stub_dir/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '/dev/md2\n'
EOF
    cat >"$stub_dir/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/md2 500000000 100000000 400000000 20%% /\n'
EOF
    chmod +x "$stub_dir/nproc" "$stub_dir/free" "$stub_dir/lsblk" "$stub_dir/findmnt" "$stub_dir/df"
    PATH="$stub_dir:$PATH"

    dbtune_audit_collect_hw "$BATS_TEST_TMPDIR/hardware.tsv"

    run grep -F $'hw.cpu_count\t12' "$BATS_TEST_TMPDIR/hardware.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'hw.storage_class\thdd' "$BATS_TEST_TMPDIR/hardware.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'hw.datadir_leaf.0\tsda:disk:1:ST_HDD' "$BATS_TEST_TMPDIR/hardware.tsv"
    [ "$status" -eq 0 ]
}

@test "audit query failure emits unknown and audit_error instead of zero" {
    dbtune_audit_sql() {
        case $1 in
            *"TABLE_NAME='wp_options'"*) printf '1\n' ;;
            *"SUM(LENGTH(option_value))"*) return 124 ;;
            *"SELECT option_name, LENGTH(option_value)"*) printf '' ;;
            *"option_name IN"*) printf '' ;;
            *"option_name LIKE"*) printf '0\t0\n' ;;
            *"information_schema.TABLES"*) printf '0\n' ;;
            *) printf '' ;;
        esac
    }

    dbtune_audit_database_metrics "$BATS_TEST_TMPDIR/databases.tsv" app.0 shop wp_

    run grep -F $'app.0\tautoload_bytes\tunknown' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.0\taudit_error.autoload\tquery_failed' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.0\tautoload_bytes\t0' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -ne 0 ]
}

@test "platform audit trusts only the independent backup evidence contract" {
    export DBTUNE_NOW_EPOCH=1785578400
    evidence=$(dbtune_backup_evidence_file)
    {
        printf 'schema\t1\n'
        printf 'status\tverified\n'
        printf 'source\truncloud-api\n'
        printf 'checked_at\t2026-08-01T10:00:00Z\n'
        printf 'last_success\t2026-08-01T09:00:00Z\n'
    } >"$evidence"
    chmod 600 "$evidence"
    dbtune_audit_sql() { return 1; }

    dbtune_audit_collect_platform "$BATS_TEST_TMPDIR/platform.tsv"
    run grep -F $'backup.status\tverified' "$BATS_TEST_TMPDIR/platform.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'backup.source\truncloud-api' "$BATS_TEST_TMPDIR/platform.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'backup.last_success\t2026-08-01T09:00:00Z' "$BATS_TEST_TMPDIR/platform.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'backup.age_seconds\t3600' "$BATS_TEST_TMPDIR/platform.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'backup.max_age_seconds\t86400' "$BATS_TEST_TMPDIR/platform.tsv"
    [ "$status" -eq 0 ]

    printf 'schema\t1\nstatus\tverified\nsource\truncloud-api\nchecked_at\t2026-08-01T10:00:00Z\nlast_success\tunknown\n' >"$evidence"
    chmod 600 "$evidence"
    dbtune_audit_collect_platform "$BATS_TEST_TMPDIR/invalid-platform.tsv"
    run grep -F $'backup.status\tunknown' "$BATS_TEST_TMPDIR/invalid-platform.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'backup.evidence_error\tinvalid' "$BATS_TEST_TMPDIR/invalid-platform.tsv"
    [ "$status" -eq 0 ]
}

@test "shared database metrics cron and multisite remain app scoped" {
    local app_a="$DBTUNE_HOME_ROOT/runcloud/webapps/a"
    local app_b="$DBTUNE_HOME_ROOT/runcloud/webapps/b"
    local app_c="$DBTUNE_HOME_ROOT/runcloud/webapps/c"
    mkdir -p "$app_a/wp-content/plugins/woocommerce" "$app_b/wp-content/plugins/woocommerce" "$app_c"
    touch "$app_a/wp-content/plugins/woocommerce/woocommerce.php" "$app_b/wp-content/plugins/woocommerce/woocommerce.php"
    cat >"$app_a/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'shared');
$table_prefix = 'a_';
define('DISABLE_WP_CRON', true);
EOF
    cat >"$app_b/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'shared');
$table_prefix = 'b_';
define('DISABLE_WP_CRON', true);
EOF
    cat >"$app_c/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'network');
$table_prefix = 'wp_';
define('MULTISITE', true);
EOF
    printf '* * * * * php %s/wp-cron.php\n' "$app_a" >"$DBTUNE_CRON_ROOT/apps"
    export DBTUNE_CRONTAB_FILE="$BATS_TEST_TMPDIR/no-crontab"
    dbtune_audit_sql() { return 1; }
    dbtune_audit_database_metrics() {
        if [[ $4 == a_ ]]; then
            dbtune_audit_scope_put "$1" "$2" autoload_bytes 100
        else
            dbtune_audit_scope_put "$1" "$2" autoload_bytes 200
        fi
    }

    dbtune_audit_collect_apps "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    run grep -F $'app.0\tautoload_bytes\t100' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.1\tautoload_bytes\t200' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.0\tsystem_wp_cron\t1' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.1\tsystem_wp_cron\tunknown' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.2\tmultisite_metrics\tunsupported' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.2\tautoload_bytes' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -ne 0 ]
}

@test "mixed app audit records complete partial and failed status without converting errors to empty values" {
    local failed_app="$DBTUNE_HOME_ROOT/runcloud/webapps/failed"
    local healthy_app="$DBTUNE_HOME_ROOT/runcloud/webapps/healthy"
    local partial_app="$DBTUNE_HOME_ROOT/runcloud/webapps/partial"
    mkdir -p "$failed_app" "$healthy_app" "$partial_app"
    touch "$failed_app/wp-load.php" "$healthy_app/wp-load.php" "$partial_app/wp-load.php"
    cat >"$healthy_app/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'healthy_db');
$table_prefix = 'wp_';
EOF
    cat >"$partial_app/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'partial_db');
$table_prefix = 'wp_';
EOF
    dbtune_audit_path_uid() { printf '1234\n'; }
    dbtune_audit_user_for_uid() { printf 'runcloud\n'; }
    dbtune_audit_uid_for_user() { printf '1234\n'; }
    dbtune_audit_sql() { printf 'https://shop.example\n'; }
    dbtune_audit_database_metrics() {
        if [[ $3 == healthy_db ]]; then
            dbtune_audit_scope_put "$1" "$2" autoload_bytes 0
        else
            dbtune_audit_scope_put "$1" "$2" autoload_bytes unknown
            dbtune_audit_scope_put "$1" "$2" audit_error.autoload query_failed
        fi
    }

    dbtune_audit_collect_apps "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    run grep -F $'app.0\taudit_status\tfailed' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.0\tsource_error\taudit_error.wp_config=missing' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.1\taudit_status\tcomplete' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.1\tsource_error\tnone' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.1\tautoload_bytes\t0' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.2\taudit_status\tpartial' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.2\tsource_error\taudit_error.autoload=query_failed' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.2\tautoload_bytes\tunknown' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.2\tautoload_bytes\t0' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -ne 0 ]
}

@test "complete required sections produce PASS or FINDINGS with success exit semantics" {
    cat >"$BATS_TEST_TMPDIR/status-audit.tsv" <<'EOF'
mariadb.available	1
mariadb.version	11.4.12-MariaDB
mariadb.variable.innodb_buffer_pool_size	1073741824
mariadb.variable.max_connections	300
mariadb.status.uptime	86400
mariadb.status.max_used_connections	120
mariadb.dataset_bytes	1073741824
hw.cpu_count	8
hw.ram_bytes	17179869184
hw.storage_class	nvme
app.discovery_status	complete
app.count	1
security.grants_audited	1
security.port_3306	local
EOF
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/status-audit.tsv"
    printf 'app.0\taudit_status\tcomplete\n' >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    run grep -F $'audit.overall_status\tPASS' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.exit_status\t0' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.failed_sections\tnone' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]

    awk -F '\t' 'BEGIN {print "finding.test\twarning"} $1 !~ /^audit\./ {print}' \
        "$BATS_TEST_TMPDIR/status-audit.tsv" >"$BATS_TEST_TMPDIR/findings-audit.tsv"
    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/findings-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"
    run grep -F $'audit.overall_status\tFINDINGS' "$BATS_TEST_TMPDIR/findings-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.exit_status\t0' "$BATS_TEST_TMPDIR/findings-audit.tsv"
    [ "$status" -eq 0 ]
}

@test "missing required MariaDB variable and status evidence makes the audit UNKNOWN" {
    cat >"$BATS_TEST_TMPDIR/status-audit.tsv" <<'EOF'
mariadb.available	1
hw.cpu_count	8
hw.ram_bytes	17179869184
hw.storage_class	nvme
app.discovery_status	complete
app.count	0
security.grants_audited	1
security.port_3306	local
EOF
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/complete-audit.tsv"
    command awk -F '\t' '$1 != "mariadb.variable.max_connections" && $1 != "mariadb.status.uptime" {print}' \
        "$BATS_TEST_TMPDIR/complete-audit.tsv" >>"$BATS_TEST_TMPDIR/status-audit.tsv"
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    run grep -F $'audit.section.mariadb.status\tpartial' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.section.mariadb.missing_evidence\tmariadb.variable.max_connections,mariadb.status.uptime' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.exit_status\t2' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
}

@test "missing non-sentinel proposal variable makes MariaDB evidence partial" {
    printf '%s\n' $'mariadb.available\t1' $'hw.cpu_count\t8' $'hw.ram_bytes\t17179869184' \
        $'hw.storage_class\tnvme' $'app.discovery_status\tcomplete' $'app.count\t0' \
        $'security.grants_audited\t1' $'security.port_3306\tlocal' >"$BATS_TEST_TMPDIR/status-audit.tsv"
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/complete-audit.tsv"
    command awk -F '\t' '$1 != "mariadb.variable.innodb_io_capacity_max" {print}' \
        "$BATS_TEST_TMPDIR/complete-audit.tsv" >>"$BATS_TEST_TMPDIR/status-audit.tsv"
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    grep -F $'audit.section.mariadb.missing_evidence\tmariadb.variable.innodb_io_capacity_max' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.section.mariadb.status\tpartial' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/status-audit.tsv"
}

@test "malformed numeric and enum MariaDB evidence is safely diagnosed" {
    printf '%s\n' $'mariadb.available\t1' $'hw.cpu_count\t8' $'hw.ram_bytes\t17179869184' \
        $'hw.storage_class\tnvme' $'app.discovery_status\tcomplete' $'app.count\t0' \
        $'security.grants_audited\t1' $'security.port_3306\tlocal' >"$BATS_TEST_TMPDIR/status-audit.tsv"
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/complete-audit.tsv"
    command awk -F '\t' 'BEGIN {OFS="\t"}
        $1=="mariadb.variable.innodb_io_capacity" {$2="fast"}
        $1=="mariadb.variable.key_buffer_size" {$2="unknown"}
        $1=="mariadb.variable.log_bin" {$2="MAYBE"}
        {print}
    ' "$BATS_TEST_TMPDIR/complete-audit.tsv" >>"$BATS_TEST_TMPDIR/status-audit.tsv"
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    grep -F $'audit.section.mariadb.invalid_evidence\tmariadb.variable.innodb_io_capacity=malformed,mariadb.variable.key_buffer_size=unknown,mariadb.variable.log_bin=malformed' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.section.mariadb.status\tpartial' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/status-audit.tsv"
    run grep -F 'fast' < <(command awk -F '\t' '$1=="audit.section.mariadb.invalid_evidence" {print}' "$BATS_TEST_TMPDIR/status-audit.tsv")
    [ "$status" -ne 0 ]
    run grep -F 'MAYBE' < <(command awk -F '\t' '$1=="audit.section.mariadb.invalid_evidence" {print}' "$BATS_TEST_TMPDIR/status-audit.tsv")
    [ "$status" -ne 0 ]
}

@test "required evidence conflicts become UNKNOWN without exposing values" {
    printf '%s\n' $'mariadb.available\t1' $'hw.cpu_count\t8' $'hw.ram_bytes\t17179869184' \
        $'hw.storage_class\tnvme' $'app.discovery_status\tcomplete' $'app.count\t0' \
        $'security.grants_audited\t1' $'security.port_3306\tlocal' >"$BATS_TEST_TMPDIR/status-audit.tsv"
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/status-audit.tsv"
    printf 'mariadb.variable.max_connections\tsecret-conflicting-value\n' >>"$BATS_TEST_TMPDIR/status-audit.tsv"
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_quarantine_mariadb_conflicts "$BATS_TEST_TMPDIR/status-audit.tsv"
    dbtune_audit_normalize_in_place "$BATS_TEST_TMPDIR/status-audit.tsv"
    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    run command awk -F '\t' '$1=="audit.section.mariadb.conflicting_evidence" || $1=="audit.overall_status" {print}' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'audit.section.mariadb.conflicting_evidence\tmariadb.variable.max_connections'* ]]
    [[ "$output" == *$'audit.overall_status\tUNKNOWN'* ]]
    [[ "$output" != *'secret-conflicting-value'* ]]
}

@test "MariaDB evidence schema applies supported version gates" {
    local version file

    for version in 10.6.18-MariaDB 10.11.13-MariaDB 11.4.12-MariaDB; do
        file="$BATS_TEST_TMPDIR/${version%%-*}.tsv"
        printf '%s\n' $'mariadb.available\t1' $'hw.cpu_count\t8' $'hw.ram_bytes\t17179869184' \
            $'hw.storage_class\tnvme' $'app.discovery_status\tcomplete' $'app.count\t0' \
            $'security.grants_audited\t1' $'security.port_3306\tlocal' >"$file"
        append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/complete.tsv" "$version"
        if [[ $version == 11.* ]]; then
            command awk -F '\t' '$1 != "mariadb.variable.innodb_flush_method" {print}' "$BATS_TEST_TMPDIR/complete.tsv" >>"$file"
        else
            command awk -F '\t' '{print}' "$BATS_TEST_TMPDIR/complete.tsv" >>"$file"
        fi
        rm -f "$BATS_TEST_TMPDIR/complete.tsv"
        : >"$BATS_TEST_TMPDIR/status-apps.tsv"
        : >"$BATS_TEST_TMPDIR/status-databases.tsv"
        dbtune_audit_finalize_status "$file" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"
        grep -F $'audit.section.mariadb.status\tcomplete' "$file"
        grep -F $'audit.overall_status\tPASS' "$file"
        if [[ $version == 11.* ]]; then
            grep -F $'audit.section.mariadb.optional_evidence\tmariadb.variable.innodb_flush_method=deprecated_11x' "$file"
        else
            grep -F $'audit.section.mariadb.optional_evidence\tnone' "$file"
        fi
    done

    printf '%s\n' $'mariadb.available\t1' $'hw.cpu_count\t8' $'hw.ram_bytes\t17179869184' \
        $'hw.storage_class\tnvme' $'app.discovery_status\tcomplete' $'app.count\t0' \
        $'security.grants_audited\t1' $'security.port_3306\tlocal' >"$BATS_TEST_TMPDIR/unsupported.tsv"
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/unsupported.tsv" 12.0.0-MariaDB
    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/unsupported.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"
    grep -F $'audit.section.mariadb.invalid_evidence\tmariadb.version=unsupported' "$BATS_TEST_TMPDIR/unsupported.tsv"
    grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/unsupported.tsv"
}

@test "partial required evidence produces UNKNOWN and lists affected domains" {
    cat >"$BATS_TEST_TMPDIR/status-audit.tsv" <<'EOF'
mariadb.available	1
mariadb.version	11.4.12-MariaDB
finding.global_status_query_failed	warning
hw.cpu_count	8
hw.ram_bytes	17179869184
hw.storage_class	nvme
app.discovery_status	complete
app.count	0
security.grants_audited	1
security.port_3306	local
EOF
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/status-audit.tsv"
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    run grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.partial_sections\tmariadb' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.affected_domains\tserver_tuning,database_inventory' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.exit_status\t2' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
}

@test "unknown datadir storage keeps otherwise known hardware evidence partial" {
    cat >"$BATS_TEST_TMPDIR/status-audit.tsv" <<'EOF'
mariadb.available	1
mariadb.version	11.4.12-MariaDB
mariadb.variable.innodb_buffer_pool_size	1073741824
mariadb.variable.max_connections	300
mariadb.status.uptime	86400
mariadb.status.max_used_connections	120
mariadb.dataset_bytes	1073741824
hw.cpu_count	8
hw.ram_bytes	17179869184
hw.storage_class	unknown
app.discovery_status	complete
app.count	0
security.grants_audited	1
security.port_3306	local
EOF
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/status-audit.tsv"
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    grep -F $'audit.section.hardware.status\tpartial' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.partial_sections\thardware' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.affected_domains\tcapacity_sizing,storage_tuning' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/status-audit.tsv"
    grep -F $'audit.exit_status\t2' "$BATS_TEST_TMPDIR/status-audit.tsv"
}

@test "mixed per-app evidence makes the applications section partial" {
    cat >"$BATS_TEST_TMPDIR/status-audit.tsv" <<'EOF'
mariadb.available	1
mariadb.version	11.4.12-MariaDB
mariadb.variable.innodb_buffer_pool_size	1073741824
mariadb.variable.max_connections	300
mariadb.status.uptime	86400
mariadb.status.max_used_connections	120
mariadb.dataset_bytes	1073741824
hw.cpu_count	8
hw.ram_bytes	17179869184
hw.storage_class	nvme
app.discovery_status	complete
app.count	2
security.grants_audited	1
security.port_3306	local
EOF
    append_complete_mariadb_evidence "$BATS_TEST_TMPDIR/status-audit.tsv"
    cat >"$BATS_TEST_TMPDIR/status-apps.tsv" <<'EOF'
app.0	audit_status	complete
app.1	audit_status	failed
EOF
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    run grep -F $'audit.section.applications.status\tpartial' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.overall_status\tUNKNOWN' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.affected_domains\tapplication_health,application_database' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
}

@test "fully failed required sections produce ERROR" {
    cat >"$BATS_TEST_TMPDIR/status-audit.tsv" <<'EOF'
mariadb.available	0
hw.cpu_count	0
hw.ram_bytes	0
hw.storage_class	unknown
app.discovery_status	failed
app.count	0
security.grants_audited	0
security.port_3306	unknown
EOF
    : >"$BATS_TEST_TMPDIR/status-apps.tsv"
    : >"$BATS_TEST_TMPDIR/status-databases.tsv"

    dbtune_audit_finalize_status "$BATS_TEST_TMPDIR/status-audit.tsv" "$BATS_TEST_TMPDIR/status-apps.tsv" "$BATS_TEST_TMPDIR/status-databases.tsv"

    run grep -F $'audit.overall_status\tERROR' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.failed_sections\tmariadb,hardware,applications,security' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'audit.exit_status\t1' "$BATS_TEST_TMPDIR/status-audit.tsv"
    [ "$status" -eq 0 ]
}

@test "app audit records only a canonical WordPress root with a verified non-root owner" {
    local app="$DBTUNE_HOME_ROOT/deploy-user/webapps/shop app"
    mkdir -p "$app/htdocs"
    touch "$app/htdocs/wp-load.php"
    cat >"$app/htdocs/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'shop');
$table_prefix = 'wp_';
EOF
    dbtune_audit_path_uid() { printf '1234\n'; }
    dbtune_audit_user_for_uid() { [[ $1 == 1234 ]] && printf 'deploy-user\n'; }
    dbtune_audit_uid_for_user() { [[ $1 == deploy-user ]] && printf '1234\n'; }
    dbtune_audit_sql() { return 1; }

    dbtune_audit_collect_apps "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    canonical=$(cd -P -- "$app/htdocs" && pwd -P)
    run grep -F $'app.0\twebroot\t'"$canonical" "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'app.0\towner\tdeploy-user' "$BATS_TEST_TMPDIR/apps.tsv"
    [ "$status" -eq 0 ]

    dbtune_audit_path_uid() { printf '0\n'; }
    run dbtune_audit_verified_owner "$canonical"
    [ "$status" -ne 0 ]
    [ -z "$output" ]

    dbtune_audit_path_uid() { printf '1234\n'; }
    dbtune_audit_user_for_uid() { printf 'bad owner\n'; }
    run dbtune_audit_verified_owner "$canonical"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "flat audit JSON collapses identical duplicate keys" {
    printf 'same\tfirst\nsame\tfirst\n' >"$BATS_TEST_TMPDIR/audit.tsv"
    printf 'app.0\ttype\twordpress\napp.0\ttype\tduplicate\n' >"$BATS_TEST_TMPDIR/apps.tsv"
    : >"$BATS_TEST_TMPDIR/databases.tsv"

    run dbtune_audit_json "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    [ "$status" -eq 0 ]
    [ "$output" = '{"same":"first","app.0.type":"wordpress"}' ]
}

@test "audit JSON and terminal summary sanitize controls and sensitive fields" {
    printf 'audit.hostname\tshop\033[31mred\rspoof\nmariadb.version\t11.4\033[32mgreen\rrewrite\nclient-secret\tdo-not-leak\n' >"$BATS_TEST_TMPDIR/audit.tsv"
    printf 'app.0\tpath\t/srv/shop\033[2J\napp.0\tApi-Key\talso-secret\n' >"$BATS_TEST_TMPDIR/apps.tsv"
    : >"$BATS_TEST_TMPDIR/databases.tsv"

    run dbtune_audit_json "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"audit.hostname":"shop [31mred spoof"'* ]]
    [[ "$output" == *'"app.0.path":"/srv/shop [2J"'* ]]
    [[ "$output" != *'CLIENT.SECRET'* ]]
    [[ "$output" != *'do-not-leak'* ]]
    [[ "$output" != *'also-secret'* ]]
    [[ "$output" != *$'\033'* ]]
    [[ "$output" != *$'\r'* ]]

    run dbtune_audit_summary "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *'MariaDB: 11.4 [32mgreen rewrite'* ]]
    [[ "$output" != *$'\033'* ]]
    [[ "$output" != *$'\r'* ]]
}

@test "audit summary defaults to English labels and fallbacks" {
    : >"$BATS_TEST_TMPDIR/summary-audit.tsv"
    : >"$BATS_TEST_TMPDIR/summary-apps.tsv"
    : >"$BATS_TEST_TMPDIR/summary-databases.tsv"

    run dbtune_audit_summary "$BATS_TEST_TMPDIR/summary-audit.tsv" "$BATS_TEST_TMPDIR/summary-apps.tsv" "$BATS_TEST_TMPDIR/summary-databases.tsv"

    [ "$status" -eq 0 ]
    [[ "$output" == *'Required sections: not detected. Failed: not detected. Partial: not detected.'* ]]
    [[ "$output" == *'Server: not detected CPU, not detected RAM, storage not detected.'* ]]
    [[ "$output" == *'Applications: 0. Total findings: 0, critical: 0, warnings: 0.'* ]]
}

@test "audit summary supports explicit Slovak labels and fallbacks" {
    : >"$BATS_TEST_TMPDIR/summary-audit.tsv"
    : >"$BATS_TEST_TMPDIR/summary-apps.tsv"
    : >"$BATS_TEST_TMPDIR/summary-databases.tsv"
    dbtune_i18n_set sk

    run dbtune_audit_summary "$BATS_TEST_TMPDIR/summary-audit.tsv" "$BATS_TEST_TMPDIR/summary-apps.tsv" "$BATS_TEST_TMPDIR/summary-databases.tsv"

    [ "$status" -eq 0 ]
    [[ "$output" == *'Povinne sekcie: nezistene. Zlyhane: nezistene. Ciastocne: nezistene.'* ]]
    [[ "$output" == *'Server: nezistene CPU, nezistena RAM, ulozisko nezistene.'* ]]
    [[ "$output" == *'Aplikacie: 0. Nalezy spolu: 0, kriticke: 0, varovania: 0.'* ]]
}

@test "cmd_audit publishes UNKNOWN evidence and returns exit status 2" {
    dbtune_audit_collect_mariadb() {
        dbtune_audit_put "$1" mariadb.available 1
        dbtune_audit_put "$1" mariadb.version 11.4.12-MariaDB
        dbtune_audit_put "$1" finding.global_status_query_failed warning
    }
    dbtune_audit_collect_hw() {
        dbtune_audit_put "$1" hw.cpu_count 8
        dbtune_audit_put "$1" hw.ram_bytes 17179869184
        dbtune_audit_put "$1" hw.storage_class nvme
    }
    dbtune_audit_collect_platform() {
        dbtune_audit_put "$1" security.grants_audited 1
        dbtune_audit_put "$1" security.port_3306 local
    }
    dbtune_audit_collect_apps() {
        dbtune_audit_put "$1" app.discovery_status complete
        dbtune_audit_put "$1" app.count 0
    }

    run cmd_audit --json

    [ "$status" -eq 2 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == *'"audit.overall_status":"UNKNOWN"'* ]]
    [[ "$output" == *'"audit.partial_sections":"mariadb"'* ]]
    [[ "$output" == *'"audit.affected_domains":"server_tuning,database_inventory"'* ]]
    [ -s "$DBTUNE_STATE_DIR/audit.tsv" ]
    [ "$(dbtune_state_read)" = audited ]
}

@test "cmd_audit writes mode 600 TSV files and emits one flat JSON object" {
    mkdir -p "$DBTUNE_HOME_ROOT/runcloud/webapps/shop/wp-content/plugins/woocommerce"
    touch "$DBTUNE_HOME_ROOT/runcloud/webapps/shop/wp-content/plugins/woocommerce/woocommerce.php" \
        "$DBTUNE_HOME_ROOT/runcloud/webapps/shop/wp-load.php"
    cat >"$DBTUNE_HOME_ROOT/runcloud/webapps/shop/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'shopdb');
define('DB_PASSWORD', 'audit-secret-must-never-appear');
$table_prefix = 'wp_';
define('DISABLE_WP_CRON', true);
EOF
    cat >"$DBTUNE_RUNCLOUD_CNF" <<'EOF'
[mysqld]
skip-log-bin
open_files_limit = 100000
EOF
    dbtune_audit_collect_hw() {
        dbtune_audit_put "$1" hw.cpu_count 8
        dbtune_audit_put "$1" memory_total_bytes 17179869184
        dbtune_audit_put "$1" hw.storage_class nvme
    }
    dbtune_audit_collect_platform() {
        dbtune_audit_put "$1" systemd.limit_nofile 32768
        dbtune_audit_put "$1" security.grants_audited 1
        dbtune_audit_put "$1" security.port_3306 local
        dbtune_audit_put "$1" security.root_cnf_present 0
    }
    dbtune_audit_path_uid() { printf '1234\n'; }
    dbtune_audit_user_for_uid() { printf 'runcloud\n'; }
    dbtune_audit_uid_for_user() { printf '1234\n'; }
    dbtune_audit_sql() {
        case $1 in
            'SELECT VERSION()') printf '11.4.12-MariaDB\n' ;;
            *"GLOBAL_VARIABLES"*) complete_mariadb_variable_rows ;;
            *"GLOBAL_STATUS"*) printf 'aborted_connects\t0\ncom_select\t100\ncreated_tmp_disk_tables\t0\ncreated_tmp_tables\t0\nhandler_read_rnd_next\t0\ninnodb_buffer_pool_pages_data\t0\ninnodb_buffer_pool_pages_free\t0\ninnodb_buffer_pool_read_requests\t0\ninnodb_buffer_pool_reads\t0\ninnodb_buffer_pool_wait_free\t0\ninnodb_data_read\t0\ninnodb_log_waits\t0\nkey_read_requests\t0\nmax_used_connections\t120\nqcache_hits\t50\nquestions\t0\nslow_queries\t0\nthreads_connected\t0\nthreads_running\t0\nuptime\t86400\n' ;;
            *"GROUP BY TABLE_SCHEMA"*) printf 'shopdb\t1073741824\t805306368\t268435456\t20\n' ;;
            *"TABLE_NAME='wp_options'"*) printf '1\n' ;;
            *"SUM(LENGTH(option_value))"*) printf '2097152\t100\n' ;;
            *"SELECT option_name, LENGTH(option_value)"*) printf 'sample\t1024\n' ;;
            *"option_name IN"*) printf 'woocommerce_custom_orders_table_enabled\tno\n' ;;
            *"option_name LIKE"*) printf '2\t512\n' ;;
            *"COUNT(*) FROM information_schema.TABLES"*) printf '0\n' ;;
            *) printf '' ;;
        esac
    }

    run cmd_audit --json

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == \{*\} ]]
    [[ "$output" == *'"mariadb.version":"11.4.12-MariaDB"'* ]]
    [[ "$output" == *'"hw.ram_bytes":"17179869184"'* ]]
    [[ "$output" == *'"audit.overall_status":"FINDINGS"'* ]]
    [[ "$output" == *'"audit.failed_sections":"none"'* ]]
    [[ "$output" == *'"audit.partial_sections":"none"'* ]]
    [[ "$output" != *'memory_total_bytes'* ]]
    [[ "$output" == *'"database.app.0.autoload_bytes":"2097152"'* ]]
    [[ "$output" != *secret* ]]
    [ "$(file_mode "$DBTUNE_STATE_DIR/audit.tsv")" = 600 ]
    [ "$(file_mode "$DBTUNE_STATE_DIR/apps.tsv")" = 600 ]
    [ "$(file_mode "$DBTUNE_STATE_DIR/databases.tsv")" = 600 ]
    [ "$(file_mode "$DBTUNE_STATE_DIR/audit-manifest.tsv")" = 600 ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/audit-manifest.tsv" audit_hash)" = \
        "$(dbtune_provenance_audit_hash \
            "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/audit.tsv")" \
            "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/apps.tsv")" \
            "$(dbtune_sha256_file "$DBTUNE_STATE_DIR/databases.tsv")")" ]
    [ "$(dbtune_state_read)" = audited ]

    old_run=$(dbtune_manifest_value "$DBTUNE_STATE_DIR/audit-manifest.tsv" run_id)
    printf 'sample\n' >"$DBTUNE_STATE_DIR/samples.tsv"
    printf 'analysis\n' >"$DBTUNE_STATE_DIR/analysis.tsv"
    printf 'proposal\n' >"$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf"
    printf 'manifest\n' >"$DBTUNE_STATE_DIR/proposal-manifest.tsv"
    mkdir -p "$DBTUNE_STATE_DIR/apply/history"
    printf '%s\n' "$DBTUNE_STATE_DIR/apply/history" >"$DBTUNE_STATE_DIR/apply/current"
    dbtune_state_write proposed

    run cmd_audit
    [ "$status" -eq 0 ]
    [[ "$output" == *'Wooptima DB Tuner audit status: FINDINGS.'* ]]
    [[ "$output" == *'Failed: none. Partial: none.'* ]]
    [[ "$output" == *'Total findings:'* ]]
    [[ "$output" != *secret* ]]
    [ "$(dbtune_state_read)" = audited ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/audit-manifest.tsv" run_id)" != "$old_run" ]
    [ -s "$DBTUNE_STATE_DIR/runs/$old_run/analysis.tsv" ]
    [ -s "$DBTUNE_STATE_DIR/runs/$old_run/proposed-99-zz-tuning.cnf" ]
    [ ! -e "$DBTUNE_STATE_DIR/analysis.tsv" ]
    [ ! -e "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$DBTUNE_STATE_DIR/apply/history" ]
}
