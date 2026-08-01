# Tuning preset pre WooCommerce na RunCloud

Kompletný postup ladenia výkonu: **aplikačná vrstva → MariaDB config → monitoring**.
Overené na MariaDB 11.4.12 / Ubuntu 24.04 (noble) / RunCloud agent.

Postavené na reálnej analýze produkčného eshopu (3,5 GB dataset, 6M riadkov `postmeta`).
Referenčné merania sú v prílohe na konci.

---

## Poradie práce — a prečo práve takto

**Aplikačná vrstva ide prvá.** Object cache dotazy *odstráni*, buffer pool ich len
*zlacní*. Ak najprv naladíš DB, schováš si problém pod RAM a nikdy sa nedozvieš,
že polovica dotazov tam vôbec nemusela byť.

```
ČASŤ I    Aplikačná vrstva     ← object cache, autoload, HPOS, odpad v tabuľkách
ČASŤ II   MariaDB config       ← meranie, výpočet, nasadenie
ČASŤ III  RunCloud špecifiká   ← pasce, ktoré budú na každom ich serveri
ČASŤ IV   Monitoring
ČASŤ V    Diagnostika
ČASŤ VI   Čo NEROBIŤ           ← rozšírené anti-patterny z internetu
```

Typický profil, na ktorý je preset stavaný: RunCloud server, MariaDB 10.6+, WooCommerce,
jedna hlavná DB od ~1 GB vyššie, RAM aspoň 8 GB, symptóm = MariaDB žerie CPU.

**Nepoužívaj bez merania.** Veľkostné hodnoty sa musia počítať z reálnych čísel
daného servera. Preset bez merania je hádanie.

---

# ČASŤ I — Aplikačná vrstva

## Krok A — Object cache (najväčší pákový efekt)

Bez object cache **každý request**:
- načíta celý `wp_options` autoload z DB
- pošle každý `get_option()` a `get_transient()` do MariaDB
- zapisuje transienty do `wp_options` → ďalšie zápisy

Prejaví sa to ako **stovky rýchlych dotazov na request**, ktoré slow log nikdy
nezachytí (žiaden neprekročí prah), ale v súčte tvoria podstatnú časť CPU.
Typický ukazovateľ: `Handler_read_rnd_next` v desiatkach tisíc riadkov/s aj v kľude.

### Kontrola

```bash
systemctl is-active redis redis-server
redis-cli ping
ls -la /path/to/webroot/wp-content/object-cache.php
grep -iE "WP_REDIS|WP_CACHE" /path/to/webroot/wp-config.php
ls -d /path/to/webroot/wp-content/plugins/*redis*
```

**`object-cache.php` musí existovať.** Je to drop-in, ktorý plugin nainštaluje —
bez neho WordPress žiadny persistent object cache nepoužíva, aj keby Redis bežal.

### Pozor na zámenu

| | Čo rieši | Čo NErieši |
|---|---|---|
| **Page cache** (WP Rocket, nginx fastcgi_cache) | anonymná návštevnosť | prihlásení, košík, checkout, admin, AJAX |
| **Object cache** (Redis) | `get_option`, transienty, WP_Query cache — **pre všetkých** | HTML rendering |

`WP_CACHE = true` v `wp-config.php` znamená page cache, **nie** object cache.
Tie dve sa nezastupujú.

### Redis konfigurácia pre eshop

```
maxmemory-policy volatile-lru
```

Zabráni tomu, aby sa pri tlaku na pamäť vyhodili session dáta (= stratené košíky).
Kontrola evikcií:

```bash
redis-cli INFO stats | grep evicted_keys
redis-cli INFO memory | grep used_memory_human
```

Dimenzovanie: alokuj aspoň **2× typický `used_memory`**. Orientačne — `wp_alloptions`
0,5–2 MB, WooCommerce session 2–5 KB each, 5 000 produktov ~50 MB.

---

## Krok B — Autoload audit

Autoloadované options sa načítajú **pri každom page loade**. Nad ~1 MB to začne byť cítiť,
a bez object cache to ide priamo z DB zakaždým.

```sql
-- celkova velkost
SELECT ROUND(SUM(LENGTH(option_value))/1024/1024,2) AS autoload_mb, COUNT(*) AS cnt
FROM wp_options WHERE autoload IN ('yes','on','auto');

-- top offenderi
SELECT option_name, ROUND(LENGTH(option_value)/1024,1) AS kb
FROM wp_options WHERE autoload IN ('yes','on','auto')
ORDER BY LENGTH(option_value) DESC LIMIT 20;
```

> **Pozn.:** WordPress 6.6+ používa hodnoty `yes`/`no`/`on`/`off`/`auto`.
> Starší dotaz s `autoload='yes'` časť dát minie.

| Autoload | Verdikt |
|---|---|
| < 1 MB | OK |
| 1–3 MB | prejdi top 20, vypni čo netreba |
| > 3 MB | rieš prioritne |

Typickí vinníci: XML feed cache (Heureka, Glami, Google), prekladové cache (Weglot,
WPML), staré `_transient_*` bez expirácie, options po odinštalovaných pluginoch.

Vypnutie autoloadu pre konkrétnu option:
```sql
UPDATE wp_options SET autoload = 'no' WHERE option_name = 'nazov_option';
```
*(Over najprv, či ju plugin nečíta na každom requeste — vtedy by to uškodilo.)*

### Skryté zápisy do wp_options

`update_option()` na **akúkoľvek** autoloadovanú option invaliduje celý `alloptions`
cache. Plugin, ktorý zapisuje pri každom requeste, ti tak zabije object cache.

