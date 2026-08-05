#!/bin/sh

set -eu

REPOSITORY=petervazan93/wooptima-db-tuner
INSTALL_DIR=${DBTUNE_INSTALL_DIR:-/usr/local/bin}
RELEASE=${DBTUNE_RELEASE:-latest}
DOWNLOAD_BASE=${DBTUNE_DOWNLOAD_BASE:-}
ALLOW_UNSUPPORTED_OS=${DBTUNE_ALLOW_UNSUPPORTED_OS:-0}
ATTESTATION_REPOSITORY=petervazan93/wooptima-db-tuner
ATTESTATION_SIGNER_WORKFLOW=petervazan93/wooptima-db-tuner/.github/workflows/release.yml
UI_LANG=${DBTUNE_UI_LANG:-en}

case $UI_LANG in
    en|sk) ;;
    *)
        printf 'Wooptima DB Tuner install: unsupported interface language: %s (expected en or sk)\n' "$UI_LANG" >&2
        exit 64
        ;;
esac

installer_message() {
    case "$UI_LANG:$1" in
        en:usage)
            INSTALLER_MESSAGE='Usage: install.sh [--version vX.Y.Z] [--install-dir PATH]

Environment:
  DBTUNE_RELEASE               Release tag, default latest
  DBTUNE_INSTALL_DIR           Target directory, default /usr/local/bin
  DBTUNE_UI_LANG=en|sk         Interface language, default en
'
            ;;
        sk:usage)
            INSTALLER_MESSAGE='Pouzitie: install.sh [--version vX.Y.Z] [--install-dir CESTA]

Premenne:
  DBTUNE_RELEASE               Release tag, default latest
  DBTUNE_INSTALL_DIR           Cielovy adresar, default /usr/local/bin
  DBTUNE_UI_LANG=en|sk         Jazyk rozhrania, default en
