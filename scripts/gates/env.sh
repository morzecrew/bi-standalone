# shellcheck shell=bash
# The variables morzer hands Compose, from the manifest: every image as
# BI_IMAGE_<KEY>, every parameter's default as BI_PARAM_<NAME>, and scratch
# directories for the secrets and data. Sourced by the gates.
manifest=bundle/manifest.yaml
while IFS=$'\t' read -r name value; do
	export "BI_IMAGE_${name}=${value}"
done < <(yq -r '.images // {} | to_entries[] | [(.key | upcase | sub("[-.]"; "_")), .value] | @tsv' "${manifest}")
while IFS=$'\t' read -r name value; do
	export "BI_PARAM_${name}=${value}"
done < <(yq -r '.parameters // {} | to_entries[] | [(.key | upcase | sub("[-.]"; "_")), (.value.default // "")] | @tsv' "${manifest}")
export BI_SECRETS_DIR="${PWD}/.tmp/bi/secrets"
export BI_RELEASE_DIR="${PWD}/bundle"
export BI_DATA_DIR="${PWD}/.tmp/bi/data"
export BI_VERSION=0.0.1-gate.1
