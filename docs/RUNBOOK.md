# dbtune rollout runbook

## Predpoklady

- Spustajte ako `root` na podporovanej MariaDB 10.6, 10.11 alebo 11.x, nie na Galera/wsrep uzle. Pre `apply`, rollback a crash recovery musi byt dostupny `python3` s podporou `dir_fd` a Linux `renameat2`.
- Pred pilotom overte obnovitelny databazovy backup, pristup do RunCloud panela a konzolu mimo webu. Lokalne cron zaznamy nie su dokaz uspesnej RunCloud zalohy.
- Bezny `apply` ocakava stav `proposed`, aspon 288 validnych vzoriek a `proposal-manifest.tsv`, ktory cez `run_id`, `audit_hash`, `samples_hash`, `analysis_hash` a `proposal_hash` viaze proposal na jeden meraci cyklus.
- Predvoleny ciel je `/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf` a povoleny adresar `/etc/mysql/mariadb.conf.d`. Nestandardny `DBTUNE_CONFIG_TARGET` vyzaduje aj explicitny `DBTUNE_CONFIG_ALLOWED_DIR`; target musi byt priamy `.cnf` v tomto adresari. Apply, verify a rollback odmietaju target symlink, dangling symlink, viac ako jeden stabilny hardlink, symlink parent komponent, vymenu parent adresara pocas apply a existujuci subor mimo `root:root 0644` kontraktu. State a lifecycle lock subor musia mat na stabilnej ceste presne jeden hardlink. Managed config publication pouziva atomicky exchange alebo no-replace rename, preto target nema ani pocas crash hranice docasny druhy hardlink.
- Apply je bez `--force` blokovany v lokalnom case 05:30-07:30 a vzdy blokovany pri Galera, beziacom mydumper procese alebo autoritativnom backup stave `missing`. Apply aj `--force` vyzaduju platny backup evidence artefakt alebo samostatne bezpecnostne potvrdenie na TTY.

## Pilot

1. Vyberte 1-2 servery: jeden MariaDB 10.6 a jeden z rodiny 11.x. Nevyberajte najvacsi obchod ani server bez otestovaneho backupu.
2. Dokoncite `audit`, zber, `analyze`, kontrolu reportu a `propose`. Rucne skontrolujte sizing poolu, `max_connections`, diskovu triedu a aplikacne nalezy.
   Report musi mat pre kazdu aktivnu serverovu zmenu znamu current hodnotu. Chybajuca current, unsafe proposal alebo aliasovy duplikat ako `max_connections`/`max-connections` je chyba vstupu, nie polozka na preskocenie.
3. Spustite `dbtune apply`. Nastroj overi samostatny backup evidence, vsetky aktivne nazvy z `[mysqld]` jednym dotazom do `information_schema.GLOBAL_VARIABLES`, ulozi baseline a atomicky zapise config ako `root:root 0644`.
4. Precitajte `$STATE/apply/<timestamp>-<pid>/ROLLBACK.txt` este pred restartom. Obsahuje doslovne prikazy a funguje bez dbtune aj bez funkcnej databazy.
5. Bez `--restart` vykonajte restart cez RunCloud `Services -> MariaDB -> Restart`. `--restart` pouzivajte iba na pilotne skriptovanie; vola `systemctl restart mariadb`, kontroluje active stav a pri chybe obnovi config.
6. Pockajte priblizne 5 minut a spustite `dbtune verify --post`. Verify najprv overi regularny nesymlinkovy target, `root:root 0644` a hash presne nasadeneho snapshotu. Potom kontroluje efektivne hodnoty a rast `Innodb_buffer_pool_wait_free`, `Innodb_log_waits`, `Aborted_connects` oproti reset-aware baseline, rast swapu a kriticky nizku dostupnu RAM. Zlyhanie je dovod na rollback.
7. Po 24 hodinach a aspon jednej realnej spicke spustite `dbtune verify --24h`. Vystup porovna status a pamat s baseline; reset lifetime countera je oznaceny ako `reset:<hodnota>`.

Prvy start moze pri zmene `innodb_log_file_size` trvat dlhsie. Zvysene `Innodb_buffer_pool_reads` pocas prveho warm-up okna samo osebe nie je regresia.

## Run semantics

