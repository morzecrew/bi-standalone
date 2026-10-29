# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The `bi` release bundle: a morzer `application-release` (`selfhost/v1alpha1`,
  morzer 0.8.0 or later) that deploys the whole BI system on one Linux machine —
  `bi-backend` (API and worker), `bi-frontend`, Postgres 18.6 and a Caddy edge
  serving the API and the frontend on one origin. `apply` sets the database
  password, migrates with flyway from the migrations image, runs the backend's
  `bootstrap` and records the schema; a smoke test probes the edge, the API and
  the frontend.
- Parameters for the ports, the API's workers, the log level, the model
  endpoint (`llm_base_url`, `llm_model`) and the Telegram bot
  (`telegram_enabled`, its links to `--domain`); every secret generated at `init` but
  `admin_password`, with placeholders for `llm_api_key` and
  `telegram_bot_token`.
- The dev-only task `seed` (`morzer task run seed -- --account beauty`), which
  starts the source emulators beside it and builds a demo workspace from two
  years of a generated business.
- CI: the components' `main` digests pinned on every publish (or every six
  hours), the bundle built, signed with the dev key, smoke-tested in dind rigs
  (install, task listing, backup and restore, database password rotation,
  update and rollback) and published to `ghcr.io/morzecrew/bi-standalone` as
  `:main`; a `vX.Y.Z` tag publishes the release `X.Y.Z`, signed with the
  release key, and moves `:stable`.
- `just` tasks for the gates (`just check`) and the pin, version and rehearsal
  helpers.
