# Wooptima DB Tuner v0.4.1 branding and installation design

## Goal

Present the product consistently as **Wooptima DB Tuner**, simplify the
homepage installation path to one pinned command, and publish the result as
the attested `v0.4.1` release.

## Naming boundary

`Wooptima DB Tuner` is the human-facing product name. Use it in headings,
descriptive prose, audit summaries, generated report text, installer status
messages, generated CNF comments, systemd descriptions, and the homepage
preview.

`dbtune` remains the stable technical identity. Do not rename the CLI command,
binary, version output prefix, artifact names, attestation subjects, repository
slug, filesystem paths, environment variables, shell functions, systemd unit
files, JSON keys, schema fields, or diagnostic `dbtune:` CLI prefix.

Historical design and implementation-plan documents remain unchanged. Active
documentation may distinguish the product from the CLI with wording such as
"Wooptima DB Tuner, exposed through the `dbtune` CLI".

## Installation

The README primary installation command is pinned to the immutable `v0.4.1`
release:

```bash
curl -fsSL https://github.com/petervazan93/wooptima-db-tuner/releases/download/v0.4.1/install.sh | sh -s -- --version v0.4.1
```

The installer runs unprivileged and invokes `sudo` only when publishing into a
privileged install directory. It continues to verify the selected `dbtune`
artifact checksum, GitHub attestation, repository, signer workflow, source tag,
syntax, and embedded artifact version.

README must state the remaining trust boundary plainly: the pipeline executes
the remote `install.sh` before that script can verify the `dbtune` artifact.
Operators who need to verify installer provenance before execution are directed
to the pinned, inspectable procedure in `SECURITY.md`.

## Release boundary

The source artifact version becomes `0.4.1`; `dbtune version` remains exactly
`dbtune 0.4.1`. Current release badges, installation examples, fixtures, and
release-preparation prose move to `v0.4.1`.

References to the pre-v0.4.0 `reason_sk` schema and instructions to start a new
v0.4.0 measurement cycle remain unchanged because they describe a data-contract
boundary rather than the latest release.

## Verification and publication

User-visible English and Slovak output is covered by focused Bats and
integration expectations before implementation changes. The complete release
candidate must pass build, static checks, unit tests, and Docker integration.

After review, commit and push the candidate to `main`, create and push tag
`v0.4.1`, wait for the release workflow, and verify the four release assets,
checksum, installer and executable attestations, artifact version, and pinned
download URL. Never move or replace the published tag; a post-tag code defect
requires a later patch release.