'
            ;;
        en:repository_override)
            INSTALLER_MESSAGE='DBTUNE_REPOSITORY is not supported; repository and attestation trust policy are pinned to upstream'
            ;;
        sk:repository_override)
            INSTALLER_MESSAGE='DBTUNE_REPOSITORY nie je podporovane; repository a attestation trust policy su pevne viazane na upstream'
            ;;
        en:version_value_required)
            INSTALLER_MESSAGE='--version requires a value'
            ;;
        sk:version_value_required)
            INSTALLER_MESSAGE='--version vyzaduje hodnotu'
            ;;
        en:install_dir_value_required)
            INSTALLER_MESSAGE='--install-dir requires a path'
            ;;
        sk:install_dir_value_required)
            INSTALLER_MESSAGE='--install-dir vyzaduje cestu'
            ;;
        en:unknown_option)
            INSTALLER_MESSAGE='unknown option: %s'
            ;;
        sk:unknown_option)
            INSTALLER_MESSAGE='neznama volba: %s'
            ;;
        en:install_dir_absolute)
            INSTALLER_MESSAGE='installation directory must be an absolute path'
            ;;
        sk:install_dir_absolute)
            INSTALLER_MESSAGE='installacny adresar musi byt absolutna cesta'
            ;;
        en:install_dir_components)
            INSTALLER_MESSAGE='installation directory must not contain . or .. components'
            ;;
        sk:install_dir_components)
            INSTALLER_MESSAGE='installacny adresar nesmie obsahovat . ani .. komponenty'
            ;;
        en:version_invalid)
            INSTALLER_MESSAGE='version must be latest or vX.Y.Z'
            ;;
        sk:version_invalid)
            INSTALLER_MESSAGE='verzia musi byt latest alebo vX.Y.Z'
            ;;
        en:linux_required)
            INSTALLER_MESSAGE='dbtune is intended for Linux; set DBTUNE_ALLOW_UNSUPPORTED_OS=1 for testing'
            ;;
        sk:linux_required)
            INSTALLER_MESSAGE='dbtune je urceny pre Linux; pre test nastavte DBTUNE_ALLOW_UNSUPPORTED_OS=1'
            ;;
        en:curl_missing)
            INSTALLER_MESSAGE='curl is missing'
            ;;
        sk:curl_missing)
            INSTALLER_MESSAGE='chyba curl'
            ;;
        en:install_missing)
            INSTALLER_MESSAGE='install command is missing'
            ;;
        sk:install_missing)
            INSTALLER_MESSAGE='chyba prikaz install'
            ;;
        en:bash_missing)
            INSTALLER_MESSAGE='bash is missing'
            ;;
        sk:bash_missing)
            INSTALLER_MESSAGE='chyba bash'
            ;;
        en:gh_missing)
            INSTALLER_MESSAGE='missing gh CLI required for artifact attestation verification'
            ;;
        sk:gh_missing)
            INSTALLER_MESSAGE='chyba gh CLI potrebne pre overenie artifact attestation'
            ;;
        en:bash_version)
            INSTALLER_MESSAGE='dbtune requires Bash 4 or newer'
            ;;
        sk:bash_version)
            INSTALLER_MESSAGE='dbtune vyzaduje Bash 4 alebo novsi'
            ;;
        en:parent_not_directory)
            INSTALLER_MESSAGE='nearest existing parent %s is not a directory'
            ;;
        sk:parent_not_directory)
            INSTALLER_MESSAGE='najblizsi existujuci rodic %s nie je adresar'
            ;;
        en:stat_missing)
            INSTALLER_MESSAGE='stat command required for secure installation is missing'
            ;;
        sk:stat_missing)
            INSTALLER_MESSAGE='chyba prikaz stat potrebny pre bezpecnu instalaciu'
            ;;
        en:stat_unsupported)
            INSTALLER_MESSAGE='stat does not support reading directory owner and mode'
            ;;
        sk:stat_unsupported)
            INSTALLER_MESSAGE='stat nepodporuje citanie vlastnika a modu adresara'
            ;;
        en:parent_unverifiable)
            INSTALLER_MESSAGE='cannot verify privileged parent %s'
            ;;
        sk:parent_unverifiable)
            INSTALLER_MESSAGE='neda sa overit privilegovany rodic %s'
            ;;
        en:parent_metadata_invalid)
            INSTALLER_MESSAGE='invalid metadata for privileged parent %s'
            ;;
        sk:parent_metadata_invalid)
            INSTALLER_MESSAGE='neplatne metadata privilegovaneho rodica %s'
            ;;
        en:parent_not_root)
            INSTALLER_MESSAGE='privileged parent %s is not owned by root'
            ;;
        sk:parent_not_root)
            INSTALLER_MESSAGE='privilegovany rodic %s nie je vlastneny rootom'
            ;;
        en:parent_untrusted_writable)
            INSTALLER_MESSAGE='privileged parent %s is writable by untrusted users'
            ;;
        sk:parent_untrusted_writable)
            INSTALLER_MESSAGE='privilegovany rodic %s je zapisovatelny nedoveryhodnymi pouzivatelmi'
            ;;
        en:path_symlink)
            INSTALLER_MESSAGE='privileged installation path contains a symlink: %s'
            ;;
        sk:path_symlink)
            INSTALLER_MESSAGE='privilegovana instalacna cesta obsahuje symlink: %s'
            ;;
        en:path_component_not_directory)
            INSTALLER_MESSAGE='privileged installation path component is not a directory: %s'
            ;;
        sk:path_component_not_directory)
            INSTALLER_MESSAGE='komponent privilegovanej instalacnej cesty nie je adresar: %s'
            ;;
        en:target_symlink)
            INSTALLER_MESSAGE='privileged target must not be a symlink: %s'
            ;;
        sk:target_symlink)
            INSTALLER_MESSAGE='privilegovany ciel nesmie byt symlink: %s'
            ;;
        en:target_not_regular)
            INSTALLER_MESSAGE='privileged target must be a regular file: %s'
            ;;
        sk:target_not_regular)
            INSTALLER_MESSAGE='privilegovany ciel musi byt regularny subor: %s'
            ;;
        en:privilege_required)
            INSTALLER_MESSAGE='writing to %s requires root or sudo'
            ;;
        sk:privilege_required)
            INSTALLER_MESSAGE='zapis do %s vyzaduje root alebo sudo'
            ;;
        en:latest_metadata_failed)
            INSTALLER_MESSAGE='failed to load latest release metadata'
            ;;
        sk:latest_metadata_failed)
            INSTALLER_MESSAGE='nepodarilo sa nacitat metadata najnovsieho release'
            ;;
        en:latest_tag_invalid)
            INSTALLER_MESSAGE='latest release metadata does not contain a valid vX.Y.Z tag'
            ;;
        sk:latest_tag_invalid)
            INSTALLER_MESSAGE='metadata najnovsieho release neobsahuju platny tag vX.Y.Z'
            ;;
        en:mktemp_failed)
            INSTALLER_MESSAGE='mktemp failed'
            ;;
        sk:mktemp_failed)
            INSTALLER_MESSAGE='mktemp zlyhal'
            ;;
        en:download_https_required)
            INSTALLER_MESSAGE='download URL must use HTTPS'
            ;;
        sk:download_https_required)
            INSTALLER_MESSAGE='download URL musi pouzivat HTTPS'
            ;;
        en:downloading)
            INSTALLER_MESSAGE='Wooptima DB Tuner install: downloading %s (%s)\n'
            ;;
        sk:downloading)
            INSTALLER_MESSAGE='Wooptima DB Tuner install: stahujem %s (%s)\n'
            ;;
        en:checksum_record_invalid)
            INSTALLER_MESSAGE='release contains an invalid SHA-256 record'
            ;;
        sk:checksum_record_invalid)
            INSTALLER_MESSAGE='release obsahuje neplatny SHA-256 zaznam'
            ;;
        en:checksum_length_invalid)
            INSTALLER_MESSAGE='release contains an invalid SHA-256 length'
            ;;
        sk:checksum_length_invalid)
            INSTALLER_MESSAGE='release obsahuje neplatnu dlzku SHA-256'
            ;;
        en:checksum_tool_missing)
            INSTALLER_MESSAGE='neither sha256sum nor shasum is available'
            ;;
        sk:checksum_tool_missing)
            INSTALLER_MESSAGE='chyba sha256sum aj shasum'
            ;;
        en:checksum_failed)
            INSTALLER_MESSAGE='artifact SHA-256 verification failed'
            ;;
        sk:checksum_failed)
            INSTALLER_MESSAGE='SHA-256 kontrola artefaktu zlyhala'
            ;;
        en:attestation_failed)
            INSTALLER_MESSAGE='GitHub artifact attestation verification failed'
            ;;
        sk:attestation_failed)
            INSTALLER_MESSAGE='GitHub artifact attestation overenie zlyhalo'
            ;;
        en:artifact_syntax_invalid)
            INSTALLER_MESSAGE='downloaded artifact does not have valid Bash syntax'
            ;;
        sk:artifact_syntax_invalid)
            INSTALLER_MESSAGE='stiahnuty artefakt nema platnu Bash syntax'
            ;;
        en:artifact_version_invalid)
            INSTALLER_MESSAGE='artifact did not return a valid version'
            ;;
        sk:artifact_version_invalid)
            INSTALLER_MESSAGE='artefakt nevratil platnu verziu'
            ;;
        en:artifact_version_mismatch)
            INSTALLER_MESSAGE='artifact version is %s, expected %s'
            ;;
        sk:artifact_version_mismatch)
            INSTALLER_MESSAGE='artefakt ma verziu %s, ocakavana je %s'
            ;;
        en:temporary_target_exists)
            INSTALLER_MESSAGE='temporary privileged target already exists: %s'
            ;;
        sk:temporary_target_exists)
            INSTALLER_MESSAGE='docasny privilegovany ciel uz existuje: %s'
            ;;
        en:temporary_target_not_regular)
            INSTALLER_MESSAGE='temporary privileged target is not a regular file: %s'
            ;;
        sk:temporary_target_not_regular)
            INSTALLER_MESSAGE='docasny privilegovany ciel nie je regularny subor: %s'
            ;;
        en:temporary_target_metadata)
            INSTALLER_MESSAGE='temporary privileged target has invalid owner or mode: %s'
            ;;
        sk:temporary_target_metadata)
            INSTALLER_MESSAGE='docasny privilegovany ciel ma neplatneho vlastnika alebo rezim: %s'
            ;;
        en:temporary_target_hardlinks)
            INSTALLER_MESSAGE='temporary privileged target has unexpected hardlinks: %s'
            ;;
        sk:temporary_target_hardlinks)
            INSTALLER_MESSAGE='docasny privilegovany ciel ma neocakavane hardlinky: %s'
            ;;
        en:installed_unusable)
            INSTALLER_MESSAGE='installed dbtune cannot be executed'
            ;;
        sk:installed_unusable)
            INSTALLER_MESSAGE='nainstalovany dbtune sa neda spustit'
            ;;
        en:install_done)
            INSTALLER_MESSAGE='Wooptima DB Tuner install: done: %s/dbtune\n'
            ;;
        sk:install_done)
            INSTALLER_MESSAGE='Wooptima DB Tuner install: hotovo: %s/dbtune\n'
            ;;
        en:next_step)
            INSTALLER_MESSAGE='Next safe step: sudo dbtune audit --json\n'
            ;;
        sk:next_step)
            INSTALLER_MESSAGE='Dalsi bezpecny krok: sudo dbtune audit --json\n'
            ;;
        *)
            printf 'Wooptima DB Tuner install: missing interface message: %s\n' "$1" >&2
            return 70
            ;;
    esac
}

