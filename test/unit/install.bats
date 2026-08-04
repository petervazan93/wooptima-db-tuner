#!/usr/bin/env bats

setup() {
    export PRIVILEGED_TEST_ROOT=
    export PROJECT_ROOT
    PROJECT_ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)
    export RELEASE_DIR="$BATS_TEST_TMPDIR/release"
    export INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
    export STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
    export ATTESTATION_LOG="$BATS_TEST_TMPDIR/attestation.log"
    export SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
    export REAL_CURL
    export REAL_ID
    export REAL_STAT
    REAL_CURL=$(command -v curl)
    REAL_ID=$(command -v id)
    REAL_STAT=$(command -v stat)
    mkdir -p "$RELEASE_DIR" "$INSTALL_DIR" "$STUB_BIN"
cat >"$STUB_BIN/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$ATTESTATION_LOG"
[ "${STUB_ATTESTATION_STATUS:-0}" -eq 0 ] || exit "$STUB_ATTESTATION_STATUS"
[ "$1" = attestation ] && [ "$2" = verify ] || exit 2
args=" $* "
case $args in *' --repo petervazan93/wooptima-db-tuner '*) ;; *) exit 2 ;; esac
case $args in *' --signer-workflow petervazan93/wooptima-db-tuner/.github/workflows/release.yml '*) ;; *) exit 2 ;; esac
case $args in *' --bundle '*'/dbtune-attestation.jsonl '*) ;; *) exit 2 ;; esac
case $args in *' --deny-self-hosted-runners '*) ;; *) exit 2 ;; esac
source_ref=
while [ "$#" -gt 0 ]; do
    if [ "$1" = --source-ref ]; then
        [ "$#" -ge 2 ] || exit 2
        source_ref=$2
        break
    fi
    shift
done
if [ -n "$source_ref" ] && [ "$source_ref" != "${STUB_ATTESTATION_SOURCE_REF:-refs/tags/v0.4.1}" ]; then
    exit 1
fi
STUB
cat >"$STUB_BIN/curl" <<'STUB'
#!/bin/sh
case " $* " in
    *' https://api.github.com/repos/petervazan93/wooptima-db-tuner/releases/latest '*)
        printf '{"tag_name":"%s"}\n' "${STUB_RELEASE_TAG:-v0.4.1}"
        exit 0
        ;;
esac
exec "$REAL_CURL" "$@"
STUB
cat >"$STUB_BIN/id" <<'STUB'
#!/bin/sh
if [ "$1" = -u ] && [ -n "${STUB_ID_UID:-}" ]; then
    printf '%s\n' "$STUB_ID_UID"
    exit 0
fi
exec "$REAL_ID" "$@"
STUB
cat >"$STUB_BIN/stat" <<'STUB'
#!/bin/sh
if [ -n "${STUB_STAT_UID:-}" ] && [ -n "${STUB_STAT_MODE:-}" ]; then
    printf '%s %s\n' "$STUB_STAT_UID" "$STUB_STAT_MODE"
    exit 0
fi
exec "$REAL_STAT" "$@"
STUB
cat >"$STUB_BIN/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$SUDO_LOG"
[ "${STUB_SUDO_EXEC:-0}" -eq 1 ] || exit 97
command=$1
shift
if [ "$command" = install ] && [ "${1:-}" = -o ]; then
    shift 4
    "$command" "$@" || exit $?
    if [ -n "${STUB_SWAP_DESTINATION:-}" ]; then
        ln -s "$STUB_SWAP_TARGET" "$STUB_SWAP_DESTINATION"
    fi
    exit 0
fi
exec "$command" "$@"
STUB
    chmod +x "$STUB_BIN/gh" "$STUB_BIN/curl" "$STUB_BIN/id" "$STUB_BIN/stat" "$STUB_BIN/sudo"
    export PATH="$STUB_BIN:$PATH"
    cp "$BATS_TEST_DIRNAME/../../dist/dbtune" "$RELEASE_DIR/dbtune"
    printf '{}\n' >"$RELEASE_DIR/dbtune-attestation.jsonl"
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$RELEASE_DIR" && sha256sum dbtune >dbtune.sha256)
    else
        (cd "$RELEASE_DIR" && shasum -a 256 dbtune >dbtune.sha256)
    fi
}

teardown() {
    if [ -n "$PRIVILEGED_TEST_ROOT" ]; then
        chmod -R u+w "$PRIVILEGED_TEST_ROOT" 2>/dev/null || true
        rm -rf "$PRIVILEGED_TEST_ROOT"
    fi
}

