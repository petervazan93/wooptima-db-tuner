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
sudo sh install.sh --version "$release"
```

The release can be pinned with `--version vX.Y.Z` or `DBTUNE_RELEASE=vX.Y.Z`. Neither `DBTUNE_VERSION` nor another runtime variable overrides the artifact's internal version. During its version check, the installer removes version/program override variables and never automatically runs audit, collection, apply, or restart. Current source is the `v0.4.1` release candidate, and its immutable artifact version is `0.4.1`.

The commands above target the `v0.4.1` release candidate and work after its tag and release assets are published. That artifact includes the `DBTUNE_UI_LANG` selector and the `fleet-v3` report schema.

The release workflow creates one SLSA provenance statement with three subjects: `dbtune`, `dbtune.sha256`, and `install.sh`. `dbtune-attestation.jsonl` is a published offline bundle, not a subject. `dbtune.sha256` contains the digest of `dbtune`. The manual preflight verifies the `install.sh` subject; the installer checks the checksum and verifies the `dbtune` subject against the upstream repository, owner, signer workflow, exact tag, and GitHub-hosted runner policy.

### v0.4.1 interface contract

The v0.4.1 installer and executable default to English. Set `DBTUNE_UI_LANG=sk` explicitly for the Slovak executable interface. Only `en` and `sk` are accepted; an unsupported non-empty value is rejected with exit status 64 before command dispatch or installer trust checks. The selected language never changes repository, provenance, checksum, publication, or runtime safety validation.

## Reporting issues

Report a security issue privately through [GitHub Private Vulnerability Reporting](https://github.com/petervazan93/wooptima-db-tuner/security/advisories/new). Do not put production credentials, `root.cnf`, `wp-config.php`, or unredacted audit artifacts in a public issue or report.
