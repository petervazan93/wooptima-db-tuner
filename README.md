# dbtune

`dbtune` je samostatny Bash nastroj na audit, meranie a bezpecne ladenie MariaDB pre RunCloud servery s WordPress/WooCommerce. Zdroj je rozdeleny na moduly, ale nasadzuje sa jediny artefakt `dist/dbtune`.

## Instalacia

Odporucany auditovatelny postup pouziva pripnuty release. Najprv stiahnite a overte povod samotneho installera, potom ho precitajte a az nasledne spustite ako root:

```bash
release=v0.3.0
curl --proto '=https' --tlsv1.2 -fsSLo install.sh \
  "https://github.com/petervazan93/wooptima-db-tuner/releases/download/$release/install.sh"
curl --proto '=https' --tlsv1.2 -fsSLo dbtune-attestation.jsonl \
  "https://github.com/petervazan93/wooptima-db-tuner/releases/download/$release/dbtune-attestation.jsonl"
gh attestation verify install.sh \
  --bundle dbtune-attestation.jsonl \
  --repo petervazan93/wooptima-db-tuner \
  --signer-workflow petervazan93/wooptima-db-tuner/.github/workflows/release.yml \
  --source-ref "refs/tags/$release" \
  --deny-self-hosted-runners
less install.sh
sudo sh install.sh --version "$release"
```

Installer vyzaduje `gh` CLI, stiahne zvoleny GitHub Release aj offline `dbtune-attestation.jsonl`, overi SHA-256, GitHub keyless artifact attestation pre `dbtune` voci explicitnemu repozitaru a jeho vlastnikovi, signer workflowu a release tagu a Bash syntax. Overenie bundle nevyzaduje `gh auth login` ani API token. Az potom artefakt atomicky nainstaluje do `/usr/local/bin/dbtune`. Nespusta audit ani nemeni MariaDB. Runtime `apply`, rollback a crash recovery vyzaduju `python3` s podporou `dir_fd` a Linux `renameat2`, ktoru poskytuju podporovane Ubuntu/RunCloud systemy. Download selector je `--version vX.Y.Z` alebo `DBTUNE_RELEASE=vX.Y.Z`; nema vplyv na immutable verziu vlozenu do artefaktu pri builde.

Pre produkciu je odporucany pripnuty `vX.Y.Z` release. Predvolene `latest` je pohyblivy selector: installer ho najprv cez GitHub release metadata prelozi na konkretny semver tag a potom overi artefakt voci presnemu `refs/tags/vX.Y.Z`. Hodnota verzie moze byt zadana s `v` aj bez neho.

GitHub Releases je predvoleny transport. Interny `DBTUNE_DOWNLOAD_BASE` moze ukazat na kontrolovany HTTPS mirror; `file://` je urceny iba pre testy. Transport override nemeni upstream repository, vlastnika, signer workflow ani exact source-ref politiku a nemoze autorizovat vlastny fork build. `DBTUNE_REPOSITORY` nie je podporovane.

Prvy read-only krok po instalacii:

```bash
sudo dbtune audit --json
```

## Podpora a zavislosti

| Oblast | Kontrakt |
| --- | --- |
| Akceptovane MariaDB rodiny | 10.6, 10.11 a 11.x |
| Integracne testovane MariaDB | 10.6 a 11.4 |
| CI operacny system | Ubuntu 24.04 |
| Cielove nasadenie | Linux RunCloud host so systemd |

- Installer: POSIX `sh`, Linux, `curl`, `gh`, Bash 4+, `install`, `stat`, SHA-256 nastroj a `sudo` pri privilegovanom cieli.
- Runtime: Bash 4+, standardne GNU/Linux nastroje a `flock`.
- Databaza: MariaDB/MySQL klient a podporovana root socket alebo defaults-file autentizacia.
- Apply, rollback a recovery: Python 3 s `dir_fd`, Linux `renameat2`, systemd a validacny prikaz MariaDB daemonu.
- Autoritativny hardware/security audit: `findmnt`, `lsblk`, `ss`, `free` a `pgrep` pre prislusne evidence domeny.
- WordPress actions: WP-CLI je volitelne; bez overeneho non-root vlastnika a kanonickeho webrootu ostane action `not-executable`.
- Vyvoj: Bats, ShellCheck, Docker a Docker Compose.

CI pokrytie netvrdi, ze kazdy Ubuntu release alebo kazdy MariaDB 11.x minor bol integracne testovany.

## Build a testy

```bash
make build
make check
make test
make integration
```

