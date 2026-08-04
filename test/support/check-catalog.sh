#!/bin/sh

set -eu

mode=${1:-}
catalog=${2:-}
[ -n "$catalog" ] || {
    printf '%s\n' 'catalog: catalog path is required' >&2
    exit 2
}
shift 2

temporary=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-catalog.XXXXXX") || exit 2
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
catalog_ids=$temporary/catalog-ids
used_ids=$temporary/used-ids

if ! awk '
    /^[[:space:]]*(en|sk):\)/ {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        language = line
        sub(/:.*/, "", language)
        print "catalog: missing ID: " language > "/dev/stderr"
        missing_id = 1
        exit 1
    }
    /^[[:space:]]*(en|sk):[A-Za-z0-9_]+\)/ {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        language = line
        sub(/:.*/, "", language)
        id = line
        sub(/^[^:]*:/, "", id)
        sub(/\).*/, "", id)
        count[language SUBSEP id]++
        language_count[language]++
    }
    END {
        if (missing_id) exit 1
        if (!language_count["en"]) {
            print "catalog: missing en IDs" > "/dev/stderr"
            exit 1
        }
        if (!language_count["sk"]) {
            print "catalog: missing sk IDs" > "/dev/stderr"
            exit 1
        }
        for (key in count) {
            split(key, parts, SUBSEP)
            language = parts[1]
            id = parts[2]
            if (count[key] > 1) {
                print "catalog: duplicate ID: " language ":" id > "/dev/stderr"
                exit 1
            }
            if (language == "en") en[id] = 1
            if (language == "sk") sk[id] = 1
        }
        for (id in en) {
            if (!(id in sk)) {
                print "catalog: en/sk ID-set mismatch: " id > "/dev/stderr"
                exit 1
            }
        }
        for (id in sk) {
            if (!(id in en)) {
                print "catalog: en/sk ID-set mismatch: " id > "/dev/stderr"
                exit 1
            }
        }
        for (id in en) print id
    }
' "$catalog" >"$catalog_ids"; then
    exit 1
fi

case $mode in
    runtime)
        [ "$#" -gt 0 ] || {
            printf '%s\n' 'catalog: runtime source paths are required' >&2
            exit 2
        }
        awk '
            {
                line = $0
                while (match(line, /dbtune_(msg|printf|eprintf|i18n_lookup)[[:space:]]+[A-Za-z][A-Za-z0-9_]*/)) {
                    call = substr(line, RSTART, RLENGTH)
                    sub(/^dbtune_(msg|printf|eprintf|i18n_lookup)[[:space:]]+/, "", call)
                    print call
                    line = substr(line, RSTART + RLENGTH)
                }
                line = $0
                while (match(line, /"reason_[a-z0-9_]+"/)) {
                    id = substr(line, RSTART + 1, RLENGTH - 2)
                    if (id != "reason_id" && id != "reason_sk") print id
                    line = substr(line, RSTART + RLENGTH)
                }
                line = $0
                while (match(line, /action_warning_[a-z0-9_]+/)) {
                    print substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        ' "$@" >"$used_ids"
        label='runtime'
        ;;
    installer)
        awk '
            {
                line = $0
                while (match(line, /(installer_message|installer_printf|fail)[[:space:]]+[a-z][a-z0-9_]*/)) {
                    call = substr(line, RSTART, RLENGTH)
                    sub(/^(installer_message|installer_printf|fail)[[:space:]]+/, "", call)
                    print call
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        ' "$catalog" >"$used_ids"
        label='installer'
        ;;
    *)
        printf 'catalog: unsupported mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac

awk -v label="$label" '
    NR == FNR { catalog[$1] = 1; next }
    !($1 in catalog) {
        print "catalog: static " label " ID absent from catalog: " $1 > "/dev/stderr"
        exit 1
    }
' "$catalog_ids" "$used_ids"
