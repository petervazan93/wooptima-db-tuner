# WooCommerce tuning preset for RunCloud

A complete performance-tuning workflow: **application layer -> MariaDB configuration -> monitoring**.
Verified on MariaDB 11.4.12 / Ubuntu 24.04 (noble) / RunCloud agent.

Based on a real production-store analysis (3.5 GB dataset, 6M `postmeta` rows).
Reference measurements are included in the appendix.

---

## Order of work and why it matters

**The application layer comes first.** Object cache *eliminates* queries; the buffer
pool only makes them *cheaper*. If you tune the database first, you hide the problem
under RAM and never learn that half of the queries did not need to exist.

```text
PART I     Application layer     <- object cache, autoload, HPOS, table waste
PART II    MariaDB configuration <- measurement, calculation, deployment
PART III   RunCloud specifics    <- traps present on every RunCloud server
PART IV    Monitoring
PART V     Diagnostics
PART VI    What NOT to do        <- common internet anti-patterns
```

The preset targets a typical RunCloud server with MariaDB 10.6, 10.11, or 11.x,
WooCommerce, one main database of approximately 1 GB or more, at least 8 GB RAM,
and a symptom of MariaDB consuming CPU.

**Do not use it without measurement.** Sizing values must be calculated from the
actual numbers for the server. A preset without measurement is guesswork.

---

# PART I - Application layer

## Step A - Object cache (the highest-leverage change)

Without object cache, **every request**:
- loads the entire `wp_options` autoload set from the database,
- sends every `get_option()` and `get_transient()` to MariaDB,
- writes transients to `wp_options`, causing more writes.

This appears as **hundreds of fast queries per request** that the slow log never
captures because none crosses the threshold, but together they consume a substantial
share of CPU. A typical indicator is `Handler_read_rnd_next` at tens of thousands of
rows per second even while idle.

### Check

```bash
systemctl is-active redis redis-server
redis-cli ping
ls -la /path/to/webroot/wp-content/object-cache.php
grep -iE "WP_REDIS|WP_CACHE" /path/to/webroot/wp-config.php
ls -d /path/to/webroot/wp-content/plugins/*redis*
```

**`object-cache.php` must exist.** It is the drop-in installed by the plugin. Without
it, WordPress does not use persistent object cache even when Redis is running.

### Do not confuse these caches

| | What it handles | What it does NOT handle |
|---|---|---|
| **Page cache** (WP Rocket, nginx fastcgi_cache) | anonymous traffic | logged-in users, cart, checkout, admin, AJAX |
| **Object cache** (Redis) | `get_option`, transients, WP_Query cache - **for everyone** | HTML rendering |

`WP_CACHE = true` in `wp-config.php` means page cache, **not** object cache.
The two are not substitutes.

### Redis configuration for a store

```text
maxmemory-policy volatile-lru
```

This prevents session data from being evicted under memory pressure, which would
cause lost carts. Check evictions:

```bash
redis-cli INFO stats | grep evicted_keys
redis-cli INFO memory | grep used_memory_human
```

Sizing: allocate at least **2x typical `used_memory`**. As a guide, `wp_alloptions`
uses 0.5-2 MB, each WooCommerce session uses 2-5 KB, and 5,000 products use about 50 MB.

---

## Step B - Autoload audit

Autoloaded options are loaded **on every page load**. Above approximately 1 MB, this
becomes noticeable, and without object cache it comes directly from the database each time.

```sql
-- total size
SELECT ROUND(SUM(LENGTH(option_value))/1024/1024,2) AS autoload_mb, COUNT(*) AS cnt
FROM wp_options WHERE autoload IN ('yes','on','auto');

-- top offenders
SELECT option_name, ROUND(LENGTH(option_value)/1024,1) AS kb
FROM wp_options WHERE autoload IN ('yes','on','auto')
ORDER BY LENGTH(option_value) DESC LIMIT 20;
```

> **Note:** WordPress 6.6+ uses `yes`/`no`/`on`/`off`/`auto` values.
> An older query using `autoload='yes'` misses part of the data.

| Autoload | Verdict |
|---|---|
| < 1 MB | OK |
| 1-3 MB | review the top 20 and disable what is unnecessary |
| > 3 MB | address as a priority |

Typical culprits are XML feed caches (Heureka, Glami, Google), translation caches
(Weglot, WPML), old `_transient_*` entries without expiration, and options left by
uninstalled plugins.

Disable autoload for a specific option:

```sql
UPDATE wp_options SET autoload = 'no' WHERE option_name = 'option_name';
```

*(First verify that the plugin does not read it on every request; otherwise this hurts performance.)*

### Hidden writes to wp_options

`update_option()` on **any** autoloaded option invalidates the entire `alloptions`
cache. A plugin that writes on every request can therefore defeat object cache.

Search with `SAVEQUERIES` in `wp-config.php` (temporarily, on staging only):

