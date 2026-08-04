#!/usr/bin/env bats

setup() {
    unset DBTUNE_UI_LANG
    export DBTUNE_LOG_LEVEL=error
    PROJECT_ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)
    CATALOG_CHECK="$BATS_TEST_DIRNAME/../support/check-catalog.sh"
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/05-i18n.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
}

@test "unset interface language defaults to English" {
    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage: dbtune <command> [options]'* ]]
    [[ "$output" != *'Pouzitie:'* ]]
}

@test "empty interface language defaults to English" {
    export DBTUNE_UI_LANG=

    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage: dbtune <command> [options]'* ]]
}

@test "explicit English interface language selects English" {
    export DBTUNE_UI_LANG=en

    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == *'Commands:'* ]]
    [[ "$output" == *'collect start [--days N] [--long-query-time SECONDS]'* ]]
    [[ "$output" == *'Show this help'* ]]
}

@test "explicit Slovak interface language selects Slovak" {
    export DBTUNE_UI_LANG=sk

    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Pouzitie: dbtune <prikaz> [volby]'* ]]
    [[ "$output" == *'Prikazy:'* ]]
    [[ "$output" == *'collect start [--days N] [--long-query-time SECONDS]'* ]]
}

@test "unsupported interface language exits before command dispatch" {
    export DBTUNE_UI_LANG=de
    dbtune_dispatch() {
        touch "$BATS_TEST_TMPDIR/dispatched"
    }

    run dbtune_main audit

    [ "$status" -eq 64 ]
    [ "$output" = "Unsupported interface language: de (expected en or sk)" ]
    [ ! -e "$BATS_TEST_TMPDIR/dispatched" ]
}

@test "operating system locale does not select the interface language" {
    export LANG=sk_SK.UTF-8

    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage: dbtune <command> [options]'* ]]
    [[ "$output" != *'Pouzitie:'* ]]
}

@test "message locale does not select the interface language" {
    export LC_MESSAGES=sk_SK.UTF-8

    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage: dbtune <command> [options]'* ]]
    [[ "$output" != *'Pouzitie:'* ]]
}

@test "catalog formatting treats dynamic values as arguments" {
    dbtune_i18n_set en

    run dbtune_printf cli_unknown_command 'audit %s %n'

    [ "$status" -eq 0 ]
    [ "$output" = 'Unknown command: audit %s %n' ]
}

@test "missing catalog messages fail without evaluating the message ID" {
    dbtune_i18n_set en

    run dbtune_printf 'missing_%s_%n' injected

    [ "$status" -eq 70 ]
    [ "$output" = 'dbtune: missing interface message: missing_%s_%n' ]
    [[ "$output" != *injected* ]]
}

@test "dispatcher diagnostics use the selected catalog" {
    export DBTUNE_UI_LANG=en

    run dbtune_main unknown
    [ "$status" -eq 64 ]
    [[ "$output" == *'Unknown command: unknown'* ]]

    run dbtune_main collect unknown
    [ "$status" -eq 64 ]
    [[ "$output" == *'Usage: dbtune collect start|status|stop'* ]]

    dbtune_i18n_set sk
    run dbtune_call_command cmd_missing
    [ "$status" -eq 69 ]
    [[ "$output" == *"Modul pre 'cmd_missing' nie je v tomto builde dostupny"* ]]
}

