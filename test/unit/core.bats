#!/usr/bin/env bats

setup() {
    unset DBTUNE_UI_LANG
    BATS_TEST_TMPDIR=$(CDPATH='' cd -- "$BATS_TEST_TMPDIR" && pwd -P)
    export BATS_TEST_TMPDIR
    export DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export DBTUNE_LOG_LEVEL=quiet
    export PROJECT_ROOT
    PROJECT_ROOT=$(CDPATH='' cd -- "$BATS_TEST_DIRNAME/../.." && pwd -P)
    source "$BATS_TEST_DIRNAME/../../lib/00-header.sh"
    source "$BATS_TEST_DIRNAME/../../lib/05-i18n.sh"
    source "$BATS_TEST_DIRNAME/../../lib/10-util.sh"
    source "$BATS_TEST_DIRNAME/../../lib/90-main.sh"
}

build_project_fixture() {
    local fixture="$BATS_TEST_TMPDIR/project"

    mkdir -p "$fixture"
    cp "$PROJECT_ROOT/build.sh" "$fixture/build.sh"
    cp -R "$PROJECT_ROOT/lib" "$PROJECT_ROOT/templates" "$PROJECT_ROOT/systemd" "$fixture/"
    printf '%s\n' "$fixture"
}

artifact_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

file_mode() {
    if [[ $(uname -s) == Darwin ]]; then
        stat -f '%Lp' "$1"
    else
        stat -c '%a' "$1"
    fi
}

make_fast_bats_stub() {
    local stub="$BATS_TEST_TMPDIR/bats-fast-stub"

    cat >"$stub" <<'STUB'
#!/usr/bin/env bash
{
    printf '%s\0' "$@"
    printf '\0'
} >>"$STUB_FAST_LOG"
if [[ $1 == --count ]]; then
    printf '%s\n' "${STUB_FAST_COUNT:-8}"
    exit 0
fi
printf '%s\n' '1..8'
exit 0
STUB
    chmod +x "$stub"
    printf '%s\n' "$stub"
}

fast_test_filter() {
    printf '%s\n' '^(CLI help and version are always available|delta metrics use counter differences|loaded defaults catalog is the single exact landmine definition|audit effective variables exactly cover the rules proposal contract|strict proposal grammar emits canonical records only after complete validation|apply rejects an unknown live variable before writing|installer rejects an unsupported interface language before trust checks|runtime and POSIX installer catalogs are complete)$'
}

@test "fast test runner rejects a missing Bats executable" {
    run env BATS_BIN="$BATS_TEST_TMPDIR/missing-bats" \
        "$PROJECT_ROOT/test/support/run-fast-tests.sh"

    [ "$status" -eq 69 ]
    [[ $output == *'Bats is required'* ]]
}

@test "fast test runner rejects stale selected counts before execution" {
    local stub count expected expected_filter
    stub=$(make_fast_bats_stub)
    export STUB_FAST_LOG="$BATS_TEST_TMPDIR/fast.log"
    expected="$BATS_TEST_TMPDIR/fast-expected.log"
    expected_filter=$(fast_test_filter)
    {
        printf '%s\0' --count --filter "$expected_filter" "$PROJECT_ROOT/test/unit"
        printf '\0'
    } >"$expected"

    for count in 7 9; do
        : >"$STUB_FAST_LOG"
        run env BATS_BIN="$stub" STUB_FAST_COUNT="$count" \
            "$PROJECT_ROOT/test/support/run-fast-tests.sh"
        [ "$status" -eq 65 ]
        [[ $output == *"selected $count tests; expected 8"* ]]
        cmp "$expected" "$STUB_FAST_LOG"
    done
}

@test "fast test runner executes the exact guarded smoke filter" {
    local stub expected expected_filter
    stub=$(make_fast_bats_stub)
    export STUB_FAST_LOG="$BATS_TEST_TMPDIR/fast.log"
    expected="$BATS_TEST_TMPDIR/fast-expected.log"
    expected_filter=$(fast_test_filter)
    {
        printf '%s\0' --count --filter "$expected_filter" "$PROJECT_ROOT/test/unit"
        printf '\0'
        printf '%s\0' --filter "$expected_filter" "$PROJECT_ROOT/test/unit"
        printf '\0'
    } >"$expected"

    run env BATS_BIN="$stub" STUB_FAST_COUNT=8 \
        "$PROJECT_ROOT/test/support/run-fast-tests.sh"

    [ "$status" -eq 0 ]
    cmp "$expected" "$STUB_FAST_LOG"
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
    [[ "$output" == *"parent component"* ]]
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
    [[ "$output" == *"privileged identity"* ]]
}