```php
define('SAVEQUERIES', true);
// Then, in the footer, inspect $wpdb->queries for UPDATE.*wp_options.
```

Common sources include analytics plugins, rate limiters, `woocommerce_tracker_last_send`,
and `_transient_wc_count_comments`.

---

## Step C - HPOS (High-Performance Order Storage)

```sql
SELECT option_name, option_value FROM wp_options WHERE option_name IN (
  'woocommerce_custom_orders_table_enabled',
  'woocommerce_custom_orders_table_data_sync_enabled',
  'woocommerce_feature_custom_order_tables_enabled');

SELECT COUNT(*) FROM wp_wc_orders;          -- HPOS table
SELECT post_type, COUNT(*) FROM wp_posts WHERE post_type LIKE 'shop_order%' GROUP BY post_type;
```

| State | Action |
|---|---|
| `enabled = no`, orders in `wp_posts`/`wp_postmeta` | **Migrate to HPOS** for the largest structural saving. This is a separate project, not part of tuning. |
| `enabled = yes`, `data_sync = yes` | **Disable sync** after verification; otherwise every order is written twice (WooCommerce -> Settings -> Advanced -> Features). |
| `enabled = yes`, `data_sync = no` | OK |

With HPOS disabled, orders make up the overwhelming majority of `postmeta`. On the
reference store, 92,288 `shop_order` posts produced 6.08M `postmeta` rows (1,443 MB).

---

## Step D - Table waste

```sql
-- Sessions (a problem from approximately 500K rows)
SELECT COUNT(*) FROM wp_woocommerce_sessions;

-- Action Scheduler
SELECT status, COUNT(*) FROM wp_actionscheduler_actions GROUP BY status;
SELECT hook, status, COUNT(*) c FROM wp_actionscheduler_actions
  GROUP BY hook, status ORDER BY c DESC LIMIT 20;

-- Database transients (they remain without object cache)
SELECT COUNT(*) cnt, ROUND(SUM(LENGTH(option_value))/1024/1024,2) mb
FROM wp_options WHERE option_name LIKE '_transient%';

-- Plugin log tables, often the largest single consumer
SELECT TABLE_NAME, TABLE_ROWS, ROUND((data_length+index_length)/1024/1024,1) mb,
       ROUND((data_length+index_length)/NULLIF(TABLE_ROWS,0)/1024,1) kb_per_row
FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME REGEXP 'log|history|track|event'
ORDER BY (data_length+index_length) DESC;
```

**`kb_per_row` is an effective detector.** A normal table uses a few KB per row. If
you see more than 20 KB per row, it is probably a log containing full bodies (emails,
requests, or response payloads) and is a purge candidate.

### Action Scheduler retention

The default keeps completed actions for 30 days. Shortening it helps, but **1 day, a
common internet recommendation, is too short** because it removes the ability to debug
failed actions.

```php
add_filter('action_scheduler_retention_period', function() {
    return 7 * DAY_IN_SECONDS;
});
```

Failed actions (`status = failed`) are not governed by retention. Address them separately;
they usually indicate a plugin that no longer works or was uninstalled.

---

# PART II - MariaDB configuration

## Step 0 - Measurement before deployment

Read-only and safe in production. Run as `root`.

