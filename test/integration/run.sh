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
    printf 'integration: %s nie je healthy\n' "$service" >&2
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

integration_dbtune() {
    local service=$1
    shift

    integration_compose exec -T "$service" env \
        DBTUNE_STATE_DIR=/var/lib/dbtune \
        DBTUNE_SYSTEMD_DIR=/var/lib/dbtune-systemd \
        DBTUNE_SYSTEMCTL=/var/lib/dbtune-bin/systemctl \
        DBTUNE_PROGRAM_PATH=/usr/local/bin/dbtune \
        DBTUNE_SAMPLE_SECONDS=1 \
        DBTUNE_MAX_SAMPLE_INTERVAL_SECONDS=5 \
        DBTUNE_MIN_FREE_KB=1 \
        DBTUNE_MIN_APPLY_SAMPLES=5 \
        DBTUNE_NOW_HHMM=1200 \
        /usr/local/bin/dbtune "$@"
}

integration_lifecycle() {
    local service=$1

    printf 'integration: %s dbtune lifecycle\n' "$service"
    integration_compose exec -T "$service" sh -eu -c '
        install -d -m 755 /var/lib/dbtune-bin /var/log/mysql
        chown mysql:mysql /var/log/mysql
        printf "%s\n" "#!/bin/sh" "exit 0" >/var/lib/dbtune-bin/systemctl
        chmod 755 /var/lib/dbtune-bin/systemctl
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
    integration_dbtune "$service" audit >/dev/null || return 1
    integration_dbtune "$service" collect start --days 1 >/dev/null || return 1
    for _ in 1 2 3 4 5; do
        integration_dbtune "$service" _tick >/dev/null || return 1
    done
    integration_dbtune "$service" collect stop >/dev/null || return 1
    integration_dbtune "$service" analyze --min-samples 5 || return 1
    integration_dbtune "$service" report >/dev/null || return 1
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
        printf 'integration: SKIP (Docker engine nie je dostupny)\n'
        return 0
    fi
    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        printf 'integration: SKIP (Docker alebo docker compose nie je dostupny)\n'
        return 0
    fi
    trap 'integration_compose down -v >/dev/null 2>&1 || true' EXIT
    integration_compose up -d || return 1
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
