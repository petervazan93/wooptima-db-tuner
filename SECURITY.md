# Security

## Instalacia

`install.sh` stahuje iba artefakty z GitHub Releases cez HTTPS, kontroluje SHA-256, GitHub keyless artifact attestation a Bash syntax a az potom publikuje `/usr/local/bin/dbtune` atomickym `mv`. Overenie je fail-closed: vyzaduje `gh` CLI a pevne kontroluje zdrojovy repozitar aj jeho vlastnika cez `--repo petervazan93/wooptima-db-tuner`, signer `petervazan93/wooptima-db-tuner/.github/workflows/release.yml`, presny release source ref a GitHub-hosted runner.

`DBTUNE_REPOSITORY` nie je podporovane. Upstream repository, ocakavany vlastnik, signer workflow a source ref tvoria jednu nemennu trust policy; operator nemoze prepisat iba download repository a ponechat nejasny povod. Distribucny mirror je bezpecny iba pre bajtovo identicke upstream artefakty s upstream atestaciou. Fork alebo mirror s vlastnym buildom moze ovladat svoj release, workflow aj bundle, preto musi udrziavat vlastny installer s kompletne explicitnou alternativnou politikou. Upstream installer takyto build odmietne namiesto automatickeho oslabenia alebo preladenia dovery.

Primarny postup nepouziva pipe do root shellu. Pripnite release, overte atestaciu installera, skontrolujte jeho obsah a az potom ho spustite:

```bash
release=v0.2.0
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

Release workflow pouziva GitHub OIDC a kratkodoby Sigstore certifikat; projekt neuchovava dlhodoby privatny signing key. `dbtune`, checksum aj `install.sh` dostanu jednu SLSA provenance attestation publikovanu aj ako offline `dbtune-attestation.jsonl`. Samotny checksum chrani konzistenciu release suborov, kym atestacia viaze ich digesty na konkretnu GitHub Actions signer identitu a tag bez potreby GitHub API autentizacie na cielovom serveri.

## Hlasenie problemov

Bezpecnostny problem nepublikujte s produkcnymi credentialmi, `root.cnf`, `wp-config.php` ani neupravenymi auditnymi artefaktmi. Kontaktujte vlastnika repozitara sukromnym kanalom cez GitHub profil.
