#!/usr/bin/env bash
# The edge routes and limits as it must, against stand-ins for the components
# (tests/compose/stub.yaml): the API to the backend, the rest to the frontend, a
# 10 MiB body through and one past 11 MiB refused.
set -euo pipefail

compose=bundle/compose/compose.yaml
stub=tests/compose/stub.yaml
# shellcheck source=scripts/gates/env.sh
. scripts/gates/env.sh
export COMPOSE_PROJECT_NAME=bi-edge-smoke
tmp="${PWD}/.tmp/bi"
rm -rf "${tmp}"
mkdir -p "${BI_SECRETS_DIR}" "${BI_DATA_DIR}"

while IFS=$'\t' read -r name kind; do
	case "${kind}" in
	base64) head -c 32 /dev/urandom | base64 -w0 >"${BI_SECRETS_DIR}/${name}" ;;
	*) head -c 24 /dev/urandom | base64 -w0 | tr -d '+/=' >"${BI_SECRETS_DIR}/${name}" ;;
	esac
	chmod 0444 "${BI_SECRETS_DIR}/${name}"
done < <(yq -r '.secrets // [] | .[] | [(.file // .name), (.generator.kind // "password")] | @tsv' bundle/secrets.schema.yaml)

dc() { docker compose -f "${compose}" -f "${stub}" "$@"; }
cleanup() {
	status=$?
	if [ "${status}" -ne 0 ]; then
		dc ps -a || true
		dc logs --no-color --tail 80 || true
	fi
	dc down -v --remove-orphans >/dev/null 2>&1 || true
	rm -rf "${tmp}"
	exit "${status}"
}
trap cleanup EXIT

dc up -d --wait --wait-timeout 300
health="http://127.0.0.1:${BI_PARAM_HEALTH_PORT:?bundle/manifest.yaml declares no health_port}"

expect() { # <path> <body>
	local got
	got="$(curl -fsS --max-time 10 "${health}$1")"
	[ "${got}" = "$2" ] || { echo "edge-smoke: $1 answered '${got}', not '$2'" >&2; exit 1; }
	echo "edge-smoke: $1 -> $2"
}

curl -fsS --max-time 10 -o /dev/null "${health}/__platform_healthz"
echo "edge-smoke: /__platform_healthz answers"
for path in /health /v1/openapi.json /v1/metrics/status; do
	expect "${path}" backend
done
for path in / /dashboards /assets/index.js; do
	expect "${path}" frontend
done

post() { # <bytes> -> HTTP status
	head -c "$1" /dev/zero >"${tmp}/body"
	curl -sS --max-time 120 -o /dev/null -w '%{http_code}' -H 'Expect:' \
		--data-binary "@${tmp}/body" -H 'Content-Type: application/octet-stream' \
		"${health}/v1/probe"
}
code="$(post 10485760)"
[ "${code}" = 200 ] || { echo "edge-smoke: a 10 MiB body got ${code}, not 200" >&2; exit 1; }
echo "edge-smoke: 10 MiB -> 200"
code="$(post 11534337)"
[ "${code}" = 413 ] || { echo "edge-smoke: a body past 11 MiB got ${code}, not 413" >&2; exit 1; }
echo "edge-smoke: past 11 MiB -> 413"
