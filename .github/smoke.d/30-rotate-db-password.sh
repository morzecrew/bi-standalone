#!/usr/bin/env bash
#
# Write `rotated`, rotate `postgres_password`, apply, and fail unless the
# marker still reads `rotated`. Apply's flyway and bootstrap have connected
# with the new password by then, and the probe bundle.yml runs after this
# hook proves the backend has.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh
# shellcheck source=.github/smoke.d/lib/markers.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/markers.sh"

# The marker is written once, before the rotation, and read after it: what it
# proves is that the data is still there behind the new password.
write_marker rotated
sudo morzer secret rotate postgres_password
sudo morzer --verbose apply
check_marker rotated
echo "30-rotate-db-password.sh: the rotated database password reached the role"
