# Security

## Instalacia

GitHub Releases je predvoleny transport. Interny `DBTUNE_DOWNLOAD_BASE` moze ukazat na kontrolovany HTTPS mirror; `file://` je urceny iba pre testy. Transport override nemeni upstream repository, vlastnika, signer workflow ani exact source-ref politiku a nemoze autorizovat vlastny fork build. `DBTUNE_REPOSITORY` nie je podporovane.

`DBTUNE_REPOSITORY` nie je podporovane. Upstream repository, ocakavany vlastnik, signer workflow a source ref tvoria jednu nemennu trust policy; operator nemoze prepisat iba download repository a ponechat nejasny povod. Distribucny mirror je bezpecny iba pre bajtovo identicke upstream artefakty s upstream atestaciou. Fork alebo mirror s vlastnym buildom moze ovladat svoj release, workflow aj bundle, preto musi udrziavat vlastny installer s kompletne explicitnou alternativnou politikou. Upstream installer takyto build odmietne namiesto automatickeho oslabenia alebo preladenia dovery.

Primarny postup nepouziva pipe do root shellu. Pripnite release, overte atestaciu installera, skontrolujte jeho obsah a az potom ho spustite:

```bash
release=v0.3.0
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

Release je mozne pripnut cez `--version vX.Y.Z` alebo `DBTUNE_RELEASE=vX.Y.Z`. `DBTUNE_VERSION` ani ina runtime premenna neprepisuje internu verziu artefaktu. Installer pri version checku odstrani version/program override premenne a nikdy automaticky nespusta audit, zber, apply ani restart.

Release workflow vytvori jednu SLSA provenance statement s tromi subjects: `dbtune`, `dbtune.sha256` a `install.sh`. `dbtune-attestation.jsonl` je publikovany offline bundle, nie subject. `dbtune.sha256` obsahuje digest `dbtune`. Manualny preflight overuje subject `install.sh`; installer kontroluje checksum a overuje subject `dbtune` voci upstream repository, vlastnikovi, signer workflowu, presnemu tagu a GitHub-hosted runner politike.

## Hlasenie problemov

Bezpecnostny problem nahlaste sukromne cez [GitHub Private Vulnerability Reporting](https://github.com/petervazan93/wooptima-db-tuner/security/advisories/new). Do verejneho issue ani reportu nevkladajte produkcne credentialy, `root.cnf`, `wp-config.php` ani neupravene auditne artefakty.