```bash
#!/bin/bash
# preset-measure.sh - read-only audit before deployment
set -u
hr(){ printf '\n=== %s ===\n' "$1"; }

hr "SERVER"
echo "hostname: $(hostname)"
echo "MariaDB:  $(mariadb -Nse 'SELECT VERSION()')"
echo "DB uptime: $(mariadb -Nse "SELECT ROUND(variable_value/3600,1) FROM information_schema.global_status WHERE variable_name='UPTIME'") h"

hr "APPLICATION LAYER"
echo "redis:            $(systemctl is-active redis redis-server 2>/dev/null | tr '\n' ' ')"
echo "object-cache.php: $(ls /home/*/webapps/*/wp-content/object-cache.php 2>/dev/null || echo 'ERROR -> no persistent object cache')"

hr "DATASET"
mariadb -Nse "SELECT CONCAT(
  'total: ', ROUND(SUM(data_length+index_length)/1024/1024/1024,2),' GB',
  '   (data ', ROUND(SUM(data_length)/1024/1024/1024,2),
  ' / index ', ROUND(SUM(index_length)/1024/1024/1024,2),')',
  '   tables: ', COUNT(*))
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys');"

echo "-- TOP 10 tables --"
mariadb -e "SELECT TABLE_SCHEMA db, TABLE_NAME, TABLE_ROWS,
  ROUND((data_length+index_length)/1024/1024,1) total_mb,
  ROUND(index_length/1024/1024,1) idx_mb,
  ROUND((data_length+index_length)/NULLIF(TABLE_ROWS,0)/1024,1) kb_per_row
  FROM information_schema.TABLES
  WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
  ORDER BY (data_length+index_length) DESC LIMIT 10;"

hr "RAM"
free -g | awk '/^Mem:/{print "total: "$2" GB   used: "$3" GB   available: "$7" GB"}'
echo "WARNING: summed php-fpm RSS is inflated by shared memory. Trust 'used' from free."

hr "STORAGE"
lsblk -dno NAME,ROTA,MODEL | grep -vE '^loop'
echo "ROTA=0 -> SSD/NVMe   ROTA=1 -> HDD"

hr "PHP-FPM"
CH=$(grep -rhE '^\s*pm\.max_children' /etc/php*rc/fpm.d/ 2>/dev/null | awk -F= '{s+=$2} END{print s+0}')
echo "sum of pm.max_children: ${CH:-0}"
echo "running workers:        $(pgrep -fc 'php-fpm: pool' || echo 0)"

hr "WRITE LOAD"
mariadb -Nse "SELECT CONCAT('redo write: ', ROUND(
  (SELECT variable_value FROM information_schema.global_status WHERE variable_name='INNODB_OS_LOG_WRITTEN')/
  (SELECT variable_value FROM information_schema.global_status WHERE variable_name='UPTIME')/1024,1),' KB/s');"

hr "DECISIONS"
mariadb -Nse "SELECT CONCAT('MyISAM: ', IF((SELECT variable_value FROM information_schema.global_status
  WHERE variable_name='KEY_READ_REQUESTS')>0,'IN USE -> keep key_buffer','NOT IN USE -> key_buffer 32M'));"

mariadb -Nse "SELECT CONCAT('query cache hit rate: ', ROUND(100*qh/NULLIF(qh+cs,0),1),'%  -> ',
  IF(100*qh/NULLIF(qh+cs,0) < 20,'DISABLE','KEEP ENABLED'))
  FROM (SELECT
   (SELECT variable_value FROM information_schema.global_status WHERE variable_name='QCACHE_HITS') qh,
   (SELECT variable_value FROM information_schema.global_status WHERE variable_name='COM_SELECT') cs) x;"

mariadb -Nse "SELECT CONCAT('peak connections: ', variable_value)
  FROM information_schema.global_status WHERE variable_name='MAX_USED_CONNECTIONS';"

mariadb -Nse "SELECT CONCAT('binlog: ', IF(@@log_bin=0,'DISABLED -> no PITR, trxcommit=1 is mandatory','enabled'));"

hr "RECOMMENDED POOL"
DS=$(mariadb -Nse "SELECT CEIL(SUM(data_length+index_length)/1024/1024/1024*1.3)
  FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN
  ('information_schema','mysql','performance_schema','sys');")
RAM=$(free -g | awk '/^Mem:/{print int($2/2)}')
echo "dataset x 1.3 = ${DS} GB"
echo "RAM / 2       = ${RAM} GB"
echo "-> USE:         $(( DS < RAM ? DS : RAM )) GB"
```

Save the output; you will need it for comparison after deployment.

---

## Step 1 - Calculate per-store values

| Variable | Formula | Note |
|---|---|---|
| `innodb_buffer_pool_size` | `min(dataset x 1.3; RAM x 0.5)` | Never more than dataset plus reserve. A pool cannot hold more data than exists. |
| `innodb_log_file_size` | `512M` default, `1G` if dataset > 10 GB | Larger means longer crash recovery. |
| `innodb_log_buffer_size` | `32M` | Use `64M` only if `Innodb_log_waits` grows. |
| `max_connections` | `sum(pm.max_children) x 1.25 + 20` | Minimum 100. RunCloud uses 4096, an OOM hazard. |
| `innodb_io_capacity` | NVMe `2000` / SATA SSD `1000` / HDD `200` | Based on `ROTA` from `lsblk`. |
| `innodb_io_capacity_max` | NVMe `6000` / SATA SSD `2000` / HDD `400` | |
| `innodb_read_io_threads`<br>`innodb_write_io_threads` | NVMe `8` / otherwise `4` | |

**Buffer pool:** growth is online and cheap; **shrinking is the disruptive operation**
(page relocation can block). Do not start high with the assumption that you can shrink later.

Check after 24 hours: if `Innodb_buffer_pool_pages_free` remains consistently above
25% of `pages_total` even after backups and peaks, the pool is unnecessarily large;
reduce it.

**max_connections:** always read `pm.max_children`; do not guess. If `max_connections`
is below the real number of PHP workers, `Too many connections` produces HTTP 500 errors.

---

## Step 2 - Configuration file

The path is critical: **`/etc/mysql/mariadb.conf.d/99-zz-tuning.cnf`**

- `mariadb.cnf` has `!includedir conf.d/` **followed by** `!includedir mariadb.conf.d/`.
- RunCloud writes to `conf.d/runcloud.cnf`, so this file loads later and overrides it.
- Prefix `99-zz-` sorts after package `50-*.cnf` files and RunCloud's `99-server.cnf`.
- A custom name is not owned by dpkg, so `apt upgrade` does not touch it.

