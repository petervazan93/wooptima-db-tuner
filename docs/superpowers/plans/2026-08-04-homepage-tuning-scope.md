# Homepage Tuning Scope and Infographics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an accurate WooCommerce tuning scope, representative MariaDB decision logic, and two accessible infographics to the GitHub homepage.

**Architecture:** Keep the homepage layered: application-first explanation, executable server formulas, then existing operational lifecycle and safety content. SVG assets are standalone presentation units; README consumes both through relative links.

**Tech Stack:** GitHub Markdown, static accessible SVG, Bash/Bats verification.

## Global Constraints

- Exact product name: `Wooptima DB Tuner`; exact technical CLI name: `dbtune`.
- Homepage copy is English and follows `lib/40-rules.sh` plus `lib/20-audit.sh`.
- Application findings are recommendation-only and no production evidence is shown.
- Say `29 version-gated proposal keys`, not 29 changes on every server.
- Preserve pre-v0.4.0 schema-history text and all runtime contracts.
- Both SVGs use a 1200-pixel viewBox, accessible `title`/`desc`, GitHub dark colors, and no external assets.

---

### Task 1: WooCommerce query-pressure infographic

**Files:**
- Create: `assets/woocommerce-query-pressure.svg`

**Interfaces:**
- Consumes: Application thresholds and recommendation-only boundary from the design.
- Produces: A 1200 by 620 accessible SVG referenced by README.

- [ ] Create the request-path diagram and four diagnostic cards with the exact approved thresholds.
- [ ] Run `xmllint --noout assets/woocommerce-query-pressure.svg` and inspect the rendered asset for clipping.
- [ ] Confirm the SVG contains no production identity, benchmark, external font, script, or remote asset.

### Task 2: MariaDB sizing-logic infographic

**Files:**
- Create: `assets/mariadb-sizing-logic.svg`

**Interfaces:**
- Consumes: Versioned evidence schema and representative executable formulas.
- Produces: A 1200 by 680 accessible SVG referenced by README.

- [ ] Create the metrics strip, five formula cards, and fail-closed footer using exact approved values.
- [ ] Run `xmllint --noout assets/mariadb-sizing-logic.svg` and inspect the rendered asset for clipping.
- [ ] Compare every number and operator with `lib/40-rules.sh` before accepting the asset.

### Task 3: Homepage content and layout

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Both SVG asset paths and all copy from the design.
- Produces: New `#woocommerce-tuning-scope` and `#how-mariadb-targets-are-calculated` homepage anchors.

- [ ] Update navigation and published `v0.4.1` wording.
- [ ] Insert the application-first section, first infographic, checks table, and no-mutation explanation.
- [ ] Insert the server-decision section, second infographic, formula table, diagnostic-evidence note, and collapsed 29-key catalog.
- [ ] Verify image paths and headings resolve and that existing Lifecycle, Safety, Install, CLI, and Documentation sections remain intact.

### Task 4: Cross-check and full verification

**Files:**
- Verify: `README.md`
- Verify: `assets/woocommerce-query-pressure.svg`
- Verify: `assets/mariadb-sizing-logic.svg`
- Verify: `lib/40-rules.sh`
- Verify: `lib/20-audit.sh`

**Interfaces:**
- Consumes: Complete documentation change.
- Produces: Review-ready homepage with no unsupported tuning claims.

- [ ] Cross-check application thresholds, formulas, the 29-key catalog, and recommendation-only boundaries against executable code.
- [ ] Run `xmllint --noout` for both SVGs, `make check`, `make test`, and `git diff --check`.
- [ ] Review the complete diff for visual accessibility, mobile readability, stale release wording, and accidental runtime changes.
