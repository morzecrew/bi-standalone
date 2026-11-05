# bi

The BI system as one self-hosted stack, packaged as a signed [morzer][morzer]
release bundle. The stack is `bi-backend` (the API and its worker), `bi-frontend`
and Postgres, behind a Caddy edge that serves the API and the frontend on one
origin. A host is run with `morzer` alone, and no Compose file is edited on it.
[morzer's docs][docs] cover every command below.

[morzer]: https://github.com/morzecrew/morzer
[docs]: https://morzecrew.github.io/morzer/

## Requirements

- amd64, 4 GiB memory, and 20 GiB disk plus room for the data and the backups.
- Docker Engine 28.0.0 and Compose v2.35.0 or later, and morzer 0.8.0 or later.
- Ports 80 and 443, and 8081 on loopback. They are the parameters `http_port`,
  `https_port` and `health_port`.
- A domain (`--domain`). The auth cookies are `Secure`, so sign-in needs HTTPS.
- Root's Docker logged in to ghcr, since morzer pulls as root.

## Channels

| Tag | Channel |
|---|---|
| `:main` | dev: every component merge. It may be broken |
| `:stable` | releases: a `vX.Y.Z` tag on `main` that promotes a dev build |

`ghcr.io/morzecrew/bi-standalone:X.Y.Z` installs an exact version.

## Install

```console
printf %s "$GHCR_TOKEN" | sudo docker login ghcr.io -u <github-user> --password-stdin

sudo morzer init --product bi \
  --release oci://ghcr.io/morzecrew/bi-standalone:stable \
  --require-signature --signing-key "$MINISIGN_RELEASE_PUBKEY" \
  --domain bi.example.com \
  --recovery-recipient "$OFFLINE_AGE_RECIPIENT"

sudo morzer secret set admin_password    # the one secret you set; init generates the rest
sudo morzer apply

sudo morzer config set update.check=true \
  update.channel=oci://ghcr.io/morzecrew/bi-standalone:stable
sudo morzer secret set backup_s3         # the target's credentials, as YAML
sudo morzer backup target add s3://<bucket>/bi --credentials backup_s3
```

- **The recovery recipient** is the public half of an offline age key:
  `age-keygen -o bi-recovery.key`, then `age-keygen -y bi-recovery.key`. Keep the
  private half in a password manager, never on the VM.
- **A customer VM** leaves `update.auto_apply` off. Updates are staged, and a
  person installs them, with a backup taken first.
- **A dev VM** uses `--mode dev`, `:main` and `MINISIGN_DEV_PUBKEY`, and sets
  `update.auto_apply=true update.schedule='*:0/15' backup.before_update=false`.

## The model and Telegram

```console
sudo morzer secret set llm_api_key                                        # the endpoint's key
sudo morzer config set llm_base_url=https://<host>/v1 llm_model=<model>   # another endpoint
sudo morzer secret set telegram_bot_token                                 # from @BotFather
sudo morzer config set telegram_enabled=true
```

The chat, field proposals, the spec author and the summaries send their questions,
and the data read to answer them, to one OpenAI-compatible endpoint (DeepSeek's by
default). They fail until its key is set. Summaries and alerts go out through the
Telegram bot once it is enabled. Their links point at `--domain`.

## Tasks (dev machines only)

```console
sudo morzer task list
sudo morzer task run seed -- --account shop-custom|shop-vanilla|beauty --workspace demo
sudo morzer task run reset   # an empty system again: the admin and an empty `demo`
```

`seed` starts the source emulators and loads two years of a generated business into
a workspace, which then loads hourly. `reset` keeps the secrets, the settings and
the certificates.

## Operating

```console
sudo morzer status                      # what runs, and the installation id
sudo morzer doctor                      # read-only diagnostics
sudo morzer logs backend --tail 100     # secrets scrubbed
sudo morzer support                     # an evidence bundle to hand over
sudo morzer update --stage && sudo morzer update --to <version>
sudo morzer rollback [--to <version>]
sudo morzer backup && sudo morzer backup list
sudo morzer restore --backup <backup-id> --force --confirm <installation-id>
```

- **Updates** take a backup, migrate, start the services and run the smoke test.
  - A failure after the migrations, on a schema that didn't change, returns to
    the previous release by itself.
  - A failure in or after a schema change stops for a person. Run `doctor` and
    fix the cause, then `status --clear-intervention=` and `apply`, or restore
    the backup morzer names.
- **Rollback** works between releases that share a schema. Across a schema
  change, restore the pre-update backup instead.
- **Restore** the whole backup, never a single volume by hand.
- **The database password:** take a backup, run `secret rotate postgres_password`,
  then run `apply` straight after.
- **Never `docker image prune -a` or `docker system prune -a`.** They delete the
  previous release's images and the backup helper. morzer prunes on its own.
- **A lost machine** is rebuilt from the recovery key and a backup target:
  `installation import --from-backup`, then `update` to the version it prints,
  then `backup fetch` and `restore --identity`.

## Development

`just check` runs every gate CI runs, and `just --list` shows the rest: pin,
version and rehearse, which need a [bundle-ci](https://github.com/morzecrew/bundle-ci)
checkout. To release:
1. Set `rollback_safe` in `components.yaml` and the notes in `bundle/RELEASE.md`.
2. Tag `vX.Y.Z` on the `main` commit the dev VM runs; `morzer status` names it.
   Tag soon: a component image no release has tagged is pruned after a day.