```ini
# /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf
# WooCommerce tuning preset. Loaded AFTER /etc/mysql/conf.d/runcloud.cnf.
# Rollback = move this file away and restart MariaDB.

[mysqld]

# === PER STORE - fill from measurements ==================================
innodb_buffer_pool_size        = 4G        # min(dataset x 1.3; RAM x 0.5)
innodb_log_file_size           = 1G        # 512M / 1G
innodb_log_buffer_size         = 32M
max_connections                = 300       # pm.max_children x 1.25 + 20
innodb_io_capacity             = 2000      # NVMe
innodb_io_capacity_max         = 6000      # NVMe
innodb_read_io_threads         = 8         # NVMe
innodb_write_io_threads        = 8         # NVMe

# === PORTABLE - same on every RunCloud WooCommerce server ================

# -- Durability ------------------------------------------------------------
# RunCloud sets skip-log-bin, so there is NO point-in-time recovery.
# The redo log is the only protection for committed orders.
innodb_flush_log_at_trx_commit = 1
innodb_doublewrite             = 1

# -- Pinned defaults -------------------------------------------------------
# These match MariaDB 11.4 compiled-in defaults. They are pinned because
# unattended-upgrades permits the "MariaDB:" origin and a newer version
# could change a default without warning.
innodb_flush_method                 = O_DIRECT
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup  = 1

# -- Flush -----------------------------------------------------------------
innodb_flush_neighbors         = 0
innodb_max_dirty_pages_pct     = 60
innodb_max_dirty_pages_pct_lwm = 10      # default 0 waits until the last moment

# -- Connections -----------------------------------------------------------
innodb_lock_wait_timeout       = 30      # RunCloud uses 200, blocking FPM workers
skip_name_resolve              = 1       # all traffic comes from 127.0.0.1
thread_cache_size              = 64

# -- Temporary tables ------------------------------------------------------
# WARNING: WordPress/WooCommerce uses LONGTEXT (meta_value, post_content,
# option_value), and the MEMORY engine cannot hold BLOB/TEXT. Approximately
# 33% of temporary tables therefore go to disk REGARDLESS of this value.
# See PART VI.
tmp_table_size                 = 64M
max_heap_table_size            = 64M     # must match tmp_table_size

# -- MyISAM is not used by modern WordPress --------------------------------
key_buffer_size                = 32M
table_definition_cache         = 2000

# -- Slow log (permanent early warning) ------------------------------------
slow_query_log                 = 1
slow_query_log_file            = /var/log/mysql/slow.log
long_query_time                = 2
log_slow_verbosity             = query_plan

# -- Query cache: INTENTIONALLY NOT SET ------------------------------------
# Decide from measurement (Step 0). Disable ONLY if:
#   hit rate < 20%  OR  Threads_running is commonly > 8
# query_cache_type = 0
# query_cache_size = 0
```

### Settings during investigation

```ini
long_query_time    = 0.5
log_slow_verbosity = query_plan,explain
```

**Warning:** `explain` breaks `mariadb-dumpslow` (`Died at line 185`). With `explain`,
analyze through `pt-query-digest` (`apt install percona-toolkit`) or read the log directly.
After the investigation, restore `2` and `query_plan`.

---

## Step 3 - Deployment

```bash
# 1. Slow-log directory (idempotent)
sudo install -d -o mysql -g mysql -m 750 /var/log/mysql

# 2. Configuration file
sudo tee /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf > /dev/null <<'EOF'
...contents from Step 2...
EOF

# 3. Check
sudo cat /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf
sudo ls -la /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf   # expected: -rw-r--r-- root root
```

The quotes around `'EOF'` are mandatory; without them, Bash interprets the contents.

### Why `/var/log/mysql/slow.log`, not `/var/lib/mysql/`

The package logrotate configuration (`/etc/logrotate.d/mariadb`) covers:

```text
/var/lib/mysql/mysqld.log  /var/lib/mysql/mariadb.log  /var/log/mysql/*.log
```

`/var/lib/mysql/slow.log` is **not included** because the pattern matches only the two
specific names. It would grow indefinitely without rotation.

Under `/var/log/mysql/`, logrotate handles it automatically: monthly, `maxsize 500M`,
6 copies, compression, and a `postrotate` call to `flush-slow-log`, so MariaDB reopens
the file correctly.

---

## Step 4 - Validation BEFORE restart

**Do not skip this.** An unknown variable or invalid value prevents the server from
starting, leaving the store down until it is corrected.

```bash
sudo install -d -o mysql -g mysql /tmp/mdb-validate
sudo mariadbd --validate-config --user=mysql --datadir=/tmp/mdb-validate 2>&1 \
  | grep -iE "unknown|invalid|error"
sudo rm -rf /tmp/mdb-validate
```

### Reading the output

**Ignore** lock errors; they come from the running server, not the configuration:

