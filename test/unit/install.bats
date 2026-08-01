#!/usr/bin/env bats

setup() {
    export RELEASE_DIR="$BATS_TEST_TMPDIR/release"
    export INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
    export STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
    export ATTESTATION_LOG="$BATS_TEST_TMPDIR/attestation.log"
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
STUB
    chmod +x "$STUB_BIN/gh"
    export PATH="$STUB_BIN:$PATH"
    cp "$BATS_TEST_DIRNAME/../../dist/dbtune" "$RELEASE_DIR/dbtune"
    printf '{}\n' >"$RELEASE_DIR/dbtune-attestation.jsonl"
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$RELEASE_DIR" && sha256sum dbtune >dbtune.sha256)
    else
        (cd "$RELEASE_DIR" && shasum -a 256 dbtune >dbtune.sha256)
    fi
}

bats::on_failure() {
    printf '%s\n' "$output" >&3
}

@test "installer verifies and atomically installs a release artifact" {
    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        DBTUNE_VERSION=9.9.9 \
        sh "$BATS_TEST_DIRNAME/../../install.sh" --version v0.2.0

    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/dbtune" ]
    [ "$("$INSTALL_DIR/dbtune" version)" = 'dbtune 0.2.0' ]
    [[ "$output" == *'SHA-256'* || "$output" == *'hotovo'* ]]
    grep -F -- '--repo petervazan93/wooptima-db-tuner' "$ATTESTATION_LOG"
    grep -F -- '--source-ref refs/tags/v0.2.0' "$ATTESTATION_LOG"
}

@test "installer rejects an attestation failure without publishing a binary" {
    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        STUB_ATTESTATION_STATUS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'attestation overenie zlyhalo'* ]]
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
    [[ "$output" == *'chyba gh CLI'* ]]
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
        sh "$BATS_TEST_DIRNAME/../../install.sh" --version 9.9.9

    [ "$status" -ne 0 ]
    [[ "$output" == *'artefakt ma verziu 0.1.0, ocakavana je 9.9.9'* ]]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}

@test "installer rejects a checksum mismatch without publishing a binary" {
    printf '%064d  dbtune\n' 0 >"$RELEASE_DIR/dbtune.sha256"

    run env DBTUNE_DOWNLOAD_BASE="file://$RELEASE_DIR" \
        DBTUNE_INSTALL_DIR="$INSTALL_DIR" \
        DBTUNE_ALLOW_UNSUPPORTED_OS=1 \
        sh "$BATS_TEST_DIRNAME/../../install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'SHA-256 kontrola'* ]]
    [ ! -e "$INSTALL_DIR/dbtune" ]
}
