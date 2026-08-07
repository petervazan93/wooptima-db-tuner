# Security

## Installation

GitHub Releases is the default transport. The internal `DBTUNE_DOWNLOAD_BASE` may point to a controlled HTTPS mirror; `file://` is intended for tests only. A transport override does not change the upstream repository, owner, signer workflow, or exact source-ref policy and cannot authorize a custom fork build. `DBTUNE_REPOSITORY` is not supported.

`DBTUNE_REPOSITORY` is not supported. The upstream repository, expected owner, signer workflow, and source ref form one immutable trust policy; an operator cannot override only the download repository and leave provenance ambiguous. A distribution mirror is safe only for byte-identical upstream artifacts with upstream attestation. A fork or mirror with its own build can control its release, workflow, and bundle, so it must maintain its own installer with a completely explicit alternative policy. The upstream installer rejects such a build instead of automatically weakening or retargeting trust.

The primary procedure does not pipe code into a root shell. Pin the release, verify the installer attestation, inspect its contents, and only then run it:

```bash
release=v0.4.1
curl --proto '=https' --tlsv1.2 -fsSLo install.sh \
  "https://github.com/petervazan93/wooptima-db-tuner/releases/download/$release/install.sh"
curl --proto '=https' --tlsv1.2 -fsSLo dbtune-attestation.jsonl \
  "https://github.com/petervazan93/wooptima-db-tuner/releases/download/$release/dbtune-attestation.jsonl"
gh attestation verify install.sh \
  --bundle dbtune-attestation.jsonl \
  --repo petervazan93/wooptima-db-tuner \
  --signer-workflow petervazan93/wooptima-db-tuner/.github/workflows/release.yml \
  --source-ref "refs/tags/$release" \
  --deny-self-hosted-runners
less install.sh
sh install.sh --version "$release"
```

The release can be pinned with `--version vX.Y.Z` or `DBTUNE_RELEASE=vX.Y.Z`. Neither `DBTUNE_VERSION` nor another runtime variable overrides the artifact's internal version or profile. During its version check, the installer removes version/program override variables and never automatically runs audit, collection, apply, or restart. Current source is the `v0.4.1` release candidate, and its immutable artifact version is `0.4.1`.

The commands above target the `v0.4.1` release candidate and work after its tag and release assets are published. That artifact includes the `DBTUNE_UI_LANG` selector and the `fleet-v3` report schema.

The release workflow creates one SLSA provenance statement with three subjects: `dbtune`, `dbtune.sha256`, and `install.sh`. `dbtune-attestation.jsonl` is a published offline bundle, not a subject. `dbtune.sha256` contains the digest of `dbtune`. The manual preflight verifies the `install.sh` subject; the installer checks the checksum and verifies the `dbtune` subject against the upstream repository, owner, signer workflow, exact tag, and GitHub-hosted runner policy. It then requires exactly one immutable `production` profile marker and rejects `source-test` and `integration-test`; the release gate enforces the same production-only boundary and the absence of `dist/dbtune-integration`.

For a privileged destination, the installer first creates a root-owned `0644` non-executable staging inode in the trusted destination directory. It verifies that inode's checksum, attestation, Bash syntax, and embedded version before changing it to `0755`, directly executes the staged path for its executable version smoke check, and revalidates the inode and destination path. Only then does `mv` atomically publish that same inode; no bytes are copied after their final trust verification.

### v0.4.1 interface contract

The v0.4.1 installer and executable default to English. Set `DBTUNE_UI_LANG=sk` explicitly for the Slovak executable interface. Only `en` and `sk` are accepted; an unsupported non-empty value is rejected with exit status 64 before command dispatch or installer trust checks. The selected language never changes repository, provenance, checksum, publication, or runtime safety validation.

## Production runtime boundary

Source modules, production artifacts, and integration artifacts embed immutable `source-test`, `production`, and `integration-test` profiles. Environment values cannot change the selected profile, and the production artifact rejects sourcing before command functions are defined; execute it directly or with `bash`.

The complete production-executable operator allowlist is:

```text
DBTUNE_UI_LANG
DBTUNE_STATE_DIR
DBTUNE_CONFIG_TARGET
DBTUNE_CONFIG_ALLOWED_DIR
DBTUNE_ROOT_CNF
DBTUNE_LOG_LEVEL
DBTUNE_MAX_BACKUP_AGE_SECONDS
```

Before dispatch, production fixes `PATH`, `LC_ALL`, and `LANG`, restores internal program/authentication defaults, removes inherited functions, and unsets every other exported `DBTUNE_*` variable. Test-only command and path substitutions, SQL-authentication inputs, clocks, ownership/mode changes, fault hooks, and sample thresholds therefore cannot influence a release artifact. Integration tests use a separate immutable artifact rather than weakening production.

## Forward apply and recovery

Interactive `--force` bypasses only measurement/analysis and proposal-manifest provenance, including its analysis-derived proposal mapping, the normal requirement for state `proposed` (force accepts `audited`, `analyzed`, or `proposed`), and the 05:30-07:30 local window. It does not bypass strict proposal parsing and exact snapshot binding, authenticated audit provenance, complete safe loaded-default evidence, live variable-name existence, blocking findings in any present analysis, Galera, mydumper, backup, target/topology/ownership, atomic publication, daemon validation, restart, rollback, or recovery guards.

Audit enumerates effective startup options from daemon `--print-defaults`; apply requires that audit evidence and repeats the scan after its other forward preflights, immediately before it creates new apply history and mutation intent. A failed audit/scan or a loaded critical removed option blocks normal and forced apply. Rollback, failed-apply restoration, and crash recovery never invoke the scanner or depend on the current audit, so forward evidence failure cannot prevent restoration. Old history remains rollbackable; newly created history binds the final scan evidence.

Enabling `skip_name_resolve` additionally requires a complete, unique, valid enumeration of account hosts from `mysql.user`, with `security.grants_audited=1` and `security.hostname_grant_count=0`. Missing, malformed, duplicate, or hostname-dependent grant evidence fails closed. Reports publish only counts and status, not account names or hosts.

## Reporting issues

Report a security issue privately through [GitHub Private Vulnerability Reporting](https://github.com/petervazan93/wooptima-db-tuner/security/advisories/new). Do not put production credentials, `root.cnf`, `wp-config.php`, or unredacted audit artifacts in a public issue or report.