```text
[ERROR] Can't lock aria control file ... error: 11
[ERROR] InnoDB: Unable to lock ./ibdata1 error: 11
[ERROR] Plugin 'Aria' registration as a STORAGE ENGINE failed.
[ERROR] Failed to initialize plugins.  /  Aborting
```

This is **good** output: the configuration was read and accepted by InnoDB:

```text
[Note] InnoDB: innodb_buffer_pool_size=4096m      <- your value
[Note] InnoDB: Completed initialization of buffer pool
```

This is **bad** output; do not restart:

```text
[ERROR] mariadbd: unknown variable 'xyz=abc'
[ERROR] mariadbd: Error while setting value 'xyz' to 'abc'
```

### Additional variable-name check (zero risk)

```bash
grep -oP '^\s*\K[a-z_]+(?=\s*=)' /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf | while read v; do
  n=$(sudo mariadb -Nse "SELECT COUNT(*) FROM information_schema.GLOBAL_VARIABLES WHERE VARIABLE_NAME='${v//-/_}'")
  [ "$n" = "0" ] && echo "UNKNOWN VARIABLE: $v"
done
echo "variable-name check complete"
```

---

## Step 5 - Restart and verification

Restart **from the RunCloud panel**: *Services -> MariaDB -> Restart*.
(Do not use `systemctl`; let the agent maintain consistent service state.)

The first start takes longer after changing `innodb_log_file_size` because MariaDB
rebuilds the redo log. This is automatic and safe.

```bash
sudo mariadb -e "SELECT
  @@innodb_buffer_pool_size/1024/1024/1024 AS pool_gb,
  @@innodb_log_file_size/1024/1024 AS log_mb,
  @@max_connections, @@innodb_flush_log_at_trx_commit AS trxcommit,
  @@innodb_io_capacity AS ioc, @@innodb_flush_method AS flush_method,
  @@skip_name_resolve AS skipdns, @@slow_query_log AS slowlog,
  @@long_query_time AS lqt, @@slow_query_log_file AS slowfile\G"
```

Health check approximately 5 minutes after restart:

```bash
sudo mariadb -e "SHOW GLOBAL STATUS WHERE Variable_name IN
 ('Innodb_buffer_pool_wait_free','Innodb_log_waits','Aborted_connects',
  'Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_data')"
free -m
```

| Metric | Expected |
|---|---|
| `Innodb_buffer_pool_wait_free` | 0 |
| `Innodb_log_waits` | 0 |
| `Aborted_connects` | 0 |
| `swap used` | does not move |

**Increased `Innodb_buffer_pool_reads` during the first 30-60 minutes is warm-up,**
not a regression.

---

## Rollback

```bash
sudo mv /etc/mysql/mariadb.conf.d/99-zz-tuning.cnf /root/
sudo systemctl start mariadb     # if it did not start
```

This is why the configuration uses a separate file rather than editing
`conf.d/runcloud.cnf`: rollback is one `mv`, without reconstructing original values.

---

# PART III - RunCloud specifics

These are conditions you encounter on **every** RunCloud server.

### 1. Configuration load order

```text
/etc/mysql/mariadb.cnf
  !includedir /etc/mysql/conf.d/           <- 1. root.cnf, runcloud.cnf
  !includedir /etc/mysql/mariadb.conf.d/   <- 2. 50-*.cnf, 60-galera.cnf, 99-server.cnf
```

`!includedir` reads `*.cnf` alphabetically, directories in the listed order, and
**the last value wins**.

### 2. unattended-upgrades restarts MariaDB without notice

```text
/etc/apt/apt.conf.d/50unattended-upgrades:
    Unattended-Upgrade::Allowed-Origins { ... "MariaDB:"; ... }
    Unattended-Upgrade::Package-Blacklist { };   <- empty
```

`apt-daily-upgrade.timer` runs daily at approximately 06:10 plus random delay.
**Any runtime `SET GLOBAL` setting is erased.** Always put configuration in a file.

If you do not want unannounced database restarts, which is recommended for a store:

```bash
sudo tee /etc/apt/apt.conf.d/52-mariadb-blacklist > /dev/null <<'EOF'
Unattended-Upgrade::Package-Blacklist {
    "mariadb-";
};
EOF
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -i mariadb
```

The cost is applying MariaDB security updates manually.

### 3. ACL on `/etc/mysql`

```text
group:users-rc:---
```

The web user cannot even read the directory. Perform all work through `root` or
`runcloud`, the only account in the `sudo` group.

### 4. `open_files_limit` from runcloud.cnf is fictional

```text
runcloud.cnf:   open_files_limit = 100000
systemd unit:   LimitNOFILE = 32768
effective:      @@open_files_limit = 32768        <- silently capped
```

If you actually need more, use a systemd drop-in, not `.cnf`.

### 5. `skip-log-bin` means no PITR

RunCloud disables the binary log. **The redo log is the only protection for committed
transactions.** Therefore `innodb_flush_log_at_trx_commit = 1` is mandatory in the
portable section, not optional. RunCloud defaults to 2, which can lose approximately
1 second of committed orders during an outage.