@test "state initialization rejects initially group or world writable directories without touching contents" {
    export DBTUNE_LOG_LEVEL=error
    mkdir "$DBTUNE_STATE_DIR"
    printf 'attacker-content\n' >"$DBTUNE_STATE_DIR/prepared"
    chmod 777 "$DBTUNE_STATE_DIR"

    run dbtune_init_state_dir

    [ "$status" -eq 65 ]
    [[ "$output" == *"expected mode"* ]]
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

@test "utility failures default to English" {
    export DBTUNE_LOG_LEVEL=error

    run dbtune_path ''

    [ "$status" -eq 64 ]
    [[ "$output" == *'Invalid state file name: <empty>'* ]]
}

@test "utility failures support explicit Slovak" {
    export DBTUNE_LOG_LEVEL=error
    dbtune_i18n_set sk

    run dbtune_require_uint --days invalid

    [ "$status" -eq 64 ]
    [[ "$output" == *'--days musi byt cele nezaporne cislo'* ]]
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
    [[ "$output" == *"hard-link topology"* ]]

    run dbtune_state_write applied
    [ "$status" -eq 65 ]
    [[ "$output" == *"hard-link topology"* ]]
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
    [ "$output" = 'dbtune 0.4.1' ]

    run env DBTUNE_VERSION=9.9.9 "$BATS_TEST_DIRNAME/../../dist/dbtune" version
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.4.1' ]
}

@test "internal tick always exits zero" {
    run dbtune_main _tick
    [ "$status" -eq 0 ]
}

@test "build profile validation preserves existing production artifacts atomically" {
    local fixture production_hash checksum_hash invocation

    fixture=$(build_project_fixture)
    "$fixture/build.sh"
    production_hash=$(artifact_hash "$fixture/dist/dbtune")
    checksum_hash=$(artifact_hash "$fixture/dist/dbtune.sha256")

    for invocation in '--profile' '--profile unknown' '--profile production extra' \
        '--profile production --profile integration-test'; do
        read -r -a arguments <<<"$invocation"
        run "$fixture/build.sh" "${arguments[@]}"
        [ "$status" -ne 0 ]
        [ "$(artifact_hash "$fixture/dist/dbtune")" = "$production_hash" ]
        [ "$(artifact_hash "$fixture/dist/dbtune.sha256")" = "$checksum_hash" ]
    done
}

@test "build profiles embed one immutable marker and isolate integration output" {
    local fixture production_hash checksum_hash

    fixture=$(build_project_fixture)
    run "$fixture/build.sh"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^readonly DBTUNE_ARTIFACT_PROFILE=production$' "$fixture/dist/dbtune")" -eq 1 ]
    ! grep -q 'DBTUNE_ARTIFACT_PROFILE=source-test\|DBTUNE_ARTIFACT_PROFILE=integration-test' "$fixture/dist/dbtune"

    run "$fixture/build.sh" --profile production
    [ "$status" -eq 0 ]
    [ "$(grep -c '^readonly DBTUNE_ARTIFACT_PROFILE=production$' "$fixture/dist/dbtune")" -eq 1 ]
    production_hash=$(artifact_hash "$fixture/dist/dbtune")
    checksum_hash=$(artifact_hash "$fixture/dist/dbtune.sha256")

    run "$fixture/build.sh" --profile integration-test
    [ "$status" -eq 0 ]
    [ -x "$fixture/dist/dbtune-integration" ]
    [ "$(grep -c '^readonly DBTUNE_ARTIFACT_PROFILE=integration-test$' "$fixture/dist/dbtune-integration")" -eq 1 ]
    ! grep -q 'DBTUNE_ARTIFACT_PROFILE=source-test\|DBTUNE_ARTIFACT_PROFILE=production' "$fixture/dist/dbtune-integration"
    [ "$(artifact_hash "$fixture/dist/dbtune")" = "$production_hash" ]
    [ "$(artifact_hash "$fixture/dist/dbtune.sha256")" = "$checksum_hash" ]
}

@test "default production build validates embedded assets through a test profile" {
    local fixture production_hash checksum_hash real_base64 stub_bin

    fixture=$(build_project_fixture)
    "$fixture/build.sh"
    production_hash=$(artifact_hash "$fixture/dist/dbtune")
    checksum_hash=$(artifact_hash "$fixture/dist/dbtune.sha256")
    real_base64=$(command -v base64)
    stub_bin="$BATS_TEST_TMPDIR/base64-stub"
    mkdir "$stub_bin"
    cat >"$stub_bin/base64" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == --decode || ${1:-} == -D ]]; then
    exec "$REAL_BASE64" "$@"
