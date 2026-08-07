# P2 Audit Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove false MariaDB listener classifications and align WordPress autoload evidence with the WordPress 6.6+ runtime contract.

**Architecture:** Listener classification will use one deterministic parser over a single `ss` snapshot and will distinguish loopback, concrete network, and wildcard endpoints. Autoload aggregation, top-option diagnostics, generated follow-up SQL, integration fixtures, and current documentation will use one exact four-value autoload-on set.

**Tech Stack:** Bash 4+, AWK, MariaDB SQL, Bats, Docker Compose, SVG/XML validation.

## Global Constraints

- Begin only after the P1 completion gate and read-only pilot checkpoint pass.
- Preserve the `security.port_3306` key while adding the approved `network` enum value to `fleet-v3`.
- Keep listener classifications language-neutral; localize only display reasons.
- Keep all WordPress and WooCommerce findings recommendation-only and read-only.
- Do not change autoload thresholds, rule severities, JSON key names, or proposal behavior outside these two findings.
- Do not manually edit or commit generated files under `dist/`.
- Write regression tests first and verify the intended red-green transition.
- Keep all code comments in English.
- Do not modify historical documents under `docs/superpowers/specs/` or older dated plans.

---

### Task 1: Classify Listener Scope Without Calling Concrete Endpoints Public

**Files:**
- Modify: `lib/20-audit.sh:1127-1232`
- Modify: `lib/40-rules.sh:680-683`
- Modify: `lib/05-i18n.sh:1004-1014`
- Modify: `test/fixtures/audit-10.6.tsv`
- Modify: `test/fixtures/audit-11.4.tsv`
- Test: `test/unit/audit.bats`
- Test: `test/unit/rules.bats`

**Interfaces:**
- Produces: `dbtune_audit_classify_listener_3306`, reading `ss -H -lnt` rows from stdin and printing exactly one enum.
- Produces: `security.port_3306=public|network|local|not_listening|unknown`.
- Produces: `R-SEC NETWORK-BOUND` with medium severity for a concrete non-loopback listener when no stronger exposure condition exists.

The approved enum contract is:

| Value | Meaning |
| --- | --- |
| `public` | At least one wildcard endpoint: `0.0.0.0:3306`, `[::]:3306`, or `*:3306`. |
| `network` | At least one concrete non-loopback IPv4 or IPv6 endpoint and no wildcard endpoint. |
| `local` | Only IPv4 `127.0.0.0/8` or IPv6 `::1` endpoints. |
| `not_listening` | No local endpoint uses port 3306. |
| `unknown` | `ss` is unavailable or its snapshot cannot be classified. |

Precedence is `public > network > local > not_listening`.

- [ ] **Step 1: Add pure classifier tests for loopback endpoints**

Add `listener classifier keeps loopback endpoints local` with this input:

```text
LISTEN 0 80 127.0.0.1:3306 0.0.0.0:*
LISTEN 0 80 127.20.30.40:3306 0.0.0.0:*
LISTEN 0 80 [::1]:3306 [::]:*
```

Assert exact output `local`.

- [ ] **Step 2: Add concrete-network tests**

Add `listener classifier marks concrete non-loopback endpoints as network` with RFC1918, IPv6 ULA, and a concrete public documentation address:

```text
LISTEN 0 80 10.23.4.5:3306 0.0.0.0:*
LISTEN 0 80 192.168.10.2:3306 0.0.0.0:*
LISTEN 0 80 [fd00::5]:3306 [::]:*
LISTEN 0 80 203.0.113.10:3306 0.0.0.0:*
```

Assert exact output `network`.

- [ ] **Step 3: Add wildcard precedence and unrelated-port tests**

Add one test combining loopback, network, and each wildcard form and assert `public`. Add another with ports `3307` and `33060` and assert `not_listening`.

- [ ] **Step 4: Add end-to-end platform finding tests**

Stub `ss` and the grant query. Assert:

```bash
grep -Fx $'security.port_3306\tlocal' "$platform_file"
! grep -F $'finding.public_db_listener\t' "$platform_file"
! grep -F $'finding.network_db_listener\t' "$platform_file"
```

For a concrete network endpoint, assert `finding.network_db_listener=warning`. For a wildcard, assert only `finding.public_db_listener=warning`.

- [ ] **Step 5: Add R-SEC enum tests**

Cover these rule outcomes:

```text
public listener -> high EXPOSED
network listener without remote grants -> medium NETWORK-BOUND
network listener with remote grants -> high EXPOSED
local listener without remote grants -> info OK
unknown listener or failed grant audit -> UNKNOWN, not OK
```

