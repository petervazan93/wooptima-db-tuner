#!/usr/bin/env bash

set -u

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P) || exit 1
bats_bin=${BATS_BIN:-bats}
expected_count=8
filter='^(CLI help and version are always available|delta metrics use counter differences|loaded defaults catalog is the single exact landmine definition|audit effective variables exactly cover the rules proposal contract|strict proposal grammar emits canonical records only after complete validation|apply rejects an unknown live variable before writing|installer rejects an unsupported interface language before trust checks|runtime and POSIX installer catalogs are complete)$'

if ! command -v "$bats_bin" >/dev/null 2>&1; then
    printf '%s\n' 'fast tests: Bats is required' >&2
    exit 69
fi

selected=$(
    "$bats_bin" --count --filter "$filter" "$project_root/test/unit"
) || exit $?
if [[ $selected != "$expected_count" ]]; then
    printf 'fast tests: selected %s tests; expected %s\n' \
        "$selected" "$expected_count" >&2
    exit 65
fi

started=$SECONDS
printf 'fast tests: running %s guarded smoke tests\n' "$selected"
"$bats_bin" --filter "$filter" "$project_root/test/unit"
result=$?
printf 'fast tests: completed in %ss\n' "$((SECONDS - started))"
exit "$result"
