#!/usr/bin/env bats

setup() {
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
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
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

@test "redaction covers whitespace around password separators" {
    run dbtune_redact 'password = first DB_PASSWORD   :   second passwd=third'
    [ "$status" -eq 0 ]
    [[ "$output" != *first* ]]
    [[ "$output" != *second* ]]
    [[ "$output" != *third* ]]
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

@test "flat audit JSON suppresses duplicate keys" {
    printf 'same\tfirst\nsame\tsecond\n' >"$BATS_TEST_TMPDIR/audit.tsv"
    printf 'app.0\ttype\twordpress\napp.0\ttype\tduplicate\n' >"$BATS_TEST_TMPDIR/apps.tsv"
    : >"$BATS_TEST_TMPDIR/databases.tsv"

    run dbtune_audit_json "$BATS_TEST_TMPDIR/audit.tsv" "$BATS_TEST_TMPDIR/apps.tsv" "$BATS_TEST_TMPDIR/databases.tsv"

    [ "$status" -eq 0 ]
    [ "$output" = '{"same":"first","app.0.type":"wordpress"}' ]
}

@test "cmd_audit writes mode 600 TSV files and emits one flat JSON object" {
    mkdir -p "$DBTUNE_HOME_ROOT/runcloud/webapps/shop/wp-content/plugins/woocommerce"
    touch "$DBTUNE_HOME_ROOT/runcloud/webapps/shop/wp-content/plugins/woocommerce/woocommerce.php"
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
        dbtune_audit_put "$1" hw.ram_bytes 17179869184
        dbtune_audit_put "$1" hw.storage_class nvme
    }
    dbtune_audit_collect_platform() {
        dbtune_audit_put "$1" systemd.limit_nofile 32768
        dbtune_audit_put "$1" security.root_cnf_present 0
    }
    dbtune_audit_sql() {
        case $1 in
            'SELECT VERSION()') printf '11.4.12-MariaDB\n' ;;
            *"GLOBAL_VARIABLES"*) printf 'log_bin\tOFF\nopen_files_limit\t32768\nperformance_schema\tOFF\nwsrep_on\tOFF\n' ;;
            *"GLOBAL_STATUS"*) printf 'com_select\t100\nqcache_hits\t50\n' ;;
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
    [[ "$output" == *'DBTune audit bol dokonceny.'* ]]
    [[ "$output" == *'Kriticke nalezy:'* ]]
    [[ "$output" != *secret* ]]
    [ "$(dbtune_state_read)" = audited ]
    [ "$(dbtune_manifest_value "$DBTUNE_STATE_DIR/audit-manifest.tsv" run_id)" != "$old_run" ]
    [ -s "$DBTUNE_STATE_DIR/runs/$old_run/analysis.tsv" ]
    [ -s "$DBTUNE_STATE_DIR/runs/$old_run/proposed-99-zz-tuning.cnf" ]
    [ ! -e "$DBTUNE_STATE_DIR/analysis.tsv" ]
    [ ! -e "$DBTUNE_STATE_DIR/proposed-99-zz-tuning.cnf" ]
    [ "$(cat "$DBTUNE_STATE_DIR/apply/current")" = "$DBTUNE_STATE_DIR/apply/history" ]
}
