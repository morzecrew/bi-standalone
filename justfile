# The bundle's development tasks. `just check` runs every gate CI runs before a
# bundle is built; `just rehearse` installs one in a throwaway rig.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List the tasks
default:
    @just --list

# Every gate below, cheapest first
check: lint shellcheck test compose verify edge-smoke

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

# The pin and version scripts' tests
test:
    bash tests/pin/run.sh
    bash tests/version/run.sh

# The workflows (actionlint, zizmor)
lint:
    actionlint
    zizmor --offline .github/workflows

# Pin the components' `main` digests and the schema into the manifest (`--release`: components.yaml's versions)
pin *args:
    bash scripts/pin.sh {{ args }}

# The version the next dev bundle gets
version:
    bash scripts/version.sh

# Install a bundle in a throwaway rig, as a machine would (`--from <oci ref>`, `--keep`)
rehearse *args:
    bash scripts/rehearse.sh {{ args }}
