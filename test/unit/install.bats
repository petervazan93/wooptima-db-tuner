#!/usr/bin/env bats

setup() {
    export RELEASE_DIR="$BATS_TEST_TMPDIR/release"
    export INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$RELEASE_DIR" "$INSTALL_DIR"
    cp "$BATS_TEST_DIRNAME/../../dist/dbtune" "$RELEASE_DIR/dbtune"
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
        sh "$BATS_TEST_DIRNAME/../../install.sh" --version v0.1.0

    [ "$status" -eq 0 ]
    [ -x "$INSTALL_DIR/dbtune" ]
    [ "$("$INSTALL_DIR/dbtune" version)" = 'dbtune 0.1.0' ]
    [[ "$output" == *'SHA-256'* || "$output" == *'hotovo'* ]]
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
