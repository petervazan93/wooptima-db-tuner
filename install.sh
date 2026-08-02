#!/bin/sh

set -eu

REPOSITORY=petervazan93/wooptima-db-tuner
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
EOF
}

fail() {
    printf 'dbtune install: %s\n' "$*" >&2
    exit 1
}

if [ "${DBTUNE_REPOSITORY+x}" = x ]; then
    fail 'DBTUNE_REPOSITORY nie je podporovane; repository a attestation trust policy su pevne viazane na upstream'
fi

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
while [ "$INSTALL_DIR" != / ] && [ "${INSTALL_DIR%/}" != "$INSTALL_DIR" ]; do
    INSTALL_DIR=${INSTALL_DIR%/}
done
case $INSTALL_DIR in
    */./*|*/.|*/../*|*/..) fail 'installacny adresar nesmie obsahovat . ani .. komponenty' ;;
esac

case $RELEASE in
    latest) ;;
    v*) ;;
    *) RELEASE="v$RELEASE" ;;
esac
if [ "$RELEASE" != latest ] && ! printf '%s\n' "$RELEASE" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail 'verzia musi byt latest alebo vX.Y.Z'
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

path_parent() {
    path=$1
    parent=${path%/*}
    [ -n "$parent" ] || parent=/
    printf '%s\n' "$parent"
}

find_nearest_existing_parent() {
    nearest_existing=$INSTALL_DIR
    while [ ! -e "$nearest_existing" ] && [ ! -L "$nearest_existing" ]; do
        [ "$nearest_existing" != / ] || break
        nearest_existing=$(path_parent "$nearest_existing")
    done
    [ -d "$nearest_existing" ] || fail "najblizsi existujuci rodic $nearest_existing nie je adresar"
}

STAT_STYLE=
configure_stat() {
    command -v stat >/dev/null 2>&1 || fail 'chyba prikaz stat potrebny pre bezpecnu instalaciu'
    if stat -c '%u %a' -- / >/dev/null 2>&1; then
        STAT_STYLE=gnu
    elif stat -f '%u %Lp' / >/dev/null 2>&1; then
        STAT_STYLE=bsd
    else
        fail 'stat nepodporuje citanie vlastnika a modu adresara'
    fi
}

directory_metadata() {
    if [ "$STAT_STYLE" = gnu ]; then
        stat -c '%u %a' -- "$1"
    else
        stat -f '%u %Lp' "$1"
    fi
}

validate_trusted_directory() {
    directory=$1
    metadata=$(directory_metadata "$directory") ||
        fail "neda sa overit privilegovany rodic $directory"
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" != "$metadata" ] || fail "neplatne metadata privilegovaneho rodica $directory"
    case $owner:$mode in
        *[!0-9:]*|:*|*' '*) fail "neplatne metadata privilegovaneho rodica $directory" ;;
    esac
    [ "$owner" -eq 0 ] || fail "privilegovany rodic $directory nie je vlastneny rootom"
    group_digit=$((mode / 10 % 10))
    other_digit=$((mode % 10))
    case $group_digit:$other_digit in
        2:*|3:*|6:*|7:*|*:2|*:3|*:6|*:7)
            fail "privilegovany rodic $directory je zapisovatelny nedoveryhodnymi pouzivatelmi"
            ;;
    esac
}

validate_privileged_install_path() {
    path=$INSTALL_DIR
    while :; do
        [ ! -L "$path" ] || fail "privilegovana instalacna cesta obsahuje symlink: $path"
        if [ -e "$path" ]; then
            [ -d "$path" ] || fail "komponent privilegovanej instalacnej cesty nie je adresar: $path"
            validate_trusted_directory "$path"
        fi
        [ "$path" != / ] || break
        path=$(path_parent "$path")
    done

    destination=$INSTALL_DIR/dbtune
    [ ! -L "$destination" ] || fail "privilegovany ciel nesmie byt symlink: $destination"
    if [ -e "$destination" ] && [ ! -f "$destination" ]; then
        fail "privilegovany ciel musi byt regularny subor: $destination"
    fi
}

SUDO=
PRIVILEGED_INSTALL=0
find_nearest_existing_parent
if [ "$(id -u)" -eq 0 ]; then
    PRIVILEGED_INSTALL=1
elif [ ! -w "$nearest_existing" ] || [ ! -x "$nearest_existing" ]; then
    command -v sudo >/dev/null 2>&1 || fail "zapis do $INSTALL_DIR vyzaduje root alebo sudo"
    SUDO=sudo
    PRIVILEGED_INSTALL=1
fi
if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    configure_stat
    validate_privileged_install_path
fi

if [ "$RELEASE" = latest ]; then
    release_metadata=$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 1 \
        "https://api.github.com/repos/$ATTESTATION_REPOSITORY/releases/latest") ||
        fail 'nepodarilo sa nacitat metadata najnovsieho release'
    selected_release=$(printf '%s\n' "$release_metadata" | awk -F '"' \
        '$2 == "tag_name" {print $4; exit}')
    if ! printf '%s\n' "$selected_release" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        fail 'metadata najnovsieho release neobsahuju platny tag vX.Y.Z'
    fi
else
    selected_release=$RELEASE
fi

if [ -z "$DOWNLOAD_BASE" ]; then
    DOWNLOAD_BASE="https://github.com/$REPOSITORY/releases/download/$selected_release"
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-install.XXXXXX") || fail 'mktemp zlyhal'
target_new="$INSTALL_DIR/.dbtune.new.$$"
target_created=0
cleanup() {
    if [ "$target_created" -eq 1 ]; then
        if [ -n "$SUDO" ]; then
            sudo rm -f "$target_new" || true
        else
            rm -f "$target_new" || true
        fi
    fi
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
    source_ref=$2
    gh attestation verify "$artifact" \
        --bundle "$temporary/dbtune-attestation.jsonl" \
        --repo "$ATTESTATION_REPOSITORY" \
        --signer-workflow "$ATTESTATION_SIGNER_WORKFLOW" \
        --source-ref "$source_ref" \
        --deny-self-hosted-runners >/dev/null
}

printf 'dbtune install: stahujem %s (%s)\n' "$REPOSITORY" "$selected_release"
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
verify_attestation "$temporary/dbtune" "refs/tags/$selected_release" ||
    fail 'GitHub artifact attestation overenie zlyhalo'
bash -n "$temporary/dbtune" || fail 'stiahnuty artefakt nema platnu Bash syntax'
artifact_version=$(
    (
        unset DBTUNE_VERSION DBTUNE_ARTIFACT_VERSION DBTUNE_RELEASE DBTUNE_PROGRAM
        bash "$temporary/dbtune" version
    ) | awk 'NF == 2 && $1 == "dbtune" {print $2}'
)
[ -n "$artifact_version" ] || fail 'artefakt nevratil platnu verziu'
if [ "v$artifact_version" != "$selected_release" ]; then
    fail "artefakt ma verziu $artifact_version, ocakavana je ${selected_release#v}"
fi

run_privileged() {
    if [ -n "$SUDO" ]; then
        sudo "$@"
    else
        "$@"
    fi
}

if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    validate_privileged_install_path
fi
run_privileged install -d -m 0755 "$INSTALL_DIR"
if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    validate_privileged_install_path
    if [ -e "$target_new" ] || [ -L "$target_new" ]; then
        fail "docasny privilegovany ciel uz existuje: $target_new"
    fi
    run_privileged install -o root -g root -m 0755 "$temporary/dbtune" "$target_new"
    target_created=1
else
    install -m 0755 "$temporary/dbtune" "$target_new"
    target_created=1
fi
if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    if [ ! -f "$target_new" ] || [ -L "$target_new" ]; then
        fail "docasny privilegovany ciel nie je regularny subor: $target_new"
    fi
    validate_privileged_install_path
fi
run_privileged mv -f "$target_new" "$INSTALL_DIR/dbtune"
target_created=0

installed_version=$("$INSTALL_DIR/dbtune" version) || fail 'nainstalovany dbtune sa neda spustit'
printf 'dbtune install: %s\n' "$installed_version"
printf 'dbtune install: hotovo: %s/dbtune\n' "$INSTALL_DIR"
printf 'Dalsi bezpecny krok: sudo dbtune audit --json\n'