- [ ] **Step 6: Run the tests and confirm the current optional regex fails**

```bash
bats --filter 'listener classifier|platform audit.*listener|R-SEC.*listener' \
    test/unit/audit.bats test/unit/rules.bats
```

Expected: loopback and concrete-address tests fail because the current public regex can match the final `:3306` alone.

- [ ] **Step 7: Implement one pure listener parser**

Add a helper before `dbtune_audit_collect_platform()`:

```bash
dbtune_audit_classify_listener_3306() {
    command awk '
        function endpoint_address(endpoint, address) {
            if (endpoint !~ /:3306$/) return ""
            address=endpoint
            sub(/:3306$/, "", address)
            sub(/^\[/, "", address)
            sub(/\]$/, "", address)
            return address
        }
        {
            address=endpoint_address($4)
            if (address == "") next
            if (address == "*" || address == "0.0.0.0" || address == "::") wildcard=1
            else if (address ~ /^127[.]/ || address == "::1") loopback=1
            else network=1
        }
        END {
            if (wildcard) print "public"
            else if (network) print "network"
            else if (loopback) print "local"
            else print "not_listening"
        }
    '
}
```

Call `ss -H -lnt` once and pipe its captured snapshot to the helper. If the command fails or produces no classifiable result, keep `unknown` rather than presenting `not_listening` as authoritative.

- [ ] **Step 8: Update audit findings and R-SEC**

Emit `finding.public_db_listener` only for `public` and `finding.network_db_listener` only for `network`. Add a stable EN/SK reason ID for `NETWORK-BOUND`; preserve the existing high exposure reason for wildcard listeners and remote grants.

Apply this fail-closed rule order:

```text
grants_audited != 1 or listener == unknown -> UNKNOWN
listener == public or remote_grant_count > 0 -> high EXPOSED
listener == network -> medium NETWORK-BOUND
listener == local or listener == not_listening -> info OK
```

Missing or malformed `remote_grant_count` must not default to zero when the grant audit did not complete.

- [ ] **Step 9: Update fixtures and verify all audit consumers**

```bash
bats test/unit/audit.bats
bats test/unit/rules.bats
bats test/unit/report.bats
sh test/support/check-catalog.sh runtime lib/05-i18n.sh lib/*.sh
```

- [ ] **Step 10: Commit listener classification**

```bash
git add lib/20-audit.sh lib/40-rules.sh lib/05-i18n.sh \
    test/fixtures/audit-10.6.tsv test/fixtures/audit-11.4.tsv \
    test/unit/audit.bats test/unit/rules.bats
git commit -m "fix: classify MariaDB listener scope correctly"
```

---

### Task 2: Include auto-on in Every WordPress Autoload Diagnostic

**Files:**
- Modify: `lib/20-audit.sh:741-758`
- Modify: `lib/50-report.sh:489-506`
- Modify: `test/unit/audit.bats:213-239`
- Modify: `test/unit/report.bats`
- Modify: `test/integration/run.sh`
- Modify: `README.md:47-52`
- Modify: `mariadb-runcloud-preset.md:91-108`
- Modify: `assets/woocommerce-query-pressure.svg`
- Modify: `assets/woocommerce-query-pressure-mobile.svg`

**Interfaces:**
- Consumes: WordPress option rows with `autoload` values.
- Produces: identical autoload-on filtering in aggregate audit SQL, top-20 audit SQL, and generated read-only follow-up SQL.

The exact autoload-on set is:

```sql
('yes','on','auto-on','auto')
```

The values `no`, `off`, and `auto-off` must remain excluded.

- [ ] **Step 1: Replace the unit test's incorrect three-value expectation**

Rename the current test to `autoload audit includes every WordPress 6.6 autoload-on value`. Record SQL calls and require the four-value set in both aggregate and top-20 queries.

```bash
expected="autoload IN ('yes','on','auto-on','auto')"
[[ $aggregate_query == *"$expected"* ]]
[[ $top_query == *"$expected"* ]]
[[ $aggregate_query != *"auto-off"* ]]
```

- [ ] **Step 2: Add a generated-diagnostic test**

Add `autoload diagnostic includes auto-on and excludes auto-off` to `test/unit/report.bats` and assert the output remains read-only, includes statement and connection timeouts, and contains:

```sql
WHERE autoload IN ('yes','on','auto-on','auto')
ORDER BY bytes DESC LIMIT 20
```

