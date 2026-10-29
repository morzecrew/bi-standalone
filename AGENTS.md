# bi-standalone

The BI system's release bundle: one morzer `application-release` (`bundle/`)
that runs bi-backend, bi-frontend and Postgres behind one Caddy edge, and the
workflows that pin, build, sign, smoke-test and publish it. README is the
operator's runbook; this file is the working agreement.

## Layout

- `bundle/` — what ships: `manifest.yaml` (morzer's `selfhost/v1alpha1`
  schema), `compose/compose.yaml`, `secrets.schema.yaml`, `edge/bi.caddy`,
  `hooks/` (POSIX sh, results as JSON on fd `${BI_RESULT_FD:-3}`, honouring
  `BI_DRY_RUN`) and `RELEASE.md`.
- `components.yaml` — the component versions a release (`--release`) pins.
- `scripts/` — `pin.sh` (writes the component digests and the schema into the
  manifest), `resolve.sh`, `version.sh` (the next dev version), `rehearse.sh`
  (a workstation rehearsal in a dind rig), and `gates/` behind the justfile.
- `.github/workflows/` — `main.yml` (the dev channel: pin on a component's
  `repository_dispatch`, a push or every six hours, then `bundle.yml` and
  `publish.yml` to `:main`), `pr.yml`, `release.yml` (a `vX.Y.Z` tag to
  `:stable`), `retention.yml`; `scripts/` holds their shell.
- `tests/` — the pin and version scripts' tests and the edge smoke's stand-ins.

## Rules

- Compose reads only what morzer hands it (`BI_IMAGE_*`, `BI_PARAM_*`,
  `BI_SECRETS_DIR`, `BI_RELEASE_DIR`, `BI_DOMAIN`, `BI_VERSION`); an image is
  named only through its pin, a setting only through a parameter, a secret only
  as a `*_FILE` under `/run/secrets` that the backend image's `ENVFILE_NAMES`
  lists.
- `metadata.name` (`bi`) and the Compose project (`bi`) never change: every
  path, variable and volume hangs off them.
- The component pins and `compatibility.database_schema_*` are `pin.sh`'s, not
  a person's; the migrations image's `tech.morze.bi.schema` label is the
  schema.
- Every migrate step is harmless to repeat. A new secret has a generator, or
  a placeholder one when the operator sets the real value later.
- `just check` passes before a pull request. Commits are gitmoji-conventional,
  one branch per change off `main`, squash-merged; record operator-facing
  changes in `CHANGELOG.md` and the next bundle's notes in `bundle/RELEASE.md`.
- No product names: say "BI system".
