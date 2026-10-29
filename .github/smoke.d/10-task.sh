#!/usr/bin/env bash
#
# The one task, `seed`, connects a workspace to the emulators and loads two
# years of a business: its listing is what a smoke run checks.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh

sudo morzer task list