installer_printf() {
    installer_printf_id=$1
    shift
    installer_message "$installer_printf_id" || return
    # shellcheck disable=SC2059 # Format strings come only from the trusted static selector.
    printf "$INSTALLER_MESSAGE" "$@"
}

usage() {
    installer_printf usage
}

fail() {
    installer_fail_id=$1
    shift
    printf 'Wooptima DB Tuner install: ' >&2
    installer_printf "$installer_fail_id" "$@" >&2
    printf '\n' >&2
    exit 1
}

if [ "${DBTUNE_REPOSITORY+x}" = x ]; then
    fail repository_override
fi

while [ "$#" -gt 0 ]; do
    case $1 in
        --version)
            [ "$#" -ge 2 ] || fail version_value_required
            RELEASE=$2
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || fail install_dir_value_required
            INSTALL_DIR=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) fail unknown_option "$1" ;;
    esac
done

case $INSTALL_DIR in
    /*) ;;
    *) fail install_dir_absolute ;;
esac
while [ "$INSTALL_DIR" != / ] && [ "${INSTALL_DIR%/}" != "$INSTALL_DIR" ]; do
    INSTALL_DIR=${INSTALL_DIR%/}
done
case $INSTALL_DIR in
    */./*|*/.|*/../*|*/..) fail install_dir_components ;;
