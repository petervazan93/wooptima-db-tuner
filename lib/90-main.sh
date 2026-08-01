dbtune_usage() {
    cat <<'USAGE'
Pouzitie: dbtune <prikaz> [volby]

Prikazy:
  audit [--json]                  Read-only audit a novy meraci cyklus
  collect start [--days N]       Zber metrik, predvolene 7 dni
  collect status | stop          Stav alebo zastavenie zberu
  analyze [--min-samples N]      Analyza nazbieranych metrik
  report                         Vygenerovanie reportu
  propose                        Navrh MariaDB konfiguracie
  apply [--restart] [--force]    Bezpecne nasadenie navrhu
  verify --post | --24h          Kontrola po nasadeni
  rollback                       Obnovenie povodnej konfiguracie
  status                         Stav dbtune
  version                        Verzia programu
  _tick                          Interny timer tick

  -h, --help                     Tato napoveda
USAGE
}

dbtune_version() {
    printf '%s %s\n' "$DBTUNE_PROGRAM" "$DBTUNE_VERSION"
}

dbtune_call_command() {
    local function_name=${1:-}
    shift || true
    if ! declare -F "$function_name" >/dev/null 2>&1; then
        dbtune_log error "Modul pre '$function_name' nie je v tomto builde dostupny"
        return 69
    fi
    "$function_name" "$@"
}

dbtune_collect_operation() {
    case ${1:-} in
        start) printf 'collect_start\n' ;;
        status) printf 'collect_status\n' ;;
        stop) printf 'collect_stop\n' ;;
        *) return 64 ;;
    esac
}

dbtune_dispatch_guarded() {
    local operation=${1:-}
    local function_name=${2:-}
    shift 2 || true

    dbtune_require_state "$operation" || return
    dbtune_call_command "$function_name" "$@"
}

dbtune_dispatch_tick() {
    if ! dbtune_require_state _tick; then
        dbtune_event tick_skipped state "$(dbtune_state_read 2>/dev/null || printf unknown)" || true
        return 0
    fi
    if ! dbtune_call_command cmd_tick "$@"; then
        dbtune_event tick_failed state collecting || true
    fi
    return 0
}

dbtune_dispatch() {
    local command=${1:-}
    local operation

    [[ -n $command ]] || {
        dbtune_usage >&2
        return 64
    }
    shift
    case $command in
        -h|--help|help)
            dbtune_usage
            ;;
        version|--version)
            dbtune_version
            ;;
        audit)
            dbtune_with_lifecycle_lock wait audit dbtune_dispatch_guarded audit cmd_audit "$@"
            ;;
        collect)
            operation=$(dbtune_collect_operation "${1:-}") || {
                dbtune_log error "Pouzitie: dbtune collect start|status|stop"
                return 64
            }
            if [[ $operation == collect_status ]]; then
                dbtune_dispatch_guarded "$operation" cmd_collect "$@"
            else
                dbtune_with_lifecycle_lock wait "$operation" dbtune_dispatch_guarded "$operation" cmd_collect "$@"
            fi
            ;;
        apply)
            dbtune_with_lifecycle_lock wait apply dbtune_call_command cmd_apply "$@"
            ;;
        analyze|report|propose|verify|rollback|status)
            if [[ $command == status ]]; then
                dbtune_dispatch_guarded "$command" "cmd_$command" "$@"
            else
                dbtune_with_lifecycle_lock wait "$command" dbtune_dispatch_guarded "$command" "cmd_$command" "$@"
            fi
            ;;
        _tick)
            if dbtune_with_lifecycle_lock skip _tick dbtune_dispatch_tick "$@"; then
                return 0
            else
                operation=$?
            fi
            if ((operation == 75)); then
                dbtune_event tick_skipped reason lifecycle_locked || true
            else
                dbtune_event tick_failed reason lifecycle_lock || true
            fi
            return 0
            ;;
        *)
            dbtune_log error "Neznamy prikaz: $command"
            dbtune_usage >&2
            return 64
            ;;
    esac
}

dbtune_main() {
    umask 077
    dbtune_dispatch "$@"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    dbtune_main "$@"
fi
