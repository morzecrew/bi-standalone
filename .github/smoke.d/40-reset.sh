#!/usr/bin/env bash
#
# Write a marker, run the `reset` task, and fail unless the marker is gone and
# the database is migrated again. A file the worker writes into the lakes'
# volume must reach the API before the reset and be gone after it. The probe
# bundle.yml runs after this hook proves the backend answers on the new
# database.
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

# The backend image has no shell; its own Python reads and writes the file.
lake() {
	sudo docker exec "$(service_container "$1")" /opt/venv/bin/python -c "$2"
}
marker=/var/lib/bi/lake/smoke_marker
# A rehearsal's published bundle may predate the volume.
shared=false
sudo docker volume inspect bi_lake-data >/dev/null 2>&1 && shared=true

write_marker reset
if "${shared}"; then
	lake worker "open('${marker}', 'w').write('reset')"
	[ "$(lake backend "print(open('${marker}').read())")" = reset ] \
		|| die "the API does not see the file the worker wrote into the lakes' volume"
fi
sudo morzer --verbose task run reset
[ "$(psql_bi "select count(*) from pg_tables where tablename = 'smoke_marker'")" = 0 ] \
	|| die "smoke_marker survived the reset"
[ "$(psql_bi "select count(*) > 0 from flyway_schema_history where success")" = t ] \
	|| die "the reset left the database unmigrated"
if "${shared}"; then
	[ "$(lake backend "import os; print(os.path.exists('${marker}'))")" = False ] \
		|| die "the reset left the lakes' volume as it was"
fi
echo "40-reset.sh: the reset dropped the data and migrated again"