- Kazdy uspesny `dbtune audit` vytvori novy `run_id` a `audit_hash`. Audit nemeni MariaDB ani systemovu konfiguraciu, ale publikuje novy meraci cyklus; samostatny prepinac `--new-run` sa nepouziva.
- Povinne autoritativne sekcie su `mariadb`, `hardware`, `applications` a `security`. `PASS` znamena kompletne sekcie bez nalezov, `FINDINGS` kompletne sekcie s nalezmi, `UNKNOWN` ciastocne alebo zlyhane povinne dokazy pri zachovani casti auditu a `ERROR` zlyhanie vsetkych povinnych sekcii. Text, audit JSON aj report uvadzaju zlyhane/ciastocne sekcie a ovplyvnene domeny odporucani.
- MariaDB evidence schema je jedinym zdrojom pre audit query, proposal current kluce, datove domeny a verziove gate. Pred pokracovanim musia byt `audit.section.mariadb.missing_evidence`, `invalid_evidence` a `conflicting_evidence` rovne `none`; `optional_evidence` vysvetluje verziovo nepovinny vstup. Diagnostika nikdy neobsahuje odmietnutu hodnotu.
- Klasifikovany audit vracia `0` pre `PASS`/`FINDINGS`, `2` pre `UNKNOWN` a `1` pre `ERROR`. Usage, validacne, dependency a ine technicke zlyhania mozu pouzit existujuce exit kody `64+`; automatizacia ich nesmie interpretovat ako auditnu klasifikaciu. Pri klasifikovanom `UNKNOWN`/`ERROR` zostanu diagnosticke artefakty publikovane, ale meraci cyklus nepovazujte za autoritativny a nepokracujte automaticky.
- Audit pocas stavu `collecting` je odmietnuty, aby sa nestratila povodna slow-log recovery konfiguracia. Najprv pouzite `dbtune collect stop`.
- Pri opakovanom audite sa predchadzajuce audit, collect, analysis, report a proposal artefakty skopiruju do `$STATE/runs/<run_id>/`. Aktivne downstream artefakty sa zneplatnia a stav prejde na `audited`.
- `$STATE/apply/` a `$STATE/apply/current` sa novym auditom nemenia. `dbtune status` zobrazi `rollback_available: ano` a rollback zostava dostupny aj po zacati noveho meracieho cyklu; v aktivnom stave `collecting` je z bezpecnostnych dovodov potrebne najprv zastavit collect.
- `analysis-manifest.tsv` musi presne sediet s aktualnym audit runom/hashom, `samples.tsv` a `analysis.tsv`. Report a proposal tento kontrakt znovu overia. Bezny apply overi aj proposal manifest a nasadi sukromny snapshot presne s overenym `proposal_hash`.
- `proposal-manifest.tsv` navyse viaze `proposal_count` a `proposal_records_hash` na kanonicky zoznam. Apply porovna tento zoznam s analysis aj skutocnymi CNF klucmi a hodnotami.
- Mutujuce lifecycle prikazy cakaju na spolocny exkluzivny lock. `_tick` je neblokujuci: pri obsadenom lifecycle locku zapise skip event a skonci uspesne, takze systemd timer nevytvara deadlock ani failed unit.
- `samples.tsv` od noveho collectoru pridava za povodnych 17 stlpcov `qcache_queries_delta`, `interval_seconds` a `sample_status`. Iba `sample_status=ok` bez `restart_flag` sa rata medzi validne vzorky. `degraded_interval` znamena neplatny alebo prilis dlhy monotónny interval a nesmie vstupit do rules/report metrík; query-cache percentile navyse pouziva iba okna s `qcache_queries_delta > 0`.

## Force

`--force` obchadza iba chybanie alebo zmenu measurement/analysis manifestu a casove okno. Stale vyzaduje rucne pripraveny proposal a stav `audited|analyzed|proposed`; neobchadza live kontrolu premennych, Galera, mydumper, backup evidence, zapis, validaciu ani rollback ochrany.

Force funguje iba na TTY a vyzaduje presne zadat:

```text
APLIKUJ BEZ MERANIA
```

Nezavisle od force musi `$STATE/backup-evidence.tsv` obsahovat `schema`, `status`, `source`, `checked_at` a `last_success`, byt regularny nesymlinkovy subor vlastneny aktualnym root procesom s mode `0600` alebo `0400`. `verified` vyzaduje `source` a platny UTC cas posledneho uspesneho behu, ktory nie je v buducnosti ani starsi ako `DBTUNE_MAX_BACKUP_AGE_SECONDS` (predvolene 86400 sekund, vratane presnej hranice). Existujuci neplatny, buduci alebo expirovany artefakt blokuje apply a chyba uvadza vyhodnoteny `age_seconds` a `max_age_seconds`. `missing` znamena potvrdenu absenciu a apply blokuje. Pri chybajucom alebo platnom `unknown` artefakte je potrebna druha samostatna TTY fraza:

```text
POTVRDZUJEM OBNOVITELNU ZALOHU
```

Pri skutocne chybajucom alebo neplatnom merani dostanu apply historia, `apply-report.md`, existujuci `report.md` a `events.log` oznacenie `BEZ MERANIA`. Force pouzity iba na casove okno sa zaznamena v `apply_completed`, ale report nespravne neoznaci ako nemerany.