`expire_logs_days` in `50-server.cnf` is dead configuration in this setup.

### 6. Backup uses mydumper and performs full scans

Slow-log signature:

```sql
SELECT /*!40001 SQL_NO_CACHE */ `col1`,`col2`,... FROM `table`     root[root]@localhost
```

(The explicit column list indicates mydumper. `mysqldump` would use `SELECT *`.)

Every run reads the largest tables completely. A pool sized for the entire dataset
makes the backup cheap. Check frequency in the panel; for a 3-5 GB database, a backup
every 3 hours is unnecessarily frequent.

### 7. Query cache - do not dictate it through a preset

RunCloud enables `query_cache_size=128M`, `query_cache_type=1`.

| Hit rate | Threads_running | Verdict |
|---|---|---|
| < 20% | any | disable |
| > 20% | commonly < 8 | keep enabled |
| > 20% | commonly > 8 | disable; the mutex costs more than the benefit |

**Warning:** `query_cache_type = 0` **at startup** means it cannot be enabled at runtime.
Returning to it requires a restart.

### 8. wp-cron

RunCloud typically sets `DISABLE_WP_CRON = true` plus a system cron using `wget`.
Check `/etc/cron.d/runcloud-runcloud`. If wp-cron is absent there while
`DISABLE_WP_CRON` is `true`, **cron does not run at all** and orders are not processed.

---

# PART IV - Monitoring after deployment

Save the output from Step 0 and compare it after 24 hours:

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

| Metric | Target | If not |
|---|---|---|
| BP hit ratio `1 - reads/read_requests` | > 99% even in a 60-second window | pool is too small |
| `Innodb_data_read` delta | < 2 MB/s | pool is too small |
| `pages_free` after peaks | 5-25% of `pages_total` | > 25% means the pool is unnecessarily large |
| `Innodb_buffer_pool_wait_free` | 0 | increase `io_capacity` |
| `Innodb_log_waits` | 0 | increase `innodb_log_buffer_size` |
| `Max_used_connections` | < 80% of `max_connections` | increase `max_connections` |

### Beware of averages

The lifetime hit ratio is **misleading**. A server can report 99.8% over 57 hours
while dropping to 28% during a burst. Always measure a delta over a short window:

```bash
sudo mariadb -Nse "SELECT variable_value FROM information_schema.global_status
  WHERE variable_name IN ('INNODB_BUFFER_POOL_READS','INNODB_BUFFER_POOL_READ_REQUESTS')" > /tmp/s1
sleep 60
sudo mariadb -Nse "SELECT variable_value FROM information_schema.global_status
  WHERE variable_name IN ('INNODB_BUFFER_POOL_READS','INNODB_BUFFER_POOL_READ_REQUESTS')" > /tmp/s2
paste /tmp/s1 /tmp/s2 | awk '{d[NR]=$2-$1} END{printf "60s hit ratio: %.2f%%  (%.0f misses/s)\n", 100*(1-d[1]/d[2]), d[1]/60}'
```

### CPU measurement

`ps` reports a **lifetime average**, not current consumption:

```bash
P=$(pgrep -x mariadbd | head -1)
T1=$(awk '{print $14+$15}' /proc/$P/stat); sleep 60
T2=$(awk '{print $14+$15}' /proc/$P/stat)
echo "$(( T2-T1 ))" | awk '{printf "%.1f%% of a core = %.2f h CPU/day\n", $1/60, $1/100/60*24}'
```

---

# PART V - Diagnostics

## When CPU consumption is invisible

**The slow log structurally cannot see death by a thousand cuts.** If
`Handler_read_rnd_next` shows tens of thousands of rows per second while the slow log
is nearly empty, hundreds of fast queries are each scanning thousands of rows.

Check **object cache** first (Part I, Step A). Its absence is the most common cause.

If object cache is running and the problem persists, the only tool is
`performance_schema`, which RunCloud disables.

Temporary diagnostic block (comment out and restart after the investigation):

```ini
performance_schema = ON
performance-schema-instrument = 'statement/%=ON'
performance-schema-consumer-statements-digest = ON
```

The cost is approximately 200-400 MB RAM and a few percent CPU.

```sql
SELECT LEFT(DIGEST_TEXT,100) AS query,
       COUNT_STAR AS calls,
       ROUND(SUM_TIMER_WAIT/1e12,1) AS total_sec,
       SUM_ROWS_EXAMINED,
       ROUND(SUM_ROWS_EXAMINED/COUNT_STAR) AS rows_per_call
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 25;
```

Sorting by `SUM_TIMER_WAIT` provides exactly what the slow log cannot: aggregate time
across every call, including fast calls.

## Slow-log analysis

```bash
sudo mariadb-dumpslow -s t -t 25 /var/log/mysql/slow.log
```

If it fails with `Died at line 185`, `log_slow_verbosity` includes `explain`.
Use `pt-query-digest` or read the log directly.

---

