# Audit-only pilot na jednom RunCloud serveri

## Rozsah

Pilot vykona iba jednorazovy read-only audit MariaDB, OS a WordPress aplikacii. Na serveri vytvori iba adresar s binarkou a state subory v `/var/lib/dbtune` s mode `700/600`.

Zakazane v tejto faze:

- `collect start`
- `analyze`, `report` a `propose`
- `apply`, restart MariaDB a `rollback`
- akekolvek upravy `runcloud.cnf`, WordPress databaz alebo aplikacnych suborov

## Vstupne brany

Audit sa nespusti, kym neplati vsetko:

- ciel je Ubuntu 22.04 alebo 24.04 s MariaDB 10.6, 10.11 alebo 11.x,
- MariaDB je `active` a server nema aktivny incident,
- nejde o Galera/wsrep uzol,
- nebezi mydumper, mysqldump ani RunCloud backup,
- na `/` a `/var/lib/mysql` je aspon 1 GB volneho miesta,
- audit prebehne mimo checkout spicky a planovaneho backup okna,
- existuje pristup do RunCloud panela; pre audit sa restart nepouzije.

## Lokalne overenie artefaktu

```bash
make check
make test
(cd dist && shasum -a 256 -c dbtune.sha256)
```

## Read-only preflight

`SERVER` je SSH alias, hostname alebo IP. Heslo ani privatny kluc sa neposielaju v prikaze alebo chate.

```bash
ssh root@SERVER 'uname -a; . /etc/os-release; printf "%s %s\n" "$ID" "$VERSION_ID"; mariadb --version; systemctl is-active mariadb; df -Pk / /var/lib/mysql; pgrep -af "mydumper|mysqldump|mariadb-dump" || true'
```

Ak MariaDB nie je active, bezi backup alebo chyba miesto, pilot sa zastavi.

## Nahratie bez instalacie do PATH

```bash
ssh root@SERVER 'install -d -o root -g root -m 700 /root/dbtune-pilot'
scp dist/dbtune dist/dbtune.sha256 root@SERVER:/root/dbtune-pilot/
ssh root@SERVER '(cd /root/dbtune-pilot && sha256sum -c dbtune.sha256) && chmod 700 /root/dbtune-pilot/dbtune'
```

## Jediny povoleny beh

GNU `timeout` ukonci cely audit, ak by trval viac ako 15 minut. JSON sa zachyti lokalne; stderr zostane viditelny operatorovi.

Query budget auditu je 5 sekund na connect a 5 sekund `max_statement_time` na kazdy read-only SQL statement. Presne full-table pocty su vypnute; velkosti a pocty velkych tabuliek pouzivaju metadata odhady a selektivne WordPress dotazy zostavaju pod rovnakym statement budgetom. Timeout alebo SQL chyba musi byt v TSV ako `unknown` a `audit_error.*`, nie ako nula. Efektivne hodnoty su zapisane v `audit.sql_connect_timeout_seconds`, `audit.sql_statement_timeout_seconds` a `audit.exact_full_table_counts`.

```bash
install -d -m 700 pilot-artifacts
ssh root@SERVER 'timeout --signal=TERM 15m /root/dbtune-pilot/dbtune audit --json' >pilot-artifacts/audit.json
scp root@SERVER:/var/lib/dbtune/audit.tsv pilot-artifacts/
scp root@SERVER:/var/lib/dbtune/apps.tsv pilot-artifacts/
scp root@SERVER:/var/lib/dbtune/databases.tsv pilot-artifacts/
scp root@SERVER:/var/lib/dbtune/events.log pilot-artifacts/
```

## Stop podmienky pocas auditu

Audit sa okamzite ukonci cez `Ctrl-C`, ak:

- narastie load alebo IO wait a ovplyvni shop,
- zacne backup,
- MariaDB prestane odpovedat,
- objavia sa checkout alebo HTTP 5xx chyby,
- audit prekroci 15 minut.

Po ukonceni sa nespusta dalsi subcommand. Najprv sa vyhodnotia lokalne artefakty a landmine/security nalezy.

## Cleanup

Binarka moze do rozhodnutia ostat v root-only adresari. Ak sa pilot zastavi:

```bash
ssh root@SERVER 'rm -rf /root/dbtune-pilot /var/lib/dbtune'
```

Cleanup sa vykona iba po stiahnuti potrebnych auditnych artefaktov.
