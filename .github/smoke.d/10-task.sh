#!/usr/bin/env bash
#
# The tasks: `seed` connects a workspace to the emulators and loads two years
# of a business, which a smoke run only lists; `reset`'s hook runs it.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh

sudo morzer task list