@test "runtime and POSIX installer catalogs are complete" {
    run sh "$CATALOG_CHECK" runtime "$PROJECT_ROOT/lib/05-i18n.sh" "$PROJECT_ROOT"/lib/*.sh
    [ "$status" -eq 0 ]

    run sh "$CATALOG_CHECK" installer "$PROJECT_ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "catalog checker rejects a missing language catalog" {
    cat >"$BATS_TEST_TMPDIR/catalog.sh" <<'EOF'
case "$language:$message_id" in
    en:shared) message='English' ;;
esac
EOF
    printf '%s\n' 'dbtune_msg shared' >"$BATS_TEST_TMPDIR/source.sh"

    run sh "$CATALOG_CHECK" runtime "$BATS_TEST_TMPDIR/catalog.sh" "$BATS_TEST_TMPDIR/source.sh"

    [ "$status" -eq 1 ]
    [ "$output" = 'catalog: missing sk IDs' ]
}

@test "catalog checker rejects a missing catalog ID" {
    cat >"$BATS_TEST_TMPDIR/catalog.sh" <<'EOF'
case "$language:$message_id" in
    en:) message='Missing ID' ;;
    en:shared) message='English' ;;
    sk:shared) message='Slovak' ;;
esac
EOF
    printf '%s\n' 'dbtune_msg shared' >"$BATS_TEST_TMPDIR/source.sh"

    run sh "$CATALOG_CHECK" runtime "$BATS_TEST_TMPDIR/catalog.sh" "$BATS_TEST_TMPDIR/source.sh"

    [ "$status" -eq 1 ]
    [ "$output" = 'catalog: missing ID: en' ]
}

@test "catalog checker rejects an English and Slovak ID-set mismatch" {
    cat >"$BATS_TEST_TMPDIR/catalog.sh" <<'EOF'
case "$language:$message_id" in
    en:shared) message='English' ;;
    sk:shared) message='Slovak' ;;
    en:english_only) message='English only' ;;
esac
EOF
    printf '%s\n' 'dbtune_msg shared' >"$BATS_TEST_TMPDIR/source.sh"

    run sh "$CATALOG_CHECK" runtime "$BATS_TEST_TMPDIR/catalog.sh" "$BATS_TEST_TMPDIR/source.sh"

    [ "$status" -eq 1 ]
    [ "$output" = 'catalog: en/sk ID-set mismatch: english_only' ]
}

@test "catalog checker rejects duplicate IDs" {
    cat >"$BATS_TEST_TMPDIR/catalog.sh" <<'EOF'
case "$language:$message_id" in
    en:shared) message='English' ;;
    en:shared) message='Duplicate' ;;
    sk:shared) message='Slovak' ;;
esac
EOF
    printf '%s\n' 'dbtune_msg shared' >"$BATS_TEST_TMPDIR/source.sh"

    run sh "$CATALOG_CHECK" runtime "$BATS_TEST_TMPDIR/catalog.sh" "$BATS_TEST_TMPDIR/source.sh"

    [ "$status" -eq 1 ]
    [ "$output" = 'catalog: duplicate ID: en:shared' ]
}

@test "catalog checker rejects statically used runtime IDs absent from the catalog" {
    cat >"$BATS_TEST_TMPDIR/catalog.sh" <<'EOF'
case "$language:$message_id" in
    en:shared) message='English' ;;
    sk:shared) message='Slovak' ;;
esac
EOF
    printf '%s\n' 'dbtune_printf missing_id value' >"$BATS_TEST_TMPDIR/source.sh"

    run sh "$CATALOG_CHECK" runtime "$BATS_TEST_TMPDIR/catalog.sh" "$BATS_TEST_TMPDIR/source.sh"

    [ "$status" -eq 1 ]
    [ "$output" = 'catalog: static runtime ID absent from catalog: missing_id' ]
}

@test "catalog checker rejects statically used POSIX installer IDs absent from the catalog" {
    cat >"$BATS_TEST_TMPDIR/installer.sh" <<'EOF'
installer_message() {
    case "$UI_LANG:$1" in
        en:shared) INSTALLER_MESSAGE='English' ;;
        sk:shared) INSTALLER_MESSAGE='Slovak' ;;
    esac
}
installer_printf missing_id
EOF

    run sh "$CATALOG_CHECK" installer "$BATS_TEST_TMPDIR/installer.sh"

    [ "$status" -eq 1 ]
    [ "$output" = 'catalog: static installer ID absent from catalog: missing_id' ]
}
