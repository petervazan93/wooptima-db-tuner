#!/usr/bin/env bash

set -u

# shellcheck disable=SC2034 # Consumed by later modules in the assembled artifact.
readonly DBTUNE_ARTIFACT_VERSION=0.2.0
DBTUNE_PROGRAM="${DBTUNE_PROGRAM:-dbtune}"
DBTUNE_STATE_DIR="${DBTUNE_STATE_DIR:-/var/lib/dbtune}"
DBTUNE_DEFAULT_DAYS="${DBTUNE_DEFAULT_DAYS:-7}"
DBTUNE_ROOT_CNF="${DBTUNE_ROOT_CNF:-/etc/mysql/conf.d/root.cnf}"
DBTUNE_LOG_LEVEL="${DBTUNE_LOG_LEVEL:-info}"
DBTUNE_SQL_AUTH_METHOD="${DBTUNE_SQL_AUTH_METHOD:-}"
DBTUNE_SQL_DEFAULTS_FILE="${DBTUNE_SQL_DEFAULTS_FILE:-}"
