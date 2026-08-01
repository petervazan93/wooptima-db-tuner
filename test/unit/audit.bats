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
    [[ "$output" == *$'DB_NAME\twoo_environment'* ]]
    [[ "$output" == *$'DB_NAME\twoo_multiline'* ]]
    [[ "$output" == *$'table_prefix\tshop_'* ]]
    [[ "$output" != *secret* ]]
    [[ "$output" != *DB_PASSWORD* ]]
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

    dbtune_audit_database_metrics "$BATS_TEST_TMPDIR/databases.tsv" shop wp_

    run grep -F $'shop\tautoload_bytes\t3145728' "$BATS_TEST_TMPDIR/databases.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'shop\tautoload_count\t42' "$BATS_TEST_TMPDIR/databases.tsv"
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

@test "hardware audit uses command stubs and resolves NVMe md slaves" {
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
if [[ $* == *'/dev/md2'* ]]; then
    printf 'md2 raid1 0 raid\n'
    printf 'nvme0n1 disk 0 Samsung_NVMe\n'
    printf 'nvme1n1 disk 0 Samsung_NVMe\n'
else
    printf 'md2 raid1 0 raid\n'
fi
EOF
    cat >"$stub_dir/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/md2 500000000 100000000 400000000 20%% /\n'
EOF
    chmod +x "$stub_dir/nproc" "$stub_dir/free" "$stub_dir/lsblk" "$stub_dir/df"
    PATH="$stub_dir:$PATH"

    dbtune_audit_collect_hw "$BATS_TEST_TMPDIR/hardware.tsv"

    run grep -F $'hw.cpu_count\t12' "$BATS_TEST_TMPDIR/hardware.tsv"
    [ "$status" -eq 0 ]
    run grep -F $'hw.storage_class\tnvme' "$BATS_TEST_TMPDIR/hardware.tsv"
    [ "$status" -eq 0 ]
    run grep -F 'nvme0n1:disk:0:Samsung_NVMe' "$BATS_TEST_TMPDIR/hardware.tsv"
    [ "$status" -eq 0 ]
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
    [[ "$output" == *'"database.shopdb.autoload_bytes":"2097152"'* ]]
    [[ "$output" != *secret* ]]
    [ "$(file_mode "$DBTUNE_STATE_DIR/audit.tsv")" = 600 ]
    [ "$(file_mode "$DBTUNE_STATE_DIR/apps.tsv")" = 600 ]
    [ "$(file_mode "$DBTUNE_STATE_DIR/databases.tsv")" = 600 ]
    [ "$(dbtune_state_read)" = audited ]

    run cmd_audit
    [ "$status" -eq 0 ]
    [[ "$output" == *'DBTune audit bol dokonceny.'* ]]
    [[ "$output" == *'Kriticke nalezy:'* ]]
    [[ "$output" != *secret* ]]
}
