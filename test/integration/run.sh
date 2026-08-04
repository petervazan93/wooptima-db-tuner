#!/usr/bin/env bash

set -u

integration_compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose -f "$(dirname -- "$0")/docker-compose.yml" "$@"
    else
        docker-compose -f "$(dirname -- "$0")/docker-compose.yml" "$@"
    fi
}

integration_wait_healthy() {
    local service=$1
    local container health attempts=0 stable=0

    container=$(integration_compose ps -q "$service") || return 1
    while ((attempts < 60)); do
        health=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)
        if [[ $health == healthy ]] && integration_compose exec -T "$service" mariadb -Nse 'SELECT 1' >/dev/null 2>&1; then
            stable=$((stable + 1))
            ((stable >= 2)) && return 0
        else
            stable=0
        fi
        sleep 2
        ((attempts += 1))
    done
    printf 'integration: %s is not healthy\n' "$service" >&2
    return 1
}

integration_smoke() {
    local service=$1

    printf 'integration: %s live variable a parser smoke test\n' "$service"
    integration_compose exec -T "$service" mariadb -Nse \
        "SELECT COUNT(*) FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME IN ('MAX_CONNECTIONS','SKIP_NAME_RESOLVE') HAVING COUNT(*)=2" |
        grep -qx '2' || return 1
    # shellcheck disable=SC2016
    integration_compose exec -T "$service" sh -eu -c '
        config=/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf
        printf "%s\n" "[mysqld]" "max_connections=151" "skip_name_resolve=1" >"$config"
        if mariadbd --help --verbose 2>&1 | grep -q -- --validate-config; then
            install -d -o mysql -g mysql /tmp/dbtune-validate
            output=$(mariadbd --validate-config --user=mysql --datadir=/tmp/dbtune-validate 2>&1) || status=$?
            status=${status:-0}
            if printf "%s\n" "$output" | grep -iE "unknown (variable|option)|invalid (value|argument|option)|is invalid|error while setting value|incorrect value|failed to set value|\[error\]"; then
                exit 1
            fi
            if [ "$status" -ne 0 ] && ! printf "%s\n" "$output" | grep -qiE "error: 11|failed to initialize plugins|aborting"; then
                printf "%s\n" "$output" >&2
                exit "$status"
            fi
        else
            mariadbd --help --verbose >/tmp/dbtune-help 2>&1
            ! grep -iE "unknown (variable|option)|invalid (value|argument|option)|is invalid|error while setting value|incorrect value|failed to set value|\[error\]" /tmp/dbtune-help
        fi
    '
}

integration_dbtune_language() {
    local service=$1
    local ui_lang=$2
    shift 2

    integration_compose exec -T "$service" env \
        PATH=/var/lib/dbtune-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        DBTUNE_STATE_DIR=/var/lib/dbtune \
        DBTUNE_CONFIG_ALLOWED_DIR=/etc/mysql/mariadb.conf.d \
        DBTUNE_SYSTEMD_DIR=/var/lib/dbtune-systemd \
        DBTUNE_SYSTEMCTL=/var/lib/dbtune-bin/systemctl \
        DBTUNE_PROGRAM_PATH=/usr/local/bin/dbtune \
        DBTUNE_SAMPLE_SECONDS=1 \
        DBTUNE_MAX_SAMPLE_INTERVAL_SECONDS=5 \
        DBTUNE_MIN_FREE_KB=1 \
        DBTUNE_MIN_APPLY_SAMPLES=5 \
        DBTUNE_NOW_HHMM=1200 \
        DBTUNE_NOW_EPOCH=1785578400 \
        DBTUNE_UI_LANG="$ui_lang" \
        /usr/local/bin/dbtune "$@"
}

integration_dbtune() {
    local service=$1
    shift

    integration_dbtune_language "$service" "${DBTUNE_UI_LANG:-en}" "$@"
}

integration_assert_report_language() {
    local service=$1
    local ui_lang=$2
    local title

    case $ui_lang in
        en) title='# dbtune report' ;;
        sk) title='# dbtune správa' ;;
        *) return 64 ;;
    esac
    # shellcheck disable=SC2016
    integration_compose exec -T "$service" env EXPECTED_LANG="$ui_lang" EXPECTED_TITLE="$title" sh -eu -c '
        grep -Fx "$EXPECTED_TITLE" /var/lib/dbtune/report.md >/dev/null
        grep -F "\"report.language\":\"$EXPECTED_LANG\"" /var/lib/dbtune/report.json >/dev/null
    '
}