fi
printf '%s\n' 'not-valid-base64!'
STUB
    chmod +x "$stub_bin/base64"

    run env PATH="$stub_bin:$PATH" REAL_BASE64="$real_base64" "$fixture/build.sh"

    [ "$status" -ne 0 ]
    [ "$(artifact_hash "$fixture/dist/dbtune")" = "$production_hash" ]
    [ "$(artifact_hash "$fixture/dist/dbtune.sha256")" = "$checksum_hash" ]
}

@test "production artifact sanitizes hostile runtime overrides" {
    local fixture marker marker_command bash_env runtime_dump

    fixture=$(build_project_fixture)
    "$fixture/build.sh"
    marker="$BATS_TEST_TMPDIR/override-marker"
    marker_command="$BATS_TEST_TMPDIR/marker-command"
    cat >"$marker_command" <<'STUB'
#!/usr/bin/env bash
touch "$DBTUNE_OVERRIDE_MARKER"
STUB
    chmod +x "$marker_command"

    run env \
        DBTUNE_FLOCK="$marker_command" \
        DBTUNE_SYSTEMCTL="$marker_command" \
        DBTUNE_SQL_AUTH_METHOD=defaults \
        DBTUNE_SQL_DEFAULTS_FILE="$BATS_TEST_TMPDIR/attacker.cnf" \
        DBTUNE_PUBLISH_FAULT_HOOK="$marker_command" \
        DBTUNE_NOW_EPOCH=1 \
        DBTUNE_MIN_APPLY_SAMPLES=0 \
        DBTUNE_OVERRIDE_MARKER="$marker" \
        DBTUNE_PROGRAM=attacker \
        DBTUNE_DEFAULT_DAYS=999 \
        DBTUNE_ARTIFACT_PROFILE=integration-test \
        "$fixture/dist/dbtune" status

    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]

    run env DBTUNE_PROGRAM=attacker "$fixture/dist/dbtune" version
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.4.1' ]

    bash_env="$BATS_TEST_TMPDIR/runtime-dump-env"
    runtime_dump="$BATS_TEST_TMPDIR/runtime-dump"
    cat >"$bash_env" <<'ENV'
trap 'printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${DBTUNE_PROGRAM_PATH-unset}" "$DBTUNE_PROGRAM" "$DBTUNE_UI_LANG" "$DBTUNE_STATE_DIR" "$DBTUNE_CONFIG_TARGET" "$DBTUNE_CONFIG_ALLOWED_DIR" "$DBTUNE_ROOT_CNF" "$DBTUNE_LOG_LEVEL" "$DBTUNE_MAX_BACKUP_AGE_SECONDS" >"$RUNTIME_DUMP"' EXIT
ENV
    run env BASH_ENV="$bash_env" RUNTIME_DUMP="$runtime_dump" \
        DBTUNE_PROGRAM_PATH="$marker_command" DBTUNE_UI_LANG=sk \
        DBTUNE_STATE_DIR="$BATS_TEST_TMPDIR/operator-state" \
        DBTUNE_CONFIG_TARGET="$BATS_TEST_TMPDIR/operator-target.cnf" \
        DBTUNE_CONFIG_ALLOWED_DIR="$BATS_TEST_TMPDIR/operator-config" \
        DBTUNE_ROOT_CNF="$BATS_TEST_TMPDIR/operator-root.cnf" \
        DBTUNE_LOG_LEVEL=quiet DBTUNE_MAX_BACKUP_AGE_SECONDS=123 \
        "$fixture/dist/dbtune" version
    [ "$status" -eq 0 ]
    [ "$(cat "$runtime_dump")" = "unset"$'\t'"dbtune"$'\t'"sk"$'\t'"$BATS_TEST_TMPDIR/operator-state"$'\t'"$BATS_TEST_TMPDIR/operator-target.cnf"$'\t'"$BATS_TEST_TMPDIR/operator-config"$'\t'"$BATS_TEST_TMPDIR/operator-root.cnf"$'\t'"quiet"$'\t'"123" ]
}

@test "production artifact cannot be sourced and still executes through bash" {
    local fixture

    fixture=$(build_project_fixture)
    "$fixture/build.sh"

    run bash -c 'source "$1"; result=$?; declare -F cmd_apply >/dev/null; defined=$?; printf "%s %s\n" "$result" "$defined"; exit "$result"' _ "$fixture/dist/dbtune"
    [ "$status" -eq 65 ]
    [ "$output" = '65 1' ]

    run bash -c 'source "$0"; result=$?; declare -F cmd_apply >/dev/null; defined=$?; printf "%s %s\n" "$result" "$defined"; exit "$result"' "$fixture/dist/dbtune"
    [ "$status" -eq 65 ]
    [ "$output" = '65 1' ]

    run bash "$fixture/dist/dbtune" version
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.4.1' ]
}