bats::on_failure() {
    printf '%s\n' "$output" >&3
}

@test "installer help defaults to English" {
    run sh "$BATS_TEST_DIRNAME/../../install.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Usage: install.sh [--version vX.Y.Z] [--install-dir PATH]'* ]]
    [[ "$output" == *'Environment:'* ]]
    [[ "$output" == *'DBTUNE_UI_LANG=en|sk'* ]]
}

@test "installer help supports explicit Slovak" {
    run env DBTUNE_UI_LANG=sk sh "$BATS_TEST_DIRNAME/../../install.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == 'Pouzitie: install.sh [--version vX.Y.Z] [--install-dir CESTA]'* ]]
    [[ "$output" == *'Premenne:'* ]]
    [[ "$output" == *'DBTUNE_UI_LANG=en|sk'* ]]
}

@test "installer rejects an unsupported interface language before trust checks" {
    run env DBTUNE_UI_LANG=de DBTUNE_REPOSITORY=other-owner/wooptima-db-tuner \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -eq 64 ]
    [ "$output" = 'Wooptima DB Tuner install: unsupported interface language: de (expected en or sk)' ]
    [ ! -e "$ATTESTATION_LOG" ]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer applies the fixed upstream trust policy and atomically installs" {
    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        DBTUNE_VERSION=9.9.9 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/dbtune" ]
    [ "$("$INSTALL_DIR/dbtune" version)" = 'dbtune 0.4.1' ]
    [[ "$output" == *'Wooptima DB Tuner install: downloading petervazan93/wooptima-db-tuner (v0.4.1)'* ]]
    [[ "$output" == *"Wooptima DB Tuner install: done: $INSTALL_DIR/dbtune"* ]]
    [[ "$output" == *'Next safe step: sudo dbtune audit --json'* ]]
    grep -F -- '--repo petervazan93/wooptima-db-tuner' "$ATTESTATION_LOG"
    grep -F -- '--signer-workflow petervazan93/wooptima-db-tuner/.github/workflows/release.yml' "$ATTESTATION_LOG"
    grep -F -- '--source-ref refs/tags/v0.4.1' "$ATTESTATION_LOG"
}

@test "installer success supports explicit Slovak" {
    run env DBTUNE_UI_LANG=sk \
        DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/dbtune" ]
    [[ "$output" == *'Wooptima DB Tuner install: stahujem petervazan93/wooptima-db-tuner (v0.4.1)'* ]]
    [[ "$output" == *"Wooptima DB Tuner install: hotovo: $INSTALL_DIR/dbtune"* ]]
    [[ "$output" == *'Dalsi bezpecny krok: sudo dbtune audit --json'* ]]
}

@test "installer rejects a cross-repository override before download or verification" {
    run env DBTUNE_REPOSITORY=other-owner/wooptima-db-tuner \
        DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'DBTUNE_REPOSITORY is not supported'* ]]
    [[ "$output" == *'pinned to upstream'* ]]
    [ ! -e "$ATTESTATION_LOG" ]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer trust failure supports explicit Slovak" {
    run env DBTUNE_UI_LANG=sk \
        DBTUNE_REPOSITORY=other-owner/wooptima-db-tuner \
        DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'DBTUNE_REPOSITORY nie je podporovane'* ]]
    [[ "$output" == *'pevne viazane na upstream'* ]]
    [ ! -e "$ATTESTATION_LOG" ]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer rejects latest artifact attested for a different source ref before execution" {
    execution_marker="$BATS_TEST_TMPDIR/artifact-executed"
    cat >"$RELEASE_DIR/dbtune" <<'ARTIFACT'
#!/usr/bin/env bash
printf '%s\n' executed >"$ARTIFACT_EXECUTION_MARKER"
if [[ ${1:-} == version ]]; then printf '%s\n' 'dbtune 0.4.1'; else exit 64; fi
ARTIFACT
    chmod +x "$RELEASE_DIR/dbtune"
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$RELEASE_DIR" && sha256sum dbtune >dbtune.sha256)
    else
        (cd "$RELEASE_DIR" && shasum -a 256 dbtune >dbtune.sha256)
    fi

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ATTESTATION_SOURCE_REF=refs/tags/v0.1.0 \
        ARTIFACT_EXECUTION_MARKER="$execution_marker" \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'artifact attestation verification failed'* ]]
    [ ! -e "$execution_marker" ]
    [ ! -e "$INSTALL_DIR/dbtune" ]
    grep -F -- '--source-ref refs/tags/v0.4.1' "$ATTESTATION_LOG"
}