Hľadanie cez `SAVEQUERIES` v `wp-config.php` (len dočasne, na staging):
```php
define('SAVEQUERIES', true);
// potom v päte: grep cez $wpdb->queries na UPDATE.*wp_options
```

Časté zdroje: analytické pluginy, rate limitery, `woocommerce_tracker_last_send`,
`_transient_wc_count_comments`.

---

## Krok C — HPOS (High-Performance Order Storage)

```sql
SELECT option_name, option_value FROM wp_options WHERE option_name IN (
  'woocommerce_custom_orders_table_enabled',
  'woocommerce_custom_orders_table_data_sync_enabled',
  'woocommerce_feature_custom_order_tables_enabled');

SELECT COUNT(*) FROM wp_wc_orders;          -- HPOS tabulka
SELECT post_type, COUNT(*) FROM wp_posts WHERE post_type LIKE 'shop_order%' GROUP BY post_type;
```

| Stav | Akcia |
|---|---|
| `enabled = no`, objednávky v `wp_posts`/`wp_postmeta` | **Migrácia na HPOS** = najväčšia štrukturálna úspora. Samostatný projekt, nie súčasť tuningu. |
| `enabled = yes`, `data_sync = yes` | **Vypni sync** po overení — inak sa každá objednávka zapisuje dvakrát (WooCommerce → Settings → Advanced → Features) |
| `enabled = yes`, `data_sync = no` | OK |

Pri vypnutom HPOS tvoria objednávky drvivú väčšinu `postmeta`. Na referenčnom shope:
92 288 `shop_order` postov → 6,08M riadkov `postmeta` (1 443 MB).

---

## Krok D — Odpad v tabuľkách

```sql
-- Sessions (problem az od ~500K riadkov)
SELECT COUNT(*) FROM wp_woocommerce_sessions;

-- Action Scheduler
SELECT status, COUNT(*) FROM wp_actionscheduler_actions GROUP BY status;
SELECT hook, status, COUNT(*) c FROM wp_actionscheduler_actions
  GROUP BY hook, status ORDER BY c DESC LIMIT 20;

-- Transienty v DB (bez object cache tam zostavaju)
SELECT COUNT(*) cnt, ROUND(SUM(LENGTH(option_value))/1024/1024,2) mb
FROM wp_options WHERE option_name LIKE '_transient%';

-- Log tabulky pluginov — casto najvacsi jednotlivy zrut
SELECT TABLE_NAME, TABLE_ROWS, ROUND((data_length+index_length)/1024/1024,1) mb,
       ROUND((data_length+index_length)/NULLIF(TABLE_ROWS,0)/1024,1) kb_per_row
FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME REGEXP 'log|history|track|event'
ORDER BY (data_length+index_length) DESC;
```

**`kb_per_row` je dobrý detektor.** Bežná tabuľka má jednotky KB/riadok. Ak vidíš
20+ KB/riadok, je to log s plnými telami (emaily, requesty, response payloady) —
kandidát na purge.

### Action Scheduler retention

Default drží dokončené akcie 30 dní. Skrátenie pomôže, ale **1 deň (častá rada
z internetu) je príliš** — prídeš o možnosť debugovať zlyhané akcie.

```php
add_filter('action_scheduler_retention_period', function() {
    return 7 * DAY_IN_SECONDS;
});
```

Zlyhané akcie (`status = failed`) sa retention neriadi — tie treba riešiť zvlášť,
väčšinou ide o plugin, ktorý už nefunguje alebo bol odinštalovaný.

---

# ČASŤ II — MariaDB config

## Krok 0 — Meranie pred nasadením

Read-only, bezpečné na produkcii. Spusti ako `root`.

