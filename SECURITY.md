# Security

## Instalacia

`install.sh` stahuje iba artefakty z GitHub Releases cez HTTPS, kontroluje SHA-256 a Bash syntax a az potom publikuje `/usr/local/bin/dbtune` atomickym `mv`.

Pre maximalnu kontrolu nepouzivajte pipe priamo do shellu:

```bash
curl --proto '=https' --tlsv1.2 -fsSLo install.sh \
  https://github.com/petervazan93/wooptima-db-tuner/releases/download/v0.1.0/install.sh
less install.sh
sudo sh install.sh --version v0.1.0
```

Release je mozne pripnut cez `DBTUNE_VERSION=vX.Y.Z`. Installer nikdy automaticky nespusta audit, zber, apply ani restart.

## Hlasenie problemov

Bezpecnostny problem nepublikujte s produkcnymi credentialmi, `root.cnf`, `wp-config.php` ani neupravenymi auditnymi artefaktmi. Kontaktujte vlastnika repozitara sukromnym kanalom cez GitHub profil.