@test "installer rejects an attestation failure without publishing a binary" {
    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ATTESTATION_STATUS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'artifact attestation verification failed'* ]]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer fails closed when the gh attestation verifier is unavailable" {
    tool_dir="$BATS_TEST_TMPDIR/tools-without-gh"
    mkdir "$tool_dir"
    for tool in grep uname curl install bash; do
        ln -s "$(command -v "$tool")" "$tool_dir/$tool"
    done

    run env PATH="$tool_dir" \
        DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        /bin/sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'missing gh CLI required for artifact attestation verification'* ]]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer rejects a 0.1.0 artifact requested as 9.9.9 despite runtime overrides" {
    cat >"$RELEASE_DIR/dbtune" <<'ARTIFACT'
#!/usr/bin/env bash
if [[ ${1:-} == version ]]; then printf '%s\n' 'dbtune 0.1.0'; else exit 64; fi
ARTIFACT
    chmod +x "$RELEASE_DIR/dbtune"
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$RELEASE_DIR" && sha256sum dbtune >dbtune.sha256)
    else
        (cd "$RELEASE_DIR" && shasum -a 256 dbtune >dbtune.sha256)
    fi

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        DBTUNE_VERSION=9.9.9 \
        DBTUNE_ARTIFACT_VERSION=9.9.9 \
        STUB_ATTESTATION_SOURCE_REF=refs/tags/v9.9.9 \
        sh "$BATS_TEST_DIRNAME/../../install.sh" --version 9.9.9

    [ "$status" -ne 0 ]
    [[ "$output" == *'artifact version is 0.1.0, expected 9.9.9'* ]]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer rejects a checksum mismatch without publishing a binary" {
    printf '%064d  dbtune\n' 0 >"$RELEASE_DIR/dbtune.sha256"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'artifact SHA-256 verification failed'* ]]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer creates a new user-local destination without sudo" {
    INSTALL_DIR="$BATS_TEST_TMPDIR/user-local/nested/bin"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/dbtune" ]
    [ ! -e "$SUDO_LOG" ]
}

@test "installer accepts a root-owned safe privileged destination" {
    PRIVILEGED_TEST_ROOT=$(mktemp -d "$PROJECT_ROOT/.installer-test.XXXXXX")
    export PRIVILEGED_TEST_ROOT
    INSTALL_DIR="$PRIVILEGED_TEST_ROOT/bin"
    mkdir "$INSTALL_DIR"
    chmod 0555 "$INSTALL_DIR"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ID_UID=1000 \
        STUB_STAT_UID=0 \
        STUB_STAT_MODE=755 \
        STUB_SUDO_EXEC=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/dbtune" ]
    grep -F -- 'install -d -m 0755' "$SUDO_LOG"
    grep -F -- "mv -f $INSTALL_DIR/.dbtune.new." "$SUDO_LOG"
}

@test "installer revalidates a privileged destination immediately before publication" {
    PRIVILEGED_TEST_ROOT=$(mktemp -d "$PROJECT_ROOT/.installer-test.XXXXXX")
    export PRIVILEGED_TEST_ROOT
    INSTALL_DIR="$PRIVILEGED_TEST_ROOT/bin"
    mkdir "$INSTALL_DIR"
    chmod 0555 "$INSTALL_DIR"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ID_UID=1000 \
        STUB_STAT_UID=0 \
        STUB_STAT_MODE=755 \
        STUB_SUDO_EXEC=1 \
        STUB_SWAP_DESTINATION="$INSTALL_DIR/dbtune" \
        STUB_SWAP_TARGET="$RELEASE_DIR/dbtune" \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'privileged target must not be a symlink'* ]]
    ! grep -F -- 'mv -f' "$SUDO_LOG"
}

@test "installer rejects a symlinked parent before privileged publication" {
    real_parent="$BATS_TEST_TMPDIR/real-parent"
    linked_parent="$BATS_TEST_TMPDIR/linked-parent"
    mkdir "$real_parent"
    ln -s "$real_parent" "$linked_parent"
    INSTALL_DIR="$linked_parent/bin"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ID_UID=0 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'contains a symlink'* ]]
    [ ! -e "$INSTALL_DIR" ]
}

@test "installer rejects a world-writable parent before privileged publication" {
    INSTALL_DIR="$BATS_TEST_TMPDIR/world-writable/bin"
    mkdir "$BATS_TEST_TMPDIR/world-writable"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ID_UID=0 \
        STUB_STAT_UID=0 \
        STUB_STAT_MODE=777 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'is writable by untrusted users'* ]]
    [ ! -e "$INSTALL_DIR" ]
}