```bash
#!/bin/bash
# preset-measure.sh — read-only audit pred nasadenim
set -u
hr(){ printf '\n═══ %s ═══\n' "$1"; }

hr "SERVER"
echo "hostname: $(hostname)"
echo "MariaDB:  $(mariadb -Nse 'SELECT VERSION()')"
echo "uptime DB: $(mariadb -Nse "SELECT ROUND(variable_value/3600,1) FROM information_schema.global_status WHERE variable_name='UPTIME'") h"

hr "APLIKACNA VRSTVA"
echo "redis:            $(systemctl is-active redis redis-server 2>/dev/null | tr '\n' ' ')"
echo "object-cache.php: $(ls /home/*/webapps/*/wp-content/object-cache.php 2>/dev/null || echo 'CHYBA -> ziadny persistent object cache')"

hr "DATASET"
mariadb -Nse "SELECT CONCAT(
  'celkom: ', ROUND(SUM(data_length+index_length)/1024/1024/1024,2),' GB',
  '   (data ', ROUND(SUM(data_length)/1024/1024/1024,2),
  ' / index ', ROUND(SUM(index_length)/1024/1024/1024,2),')',
  '   tabuliek: ', COUNT(*))
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys');"

echo "-- TOP 10 tabuliek --"
mariadb -e "SELECT TABLE_SCHEMA db, TABLE_NAME, TABLE_ROWS,
  ROUND((data_length+index_length)/1024/1024,1) total_mb,
  ROUND(index_length/1024/1024,1) idx_mb,
  ROUND((data_length+index_length)/NULLIF(TABLE_ROWS,0)/1024,1) kb_per_row
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
  ORDER BY (data_length+index_length) DESC LIMIT 10;"

hr "RAM"
free -g | awk '/^Mem:/{print "total: "$2" GB   used: "$3" GB   available: "$7" GB"}'
echo "POZOR: sucet RSS php-fpm je nafuknuty (zdielana pamat). Ver 'used' z free."

hr "STORAGE"
lsblk -dno NAME,ROTA,MODEL | grep -vE '^loop'
echo "ROTA=0 -> SSD/NVMe   ROTA=1 -> HDD"

hr "PHP-FPM"
CH=$(grep -rhE '^\s*pm\.max_children' /etc/php*rc/fpm.d/ 2>/dev/null | awk -F= '{s+=$2} END{print s+0}')
echo "sucet pm.max_children: ${CH:-0}"
echo "beziacich workerov:    $(pgrep -fc 'php-fpm: pool' || echo 0)"

hr "ZAPISOVA ZATAZ"
mariadb -Nse "SELECT CONCAT('redo write: ', ROUND(
  (SELECT variable_value FROM information_schema.global_status WHERE variable_name='INNODB_OS_LOG_WRITTEN')/
  (SELECT variable_value FROM information_schema.global_status WHERE variable_name='UPTIME')/1024,1),' KB/s');"

hr "ROZHODNUTIA"
mariadb -Nse "SELECT CONCAT('MyISAM: ', IF((SELECT variable_value FROM information_schema.global_status
  WHERE variable_name='KEY_READ_REQUESTS')>0,'POUZIVA SA -> nechaj key_buffer','NEPOUZIVA -> key_buffer 32M'));"

mariadb -Nse "SELECT CONCAT('query cache hit rate: ', ROUND(100*qh/NULLIF(qh+cs,0),1),'%  -> ',
  IF(100*qh/NULLIF(qh+cs,0) < 20,'VYPNI','NECHAJ ZAPNUTU'))
  FROM (SELECT
   (SELECT variable_value FROM information_schema.global_status WHERE variable_name='QCACHE_HITS') qh,
   (SELECT variable_value FROM information_schema.global_status WHERE variable_name='COM_SELECT') cs) x;"

mariadb -Nse "SELECT CONCAT('peak spojeni: ', variable_value)
  FROM information_schema.global_status WHERE variable_name='MAX_USED_CONNECTIONS';"

mariadb -Nse "SELECT CONCAT('binlog: ', IF(@@log_bin=0,'VYPNUTY -> ziadne PITR, trxcommit=1 je povinny','zapnuty'));"

hr "ODPORUCANY POOL"
DS=$(mariadb -Nse "SELECT CEIL(SUM(data_length+index_length)/1024/1024/1024*1.3)
  FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN
  ('information_schema','mysql','performance_schema','sys');")
RAM=$(free -g | awk '/^Mem:/{print int($2/2)}')
echo "dataset × 1,3 = ${DS} GB"
echo "RAM / 2       = ${RAM} GB"
echo "-> POUZI:       $(( DS < RAM ? DS : RAM )) GB"
```

Ulož výstup — budeš ho potrebovať na porovnanie po nasadení.

---

## Krok 1 — Výpočet per-shop hodnôt

| Premenná | Vzorec | Poznámka |
|---|---|---|
| `innodb_buffer_pool_size` | `min(dataset × 1,3 ; RAM × 0,5)` | Nikdy viac než dataset + rezerva. Pool nepojme viac dát než existuje. |
| `innodb_log_file_size` | `512M` default, `1G` ak dataset > 10 GB | Väčší = dlhší crash recovery. |
| `innodb_log_buffer_size` | `32M` | Na `64M` len ak `Innodb_log_waits` rastie. |
| `max_connections` | `suma pm.max_children × 1,25 + 20` | Minimum 100. RunCloud dáva 4096 = OOM mína. |
| `innodb_io_capacity` | NVMe `2000` / SATA SSD `1000` / HDD `200` | Podľa `ROTA` z `lsblk`. |
| `innodb_io_capacity_max` | NVMe `6000` / SATA SSD `2000` / HDD `400` | |
| `innodb_read_io_threads`<br>`innodb_write_io_threads` | NVMe `8` / inak `4` | |

**Buffer pool:** rast je online a lacný, **zmenšovanie je tá rušivá operácia**
(relokácia stránok, môže blokovať). Nezačínaj vysoko s tým, že „potom zmenším".

Kontrola po 24 h: ak `Innodb_buffer_pool_pages_free` zostáva trvale nad 25 %
z `pages_total` aj po backupoch a špičkách, pool je zbytočne veľký — zníž ho.

**max_connections:** `pm.max_children` prečítaj vždy, nehádaj. Ak je `max_connections`
nižší než reálny počet PHP workerov, dostaneš `Too many connections` = 500-ky na shope.

---

## Krok 2 — Config súbor

Cesta je kritická: **`/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf`**

- `mariadb.cnf` má `!includedir conf.d/` **a až potom** `!includedir mariadb.conf.d/`
- RunCloud píše do `conf.d/runcloud.cnf` → náš súbor sa načíta neskôr a prebije ho
- prefix `99-zz-` sortuje za balíkové `50-*.cnf` aj za RunCloudové `99-server.cnf`
- vlastný názov = dpkg ho nevlastní → `apt upgrade` sa ho nedotkne

