#!/usr/bin/env bats

setup() {
    BATS_TEST_TMPDIR=$(CDPATH='' cd -- "$BATS_TEST_TMPDIR" && pwd -P)
    export BATS_TEST_TMPDIR
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/05-i18n.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
}

file_mode() {
    if [[ $(uname -s) == Darwin ]]; then
        stat -f '%Lp' "$1"
    else
        stat -c '%a' "$1"
    fi
}

@test "state initialization rejects a symlinked state directory" {
    export DBTUNE_LOG_LEVEL=error
    mkdir "$BATS_TEST_TMPDIR/real-state"
    chmod 755 "$BATS_TEST_TMPDIR/real-state"
    ln -s "$BATS_TEST_TMPDIR/real-state" "$DBTUNE_STATE_DIR"

    run dbtune_init_state_dir

    [ "$status" -eq 65 ]
    [[ "$output" == *"symlink"* ]]
    [ "$(file_mode "$BATS_TEST_TMPDIR/real-state")" = 755 ]
}

@test "state initialization rejects a symlinked parent component" {
    export DBTUNE_LOG_LEVEL=error
    mkdir "$BATS_TEST_TMPDIR/real-parent"
    ln -s "$BATS_TEST_TMPDIR/real-parent" "$BATS_TEST_TMPDIR/linked-parent"
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/linked-parent/state"

    run dbtune_init_state_dir

    [ "$status" -eq 65 ]
    [[ "$output" == *"parent komponent"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/real-parent/state" ]
}

@test "state initialization rejects ownership other than the expected identity" {
    export DBTUNE_LOG_LEVEL=error
    mkdir "$DBTUNE_STATE_DIR"
    chmod 700 "$DBTUNE_STATE_DIR"
    export DBTUNE_STATE_UID=$(( $(id -u) + 1 ))
    dbtune_validate_state_parent_components() { return 0; }

    run dbtune_init_state_dir

    [ "$status" -eq 65 ]
    [[ "$output" == *"privilegovana identita"* ]]
}

@test "state initialization rejects initially group or world writable directories without touching contents" {
    export DBTUNE_LOG_LEVEL=error
    mkdir "$DBTUNE_STATE_DIR"
    printf 'attacker-content\n' >"$DBTUNE_STATE_DIR/prepared"
    chmod 777 "$DBTUNE_STATE_DIR"

    run dbtune_init_state_dir

    [ "$status" -eq 65 ]
    [[ "$output" == *"ocakavany mode"* ]]
    [ "$(file_mode "$DBTUNE_STATE_DIR")" = 777 ]
    [ "$(cat "$DBTUNE_STATE_DIR/prepared")" = attacker-content ]
}

@test "state initialization accepts a safe existing directory" {
    mkdir "$DBTUNE_STATE_DIR"
    chmod 700 "$DBTUNE_STATE_DIR"

    run dbtune_init_state_dir

    [ "$status" -eq 0 ]
    [ ! -L "$DBTUNE_STATE_DIR" ]
    [ "$(file_mode "$DBTUNE_STATE_DIR")" = 700 ]
}

@test "event lock rejects symlinks before flock or target access" {
    export DBTUNE_LOG_LEVEL=error
    export DBTUNE_EVENT_FLOCK=fake_event_flock
    mkdir "$DBTUNE_STATE_DIR"
    chmod 700 "$DBTUNE_STATE_DIR"
    printf 'unchanged\n' >"$BATS_TEST_TMPDIR/event-lock-target"
    ln -s "$BATS_TEST_TMPDIR/event-lock-target" "$DBTUNE_STATE_DIR/.events.lock"
    fake_event_flock() { touch "$BATS_TEST_TMPDIR/event-flock-called"; }

    run dbtune_event adversarial detail safe

    [ "$status" -eq 65 ]
    [[ "$output" == *"Event lock"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/event-lock-target")" = unchanged ]
    [ ! -e "$BATS_TEST_TMPDIR/event-flock-called" ]
    [ ! -e "$(dbtune_events_file)" ]
}

@test "JSON escaping produces valid escaped content" {
    run dbtune_json_escape $'quote" slash\\ line\n tab\t return\r'
    [ "$status" -eq 0 ]
    [ "$output" = 'quote\" slash\\ line\n tab\t return\r' ]
}

@test "flat JSON emitter escapes keys and values" {
    run dbtune_json_emit 'a"b' $'x\ny' plain value
    [ "$status" -eq 0 ]
    [ "$output" = '{"a\"b":"x\ny","plain":"value"}' ]
}

@test "event redaction preserves valid flat JSON" {
    dbtune_event test detail 'password=secret' quote 'a"b'
    run grep -F '"detail":"password=[REDACTED]"' "$DBTUNE_STATE_DIR/events.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"quote":"a\"b"'* ]]
}

@test "output sanitization neutralizes C0 C1 ANSI and carriage-return controls" {
    run dbtune_sanitize_text $'ok\033[31mred\033[0m\rrewrite\302\205next\tend'

    [ "$status" -eq 0 ]
    [ "$output" = 'ok [31mred [0m rewrite next end' ]
    [[ "$output" != *$'\033'* ]]
    [[ "$output" != *$'\r'* ]]
    [[ "$output" != *$'\302\205'* ]]
}

@test "sensitive keys and assignments ignore quotes case and separators" {
    local key

    for key in "'CLIENT.SECRET'" 'Api-Key' 'refresh token' 'private.key' 'DB PASSWORD'; do
        run dbtune_is_sensitive_key "$key"
        [ "$status" -eq 0 ]
    done
    run dbtune_is_sensitive_key monkey
    [ "$status" -ne 0 ]

    run dbtune_redact $'"CLIENT.SECRET" = "quoted value"; Api-Key: second; DB PASSWORD=third\rspoof'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"CLIENT.SECRET" = [REDACTED]'* ]]
    [[ "$output" == *'Api-Key: [REDACTED]'* ]]
    [[ "$output" == *'DB PASSWORD=[REDACTED] spoof'* ]]
    [[ "$output" != *'quoted value'* ]]
    [[ "$output" != *second* ]]
    [[ "$output" != *third* ]]
}

@test "state defaults to idle and is written atomically" {
    run dbtune_state_read
    [ "$status" -eq 0 ]
    [ "$output" = idle ]

    dbtune_state_write audited
    run dbtune_state_read
    [ "$status" -eq 0 ]
    [ "$output" = audited ]
}

@test "state read and mutation reject a hard-linked state file" {
    export DBTUNE_LOG_LEVEL=error
    mkdir -p "$DBTUNE_STATE_DIR"
    chmod 700 "$DBTUNE_STATE_DIR"
    printf 'proposed\n' >"$(dbtune_state_file)"
    ln "$(dbtune_state_file)" "$BATS_TEST_TMPDIR/state-alias"

    run dbtune_state_read
    [ "$status" -eq 65 ]
    [[ "$output" == *"hardlink topologiu"* ]]

    run dbtune_state_write applied
    [ "$status" -eq 65 ]
    [[ "$output" == *"hardlink topologiu"* ]]
    [ "$(cat "$(dbtune_state_file)")" = proposed ]
    [ "$(cat "$BATS_TEST_TMPDIR/state-alias")" = proposed ]
}

@test "state transitions follow the lifecycle" {
    dbtune_state_transition audited
    dbtune_state_transition collecting
    dbtune_state_transition collected
    run dbtune_state_read
    [ "$status" -eq 0 ]
    [ "$output" = collected ]

    run dbtune_state_transition applied
    [ "$status" -eq 65 ]
    [ "$(dbtune_state_read)" = collected ]
}

@test "apply guard accepts only a proposed state" {
    run dbtune_state_guard apply idle
    [ "$status" -ne 0 ]
    run dbtune_state_guard apply analyzed
    [ "$status" -ne 0 ]
    run dbtune_state_guard apply proposed
    [ "$status" -eq 0 ]
    run dbtune_state_guard audit applied
    [ "$status" -eq 0 ]
    run dbtune_state_guard audit recovery_required
    [ "$status" -ne 0 ]
    run dbtune_state_guard audit rollback_failed
    [ "$status" -ne 0 ]
}

@test "a new audit cycle resets advanced state without deleting apply recovery" {
    dbtune_state_write applied
    mkdir -p "$DBTUNE_STATE_DIR/apply/history"
    printf '%s\n' "$DBTUNE_STATE_DIR/apply/history" >"$DBTUNE_STATE_DIR/apply/current"
    dbtune_state_record_audit run-2
    [ "$(dbtune_state_read)" = audited ]
    [ -r "$DBTUNE_STATE_DIR/apply/current" ]
    run dbtune_state_guard rollback audited
    [ "$status" -eq 0 ]
}

@test "CLI help and version are always available" {
    run dbtune_main --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'Usage: dbtune <command> [options]'* ]]

    run dbtune_main version
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.3.0' ]

    run env DBTUNE_VERSION=9.9.9 "$BATS_TEST_DIRNAME/../../dist/dbtune" version
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.3.0' ]
}

@test "internal tick always exits zero" {
    run dbtune_main _tick
    [ "$status" -eq 0 ]
}
