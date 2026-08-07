#!/usr/bin/env bash

set -u

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/dbtune-environment-contract.XXXXXX") || exit 1
trap 'rm -rf "$temporary"' EXIT

# shellcheck disable=SC1090,SC1091
source "$ROOT_DIR/lib/00-header.sh"
# shellcheck disable=SC1090,SC1091
source "$ROOT_DIR/lib/10-util.sh"

grep -hEo 'DBTUNE_[A-Z0-9_]+' "$ROOT_DIR"/lib/*.sh | LC_ALL=C sort -u >"$temporary/symbols"
dbtune_runtime_environment_contract >"$temporary/contract"

awk -F '\t' '
    NF != 2 || $1 !~ /^DBTUNE_[A-Z0-9_]+$/ ||
        $2 !~ /^(immutable|operator|test-only|internal)$/ {
        print "invalid runtime environment classification: " $0 > "/dev/stderr"
        failed=1
        next
    }
    seen[$1]++ {
        print "duplicate runtime environment classification: " $1 > "/dev/stderr"
        failed=1
    }
    END { exit failed }
' "$temporary/contract" || exit 1

awk -F '\t' '
    NR == FNR { classified[$1]=1; next }
    { referenced[$1]=1; if (!classified[$1]) { print "unclassified runtime environment symbol: " $1 > "/dev/stderr"; failed=1 } }
    END {
        for (name in classified) {
            if (!referenced[name]) {
                print "stale runtime environment classification: " name > "/dev/stderr"
                failed=1
            }
        }
        exit failed
    }
' "$temporary/contract" "$temporary/symbols"