```ini
# /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf
# WooCommerce tuning preset. Nacita sa PO /etc/mysql/conf.d/runcloud.cnf.
# Rollback = mv tento subor prec + restart MariaDB.

[mysqld]

# ═══ PER-SHOP — vypln z merania ═══════════════════════════════════
innodb_buffer_pool_size        = 4G        # min(dataset×1,3 ; RAM×0,5)
innodb_log_file_size           = 1G        # 512M / 1G
innodb_log_buffer_size         = 32M
max_connections                = 300       # pm.max_children × 1,25 + 20
innodb_io_capacity             = 2000      # NVMe
innodb_io_capacity_max         = 6000      # NVMe
innodb_read_io_threads         = 8         # NVMe
innodb_write_io_threads        = 8         # NVMe

# ═══ PRENOSNE — rovnake na kazdom RunCloud WooCommerce boxe ═══════

# ── Durabilita ────────────────────────────────────────────────────
# RunCloud nastavuje skip-log-bin => ZIADNE point-in-time recovery.
# Redo log je jedina ochrana potvrdenych objednavok.
innodb_flush_log_at_trx_commit = 1
innodb_doublewrite             = 1

# ── Pripnute defaulty ─────────────────────────────────────────────
# Zhodne s compiled-in defaultmi MariaDB 11.4. Pripnute preto, ze
# unattended-upgrades ma povoleny origin "MariaDB:" a novsia verzia
# by mohla default zmenit bez upozornenia.
innodb_flush_method                 = O_DIRECT
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup  = 1

# ── Flush ─────────────────────────────────────────────────────────
innodb_flush_neighbors         = 0
innodb_max_dirty_pages_pct     = 60
innodb_max_dirty_pages_pct_lwm = 10      # default 0 = flush caka do poslednej chvile

# ── Connections ───────────────────────────────────────────────────
innodb_lock_wait_timeout       = 30      # RunCloud dava 200 = blokuje FPM workerov
skip_name_resolve              = 1       # vsetko chodi z 127.0.0.1
thread_cache_size              = 64

# ── Temp tables ───────────────────────────────────────────────────
# POZOR: WP/Woo pouziva LONGTEXT (meta_value, post_content, option_value)
# a MEMORY engine BLOB/TEXT neuchova -> ~33 % temp tabuliek ide na disk
# BEZ OHLADU na tuto hodnotu. Viz CAST VI.
tmp_table_size                 = 64M
max_heap_table_size            = 64M     # musi sedet s tmp_table_size

# ── MyISAM sa v modernom WP nepouziva ─────────────────────────────
key_buffer_size                = 32M
table_definition_cache         = 2000

# ── Slow log (trvale, early warning) ──────────────────────────────
slow_query_log                 = 1
slow_query_log_file            = /var/log/mysql/slow.log
long_query_time                = 2
log_slow_verbosity             = query_plan

# ── Query cache: ZAMERNE NENASTAVENA ──────────────────────────────
# Rozhodni podla merania (Krok 0). Vypni LEN ak:
#   hit rate < 20 %  ALEBO  Threads_running bezne > 8
# query_cache_type = 0
# query_cache_size = 0
```

### Nastavenia počas vyšetrovania

```ini
long_query_time    = 0.5
log_slow_verbosity = query_plan,explain
```

**Pozor:** `explain` rozbije `mariadb-dumpslow` (`Died at line 185`). S `explain`
analyzuj cez `pt-query-digest` (`apt install percona-toolkit`) alebo čítaj log priamo.
Po vyšetrovaní vráť na `2` a `query_plan`.

---

## Krok 3 — Nasadenie

```bash
# 1. Adresar pre slow log (idempotentne)
sudo install -d -o mysql -g mysql -m 750 /var/log/mysql

# 2. Config subor
sudo tee /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf > /dev/null <<'EOF'
...obsah z Kroku 2...
EOF

# 3. Kontrola
sudo cat /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf
sudo ls -la /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf   # ocakavane: -rw-r--r-- root root
```

Apostrofy okolo `'EOF'` sú povinné — bez nich bash interpretuje obsah.

### Prečo `/var/log/mysql/slow.log` a nie `/var/lib/mysql/`

Balíkový logrotate (`/etc/logrotate.d/mariadb`) pokrýva:

```
/var/lib/mysql/mysqld.log  /var/lib/mysql/mariadb.log  /var/log/mysql/*.log
```

`/var/lib/mysql/slow.log` tam **nespadá** — vzor matchuje len tie dva konkrétne názvy.
Rástol by donekonečna bez rotácie.

V `/var/log/mysql/` ho logrotate rieši sám: monthly, `maxsize 500M`, 6 kópií, compress,
a `postrotate` volá `flush-slow-log`, takže MariaDB súbor korektne znovuotvorí.

---

## Krok 4 — Validácia PRED reštartom

**Nepreskakuj.** Neznáma premenná alebo neplatná hodnota zastaví štart servera
= shop je dole, kým to neopravíš.

```bash
sudo install -d -o mysql -g mysql /tmp/mdb-validate
sudo mariadbd --validate-config --user=mysql --datadir=/tmp/mdb-validate 2>&1 \
  | grep -iE "unknown|invalid|error"
sudo rm -rf /tmp/mdb-validate
```

### Ako čítať výstup

Chyby o zámkoch **ignoruj** — pochádzajú od bežiaceho servera, nie z configu:

```
[ERROR] Can't lock aria control file ... error: 11
[ERROR] InnoDB: Unable to lock ./ibdata1 error: 11
[ERROR] Plugin 'Aria' registration as a STORAGE ENGINE failed.
[ERROR] Failed to initialize plugins.  /  Aborting
```

Toto je **dobrý** výstup — config sa prečítal a InnoDB ho prijal:

```
[Note] InnoDB: innodb_buffer_pool_size=4096m      <- tvoja hodnota
[Note] InnoDB: Completed initialization of buffer pool
```

Toto je **zlý** výstup, nereštartuj:

