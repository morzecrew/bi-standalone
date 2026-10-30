#!/usr/bin/env bash
#
# Write a marker, run the `reset` task, and fail unless the marker is gone and
# the database is migrated again. The probe bundle.yml runs after this hook
# proves the backend answers on the new database.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh
# shellcheck source=.github/smoke.d/lib/markers.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/markers.sh"

# A rehearsal runs the hooks against the published bundle, which may predate
# the task.
if ! sudo morzer task list --json | jq -e '.. | objects | select(.name? == "reset")' >/dev/null; then
	echo "40-reset.sh: the installed release has no reset task"
	exit 0
fi

write_marker reset
sudo morzer --verbose task run reset
[ "$(psql_bi "select count(*) from pg_tables where tablename = 'smoke_marker'")" = 0 ] \
	|| die "smoke_marker survived the reset"
[ "$(psql_bi "select count(*) > 0 from flyway_schema_history where success")" = t ] \
	|| die "the reset left the database unmigrated"
echo "40-reset.sh: the reset dropped the data and migrated again"
