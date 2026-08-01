#!/usr/bin/env bats

setup() {
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
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

@test "state defaults to idle and is written atomically" {
    run dbtune_state_read
    [ "$status" -eq 0 ]
    [ "$output" = idle ]

    dbtune_state_write audited
    run dbtune_state_read
    [ "$status" -eq 0 ]
    [ "$output" = audited ]
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
}

@test "repeated audit preserves an advanced state" {
    dbtune_state_write applied
    dbtune_state_record_audit
    [ "$(dbtune_state_read)" = applied ]
}

@test "CLI help and version are always available" {
    run dbtune_main --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'Pouzitie: dbtune'* ]]

    run dbtune_main version
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.1.0' ]
}

@test "internal tick always exits zero" {
    run dbtune_main _tick
    [ "$status" -eq 0 ]
}