```
[ERROR] mariadbd: unknown variable 'xyz=abc'
[ERROR] mariadbd: Error while setting value 'xyz' to 'abc'
```

### Doplnková kontrola názvov (nulové riziko)

```bash
grep -oP '^\s*\K[a-z_]+(?=\s*=)' /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf | while read v; do
  n=$(sudo mariadb -Nse "SELECT COUNT(*) FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME='${v//-/_}'")
  [ "$n" = "0" ] && echo "NEZNAMA PREMENNA: $v"
done
echo "kontrola nazvov hotova"
```

---

## Krok 5 — Reštart a overenie

Reštartuj **z RunCloud panela**: *Services → MariaDB → Restart*.
(Nie cez `systemctl`, nech si agent udrží konzistentný stav služby.)

Prvý štart potrvá dlhšie, ak si menil `innodb_log_file_size` — MariaDB redo log prerába.
Je to automatické a bezpečné.

```bash
sudo mariadb -e "SELECT
  @@innodb_buffer_pool_size/1024/1024/1024 AS pool_gb,
  @@innodb_log_file_size/1024/1024 AS log_mb,
  @@max_connections, @@innodb_flush_log_at_trx_commit AS trxcommit,
  @@innodb_io_capacity AS ioc, @@innodb_flush_method AS flush_method,
  @@skip_name_resolve AS skipdns, @@slow_query_log AS slowlog,
  @@long_query_time AS lqt, @@slow_query_log_file AS slowfile\G"
```

Zdravotná kontrola ~5 minút po reštarte:

```bash
sudo mariadb -e "SHOW GLOBAL STATUS WHERE Variable_name IN
 ('Innodb_buffer_pool_wait_free','Innodb_log_waits','Aborted_connects',
  'Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_data')"
free -m
```

| Metrika | Očakávané |
|---|---|
| `Innodb_buffer_pool_wait_free` | 0 |
| `Innodb_log_waits` | 0 |
| `Aborted_connects` | 0 |
| `swap used` | nehýbe sa |

**Zvýšené `Innodb_buffer_pool_reads` prvých 30–60 min je warm-up**, nie regresia.

---

## Rollback

```bash
sudo mv /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf /root/
sudo systemctl start mariadb     # ak nenastartovala
```

Preto samostatný súbor namiesto editovania `conf.d/runcloud.cnf` — rollback je
jeden `mv`, bez rekonštrukcie pôvodných hodnôt.

---

# ČASŤ III — RunCloud špecifiká

Veci, na ktoré narazíš na **každom** ich serveri.

### 1. Poradie načítania configu

```
/etc/mysql/mariadb.cnf
  !includedir /etc/mysql/conf.d/           <- 1. root.cnf, runcloud.cnf
  !includedir /etc/mysql/mariadb.conf.d/   <- 2. 50-*.cnf, 60-galera.cnf, 99-server.cnf
```

`!includedir` číta `*.cnf` abecedne, adresáre v uvedenom poradí, **posledná hodnota vyhráva**.

### 2. unattended-upgrades reštartuje MariaDB bez ohlásenia

```
/etc/apt/apt.conf.d/50unattended-upgrades:
    Unattended-Upgrade::Allowed-Origins { ... "MariaDB:"; ... }
    Unattended-Upgrade::Package-Blacklist { };   <- prazdny
```

`apt-daily-upgrade.timer` beží denne ~06:10 + náhodné oneskorenie.
**Akékoľvek runtime `SET GLOBAL` nastavenie sa tým zmaže.** Preto config vždy do súboru.

Ak nechceš neohlásené reštarty DB (odporúčané pre eshop):

```bash
sudo tee /etc/apt/apt.conf.d/52-mariadb-blacklist > /dev/null <<'EOF'
Unattended-Upgrade::Package-Blacklist {
    "mariadb-";
};
EOF
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -i mariadb
```

Cena: MariaDB bezpečnostné updaty aplikuješ ručne.

### 3. ACL na `/etc/mysql`

```
group:users-rc:---
```

Web užívateľ tam nevidí ani na čítanie. Všetko cez `root` alebo `runcloud`
(jediný účet v skupine `sudo`).

### 4. `open_files_limit` z runcloud.cnf je fikcia

```
runcloud.cnf:   open_files_limit = 100000
systemd unit:   LimitNOFILE = 32768
efektivne:      @@open_files_limit = 32768        <- ticho zrezane
```

Ak naozaj potrebuješ viac, je to systemd drop-in, nie `.cnf`.

### 5. `skip-log-bin` → žiadne PITR

RunCloud vypína binárny log. **Jediná ochrana potvrdených transakcií je redo log.**
Preto `innodb_flush_log_at_trx_commit = 1` v prenosnej časti povinný, nie voliteľný.
(RunCloud default je 2 = pri výpadku stratíš ~1 s potvrdených objednávok.)

`expire_logs_days` v `50-server.cnf` je pri tom mŕtvy config.

### 6. Backup = mydumper, robí full scany

Podpis v slow logu:
```
SELECT /*!40001 SQL_NO_CACHE */ `col1`,`col2`,... FROM `tabulka`     root[root]@localhost
```
(Explicitný zoznam stĺpcov = mydumper. `mysqldump` by použil `SELECT *`.)

Číta kompletne najväčšie tabuľky pri každom behu. Pool nadimenzovaný na celý dataset
spraví backup lacným. Skontroluj frekvenciu v paneli — pre 3–5 GB DB je backup
každé 3 hodiny zbytočne časté.

### 7. Query cache — nediktuj presetom

RunCloud zapína `query_cache_size=128M`, `query_cache_type=1`.

