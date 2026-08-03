#!/usr/bin/env bats

setup() {
    unset DBTUNE_UI_LANG
    export DBTUNE_LOG_LEVEL=error
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
    [[ "$output" == *'Show this help'* ]]
}

@test "explicit Slovak interface language selects Slovak" {
    export DBTUNE_UI_LANG=sk

    run dbtune_main --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Pouzitie: dbtune <prikaz> [volby]'* ]]
    [[ "$output" == *'Prikazy:'* ]]
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