# PART VI - What NOT to do

These anti-patterns circulate online. They all appear reasonable and are all wrong
in this context.

## Do not add an index on `wp_postmeta.meta_value`

```sql
-- DO NOT DO THIS
ALTER TABLE wp_postmeta ADD INDEX idx_meta_value(meta_value(191));
```

1. **WordPress queries use `WHERE meta_key='X' AND meta_value='Y'`.** They need a
   **composite** index `(meta_key(N), meta_value(N))`. A standalone `meta_value` index
   has poor selectivity and the optimizer usually does not choose it.
2. **Size:** `191 x 4 B` (utf8mb4) = 764 B per entry. At 6M rows, that is roughly
   **1-3 GB of new index**, invalidating buffer-pool sizing.
3. `postmeta` typically already has more index than data (931 MB of indexes versus
   512 MB of data on the reference store).
4. **Write amplification:** WooCommerce writes to `postmeta` for every order.

If a composite index is required, use this form with short prefixes:

```sql
ALTER TABLE wp_postmeta ADD INDEX idx_mk_mv (meta_key(50), meta_value(15));
```

Check whether one already exists; plugins such as WP All Import add them themselves:

```sql
SELECT INDEX_NAME, GROUP_CONCAT(CONCAT(COLUMN_NAME,IFNULL(CONCAT('(',SUB_PART,')'),'')
       ORDER BY SEQ_IN_INDEX) cols
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='wp_postmeta' GROUP BY INDEX_NAME;
```

## Do not set `innodb_buffer_pool_size` to 70-80% of RAM

This is a classic rule of thumb. **The pool cannot hold more data than exists.**
70% of 64 GB is 45 GB for a 3.5 GB dataset, leaving 41 GB permanently unused.

Correct: `min(dataset x 1.3; RAM x 0.5)`.

A related myth is to set it high and then shrink according to `pages_free`. Pool
growth is online and cheap; **shrinking is the disruptive operation**.

## Do not blanket-disable query cache because MySQL 8 removed it

That statement is true **for MySQL**. MariaDB never removed query cache and still
maintains it in 11.4. The argument does not apply to MariaDB.

The mutex problem is real but depends on concurrency. Decide from measurement
(Part III, item 7), not from a statement about MySQL.

## Do not expect `tmp_table_size` to eliminate disk temporary tables

The MEMORY engine **cannot hold BLOB/TEXT**. WordPress uses LONGTEXT almost everywhere
(`postmeta.meta_value`, `posts.post_content`, and `options.option_value`), so those
temporary tables go to Aria on disk **regardless of `tmp_table_size`**.

Measured on the reference store:

| `tmp_table_size` | disk temporary tables |
|---|---|
| 16M | 36.6% |
| **64M** | **33.3%** |

Set `64M` to cover queries without TEXT, but **do not expect it to solve the problem**.
MySQL 8 addressed this with the TempTable engine; MariaDB did not. The only fix is to
rewrite the queries in the application layer.

## Do not measure php-fpm memory by summing RSS

```bash
# WRONG - shared memory (opcache) is counted repeatedly
ps --no-headers -o rss -C php-fpm | awk '{sum+=$1} END {print sum/1024" MB"}'
```

On the reference store, this reported **18 GB** while `free` showed **8.4 GB for the
entire machine**. Trust `free -m` -> `used`, not summed RSS. The same applies to an
average (`sum/NR`).

## Do not set Action Scheduler retention to 1 day

You lose the ability to debug failed actions. **7 days** is a reasonable compromise.

## Do not tune the database before checking object cache

The buffer pool makes queries **cheaper**; object cache **eliminates** them. Order
matters, otherwise the problem is hidden under RAM.

---

# Security check

This is unrelated to performance, but it is worth checking during the first deployment
on a RunCloud server.

```bash
# 1. Addresses on which MariaDB listens
sudo mariadb -e "SELECT @@bind_address"
ss -lntp | grep 3306

# 2. Grants with wildcard hosts
sudo mariadb -e "SELECT user, host FROM mysql.user WHERE host NOT IN ('localhost','127.0.0.1')"

# 3. Firewall
sudo firewall-cmd --list-all
```

Common findings:

- **`/etc/mysql/mariadb.conf.d/99-server.cnf` contains `bind-address=0.0.0.0`** and
  overrides `50-server.cnf` with `127.0.0.1`. If no external database client is
  required, restore the local binding.
- **The application user has `@'%'`** instead of `@localhost`. WordPress connects to
  `127.0.0.1`.
- **`/etc/mysql/conf.d/root.cnf` contains the root password in plaintext.** The RunCloud
  agent uses it to manage databases from the panel. During rotation, change the password
  **both in MariaDB and in that file at the same time**, or the panel's Database section breaks.
- **`wp-config.php` contains other secrets** (`RCWP_REDIS_PASSWORD`, database password,
  and salts). Take care when sharing configurations.

---

# Appendix: reference measurements

