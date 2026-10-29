# The bundle's development tasks. `just check` runs every gate CI runs before a
# bundle is built; `just rehearse` installs one in a throwaway rig.
#
# `pin`, `version` and `rehearse` run bundle-ci's scripts from a checkout of
# it: BUNDLE_CI, or ../bundle-ci beside this repository.

set shell := ["bash", "-euo", "pipefail", "-c"]

bundle_ci := env_var_or_default("BUNDLE_CI", "../bundle-ci")

# List the tasks
default:
    @just --list

# Every gate below, cheapest first
check: lint shellcheck compose verify edge-smoke

# The bundle builds and verifies as morzer would release it (needs morzer)
verify:
    bash scripts/gates/bundle-verify.sh

# The Compose file is valid with only what morzer gives it (needs yq, docker)
compose:
    bash scripts/gates/compose-config.sh

# The edge's routing and body limit, against stand-ins for the components (needs docker)
edge-smoke:
    bash scripts/gates/edge-smoke.sh

# Every shell script and hook, at warning level
shellcheck:
    git ls-files -z --cached --others --exclude-standard -- '*.sh' 'bundle/hooks/*' | xargs -0 -r shellcheck -S warning

# The workflows (actionlint, zizmor)
lint:
    actionlint
    zizmor --offline .github/workflows

# Pin the components' `main` digests and the schema into the manifest (`--release X.Y.Z`: promote the committed pins)
pin *args:
    bash {{ bundle_ci }}/scripts/pin.sh {{ args }}

# The version the next dev bundle gets
version:
    bash {{ bundle_ci }}/scripts/version.sh

# Install a bundle in a throwaway rig, as a machine would (`--from <oci ref>`, `--keep`; REHEARSE_PUBKEY)
rehearse *args:
    REHEARSE_OPERATOR_SECRETS=admin_password bash {{ bundle_ci }}/scripts/rehearse.sh {{ args }}
