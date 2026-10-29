#!/usr/bin/env bash
# The bundle builds and verifies as morzer would release it, rendered once: from
# a copy of the tracked files, so a build output in the tree changes nothing.
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
git ls-files -z --cached --others --exclude-standard -- bundle | xargs -0 cp --parents -t "${work}"
rm -f "${work}/bundle/SHA256SUMS" "${work}/bundle/SHA256SUMS.minisig"
morzer release build "${work}/bundle" --version 0.0.1-gate.1
morzer release verify "${work}/bundle" --render-check