integration_proposal_records() {
    local service=$1

    # shellcheck disable=SC2016
    integration_compose exec -T "$service" awk '
        /^[[:space:]]*\[/ { active=($0 ~ /^[[:space:]]*\[mysqld\][[:space:]]*$/); next }
        active && /^[[:space:]]*[A-Za-z][A-Za-z0-9_-]*[[:space:]]*=/ {
            line=$0
            sub(/[[:space:]]*[#;].*$/, "", line)
            split(line, fields, "=")
            key=fields[1]
            value=substr(line, index(line, "=") + 1)
            gsub(/[[:space:]]/, "", key)
            gsub(/-/, "_", key)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print tolower(key) "\t" value
        }
    ' /var/lib/dbtune/proposed-99-zz-tuning.cnf | LC_ALL=C sort
}

integration_lifecycle() {
    local service=$1
    local audit_output proposal_en proposal_sk

    printf 'integration: %s dbtune lifecycle\n' "$service"
    integration_compose exec -T "$service" sh -eu -c '
        install -d -m 755 /var/lib/dbtune-bin /var/log/mysql
        chown mysql:mysql /var/log/mysql
        printf "%s\n" "#!/bin/sh" "exit 0" >/var/lib/dbtune-bin/systemctl
        printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" /dev/dbtune-integration" >/var/lib/dbtune-bin/findmnt
        printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" \"dbtune-integration disk 0 Integration_NVMe\"" >/var/lib/dbtune-bin/lsblk
        chmod 755 /var/lib/dbtune-bin/systemctl /var/lib/dbtune-bin/findmnt /var/lib/dbtune-bin/lsblk
        rm -rf /var/lib/dbtune
        install -d -m 700 /var/lib/dbtune
        printf "%b\n" \
            "schema\t1" \
            "status\tverified" \
            "source\tdocker-integration-backup-fixture" \
            "checked_at\t2026-08-01T10:00:00Z" \
            "last_success\t2026-08-01T09:00:00Z" >/var/lib/dbtune/backup-evidence.tsv
        chmod 600 /var/lib/dbtune/backup-evidence.tsv
    ' || return 1
    if ! audit_output=$(integration_dbtune "$service" audit); then
        printf 'integration: %s audit is not authoritative\n%s\n' "$service" "$audit_output" >&2
        # shellcheck disable=SC2016
        integration_compose exec -T "$service" awk -F '\t' \
            '$1 ~ /^audit\.(overall_status|failed_sections|partial_sections|affected_domains|section\.)/ {print}' \
            /var/lib/dbtune/audit.tsv >&2 || true
        return 1
    fi
    # shellcheck disable=SC2016
    integration_compose exec -T "$service" awk -F '\t' '
        $1=="audit.overall_status" && ($2=="PASS" || $2=="FINDINGS") {authoritative=1}
        $1=="audit.section.hardware.status" && $2=="complete" {hardware=1}
        $1=="audit.section.mariadb.status" && $2=="complete" {mariadb=1}
        $1=="audit.section.mariadb.evidence_schema_version" && $2=="1" {schema=1}
        $1=="audit.section.mariadb.missing_evidence" && $2=="none" {missing=1}
        $1=="audit.section.mariadb.invalid_evidence" && $2=="none" {invalid=1}
        $1=="audit.section.mariadb.conflicting_evidence" && $2=="none" {conflicting=1}
        $1=="hw.storage_class" && $2=="nvme" {storage=1}
        END {exit !(authoritative && hardware && mariadb && schema && missing && invalid && conflicting && storage)}
    ' /var/lib/dbtune/audit.tsv || return 1
    integration_dbtune "$service" collect start --days 1 >/dev/null || return 1
    for _ in 1 2 3 4 5; do
        integration_dbtune "$service" _tick >/dev/null || return 1
    done
    integration_dbtune "$service" collect stop >/dev/null || return 1
    integration_dbtune "$service" analyze --min-samples 5 || return 1
    integration_dbtune_language "$service" en report >/dev/null || return 1
    integration_assert_report_language "$service" en || return 1
    integration_dbtune_language "$service" en propose >/dev/null || return 1
    proposal_en=$(integration_proposal_records "$service") || return 1
    integration_dbtune_language "$service" sk report >/dev/null || return 1
    integration_assert_report_language "$service" sk || return 1
    integration_dbtune_language "$service" sk propose >/dev/null || return 1
    proposal_sk=$(integration_proposal_records "$service") || return 1
    [[ -n $proposal_en && $proposal_en == "$proposal_sk" ]] || return 1
    integration_dbtune "$service" report >/dev/null || return 1
    integration_assert_report_language "$service" "${DBTUNE_UI_LANG:-en}" || return 1
    integration_dbtune "$service" propose >/dev/null || return 1
    integration_dbtune "$service" apply >/dev/null || return 1
    integration_compose restart "$service" || return 1
    integration_wait_healthy "$service" || return 1
    integration_dbtune "$service" verify --post >/dev/null || return 1
    # shellcheck disable=SC2016
    integration_compose exec -T "$service" sh -eu -c '
        test "$(cat /var/lib/dbtune/state)" = verified
        test -s /var/lib/dbtune/report.md
        test -s /var/lib/dbtune/report.json
        test -s /var/lib/dbtune/proposal-manifest.tsv
        test -s /var/lib/dbtune/backup-evidence.tsv
        test -s /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf
    '
}

integration_main() {
    local status=0

    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        if [[ -n ${CI:-} && ${CI:-} != 0 && ${CI:-} != false ]] || [[ ${DBTUNE_REQUIRE_INTEGRATION:-0} == 1 ]]; then
            printf 'integration: FAIL (Docker engine is unavailable in required mode)\n' >&2
            return 1
        fi
        printf 'integration: SKIP (Docker engine is unavailable)\n'
        return 0
    fi
    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        if [[ -n ${CI:-} && ${CI:-} != 0 && ${CI:-} != false ]] || [[ ${DBTUNE_REQUIRE_INTEGRATION:-0} == 1 ]]; then
            printf 'integration: FAIL (Docker Compose is unavailable in required mode)\n' >&2
            return 1
        fi
        printf 'integration: SKIP (Docker and docker compose are unavailable)\n'
        return 0
    fi
    trap 'integration_compose down -v >/dev/null 2>&1 || true' EXIT
    integration_compose up -d --build || return 1
    integration_wait_healthy mariadb106 || return 1
    integration_wait_healthy mariadb114 || return 1
    integration_smoke mariadb106 || status=1
    integration_smoke mariadb114 || status=1
    integration_lifecycle mariadb106 || status=1
    integration_lifecycle mariadb114 || status=1
    return "$status"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    integration_main "$@"
fi