esac

case $RELEASE in
    latest) ;;
    v*) ;;
    *) RELEASE="v$RELEASE" ;;
esac
if [ "$RELEASE" != latest ] && ! printf '%s\n' "$RELEASE" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail version_invalid
fi
if [ "$(uname -s)" != Linux ] && [ "$ALLOW_UNSUPPORTED_OS" != 1 ]; then
    fail linux_required
fi
command -v curl >/dev/null 2>&1 || fail curl_missing
command -v install >/dev/null 2>&1 || fail install_missing
command -v bash >/dev/null 2>&1 || fail bash_missing
command -v gh >/dev/null 2>&1 || fail gh_missing

bash_major=$(bash -c 'printf "%s" "${BASH_VERSINFO[0]}"')
[ "$bash_major" -ge 4 ] || fail bash_version

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
    [ -d "$nearest_existing" ] || fail parent_not_directory "$nearest_existing"
}

STAT_STYLE=
configure_stat() {
    command -v stat >/dev/null 2>&1 || fail stat_missing
    if stat -c '%u %a' -- / >/dev/null 2>&1; then
        STAT_STYLE=gnu
    elif stat -f '%u %Lp' / >/dev/null 2>&1; then
        STAT_STYLE=bsd
    else
        fail stat_unsupported
    fi
}

directory_metadata() {
    if [ "$STAT_STYLE" = gnu ]; then
        stat -c '%u %a' -- "$1"
    else
        stat -f '%u %Lp' "$1"
    fi
}

file_link_count() {
    if [ "$STAT_STYLE" = gnu ]; then
        stat -c '%h' -- "$1"
    else
        stat -f '%l' "$1"
    fi
}

validate_privileged_staging() {
    staging=$1
    expected_mode=$2
    [ -f "$staging" ] && [ ! -L "$staging" ] ||
        fail temporary_target_not_regular "$staging"
    metadata=$(directory_metadata "$staging") ||
        fail temporary_target_metadata "$staging"
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" -eq 0 ] && [ "$mode" = "$expected_mode" ] ||
        fail temporary_target_metadata "$staging"
    links=$(file_link_count "$staging") ||
        fail temporary_target_metadata "$staging"
    [ "$links" -eq 1 ] || fail temporary_target_hardlinks "$staging"
}

validate_trusted_directory() {
    directory=$1
    metadata=$(directory_metadata "$directory") ||
        fail parent_unverifiable "$directory"
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" != "$metadata" ] || fail parent_metadata_invalid "$directory"
    case $owner:$mode in
        *[!0-9:]*|:*|*' '*) fail parent_metadata_invalid "$directory" ;;
    esac
    [ "$owner" -eq 0 ] || fail parent_not_root "$directory"
    group_digit=$((mode / 10 % 10))
    other_digit=$((mode % 10))
    case $group_digit:$other_digit in
        2:*|3:*|6:*|7:*|*:2|*:3|*:6|*:7)
            fail parent_untrusted_writable "$directory"
            ;;
    esac
}

