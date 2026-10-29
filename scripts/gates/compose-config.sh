#!/usr/bin/env bash
# The Compose file is valid with only what morzer gives it.
set -euo pipefail

compose=bundle/compose/compose.yaml
# shellcheck source=scripts/gates/env.sh
. scripts/gates/env.sh
mapfile -t bi < <(env | grep '^BI_')
env -i PATH="${PATH}" HOME="${HOME}" "${bi[@]}" docker compose -f "${compose}" config -q
echo "compose-config: ${compose} is valid"
