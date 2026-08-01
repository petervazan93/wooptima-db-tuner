#!/bin/sh

set -eu

REPOSITORY=${DBTUNE_REPOSITORY:-petervazan93/wooptima-db-tuner}
INSTALL_DIR=${DBTUNE_INSTALL_DIR:-/usr/local/bin}
RELEASE=${DBTUNE_RELEASE:-latest}
DOWNLOAD_BASE=${DBTUNE_DOWNLOAD_BASE:-}
ALLOW_UNSUPPORTED_OS=${DBTUNE_ALLOW_UNSUPPORTED_OS:-0}
ATTESTATION_REPOSITORY=petervazan93/wooptima-db-tuner
ATTESTATION_SIGNER_WORKFLOW=petervazan93/wooptima-db-tuner/.github/workflows/release.yml

usage() {
    cat <<'EOF'
Pouzitie: install.sh [--version vX.Y.Z] [--install-dir CESTA]

Premenne:
  DBTUNE_RELEASE               Release tag, default latest
  DBTUNE_INSTALL_DIR           Cielovy adresar, default /usr/local/bin
  DBTUNE_REPOSITORY            GitHub owner/repo
EOF
}

fail() {
    printf 'dbtune install: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --version)
            [ "$#" -ge 2 ] || fail '--version vyzaduje hodnotu'
            RELEASE=$2
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || fail '--install-dir vyzaduje cestu'
            INSTALL_DIR=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) fail "neznama volba: $1" ;;
    esac
done