Build zoradi `lib/*.sh`, vlozi subory z `templates/*` a `systemd/*` do funkcii `dbtune_embedded_list` a `dbtune_embedded_get`, vykona `bash -n`, volitelne `shellcheck` a vytvori `dist/dbtune.sha256`. Ak `bats` nie je nainstalovany, `make test` to oznaci ako `SKIP`. Docker integration moze lokalne bez Dockera alebo Compose skoncit ako `SKIP`; pri `CI=1` alebo `DBTUNE_REQUIRE_INTEGRATION=1` je nedostupnost chyba.

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

Autoritativny audit vyzaduje styri sekcie: `mariadb` (serverove premenne, status a databazovy inventar), `hardware` (CPU, RAM a trieda datadir uloziska), `applications` (uplne discovery a per-app audit statusy) a `security` (granty a stav listenera na porte 3306). `audit.overall_status` ma presnu semantiku: `PASS` znamena uplne povinne sekcie bez nalezov, `FINDINGS` uplne povinne sekcie s aspon jednym nalezom, `UNKNOWN` aspon jednu `partial` alebo `failed` sekciu pri zachovani casti povinnych dokazov a `ERROR` zlyhanie vsetkych povinnych sekcii. `audit --json`, textovy summary aj report publikuju `audit.required_sections`, `audit.failed_sections`, `audit.partial_sections`, `audit.affected_domains` a stav kazdej sekcie. Klasifikovany audit vracia `0` pre `PASS`/`FINDINGS`, `2` pre `UNKNOWN` a `1` pre `ERROR`. Usage, validacne, dependency a ine technicke zlyhania mozu pouzit existujuce exit kody `64+`; automatizacia ich nesmie interpretovat ako auditnu klasifikaciu. Artefakty sa pri klasifikovanom `UNKNOWN`/`ERROR` zachovaju pre diagnostiku, ale automatizacia musi ne-nulovy status povazovat za neautoritativny vysledok.

MariaDB sekcia pouziva jedinu verziovanu evidence schemu pre vsetky proposal current hodnoty a MariaDB vstupy serverovych pravidiel. Schema urcuje kanonicky kluc, validator (`uint`, kladne cislo, decimal, percento, bool/enum, cesta alebo text), verziovy gate a rolu `proposal|input`; z rovnakej tabulky sa generuje GLOBAL_VARIABLES query aj rules proposal kontrakt. Chybajuci, `unknown`, malformed, konfliktny alebo nepodporovany povinny kluc nastavi sekciu na `partial` a audit na `UNKNOWN`. Bezpecne diagnostiky `audit.section.mariadb.{missing,invalid,conflicting,optional}_evidence` obsahuju iba nazvy klucov a dovody, nie hodnoty. `innodb_flush_method` je povinny na 10.6/10.11 a explicitne volitelny ako deprecated vstup na 11.x; ostatne podporovane proposal current hodnoty su povinne.

`analysis-manifest.tsv` nesie povodny `run_id`, `audit_hash`, presny `samples_hash`, identitu a hash `dbsize.tsv`, vybrane denne baseline riadky, `analysis_hash` a spolocny `analysis_fingerprint`. Report tieto hodnoty publikuje, proposal manifest fingerprint prebera a doplna `proposal_hash`; apply history ich zaznamena spolu s hashom skutocne nasadeneho snapshotu. Ak sa ktorykolvek vstup zmeni alebo zmiesa s inym runom, `report`, `propose` a bezny `apply` ho odmietnu. `verify` navyse vyzaduje regularny nesymlinkovy target `root:root 0644`, ktoreho hash presne sedi s immutable `apply/<run>/proposed.cnf`.

Audit cita efektivne hodnoty vsetkych MariaDB premennych, ktore rules engine moze navrhnut. Bez znamenej aktualnej hodnoty bezne pravidlo emituje `UNKNOWN` bez proposal; explicitne durability pravidlo je v evidencii oznacene `durability_exception=explicit`, ale pri chybajucej current hodnote je rovnako fail-closed. Report ani proposal preto nikdy nepublikuju aktivnu zmenu s `current=unknown`.

Serverove proposal records sa pri `report` a `propose` validuju a kanonizuju (`-` na `_`, lowercase) do jedneho streamu. Unsafe hodnota, app-scope proposal, chybajuca current hodnota alebo kanonicky duplicitny kluc zastavia prikaz. Markdown diff, flat JSON `proposal.*`, CNF a `proposal-manifest.tsv` pouzivaju rovnake poradie zmien; manifest nesie aj `proposal_count` a `proposal_records_hash`, ktore apply znovu porovna s analysis a CNF.

