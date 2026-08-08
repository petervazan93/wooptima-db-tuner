#!/usr/bin/env bash

set -u

# shellcheck disable=SC2034 # Replaced with an immutable value in built artifacts.
readonly DBTUNE_ARTIFACT_PROFILE=source-test
if [[ $DBTUNE_ARTIFACT_PROFILE != source-test ]]; then
    if [[ ${BASH_SOURCE[0]} != "$0" ]]; then return 65; else exit 65; fi
fi

if [[ $DBTUNE_ARTIFACT_PROFILE == production && ${BASH_SOURCE[0]} != "$0" ]]; then
    return 65
fi
if [[ $DBTUNE_ARTIFACT_PROFILE == production ]] && (return 0 2>/dev/null); then
    return 65
fi

# shellcheck disable=SC2034 # Consumed by later modules in the assembled artifact.
readonly DBTUNE_ARTIFACT_VERSION=0.4.2
if [[ $DBTUNE_ARTIFACT_VERSION != 0.4.2 ]]; then
    if [[ ${BASH_SOURCE[0]} != "$0" ]]; then return 65; else exit 65; fi
fi
DBTUNE_STATE_DIR="${DBTUNE_STATE_DIR:-/var/lib/dbtune}"
DBTUNE_ROOT_CNF="${DBTUNE_ROOT_CNF:-/etc/mysql/conf.d/root.cnf}"
DBTUNE_LOG_LEVEL="${DBTUNE_LOG_LEVEL:-info}"
DBTUNE_UI_LANG="${DBTUNE_UI_LANG:-}"
if [[ $DBTUNE_ARTIFACT_PROFILE == production ]]; then
    DBTUNE_PROGRAM=dbtune
    DBTUNE_DEFAULT_DAYS=7
    DBTUNE_SQL_AUTH_METHOD=
    DBTUNE_SQL_DEFAULTS_FILE=
else
    DBTUNE_PROGRAM="${DBTUNE_PROGRAM:-dbtune}"
    DBTUNE_DEFAULT_DAYS="${DBTUNE_DEFAULT_DAYS:-7}"
    DBTUNE_SQL_AUTH_METHOD="${DBTUNE_SQL_AUTH_METHOD:-}"
    DBTUNE_SQL_DEFAULTS_FILE="${DBTUNE_SQL_DEFAULTS_FILE:-}"
fi
