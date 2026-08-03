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
