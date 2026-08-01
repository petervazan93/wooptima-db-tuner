# dbtune

`dbtune` je samostatny Bash nastroj na audit, meranie a bezpecne ladenie MariaDB pre RunCloud servery s WordPress/WooCommerce. Zdroj je rozdeleny na moduly, ale nasadzuje sa jediny artefakt `dist/dbtune`.

## Instalacia

Na podporovanom Ubuntu serveri:

```bash
curl -fsSL https://github.com/petervazan93/wooptima-db-tuner/releases/latest/download/install.sh | sudo sh
```

Installer stiahne posledny GitHub Release, overi SHA-256 a Bash syntax a atomicky nainstaluje `/usr/local/bin/dbtune`. Nespusta audit ani nemeni MariaDB.

Odporucany auditovatelny a pripnuty variant:

```bash
curl --proto '=https' --tlsv1.2 -fsSLo install.sh \
  https://github.com/petervazan93/wooptima-db-tuner/releases/download/v0.1.0/install.sh
less install.sh
sudo sh install.sh --version v0.1.0
```

Prvy read-only krok po instalacii:

```bash
sudo dbtune audit --json
```

## Build a testy

```bash
make build
make test
```

Build zoradi `lib/*.sh`, vlozi subory z `templates/*` a `systemd/*` do funkcii `dbtune_embedded_list` a `dbtune_embedded_get`, vykona `bash -n`, volitelne `shellcheck` a vytvori `dist/dbtune.sha256`. Ak `bats` nie je nainstalovany, `make test` to oznaci ako `SKIP`.

## CLI

```text
dbtune audit [--json]
dbtune collect start [--days N]
dbtune collect status | stop
dbtune analyze [--min-samples N]
dbtune report | propose
dbtune apply [--restart] [--force]
dbtune verify --post | --24h
dbtune rollback
dbtune status | version
dbtune _tick
```

Dispatcher vola funkcie `cmd_audit`, `cmd_collect`, `cmd_analyze`, `cmd_report`, `cmd_propose`, `cmd_apply`, `cmd_verify`, `cmd_rollback`, `cmd_status` a `cmd_tick`, ktore dodaju dalsie moduly. `status` a `version` su povolene kedykolvek; novy audit nie je povoleny pocas aktivneho collectu. Bezny `apply` vyzaduje stav `proposed`, minimalny pocet validnych vzoriek a SHA-256 manifest viazuci proposal na aktualny audit, samples a analysis. Interaktivny `--force` moze pouzit rucne pripraveny proposal v stave `audited`, `analyzed` alebo `proposed`, ale neobchadza live validaciu, Galera ani samostatny backup guard.

Kazdy uspesny `audit` je stale read-only voci MariaDB a systemovej konfiguracii, ale zacina novy immutable meraci cyklus. Dostane jedinecny `run_id`; `audit_hash` pokryva `audit.tsv`, `apps.tsv` aj `databases.tsv`. Predchadzajuci cyklus sa skopiruje do `$DBTUNE_STATE_DIR/runs/<run_id>/`, jeho collect/analysis/report/proposal subory sa z aktivneho priestoru odstrania a stav sa nastavi na `audited`. `apply/` a `apply/current` sa nearchivuju ani nemazu, preto zostava dostupny rollback predchadzajuceho apply. Explicitny `audit --new-run` nie je potrebny.

`analysis-manifest.tsv` nesie povodny `run_id`, `audit_hash`, presny `samples_hash` a `analysis_hash`. Report tieto hodnoty publikuje, proposal manifest ich prebera a doplna `proposal_hash`; apply history ich zaznamena spolu s hashom skutocne nasadeneho snapshotu. Ak sa ktorykolvek vstup zmeni alebo zmiesa s inym runom, `report`, `propose` a bezny `apply` ho odmietnu. `verify` navyse vyzaduje regularny nesymlinkovy target `root:root 0644`, ktoreho hash presne sedi s immutable `apply/<run>/proposed.cnf`.

Backup sa z lokalneho cronu neodvodzuje. Autoritativna integracia moze atomicky vytvorit root-owned mode `0600` subor `$DBTUNE_STATE_DIR/backup-evidence.tsv` s piatimi jedinecnymi TSV klucmi: `schema=1`, `status=verified|missing|unknown`, `source`, UTC `checked_at` a `last_success`. `verified` vyzaduje UTC timestamp posledneho uspesneho behu, `missing` vyzaduje `last_success=none`; bez platneho `verified` artefaktu apply vyzaduje samostatne TTY potvrdenie `POTVRDZUJEM OBNOVITELNU ZALOHU`. Potvrdene `missing` apply vzdy blokuje. Audit artefakt iba cita a nikdy ho nevytvara ani rucne nedoplna `audit.tsv`.

## Spolocne kontrakty