validate_privileged_install_path() {
    path=$INSTALL_DIR
    while :; do
        [ ! -L "$path" ] || fail path_symlink "$path"
        if [ -e "$path" ]; then
            [ -d "$path" ] || fail path_component_not_directory "$path"
            validate_trusted_directory "$path"
        fi
        [ "$path" != / ] || break
        path=$(path_parent "$path")
    done

    destination=$INSTALL_DIR/dbtune
    [ ! -L "$destination" ] || fail target_symlink "$destination"
    if [ -e "$destination" ] && [ ! -f "$destination" ]; then
        fail target_not_regular "$destination"
    fi
}

SUDO=
PRIVILEGED_INSTALL=0
find_nearest_existing_parent
if [ "$(id -u)" -eq 0 ]; then
    PRIVILEGED_INSTALL=1
elif [ ! -w "$nearest_existing" ] || [ ! -x "$nearest_existing" ]; then
    command -v sudo >/dev/null 2>&1 || fail privilege_required "$INSTALL_DIR"
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
        fail latest_metadata_failed
    selected_release=$(printf '%s\n' "$release_metadata" | awk -F '"' \
        '$2 == "tag_name" {print $4; exit}')
    if ! printf '%s\n' "$selected_release" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        fail latest_tag_invalid
    fi
else
    selected_release=$RELEASE
fi

if [ -z "$DOWNLOAD_BASE" ]; then
    DOWNLOAD_BASE="https://github.com/$REPOSITORY/releases/download/$selected_release"
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-install.XXXXXX") || fail mktemp_failed
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
        *) fail download_https_required ;;
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

run_privileged() {
    if [ -n "$SUDO" ]; then
        sudo "$@"
    else
        "$@"
    fi
}

installer_printf downloading "$REPOSITORY" "$selected_release"
download dbtune "$temporary/dbtune"
download dbtune.sha256 "$temporary/dbtune.sha256"
download dbtune-attestation.jsonl "$temporary/dbtune-attestation.jsonl"

expected=$(awk '$2 == "dbtune" || $2 == "*dbtune" {print $1; exit}' "$temporary/dbtune.sha256")
case $expected in
    *[!0-9a-fA-F]*|'') fail checksum_record_invalid ;;
esac
[ "${#expected}" -eq 64 ] || fail checksum_length_invalid

artifact="$temporary/dbtune"
if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    validate_privileged_install_path
fi
run_privileged install -d -m 0755 "$INSTALL_DIR"
if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    validate_privileged_install_path
    if [ -e "$target_new" ] || [ -L "$target_new" ]; then
        fail temporary_target_exists "$target_new"
    fi
    target_created=1
    run_privileged install -o root -g root -m 0644 "$temporary/dbtune" "$target_new"
    artifact=$target_new
    validate_privileged_staging "$artifact" 644
fi

if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$artifact" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$artifact" | awk '{print $1}')
else
    fail checksum_tool_missing
fi
[ "$actual" = "$expected" ] || fail checksum_failed
verify_attestation "$artifact" "refs/tags/$selected_release" ||
    fail attestation_failed
bash -n "$artifact" || fail artifact_syntax_invalid
artifact_version=$(
    (
        unset DBTUNE_VERSION DBTUNE_ARTIFACT_VERSION DBTUNE_RELEASE DBTUNE_PROGRAM
        bash "$artifact" version
    ) | awk 'NF == 2 && $1 == "dbtune" {print $2}'
)
[ -n "$artifact_version" ] || fail artifact_version_invalid
if [ "v$artifact_version" != "$selected_release" ]; then
    fail artifact_version_mismatch "$artifact_version" "${selected_release#v}"
fi

if [ "$PRIVILEGED_INSTALL" -eq 1 ]; then
    run_privileged chmod 0755 "$target_new"
    validate_privileged_staging "$target_new" 755
    validate_privileged_install_path
else
    target_created=1
    install -m 0755 "$temporary/dbtune" "$target_new"
fi
run_privileged mv -f "$target_new" "$INSTALL_DIR/dbtune"
target_created=0

installed_version=$("$INSTALL_DIR/dbtune" version) || fail installed_unusable
printf 'Wooptima DB Tuner install: %s\n' "$installed_version"
installer_printf install_done "$INSTALL_DIR"
installer_printf next_step