@test "environment cannot switch production profile or freeze sanitization" {
    local fixture bash_env

    fixture=$(build_project_fixture)
    "$fixture/build.sh"
    bash_env="$BATS_TEST_TMPDIR/bash-env"
    printf '%s\n' 'readonly PATH' >"$bash_env"

    run env BASH_ENV="$bash_env" bash "$fixture/dist/dbtune" version
    [ "$status" -eq 65 ]

    run bash -c 'readonly DBTUNE_ARTIFACT_PROFILE=bad; source "$1"' _ "$fixture/dist/dbtune"
    [ "$status" -eq 65 ]

    printf '%s\n' 'readonly DBTUNE_ARTIFACT_VERSION=bad' >"$bash_env"
    run env BASH_ENV="$bash_env" bash "$fixture/dist/dbtune" version
    [ "$status" -eq 65 ]
}

@test "exported command functions cannot cross the production boundary" {
    local fixture marker

    fixture=$(build_project_fixture)
    "$fixture/build.sh"
    marker="$BATS_TEST_TMPDIR/exported-function-marker"

    run env ARTIFACT="$fixture/dist/dbtune" MARKER="$marker" bash -c '
        export DBTUNE_STATE_DIR="${MARKER}.state"
        flock() { touch "$MARKER"; return 1; }
        export -f flock
        exec "$ARTIFACT" _tick
    '
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]

    run env ARTIFACT="$fixture/dist/dbtune" MARKER="$marker" bash -c '
        printf() { touch "$MARKER"; builtin printf "$@"; }
        export -f printf
        exec "$ARTIFACT" version
    '
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.4.1' ]
    [ ! -e "$marker" ]

    run env ARTIFACT="$fixture/dist/dbtune" bash -c '
        dbtune_dispatch() { return 99; }
        export -f dbtune_dispatch
        exec "$ARTIFACT" version
    '
    [ "$status" -eq 0 ]
    [ "$output" = 'dbtune 0.4.1' ]
}

@test "runtime environment contract classifies every production symbol" {
    run "$PROJECT_ROOT/test/support/check-runtime-environment.sh"
    [ "$status" -eq 0 ]
}

@test "runtime command resolver accepts only absolute trusted executables" {
    local trusted

    run dbtune_runtime_command_path 'bad/name'
    [ "$status" -eq 64 ]
    run dbtune_runtime_command_path dbtune-command-that-does-not-exist
    [ "$status" -eq 69 ]

    PATH=/bin:/usr/bin
    trusted=$(dbtune_runtime_command_path bash)
    [[ $trusted == /* ]]
    [ -f "$trusted" ]
    [ ! -L "$trusted" ]
    [ -x "$trusted" ]

    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$BATS_TEST_TMPDIR/untrusted-command"
    chmod +x "$BATS_TEST_TMPDIR/untrusted-command"
    PATH="$BATS_TEST_TMPDIR:$PATH" run dbtune_runtime_command_path untrusted-command
    [ "$status" -eq 69 ]
}

@test "runtime environment checker names duplicate and unclassified symbols" {
    local fixture="$BATS_TEST_TMPDIR/checker-project"

    mkdir -p "$fixture/test/support"
    cp -R "$PROJECT_ROOT/lib" "$fixture/"
    cp "$PROJECT_ROOT/test/support/check-runtime-environment.sh" "$fixture/test/support/"
    printf '%s\n' 'DBTUNE_UNCLASSIFIED_PROBE=1' >>"$fixture/lib/90-main.sh"
    run "$fixture/test/support/check-runtime-environment.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'unclassified runtime environment symbol: DBTUNE_UNCLASSIFIED_PROBE'* ]]

    cp "$PROJECT_ROOT/lib/90-main.sh" "$fixture/lib/90-main.sh"
    awk '
        { print }
        $0 == "DBTUNE_ARTIFACT_PROFILE\timmutable" { print }
    ' "$fixture/lib/10-util.sh" >"$fixture/lib/10-util.sh.new"
    mv "$fixture/lib/10-util.sh.new" "$fixture/lib/10-util.sh"
    run "$fixture/test/support/check-runtime-environment.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'duplicate runtime environment classification: DBTUNE_ARTIFACT_PROFILE'* ]]
}
