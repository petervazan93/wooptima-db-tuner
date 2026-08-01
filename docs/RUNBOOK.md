# dbtune rollout runbook

## Predpoklady

- Spustajte ako `root` na podporovanej MariaDB 10.6 az 11.x, nie na Galera/wsrep uzle.
- Pred pilotom overte obnovitelny databazovy backup, pristup do RunCloud panela a konzolu mimo webu.
- Bezny `apply` ocakava stav `proposed`, aspon 288 validnych vzoriek a `proposal-manifest.tsv`, ktory cez `run_id`, `audit_hash`, `samples_hash`, `analysis_hash` a `proposal_hash` viaze proposal na jeden meraci cyklus.
- Predvoleny ciel je `/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf`. `DBTUNE_CONFIG_TARGET` je urceny pre test alebo explicitne riadene nestandardne instalacie.
- Apply je bez `--force` blokovany v lokalnom case 05:30-07:30 a vzdy blokovany pri Galera alebo beziacom mydumper procese.

## Pilot

1. Vyberte 1-2 servery: jeden MariaDB 10.6 a jeden z rodiny 11.x. Nevyberajte najvacsi obchod ani server bez otestovaneho backupu.
2. Dokoncite `audit`, zber, `analyze`, kontrolu reportu a `propose`. Rucne skontrolujte sizing poolu, `max_connections`, diskovu triedu a aplikacne nalezy.
3. Spustite `dbtune apply`. Nastroj overi vsetky aktivne nazvy z `[mysqld]` jednym dotazom do `information_schema.GLOBAL_VARIABLES`, ulozi baseline a atomicky zapise config ako `root:root 0644`.
4. Precitajte `$STATE/apply/<timestamp>-<pid>/ROLLBACK.txt` este pred restartom. Obsahuje doslovne prikazy a funguje bez dbtune aj bez funkcnej databazy.
5. Bez `--restart` vykonajte restart cez RunCloud `Services -> MariaDB -> Restart`. `--restart` pouzivajte iba na pilotne skriptovanie; vola `systemctl restart mariadb`, kontroluje active stav a pri chybe obnovi config.
6. Pockajte priblizne 5 minut a spustite `dbtune verify --post`. Zlyhanie efektivnych hodnot, `Innodb_buffer_pool_wait_free`, `Innodb_log_waits`, `Aborted_connects`, rast swapu alebo kriticky nizka dostupna RAM je dovod na rollback.
7. Po 24 hodinach a aspon jednej realnej spicke spustite `dbtune verify --24h`. Vystup porovna status a pamat s baseline; reset lifetime countera je oznaceny ako `reset:<hodnota>`.

Prvy start moze pri zmene `innodb_log_file_size` trvat dlhsie. Zvysene `Innodb_buffer_pool_reads` pocas prveho warm-up okna samo osebe nie je regresia.

## Run semantics

- Kazdy uspesny `dbtune audit` vytvori novy `run_id` a `audit_hash`. Audit nemeni MariaDB ani systemovu konfiguraciu, ale publikuje novy meraci cyklus; samostatny prepinac `--new-run` sa nepouziva.
- Audit pocas stavu `collecting` je odmietnuty, aby sa nestratila povodna slow-log recovery konfiguracia. Najprv pouzite `dbtune collect stop`.
- Pri opakovanom audite sa predchadzajuce audit, collect, analysis, report a proposal artefakty skopiruju do `$STATE/runs/<run_id>/`. Aktivne downstream artefakty sa zneplatnia a stav prejde na `audited`.
- `$STATE/apply/` a `$STATE/apply/current` sa novym auditom nemenia. `dbtune status` zobrazi `rollback_available: ano` a rollback zostava dostupny aj po zacati noveho meracieho cyklu; v aktivnom stave `collecting` je z bezpecnostnych dovodov potrebne najprv zastavit collect.
- `analysis-manifest.tsv` musi presne sediet s aktualnym audit runom/hashom, `samples.tsv` a `analysis.tsv`. Report a proposal tento kontrakt znovu overia. Bezny apply overi aj proposal manifest a nasadi sukromny snapshot presne s overenym `proposal_hash`.
- Mutujuce lifecycle prikazy cakaju na spolocny exkluzivny lock. `_tick` je neblokujuci: pri obsadenom lifecycle locku zapise skip event a skonci uspesne, takze systemd timer nevytvara deadlock ani failed unit.

## Force

`--force` obchadza iba chybanie alebo zmenu measurement/analysis manifestu a casove okno. Stale vyzaduje rucne pripraveny proposal a stav `audited|analyzed|proposed`; neobchadza live kontrolu premennych, Galera, mydumper, zapis, validaciu ani rollback ochrany.

Force funguje iba na TTY a vyzaduje presne zadat:

```text
APLIKUJ BEZ MERANIA
```

Pri skutocne chybajucom alebo neplatnom merani dostanu apply historia, `apply-report.md`, existujuci `report.md` a `events.log` oznacenie `BEZ MERANIA`. Force pouzity iba na casove okno sa zaznamena v `apply_completed`, ale report nespravne neoznaci ako nemerany.

## Staging a flotila

1. Po uspesnom pilote nasadte na 5 reprezentativnych serverov, vzdy jednotlivo a mimo backupov.
2. Sledujte ich najmenej 24 hodin. Porovnajte checkout chyby, DB CPU/IO, swap, connection peak, wait-free a log waits.
3. Zvysok flotily robte v davkach najviac priblizne 10 serverov. Dalsiu davku nezacinajte pred `verify --post` predchadzajucej davky.
4. Zachovajte manualny RunCloud restart. Stav kontrolujte cez `dbtune status`; prikaz necita SQL a je pouzitelny aj pri vypadku DB.

## Rollback

Preferovany postup:

```bash
sudo dbtune rollback
```

Rollback najprv presunie nasadeny ciel do apply historie a obnovi povodny subor, ak existoval. Nepouziva SQL. Ak MariaDB nebezi, zavola `systemctl start mariadb`; ak bezi, runtime hodnoty sa bez restartu nezmenia, preto vytvori `RESTART_REQUIRED` a vyziada manualny restart cez RunCloud panel. `dbtune status` tento pending restart zobrazi.

Ak dbtune nie je dostupny, vykonajte riadky z posledneho `$STATE/apply/<timestamp>-<pid>/ROLLBACK.txt`. Neupravujte `runcloud.cnf`.

## Artefakty a limity

- Apply historia sa nikdy neprepisuje. Obsahuje `manifest.tsv` s run/audit/proposal hashmi, nemenny nasadeny `proposed.cnf`, volitelny `original.cnf`, baseline, validacne/rollback artefakty a `ROLLBACK.txt`.
- `verify --24h` porovnava lifetime countery a rozpozna ich reset, ale nenahradza kratke 60-sekundove delty collectora ani aplikacny monitoring.
- Validacia capability-probne `mariadbd --validate-config`; na verzii bez tejto volby pouzije parser vystupu `mariadbd --help --verbose`. Dokumentovane lock/Aria/InnoDB init chyby beziaceho servera toleruje, ostatne `[ERROR]`, unknown, invalid a value chyby odmietne.
- Docker integration spusta realny `dist/dbtune` na MariaDB 10.6 aj 11.4 cez audit, kratky fake-timer zber, analyze, report, propose, apply, restart kontajnera a `verify --post`. Systemd-in-container nahradza iba minimalny stub; realny systemd timer a produkcne data musi potvrdit pilot.
