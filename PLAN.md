# Plán: `dbtune` — audit & tuning nástroj pre MariaDB na RunCloud flotile

## Kontext

Máme ~40 dedikovaných serverov (Hetzner, Ubuntu 22.04/24.04) spravovaných cez RunCloud, všetky hostujú WordPress + WooCommerce eshopy (DB typicky 3–15 GB, MariaDB 10.6–11.x, niekedy 2–3 eshopy na jednom serveri so zdieľanou MariaDB inštanciou). MariaDB všade beží na RunCloud defaultoch (buffer pool 128M, max_connections 4096, trxcommit=2…), čo je pre ecommerce záťaž nevhodné.

Cieľ: nástroj, ktorý na každom serveri **zaudituje** prostredie, **pozbiera** metriky z ostrej prevádzky (default 7 dní), **vyhodnotí** ich podľa metodiky z [mariadb-runcloud-preset.md](mariadb-runcloud-preset.md) a **navrhne** personalizovaný config + per-app odporúčania, s bezpečným apply/rollback.

**Odsúhlasené rozhodnutia:**
- v1 = standalone per-server; report aj ako JSON (flat keys) → budúca fleet agregácia v v2 bez prerábania
- reštart MariaDB vždy manuálne cez RunCloud panel (tool len inštruuje; `--restart` flag len pre pilotné skriptovanie)

## Forma toolu

**Jeden samostatný bash skript `dbtune`** so subcommands, vyvíjaný modulárne (`lib/*.sh`) a build krokom spájaný do jedného artefaktu `dist/dbtune`.

Prečo bash (potvrdené aj architektonickou analýzou): ~90 % práce je volanie `mariadb -Nse`, `systemctl`, `lsblk`, `free` + formátovanie textu; podkladový MD je už bash-native (1:1 kodifikácia = menej translačných chýb); jeden greppateľný súbor je na flotile s root SSH debugovateľný priamo na mieste; žiadny runtime skew medzi Ubuntu 22/24.

Disciplína, ktorá robí bash bezpečným: všetka aritmetika cez awk (žiadne delenie v bashi), JSON len cez jeden testovaný emitter, `set -u` globálne, `shellcheck` + `bats` povinné, lib moduly obsahujú len funkcie (žiadna top-level exekúcia) — vďaka čomu je build obyčajná konkatenácia a unit testy per-modul.

- **Nasadenie:** `scp dist/dbtune server:/usr/local/bin/dbtune` — jeden súbor.
- **Stav a dáta:** `/var/lib/dbtune/` (mode 700; audit, vzorky, analýzy, reporty, apply história, events.log).
- **Výstupy:** Markdown report v slovenčine + terminálový súhrn + strojový JSON.

## CLI a state machine

```
dbtune audit [--json]                 # read-only audit, spustiteľný kedykoľvek
dbtune collect start [--days N]       # default 7; --long-query-time pre deep režim
dbtune collect status | stop
dbtune analyze [--min-samples N]      # vyžaduje ≥ ~1 deň vzoriek
dbtune report | propose
dbtune apply [--restart] [--force]
dbtune verify --post | --24h
dbtune rollback
dbtune status | version
dbtune _tick                          # interné, volá systemd timer
```