Backup sa z lokalneho cronu neodvodzuje. Autoritativna integracia moze atomicky vytvorit root-owned mode `0600` subor `$DBTUNE_STATE_DIR/backup-evidence.tsv` s piatimi jedinecnymi TSV klucmi: `schema=1`, `status=verified|missing|unknown`, `source`, UTC `checked_at` a `last_success`. `verified` vyzaduje platny UTC timestamp posledneho uspesneho behu, ktory nie je v buducnosti ani starsi ako `DBTUNE_MAX_BACKUP_AGE_SECONDS` (predvolene 86400 sekund); presna hranica je akceptovana. Existujuci neplatny, buduci alebo expirovany artefakt blokuje apply bez interaktivneho fallbacku a audit/report zobrazuje vyhodnoteny vek aj politiku. `missing` vyzaduje `last_success=none`; iba chybajuci alebo platny `unknown` artefakt vyzaduje samostatne TTY potvrdenie `POTVRDZUJEM OBNOVITELNU ZALOHU`. Potvrdene `missing` apply vzdy blokuje. Audit artefakt iba cita a nikdy ho nevytvara ani rucne nedoplna `audit.tsv`.

## Spolocne kontrakty

- Cesty sa odvodzuju od `DBTUNE_STATE_DIR` (default `/var/lib/dbtune`) cez `dbtune_state_file`, `dbtune_events_file`, `dbtune_auth_method_file` a `dbtune_path`. State cesta musi byt kanonicka absolutna cesta bez symlink parent komponentov; existujuci adresar musi uz pri prvom otvoreni vlastnit efektivne privilegovane UID a mat presne mode `700`, inak sa jeho obsah odmietne bez automatickeho `chmod`. Stabilny state subor aj lifecycle, event a collector locky musia mat presne jeden hardlink; kazdy lock je regularny mode `0600` subor rovnakeho vlastnika, otvara sa cez docasny overeny hardlink bez nasledovania symlinkov a po otvoreni sa znovu vyzaduje jediny link na stabilnej ceste. Config target musi byt priamy `.cnf` subor v explicitnom `DBTUNE_CONFIG_ALLOWED_DIR` (default `/etc/mysql/mariadb.conf.d`); apply, verify a rollback odmietaju symlink alebo dangling target, target s viac ako jednym hardlinkom, symlink parent komponent, vymeneny parent inode a existujuci target mimo ocakavaneho `root:root 0644` kontraktu. Apply, rollback aj recovery publikuju cez spolocnu `dir_fd` primitivu viazanu na ulozene identity celeho parent retazca. Existujuci target a pripraveny subor vymeni jednym `renameat2(RENAME_EXCHANGE)` commitom; absent target publikuje cez `RENAME_NOREPLACE`. Crash preto ponecha bud povodny, alebo kompletne novy target s jedinym hardlinkom.
- `dbtune_state_read`, `dbtune_state_write`, `dbtune_state_transition`, `dbtune_state_guard` a `dbtune_require_state` implementuju lifecycle `idle -> audited -> collecting -> collected -> analyzed -> proposed -> applied -> verified`, vratane `rolled_back`, `recovery_required` a `rollback_failed`. Novy audit zacina novy cyklus v stave `audited`; pocas recovery stavov je blokovany a existujuca apply recovery historia ostava dostupna. Event log je best-effort a jeho zlyhanie nerusi uz atomicky commitnuty state.
- Audit, collect start/stop, analyze, report, propose, apply, verify a rollback su cez dispatcher serializovane spolocnym exkluzivnym `flock`. Bezny prikaz na lock caka; timerovy `_tick` cakanie nerobi a pri contention bezpecne preskoci tick. Collector si ponechava vlastny interny lock, ktory dispatcher nenahradza.
- `dbtune_atomic_write CESTA [MODE]` cita obsah zo stdin a publikuje ho cez docasny subor v rovnakom adresari.
- `dbtune_is_uint HODNOTA` a `dbtune_require_uint NAZOV HODNOTA [MIN] [MAX]` validuju integer argumenty bez implicitnych Bash konverzii.
- `dbtune_json_escape TEXT` a `dbtune_json_emit KLUC HODNOTA ...` su jediny podporovany sposob tvorby flat JSON. Vsetky emitovane hodnoty su JSON stringy.
- `dbtune_tsv_percentile` je spolocny nearest-rank percentile algoritmus pre rules aj report. Pri 20 hodnotach je p95 devatnasta zoradena hodnota.
- `dbtune_event TYP [KLUC HODNOTA ...]` zapisuje redigovany JSONL do `events.log`; `dbtune_log_*` zapisuje redigovane spravy na stderr. Hesla ani cele credential subory sa nesmu posielat loggeru.
- `dbtune_sql QUERY [DATABASE]` cita query cez stdin klienta. Najprv skusi root `unix_socket`, potom `DBTUNE_ROOT_CNF` (default `/etc/mysql/conf.d/root.cnf`) cez `--defaults-extra-file`. Heslo nikdy nie je na CLI ani v logu a uspesna metoda sa ulozi do state.
- Embedded asset sa cita cez `dbtune_embedded_get templates/tuning.cnf.tmpl`; zoznam poskytne `dbtune_embedded_list`.