case $INSTALL_DIR in
    /*) ;;
    *) fail 'installacny adresar musi byt absolutna cesta' ;;
esac

case $RELEASE in
    latest) ;;
    v*) ;;
    *) RELEASE="v$RELEASE" ;;
esac
if [ "$RELEASE" != latest ] && ! printf '%s\n' "$RELEASE" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail 'verzia musi byt latest alebo vX.Y.Z'
fi
if ! printf '%s\n' "$REPOSITORY" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    fail 'DBTUNE_REPOSITORY musi mat tvar owner/repo'
fi

if [ "$(uname -s)" != Linux ] && [ "$ALLOW_UNSUPPORTED_OS" != 1 ]; then
    fail 'dbtune je urceny pre Linux; pre test nastavte DBTUNE_ALLOW_UNSUPPORTED_OS=1'
fi
command -v curl >/dev/null 2>&1 || fail 'chyba curl'
command -v install >/dev/null 2>&1 || fail 'chyba prikaz install'
command -v bash >/dev/null 2>&1 || fail 'chyba bash'
command -v gh >/dev/null 2>&1 || fail 'chyba gh CLI potrebne pre overenie artifact attestation'

bash_major=$(bash -c 'printf "%s" "${BASH_VERSINFO[0]}"')
[ "$bash_major" -ge 4 ] || fail 'dbtune vyzaduje Bash 4 alebo novsi'

if [ -z "$DOWNLOAD_BASE" ]; then
    if [ "$RELEASE" = latest ]; then
        DOWNLOAD_BASE="https://github.com/$REPOSITORY/releases/latest/download"
    else
        DOWNLOAD_BASE="https://github.com/$REPOSITORY/releases/download/$RELEASE"
    fi
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-install.XXXXXX") || fail 'mktemp zlyhal'
target_new="$INSTALL_DIR/.dbtune.new.$$"
cleanup() {
    rm -rf "$temporary"
}
trap cleanup EXIT HUP INT TERM

download() {
    name=$1
    destination=$2
    case $DOWNLOAD_BASE in
        https://*) curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 1 "$DOWNLOAD_BASE/$name" -o "$destination" ;;
        file://*) curl -fsSL "$DOWNLOAD_BASE/$name" -o "$destination" ;;
        *) fail 'download URL musi pouzivat HTTPS' ;;
    esac
}

verify_attestation() {
    artifact=$1
    source_ref=${2:-}
    if [ -n "$source_ref" ]; then
        gh attestation verify "$artifact" \
            --bundle "$temporary/dbtune-attestation.jsonl" \
            --repo "$ATTESTATION_REPOSITORY" \
            --signer-workflow "$ATTESTATION_SIGNER_WORKFLOW" \
            --source-ref "$source_ref" \
            --deny-self-hosted-runners >/dev/null
    else
        gh attestation verify "$artifact" \
            --bundle "$temporary/dbtune-attestation.jsonl" \
            --repo "$ATTESTATION_REPOSITORY" \
            --signer-workflow "$ATTESTATION_SIGNER_WORKFLOW" \
            --deny-self-hosted-runners >/dev/null
    fi
}

printf 'dbtune install: stahujem %s (%s)\n' "$REPOSITORY" "$RELEASE"
download dbtune "$temporary/dbtune"
download dbtune.sha256 "$temporary/dbtune.sha256"
download dbtune-attestation.jsonl "$temporary/dbtune-attestation.jsonl"

expected=$(awk '$2 == "dbtune" || $2 == "*dbtune" {print $1; exit}' "$temporary/dbtune.sha256")
case $expected in
    *[!0-9a-fA-F]*|'') fail 'release obsahuje neplatny SHA-256 zaznam' ;;
esac
[ "${#expected}" -eq 64 ] || fail 'release obsahuje neplatnu dlzku SHA-256'

if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$temporary/dbtune" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$temporary/dbtune" | awk '{print $1}')
else
    fail 'chyba sha256sum aj shasum'
fi
[ "$actual" = "$expected" ] || fail 'SHA-256 kontrola artefaktu zlyhala'
if [ "$RELEASE" = latest ]; then
    verify_attestation "$temporary/dbtune" || fail 'GitHub artifact attestation overenie zlyhalo'
else
    verify_attestation "$temporary/dbtune" "refs/tags/$RELEASE" || fail 'GitHub artifact attestation overenie zlyhalo'
fi
bash -n "$temporary/dbtune" || fail 'stiahnuty artefakt nema platnu Bash syntax'
artifact_version=$(
    (
        unset DBTUNE_VERSION DBTUNE_ARTIFACT_VERSION DBTUNE_RELEASE DBTUNE_PROGRAM
        bash "$temporary/dbtune" version
    ) | awk 'NF == 2 && $1 == "dbtune" {print $2}'
)
[ -n "$artifact_version" ] || fail 'artefakt nevratil platnu verziu'
if [ "$RELEASE" != latest ] && [ "v$artifact_version" != "$RELEASE" ]; then
    fail "artefakt ma verziu $artifact_version, ocakavana je ${RELEASE#v}"
fi
if [ "$RELEASE" = latest ]; then
    verify_attestation "$temporary/dbtune" "refs/tags/v$artifact_version" ||
        fail 'GitHub artifact attestation nezodpoveda tagu immutable verzie'
fi

SUDO=
if [ "$(id -u)" -ne 0 ] && { [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; }; then
    command -v sudo >/dev/null 2>&1 || fail "zapis do $INSTALL_DIR vyzaduje root alebo sudo"
    SUDO=sudo
fi

run_privileged() {
    if [ -n "$SUDO" ]; then
        sudo "$@"
    else
        "$@"
    fi
}

run_privileged install -d -m 0755 "$INSTALL_DIR"
if [ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ]; then
    run_privileged install -o root -g root -m 0755 "$temporary/dbtune" "$target_new"
else
    install -m 0755 "$temporary/dbtune" "$target_new"
fi
run_privileged mv -f "$target_new" "$INSTALL_DIR/dbtune"

installed_version=$("$INSTALL_DIR/dbtune" version) || fail 'nainstalovany dbtune sa neda spustit'
printf 'dbtune install: %s\n' "$installed_version"
printf 'dbtune install: hotovo: %s/dbtune\n' "$INSTALL_DIR"
printf 'Dalsi bezpecny krok: sudo dbtune audit --json\n'