| Hit rate | Threads_running | Verdikt |
|---|---|---|
| < 20 % | ktokoľvek | vypni |
| > 20 % | bežne < 8 | nechaj zapnutú |
| > 20 % | bežne > 8 | vypni — mutex je väčšia brzda než prínos |

**Pozor:** `query_cache_type = 0` **pri štarte** znamená, že sa už za behu nedá zapnúť.
Návrat vyžaduje reštart.

### 8. wp-cron

RunCloud typicky nastaví `DISABLE_WP_CRON = true` + systémový cron cez `wget`.
Over v `/etc/cron.d/runcloud-runcloud`. Ak tam wp-cron nie je a `DISABLE_WP_CRON`
je `true`, **cron vôbec nebeží** — objednávky sa nespracujú.

---

# ČASŤ IV — Monitoring po nasadení

Odlož si výstup z Kroku 0 a po 24 hodinách porovnaj:

```bash
sudo mariadb -e "SHOW GLOBAL STATUS WHERE Variable_name IN
 ('Uptime','Questions','Com_select','Innodb_buffer_pool_reads',
  'Innodb_buffer_pool_read_requests','Innodb_data_read',
  'Innodb_buffer_pool_pages_data','Innodb_buffer_pool_pages_free',
  'Innodb_buffer_pool_wait_free','Innodb_log_waits',
  'Created_tmp_disk_tables','Created_tmp_tables','Handler_read_rnd_next',
  'Qcache_hits','Max_used_connections','Slow_queries')"
free -m
ps -o rss,etimes,times --no-headers -p $(pgrep -x mariadbd | head -1)
sudo ls -lh /var/log/mysql/slow.log
```

| Metrika | Cieľ | Ak nie |
|---|---|---|
| BP hit ratio `1 - reads/read_requests` | > 99 % aj v 60 s okne | pool je malý |
| `Innodb_data_read` delta | < 2 MB/s | pool je malý |
| `pages_free` po špičkách | 5–25 % z `pages_total` | > 25 % = pool je zbytočne veľký |
| `Innodb_buffer_pool_wait_free` | 0 | zvýš `io_capacity` |
| `Innodb_log_waits` | 0 | zvýš `innodb_log_buffer_size` |
| `Max_used_connections` | < 80 % `max_connections` | zvýš `max_connections` |

### Pozor na priemery

Lifetime hit ratio je **zavádzajúce**. Server môže mať 99,8 % za 57 hodín a pritom
v burste 28 %. Vždy meraj deltu v krátkom okne:

```bash
sudo mariadb -Nse "SELECT variable_value FROM information_schema.global_status
  WHERE variable_name IN ('INNODB_BUFFER_POOL_READS','INNODB_BUFFER_POOL_READ_REQUESTS')" > /tmp/s1
sleep 60
sudo mariadb -Nse "SELECT variable_value FROM information_schema.global_status
  WHERE variable_name IN ('INNODB_BUFFER_POOL_READS','INNODB_BUFFER_POOL_READ_REQUESTS')" > /tmp/s2
paste /tmp/s1 /tmp/s2 | awk '{d[NR]=$2-$1} END{printf "hit ratio za 60s: %.2f%%  (%.0f missov/s)\n", 100*(1-d[1]/d[2]), d[1]/60}'
```

### CPU meranie

`ps` ukazuje **lifetime priemer**, nie aktuálnu spotrebu:

```bash
P=$(pgrep -x mariadbd | head -1)
T1=$(awk '{print $14+$15}' /proc/$P/stat); sleep 60
T2=$(awk '{print $14+$15}' /proc/$P/stat)
echo "$(( T2-T1 ))" | awk '{printf "%.1f%% jadra = %.2f h CPU/den\n", $1/60, $1/100/60*24}'
```

---

# ČASŤ V — Diagnostika

## Keď CPU žerie niečo neviditeľné

**Slow log štrukturálne nevidí death-by-a-thousand-cuts.** Ak `Handler_read_rnd_next`
ukazuje desaťtisíce riadkov/s, ale slow log je skoro prázdny, znamená to stovky
rýchlych dotazov skenujúcich tisíce riadkov každý.

Prvá vec na kontrolu: **object cache** (Časť I, Krok A). Bez neho je to najčastejšia
príčina.

Ak object cache beží a problém trvá, jediný nástroj je `performance_schema` —
ktorý RunCloud vypína.

Dočasný diagnostický blok (po vyšetrovaní zakomentovať a reštartovať):

```ini
performance_schema = ON
performance-schema-instrument = 'statement/%=ON'
performance-schema-consumer-statements-digest = ON
```

Cena: ~200–400 MB RAM a jednotky % CPU.

```sql
SELECT LEFT(DIGEST_TEXT,100) AS query,
       COUNT_STAR AS calls,
       ROUND(SUM_TIMER_WAIT/1e12,1) AS total_sec,
       SUM_ROWS_EXAMINED,
       ROUND(SUM_ROWS_EXAMINED/COUNT_STAR) AS rows_per_call
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 25;
```

Zoradenie podľa `SUM_TIMER_WAIT` dá presne to, čo slow log nedokáže: agregovaný čas
naprieč všetkými volaniami, vrátane rýchlych.

## Slow log analýza

```bash
sudo mariadb-dumpslow -s t -t 25 /var/log/mysql/slow.log
```

Ak spadne (`Died at line 185`), máš zapnutý `log_slow_verbosity` s `explain`.
Použi `pt-query-digest` alebo čítaj log priamo.

---

# ČASŤ VI — Čo NEROBIŤ

