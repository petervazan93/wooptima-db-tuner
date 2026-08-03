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
        en:core_value_empty)
            DBTUNE_I18N_MESSAGE='<empty>'
            ;;
        sk:core_value_empty)
            DBTUNE_I18N_MESSAGE='<prazdny>'
            ;;
        en:core_label_managed_file)
            DBTUNE_I18N_MESSAGE='Managed file'
            ;;
        sk:core_label_managed_file)
            DBTUNE_I18N_MESSAGE='Spravovany subor'
            ;;
        en:core_label_state_file)
            DBTUNE_I18N_MESSAGE='State file'
            ;;
        sk:core_label_state_file)
            DBTUNE_I18N_MESSAGE='State subor'
            ;;
        en:core_label_published_state_file)
            DBTUNE_I18N_MESSAGE='Published state file'
            ;;
        sk:core_label_published_state_file)
            DBTUNE_I18N_MESSAGE='Publikovany state subor'
            ;;
        en:core_label_state_lock)
            DBTUNE_I18N_MESSAGE='State lock'
            ;;
        sk:core_label_state_lock)
            DBTUNE_I18N_MESSAGE='State zamok'
            ;;
        en:core_label_lifecycle_lock)
            DBTUNE_I18N_MESSAGE='Lifecycle lock'
            ;;
        sk:core_label_lifecycle_lock)
            DBTUNE_I18N_MESSAGE='Lifecycle zamok'
            ;;
        en:core_label_event_lock)
            DBTUNE_I18N_MESSAGE='Event lock'
            ;;
        sk:core_label_event_lock)
            DBTUNE_I18N_MESSAGE='Event zamok'
            ;;
        en:core_invalid_state_file_name)
            DBTUNE_I18N_MESSAGE='Invalid state file name: %s'
            ;;
        sk:core_invalid_state_file_name)
            DBTUNE_I18N_MESSAGE='Neplatny nazov state suboru: %s'
            ;;
        en:core_unsafe_regular_file)
            DBTUNE_I18N_MESSAGE='%s is not a safe regular file: %s'
            ;;
        sk:core_unsafe_regular_file)
            DBTUNE_I18N_MESSAGE='%s nie je bezpecny regularny subor: %s'
            ;;
        en:core_unexpected_hardlink_topology)
            DBTUNE_I18N_MESSAGE='%s does not have the expected hard-link topology: %s (links=%s, expected=1)'
            ;;
        sk:core_unexpected_hardlink_topology)
            DBTUNE_I18N_MESSAGE='%s nema ocakavanu hardlink topologiu: %s (links=%s, ocakavane=1)'
            ;;
        en:core_state_dir_canonical_absolute)
            DBTUNE_I18N_MESSAGE='State directory must be a canonical absolute path: %s'
            ;;
        sk:core_state_dir_canonical_absolute)
            DBTUNE_I18N_MESSAGE='State adresar musi byt kanonicka absolutna cesta: %s'
            ;;
        en:core_state_parent_unsafe)
            DBTUNE_I18N_MESSAGE='State parent component is not a safe real directory: %s'
            ;;
        sk:core_state_parent_unsafe)
            DBTUNE_I18N_MESSAGE='State parent komponent nie je bezpecny realny adresar: %s'
            ;;
        en:core_state_parent_untrusted_metadata)
            DBTUNE_I18N_MESSAGE='State parent component has untrusted ownership or mode: %s (%s:%s %s)'
            ;;
        sk:core_state_parent_untrusted_metadata)
            DBTUNE_I18N_MESSAGE='State parent komponent ma nedoveryhodne vlastnictvo alebo mode: %s (%s:%s %s)'
            ;;
        en:core_state_parent_untrusted_writable)
            DBTUNE_I18N_MESSAGE='State parent component is untrusted group/world writable: %s (%s:%s %s)'
            ;;
        sk:core_state_parent_untrusted_writable)
            DBTUNE_I18N_MESSAGE='State parent komponent je nedoveryhodne group/world writable: %s (%s:%s %s)'
            ;;
        en:core_state_path_unsafe)
            DBTUNE_I18N_MESSAGE='State path is not a safe real directory: %s'
            ;;
        sk:core_state_path_unsafe)
            DBTUNE_I18N_MESSAGE='State cesta nie je bezpecny realny adresar: %s'
            ;;
        en:core_state_dir_wrong_owner)
            DBTUNE_I18N_MESSAGE='State directory is not owned by the expected privileged identity: %s (%s:%s)'
            ;;
        sk:core_state_dir_wrong_owner)
            DBTUNE_I18N_MESSAGE='State adresar nevlastni ocakavana privilegovana identita: %s (%s:%s)'
            ;;
        en:core_state_dir_wrong_mode)
            DBTUNE_I18N_MESSAGE='State directory does not have the expected mode: %s (%s)'
            ;;
        sk:core_state_dir_wrong_mode)
            DBTUNE_I18N_MESSAGE='State adresar nema ocakavany mode: %s (%s)'
            ;;
        en:core_state_dir_replaced)
            DBTUNE_I18N_MESSAGE='State directory was replaced during validation: %s'
            ;;
        sk:core_state_dir_replaced)
            DBTUNE_I18N_MESSAGE='State adresar bol pocas validacie vymeneny: %s'
            ;;
        en:core_state_path_symlink)
            DBTUNE_I18N_MESSAGE='State path must not be a symlink: %s'
            ;;
        sk:core_state_path_symlink)
            DBTUNE_I18N_MESSAGE='State cesta nesmie byt symlink: %s'
            ;;
        en:core_invalid_audit_key)
            DBTUNE_I18N_MESSAGE='dbtune: invalid audit key on line %s\n'
            ;;
        sk:core_invalid_audit_key)
            DBTUNE_I18N_MESSAGE='dbtune: neplatny audit key na riadku %s\n'
            ;;
        en:core_conflicting_audit_value)
            DBTUNE_I18N_MESSAGE='dbtune: conflicting duplicate audit value: key=%s; first_line=%s; duplicate_line=%s\n'
            ;;
        sk:core_conflicting_audit_value)
            DBTUNE_I18N_MESSAGE='dbtune: konfliktna duplicitna audit hodnota: key=%s; first_line=%s; duplicate_line=%s\n'
            ;;
        en:core_atomic_target_required)
            DBTUNE_I18N_MESSAGE='Atomic write requires a target path'
            ;;
        sk:core_atomic_target_required)
            DBTUNE_I18N_MESSAGE='Atomicky zapis vyzaduje cielovu cestu'
            ;;
        en:core_atomic_mode_invalid)
            DBTUNE_I18N_MESSAGE='Invalid mode for atomic write: %s'
            ;;
        sk:core_atomic_mode_invalid)
            DBTUNE_I18N_MESSAGE='Neplatny mode pre atomicky zapis: %s'
            ;;
        en:core_uint_required)
            DBTUNE_I18N_MESSAGE='%s must be a non-negative integer'
            ;;
        sk:core_uint_required)
            DBTUNE_I18N_MESSAGE='%s musi byt cele nezaporne cislo'
            ;;
        en:core_uint_internal_range)
            DBTUNE_I18N_MESSAGE='Internal range for %s is invalid'
            ;;
        sk:core_uint_internal_range)
            DBTUNE_I18N_MESSAGE='Interny rozsah pre %s je neplatny'
            ;;
        en:core_uint_range)
            DBTUNE_I18N_MESSAGE='%s must be in the range %s to %s'
            ;;
        sk:core_uint_range)
            DBTUNE_I18N_MESSAGE='%s musi byt v rozsahu %s az %s'
            ;;
        en:core_json_pairs_required)
            DBTUNE_I18N_MESSAGE='JSON emitter expects key-value pairs'
            ;;
        sk:core_json_pairs_required)
            DBTUNE_I18N_MESSAGE='JSON emitter ocakava dvojice kluc hodnota'
            ;;
        en:core_hash_tool_missing)
            DBTUNE_I18N_MESSAGE='Neither sha256sum nor shasum is available'
            ;;
        sk:core_hash_tool_missing)
            DBTUNE_I18N_MESSAGE='Chyba sha256sum aj shasum'
            ;;
        en:core_audit_manifest_missing)
            DBTUNE_I18N_MESSAGE='Audit provenance manifest is missing: %s'
            ;;
        sk:core_audit_manifest_missing)
            DBTUNE_I18N_MESSAGE='Chyba audit provenance manifest: %s'
            ;;
        en:core_audit_artifact_mismatch)
            DBTUNE_I18N_MESSAGE='Audit artifact %s does not match run %s'
            ;;
        sk:core_audit_artifact_mismatch)
            DBTUNE_I18N_MESSAGE='Audit artefakt %s nezodpoveda runu %s'
            ;;
        en:core_audit_hash_mismatch)
            DBTUNE_I18N_MESSAGE='Audit hash does not match the artifacts for run %s'
            ;;
        sk:core_audit_hash_mismatch)
            DBTUNE_I18N_MESSAGE='Audit hash nezodpoveda artefaktom runu %s'
            ;;
        en:core_analysis_input_missing)
            DBTUNE_I18N_MESSAGE='Analysis provenance or one of its inputs is missing'
            ;;
        sk:core_analysis_input_missing)
            DBTUNE_I18N_MESSAGE='Chyba analysis provenance alebo jeho vstup'
            ;;
        en:core_analysis_other_run)
            DBTUNE_I18N_MESSAGE='Analysis belongs to a different audit run (%s)'
            ;;
        sk:core_analysis_other_run)
            DBTUNE_I18N_MESSAGE='Analysis patri inemu audit runu (%s)'
            ;;
        en:core_analysis_other_dbsize)
            DBTUNE_I18N_MESSAGE='Analysis used a different dbsize input'
            ;;
        sk:core_analysis_other_dbsize)
            DBTUNE_I18N_MESSAGE='Analysis pouzila iny dbsize vstup'
            ;;
        en:core_analysis_stale_input)
            DBTUNE_I18N_MESSAGE='Stale or changed analysis input: %s'
            ;;
        sk:core_analysis_stale_input)
            DBTUNE_I18N_MESSAGE='Stale alebo zmeneny analysis vstup: %s'
            ;;
        en:core_analysis_dbsize_rows_mismatch)
            DBTUNE_I18N_MESSAGE='Analysis dbsize baseline rows do not match the input'
            ;;
        sk:core_analysis_dbsize_rows_mismatch)
            DBTUNE_I18N_MESSAGE='Analysis dbsize baseline riadky nezodpovedaju vstupu'
            ;;
        en:core_analysis_fingerprint_mismatch)
            DBTUNE_I18N_MESSAGE='Analysis fingerprint does not match provenance'
            ;;
        sk:core_analysis_fingerprint_mismatch)
            DBTUNE_I18N_MESSAGE='Analysis fingerprint nezodpoveda provenance'
            ;;
        en:core_lock_path_invalid)
            DBTUNE_I18N_MESSAGE='%s must be a direct .lock file in the state directory: %s'
            ;;
        sk:core_lock_path_invalid)
            DBTUNE_I18N_MESSAGE='%s musi byt priamy .lock subor v state adresari: %s'
            ;;
        en:core_lock_metadata_invalid)
            DBTUNE_I18N_MESSAGE='%s has unexpected ownership, mode, or topology: %s (%s:%s %s links=%s, expected=%s)'
            ;;
        sk:core_lock_metadata_invalid)
            DBTUNE_I18N_MESSAGE='%s ma neocakavane vlastnictvo, mode alebo topologiu: %s (%s:%s %s links=%s, ocakavane=%s)'
            ;;
        en:core_lock_replaced)
            DBTUNE_I18N_MESSAGE='%s was replaced while opening: %s'
            ;;
        sk:core_lock_replaced)
            DBTUNE_I18N_MESSAGE='%s bol pocas otvorenia vymeneny: %s'
            ;;
        en:core_lock_open_failed)
            DBTUNE_I18N_MESSAGE='%s could not be opened without following symlinks: %s'
            ;;
        sk:core_lock_open_failed)
            DBTUNE_I18N_MESSAGE='%s sa nepodarilo otvorit bez nasledovania symlinkov: %s'
            ;;
        en:core_open_lock_identity_invalid)
            DBTUNE_I18N_MESSAGE='Opened %s does not have the expected identity'
            ;;
        sk:core_open_lock_identity_invalid)
            DBTUNE_I18N_MESSAGE='Otvoreny %s nema ocakavanu identitu'
            ;;
        en:core_lifecycle_flock_required)
            DBTUNE_I18N_MESSAGE='Lifecycle lock requires flock'
            ;;
        sk:core_lifecycle_flock_required)
            DBTUNE_I18N_MESSAGE='Lifecycle lock vyzaduje flock'
            ;;
        en:core_lifecycle_lock_failed)
            DBTUNE_I18N_MESSAGE='Failed to acquire lifecycle lock for %s'
            ;;
        sk:core_lifecycle_lock_failed)
            DBTUNE_I18N_MESSAGE='Nepodarilo sa ziskat lifecycle lock pre %s'
            ;;
        en:core_event_type_required)
            DBTUNE_I18N_MESSAGE='Event requires a type'
            ;;
        sk:core_event_type_required)
            DBTUNE_I18N_MESSAGE='Event vyzaduje typ'
            ;;
        en:core_event_pairs_required)
            DBTUNE_I18N_MESSAGE='Event expects key-value pairs'
            ;;
        sk:core_event_pairs_required)
            DBTUNE_I18N_MESSAGE='Event ocakava dvojice kluc hodnota'
            ;;
        en:core_state_file_invalid)
            DBTUNE_I18N_MESSAGE='State file contains an invalid state: %s'
            ;;
        sk:core_state_file_invalid)
            DBTUNE_I18N_MESSAGE='State subor obsahuje neplatny stav: %s'
            ;;
        en:core_state_write_invalid)
            DBTUNE_I18N_MESSAGE='Cannot write an invalid state: %s'
            ;;
        sk:core_state_write_invalid)
            DBTUNE_I18N_MESSAGE='Nie je mozne zapisat neplatny stav: %s'
            ;;
        en:core_state_transition_invalid)
            DBTUNE_I18N_MESSAGE='Invalid state transition: %s -> %s'
            ;;
        sk:core_state_transition_invalid)
            DBTUNE_I18N_MESSAGE='Neplatny prechod stavu: %s -> %s'
            ;;
        en:core_command_state_disallowed)
            DBTUNE_I18N_MESSAGE="Command '%s' is not allowed in state '%s'"
            ;;
        sk:core_command_state_disallowed)
            DBTUNE_I18N_MESSAGE="Prikaz '%s' nie je povoleny v stave '%s'"
            ;;
        en:core_sql_client_missing)
            DBTUNE_I18N_MESSAGE='Neither the mariadb nor mysql client was found'
            ;;
        sk:core_sql_client_missing)
            DBTUNE_I18N_MESSAGE='Nenasiel sa klient mariadb ani mysql'
            ;;
        en:core_sql_auth_failed)
            DBTUNE_I18N_MESSAGE='MariaDB root authentication failed through both unix_socket and defaults-extra-file'
            ;;
        sk:core_sql_auth_failed)
            DBTUNE_I18N_MESSAGE='MariaDB root auth zlyhal cez unix_socket aj defaults-extra-file'
            ;;
        en:core_sql_query_required)
            DBTUNE_I18N_MESSAGE='SQL wrapper requires a query'
            ;;
        sk:core_sql_query_required)
            DBTUNE_I18N_MESSAGE='SQL wrapper vyzaduje query'
            ;;
        en:core_sql_timeout_positive)
            DBTUNE_I18N_MESSAGE='SQL timeout must be a positive number'
            ;;
        sk:core_sql_timeout_positive)
            DBTUNE_I18N_MESSAGE='SQL timeout musi byt kladne cislo'
            ;;
        en:core_sql_timeout_max)
            DBTUNE_I18N_MESSAGE='SQL connect timeout may be at most 30s and statement timeout 60s'
            ;;
        sk:core_sql_timeout_max)
            DBTUNE_I18N_MESSAGE='SQL connect timeout moze byt najviac 30s a statement timeout 60s'
            ;;
        en:core_sql_auth_unknown)
            DBTUNE_I18N_MESSAGE='Unknown SQL authentication contract'
            ;;
        sk:core_sql_auth_unknown)
            DBTUNE_I18N_MESSAGE='Neznamy SQL auth kontrakt'
            ;;
        en:audit_invalid_option)
            DBTUNE_I18N_MESSAGE='Unknown audit option: %s'
            ;;
        sk:audit_invalid_option)
            DBTUNE_I18N_MESSAGE='Neznama volba audit: %s'
            ;;
        en:audit_evidence_isolation_failed)
            DBTUNE_I18N_MESSAGE='Conflicting MariaDB audit evidence could not be safely isolated'
            ;;
        sk:audit_evidence_isolation_failed)
            DBTUNE_I18N_MESSAGE='Konfliktne MariaDB auditne dokazy sa nepodarilo bezpecne izolovat'
            ;;
        en:audit_conflicting_values)
            DBTUNE_I18N_MESSAGE='Audit contains conflicting aliases or duplicate values'
            ;;
        sk:audit_conflicting_values)
            DBTUNE_I18N_MESSAGE='Audit obsahuje konfliktne aliasy alebo duplicitne hodnoty'
            ;;
        en:audit_status_failed)
            DBTUNE_I18N_MESSAGE='Overall audit status could not be evaluated'
            ;;
        sk:audit_status_failed)
            DBTUNE_I18N_MESSAGE='Celkovy stav auditu sa nepodarilo vyhodnotit'
            ;;
        en:audit_manifest_failed)
            DBTUNE_I18N_MESSAGE='Audit provenance could not be created'
            ;;
        sk:audit_manifest_failed)
            DBTUNE_I18N_MESSAGE='Audit provenance sa nepodarilo vytvorit'
            ;;
        en:audit_cycle_archive_failed)
            DBTUNE_I18N_MESSAGE='Previous measurement cycle could not be archived'
            ;;
        sk:audit_cycle_archive_failed)
            DBTUNE_I18N_MESSAGE='Predchadzajuci meraci cyklus sa nepodarilo archivovat'
            ;;
        en:audit_write_failed)
            DBTUNE_I18N_MESSAGE='Audit data could not be written atomically'
            ;;
        sk:audit_write_failed)
            DBTUNE_I18N_MESSAGE='Audit data sa nepodarilo atomicky zapisat'
            ;;
        en:audit_value_not_detected)
            DBTUNE_I18N_MESSAGE='not detected'
            ;;
        sk:audit_value_not_detected)
            DBTUNE_I18N_MESSAGE='nezistene'
            ;;
        en:audit_value_not_detected_feminine)
            DBTUNE_I18N_MESSAGE='not detected'
            ;;
        sk:audit_value_not_detected_feminine)
            DBTUNE_I18N_MESSAGE='nezistena'
            ;;
        en:audit_value_not_detected_masculine)
            DBTUNE_I18N_MESSAGE='not detected'
            ;;
        sk:audit_value_not_detected_masculine)
            DBTUNE_I18N_MESSAGE='nezisteny'
            ;;
        en:audit_value_not_available_feminine)
            DBTUNE_I18N_MESSAGE='not available'
            ;;
        sk:audit_value_not_available_feminine)
            DBTUNE_I18N_MESSAGE='nedostupna'
            ;;
        en:audit_summary_status)
            DBTUNE_I18N_MESSAGE='DBTune audit status: %s.\n'
            ;;
        sk:audit_summary_status)
            DBTUNE_I18N_MESSAGE='DBTune audit status: %s.\n'
            ;;
        en:audit_summary_sections)
            DBTUNE_I18N_MESSAGE='Required sections: %s. Failed: %s. Partial: %s.\n'
            ;;
        sk:audit_summary_sections)
            DBTUNE_I18N_MESSAGE='Povinne sekcie: %s. Zlyhane: %s. Ciastocne: %s.\n'
            ;;
        en:audit_summary_domains)
            DBTUNE_I18N_MESSAGE='Affected recommendation domains: %s.\n'
            ;;
        sk:audit_summary_domains)
            DBTUNE_I18N_MESSAGE='Ovplyvnene domeny odporucani: %s.\n'
            ;;
        en:audit_summary_evidence)
            DBTUNE_I18N_MESSAGE='MariaDB evidence: missing=%s; invalid=%s; conflicting=%s; optional=%s.\n'
            ;;
        sk:audit_summary_evidence)
            DBTUNE_I18N_MESSAGE='MariaDB dokazy: chybajuce=%s; neplatne=%s; konfliktne=%s; volitelne=%s.\n'
            ;;
        en:audit_summary_server)
            DBTUNE_I18N_MESSAGE='Server: %s CPU, %s RAM, storage %s.\n'
            ;;
        sk:audit_summary_server)
            DBTUNE_I18N_MESSAGE='Server: %s CPU, %s RAM, ulozisko %s.\n'
            ;;
        en:audit_summary_mariadb)
            DBTUNE_I18N_MESSAGE='MariaDB: %s, dataset %s, databases %s.\n'
            ;;
        sk:audit_summary_mariadb)
            DBTUNE_I18N_MESSAGE='MariaDB: %s, dataset %s, databazy %s.\n'
            ;;
        en:audit_summary_applications)
            DBTUNE_I18N_MESSAGE='Applications: %s. Total findings: %s, critical: %s, warnings: %s.\n'
            ;;
        sk:audit_summary_applications)
            DBTUNE_I18N_MESSAGE='Aplikacie: %s. Nalezy spolu: %s, kriticke: %s, varovania: %s.\n'
            ;;
        en:audit_summary_data)
            DBTUNE_I18N_MESSAGE='Data: %s/{audit,apps,databases}.tsv\n'
            ;;
        sk:audit_summary_data)
            DBTUNE_I18N_MESSAGE='Data: %s/{audit,apps,databases}.tsv\n'
            ;;
        en:collect_label_collector_lock)
            DBTUNE_I18N_MESSAGE='Collector lock'
            ;;
        sk:collect_label_collector_lock)
            DBTUNE_I18N_MESSAGE='Collector zamok'
            ;;
        en:collect_usage)
            DBTUNE_I18N_MESSAGE=$'Usage:\n  dbtune collect start [--days N] [--long-query-time SECONDS]\n  dbtune collect status\n  dbtune collect stop\n'
            ;;
        sk:collect_usage)
            DBTUNE_I18N_MESSAGE=$'Pouzitie:\n  dbtune collect start [--days N] [--long-query-time SEKUNDY]\n  dbtune collect status\n  dbtune collect stop\n'
            ;;
        en:collect_long_query_nonnegative)
            DBTUNE_I18N_MESSAGE='--long-query-time must be a non-negative number'
            ;;
        sk:collect_long_query_nonnegative)
            DBTUNE_I18N_MESSAGE='--long-query-time musi byt nezaporne cislo'
            ;;
        en:collect_long_query_range)
            DBTUNE_I18N_MESSAGE='--long-query-time must be in the range 0 to 3600'
            ;;
        sk:collect_long_query_range)
            DBTUNE_I18N_MESSAGE='--long-query-time musi byt v rozsahu 0 az 3600'
            ;;
        en:collect_assets_missing)
            DBTUNE_I18N_MESSAGE='Build does not contain embedded systemd assets'
            ;;
        sk:collect_assets_missing)
            DBTUNE_I18N_MESSAGE='Build neobsahuje embedded systemd assety'
            ;;
        en:collect_program_path_invalid)
            DBTUNE_I18N_MESSAGE='DBTUNE_PROGRAM_PATH must be an absolute path without spaces'
            ;;
        sk:collect_program_path_invalid)
            DBTUNE_I18N_MESSAGE='DBTUNE_PROGRAM_PATH musi byt absolutna cesta bez medzier'
            ;;
        en:collect_days_value_required)
            DBTUNE_I18N_MESSAGE='--days requires a value'
            ;;
        sk:collect_days_value_required)
            DBTUNE_I18N_MESSAGE='--days vyzaduje hodnotu'
            ;;
        en:collect_long_query_value_required)
            DBTUNE_I18N_MESSAGE='--long-query-time requires a value'
            ;;
        sk:collect_long_query_value_required)
            DBTUNE_I18N_MESSAGE='--long-query-time vyzaduje hodnotu'
            ;;
        en:collect_unknown_start_option)
            DBTUNE_I18N_MESSAGE='Unknown collect start option: %s'
            ;;
        sk:collect_unknown_start_option)
            DBTUNE_I18N_MESSAGE='Neznama collect start volba: %s'
            ;;
        en:collect_original_slow_invalid)
            DBTUNE_I18N_MESSAGE='MariaDB returned an invalid original slow log state'
            ;;
        sk:collect_original_slow_invalid)
            DBTUNE_I18N_MESSAGE='MariaDB vratila neplatny povodny stav slow logu'
            ;;
        en:collect_original_slow_missing)
            DBTUNE_I18N_MESSAGE='MariaDB did not return the original slow-log values'
            ;;
        sk:collect_original_slow_missing)
            DBTUNE_I18N_MESSAGE='MariaDB nevratila povodne slow-log hodnoty'
            ;;
        en:collect_current_epoch_label)
            DBTUNE_I18N_MESSAGE='current epoch'
            ;;
        sk:collect_current_epoch_label)
            DBTUNE_I18N_MESSAGE='aktualny epoch'
            ;;
        en:collect_start_failed)
            DBTUNE_I18N_MESSAGE='Collection failed to start before timer activation'
            ;;
        sk:collect_start_failed)
            DBTUNE_I18N_MESSAGE='Spustenie collect zlyhalo pred aktivaciou timeru'
            ;;
        en:collect_started)
            DBTUNE_I18N_MESSAGE='Collection started for %s days (deadline epoch %s).\n'
            ;;
        sk:collect_started)
            DBTUNE_I18N_MESSAGE='Zber spusteny na %s dni (deadline epoch %s).\n'
            ;;
        en:collect_restore_failed)
            DBTUNE_I18N_MESSAGE='Failed to restore the original runtime slow-log values'
            ;;
        sk:collect_restore_failed)
            DBTUNE_I18N_MESSAGE='Nepodarilo sa obnovit povodne runtime slow-log hodnoty'
            ;;
        en:collect_stopped)
            DBTUNE_I18N_MESSAGE='Collection stopped.\n'
            ;;
        sk:collect_stopped)
            DBTUNE_I18N_MESSAGE='Zber zastaveny.\n'
            ;;
        en:collect_watchdog_stopped)
            DBTUNE_I18N_MESSAGE='Collection watchdog stopped collection: %s'
            ;;
        sk:collect_watchdog_stopped)
            DBTUNE_I18N_MESSAGE='Collect watchdog ukoncil zber: %s'
            ;;
        en:collect_sample_header_unsupported)
            DBTUNE_I18N_MESSAGE='samples.tsv has an unsupported header'
            ;;
        sk:collect_sample_header_unsupported)
            DBTUNE_I18N_MESSAGE='samples.tsv ma nepodporovanu hlavicku'
            ;;
        en:collect_auto_stop_failed)
            DBTUNE_I18N_MESSAGE='Automatic collection stop failed'
            ;;
        sk:collect_auto_stop_failed)
            DBTUNE_I18N_MESSAGE='Automaticke zastavenie collect zlyhalo'
            ;;
        en:collect_auto_analyze_failed)
            DBTUNE_I18N_MESSAGE='Automatic analyze phase failed or is unavailable'
            ;;
        sk:collect_auto_analyze_failed)
            DBTUNE_I18N_MESSAGE='Automaticka analyze faza zlyhala alebo nie je dostupna'
            ;;
        en:collect_auto_report_failed)
            DBTUNE_I18N_MESSAGE='Automatic report phase failed or is unavailable'
            ;;
        sk:collect_auto_report_failed)
            DBTUNE_I18N_MESSAGE='Automaticka report faza zlyhala alebo nie je dostupna'
            ;;
        en:collect_tick_arguments_ignored)
            DBTUNE_I18N_MESSAGE='_tick ignores arguments'
            ;;
        sk:collect_tick_arguments_ignored)
            DBTUNE_I18N_MESSAGE='_tick ignoruje argumenty'
            ;;
        en:analysis_old_schema)
            DBTUNE_I18N_MESSAGE='analysis.tsv uses the pre-v0.4.0 reason_sk schema; start a new v0.4.0 audit and measurement cycle'
            ;;
        sk:analysis_old_schema)
            DBTUNE_I18N_MESSAGE='analysis.tsv používa starú schému reason_sk; spustite nový auditný a merací cyklus v0.4.0'
            ;;
        en:analysis_invalid_header)
            DBTUNE_I18N_MESSAGE='analysis.tsv does not have the expected eight-column reason_id header'
            ;;
        sk:analysis_invalid_header)
            DBTUNE_I18N_MESSAGE='analysis.tsv nemá očakávanú osemstĺpcovú hlavičku reason_id'
            ;;
        en:analysis_invalid_record)
            DBTUNE_I18N_MESSAGE='Invalid analysis.tsv record; exactly eight fields, a supported verdict token, and a catalog reason_id are required'
            ;;
        sk:analysis_invalid_record)
            DBTUNE_I18N_MESSAGE='Neplatný analysis.tsv záznam; vyžaduje sa presne osem polí, podporovaný verdict token a katalógový reason_id'
            ;;
        en:analysis_empty)
            DBTUNE_I18N_MESSAGE='analysis.tsv is empty'
            ;;
        sk:analysis_empty)
            DBTUNE_I18N_MESSAGE='analysis.tsv je prázdny'
            ;;
        en:reason_buffer_pool_current_missing)
            DBTUNE_I18N_MESSAGE='The effective buffer pool value is missing; a change must not be proposed blindly.'
            ;;
        sk:reason_buffer_pool_current_missing)
            DBTUNE_I18N_MESSAGE='Chýba efektívna hodnota buffer poolu; zmena sa nesmie navrhnúť naslepo.'
            ;;
        en:reason_buffer_pool_inputs_missing)
            DBTUNE_I18N_MESSAGE='Inputs required for a safe buffer pool calculation are missing.'
            ;;
        sk:reason_buffer_pool_inputs_missing)
            DBTUNE_I18N_MESSAGE='Chýbajú dáta pre bezpečný výpočet buffer poolu.'
            ;;
        en:reason_buffer_pool_no_shrink)
            DBTUNE_I18N_MESSAGE='The existing pool is not reduced automatically because shrinking is disruptive.'
            ;;
        sk:reason_buffer_pool_no_shrink)
            DBTUNE_I18N_MESSAGE='Existujúci pool sa automaticky nezmenšuje; zmenšovanie je rušivá operácia.'
            ;;
        en:reason_buffer_pool_memory_guard)
            DBTUNE_I18N_MESSAGE='The MemAvailable guard does not permit a safe pool increase.'
            ;;
        sk:reason_buffer_pool_memory_guard)
            DBTUNE_I18N_MESSAGE='MemAvailable guard nedovoľuje bezpečne zvýšiť pool.'
            ;;
        en:reason_buffer_pool_change)
            DBTUNE_I18N_MESSAGE='The pool is min((dataset plus positive six-month growth) times 1.3, RAM times 0.5), constrained by MemAvailable and rounded to 256M.'
            ;;
        sk:reason_buffer_pool_change)
            DBTUNE_I18N_MESSAGE='Pool je min((dataset plus kladný šesťmesačný rast) krát 1,3; RAM krát 0,5), s MemAvailable guardom a zaokrúhlením na 256M.'
            ;;
        en:reason_buffer_pool_growth_discontinuity)
            DBTUNE_I18N_MESSAGE='A jump above the adaptive 25 percent threshold, at least 1 GiB, resembles an import or discontinuity and is excluded from growth projection.'
            ;;
        sk:reason_buffer_pool_growth_discontinuity)
            DBTUNE_I18N_MESSAGE='Skok nad adaptívny prah 25 percent, minimálne 1 GiB, vyzerá ako import alebo diskontinuita a je vylúčený z projekcie rastu.'
            ;;
        en:reason_max_connections_worker_limit_missing)
            DBTUNE_I18N_MESSAGE='Without an authoritative PHP-FPM or OLS worker limit, max_connections must not be estimated even with a low peak.'
            ;;
        sk:reason_max_connections_worker_limit_missing)
            DBTUNE_I18N_MESSAGE='Bez autoritatívneho limitu PHP-FPM alebo OLS workerov sa max_connections nesmie odhadovať ani pri nízkom peaku.'
            ;;
        en:reason_max_connections_current_missing)
            DBTUNE_I18N_MESSAGE='The effective max_connections value is missing; a change must not be proposed blindly.'
            ;;
        sk:reason_max_connections_current_missing)
            DBTUNE_I18N_MESSAGE='Chýba efektívna hodnota max_connections; zmena sa nesmie navrhnúť naslepo.'
            ;;
        en:reason_max_connections_ok)
            DBTUNE_I18N_MESSAGE='The limit covers PHP-FPM and a 25 percent reserve above the measured peak.'
            ;;
        sk:reason_max_connections_ok)
            DBTUNE_I18N_MESSAGE='Limit pokrýva PHP-FPM aj 25-percentnú rezervu nad nameraným peakom.'
            ;;
        en:reason_max_connections_change)
            DBTUNE_I18N_MESSAGE='The larger of the PHP-FPM formula and a 25 percent reserve above the measured peak is used.'
            ;;
        sk:reason_max_connections_change)
            DBTUNE_I18N_MESSAGE='Používa sa väčšia hodnota zo vzorca PHP-FPM a 25-percentnej rezervy nad reálnym peakom.'
            ;;
        en:reason_storage_class_unknown)
            DBTUNE_I18N_MESSAGE='I/O capacities must not be guessed without a storage class.'
            ;;
        sk:reason_storage_class_unknown)
            DBTUNE_I18N_MESSAGE='Bez triedy úložiska sa I/O kapacity nesmú hádať.'
            ;;
        en:reason_io_capacity)
            DBTUNE_I18N_MESSAGE='I/O capacity matches the storage class.'
            ;;
        sk:reason_io_capacity)
            DBTUNE_I18N_MESSAGE='I/O kapacita zodpovedá triede úložiska.'
            ;;
        en:reason_io_capacity_max)
            DBTUNE_I18N_MESSAGE='Peak I/O capacity matches the storage class.'
            ;;
        sk:reason_io_capacity_max)
            DBTUNE_I18N_MESSAGE='Špičková I/O kapacita zodpovedá triede úložiska.'
            ;;
        en:reason_io_threads)
            DBTUNE_I18N_MESSAGE='NVMe uses eight I/O threads; other storage classes use four.'
            ;;
        sk:reason_io_threads)
            DBTUNE_I18N_MESSAGE='NVMe používa osem I/O vlákien, ostatné úložiská štyri.'
            ;;
        en:reason_flush_neighbors)
            DBTUNE_I18N_MESSAGE='Flushing neighboring pages is useful only on rotational storage.'
            ;;
        sk:reason_flush_neighbors)
            DBTUNE_I18N_MESSAGE='Susedné stránky sa oplatí flushovať iba na rotačnom disku.'
            ;;
        en:reason_query_cache_insufficient_active_windows)
            DBTUNE_I18N_MESSAGE='Query cache has too few active windows with nonzero queries; idle windows are excluded from the hit-rate percentile.'
            ;;
        sk:reason_query_cache_insufficient_active_windows)
            DBTUNE_I18N_MESSAGE='Query cache nemá dosť aktívnych okien s nenulovým počtom query; idle okná sa do hit-rate percentilu nerátajú.'
            ;;
        en:reason_query_cache_disable)
            DBTUNE_I18N_MESSAGE='Query cache is disabled when hit rate is below 20 percent or p95 Threads_running is above 8.'
            ;;
        sk:reason_query_cache_disable)
            DBTUNE_I18N_MESSAGE='Query cache sa vypína pri hit rate pod 20 percent alebo p95 Threads_running nad 8.'
            ;;
        en:reason_query_cache_memory_release)
            DBTUNE_I18N_MESSAGE='Disabling query cache also releases its memory.'
            ;;
        sk:reason_query_cache_memory_release)
            DBTUNE_I18N_MESSAGE='Pri vypnutom query cache sa uvoľní aj jeho pamäť.'
            ;;
        en:reason_query_cache_keep)
            DBTUNE_I18N_MESSAGE='A hit rate of at least 20 percent and p95 Threads_running no greater than 8 support keeping query cache.'
            ;;
        sk:reason_query_cache_keep)
            DBTUNE_I18N_MESSAGE='Hit rate aspoň 20 percent a p95 Threads_running najviac 8 podporujú ponechanie query cache.'
            ;;
        en:reason_version_unsupported)
            DBTUNE_I18N_MESSAGE='Supported MariaDB families are 10.6, 10.11, and 11.x.'
            ;;
        sk:reason_version_unsupported)
            DBTUNE_I18N_MESSAGE='Podporované sú MariaDB 10.6, 10.11 a 11.x.'
            ;;
        en:reason_variable_removed_startup)
            DBTUNE_I18N_MESSAGE='The variable was removed in MariaDB 11 and can prevent the next start.'
            ;;
        sk:reason_variable_removed_startup)
            DBTUNE_I18N_MESSAGE='Premenná je od MariaDB 11 odstránená a môže zablokovať ďalší štart.'
            ;;
        en:reason_variable_removed_config)
            DBTUNE_I18N_MESSAGE='The removed variable must be deleted from configuration before restart.'
            ;;
        sk:reason_variable_removed_config)
            DBTUNE_I18N_MESSAGE='Odstránená premenná musí byť vymazaná z konfigurácie pred reštartom.'
            ;;
        en:reason_flush_method_deprecated)
            DBTUNE_I18N_MESSAGE='flush_method is deprecated in MariaDB 11.x; review the existing value and do not add a new one blindly.'
            ;;
        sk:reason_flush_method_deprecated)
            DBTUNE_I18N_MESSAGE='V MariaDB 11.x je flush_method deprecated; existujúcu hodnotu overte a nepridávajte novú naslepo.'
            ;;
        en:reason_doublewrite)
            DBTUNE_I18N_MESSAGE='Doublewrite protects pages from torn writes.'
            ;;
        sk:reason_doublewrite)
            DBTUNE_I18N_MESSAGE='Doublewrite chráni stránky pri torn write.'
            ;;
        en:reason_o_direct)
            DBTUNE_I18N_MESSAGE='O_DIRECT limits double caching of data.'
            ;;
        sk:reason_o_direct)
            DBTUNE_I18N_MESSAGE='O_DIRECT obmedzí dvojité cachovanie dát.'
            ;;
        en:reason_buffer_pool_warmup)
            DBTUNE_I18N_MESSAGE='Dumping and loading the pool shortens warm-up after restart.'
            ;;
        sk:reason_buffer_pool_warmup)
            DBTUNE_I18N_MESSAGE='Dump a load poolu skracuje warm-up po reštarte.'
            ;;
        en:reason_dirty_pages_limit)
            DBTUNE_I18N_MESSAGE='The dirty-page limit reduces burst flushing.'
            ;;
        sk:reason_dirty_pages_limit)
            DBTUNE_I18N_MESSAGE='Limit špinavých stránok obmedzuje nárazový flush.'
            ;;
        en:reason_dirty_pages_lwm)
            DBTUNE_I18N_MESSAGE='The low-water mark starts continuous flushing earlier.'
            ;;
        sk:reason_dirty_pages_lwm)
            DBTUNE_I18N_MESSAGE='Low-water mark spustí priebežný flush skôr.'
            ;;
        en:reason_lock_wait_timeout)
            DBTUNE_I18N_MESSAGE='A shorter timeout avoids blocking PHP-FPM workers for 200 seconds.'
            ;;
        sk:reason_lock_wait_timeout)
            DBTUNE_I18N_MESSAGE='Kratší timeout neblokuje PHP-FPM workery 200 sekúnd.'
            ;;
        en:reason_skip_name_resolve)
            DBTUNE_I18N_MESSAGE='Local applications do not need reverse DNS.'
            ;;
        sk:reason_skip_name_resolve)
            DBTUNE_I18N_MESSAGE='Lokálne aplikácie nepotrebujú reverzné DNS.'
            ;;
        en:reason_thread_cache)
            DBTUNE_I18N_MESSAGE='The cache reduces thread creation cost.'
            ;;
        sk:reason_thread_cache)
            DBTUNE_I18N_MESSAGE='Cache obmedzí cenu vytvárania vlákien.'
            ;;
        en:reason_tmp_table_size)
            DBTUNE_I18N_MESSAGE='64M helps tables without BLOB/TEXT, while LONGTEXT remains disk-backed.'
            ;;
        sk:reason_tmp_table_size)
            DBTUNE_I18N_MESSAGE='64M pomôže tabuľkám bez BLOB/TEXT, ale LONGTEXT zostane na disku.'
            ;;
        en:reason_max_heap_table_size)
            DBTUNE_I18N_MESSAGE='The limit must match tmp_table_size.'
            ;;
        sk:reason_max_heap_table_size)
            DBTUNE_I18N_MESSAGE='Limit musí zodpovedať tmp_table_size.'
            ;;
        en:reason_table_definition_cache)
            DBTUNE_I18N_MESSAGE='Multiple WordPress databases need additional table-definition capacity.'
            ;;
        sk:reason_table_definition_cache)
            DBTUNE_I18N_MESSAGE='Viac WordPress databáz potrebuje rezervu definícií tabuliek.'
            ;;
        en:reason_myisam_keep)
            DBTUNE_I18N_MESSAGE='MyISAM is in use, so key buffer must not be reduced globally.'
            ;;
        sk:reason_myisam_keep)
            DBTUNE_I18N_MESSAGE='MyISAM sa používa, key buffer sa nesmie plošne zmenšiť.'
            ;;
        en:reason_myisam_key_buffer)
            DBTUNE_I18N_MESSAGE='Modern WordPress normally does not use MyISAM.'
            ;;
        sk:reason_myisam_key_buffer)
            DBTUNE_I18N_MESSAGE='Moderný WordPress MyISAM bežne nepoužíva.'
            ;;
        en:reason_slow_query_log)
            DBTUNE_I18N_MESSAGE='A persistent slow log is an early diagnostic signal.'
            ;;
        sk:reason_slow_query_log)
            DBTUNE_I18N_MESSAGE='Trvalý slow log je včasný diagnostický signál.'
            ;;
        en:reason_slow_query_log_file)
            DBTUNE_I18N_MESSAGE='The /var/log/mysql path is covered by MariaDB logrotate.'
            ;;
        sk:reason_slow_query_log_file)
            DBTUNE_I18N_MESSAGE='Cesta /var/log/mysql je pokrytá MariaDB logrotate.'
            ;;
        en:reason_long_query_time)
            DBTUNE_I18N_MESSAGE='Two seconds is a safe persistent production threshold.'
            ;;
        sk:reason_long_query_time)
            DBTUNE_I18N_MESSAGE='Dve sekundy sú bezpečný trvalý produkčný prah.'
            ;;
        en:reason_log_slow_verbosity)
            DBTUNE_I18N_MESSAGE='query_plan preserves useful detail without EXPLAIN output.'
            ;;
        sk:reason_log_slow_verbosity)
            DBTUNE_I18N_MESSAGE='query_plan zachová užitočný detail bez EXPLAIN výstupu.'
            ;;
        en:reason_unattended_upgrade_action)
            DBTUNE_I18N_MESSAGE='Disable automatic MariaDB restarts and schedule security updates manually.'
            ;;
        sk:reason_unattended_upgrade_action)
            DBTUNE_I18N_MESSAGE='Zakážte automatický reštart MariaDB a bezpečnostné aktualizácie plánujte ručne.'
            ;;
        en:reason_unattended_upgrade_ok)
            DBTUNE_I18N_MESSAGE='No uncontrolled automatic MariaDB upgrade was found.'
            ;;
        sk:reason_unattended_upgrade_ok)
            DBTUNE_I18N_MESSAGE='Nenašiel sa nekontrolovaný automatický MariaDB upgrade.'
            ;;
        en:reason_open_files_systemd_limit)
            DBTUNE_I18N_MESSAGE='open_files_limit is managed by a systemd drop-in, not MariaDB cnf.'
            ;;
        sk:reason_open_files_systemd_limit)
            DBTUNE_I18N_MESSAGE='open_files_limit sa rieši systemd drop-inom, nie MariaDB cnf.'
            ;;
        en:reason_open_files_ok)
            DBTUNE_I18N_MESSAGE='The effective open-files limit is not evidently capped.'
            ;;
        sk:reason_open_files_ok)
            DBTUNE_I18N_MESSAGE='Efektívny open-files limit nie je zjavne zrezaný.'
            ;;
        en:reason_security_exposed)
            DBTUNE_I18N_MESSAGE='If no external database client is required, restrict the listener and grants to localhost.'
            ;;
        sk:reason_security_exposed)
            DBTUNE_I18N_MESSAGE='Ak nie je potrebný externý DB klient, obmedzte listener a granty na localhost.'
            ;;
        en:reason_security_ok)
            DBTUNE_I18N_MESSAGE='The audit found no public listener or remote grant.'
            ;;
        sk:reason_security_ok)
            DBTUNE_I18N_MESSAGE='Audit nenašiel verejný listener ani vzdialený grant.'
            ;;
        en:reason_root_cnf_credential)
            DBTUNE_I18N_MESSAGE='Never print the root.cnf password; rotate it simultaneously in MariaDB and the RunCloud file.'
            ;;
        sk:reason_root_cnf_credential)
            DBTUNE_I18N_MESSAGE='Heslo z root.cnf nikdy nevypisujte; pri rotácii ho zmeňte naraz v MariaDB aj v RunCloud súbore.'
            ;;
        en:reason_backup_missing)
            DBTUNE_I18N_MESSAGE='Confirmed absence of a backup blocks tuning.'
            ;;
        sk:reason_backup_missing)
            DBTUNE_I18N_MESSAGE='Potvrdená absencia zálohy blokuje tuning.'
            ;;
        en:reason_backup_unknown)
            DBTUNE_I18N_MESSAGE='Backup status is not authoritatively verified; the number of local schedules alone does not confirm a backup.'
            ;;
        sk:reason_backup_unknown)
            DBTUNE_I18N_MESSAGE='Stav zálohy nie je autoritatívne overený; počet lokálnych plánov sám osebe zálohu nepotvrdzuje.'
            ;;
        en:reason_backup_frequent)
            DBTUNE_I18N_MESSAGE='Frequent full mydumper scans can create I/O spikes; verify the actual requirement.'
            ;;
        sk:reason_backup_frequent)
            DBTUNE_I18N_MESSAGE='Častý mydumper full scan môže vytvárať I/O špičky; overte reálnu potrebu.'
            ;;
        en:reason_backup_verified)
            DBTUNE_I18N_MESSAGE='The backup is authoritatively verified.'
            ;;
        sk:reason_backup_verified)
            DBTUNE_I18N_MESSAGE='Záloha je autoritatívne overená.'
            ;;
        en:reason_redo_file_size)
            DBTUNE_I18N_MESSAGE='Datasets above 10G use a 1G redo file; smaller datasets use 512M.'
            ;;
        sk:reason_redo_file_size)
            DBTUNE_I18N_MESSAGE='Dataset nad 10G používa 1G redo súbor, menší dataset 512M.'
            ;;
        en:reason_log_buffer_size)
            DBTUNE_I18N_MESSAGE='64M is justified only by growth in Innodb_log_waits.'
            ;;
        sk:reason_log_buffer_size)
            DBTUNE_I18N_MESSAGE='64M je odôvodnené iba rastom Innodb_log_waits.'
            ;;
        en:reason_trx_commit_without_binlog)
            DBTUNE_I18N_MESSAGE='Without binary logging, redo is the only protection for confirmed orders.'
            ;;
        sk:reason_trx_commit_without_binlog)
            DBTUNE_I18N_MESSAGE='Bez binlogu je redo jediná ochrana potvrdených objednávok.'
            ;;
        en:reason_trx_commit_with_binlog)
            DBTUNE_I18N_MESSAGE='With binary logging enabled, assess durability together with sync_binlog and the PITR policy.'
            ;;
        sk:reason_trx_commit_with_binlog)
            DBTUNE_I18N_MESSAGE='Pri zapnutom binlogu posúďte durability spolu so sync_binlog a PITR politikou.'
            ;;
        en:reason_app_source_unavailable)
            DBTUNE_I18N_MESSAGE='Source audit data for this rule is unavailable; the finding must not be treated as healthy or empty.'
            ;;
        sk:reason_app_source_unavailable)
            DBTUNE_I18N_MESSAGE='Zdrojové auditné dáta pre toto pravidlo nie sú dostupné; nález sa nesmie vyhodnotiť ako zdravý ani prázdny.'
            ;;
        en:reason_multisite_unknown)
            DBTUNE_I18N_MESSAGE='Multisite prefixes were not enumerated; application database metrics must not be treated as healthy.'
            ;;
        sk:reason_multisite_unknown)
            DBTUNE_I18N_MESSAGE='Multisite prefixy neboli enumerované; aplikačné DB metriky sa nesmú hodnotiť ako zdravé.'
            ;;
        en:reason_object_cache_ok)
            DBTUNE_I18N_MESSAGE='Persistent object cache has both a drop-in and a successful Redis probe.'
            ;;
        sk:reason_object_cache_ok)
            DBTUNE_I18N_MESSAGE='Persistent object cache má drop-in aj úspešný Redis probe.'
            ;;
        en:reason_redis_down)
            DBTUNE_I18N_MESSAGE='Redis probe failed; fix the application layer before database tuning.'
            ;;
        sk:reason_redis_down)
            DBTUNE_I18N_MESSAGE='Redis probe zlyhal; aplikačnú vrstvu rieš pred DB tuningom.'
            ;;
        en:reason_object_cache_dropin_missing)
            DBTUNE_I18N_MESSAGE='Redis alone is insufficient; WordPress needs the wp-content/object-cache.php drop-in.'
            ;;
        sk:reason_object_cache_dropin_missing)
            DBTUNE_I18N_MESSAGE='Redis sám nestačí; WordPress potrebuje wp-content/object-cache.php drop-in.'
            ;;
        en:reason_object_cache_unknown)
            DBTUNE_I18N_MESSAGE='Both the drop-in and Redis probe must be confirmed; an unknown state is not healthy.'
            ;;
        sk:reason_object_cache_unknown)
            DBTUNE_I18N_MESSAGE='Drop-in aj Redis probe musia byť potvrdené; neznámy stav nie je zdravý stav.'
            ;;
        en:reason_wp_cron_disabled)
            DBTUNE_I18N_MESSAGE='WP-Cron is not running, endangering orders and Action Scheduler.'
            ;;
        sk:reason_wp_cron_disabled)
            DBTUNE_I18N_MESSAGE='WP-Cron nebeží, čo ohrozuje objednávky a Action Scheduler.'
            ;;
        en:reason_wp_cron_mapping_unknown)
            DBTUNE_I18N_MESSAGE='A global cron is not evidence for this application; map the URL or webroot of its wp-cron run.'
            ;;
        sk:reason_wp_cron_mapping_unknown)
            DBTUNE_I18N_MESSAGE='Globálny cron nie je dôkaz pre túto aplikáciu; namapujte URL alebo webroot konkrétneho wp-cron behu.'
            ;;
        en:reason_autoload_too_large)
            DBTUNE_I18N_MESSAGE='Prioritize autoload above 3 MB and inspect the top 20 options.'
            ;;
        sk:reason_autoload_too_large)
            DBTUNE_I18N_MESSAGE='Autoload nad 3 MB riešte prioritne a skontrolujte top 20 options.'
            ;;
        en:reason_autoload_review)
            DBTUNE_I18N_MESSAGE='Autoload from 1 to 3 MB requires review of the largest options.'
            ;;
        sk:reason_autoload_review)
            DBTUNE_I18N_MESSAGE='Autoload 1 až 3 MB vyžaduje kontrolu najväčších options.'
            ;;
        en:reason_autoload_ok)
            DBTUNE_I18N_MESSAGE='Autoload is below 1 MB.'
            ;;
        sk:reason_autoload_ok)
            DBTUNE_I18N_MESSAGE='Autoload je pod 1 MB.'
            ;;
        en:reason_hpos_migrate)
            DBTUNE_I18N_MESSAGE='Orders in posts/postmeta are candidates for a separate HPOS migration.'
            ;;
        sk:reason_hpos_migrate)
            DBTUNE_I18N_MESSAGE='Objednávky v posts/postmeta sú kandidátom na samostatnú HPOS migráciu.'
            ;;
        en:reason_hpos_duplicate_writes)
            DBTUNE_I18N_MESSAGE='After verifying migration, disable compatibility sync to avoid writing orders twice.'
            ;;
        sk:reason_hpos_duplicate_writes)
            DBTUNE_I18N_MESSAGE='Po overení migrácie vypnite kompatibilný sync, inak sa objednávky zapisujú dvakrát.'
            ;;
        en:reason_log_table_payloads)
            DBTUNE_I18N_MESSAGE='A log table above 20 KB per row probably stores complete payloads.'
            ;;
        sk:reason_log_table_payloads)
            DBTUNE_I18N_MESSAGE='Log tabuľka nad 20 KB na riadok pravdepodobne drží celé payloady.'
            ;;
        en:reason_sessions_cleanup)
            DBTUNE_I18N_MESSAGE='WooCommerce sessions become a concern around 500 thousand rows.'
            ;;
        sk:reason_sessions_cleanup)
            DBTUNE_I18N_MESSAGE='WooCommerce sessions sú problém približne od 500-tisíc riadkov.'
            ;;
        en:reason_action_scheduler_failed)
            DBTUNE_I18N_MESSAGE='Retention does not remove failed Action Scheduler actions; find the faulty plugin or hook.'
            ;;
        sk:reason_action_scheduler_failed)
            DBTUNE_I18N_MESSAGE='Zlyhané Action Scheduler akcie retention neodstráni; nájdite chybný plugin alebo hook.'
            ;;
        en:reason_action_scheduler_retention)
            DBTUNE_I18N_MESSAGE='Reduce completed-history retention to 7 days, not 1 day.'
            ;;
        sk:reason_action_scheduler_retention)
            DBTUNE_I18N_MESSAGE='Skráťte retention dokončenej histórie na 7 dní, nie na 1 deň.'
            ;;
        en:reason_transients_cleanup)
            DBTUNE_I18N_MESSAGE='Review a large volume of database transients and remove only expired records.'
            ;;
        sk:reason_transients_cleanup)
            DBTUNE_I18N_MESSAGE='Veľký objem DB transientov preverte a odstráňte iba expirované záznamy.'
            ;;
        en:reason_meta_value_index)
            DBTUNE_I18N_MESSAGE='A standalone meta_value index is large and poorly selective; verify usage before removal.'
            ;;
        sk:reason_meta_value_index)
            DBTUNE_I18N_MESSAGE='Samostatný index meta_value je veľký a málo selektívny; pred odstránením overte použitie.'
            ;;
        en:reason_redis_policy)
            DBTUNE_I18N_MESSAGE='Use volatile-lru for a store so memory pressure does not evict session data.'
            ;;
        sk:reason_redis_policy)
            DBTUNE_I18N_MESSAGE='Pre e-shop použite volatile-lru, aby tlak na pamäť nevyhadzoval session dáta.'
            ;;
        en:action_warning_read_only)
            DBTUNE_I18N_MESSAGE='Do not run DELETE, DROP, UPDATE, or automatic cleanup; review the result manually first.'
            ;;
        sk:action_warning_read_only)
            DBTUNE_I18N_MESSAGE='Nevykonávajte DELETE, DROP, UPDATE ani automatický cleanup; výsledok najprv ručne skontrolujte.'
            ;;
        en:action_warning_source_error)
            DBTUNE_I18N_MESSAGE='Non-executable diagnostic: the audit source failed, so no command was generated.'
            ;;
        sk:action_warning_source_error)
            DBTUNE_I18N_MESSAGE='Neexekvovateľná diagnostika: auditný zdroj zlyhal, preto príkaz nebol vygenerovaný.'
            ;;
        en:action_warning_sql_unavailable)
            DBTUNE_I18N_MESSAGE='Non-executable SQL diagnostic: statement-timeout capability or database mapping is unsafe, so no command was generated.'
            ;;
        sk:action_warning_sql_unavailable)
            DBTUNE_I18N_MESSAGE='Neexekvovateľná SQL diagnostika: statement-timeout capability alebo databázové mapovanie nie je bezpečné, preto príkaz nebol vygenerovaný.'
            ;;
        en:action_warning_wp_unavailable)
            DBTUNE_I18N_MESSAGE='Non-executable diagnostic: a verified WordPress webroot or owner is unavailable, so no command was generated.'
            ;;
        sk:action_warning_wp_unavailable)
            DBTUNE_I18N_MESSAGE='Neexekvovateľná diagnostika: overený WordPress webroot alebo vlastník nie je dostupný, preto príkaz nebol vygenerovaný.'
            ;;
        en:actions_warning_summary)
            DBTUNE_I18N_MESSAGE='Do not execute destructive SQL automatically; action steps are read-only diagnostics.'
            ;;
        sk:actions_warning_summary)
            DBTUNE_I18N_MESSAGE='Nevykonávajte deštruktívne SQL automaticky; action kroky sú iba read-only diagnostika.'
            ;;
        en:report_inventory_unavailable)
            DBTUNE_I18N_MESSAGE='_Data is unavailable._'
            ;;
        sk:report_inventory_unavailable)
            DBTUNE_I18N_MESSAGE='_Údaje nie sú dostupné._'
            ;;
        en:report_inventory_no_safe_values)
            DBTUNE_I18N_MESSAGE='_no safely displayable values_'
            ;;
        sk:report_inventory_no_safe_values)
            DBTUNE_I18N_MESSAGE='_bez bezpečne zobraziteľných hodnôt_'
            ;;
        en:report_inventory_record)
            DBTUNE_I18N_MESSAGE='- Record %s: %s\n'
            ;;
        sk:report_inventory_record)
            DBTUNE_I18N_MESSAGE='- Záznam %s: %s\n'
            ;;
        en:report_no_findings)
            DBTUNE_I18N_MESSAGE='- The analysis contains no findings.\n'
            ;;
        sk:report_no_findings)
            DBTUNE_I18N_MESSAGE='- Analýza neobsahuje žiadne nálezy.\n'
            ;;
        en:report_application_heading)
            DBTUNE_I18N_MESSAGE='## Application layer - FIX FIRST\n\n'
            ;;
        sk:report_application_heading)
            DBTUNE_I18N_MESSAGE='## Aplikačná vrstva - RIEŠ PRVÚ\n\n'
            ;;
        en:report_application_intro)
            DBTUNE_I18N_MESSAGE='Object cache removes queries; database tuning only makes them cheaper. Resolve application findings before applying the server proposal.\n\n'
            ;;
        sk:report_application_intro)
            DBTUNE_I18N_MESSAGE='Object cache odstráni dotazy; databázový tuning ich iba zlacní. Najprv vyriešte aplikačné nálezy, až potom aplikujte serverový návrh.\n\n'
            ;;
        en:report_application_table)
            DBTUNE_I18N_MESSAGE=$'| Severity | Application | Verdict | Reason |\n|---|---|---|---|\n'
            ;;
        sk:report_application_table)
            DBTUNE_I18N_MESSAGE=$'| Závažnosť | Aplikácia | Verdikt | Dôvod |\n|---|---|---|---|\n'
            ;;
        en:report_application_none)
            DBTUNE_I18N_MESSAGE='| info | - | No application findings | - |\n'
            ;;
        sk:report_application_none)
            DBTUNE_I18N_MESSAGE='| info | - | Bez aplikačných nálezov | - |\n'
            ;;
        en:report_server_heading)
            DBTUNE_I18N_MESSAGE='## Server, hardware, and workload profile\n\n'
            ;;
        sk:report_server_heading)
            DBTUNE_I18N_MESSAGE='## Server, hardvér a profil záťaže\n\n'
            ;;
        en:report_label_host)
            DBTUNE_I18N_MESSAGE='Host'
            ;;
        sk:report_label_host)
            DBTUNE_I18N_MESSAGE='Host'
            ;;
        en:report_label_mariadb)
            DBTUNE_I18N_MESSAGE='MariaDB'
            ;;
        sk:report_label_mariadb)
            DBTUNE_I18N_MESSAGE='MariaDB'
            ;;
        en:report_label_os)
            DBTUNE_I18N_MESSAGE='Operating system'
            ;;
        sk:report_label_os)
            DBTUNE_I18N_MESSAGE='Operačný systém'
            ;;
        en:report_label_cpu_cores)
            DBTUNE_I18N_MESSAGE='CPU cores'
            ;;
        sk:report_label_cpu_cores)
            DBTUNE_I18N_MESSAGE='CPU jadrá'
            ;;
        en:report_label_ram_bytes)
            DBTUNE_I18N_MESSAGE='RAM (bytes)'
            ;;
        sk:report_label_ram_bytes)
            DBTUNE_I18N_MESSAGE='RAM (bajty)'
            ;;
        en:report_label_disk)
            DBTUNE_I18N_MESSAGE='Disk'
            ;;
        sk:report_label_disk)
            DBTUNE_I18N_MESSAGE='Disk'
            ;;
        en:report_label_dataset_bytes)
            DBTUNE_I18N_MESSAGE='Dataset (bytes)'
            ;;
        sk:report_label_dataset_bytes)
            DBTUNE_I18N_MESSAGE='Dataset (bajty)'
            ;;
        en:report_valid_samples)
            DBTUNE_I18N_MESSAGE='- **Valid samples:** %s\n\n'
            ;;
        sk:report_valid_samples)
            DBTUNE_I18N_MESSAGE='- **Počet validných vzoriek:** %s\n\n'
            ;;
        en:report_rejected_samples)
            DBTUNE_I18N_MESSAGE='- **Rejected samples:** %s (%s)\n\n'
            ;;
        sk:report_rejected_samples)
            DBTUNE_I18N_MESSAGE='- **Odmietnuté vzorky:** %s (%s)\n\n'
            ;;
        en:report_percentiles_heading)
            DBTUNE_I18N_MESSAGE='### Short-window percentiles\n\n'
            ;;
        sk:report_percentiles_heading)
            DBTUNE_I18N_MESSAGE='### Percentily krátkych okien\n\n'
            ;;
        en:report_metrics_table)
            DBTUNE_I18N_MESSAGE=$'| Metric | p50 | p95 | p99 | Maximum |\n|---|---:|---:|---:|---:|\n'
            ;;
        sk:report_metrics_table)
            DBTUNE_I18N_MESSAGE=$'| Metrika | p50 | p95 | p99 | Maximum |\n|---|---:|---:|---:|---:|\n'
            ;;
        en:report_metric_mariadb_cpu)
            DBTUNE_I18N_MESSAGE='MariaDB CPU'
            ;;
        sk:report_metric_mariadb_cpu)
            DBTUNE_I18N_MESSAGE='MariaDB CPU'
            ;;
        en:report_metric_bp_hit)
            DBTUNE_I18N_MESSAGE='Buffer pool hit ratio'
            ;;
        sk:report_metric_bp_hit)
            DBTUNE_I18N_MESSAGE='Buffer pool hit ratio'
            ;;
        en:report_metric_bp_misses)
            DBTUNE_I18N_MESSAGE='Buffer pool misses/s'
            ;;
        sk:report_metric_bp_misses)
            DBTUNE_I18N_MESSAGE='Buffer pool missy/s'
            ;;
        en:report_metric_data_read)
            DBTUNE_I18N_MESSAGE='Data read/s'
            ;;
        sk:report_metric_data_read)
            DBTUNE_I18N_MESSAGE='Čítanie dát/s'
            ;;
        en:report_metric_rnd_next)
            DBTUNE_I18N_MESSAGE='Handler_read_rnd_next/s'
            ;;
        sk:report_metric_rnd_next)
            DBTUNE_I18N_MESSAGE='Handler_read_rnd_next/s'
            ;;
        en:report_metric_threads_running)
            DBTUNE_I18N_MESSAGE='Threads_running'
            ;;
        sk:report_metric_threads_running)
            DBTUNE_I18N_MESSAGE='Threads_running'
            ;;
        en:report_metric_disk_temp)
            DBTUNE_I18N_MESSAGE='Disk temporary tables'
            ;;
        sk:report_metric_disk_temp)
            DBTUNE_I18N_MESSAGE='Diskové temp tabuľky'
            ;;
        en:report_metric_available_ram)
            DBTUNE_I18N_MESSAGE='Available RAM'
            ;;
        sk:report_metric_available_ram)
            DBTUNE_I18N_MESSAGE='Dostupná RAM'
            ;;
        en:report_metric_swap)
            DBTUNE_I18N_MESSAGE='Swap used'
            ;;
        sk:report_metric_swap)
            DBTUNE_I18N_MESSAGE='Použitý swap'
            ;;
        en:report_worst_heading)
            DBTUNE_I18N_MESSAGE='\n### Worst windows\n\n'
            ;;
        sk:report_worst_heading)
            DBTUNE_I18N_MESSAGE='\n### Najhoršie okná\n\n'
            ;;
        en:report_worst_table)
            DBTUNE_I18N_MESSAGE=$'| Time | CPU %% | BP hit %% | Misses/s | Read B/s | Threads running | Backup correlation |\n|---|---:|---:|---:|---:|---:|---|\n'
            ;;
        sk:report_worst_table)
            DBTUNE_I18N_MESSAGE=$'| Čas | CPU %% | BP hit %% | Missy/s | Čítanie B/s | Threads running | Backup korelácia |\n|---|---:|---:|---:|---:|---:|---|\n'
            ;;
        en:report_proposal_heading)
            DBTUNE_I18N_MESSAGE='## Configuration proposal: current -> proposed value\n\n'
            ;;
        sk:report_proposal_heading)
            DBTUNE_I18N_MESSAGE='## Návrh konfigurácie: aktuálna -> navrhnutá hodnota\n\n'
            ;;
        en:report_proposal_table)
            DBTUNE_I18N_MESSAGE=$'| Key | Current value | Proposed value | Evidence | Reason |\n|---|---|---|---|---|\n'
            ;;
        sk:report_proposal_table)
            DBTUNE_I18N_MESSAGE=$'| Kľúč | Aktuálna hodnota | Navrhnutá hodnota | Evidencia | Odôvodnenie |\n|---|---|---|---|---|\n'
            ;;
        en:report_proposal_none)
            DBTUNE_I18N_MESSAGE='| - | - | - | The analysis proposed no server change. | - |\n'
            ;;
        sk:report_proposal_none)
            DBTUNE_I18N_MESSAGE='| - | - | - | Analýza nenavrhla žiadnu serverovú zmenu. | - |\n'
            ;;
        en:report_per_app_heading)
            DBTUNE_I18N_MESSAGE='## Per-application sections\n\n'
            ;;
        sk:report_per_app_heading)
            DBTUNE_I18N_MESSAGE='## Per-app sekcie\n\n'
            ;;
        en:report_per_app_table)
            DBTUNE_I18N_MESSAGE=$'| Severity | Verdict | Evidence | Recommendation | Safe action step |\n|---|---|---|---|---|\n'
            ;;
        sk:report_per_app_table)
            DBTUNE_I18N_MESSAGE=$'| Závažnosť | Verdikt | Evidencia | Odporúčanie | Bezpečný action krok |\n|---|---|---|---|---|\n'
            ;;
        en:report_autoload_heading)
            DBTUNE_I18N_MESSAGE='\n#### Top autoload entries (name and size only)\n\n'
            ;;
        sk:report_autoload_heading)
            DBTUNE_I18N_MESSAGE='\n#### Top autoload položky (iba názov a veľkosť)\n\n'
            ;;
        en:report_autoload_table)
            DBTUNE_I18N_MESSAGE=$'| Option | Bytes |\n|---|---:|\n'
            ;;
        sk:report_autoload_table)
            DBTUNE_I18N_MESSAGE=$'| Option | Bajty |\n|---|---:|\n'
            ;;
        en:report_autoload_unavailable)
            DBTUNE_I18N_MESSAGE='| - | Data is unavailable. |\n'
            ;;
        sk:report_autoload_unavailable)
            DBTUNE_I18N_MESSAGE='| - | Údaje nie sú dostupné. |\n'
            ;;
        en:report_per_app_none)
            DBTUNE_I18N_MESSAGE='_No per-application findings._\n\n'
            ;;
        sk:report_per_app_none)
            DBTUNE_I18N_MESSAGE='_Bez per-app nálezov._\n\n'
            ;;
        en:report_inventory_apps)
            DBTUNE_I18N_MESSAGE='Application inventory'
            ;;
        sk:report_inventory_apps)
            DBTUNE_I18N_MESSAGE='Inventár aplikácií'
            ;;
        en:report_inventory_databases)
            DBTUNE_I18N_MESSAGE='Databases'
            ;;
        sk:report_inventory_databases)
            DBTUNE_I18N_MESSAGE='Databázy'
            ;;
        en:report_security_heading)
            DBTUNE_I18N_MESSAGE='## Security findings\n\n'
            ;;
        sk:report_security_heading)
            DBTUNE_I18N_MESSAGE='## Bezpečnostné nálezy\n\n'
            ;;
        en:report_security_none)
            DBTUNE_I18N_MESSAGE='- No separate security findings in the analysis.\n'
            ;;
        sk:report_security_none)
            DBTUNE_I18N_MESSAGE='- Bez samostatných bezpečnostných nálezov v analýze.\n'
            ;;
        en:report_title)
            DBTUNE_I18N_MESSAGE='# dbtune report\n\n'
            ;;
        sk:report_title)
            DBTUNE_I18N_MESSAGE='# dbtune správa\n\n'
            ;;
        en:report_generated)
            DBTUNE_I18N_MESSAGE='_Generated: %s | dbtune %s_\n\n'
            ;;
        sk:report_generated)
            DBTUNE_I18N_MESSAGE='_Vygenerované: %s | dbtune %s_\n\n'
            ;;
        en:report_provenance)
            DBTUNE_I18N_MESSAGE="_Run: \`%s\` | fingerprint: \`%s\` | audit SHA-256: \`%s\` | samples SHA-256: \`%s\` | dbsize SHA-256: \`%s\`_\n\n"
            ;;
        sk:report_provenance)
            DBTUNE_I18N_MESSAGE="_Run: \`%s\` | fingerprint: \`%s\` | audit SHA-256: \`%s\` | samples SHA-256: \`%s\` | dbsize SHA-256: \`%s\`_\n\n"
            ;;
        en:report_unsupported)
            DBTUNE_I18N_MESSAGE='> **Unsupported MariaDB:** the server family was not explicitly approved. Server tuning recommendations and the configuration proposal are suppressed.\n\n'
            ;;
        sk:report_unsupported)
            DBTUNE_I18N_MESSAGE='> **Nepodporovaná MariaDB:** serverová rodina nebola explicitne schválená. Serverové tuning odporúčania a návrh konfigurácie sú potlačené.\n\n'
            ;;
        en:report_summary_heading)
            DBTUNE_I18N_MESSAGE='## Executive summary\n\n'
            ;;
        sk:report_summary_heading)
            DBTUNE_I18N_MESSAGE='## Manažérske zhrnutie\n\n'
            ;;
        en:report_audit_status)
            DBTUNE_I18N_MESSAGE='**Overall audit status:** %s.\n\n'
            ;;
        sk:report_audit_status)
            DBTUNE_I18N_MESSAGE='**Celkový stav auditu:** %s.\n\n'
            ;;
        en:report_required_sections)
            DBTUNE_I18N_MESSAGE='- **Required sections:** %s\n'
            ;;
        sk:report_required_sections)
            DBTUNE_I18N_MESSAGE='- **Povinné sekcie:** %s\n'
            ;;
        en:report_failed_sections)
            DBTUNE_I18N_MESSAGE='- **Failed sections:** %s\n'
            ;;
        sk:report_failed_sections)
            DBTUNE_I18N_MESSAGE='- **Zlyhané sekcie:** %s\n'
            ;;
        en:report_partial_sections)
            DBTUNE_I18N_MESSAGE='- **Partial sections:** %s\n'
            ;;
        sk:report_partial_sections)
            DBTUNE_I18N_MESSAGE='- **Čiastočné sekcie:** %s\n'
            ;;
        en:report_affected_domains)
            DBTUNE_I18N_MESSAGE='- **Affected recommendation domains:** %s\n\n'
            ;;
        sk:report_affected_domains)
            DBTUNE_I18N_MESSAGE='- **Ovplyvnené domény odporúčaní:** %s\n\n'
            ;;
        en:report_mariadb_missing)
            DBTUNE_I18N_MESSAGE='- **Missing MariaDB evidence:** %s\n'
            ;;
        sk:report_mariadb_missing)
            DBTUNE_I18N_MESSAGE='- **MariaDB chýbajúce dôkazy:** %s\n'
            ;;
        en:report_mariadb_invalid)
            DBTUNE_I18N_MESSAGE='- **Invalid MariaDB evidence:** %s\n'
            ;;
        sk:report_mariadb_invalid)
            DBTUNE_I18N_MESSAGE='- **MariaDB neplatné dôkazy:** %s\n'
            ;;
        en:report_mariadb_conflicting)
            DBTUNE_I18N_MESSAGE='- **Conflicting MariaDB evidence:** %s\n'
            ;;
        sk:report_mariadb_conflicting)
            DBTUNE_I18N_MESSAGE='- **MariaDB konfliktné dôkazy:** %s\n'
            ;;
        en:report_mariadb_optional)
            DBTUNE_I18N_MESSAGE='- **Optional MariaDB evidence:** %s\n\n'
            ;;
        sk:report_mariadb_optional)
            DBTUNE_I18N_MESSAGE='- **MariaDB voliteľné dôkazy:** %s\n\n'
            ;;
        en:report_findings)
            DBTUNE_I18N_MESSAGE='**Findings:** critical %s, high %s, medium %s, low %s.\n\n'
            ;;
        sk:report_findings)
            DBTUNE_I18N_MESSAGE='**Nálezy:** critical %s, high %s, medium %s, low %s.\n\n'
            ;;
        en:report_safety_warning)
            DBTUNE_I18N_MESSAGE='> **Safety warning:** action steps are read-only diagnostics. dbtune does not automatically run application SQL or cleanup; run destructive DELETE, DROP, or UPDATE only after separate review and a verified backup.\n\n'
            ;;
        sk:report_safety_warning)
            DBTUNE_I18N_MESSAGE='> **Bezpečnostné upozornenie:** action kroky sú iba read-only diagnostika. dbtune automaticky nespúšťa aplikačné SQL ani cleanup; deštruktívne DELETE, DROP a UPDATE vykonajte iba po samostatnom review a overenej zálohe.\n\n'
            ;;
        en:report_next_steps_heading)
            DBTUNE_I18N_MESSAGE='## Next steps\n\n'
            ;;
        sk:report_next_steps_heading)
            DBTUNE_I18N_MESSAGE='## Ďalší postup\n\n'
            ;;
        en:report_next_step_apps)
            DBTUNE_I18N_MESSAGE='1. Resolve application findings, especially object cache, autoload, HPOS, and wp-cron.\n'
            ;;
        sk:report_next_step_apps)
            DBTUNE_I18N_MESSAGE='1. Vyriešte aplikačné nálezy, najmä object cache, autoload, HPOS a wp-cron.\n'
            ;;
        en:report_next_step_unsupported)
            DBTUNE_I18N_MESSAGE='2. Do not use server tuning recommendations until this MariaDB family passes compatibility review.\n'
            ;;
        sk:report_next_step_unsupported)
            DBTUNE_I18N_MESSAGE='2. Nepoužívajte serverové tuning odporúčania, kým táto MariaDB rodina neprejde compatibility review.\n'
            ;;
        en:report_next_step_propose)
            DBTUNE_I18N_MESSAGE="2. Review the diff and create the gated server file with \`dbtune propose\`.\n"
            ;;
        sk:report_next_step_propose)
            DBTUNE_I18N_MESSAGE="2. Skontrolujte diff a vytvorte gated serverový súbor príkazom \`dbtune propose\`.\n"
            ;;
        en:report_next_step_restart)
            DBTUNE_I18N_MESSAGE='3. Validate variable names and configuration before restart; restart through the RunCloud panel.\n'
            ;;
        sk:report_next_step_restart)
            DBTUNE_I18N_MESSAGE='3. Pred reštartom validujte názvy premenných a konfiguráciu; reštart vykonajte cez RunCloud panel.\n'
            ;;
        en:report_next_step_verify)
            DBTUNE_I18N_MESSAGE="4. After restart, run \`dbtune verify --post\`, then \`dbtune verify --24h\` after 24 hours.\n"
            ;;
        sk:report_next_step_verify)
            DBTUNE_I18N_MESSAGE="4. Po reštarte spustite \`dbtune verify --post\` a po 24 hodinách \`dbtune verify --24h\`.\n"
            ;;
        en:report_saved)
            DBTUNE_I18N_MESSAGE='\nReport saved: %s\nJSON saved: %s\n'
            ;;
        sk:report_saved)
            DBTUNE_I18N_MESSAGE='\nReport uložený: %s\nJSON uložený: %s\n'
            ;;
        en:proposal_saved)
            DBTUNE_I18N_MESSAGE='Proposal saved: %s\n'
            ;;
        sk:proposal_saved)
            DBTUNE_I18N_MESSAGE='Návrh uložený: %s\n'
            ;;
        en:cnf_generated)
            DBTUNE_I18N_MESSAGE='# Generated by dbtune %s at %s.\n'
            ;;
        sk:cnf_generated)
            DBTUNE_I18N_MESSAGE='# Vygeneroval dbtune %s dňa %s.\n'
            ;;
        en:cnf_load_order)
            DBTUNE_I18N_MESSAGE='# Loaded after /etc/mysql/conf.d/runcloud.cnf.\n'
            ;;
        sk:cnf_load_order)
            DBTUNE_I18N_MESSAGE='# Načíta sa po /etc/mysql/conf.d/runcloud.cnf.\n'
            ;;
        en:cnf_rollback)
            DBTUNE_I18N_MESSAGE='# Rollback: remove deployed 99-zz-tuning.cnf and restart MariaDB through RunCloud.\n'
            ;;
        sk:cnf_rollback)
            DBTUNE_I18N_MESSAGE='# Rollback: odstráňte nasadený 99-zz-tuning.cnf a reštartujte MariaDB cez RunCloud.\n'
            ;;
        en:cnf_baseline_intro)
            DBTUNE_I18N_MESSAGE='# The safe portable baseline is an inactive catalog. Only keys supported and permitted by version or measurement in analysis.tsv are activated:\n'
            ;;
        sk:cnf_baseline_intro)
            DBTUNE_I18N_MESSAGE='# Bezpečný prenosný baseline je neaktívny katalóg. Aktivujú sa iba kľúče podporené a verziou alebo meraním povolené v analysis.tsv:\n'
            ;;
        en:cnf_evidence)
            DBTUNE_I18N_MESSAGE='Evidence'
            ;;
        sk:cnf_evidence)
            DBTUNE_I18N_MESSAGE='Evidencia'
            ;;
        en:lifecycle_config_parent_unsafe) DBTUNE_I18N_MESSAGE='Config parent component is not a safe real directory: %s' ;;
        sk:lifecycle_config_parent_unsafe) DBTUNE_I18N_MESSAGE='Nadradený komponent konfigurácie nie je bezpečný reálny adresár: %s' ;;
        en:lifecycle_target_paths_absolute) DBTUNE_I18N_MESSAGE='Config target and allowed directory must be canonical absolute paths' ;;
        sk:lifecycle_target_paths_absolute) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie a povolený adresár musia byť kanonické absolútne cesty' ;;
        en:lifecycle_target_allowed) DBTUNE_I18N_MESSAGE='Config target must be a .cnf file directly in the allowed directory %s' ;;
        sk:lifecycle_target_allowed) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie musí byť súbor .cnf priamo v povolenom adresári %s' ;;
        en:lifecycle_allowed_dir_metadata) DBTUNE_I18N_MESSAGE='Allowed config directory has unexpected ownership or is group/world writable: %s (%s:%s %s)' ;;
        sk:lifecycle_allowed_dir_metadata) DBTUNE_I18N_MESSAGE='Povolený adresár konfigurácie má neočakávané vlastníctvo alebo je zapisovateľný pre skupinu či ostatných: %s (%s:%s %s)' ;;
        en:lifecycle_allowed_dir_replaced_apply) DBTUNE_I18N_MESSAGE='Allowed config directory was replaced during apply' ;;
        sk:lifecycle_allowed_dir_replaced_apply) DBTUNE_I18N_MESSAGE='Povolený adresár konfigurácie bol počas apply vymenený' ;;
        en:lifecycle_target_symlink) DBTUNE_I18N_MESSAGE='Config target is a symlink or dangling symlink: %s' ;;
        sk:lifecycle_target_symlink) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie je symlink alebo neplatný symlink: %s' ;;
        en:lifecycle_target_not_regular) DBTUNE_I18N_MESSAGE='Config target is not a regular file: %s' ;;
        sk:lifecycle_target_not_regular) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie nie je regulárny súbor: %s' ;;
        en:lifecycle_target_metadata) DBTUNE_I18N_MESSAGE='Config target has unexpected ownership or mode: %s (%s:%s %s)' ;;
        sk:lifecycle_target_metadata) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie má neočakávané vlastníctvo alebo režim: %s (%s:%s %s)' ;;
        en:lifecycle_target_hardlinks) DBTUNE_I18N_MESSAGE='Config target has multiple hard links and its topology cannot be safely restored: %s' ;;
        sk:lifecycle_target_hardlinks) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie má viac hardlinkov a jeho topológiu nie je možné bezpečne obnoviť: %s' ;;
        en:lifecycle_target_topology_changed) DBTUNE_I18N_MESSAGE='Config target changed topology during the operation (%s -> %s)' ;;
        sk:lifecycle_target_topology_changed) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie počas operácie zmenil topológiu (%s -> %s)' ;;
        en:lifecycle_target_replaced) DBTUNE_I18N_MESSAGE='Config target was replaced during the operation' ;;
        sk:lifecycle_target_replaced) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie bol počas operácie vymenený' ;;
        en:lifecycle_target_changed) DBTUNE_I18N_MESSAGE='Config target was changed during the operation' ;;
        sk:lifecycle_target_changed) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie bol počas operácie zmenený' ;;
        en:lifecycle_fault_injection) DBTUNE_I18N_MESSAGE='Fault injection at lifecycle boundary: %s' ;;
        sk:lifecycle_fault_injection) DBTUNE_I18N_MESSAGE='Simulované zlyhanie na hranici lifecycle: %s' ;;
        en:lifecycle_apply_unknown_option) DBTUNE_I18N_MESSAGE='Unknown apply option: %s' ;;
        sk:lifecycle_apply_unknown_option) DBTUNE_I18N_MESSAGE='Neznáma voľba apply: %s' ;;
        en:lifecycle_force_phrase) DBTUNE_I18N_MESSAGE='APPLY WITHOUT MEASUREMENTS' ;;
        sk:lifecycle_force_phrase) DBTUNE_I18N_MESSAGE='APLIKUJ BEZ MERANIA' ;;
        en:lifecycle_backup_phrase) DBTUNE_I18N_MESSAGE='I CONFIRM A RESTORABLE BACKUP' ;;
        sk:lifecycle_backup_phrase) DBTUNE_I18N_MESSAGE='POTVRDZUJEM OBNOVITELNU ZALOHU' ;;
        en:lifecycle_force_tty) DBTUNE_I18N_MESSAGE='--force is allowed only interactively on a TTY' ;;
        sk:lifecycle_force_tty) DBTUNE_I18N_MESSAGE='--force je povolený iba interaktívne na TTY' ;;
        en:lifecycle_confirmation_prompt) DBTUNE_I18N_MESSAGE='Type exactly to continue: %s\n> ' ;;
        sk:lifecycle_confirmation_prompt) DBTUNE_I18N_MESSAGE='Pre pokračovanie napíšte presne: %s\n> ' ;;
        en:lifecycle_force_confirmation_mismatch) DBTUNE_I18N_MESSAGE='The confirmation phrase does not match' ;;
        sk:lifecycle_force_confirmation_mismatch) DBTUNE_I18N_MESSAGE='Potvrdzovacia fráza sa nezhoduje' ;;
        en:lifecycle_backup_tty) DBTUNE_I18N_MESSAGE='Apply requires verified backup-evidence.tsv or interactive confirmation on a TTY' ;;
        sk:lifecycle_backup_tty) DBTUNE_I18N_MESSAGE='Apply vyžaduje overený backup-evidence.tsv alebo interaktívne potvrdenie na TTY' ;;
        en:lifecycle_backup_missing_intro) DBTUNE_I18N_MESSAGE='Authoritative evidence of the last successful backup is missing. Verify restoration outside dbtune.\n' ;;
        sk:lifecycle_backup_missing_intro) DBTUNE_I18N_MESSAGE='Chýba autoritatívny dôkaz poslednej úspešnej zálohy. Overte obnovu mimo dbtune.\n' ;;
        en:lifecycle_backup_confirmation_mismatch) DBTUNE_I18N_MESSAGE='The restorable-backup confirmation does not match' ;;
        sk:lifecycle_backup_confirmation_mismatch) DBTUNE_I18N_MESSAGE='Potvrdenie obnoviteľnej zálohy sa nezhoduje' ;;
        en:lifecycle_backup_rejected) DBTUNE_I18N_MESSAGE='Apply is blocked: backup evidence was rejected; reason=%s; age_seconds=%s; max_age_seconds=%s' ;;
        sk:lifecycle_backup_rejected) DBTUNE_I18N_MESSAGE='Apply je zablokovaný: backup evidence bol odmietnutý; reason=%s; age_seconds=%s; max_age_seconds=%s' ;;
        en:lifecycle_backup_confirmed_missing) DBTUNE_I18N_MESSAGE='Apply is blocked: authoritative backup evidence confirms that no backup exists' ;;
        sk:lifecycle_backup_confirmed_missing) DBTUNE_I18N_MESSAGE='Apply je zablokovaný: autoritatívny backup evidence potvrdzuje absenciu zálohy' ;;
        en:lifecycle_proposal_manifest_missing) DBTUNE_I18N_MESSAGE='Proposal manifest is missing: %s' ;;
        sk:lifecycle_proposal_manifest_missing) DBTUNE_I18N_MESSAGE='Chýba proposal manifest: %s' ;;
        en:lifecycle_proposal_manifest_key_missing) DBTUNE_I18N_MESSAGE='Proposal manifest has no provenance record for %s' ;;
        sk:lifecycle_proposal_manifest_key_missing) DBTUNE_I18N_MESSAGE='Proposal manifest nemá provenance záznam %s' ;;
        en:lifecycle_proposal_other_run) DBTUNE_I18N_MESSAGE='Proposal belongs to a different analysis run (%s)' ;;
        sk:lifecycle_proposal_other_run) DBTUNE_I18N_MESSAGE='Proposal patrí inému analysis runu (%s)' ;;
        en:lifecycle_proposal_hash_missing) DBTUNE_I18N_MESSAGE='Proposal manifest has no proposal_hash' ;;
        sk:lifecycle_proposal_hash_missing) DBTUNE_I18N_MESSAGE='Proposal manifest nemá proposal_hash' ;;
        en:lifecycle_proposal_changed) DBTUNE_I18N_MESSAGE='Proposal snapshot changed or does not match the manifest' ;;
        sk:lifecycle_proposal_changed) DBTUNE_I18N_MESSAGE='Proposal snapshot sa zmenil alebo nezodpovedá manifestu' ;;
        en:lifecycle_proposal_count_missing) DBTUNE_I18N_MESSAGE='Proposal manifest has no proposal_count' ;;
        sk:lifecycle_proposal_count_missing) DBTUNE_I18N_MESSAGE='Proposal manifest nemá proposal_count' ;;
        en:lifecycle_proposal_records_hash_missing) DBTUNE_I18N_MESSAGE='Proposal manifest has no proposal_records_hash' ;;
        sk:lifecycle_proposal_records_hash_missing) DBTUNE_I18N_MESSAGE='Proposal manifest nemá proposal_records_hash' ;;
        en:lifecycle_proposal_records_mismatch) DBTUNE_I18N_MESSAGE='Proposal manifest does not match the canonical change records' ;;
        sk:lifecycle_proposal_records_mismatch) DBTUNE_I18N_MESSAGE='Proposal manifest nezodpovedá kanonickému zoznamu zmien' ;;
        en:lifecycle_cnf_duplicate) DBTUNE_I18N_MESSAGE='Deployed CNF contains a duplicate key: %s' ;;
        sk:lifecycle_cnf_duplicate) DBTUNE_I18N_MESSAGE='Nasadený CNF obsahuje duplicitný kľúč: %s' ;;
        en:lifecycle_cnf_count_mismatch) DBTUNE_I18N_MESSAGE='CNF and canonical proposal have different change counts' ;;
        sk:lifecycle_cnf_count_mismatch) DBTUNE_I18N_MESSAGE='CNF a kanonický proposal majú rozdielny počet zmien' ;;
        en:lifecycle_cnf_record_mismatch) DBTUNE_I18N_MESSAGE='CNF does not match canonical change %s' ;;
        sk:lifecycle_cnf_record_mismatch) DBTUNE_I18N_MESSAGE='CNF nezodpovedá kanonickej zmene %s' ;;
        en:lifecycle_apply_state_required) DBTUNE_I18N_MESSAGE="Apply requires current state 'proposed'; current state is '%s'" ;;
        sk:lifecycle_apply_state_required) DBTUNE_I18N_MESSAGE="Apply vyžaduje aktuálny stav 'proposed'; aktuálny stav je '%s'" ;;
        en:lifecycle_force_state_required) DBTUNE_I18N_MESSAGE="Forced apply requires state 'audited', 'analyzed', or 'proposed'; current state is '%s'" ;;
        sk:lifecycle_force_state_required) DBTUNE_I18N_MESSAGE="Vynútený apply vyžaduje stav 'audited', 'analyzed' alebo 'proposed'; aktuálny stav je '%s'" ;;
        en:lifecycle_proposal_missing) DBTUNE_I18N_MESSAGE='Configuration proposal is missing: %s' ;;
        sk:lifecycle_proposal_missing) DBTUNE_I18N_MESSAGE='Chýba návrh konfigurácie: %s' ;;
        en:lifecycle_measurement_missing) DBTUNE_I18N_MESSAGE='Apply is blocked: samples.tsv or analysis.tsv is missing; an unmeasured preset is a guess' ;;
        sk:lifecycle_measurement_missing) DBTUNE_I18N_MESSAGE='Apply je zablokovaný: chýba samples.tsv alebo analysis.tsv; preset bez merania je odhad' ;;
        en:lifecycle_invalid_clock) DBTUNE_I18N_MESSAGE='date returned an invalid local time: %s' ;;
        sk:lifecycle_invalid_clock) DBTUNE_I18N_MESSAGE='date vrátil neplatný lokálny čas: %s' ;;
        en:lifecycle_blocked_time_window) DBTUNE_I18N_MESSAGE='Apply is blocked between 05:30 and 07:30 local time because of unattended-upgrades; use interactive --force' ;;
        sk:lifecycle_blocked_time_window) DBTUNE_I18N_MESSAGE='Apply je medzi 05:30 a 07:30 lokálne zablokovaný kvôli unattended-upgrades; použite interaktívny --force' ;;
        en:lifecycle_no_active_variables) DBTUNE_I18N_MESSAGE='Proposal has no active variables in the [mysqld] section' ;;
        sk:lifecycle_no_active_variables) DBTUNE_I18N_MESSAGE='Návrh nemá žiadne aktívne premenné v sekcii [mysqld]' ;;
        en:lifecycle_live_variable_check_failed) DBTUNE_I18N_MESSAGE='Live variable-name validation failed' ;;
        sk:lifecycle_live_variable_check_failed) DBTUNE_I18N_MESSAGE='Živá kontrola názvov premenných zlyhala' ;;
        en:lifecycle_unknown_variable) DBTUNE_I18N_MESSAGE='Unknown or inactive MariaDB variable: %s' ;;
        sk:lifecycle_unknown_variable) DBTUNE_I18N_MESSAGE='Neznáma alebo neaktívna MariaDB premenná: %s' ;;
        en:lifecycle_galera_rejected) DBTUNE_I18N_MESSAGE='Galera/wsrep is active or configured; apply is refused' ;;
        sk:lifecycle_galera_rejected) DBTUNE_I18N_MESSAGE='Galera/wsrep je aktívna alebo nakonfigurovaná; apply sa odmieta' ;;
        en:lifecycle_mydumper_invalid) DBTUNE_I18N_MESSAGE='The mydumper process check returned an invalid result' ;;
        sk:lifecycle_mydumper_invalid) DBTUNE_I18N_MESSAGE='Kontrola procesu mydumper vrátila neplatný výsledok' ;;
        en:lifecycle_mydumper_running) DBTUNE_I18N_MESSAGE='A mydumper backup is running; configuration and restart instructions will not be applied' ;;
        sk:lifecycle_mydumper_running) DBTUNE_I18N_MESSAGE='Prebieha mydumper backup; konfigurácia ani pokyn na reštart sa nevykoná' ;;
        en:lifecycle_critical_finding) DBTUNE_I18N_MESSAGE='Apply is blocked by a critical server finding: %s' ;;
        sk:lifecycle_critical_finding) DBTUNE_I18N_MESSAGE='Apply blokuje kritický serverový nález: %s' ;;
        en:lifecycle_rollback_intro) DBTUNE_I18N_MESSAGE='# Filesystem-first rollback; does not require a working MariaDB or dbtune.\n' ;;
        sk:lifecycle_rollback_intro) DBTUNE_I18N_MESSAGE='# Filesystem-first rollback; nevyžaduje funkčnú MariaDB ani dbtune.\n' ;;
        en:lifecycle_rollback_restored_shell) DBTUNE_I18N_MESSAGE='  printf "Configuration restored; restart MariaDB through the RunCloud panel.\\n"\n' ;;
        sk:lifecycle_rollback_restored_shell) DBTUNE_I18N_MESSAGE='  printf "Konfigurácia bola obnovená; reštartujte MariaDB cez RunCloud panel.\\n"\n' ;;
        en:lifecycle_apply_report_title) DBTUNE_I18N_MESSAGE='# APPLY REPORT\n\n' ;;
        sk:lifecycle_apply_report_title) DBTUNE_I18N_MESSAGE='# REPORT NASADENIA\n\n' ;;
        en:lifecycle_without_measurements) DBTUNE_I18N_MESSAGE='WITHOUT MEASUREMENTS' ;;
        sk:lifecycle_without_measurements) DBTUNE_I18N_MESSAGE='BEZ MERANIA' ;;
        en:lifecycle_apply_report_forced) DBTUNE_I18N_MESSAGE='**%s** - the configuration was applied with interactive --force.\n' ;;
        sk:lifecycle_apply_report_forced) DBTUNE_I18N_MESSAGE='**%s** - konfigurácia bola aplikovaná cez interaktívny --force.\n' ;;
        en:lifecycle_report_forced_note) DBTUNE_I18N_MESSAGE='\n> **%s** - apply was forced without complete measurement/analysis artifacts.\n' ;;
        sk:lifecycle_report_forced_note) DBTUNE_I18N_MESSAGE='\n> **%s** - apply bol vynútený bez kompletného measurement/analysis artefaktu.\n' ;;
        en:lifecycle_config_written) DBTUNE_I18N_MESSAGE='Configuration was written to %s.\n' ;;
        sk:lifecycle_config_written) DBTUNE_I18N_MESSAGE='Konfigurácia bola zapísaná do %s.\n' ;;
        en:lifecycle_runcloud_restart) DBTUNE_I18N_MESSAGE='Restart through RunCloud: Services -> MariaDB -> Restart.\n' ;;
        sk:lifecycle_runcloud_restart) DBTUNE_I18N_MESSAGE='Reštartujte cez RunCloud: Services -> MariaDB -> Restart.\n' ;;
        en:lifecycle_redo_start_delay) DBTUNE_I18N_MESSAGE='After a redo-log change, the first start may take longer.\n' ;;
        sk:lifecycle_redo_start_delay) DBTUNE_I18N_MESSAGE='Pri zmene redo logu môže prvý štart trvať dlhšie.\n' ;;
        en:lifecycle_run_verify) DBTUNE_I18N_MESSAGE='After restart, run: dbtune verify --post\n' ;;
        sk:lifecycle_run_verify) DBTUNE_I18N_MESSAGE='Po reštarte spustite: dbtune verify --post\n' ;;
        en:lifecycle_emergency_commands) DBTUNE_I18N_MESSAGE='Emergency literal commands: %s/ROLLBACK.txt\n' ;;
        sk:lifecycle_emergency_commands) DBTUNE_I18N_MESSAGE='Núdzové doslovné príkazy: %s/ROLLBACK.txt\n' ;;
        en:lifecycle_target_missing) DBTUNE_I18N_MESSAGE='TARGET ERROR: %s is not a regular file or is a symlink\n' ;;
        sk:lifecycle_target_missing) DBTUNE_I18N_MESSAGE='CHYBA CIEĽA: %s nie je regulárny súbor alebo je symlink\n' ;;
        en:lifecycle_target_hardlink_error) DBTUNE_I18N_MESSAGE='TARGET ERROR: %s does not have the expected hard-link topology (links=%s, expected=1)\n' ;;
        sk:lifecycle_target_hardlink_error) DBTUNE_I18N_MESSAGE='CHYBA CIEĽA: %s nemá očakávanú hardlink topológiu (links=%s, očakávané=1)\n' ;;
        en:lifecycle_target_metadata_error) DBTUNE_I18N_MESSAGE='TARGET ERROR: owner=%s:%s mode=%s, expected=%s:%s %s\n' ;;
        sk:lifecycle_target_metadata_error) DBTUNE_I18N_MESSAGE='CHYBA CIEĽA: owner=%s:%s mode=%s, očakávané=%s:%s %s\n' ;;
        en:lifecycle_target_hash_error) DBTUNE_I18N_MESSAGE='TARGET ERROR: deployed configuration hash does not match the apply snapshot\n' ;;
        sk:lifecycle_target_hash_error) DBTUNE_I18N_MESSAGE='CHYBA CIEĽA: hash nasadenej konfigurácie nezodpovedá apply snapshotu\n' ;;
        en:lifecycle_target_ok) DBTUNE_I18N_MESSAGE='TARGET OK: %s owner=%s:%s mode=%s hash=%s\n' ;;
        sk:lifecycle_target_ok) DBTUNE_I18N_MESSAGE='CIEĽ OK: %s owner=%s:%s mode=%s hash=%s\n' ;;
        en:lifecycle_value_mismatch) DBTUNE_I18N_MESSAGE='MISMATCH %s: proposal=%s effective=%s\n' ;;
        sk:lifecycle_value_mismatch) DBTUNE_I18N_MESSAGE='NEZHODA %s: proposal=%s effective=%s\n' ;;
        en:lifecycle_value_ok) DBTUNE_I18N_MESSAGE='OK %s=%s\n' ;;
        sk:lifecycle_value_ok) DBTUNE_I18N_MESSAGE='OK %s=%s\n' ;;
        en:lifecycle_value_missing) DBTUNE_I18N_MESSAGE='<missing>' ;;
        sk:lifecycle_value_missing) DBTUNE_I18N_MESSAGE='<chýba>' ;;
        en:lifecycle_value_missing_upper) DBTUNE_I18N_MESSAGE='MISSING' ;;
        sk:lifecycle_value_missing_upper) DBTUNE_I18N_MESSAGE='CHÝBA' ;;
        en:lifecycle_verify_post_required) DBTUNE_I18N_MESSAGE='verify --24h requires a successful verify --post after restart' ;;
        sk:lifecycle_verify_post_required) DBTUNE_I18N_MESSAGE='verify --24h vyžaduje úspešný verify --post po reštarte' ;;
        en:lifecycle_health_line) DBTUNE_I18N_MESSAGE='%s baseline=%s current=%s delta=%s reset=%s\n' ;;
        sk:lifecycle_health_line) DBTUNE_I18N_MESSAGE='%s baseline=%s current=%s delta=%s reset=%s\n' ;;
        en:lifecycle_memory_line) DBTUNE_I18N_MESSAGE='memory_available_mb=%s swap_used_mb=%s baseline_swap_used_mb=%s\n' ;;
        sk:lifecycle_memory_line) DBTUNE_I18N_MESSAGE='memory_available_mb=%s swap_used_mb=%s baseline_swap_used_mb=%s\n' ;;
        en:lifecycle_verify_table_header) DBTUNE_I18N_MESSAGE='METRIC\tBASELINE\tCURRENT\tDELTA_OR_RESET\n' ;;
        sk:lifecycle_verify_table_header) DBTUNE_I18N_MESSAGE='METRIKA\tBASELINE\tAKTUÁLNE\tDELTA_ALEBO_RESET\n' ;;
        en:lifecycle_verify_usage) DBTUNE_I18N_MESSAGE='Usage: dbtune verify --post|--24h' ;;
        sk:lifecycle_verify_usage) DBTUNE_I18N_MESSAGE='Použitie: dbtune verify --post|--24h' ;;
        en:lifecycle_rollback_no_options) DBTUNE_I18N_MESSAGE='rollback does not accept options' ;;
        sk:lifecycle_rollback_no_options) DBTUNE_I18N_MESSAGE='rollback nemá voľby' ;;
        en:lifecycle_status_no_options) DBTUNE_I18N_MESSAGE='status does not accept options' ;;
        sk:lifecycle_status_no_options) DBTUNE_I18N_MESSAGE='status nemá voľby' ;;
        en:lifecycle_recovery_manual) DBTUNE_I18N_MESSAGE='sudo dbtune rollback; manually: %s/ROLLBACK.txt' ;;
        sk:lifecycle_recovery_manual) DBTUNE_I18N_MESSAGE='sudo dbtune rollback; manuálne: %s/ROLLBACK.txt' ;;
        en:lifecycle_parent_replaced_prepare) DBTUNE_I18N_MESSAGE='Config parent was replaced while apply was being prepared' ;;
        sk:lifecycle_parent_replaced_prepare) DBTUNE_I18N_MESSAGE='Nadradený adresár konfigurácie bol počas prípravy apply vymenený' ;;
        en:lifecycle_original_backup_mismatch) DBTUNE_I18N_MESSAGE='Backup of the original config target does not match its source' ;;
        sk:lifecycle_original_backup_mismatch) DBTUNE_I18N_MESSAGE='Záloha pôvodného cieľa konfigurácie nezodpovedá zdroju' ;;
        en:lifecycle_publisher_required) DBTUNE_I18N_MESSAGE='Secure config publication requires python3 with dir_fd and atomic rename-exchange support' ;;
        sk:lifecycle_publisher_required) DBTUNE_I18N_MESSAGE='Bezpečné publikovanie konfigurácie vyžaduje python3 s podporou dir_fd a atomického rename exchange' ;;
        en:lifecycle_parent_replaced_validation) DBTUNE_I18N_MESSAGE='Config parent was replaced since the original validation' ;;
        sk:lifecycle_parent_replaced_validation) DBTUNE_I18N_MESSAGE='Nadradený adresár konfigurácie bol od pôvodnej validácie vymenený' ;;
        en:lifecycle_validation_server_missing) DBTUNE_I18N_MESSAGE='Neither mariadbd nor mysqld was found for validation' ;;
        sk:lifecycle_validation_server_missing) DBTUNE_I18N_MESSAGE='Pre validáciu sa nenašiel mariadbd ani mysqld' ;;
        en:lifecycle_validation_invalid) DBTUNE_I18N_MESSAGE='mariadbd validation found an invalid configuration' ;;
        sk:lifecycle_validation_invalid) DBTUNE_I18N_MESSAGE='Validácia mariadbd našla neplatnú konfiguráciu' ;;
        en:lifecycle_validation_failed) DBTUNE_I18N_MESSAGE='mariadbd validation failed without a documented lock/engine initialization error' ;;
        sk:lifecycle_validation_failed) DBTUNE_I18N_MESSAGE='Validácia mariadbd zlyhala bez dokumentovanej chyby inicializácie locku alebo enginu' ;;
        en:lifecycle_validation_tolerated) DBTUNE_I18N_MESSAGE='mariadbd returned %s, but output contained only documented lock/engine initialization errors' ;;
        sk:lifecycle_validation_tolerated) DBTUNE_I18N_MESSAGE='mariadbd vrátil %s, ale výstup obsahoval iba dokumentované chyby inicializácie locku alebo enginu' ;;
        en:lifecycle_history_identity_invalid) DBTUNE_I18N_MESSAGE='Invalid apply history for cycle identity: %s' ;;
        sk:lifecycle_history_identity_invalid) DBTUNE_I18N_MESSAGE='Neplatná apply história pre identitu cyklu: %s' ;;
        en:lifecycle_cycle_id_mismatch) DBTUNE_I18N_MESSAGE='Apply cycle_id does not match the immutable history identity: %s' ;;
        sk:lifecycle_cycle_id_mismatch) DBTUNE_I18N_MESSAGE='Apply cycle_id nezodpovedá nemennej identite histórie: %s' ;;
        en:lifecycle_source_cycle_mismatch) DBTUNE_I18N_MESSAGE='Source apply cycle does not match the restore config backup' ;;
        sk:lifecycle_source_cycle_mismatch) DBTUNE_I18N_MESSAGE='Zdrojový apply cyklus nezodpovedá zálohe konfigurácie na obnovu' ;;
        en:lifecycle_backup_source_unknown) DBTUNE_I18N_MESSAGE='Unknown config-backup source: %s' ;;
        sk:lifecycle_backup_source_unknown) DBTUNE_I18N_MESSAGE='Neznámy zdroj zálohy konfigurácie: %s' ;;
        en:lifecycle_parent_replaced_apply) DBTUNE_I18N_MESSAGE='Config parent was replaced since apply validation' ;;
        sk:lifecycle_parent_replaced_apply) DBTUNE_I18N_MESSAGE='Nadradený adresár konfigurácie bol od apply validácie vymenený' ;;
        en:lifecycle_target_snapshot_mismatch) DBTUNE_I18N_MESSAGE='Config target does not match the original or published apply snapshot' ;;
        sk:lifecycle_target_snapshot_mismatch) DBTUNE_I18N_MESSAGE='Cieľ konfigurácie nezodpovedá pôvodnému ani publikovanému apply snapshotu' ;;
        en:lifecycle_original_target_missing) DBTUNE_I18N_MESSAGE='Originally present config target disappeared during restoration' ;;
        sk:lifecycle_original_target_missing) DBTUNE_I18N_MESSAGE='Pôvodne existujúci cieľ konfigurácie počas obnovy zmizol' ;;
        en:lifecycle_original_config_missing) DBTUNE_I18N_MESSAGE='Apply history is missing the regular original config: %s/original.cnf' ;;
        sk:lifecycle_original_config_missing) DBTUNE_I18N_MESSAGE='V apply histórii chýba regulárna pôvodná konfigurácia: %s/original.cnf' ;;
        en:lifecycle_original_config_hash_invalid) DBTUNE_I18N_MESSAGE='Original config in apply history has an invalid hash' ;;
        sk:lifecycle_original_config_hash_invalid) DBTUNE_I18N_MESSAGE='Pôvodná konfigurácia v apply histórii má neplatný hash' ;;
        en:lifecycle_restored_config_mismatch) DBTUNE_I18N_MESSAGE='Restored config does not match the original backup' ;;
        sk:lifecycle_restored_config_mismatch) DBTUNE_I18N_MESSAGE='Obnovená konfigurácia nezodpovedá pôvodnej zálohe' ;;
        en:lifecycle_rollback_intent_invalid) DBTUNE_I18N_MESSAGE='Rollback intent journal is invalid: %s' ;;
        sk:lifecycle_rollback_intent_invalid) DBTUNE_I18N_MESSAGE='Rollback intent journal je neplatný: %s' ;;
        en:lifecycle_rollback_lineage_mismatch) DBTUNE_I18N_MESSAGE='Rollback intent does not match the immutable restore lineage' ;;
        sk:lifecycle_rollback_lineage_mismatch) DBTUNE_I18N_MESSAGE='Rollback intent nezodpovedá nemennej restore lineage' ;;
        en:lifecycle_rollback_completion_invalid) DBTUNE_I18N_MESSAGE='Rollback completion metadata is invalid: %s' ;;
        sk:lifecycle_rollback_completion_invalid) DBTUNE_I18N_MESSAGE='Rollback completion metadata sú neplatné: %s' ;;
        en:lifecycle_rollback_completion_mismatch) DBTUNE_I18N_MESSAGE='Rollback completion metadata does not match the journal: %s' ;;
        sk:lifecycle_rollback_completion_mismatch) DBTUNE_I18N_MESSAGE='Rollback completion metadata nezodpovedajú journalu: %s' ;;
        en:lifecycle_previous_pointer_unsafe) DBTUNE_I18N_MESSAGE='Previous apply pointer is not a safe history: %s' ;;
        sk:lifecycle_previous_pointer_unsafe) DBTUNE_I18N_MESSAGE='Predchádzajúci apply pointer nie je bezpečná história: %s' ;;
        en:lifecycle_apply_intent_invalid) DBTUNE_I18N_MESSAGE='Apply intent journal is invalid: %s' ;;
        sk:lifecycle_apply_intent_invalid) DBTUNE_I18N_MESSAGE='Apply intent journal je neplatný: %s' ;;
        en:lifecycle_apply_intent_history_invalid) DBTUNE_I18N_MESSAGE='Apply intent refers to invalid history' ;;
        sk:lifecycle_apply_intent_history_invalid) DBTUNE_I18N_MESSAGE='Apply intent odkazuje na neplatnú históriu' ;;
        en:lifecycle_apply_intent_pointer_invalid) DBTUNE_I18N_MESSAGE='Apply intent contains an invalid previous pointer' ;;
        sk:lifecycle_apply_intent_pointer_invalid) DBTUNE_I18N_MESSAGE='Apply intent obsahuje neplatný predchádzajúci pointer' ;;
        en:lifecycle_apply_intent_snapshot_mismatch) DBTUNE_I18N_MESSAGE='Apply intent does not match the stored proposal snapshot' ;;
        sk:lifecycle_apply_intent_snapshot_mismatch) DBTUNE_I18N_MESSAGE='Apply intent nezodpovedá uloženému proposal snapshotu' ;;
        en:lifecycle_current_missing) DBTUNE_I18N_MESSAGE='Current apply record is missing: %s' ;;
        sk:lifecycle_current_missing) DBTUNE_I18N_MESSAGE='Chýba záznam aktuálneho apply: %s' ;;
        en:lifecycle_history_invalid) DBTUNE_I18N_MESSAGE='Invalid apply history: %s' ;;
        sk:lifecycle_history_invalid) DBTUNE_I18N_MESSAGE='Neplatná apply história: %s' ;;
        en:lifecycle_recovery_critical) DBTUNE_I18N_MESSAGE='CRITICAL: configuration recovery failed; use %s/ROLLBACK.txt' ;;
        sk:lifecycle_recovery_critical) DBTUNE_I18N_MESSAGE='KRITICKÉ: obnova konfigurácie zlyhala; použite %s/ROLLBACK.txt' ;;
        en:lifecycle_rollback_failed) DBTUNE_I18N_MESSAGE='Filesystem rollback failed; use %s/ROLLBACK.txt' ;;
        sk:lifecycle_rollback_failed) DBTUNE_I18N_MESSAGE='Filesystem rollback zlyhal; použite %s/ROLLBACK.txt' ;;
        en:lifecycle_rollback_target_mismatch) DBTUNE_I18N_MESSAGE='Rollback target does not match the deployed or restored snapshot' ;;
        sk:lifecycle_rollback_target_mismatch) DBTUNE_I18N_MESSAGE='Rollback cieľ nezodpovedá nasadenému ani obnovenému snapshotu' ;;
        en:lifecycle_rollback_restart_required) DBTUNE_I18N_MESSAGE='Configuration was restored. Restart MariaDB manually through the RunCloud panel so effective values are restored too.\n' ;;
        sk:lifecycle_rollback_restart_required) DBTUNE_I18N_MESSAGE='Konfigurácia bola obnovená. Reštartujte MariaDB manuálne cez RunCloud panel, aby sa obnovili aj efektívne hodnoty.\n' ;;
        en:lifecycle_rollback_pointer_mismatch) DBTUNE_I18N_MESSAGE='Rollback pointer does not match the original or restored cycle' ;;
        sk:lifecycle_rollback_pointer_mismatch) DBTUNE_I18N_MESSAGE='Rollback pointer nezodpovedá pôvodnému ani obnovenému cyklu' ;;
        en:lifecycle_rollback_state_mismatch) DBTUNE_I18N_MESSAGE='Rollback state does not match the journal: %s' ;;
        sk:lifecycle_rollback_state_mismatch) DBTUNE_I18N_MESSAGE='Rollback stav nezodpovedá journalu: %s' ;;
        en:lifecycle_service_start_failed) DBTUNE_I18N_MESSAGE='Configuration was restored, but systemctl start mariadb failed' ;;
        sk:lifecycle_service_start_failed) DBTUNE_I18N_MESSAGE='Konfigurácia bola obnovená, ale systemctl start mariadb zlyhal' ;;
        en:lifecycle_baseline_failed) DBTUNE_I18N_MESSAGE='Baseline could not be saved; config was not written' ;;
        sk:lifecycle_baseline_failed) DBTUNE_I18N_MESSAGE='Baseline sa nepodarilo uložiť; konfigurácia sa nezapísala' ;;
        en:lifecycle_atomic_write_failed) DBTUNE_I18N_MESSAGE='Atomic configuration write failed' ;;
        sk:lifecycle_atomic_write_failed) DBTUNE_I18N_MESSAGE='Atomický zápis konfigurácie zlyhal' ;;
        en:lifecycle_final_check_failed) DBTUNE_I18N_MESSAGE='Published config failed the final filesystem check' ;;
        sk:lifecycle_final_check_failed) DBTUNE_I18N_MESSAGE='Publikovaná konfigurácia neprešla finálnou filesystem kontrolou' ;;
        en:lifecycle_intent_finalize_failed) DBTUNE_I18N_MESSAGE='Apply was published, but the intent journal could not be safely finalized' ;;
        sk:lifecycle_intent_finalize_failed) DBTUNE_I18N_MESSAGE='Apply bol publikovaný, ale intent journal sa nepodarilo bezpečne finalizovať' ;;
        en:lifecycle_restart_failed) DBTUNE_I18N_MESSAGE='MariaDB restart failed; restoring the original config and starting the service' ;;
        sk:lifecycle_restart_failed) DBTUNE_I18N_MESSAGE='Reštart MariaDB zlyhal; obnovujem pôvodnú konfiguráciu a spúšťam službu' ;;
        en:lifecycle_publisher_not_regular) DBTUNE_I18N_MESSAGE='%s is not a regular file' ;;
        sk:lifecycle_publisher_not_regular) DBTUNE_I18N_MESSAGE='%s nie je regulárny súbor' ;;
        en:lifecycle_publisher_metadata) DBTUNE_I18N_MESSAGE='%s has unexpected ownership or mode' ;;
        sk:lifecycle_publisher_metadata) DBTUNE_I18N_MESSAGE='%s má neočakávané vlastníctvo alebo režim' ;;
        en:lifecycle_publisher_hardlinks) DBTUNE_I18N_MESSAGE='%s has an unexpected hard-link count' ;;
        sk:lifecycle_publisher_hardlinks) DBTUNE_I18N_MESSAGE='%s má neočakávaný počet hardlinkov' ;;
        en:lifecycle_publisher_replaced) DBTUNE_I18N_MESSAGE='%s was replaced during publication' ;;
        sk:lifecycle_publisher_replaced) DBTUNE_I18N_MESSAGE='%s bol počas publikovania vymenený' ;;
        en:lifecycle_publisher_changed) DBTUNE_I18N_MESSAGE='%s was changed during publication' ;;
        sk:lifecycle_publisher_changed) DBTUNE_I18N_MESSAGE='%s bol počas publikovania zmenený' ;;
        en:lifecycle_publisher_open_dir_identity) DBTUNE_I18N_MESSAGE='opened config directory does not have the expected identity' ;;
        sk:lifecycle_publisher_open_dir_identity) DBTUNE_I18N_MESSAGE='otvorený adresár konfigurácie nemá očakávanú identitu' ;;
        en:lifecycle_publisher_dir_replaced) DBTUNE_I18N_MESSAGE='config directory was replaced during publication' ;;
        sk:lifecycle_publisher_dir_replaced) DBTUNE_I18N_MESSAGE='adresár konfigurácie bol počas publikovania vymenený' ;;
        en:lifecycle_publisher_parent_chain) DBTUNE_I18N_MESSAGE='config parent chain is invalid' ;;
        sk:lifecycle_publisher_parent_chain) DBTUNE_I18N_MESSAGE='reťazec nadradených adresárov konfigurácie je neplatný' ;;
        en:lifecycle_publisher_parent_replaced) DBTUNE_I18N_MESSAGE='config parent was replaced during publication: %s' ;;
        sk:lifecycle_publisher_parent_replaced) DBTUNE_I18N_MESSAGE='nadradený adresár konfigurácie bol počas publikovania vymenený: %s' ;;
        en:lifecycle_publisher_topology_changed) DBTUNE_I18N_MESSAGE='%s changed topology during publication' ;;
        sk:lifecycle_publisher_topology_changed) DBTUNE_I18N_MESSAGE='%s počas publikovania zmenil topológiu' ;;
        en:lifecycle_publisher_fault_hook) DBTUNE_I18N_MESSAGE='fault hook failed' ;;
        sk:lifecycle_publisher_fault_hook) DBTUNE_I18N_MESSAGE='fault hook zlyhal' ;;
        en:lifecycle_publisher_atomic_flags) DBTUNE_I18N_MESSAGE='atomic rename flags are unavailable' ;;
        sk:lifecycle_publisher_atomic_flags) DBTUNE_I18N_MESSAGE='príznaky atomického rename nie sú dostupné' ;;
        en:lifecycle_publisher_fault_before) DBTUNE_I18N_MESSAGE='fault injection before publication' ;;
        sk:lifecycle_publisher_fault_before) DBTUNE_I18N_MESSAGE='simulované zlyhanie pred publikovaním' ;;
        en:lifecycle_publisher_failed) DBTUNE_I18N_MESSAGE='dbtune: secure config publication failed: %s' ;;
        sk:lifecycle_publisher_failed) DBTUNE_I18N_MESSAGE='dbtune: bezpečné publikovanie konfigurácie zlyhalo: %s' ;;
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
    printf -- "$DBTUNE_I18N_MESSAGE" "$@"
}

dbtune_eprintf() {
    dbtune_printf "$@" >&2
}