## Staging a flotila

1. Po uspesnom pilote nasadte na 5 reprezentativnych serverov, vzdy jednotlivo a mimo backupov.
2. Sledujte ich najmenej 24 hodin. Porovnajte checkout chyby, DB CPU/IO, swap, connection peak, wait-free a log waits.
3. Zvysok flotily robte v davkach najviac priblizne 10 serverov. Dalsiu davku nezacinajte pred `verify --post` predchadzajucej davky.
4. Zachovajte manualny RunCloud restart. Stav kontrolujte cez `dbtune status`; prikaz necita SQL a je pouzitelny aj pri vypadku DB.

Per-app action kroky z reportu su copy-paste read-only diagnostika. Pred spustenim skontrolujte `target` (app, path, database a prefix) a shell quoting. dbtune ich automaticky nespusta; cleanup, migraciu, `DELETE`, `DROP` ani `UPDATE` nevykonavajte bez samostatneho review, overenej obnovitelnej zalohy a maintenance planu. Top autoload sekcia obsahuje iba nazvy a velkosti. Backup korelacia pri najhorsich oknach porovnava dostupnu evidenciu, ale sama nepotvrdzuje kauzalitu.

## Rollback

Preferovany postup:

```bash
sudo dbtune rollback
```

Rollback pri povodne absent targete presunie nasadeny regularny subor do apply historie a ponecha target absent. Pri povodnom regularnom targete najprv zachova nasadeny subor v historii a povodny snapshot publikuje atomicky; symlinky neobnovuje ani nenasleduje. Nepouziva SQL. Ak MariaDB nebezi, zavola `systemctl start mariadb`; ak bezi, runtime hodnoty sa bez restartu nezmenia, preto vytvori `RESTART_REQUIRED` a vyziada manualny restart cez RunCloud panel. `dbtune status` tento pending restart zobrazi.

Ak filesystem restore zlyha, `apply/current` ostane na problemovej historii, stav bude `recovery_required` alebo `rollback_failed` a `dbtune status` vypise `sudo dbtune rollback` aj cestu k `ROLLBACK.txt`. Pointer ani predchadzajuci state sa po zlyhanom apply nerestartuju naslepo; obnovia sa az po potvrdenom restore.

Ak dbtune nie je dostupny, vykonajte riadky z posledneho `$STATE/apply/<timestamp>-<pid>/ROLLBACK.txt`. Neupravujte `runcloud.cnf`.

## Artefakty a limity

- Apply historia sa nikdy neprepisuje. Obsahuje `manifest.tsv` s nemennym `cycle_id`, run/audit/proposal a backup evidence hashmi aj povodom config backupu, nemenny nasadeny `proposed.cnf`, snapshot backup evidence alebo zaznam interaktivneho potvrdenia, volitelny `original.cnf`, baseline, validacne/rollback artefakty a `ROLLBACK.txt`.
- Rollback pred prvou zmenou targetu durable publikuje `rollback-intent.tsv`. Po preruseni nasledujuci zamknuty lifecycle prikaz idempotentne dokonci restore, `ROLLBACK_COMPLETED.tsv`, `apply/last-rollback`, `apply/current` a stav `rolled_back`; journal odstrani az po synchronizacii vsetkych krokov. Pri obnove configu z predchadzajuceho apply cyklu ukazuje `apply/current` na presne tento cyklus, zatial co `apply/last-rollback` a completion metadata zachovavaju rollbacknuty cyklus, pouzity backup a hash.
- Prvy uspesny `verify --post` ulozi `post-status.tsv` ako post-restart baseline. Dalsi `verify --post` aj `verify --24h` hodnotia health lifetime countery voci tejto baseline; `--24h` bez uspesneho `--post` zlyha. Pri poklese uptime alebo countera sa pouzije reset baseline nula. Nezmenena nenulova hodnota preto prejde, rast zlyha a reset na nulu prejde. Nenahradza to kratke 60-sekundove delty collectora ani aplikacny monitoring.
- Validacia capability-probne `mariadbd --validate-config`; na verzii bez tejto volby pouzije parser vystupu `mariadbd --help --verbose`. Dokumentovane lock/Aria/InnoDB init chyby beziaceho servera toleruje, ostatne `[ERROR]`, unknown, invalid a value chyby odmietne.
- Docker integration spusta realny `dist/dbtune` na MariaDB 10.6 aj 11.4 cez audit, kratky fake-timer zber, analyze, report, propose, apply, restart kontajnera a `verify --post`. Systemd-in-container nahradza iba minimalny stub; realny systemd timer a produkcne data musi potvrdit pilot.
