# Parallel CI Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run static/unit verification and one complete two-version Docker lifecycle in parallel, then gate release publication on both results.

**Architecture:** Split CI into independent `quality` and `integration` jobs. Split release into parallel read-only `quality` and `integration` jobs followed by a permission-scoped `publish` job that rebuilds and publishes artifacts only after both gates pass.

**Tech Stack:** GitHub Actions YAML, GNU Make, Bats, ShellCheck, Docker Compose, GitHub artifact attestations.

## Global Constraints

- Change only `.github/workflows/ci.yml` and `.github/workflows/release.yml`.
- Run one full Docker integration invocation per workflow.
- Keep MariaDB 10.6 and 11.4 lifecycle coverage through the existing integration harness.
- Keep English and Slovak report/proposal rendering and canonical proposal comparison inside the existing integration harness.
- Set `DBTUNE_REQUIRE_INTEGRATION=1` and canonical outer `DBTUNE_UI_LANG=en` in each integration job.
- Keep release tag/version verification unchanged.
- Keep attestation subjects exactly `dist/dbtune`, `dist/dbtune.sha256`, and `install.sh`.
- Keep published assets exactly `dbtune`, `dbtune.sha256`, `dbtune-attestation.jsonl`, and `install.sh`.
- Grant write, OIDC, and attestation permissions only to the release `publish` job.
- Do not change runtime code, tests, Docker configuration, integration code, or artifact contents.

---

### Task 1: Parallelize CI gates

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `make check`, `make test`, and the existing `make integration` target.
- Produces: independent required checks named `quality` and `integration`.

- [ ] **Step 1: Run RED structural assertions**

Run assertions that require `jobs.quality`, `jobs.integration`, exactly one `make integration`, `DBTUNE_REQUIRE_INTEGRATION=1`, and `DBTUNE_UI_LANG=en`.

Expected: FAIL because the current workflow contains only `jobs.test` and two integration invocations.

- [ ] **Step 2: Replace the sequential job with two jobs**

Use this structure:

```yaml
permissions:
  contents: read

jobs:
  quality:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
      - name: Install test tools
        run: sudo apt-get update && sudo apt-get install -y bats shellcheck python3
      - name: Static and unit tests
        run: make check && make test

  integration:
    runs-on: ubuntu-24.04
    env:
      DBTUNE_REQUIRE_INTEGRATION: 1
      DBTUNE_UI_LANG: en
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
      - name: MariaDB lifecycle integration
        run: make integration
```

- [ ] **Step 3: Run GREEN structural and YAML assertions**

Verify both jobs exist, neither has `needs`, integration appears once, required environment values are exact, and the workflow parses as YAML.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: parallelize quality and integration gates"
```

### Task 2: Gate release publication on parallel verification

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: the same `quality` and `integration` contracts as Task 1.
- Produces: a `publish` job that runs only after both read-only gates succeed.

- [ ] **Step 1: Run RED release assertions**

Require `jobs.quality`, `jobs.integration`, `jobs.publish`, publish dependencies on both gates, exactly one integration invocation, and publish-only write/OIDC/attestation permissions.

Expected: FAIL because the current release workflow contains one sequential `release` job and two integration invocations.

- [ ] **Step 2: Add parallel read-only gates**

Set workflow-level permissions to `contents: read`. Add `quality` and `integration` jobs with the same commands and environment as the CI workflow.

- [ ] **Step 3: Move release operations into the dependent publish job**

Use:

```yaml
  publish:
    needs: [quality, integration]
    runs-on: ubuntu-24.04
    permissions:
      contents: write
      id-token: write
      attestations: write
```

The job checks out the tag, runs `make build`, then retains the existing tag/version, attestation, offline-bundle verification, and `gh release create` steps unchanged.

- [ ] **Step 4: Run GREEN release assertions**

Verify exact dependencies and permissions, one integration invocation, unchanged tag/version command, exact three attestation subjects, exact publication assets, and valid YAML.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: gate releases on parallel verification"
```

### Task 3: Verify the complete workflow change

**Files:**
- Review: `.github/workflows/ci.yml`
- Review: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: both workflow changes.
- Produces: a review-ready branch with local verification evidence.

- [ ] **Step 1: Parse both workflows**

Use Ruby safe YAML parsing with aliases enabled and confirm both documents load without syntax errors.

- [ ] **Step 2: Run all structural assertions together**

Confirm CI has two parallel jobs, release has two parallel gates plus dependent publish, and each workflow invokes `make integration` exactly once.

- [ ] **Step 3: Run project verification**

```bash
make check
make test
git diff --check
```

Expected: all 254 tests pass and no whitespace errors are reported.

- [ ] **Step 4: Review the branch diff**

Confirm no file outside the design document, this plan, and the two workflow files changed. Confirm release permissions and provenance commands remain fail-closed.

- [ ] **Step 5: Request code review and prepare PR**

The PR must state that one full integration still covers both MariaDB versions and both report languages, while the duplicate outer Slovak lifecycle was removed. Confirm on GitHub that `quality` and `integration` start concurrently.