Anti-patterny, ktoré kolujú po internete. Všetky vyzerajú rozumne a všetky sú
v tomto kontexte zlé.

## ❌ Index na `wp_postmeta.meta_value`

```sql
-- NEROB TOTO
ALTER TABLE wp_postmeta ADD INDEX idx_meta_value(meta_value(191));
```

1. **WP dotazy majú tvar `WHERE meta_key='X' AND meta_value='Y'`.** Potrebný je
   **kompozitný** index `(meta_key(N), meta_value(N))`. Samostatný index na `meta_value`
   má mizernú selektivitu a optimizer ho väčšinou nezvolí.
2. **Veľkosť:** `191 × 4 B` (utf8mb4) = 764 B na položku. Pri 6M riadkoch rádovo
   **1–3 GB nového indexu** — a rozbije ti to sizing buffer poolu.
3. `postmeta` už typicky má viac indexov než dát (na referenčnom shope 931 MB
   indexov vs 512 MB dát).
4. **Write amplification** — WooCommerce zapisuje do `postmeta` pri každej objednávke.

Ak už kompozitný index potrebuješ, tak v tomto tvare (a s krátkym prefixom):
```sql
ALTER TABLE wp_postmeta ADD INDEX idx_mk_mv (meta_key(50), meta_value(15));
```
Overenie, či niečo také už nemáš (pluginy ako WP All Import ich pridávajú samé):
```sql
SELECT INDEX_NAME, GROUP_CONCAT(CONCAT(COLUMN_NAME,IFNULL(CONCAT('(',SUB_PART,')'),''))
       ORDER BY SEQ_IN_INDEX) cols
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_postmeta' GROUP BY INDEX_NAME;
```

## ❌ `innodb_buffer_pool_size` na 70–80 % RAM

Klasická polovica pravidla. **Pool nikdy nepojme viac dát, než existuje.**
70 % zo 64 GB = 45 GB pre 3,5 GB dataset = 41 GB navždy nevyužitých.

Správne: `min(dataset × 1,3 ; RAM × 0,5)`.

Súvisiaci mýtus: *„nastav vysoko a potom zmenš podľa `pages_free`"*. Rast poolu je
online a lacný, **zmenšovanie je tá rušivá operácia.**

## ❌ Plošné „vypni query cache, veď ju MySQL 8 odstránil"

Pravda **o MySQL**. MariaDB query cache nikdy neodstránila a v 11.4 ju stále udržiava.
Argument sa na MariaDB nevzťahuje.

Mutex problém je reálny, ale závisí od súbežnosti. Rozhodni meraním (Časť III, bod 7),
nie citátom o MySQL.

## ❌ Očakávať, že `tmp_table_size` odstráni disk temp tabuľky

MEMORY engine **nevie držať BLOB/TEXT**. WordPress používa LONGTEXT prakticky všade
(`postmeta.meta_value`, `posts.post_content`, `options.option_value`), takže tie
temp tabuľky idú na disk do Arie **bez ohľadu na `tmp_table_size`**.

Namerané na referenčnom shope:

| `tmp_table_size` | disk temp tables |
|---|---|
| 16M | 36,6 % |
| **64M** | **33,3 %** |

Nastav `64M` (pokryje dotazy bez TEXT), ale **nečakaj od toho zlepšenie**.
MySQL 8 to vyriešil TempTable enginom, MariaDB nie. Opraviť sa to dá len prepisom
dotazov na aplikačnej strane.

## ❌ Merať pamäť php-fpm cez súčet RSS

```bash
# ZLE — zdielana pamat (opcache) sa rata viacnasobne
ps --no-headers -o rss -C php-fpm | awk '{sum+=$1} END {print sum/1024" MB"}'
```

Na referenčnom shope to dalo **18 GB**, kým `free` ukázal **8,4 GB pre celý stroj**.
Ver `free -m` → `used`, nie súčtu RSS. To isté platí pre priemer (`sum/NR`).

## ❌ Action Scheduler retention na 1 deň

Prídeš o možnosť debugovať zlyhané akcie. **7 dní** je rozumný kompromis.

## ❌ Ladiť DB pred kontrolou object cache

Buffer pool dotazy **zlacní**, object cache ich **odstráni**. Poradie má význam —
inak si problém schováš pod RAM.

---

# Bezpečnostná kontrola

Nesúvisí s výkonom, ale na RunCloud serveroch to stojí za pohľad pri prvom nasadení.

```bash
# 1. Na com MariaDB posluchne
sudo mariadb -e "SELECT @@bind_address"
ss -lntp | grep 3306

# 2. Granty s wildcard hostom
sudo mariadb -e "SELECT user, host FROM mysql.user WHERE host NOT IN ('localhost','127.0.0.1')"

# 3. Firewall
sudo firewall-cmd --list-all
```

Časté nálezy:

- **`/etc/mysql/mariadb.conf.d/99-server.cnf` obsahuje `bind-address=0.0.0.0`**
  a prebíja `50-server.cnf` s `127.0.0.1`. Ak nemáš externý DB klient, patrí to späť.
- **App user má `@'%'`** namiesto `@localhost`. WordPress sa pripája na `127.0.0.1`.
- **`/etc/mysql/conf.d/root.cnf` obsahuje root heslo v plaintexte.** RunCloud agent ho
  používa na správu databáz z panela — pri rotácii treba zmeniť heslo **aj v DB aj
  v tom súbore naraz**, inak sa rozbije sekcia Database v paneli.
- **`wp-config.php` obsahuje ďalšie tajomstvá** (`RCWP_REDIS_PASSWORD`, DB heslo,
  salty). Pri zdieľaní configov to pozor.