### Kontrakt `samples.tsv`

Novy collector zapisuje append-only hlavicku `timestamp, uptime, bp_hit_pct, bp_misses_s, data_read_s, rnd_next_s, tmp_disk_pct, threads_running, threads_connected, qcache_hit_pct, log_waits_delta, wait_free_delta, cpu_pct, mem_available_kb, swap_used_kb, load1, restart_flag, qcache_queries_delta, interval_seconds, sample_status` oddelenu tabulatormi. Prvych 17 stlpcov zostava v povodnom poradi; posledne tri su rozsirujuci kontrakt.

- `qcache_queries_delta` je denominator `Qcache_hits delta + Com_select delta`. Hodnota `0` znamena idle okno a `R-QCACHE` ho nezahrnie do hit-rate percentilu. Pravidlo vyzaduje aspon tolko aktivnych okien, kolko urcuje `--min-samples`; inak emituje `UNKNOWN` bez proposal.
- `interval_seconds` je skutocny monotónny cas medzi dvojicou status/CPU snapshotov, vratane sleepu, scheduler delay a druheho SQL snapshotu. Rates a CPU pouzivaju tento interval, nie nakonfigurovany sleep.
- `sample_status` je `ok` alebo `degraded_interval`. Nečíselny, nerastuci alebo prilis dlhy interval je degraded; predvoleny limit je dvojnasobok `DBTUNE_SAMPLE_SECONDS` a da sa explicitne nastavit cez `DBTUNE_MAX_SAMPLE_INTERVAL_SECONDS`. Degraded a restart riadky sa nepouziju v rules/report metrikach ani v minimalnom pocte validnych vzoriek.
- Kazdy riadok musi mat presne 20 poli: skutocny gregoriansky UTC timestamp vratane spravnych dni v mesiaci a priestupnych rokov, nezaporne numericke metriky, celočíselné countery, `restart_flag` 0/1, kladny `interval_seconds` pre `sample_status=ok` a znamy status. Skratene, rozsirené, nečíselné a inak neplatné riadky sa odmietnu pred readiness, percentilmi a apply gate; ich pocty a dovody zobrazuje `collect status` aj report.
- Legacy 17-stlpcove subory ostavaju kompatibilne pre ostatne pravidla. Kedze neuchovavaju query-cache denominator, `R-QCACHE` pri nich bezpecne vrati `UNKNOWN` bez proposal. Ak upgrade zastihne aktivny legacy collect, prvy novy append atomicky rozsiri jeho hlavicku a stare riadky; povodne metriky ostanu validne a novy denominator v starych riadkoch ostane prazdny.

### Report action kontrakt

Kazdy emitovany per-app rule dostane v Markdown aj JSON rovnake action metadata: `rule_id`, app scope, typ, safety, ciel, prikaz, `destructive=false`, connect/statement timeout, timeout capability a varovanie. Ak je dostupne bezpecne mapovanie, read-only SQL je scopeovane cez `--database` a validovany WordPress prefix. SQL prikaz ma connect timeout 5 sekund a serverovy statement timeout 30 sekund: MariaDB pouziva `max_statement_time`, MySQL `max_execution_time` v milisekundach. Klient pouziva lokalny socket bez hesla v argv; report nevypisuje credential argumenty ani credential subory. Ak rodinu/verziu servera a timeout capability nie je mozne bezpecne urcit, SQL action je `not-executable` a prikaz sa nevygeneruje. wp-cli pouziva kanonicky auditovany `--path` a overeneho nenuloveho vlastnika. Ak WordPress webroot alebo vlastnika nie je mozne bezpecne overit, report nevygeneruje prikaz a action oznaci ako `not-executable`; nepouziva root ani `--allow-root` fallback. Prikazy su navrhy na rucne spustenie: dbtune ich nevykonava a negeneruje automaticky `DELETE`, `DROP` ani `UPDATE`.

Report publikuje nazvy a velkosti zozbieranych top-20 autoload poloziek, nikdy ich hodnoty; citlive nazvy su nahradene `[REDACTED]`. Najhorsie measurement okna obsahuju backup korelaciu s autoritativnym statusom, zdrojom, `last_success`, casovym rozdielom, casom kontroly, poctom planov a process snapshotom z auditu. Korelacia je evidencia, nie dokaz priciny.

Projekt globalne pouziva `set -u`, nie `set -e`. Kniznicove moduly obsahuju iba deklaracie a funkcie; vykonanie programu zabezpecuje jediny guard na konci `lib/90-main.sh`.