Stavy: `idle → audited → collecting → collected → analyzed → proposed → applied → verified` (+ `rolled_back`, `recovery_required`, `rollback_failed`). Neplatný príkaz v danom stave = zrozumiteľné odmietnutie. **`apply` bez merania je zablokovaný** („preset bez merania je hádanie") — `--force` vyžaduje napísanie potvrdzovacej frázy a report dostane pečiatku „BEZ MERANIA". Apply aj force navyše vyžadujú samostatný autoritatívny backup evidence alebo druhé explicitné TTY potvrdenie.

## Fáza AUDIT (read-only)

- **HW:** CPU, RAM, swap, disky (ROTA + NVMe detekcia, vrátane md RAID cez slave devices), voľné miesto.
- **MariaDB:** verzia → verzálne brány; efektívne premenné; **landmine scan** existujúcich configov na premenné odstránené v novších verziách (`innodb_change_buffering` na 11.x = kritický nález — server by po najbližšom reštarte nenaštartoval; ďalej `innodb_buffer_pool_instances`, `innodb_log_files_in_group`…).
- **RunCloud vrstva:** runcloud.cnf hodnoty, `skip-log-bin`, query cache hit rate, `open_files_limit` vs systemd `LimitNOFILE`, unattended-upgrades origin „MariaDB:", backup (mydumper) frekvencia, wp-cron setup, performance_schema, Galera detekcia (→ apply sa odmietne).
- **Aplikácie:** `/home/*/webapps/*` → WP detekcia, tolerantný wp-config parser (define/const/env varianty, custom prefix, multisite; fallback cez wp-cli ak existuje, inak SHOW TABLES); WooCommerce, Redis + `object-cache.php` drop-in, page cache. Non-WP appky sa označia, ich DB sa započíta do sizingu.
- **Per-DB:** dataset, top tabuľky, `kb_per_row` log-detektor, autoload, HPOS, sessions, Action Scheduler (vrátane failed), transienty, cudzie indexy na postmeta.
- **PHP-FPM:** suma `pm.max_children` cez všetky verzie a pooly (OLS stack → warning, formula input chýba).
- **Bezpečnostná mini-kontrola:** bind-address, wildcard granty, root.cnf poznámka. Reporty nikdy neobsahujú heslá.
- **Root auth probe:** unix_socket → root.cnf defaults-extra-file; metóda sa zapamätá, heslo nikdy na command line ani v logoch.

## Fáza COLLECT

- **systemd oneshot service + timer** (`OnCalendar=*:0/5`, `Persistent=false`, enabled → prežije reboot = automatické pokračovanie po prerušení). Tick: `flock`, **vždy exit 0** (zdravie sa sleduje v health súbore, nie vo failed unite).
- Každý tick = **60 s dvojbodová delta** (2× jeden SQL round-trip GLOBAL STATUS + /proc CPU mariadbd + free + loadavg) → riadok do `samples.tsv`: BP hit ratio v krátkom okne, missy/s, data_read/s, `Handler_read_rnd_next`/s, tmp disk %, Threads_running/connected, qcache aj jeho denominator, log_waits, wait_free, CPU %, RAM/swap, restart_flag, skutocny monotónny interval a sample status. Rates a CPU pouzivaju realny interval vratane SQL/scheduler delay; neplatne alebo prilis dlhe intervaly su degraded a rules ich nepouziju. 7 dní ≈ 500 KB.
- **Slow log** runtime (`long_query_time=2` do `/var/log/mysql/slow.log` kvôli logrotate pokrytiu). **Self-healing:** tick deteguje reset uptime (unattended-upgrades reštart) → znovu zapne slow log + event `db_restart_detected`; restart_flag umožní analyze správne segmentovať lifetime countery.
- **Denne:** per-DB snapshot veľkostí → `dbsize.tsv` (growth rate pre rezervu na expanziu); disk guardy (voľné miesto, veľkosť samples, slow log > 2 GB watchdog).
- **Auto-stop** po `--days` + automatický `analyze` + `report` — po týždni na serveri čaká hotový report.

## Fáza ANALYZE — rules engine

Jednotný kontrakt: každé pravidlo emituje záznam `rule_id | scope (server/app:X) | severity | verdikt | proposed_key/value | evidencia | odôvodnenie po slovensky`. REPORT renderuje všetky záznamy, PROPOSE konzumuje len server-scope záznamy s proposed_key — report a cnf sa nikdy nerozídu.

**Server pravidlá** (priama kodifikácia MD): `R-BP-SIZE` (`min((dataset + 6-mes. rast)×1,3 ; RAM×0,5)`, zaokrúhlené, growth vyžaduje ≥5 denných bodov, **nikdy nenavrhne zmenšenie** existujúceho poolu, guard na MemAvailable), `R-MAXCONN` (`max(Σpm.max_children×1,25+20 ; 100)` + cross-check nameraného peaku), `R-IO-CAP` (NVMe/SSD/HDD triedy + flush_neighbors gate), `R-LOG-FILE`/`R-LOG-BUF` (512M/1G; 64M log buffer len ak namerané log_waits>0), `R-QCACHE` (presná matica z MD: hit rate × Threads_running p95, nikdy plošne), `R-TRXCOMMIT` (=1 povinný kvôli skip-log-bin), `R-PINNED` (O_DIRECT, dirty pct/lwm, lock_wait_timeout=30, skip_name_resolve, tmp 64M s LONGTEXT poznámkou…), `R-MYISAM`, `R-SLOWLOG`, `R-UNATT` (blacklist odporúčanie), `R-OPENFILES`, `R-SEC`, `R-BACKUP`.

**Verzálne brány — dve vrstvy:** (1) statická gate tabuľka (rodiny 10.6 / 10.11 / 11.x — napr. change_buffering odstránené v 11.0, log_file_size dynamický od 10.9, io_threads dynamické od 10.11, query cache existuje v celom rozsahu, flush_method deprecated v 11.x; mariadb/mysql binárne názvy fallback), (2) **živá autoritatívna kontrola** — pred apply každý názov premennej overený proti `information_schema.GLOBAL_VARIABLES`.

**Per-app nálezy so severitou** (len odporúčania, tool nikdy nezapisuje do WP databáz):
- *critical:* chýbajúci object cache (rozlíšené: Redis nebeží vs drop-in chýba); wp-cron úplne vypnutý
- *high:* autoload > 3 MB (+top 20), HPOS vypnutý pri objednávkach v postmeta, log tabuľky kb_per_row > 20
- *medium:* autoload 1–3 MB, HPOS sync duplikátne zápisy, failed AS akcie, rogue meta_value index, Redis eviction policy
- *low:* AS retention 30d → 7d (explicitne nie 1d)

Report drží filozofiu MD: sekcia „aplikačná vrstva — rieš PRVÚ" ide pred DB config návrhom.

## REPORT + PROPOSE

- **Executive summary** (top akcie podľa dopadu) → **server sekcia** (HW, profil záťaže: percentily, najhoršie okná, korelácia s backupmi; navrhnutý config ako **diff proti aktuálnym efektívnym hodnotám** s per-hodnota odôvodnením) → **per-app sekcie** (nálezy + copy-paste SQL/wp-cli kroky).
- `proposed-99-zz-tuning.cnf` renderovaný z template (Krok 2 z MD) + `report.json`.

## APPLY / VERIFY / ROLLBACK — obrana do hĺbky

1. Pre-write kontrola názvov premenných proti živej information_schema.
2. Zápis **len** `/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf` (runcloud.cnf sa nikdy nedotkne) + `mariadbd --validate-config` s parserom z MD (ignoruje lock chyby bežiaceho servera, capability-probed).
3. Guard proti unattended-upgrades oknu (apply sa odmietne 05:30–07:30 bez --force) + kontrola bežiaceho mydumper backupu v processliste pred pokynom na reštart.
4. Reštart decoupled: apply vypíše presné inštrukcie pre RunCloud panel + očakávania (dlhší prvý štart pri zmene redo logu) + **`ROLLBACK.txt` s doslovnými príkazmi** — recovery nevyžaduje ani samotný tool.
5. `rollback` = čisto filesystem operácia (mv + systemctl start), žiadne SQL — funguje aj s ležiacou DB.
6. `verify --post` (bez rastu wait_free, log_waits a aborted oproti reset-aware baseline, swap stabilný, ulozenie post-restart baseline) a `verify --24h` (porovnanie proti uspesnej post-restart baseline).

## Repo štruktúra a testy

```
lib/00-header … 90-main.sh   # číslované moduly, len funkcie
templates/tuning.cnf.tmpl    # Krok 2 z MD s placeholdermi
build.sh + Makefile          # konkatenácia + embed templates/units, bash -n, shellcheck, sha256
test/stubs/                  # fake mariadb, systemctl, lsblk, free…
test/fixtures/               # zachytené GLOBAL STATUS/VARIABLES pre 10.6 aj 11.4, wp-config varianty,
                             # runcloud confy, fpm pooly, lsblk profily, 7-dňové syntetické samples
test/unit/*.bats             # formuly, qcache matica, version gates, delta math, parser, state machine
test/integration/            # docker-compose: mariadb 10.6 + 11.4 + ubuntu SUT, seedovaná WP/Woo schéma,
                             # fake-timer tick loop (systemd-in-docker skip na macOS), plný lifecycle
docs/RUNBOOK.md
```

## Postup implementácie

1. Repo skeleton + build pipeline + state machine + util/log/sql vrstva
2. Audit modul (detect + apps + per-DB)
3. Collector (systemd, tick, self-healing, guardy)
4. Rules engine + verzálne brány (srdce toolu)
5. Report + propose
6. Apply / verify / rollback
7. Testy (fixtures, bats, docker harness) — priebežne popri moduloch
8. RUNBOOK: pilot na 1–2 serveroch (jeden per MariaDB rodina, s overenými backupmi) → stage 5 serverov → zvyšok flotily v dávkach ~10, apply vždy manuálne per server

Moduly 2–5 viem po skelete vyvíjať paralelne cez sub-agentov s finálnou integráciou a review.

## Verifikácia

- `shellcheck` čistý, `bats` zelené na fixtures oboch MariaDB rodín, emitovaný JSON validovaný.
- Docker harness: plný lifecycle audit → ticky → analyze → report → propose → validate cnf v DB kontajneri → apply + reštart + verify --post.
- Reálny pilot: 1 server z flotily, porovnanie auditu s ručnými meraniami z referenčného shopu v MD.

## Mimo rozsah v1

- Centrálna fleet agregácia (v2 — JSON reporty pripravené)
- Automatické app-layer fixy (Redis inštalácia, autoload čistenie, HPOS migrácia) — len odporúčania s návodom
- Galera setupy (apply sa na nich odmietne)
