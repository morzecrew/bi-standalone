#!/usr/bin/env bash
#
# Smoke-test a bundle archive on the runner, the way a machine installs it.
#
#   smoke.sh install <archive> <pubkey>...  fresh `sudo morzer init` and `apply`
#   smoke.sh update <archive>               `sudo morzer update` to the archive
#   smoke.sh task                           `morzer task list`
#   smoke.sh probe                          the edge's loopback health port
#   smoke.sh backup-restore                 back up, write over it, restore, check
#   smoke.sh rotate-db-password             rotate the database password, apply, read
#   smoke.sh rollback <published> <new>     `sudo morzer rollback` from <new> to <published>
#   smoke.sh diagnose                       `morzer status` and the Compose logs
#   smoke.sh free-disk                      room for the release's disk requirement
#
# `install` trusts every key it is given and refuses an unsigned release. It
# sets `admin_password`, the one secret the operator sets, from `random`;
# `init` generates the rest, and nothing here prints a secret.
#
# `backup-restore` writes the marker `before` into Postgres, backs up, writes
# `after`, restores, and fails unless it reads `before` again.
# `rotate-db-password` writes `rotated`, rotates `postgres_password` and
# applies, whose flyway and bootstrap connect with the rotated password before
# anything starts; then the marker must read `rotated` and the edge answer.
# `rollback` passes when the rollback succeeds, or when morzer refuses it
# (exit 9) and either the new archive declares `rollback_safe: false` or the
# two archives produce different database schemas.
# The markers are fixed words; no secret is ever read out here.
set -euo pipefail

health_port=8081
# morzer pulls the image a backup reads its volumes through itself, on `apply`
# and on `update` (morzer#142), so nothing here pulls it.

die() {
	echo "smoke.sh: $*" >&2
	exit 1
}

random() {
	openssl rand -hex 24
}

install_release() {
	local archive=$1 key
	shift
	local keys=()
	for key in "$@"; do
		[ -n "${key}" ] && keys+=(--signing-key "${key}")
	done
	[ ${#keys[@]} -gt 0 ] || die "install needs at least one signing key"

	sudo morzer init --mode dev --release "${archive}" --require-signature \
		--no-recovery-recipient --install-units=false "${keys[@]}"

	random | sudo morzer secret set admin_password

	# --verbose: morzer prints a one-shot's output, a migration's error, only then.
	sudo morzer --verbose apply
}

# The running container of one of the bi project's services, by the labels
# Compose puts on it. A restore recreates it, so each call looks it up again.
service_container() {
	local container
	container=$(sudo docker ps --quiet \
		--filter label=com.docker.compose.project=bi \
		--filter "label=com.docker.compose.service=$1" | sed -n 1p)
	[ -n "${container}" ] || die "no running $1 container of the bi project"
	printf '%s\n' "${container}"
}

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
	echo "smoke.sh: the marker reads $1"
}

backup_restore() {
	local out id installation
	write_marker before

	# Under --json morzer's error is only in the envelope on stdout.
	if ! out=$(sudo morzer backup --reason smoke --json); then
		printf '%s\n' "${out}" >&2
		exit 1
	fi
	id=$(jq -r '.data.id // .data.backup.id // .data.backup_id // empty' <<<"${out}")
	[ -n "${id}" ] || die "morzer backup reported no backup id"
	echo "smoke.sh: backup ${id}"

	write_marker after
	check_marker after

	installation=$(sudo morzer status --json | jq -r '.data.installation_id // .data.installation.id // empty')
	[ -n "${installation}" ] || die "morzer status reported no installation id"
	sudo morzer --verbose restore --backup "${id}" --force --confirm "${installation}"
	check_marker before
}

rotate_db_password() {
	# The marker is written once, before the rotation, and read after it: what
	# it proves is that the data is still there behind the new password, which
	# apply's flyway and bootstrap have already connected with.
	write_marker rotated
	sudo morzer secret rotate postgres_password
	sudo morzer --verbose apply
	check_marker rotated
	probe
	echo "smoke.sh: the rotated database password reached the role and the backend"
}

# A field an archive's manifest declares, by its key: `rollback_safe`,
# `database_schema_produces`.
manifest_field() {
	local manifest
	manifest=$(tar -I zstd -tf "$1" | grep -E '(^|/)manifest\.yaml$' | awk '{ print length, $0 }' \
		| sort -n | sed -n '1s/^[0-9]* //p')
	[ -n "${manifest}" ] || die "$1 holds no manifest.yaml"
	tar -I zstd -xOf "$1" "${manifest}" \
		| sed -n "s/^[[:space:]]*$2:[[:space:]]*\([^[:space:]#]*\).*/\1/p" | sed -n 1p
}

rollback() {
	local published=$1 new=$2 status=0 from to
	sudo morzer --verbose rollback || status=$?
	[ "${status}" -ne 0 ] || { echo "smoke.sh: rolled back"; return; }
	[ "${status}" -eq 9 ] || die "morzer rollback exited ${status}"
	# A release takes rollback_safe from components.yaml, and false refuses
	# any rollback from it, on one schema or not.
	if [ "$(manifest_field "${new}" rollback_safe)" = false ]; then
		echo "smoke.sh: rollback refused, as the new release declares rollback_safe: false"
		return
	fi
	from=$(manifest_field "${new}" database_schema_produces)
	to=$(manifest_field "${published}" database_schema_produces)
	[ -n "${from}" ] && [ -n "${to}" ] || die "an archive declares no database_schema_produces"
	[ "${from}" != "${to}" ] \
		|| die "morzer rollback refused (exit 9) between two releases on schema ${from}"
	echo "smoke.sh: rollback refused across the schema change ${from} -> ${to}, as it must be"
}

probe() {
	local path
	for path in /__platform_healthz /health; do
		curl -fsS --max-time 10 --retry 10 --retry-delay 3 --retry-all-errors \
			-o /dev/null "http://127.0.0.1:${health_port}${path}" \
			|| die "127.0.0.1:${health_port}${path} did not answer 2xx"
		echo "smoke.sh: ${path} ok"
	done
}

# A hosted runner's root has about 14 GiB free, and the release's preflight
# wants 20 GiB under /var/lib/bi; the preinstalled toolchains hold about 25.
free_disk() {
	[ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] \
		|| die "free-disk deletes the runner's toolchains; GitHub-hosted runners only"
	sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /opt/hostedtoolcache/CodeQL
	df -h /
}

diagnose() {
	sudo morzer status || true
	# The manifest's Compose project.
	sudo docker compose -p bi ps -a || true
	sudo docker compose -p bi logs --no-color --timestamps || true
}

case "${1:-}" in
install)
	[ $# -ge 3 ] || die "usage: smoke.sh install <archive> <pubkey>..."
	shift
	install_release "$@"
	;;
update)
	[ $# -eq 2 ] || die "usage: smoke.sh update <archive>"
	sudo morzer --verbose update "$2"
	;;
task)
	# The one task, `seed`, connects a workspace to the emulators and loads two
	# years of a business: its listing is what a smoke run checks.
	sudo morzer task list
	;;
probe) probe ;;
backup-restore) backup_restore ;;
rotate-db-password) rotate_db_password ;;
rollback)
	[ $# -eq 3 ] || die "usage: smoke.sh rollback <published archive> <new archive>"
	rollback "$2" "$3"
	;;
free-disk) free_disk ;;
diagnose) diagnose ;;
*) die "usage: smoke.sh install|update|task|probe|backup-restore|rotate-db-password|rollback|diagnose|free-disk" ;;
esac