---

# Príloha: referenčné merania

Prvý shop, na ktorom bol preset odvodený. Slúži ako mierka „ako to vyzerá v praxi".

### Server

```
MariaDB 11.4.12  /  Ubuntu 24.04 noble  /  RunCloud
CPU 12 jadier, RAM 64 GB
2× Samsung MZVL2512HCJQ NVMe v RAID1 (md2, 436 GB)
```

### Dataset

```
SUM(data_length + index_length)  =  3 499 MB  (3,42 GB)
  data_length   1 826 MB
  index_length  1 673 MB      <- ratio 0,92 : 1
237 InnoDB tabuliek
```

| Tabuľka | Riadky | Total | Poznámka |
|---|---|---|---|
| `postmeta` | 6 077 309 | 1 443 MB | 931 MB indexy — 2 extra non-WP indexy z WP All Import |
| `woocommerce_order_itemmeta` | 4 301 208 | 594 MB | |
| `email_log` | 15 814 | 403 MB | **~26 KB/riadok** — plné telá emailov |
| `comments` | 620 469 | 321 MB | |
| `posts` | 106 862 | 131 MB | 92 288 z toho `shop_order` — HPOS vypnuté |

### Aplikačná vrstva

```
object cache:        ŽIADNY (Redis inactive, object-cache.php neexistuje)
page cache:          WP Rocket (WP_CACHE = true)
autoload:            2,14 MB / 2 865 riadkov     <- 2× nad prahom
  wpify_woo_heureka_xml_categories      566 KB
  wpify_woo_heureka_xml_categories_sk   499 KB   <- 1,06 MB v dvoch options
transienty v DB:     618 riadkov / 1,50 MB
HPOS:                VYPNUTÝ — 92 288 objednávok v postmeta
sessions:            16 568 riadkov (v poriadku)
Action Scheduler:    25 280 akcií, z toho 7 467 failed image-optimization
aktívnych pluginov:  50
```

### Pôvodný MariaDB config (RunCloud default)

```
innodb_buffer_pool_size = 128M      <- compiled-in default, nikto to nikdy neladil
query_cache_size = 128M, type = ON  <- runcloud.cnf
max_connections = 4096              <- runcloud.cnf
innodb_lock_wait_timeout = 200      <- runcloud.cnf
innodb_flush_log_at_trx_commit = 2  <- runcloud.cnf
innodb_log_file_size = 96M
performance_schema = OFF
slow_query_log = OFF
```

### Namerané pred zmenou

```
CPU mariadbd:  5,85 h / 57,4 h uptime  =  10,2 % jadra
lifetime BP hit ratio:  99,80 %        <- ZAVADZAJUCE

burst (60 s okno):     hit ratio 28 %,  2 414 missov/s,  39,6 MB/s z disku
burst (148 s okno):    hit ratio 53 %,  1 466 missov/s,  24,0 MB/s
kludne okno (49 min):  hit ratio 96,7 %,   57 missov/s,   0,89 MB/s

Handler_read_rnd_next:  12 782 riadkov/s v kludu,  134 000/s v burste
disk temp tables:       36,6 %
query cache hit rate:   30–32 %  (merane 3× nezavisle)
```

Pool držal 3,7 % datasetu. Kľudná pracovná množina bola len ~123 MB — celá hodnota
väčšieho poolu je v **absorbovaní burstov**, nie v kľudnej prevádzke.

### Čo bolo príčinou burstov

Slow log (14 h, prah 0,5 s) ukázal ako najväčších jednotlivých žrútov IO
**mydumper backupy** — 4 behy za 14 h, každý číta kompletne `postmeta` (6,08M riadkov),
`order_itemmeta` (4,16M), `comments` (612k).

**Ale:** celý 14-hodinový slow log obsahoval len **~38 sekúnd** dotazov nad 0,5 s.
To nevysvetľuje 4 h CPU/deň. Zvyšok je objem rýchlych dotazov — a najpravdepodobnejší
dôvod je **chýbajúci object cache**.

### Nasadené hodnoty

```ini
innodb_buffer_pool_size = 4G      # dataset 3,5 GB × 1,3 = 4,5 -> 4G stacilo
innodb_log_file_size    = 1G
max_connections         = 300     # peak bol 91, 86 php-fpm workerov
innodb_io_capacity      = 2000    # NVMe
innodb_io_capacity_max  = 6000
```

### Poučenia

1. **Runtime `SET GLOBAL` sa nedá použiť** — unattended-upgrades to zmazal
   po 14 hodinách. Config vždy do súboru, hneď.
2. **Lifetime countery klamú.** 99,8 % hit ratio pri poole, ktorý drží 3,7 % datasetu.
   Vždy meraj krátke okná.
3. **Súčet RSS php-fpm klame.** 18 GB podľa `ps`, ale 8,4 GB podľa `free` pre celý stroj.
4. **Buffer pool nerastie okamžite.** Linux alokuje lazy — po zmene na 4G narástol
   RSS len o 84 MB, zvyšok pribúdal postupne.
5. **Väčší pool vytvára nové riziko.** Pri 128 MB bolo max špinavých stránok 115 MB,
   pri 4G je to 2,4 GB. Preto `io_capacity` a `max_dirty_pages_pct_lwm` patria
   do rovnakej zmeny, nie neskôr.
6. **Slow log nevidí to hlavné.** 38 s pomalých dotazov za 14 h pri 4 h CPU/deň
   znamená, že problém je inde — v objeme rýchlych dotazov, čiže v object cache.