The first store from which the preset was derived. It serves as a scale reference for
what production data looks like.

### Server

```text
MariaDB 11.4.12  /  Ubuntu 24.04 noble  /  RunCloud
12 CPU cores, 64 GB RAM
2x Samsung MZVL2512HCJQ NVMe in RAID1 (md2, 436 GB)
```

### Dataset

```text
SUM(data_length + index_length)  =  3,499 MB  (3.42 GB)
  data_length   1,826 MB
  index_length  1,673 MB      <- ratio 0.92 : 1
237 InnoDB tables
```

| Table | Rows | Total | Note |
|---|---|---|---|
| `postmeta` | 6,077,309 | 1,443 MB | 931 MB indexes; 2 extra non-WordPress indexes from WP All Import |
| `woocommerce_order_itemmeta` | 4,301,208 | 594 MB | |
| `email_log` | 15,814 | 403 MB | **approximately 26 KB per row**, full email bodies |
| `comments` | 620,469 | 321 MB | |
| `posts` | 106,862 | 131 MB | 92,288 are `shop_order`; HPOS disabled |

### Application layer

```text
object cache:        NONE (Redis inactive, object-cache.php absent)
page cache:          WP Rocket (WP_CACHE = true)
autoload:            2.14 MB / 2,865 rows     <- 2x above threshold
  wpify_woo_heureka_xml_categories      566 KB
  wpify_woo_heureka_xml_categories_sk   499 KB   <- 1.06 MB in two options
database transients: 618 rows / 1.50 MB
HPOS:                DISABLED; 92,288 orders in postmeta
sessions:            16,568 rows (acceptable)
Action Scheduler:    25,280 actions, including 7,467 failed image-optimization actions
active plugins:      50
```

### Original MariaDB configuration (RunCloud default)

```text
innodb_buffer_pool_size = 128M      <- compiled-in default, never tuned
query_cache_size = 128M, type = ON  <- runcloud.cnf
max_connections = 4096              <- runcloud.cnf
innodb_lock_wait_timeout = 200      <- runcloud.cnf
innodb_flush_log_at_trx_commit = 2  <- runcloud.cnf
innodb_log_file_size = 96M
performance_schema = OFF
slow_query_log = OFF
```

### Measured before the change

```text
mariadbd CPU:  5.85 h / 57.4 h uptime  =  10.2% of a core
lifetime BP hit ratio:  99.80%         <- MISLEADING

burst (60-second window):  28% hit ratio, 2,414 misses/s, 39.6 MB/s from disk
burst (148-second window): 53% hit ratio, 1,466 misses/s, 24.0 MB/s
idle window (49 minutes):  96.7% hit ratio, 57 misses/s, 0.89 MB/s

Handler_read_rnd_next:  12,782 rows/s while idle, 134,000/s during a burst
disk temporary tables: 36.6%
query cache hit rate:   30-32% (measured independently 3 times)
```

The pool held 3.7% of the dataset. The idle working set was only approximately 123 MB;
the entire value of a larger pool comes from **absorbing bursts**, not idle operation.

### What caused the bursts

The slow log over 14 hours at a 0.5-second threshold identified **mydumper backups**
as the largest individual IO consumers: 4 runs in 14 hours, each reading all of
`postmeta` (6.08M rows), `order_itemmeta` (4.16M), and `comments` (612K).

**However,** the entire 14-hour slow log contained only **approximately 38 seconds** of
queries above 0.5 seconds. That does not explain 4 hours of CPU per day. The rest is
the volume of fast queries, most likely caused by **missing object cache**.

### Deployed values

```ini
innodb_buffer_pool_size = 4G      # dataset 3.5 GB x 1.3 = 4.5; 4G was sufficient
innodb_log_file_size    = 1G
max_connections         = 300     # peak was 91, with 86 php-fpm workers
innodb_io_capacity      = 2000    # NVMe
innodb_io_capacity_max  = 6000
```

### Lessons

1. **Runtime `SET GLOBAL` cannot be used** because unattended-upgrades erased it after
   14 hours. Always put configuration in a file immediately.
2. **Lifetime counters lie.** A 99.8% hit ratio was reported for a pool holding 3.7%
   of the dataset. Always measure short windows.
3. **Summed php-fpm RSS lies.** `ps` reported 18 GB while `free` reported 8.4 GB for
   the entire machine.
4. **The buffer pool does not grow immediately.** Linux allocates lazily; after changing
   to 4G, RSS grew by only 84 MB and the rest increased gradually.
5. **A larger pool creates a new risk.** At 128 MB, the maximum dirty pages were 115 MB;
   at 4G, they are 2.4 GB. Therefore `io_capacity` and `max_dirty_pages_pct_lwm` belong
   in the same change, not a later one.
6. **The slow log misses the main problem.** Thirty-eight seconds of slow queries over
   14 hours with 4 hours of CPU per day means the problem lies elsewhere: in the volume
   of fast queries, and therefore in object cache.
