DBTUNE_I18N_LANGUAGE=en
DBTUNE_I18N_MESSAGE=

dbtune_i18n_lookup() {
    local message_id=${1:-}

    case "$DBTUNE_I18N_LANGUAGE:$message_id" in
        en:cli_usage)
            DBTUNE_I18N_MESSAGE=$'Usage: dbtune <command> [options]\n\nCommands:\n  audit [--json]                  Read-only audit and a new measurement cycle\n  collect start [--days N]       Collect metrics, 7 days by default\n  collect status | stop          Show or stop collection\n  analyze [--min-samples N]      Analyze collected metrics\n  report                         Generate a report\n  propose                        Propose MariaDB configuration\n  apply [--restart] [--force]    Safely apply the proposal\n  verify --post | --24h          Verify after applying\n  rollback                       Restore the original configuration\n  status                         Show dbtune status\n  version                        Show program version\n  _tick                          Internal timer tick\n\n  -h, --help                     Show this help\n'
            ;;
        sk:cli_usage)
            DBTUNE_I18N_MESSAGE=$'Pouzitie: dbtune <prikaz> [volby]\n\nPrikazy:\n  audit [--json]                  Read-only audit a novy meraci cyklus\n  collect start [--days N]       Zber metrik, predvolene 7 dni\n  collect status | stop          Stav alebo zastavenie zberu\n  analyze [--min-samples N]      Analyza nazbieranych metrik\n  report                         Vygenerovanie reportu\n  propose                        Navrh MariaDB konfiguracie\n  apply [--restart] [--force]    Bezpecne nasadenie navrhu\n  verify --post | --24h          Kontrola po nasadeni\n  rollback                       Obnovenie povodnej konfiguracie\n  status                         Stav dbtune\n  version                        Verzia programu\n  _tick                          Interny timer tick\n\n  -h, --help                     Tato napoveda\n'
            ;;
        en:cli_module_unavailable)
            DBTUNE_I18N_MESSAGE="Module for '%s' is not available in this build"
            ;;
        sk:cli_module_unavailable)
            DBTUNE_I18N_MESSAGE="Modul pre '%s' nie je v tomto builde dostupny"
            ;;
        en:cli_collect_usage)
            DBTUNE_I18N_MESSAGE='Usage: dbtune collect start|status|stop'
            ;;
        sk:cli_collect_usage)
            DBTUNE_I18N_MESSAGE='Pouzitie: dbtune collect start|status|stop'
            ;;
        en:cli_unknown_command)
            DBTUNE_I18N_MESSAGE='Unknown command: %s'
            ;;
        sk:cli_unknown_command)
            DBTUNE_I18N_MESSAGE='Neznamy prikaz: %s'
            ;;
        en:i18n_unsupported_language)
            DBTUNE_I18N_MESSAGE=$'Unsupported interface language: %s (expected en or sk)\n'
            ;;
        sk:i18n_unsupported_language)
            DBTUNE_I18N_MESSAGE=$'Nepodporovany jazyk rozhrania: %s (ocakavane en alebo sk)\n'
            ;;
        *)
            printf 'dbtune: missing interface message: %s\n' "$message_id" >&2
            return 70
            ;;
    esac
}

dbtune_i18n_set() {
    local language=${1:-}

    case $language in
        en|sk)
            DBTUNE_I18N_LANGUAGE=$language
            DBTUNE_UI_LANG=$language
            ;;
        *)
            dbtune_eprintf i18n_unsupported_language "$language"
            return 64
            ;;
    esac
}

dbtune_i18n_init() {
    local language=${DBTUNE_UI_LANG:-en}

    [[ -n $language ]] || language=en
    dbtune_i18n_set "$language"
}

dbtune_msg() {
    dbtune_i18n_lookup "${1:-}" || return
    printf '%s' "$DBTUNE_I18N_MESSAGE"
}

dbtune_printf() {
    local message_id=${1:-}
    shift || true

    dbtune_i18n_lookup "$message_id" || return
    # shellcheck disable=SC2059 # Format strings come only from the trusted static catalog.
    printf "$DBTUNE_I18N_MESSAGE" "$@"
}

dbtune_eprintf() {
    dbtune_printf "$@" >&2
}
