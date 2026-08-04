# Wooptima DB Tuner v0.4.1 Branding and Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brand all human-facing output as Wooptima DB Tuner, provide a pinned one-line installer, and publish the verified `v0.4.1` release.

**Architecture:** Preserve `dbtune` as the stable technical interface while changing only display copy and active documentation. Keep the existing installer trust checks and release workflow, changing the immutable artifact version and documentation pin together.

**Tech Stack:** POSIX sh installer, Bash 4+ application, Bats, ShellCheck, Docker Compose, GitHub Actions attestations and releases.

## Global Constraints

- The product display name is exactly `Wooptima DB Tuner`.
- The CLI command, binary, version prefix, paths, artifacts, repository slug, variables, functions, service unit names, schema keys, and `dbtune:` diagnostic prefix remain `dbtune`.
- `dbtune version` must print exactly `dbtune 0.4.1`.
- The README primary command must be exactly `curl -fsSL https://github.com/petervazan93/wooptima-db-tuner/releases/download/v0.4.1/install.sh | sh -s -- --version v0.4.1`.
- README must say that the one-liner trusts remote `install.sh` before artifact verification and link to `SECURITY.md` for verify-before-run installation.
- Historical files under `docs/superpowers/specs` and `docs/superpowers/plans` are not renamed or rewritten, except for the two documents created for this change.
- Pre-v0.4.0 schema compatibility messages remain pinned to `v0.4.0`.
- Do not create or move a tag until all local checks and reviews pass.

---

### Task 1: Runtime product branding

**Files:**
- Modify: `test/unit/audit.bats`
- Modify: `test/unit/report.bats`
- Modify: `test/unit/collect.bats`
- Modify: `test/unit/lifecycle.bats`
- Modify: `test/integration/run.sh`
- Modify: `lib/05-i18n.sh`
- Modify: `systemd/dbtune-collect.service`
- Modify: `systemd/dbtune-collect.timer`

**Interfaces:**
- Consumes: Existing `dbtune_i18n` message IDs and generated report/CNF contracts.
- Produces: Human-facing EN/SK output branded `Wooptima DB Tuner`; unchanged commands and machine identifiers.

- [ ] Update literal behavior expectations for audit status, report headings and metadata, safety text, generated CNF comments, backup/rollback prose, help descriptions, and automatic reports.
- [ ] Run focused Bats tests and confirm they fail because runtime output still says `dbtune` or `DBTune`.
- [ ] Change only human-facing messages in `lib/05-i18n.sh`; retain command examples, `dbtune:` diagnostics, paths, and machine contracts.
- [ ] Brand both systemd `Description=` values while retaining unit names and `ExecStart=/usr/local/bin/dbtune _tick`.
- [ ] Re-run the focused Bats tests and confirm they pass.
- [ ] Run `make check` and commit with `feat: brand Wooptima DB Tuner output`.

### Task 2: Installer branding and v0.4.1 artifact contract

**Files:**
- Modify: `test/unit/install.bats`
- Modify: `test/unit/core.bats`
- Modify: `lib/00-header.sh`
- Modify: `install.sh`

**Interfaces:**
- Consumes: Existing fixed upstream attestation policy and `dbtune version` parser.
- Produces: Artifact version `0.4.1`, version output `dbtune 0.4.1`, and branded installer display messages.

- [ ] Update installer and core expectations from `v0.4.0`/`0.4.0` to `v0.4.1`/`0.4.1`, including stub source refs and latest metadata.
- [ ] Update installer status expectations to `Wooptima DB Tuner install: ...` while retaining technical paths and the `sudo dbtune audit --json` next step.
- [ ] Run `bats test/unit/core.bats test/unit/install.bats` and confirm failures are caused by the old version and display text.
- [ ] Set `DBTUNE_ARTIFACT_VERSION=0.4.1` and update only installer human-facing branding; retain artifact names, trust policy, and the parser requirement `$1 == "dbtune"`.
- [ ] Re-run the focused tests and `make check`; confirm both pass.
- [ ] Commit with `release: prepare Wooptima DB Tuner v0.4.1`.

### Task 3: Homepage, active documentation, and preview

**Files:**
- Modify: `README.md`
- Modify: `SECURITY.md`
- Modify: `docs/RUNBOOK.md`
- Modify: `PLAN.md`
- Modify: `assets/dbtune-audit.svg`

**Interfaces:**
- Consumes: Published product naming boundary and `v0.4.1` artifact contract.
- Produces: A concise pinned homepage install path and an explicit remote-installer trust warning.

- [ ] Change active product headings and prose to `Wooptima DB Tuner`, retaining inline `dbtune` where it denotes a command, artifact, path, or schema identity.
- [ ] Replace the README attested command block with the exact pinned one-liner from Global Constraints, list Linux/Bash/curl/gh prerequisites briefly, and link to `SECURITY.md#installation`.
- [ ] Add a short explicit note that the pipeline trusts remote `install.sh` before it verifies the downloaded `dbtune` artifact.
- [ ] Pin the full inspectable procedure in `SECURITY.md` to `v0.4.1`; update current release-preparation prose while retaining v0.4.0 schema-history statements.
- [ ] Update the accessible and visible SVG audit title to `Wooptima DB Tuner` without renaming the asset file.
- [ ] Inspect the rendered Markdown structure and run `make check`.
- [ ] Commit with `docs: simplify pinned Wooptima DB Tuner installation`.

### Task 4: Full verification and release publication

**Files:**
- Generated, not tracked: `dist/dbtune`
- Generated, not tracked: `dist/dbtune.sha256`
- Verify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: Complete reviewed `v0.4.1` source and documentation.
- Produces: GitHub release `v0.4.1` with verified assets and attestations.

- [ ] Run `make build` and verify `dist/dbtune version` prints exactly `dbtune 0.4.1`.
- [ ] Run `make check`, `make test`, and `make integration`; require all available checks to pass without warnings or skips forbidden by CI.
- [ ] Review `git status`, `git diff`, and recent commits; ensure only intended tracked files are included.
- [ ] Run a final whole-change code review and address all load-bearing findings before publication.
- [ ] Push `main`, create annotated tag `v0.4.1`, and push the tag without force.
- [ ] Wait for `.github/workflows/release.yml` to complete successfully.
- [ ] Download `dbtune`, `dbtune.sha256`, `dbtune-attestation.jsonl`, and `install.sh`; verify the checksum and GitHub attestations for both `dbtune` and `install.sh` against `refs/tags/v0.4.1`.
- [ ] Verify the pinned README URL resolves and the downloaded executable prints `dbtune 0.4.1`.