- [ ] **Step 3: Run unit tests and confirm both SQL paths omit auto-on**

```bash
bats --filter 'autoload audit includes every WordPress 6.6|autoload diagnostic includes auto-on' \
    test/unit/audit.bats test/unit/report.bats
```

- [ ] **Step 4: Update all three SQL statements**

Change the aggregate query, top-20 query, and generated action SQL to use the exact four-value set. Do not add WordPress version detection; querying for an unused enum value is harmless on older versions.

- [ ] **Step 5: Add a real SQL integration fixture**

In both MariaDB containers, create a temporary `wp_options` table and insert deterministic values:

| Option | Bytes | Autoload |
| --- | ---: | --- |
| `legacy_yes` | 1 | `yes` |
| `explicit_on` | 2 | `on` |
| `dynamic_on` | 4 | `auto-on` |
| `default_auto` | 8 | `auto` |
| `dynamic_off` | 32 | `auto-off` |
| `explicit_off` | 64 | `off` |

Source the real assembled artifact in a Bash subprocess and invoke `dbtune_audit_database_metrics` against the live database. Assert:

```text
app.0  autoload_bytes  15
app.0  autoload_count  4
```

Assert `dynamic_on:4` appears in `autoload.top.*` and neither excluded option appears.

- [ ] **Step 6: Update current documentation and diagrams**

Update README, tuning methodology, and both current WooCommerce SVGs to show `yes | on | auto-on | auto`. Do not change historical dated specs. Keep the mobile SVG text within its existing card width.

- [ ] **Step 7: Verify SQL, XML, and visual output**

```bash
bats --filter 'autoload' test/unit/audit.bats test/unit/report.bats
DBTUNE_REQUIRE_INTEGRATION=1 make integration
xmllint --noout assets/woocommerce-query-pressure.svg
xmllint --noout assets/woocommerce-query-pressure-mobile.svg
```

Open both SVGs at native size and render the mobile asset at approximately 350 px width. Confirm no clipping, overlap, or unreadable autoload text.

- [ ] **Step 8: Commit the autoload contract**

```bash
git add lib/20-audit.sh lib/50-report.sh test/unit/audit.bats \
    test/unit/report.bats test/integration/run.sh README.md \
    mariadb-runcloud-preset.md assets/woocommerce-query-pressure.svg \
    assets/woocommerce-query-pressure-mobile.svg
git commit -m "fix: include auto-on in WordPress autoload audits"
```

---

### Task 3: Document and Verify the P2 Contracts

**Files:**
- Modify: `README.md:138-165`
- Modify: `mariadb-runcloud-preset.md:847-870`

**Interfaces:**
- Documents: the expanded language-neutral listener enum and the distinction between wildcard exposure and a concrete network bind.

- [ ] **Step 1: Document listener enum semantics**

Document `public`, `network`, `local`, `not_listening`, and `unknown`, including the precedence used when multiple listeners exist.

- [ ] **Step 2: Document rule behavior**

State that wildcard listeners are high exposure, concrete network listeners require medium review, and loopback-only listeners do not produce network exposure findings by themselves.

- [ ] **Step 3: Run complete P2 verification**

```bash
make build
make check
make test
DBTUNE_REQUIRE_INTEGRATION=1 make integration
sh test/support/check-catalog.sh runtime lib/05-i18n.sh lib/*.sh
xmllint --noout assets/woocommerce-query-pressure.svg
xmllint --noout assets/woocommerce-query-pressure-mobile.svg
git diff --check
git status --short
```

- [ ] **Step 4: Commit remaining P2 documentation**

If listener documentation was not included in Task 1, commit it separately:

```bash
git add README.md mariadb-runcloud-preset.md
git commit -m "docs: clarify MariaDB listener scope"
```

If Task 1 already committed these exact documentation hunks, skip this commit rather than creating an empty commit.

## P2 Completion Gate

- [ ] Loopback, concrete network, wildcard, mixed, unrelated-port, unavailable-`ss`, and command-failure cases are covered by deterministic tests.
- [ ] `network` is present in fixtures, report output, documentation, and EN/SK presentation without changing the key name.
- [ ] Aggregate, top-20, and generated action SQL use the same four autoload-on values.
- [ ] Real MariaDB integration returns the expected 15 bytes and 4 autoloaded rows.
- [ ] Both SVG files pass XML validation and visual inspection.
- [ ] `make check`, `make test`, required integration, catalog validation, and `git diff --check` pass.
