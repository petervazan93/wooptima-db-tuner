# Homepage tuning scope and infographics design

## Goal

Explain on the GitHub homepage what Wooptima DB Tuner evaluates for a
WooCommerce workload, how representative MariaDB targets are calculated, and
which safety boundaries prevent unsupported or incomplete evidence from
becoming an active proposal.

## Source of truth

Homepage claims must follow the executable contracts in `lib/40-rules.sh` and
`lib/20-audit.sh`. The methodology document is supporting context, not the
authoritative source for exact formulas. In particular, the homepage must use
the implemented buffer-pool growth and memory guards, the measured connection
peak, active-window query-cache requirements, version-gated flush method, and
storage-specific flush-neighbor target.

## Homepage structure

Keep the hero and sanitized audit preview. Insert two new sections between
Overview and Lifecycle:

1. `WooCommerce tuning scope` explains application-first diagnostics and shows
   the request/database-pressure infographic followed by a concise checks table.
2. `How MariaDB targets are calculated` explains collection quality, shows the
   sizing-logic infographic, documents representative formulas, and provides a
   collapsed list of all 29 version-gated proposal keys.

The top navigation becomes `Overview`, `Tuning scope`, `Decision logic`,
`Safety`, `Install`, and `Docs`. Existing stale `v0.4.1 release candidate`
language is corrected to describe the published release.

## Application scope

The application section states that application findings are
recommendation-only and never mutate WordPress or WooCommerce data. It covers:

- persistent object cache: Redis probe plus `wp-content/object-cache.php`;
- Redis `maxmemory-policy`, with `volatile-lru` as the implemented target;
- autoload totals for `yes`, `on`, and `auto`: a positive total below 1 MiB
  is OK, 1-3 MiB requires review, above 3 MiB is high priority, and zero emits
  no autoload verdict;
- HPOS migration and compatibility-sync duplicate writes;
- WooCommerce sessions at an estimated 500,000 rows, with an exact read-only
  follow-up query;
- failed Action Scheduler actions;
- database transients at 1,000 records or 10 MiB;
- plugin log tables above 20 KiB per estimated row;
- disabled WP-Cron without a confirmed system cron;
- a standalone `postmeta.meta_value` index.

Do not advertise Action Scheduler retention, Redis sizing/eviction analysis, or
HPOS row-count reconciliation as production decisions because current audit
data does not drive those verdicts.

## Server decision logic

The server section states the default seven-day collection, five-minute tick,
60-second delta window, configurable valid-sample minimum of 288 by default,
exclusion of degraded and restart windows, 29 version-gated proposal keys, and
zero automatic application mutations.

Representative formulas are copied from the executable rules:

- buffer pool starts from
  `min((dataset + growth180) x 1.3, RAM x 0.5)`, rounds to 256 MiB, applies the
  p05 available-memory reserve, and never shrinks automatically;
- connections use
  `max(100, ceil(workers x 1.25 + 20), ceil(measured_peak x 1.25))`;
- storage maps NVMe to `2000/6000/8/0`, SSD/SATA to `1000/2000/4/0`, and HDD
  to `200/400/4/1` for capacity, maximum, threads, and flush neighbors;
- query cache disables below 20 percent p50 hit rate or above 8 p95 running
  threads and requires the configured active-window minimum, 288 by default;
- any valid sampled log wait selects a 64 MiB log buffer, otherwise 32 MiB;
- dataset above 10 GiB selects a 1 GiB log file, otherwise 512 MiB;
- disabled binary logging allows the durability rule to propose
  `innodb_flush_log_at_trx_commit=1`, while doublewrite remains enabled.

The copy distinguishes diagnostic metrics from proposal-driving inputs. Unknown
current values, unsupported versions, conflicting evidence, and degraded
samples never become active CNF changes.

## Infographic design

Both infographic concepts have a 1200-pixel desktop SVG and a vertically
stacked 600-pixel mobile SVG selected through a standard HTML `picture` block.
All variants use GitHub dark colors, system sans-serif for prose, monospace for
keys and formulas, and accessible `title` and `desc` elements. They contain no
production data or benchmark claims.

`assets/woocommerce-query-pressure.svg` is 1200 by 620. It shows the request
path from page cache through WordPress/WooCommerce and persistent object cache
to database work and MariaDB. Four cards summarize object-cache, autoload,
orders/jobs, and table-waste decisions.

`assets/woocommerce-query-pressure-mobile.svg` is 600 by 1200 and presents the
same branched flow and cards vertically with mobile-readable typography.

`assets/mariadb-sizing-logic.svg` is 1200 by 680. It shows the collection metrics
strip, cards for buffer pool, connections, storage, query cache, and redo log,
and a bottom fail-closed strip.

`assets/mariadb-sizing-logic-mobile.svg` is 600 by 1550 and stacks the same
metrics, formulas, and scoped fail-closed rules vertically.

## Verification

Validate all four SVG variants with `xmllint --noout`, inspect them for clipping
at their declared viewBoxes and at approximately 350-pixel display width,
ensure README `picture` sources resolve, and run `make check`,
`make test`, and `git diff --check`. Review all numeric claims against the
executable schema and rules before completion.