- Cesty sa odvodzuju od `DBTUNE_STATE_DIR` (default `/var/lib/dbtune`) cez `dbtune_state_file`, `dbtune_events_file`, `dbtune_auth_method_file` a `dbtune_path`. Adresar ma mode `700`.
- `dbtune_state_read`, `dbtune_state_write`, `dbtune_state_transition`, `dbtune_state_guard` a `dbtune_require_state` implementuju lifecycle `idle -> audited -> collecting -> collected -> analyzed -> proposed -> applied -> verified`, vratane `rolled_back`, `recovery_required` a `rollback_failed`. Novy audit zacina novy cyklus v stave `audited`; pocas recovery stavov je blokovany a existujuca apply recovery historia ostava dostupna. Event log je best-effort a jeho zlyhanie nerusi uz atomicky commitnuty state.
- Audit, collect start/stop, analyze, report, propose, apply, verify a rollback su cez dispatcher serializovane spolocnym exkluzivnym `flock`. Bezny prikaz na lock caka; timerovy `_tick` cakanie nerobi a pri contention bezpecne preskoci tick. Collector si ponechava vlastny interny lock, ktory dispatcher nenahradza.
- `dbtune_atomic_write CESTA [MODE]` cita obsah zo stdin a publikuje ho cez docasny subor v rovnakom adresari.
- `dbtune_is_uint HODNOTA` a `dbtune_require_uint NAZOV HODNOTA [MIN] [MAX]` validuju integer argumenty bez implicitnych Bash konverzii.
- `dbtune_json_escape TEXT` a `dbtune_json_emit KLUC HODNOTA ...` su jediny podporovany sposob tvorby flat JSON. Vsetky emitovane hodnoty su JSON stringy.
- `dbtune_event TYP [KLUC HODNOTA ...]` zapisuje redigovany JSONL do `events.log`; `dbtune_log_*` zapisuje redigovane spravy na stderr. Hesla ani cele credential subory sa nesmu posielat loggeru.
- `dbtune_sql QUERY [DATABASE]` cita query cez stdin klienta. Najprv skusi root `unix_socket`, potom `DBTUNE_ROOT_CNF` (default `/etc/mysql/conf.d/root.cnf`) cez `--defaults-extra-file`. Heslo nikdy nie je na CLI ani v logu a uspesna metoda sa ulozi do state.
- Embedded asset sa cita cez `dbtune_embedded_get templates/tuning.cnf.tmpl`; zoznam poskytne `dbtune_embedded_list`.

### Kontrakt `samples.tsv`

Novy collector zapisuje append-only hlavicku `timestamp, uptime, bp_hit_pct, bp_misses_s, data_read_s, rnd_next_s, tmp_disk_pct, threads_running, threads_connected, qcache_hit_pct, log_waits_delta, wait_free_delta, cpu_pct, mem_available_kb, swap_used_kb, load1, restart_flag, qcache_queries_delta, interval_seconds, sample_status` oddelenu tabulatormi. Prvych 17 stlpcov zostava v povodnom poradi; posledne tri su rozsirujuci kontrakt.

- `qcache_queries_delta` je denominator `Qcache_hits delta + Com_select delta`. Hodnota `0` znamena idle okno a `R-QCACHE` ho nezahrnie do hit-rate percentilu. Pravidlo vyzaduje aspon tolko aktivnych okien, kolko urcuje `--min-samples`; inak emituje `UNKNOWN` bez proposal.
- `interval_seconds` je skutocny monotónny cas medzi dvojicou status/CPU snapshotov, vratane sleepu, scheduler delay a druheho SQL snapshotu. Rates a CPU pouzivaju tento interval, nie nakonfigurovany sleep.
- `sample_status` je `ok` alebo `degraded_interval`. Nečíselny, nerastuci alebo prilis dlhy interval je degraded; predvoleny limit je dvojnasobok `DBTUNE_SAMPLE_SECONDS` a da sa explicitne nastavit cez `DBTUNE_MAX_SAMPLE_INTERVAL_SECONDS`. Degraded a restart riadky sa nepouziju v rules/report metrikach ani v minimalnom pocte validnych vzoriek.
- Legacy 17-stlpcove subory ostavaju kompatibilne pre ostatne pravidla. Kedze neuchovavaju query-cache denominator, `R-QCACHE` pri nich bezpecne vrati `UNKNOWN` bez proposal. Ak upgrade zastihne aktivny legacy collect, prvy novy append atomicky rozsiri jeho hlavicku a stare riadky; povodne metriky ostanu validne a novy denominator v starych riadkoch ostane prazdny.

Projekt globalne pouziva `set -u`, nie `set -e`. Kniznicove moduly obsahuju iba deklaracie a funkcie; vykonanie programu zabezpecuje jediny guard na konci `lib/90-main.sh`.
