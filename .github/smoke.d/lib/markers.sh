# The bi project's marker: a fixed word written into Postgres, which the
# backup and rotation hooks read back. Sourced by a hook after
# /rig/smoke-lib.sh; no secret is ever read out here.
# shellcheck shell=bash

psql_bi() {
	sudo docker exec "$(service_container postgres)" \
		psql -U postgres -d bi -v ON_ERROR_STOP=1 -tAqc "$1"
}

write_marker() {
	psql_bi "create table if not exists smoke_marker (value text not null);
		delete from smoke_marker; insert into smoke_marker values ('$1')" >/dev/null
}

check_marker() {
	local database
	database=$(psql_bi "select value from smoke_marker")
	[ "${database}" = "$1" ] || die "smoke_marker reads '${database}', not '$1'"
	echo "${0##*/}: the marker reads $1"
}
