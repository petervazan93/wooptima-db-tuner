# Parallel CI gates design

Date: 2026-08-04
Status: approved

## Goal

Reduce dbtune CI and release wall-clock time by removing the duplicate full
Docker lifecycle run while preserving real MariaDB 10.6 and 11.4 coverage,
English and Slovak report coverage, release provenance, and all existing
safety gates.

## Current behavior

Both CI and release use one sequential job:

1. static and unit tests take about 18 minutes;
2. a full English Docker integration takes about 14 minutes;
3. the same full Docker integration under Slovak takes another 14 minutes.

Each integration invocation starts both MariaDB versions and runs a complete
audit, collection, analysis, report, proposal, apply, restart, and verification
lifecycle on each. The integration harness already renders and compares English
and Slovak reports and proposals inside every lifecycle. Repeating the complete
database mutation lifecycle only to change the outer interface language is
therefore redundant.

## CI architecture

The CI workflow will contain two independent jobs that start in parallel.

### Quality job

The `quality` job will:

- check out the exact commit;
- install Bats, ShellCheck, and Python 3;
- run `make check && make test`.

This remains the authoritative static and unit-test gate, including catalog
completeness, exact English and Slovak safety phrases, localized lifecycle
output, persisted collector language, and language-neutral analysis hashes.

### Integration job

The `integration` job will:

- check out the same commit;
- set `DBTUNE_REQUIRE_INTEGRATION=1`;
- set `DBTUNE_UI_LANG=en` for the canonical full lifecycle;
- run `make integration` once.

That single run continues to exercise MariaDB 10.6 and 11.4. For each database
version, the existing harness generates English and Slovak reports and
proposals, validates `report.language`, and compares canonical proposal records
before completing apply, restart, and post-restart verification.

The removed coverage is only a second execution of the same language-neutral
database mutation lifecycle with Slovak selected as the outer process language.
Slovak prompts, output, persistence, and recovery presentation remain covered
by focused unit tests and real Docker report/proposal rendering.

## Release architecture

The release workflow will contain three jobs.

### Quality and integration gates

`quality` and `integration` have the same responsibilities as in CI and run in
parallel against the exact tagged commit. They use read-only repository
permissions.

### Publish job

The `publish` job depends on both gates through:

```yaml
needs: [quality, integration]
```

It receives only the permissions required to publish and attest artifacts:

```yaml
permissions:
  contents: write
  id-token: write
  attestations: write
```

After both gates pass, the job checks out the same tag, runs `make build`,
verifies that the artifact version matches the tag, creates the existing
three-subject attestation, stages and verifies the offline bundle, and publishes
the existing four release assets.

The three attested subjects remain exactly:

- `dist/dbtune`;
- `dist/dbtune.sha256`;
- `install.sh`.

The published assets remain exactly:

- `dbtune`;
- `dbtune.sha256`;
- `dbtune-attestation.jsonl`;
- `install.sh`.

## Scope

The implementation changes only:

- `.github/workflows/ci.yml`;
- `.github/workflows/release.yml`.

The integration harness, Dockerfile, Compose configuration, runtime code,
tests, artifact contents, release tag policy, and attestation policy remain
unchanged.

## Failure behavior

- A failed `quality` or `integration` job fails CI.
- In the release workflow, any failed prerequisite prevents `publish` from
  starting.
- Docker unavailability remains a hard failure through
  `DBTUNE_REQUIRE_INTEGRATION=1`.
- Artifact publication cannot happen before both gates succeed.
- Tag/version, checksum, and provenance verification remain fail-closed.

## Expected result

PR and main CI wall-clock should fall from about 46 minutes to about 18-20
minutes because the 18-minute quality job and 14-minute integration job run in
parallel. Release wall-clock should fall to about 20-22 minutes, including the
short dependent publish job.

The optimization also reduces full Docker lifecycle executions from four to
two per workflow while retaining both tested MariaDB versions and both report
languages.

## Verification

- Parse both workflows as YAML.
- Assert the CI workflow contains independent `quality` and `integration` jobs.
- Assert the release workflow contains `quality`, `integration`, and a
  permission-scoped `publish` job with `needs: [quality, integration]`.
- Assert each workflow invokes `make integration` exactly once.
- Assert integration remains required and uses the canonical English outer
  language.
- Assert tag/version verification, attestation subjects, offline verification,
  and release asset publication commands remain unchanged.
- Run `make check` and the full unit suite.
- Push a PR and confirm that `quality` and `integration` start concurrently.
