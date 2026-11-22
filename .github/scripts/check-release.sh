#!/bin/sh
# Check the app version in lan_dhcp/config.yaml: a semantic version with a lan_dhcp/CHANGELOG.md
# entry, and equal to the release tag when one is given. Supervisor pulls the image tagged with
# that version, which only a matching v<version> tag publishes.
#   .github/scripts/check-release.sh [v<version>]
set -eu

cd "$(dirname "$0")/../.."
version=$(sed -n 's/^version:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' lan_dhcp/config.yaml)

if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "lan_dhcp/config.yaml: version must be MAJOR.MINOR.PATCH, not '$version'" >&2
    exit 1
fi
if ! grep -qx "## $version" lan_dhcp/CHANGELOG.md; then
    echo "lan_dhcp/CHANGELOG.md has no '## $version' entry" >&2
    exit 1
fi
if [ $# -gt 0 ] && [ "$1" != "v$version" ]; then
    echo "tag $1 does not match lan_dhcp/config.yaml version $version: tag v$version instead" >&2
    exit 1
fi
echo "version $version${1:+ matches $1}"
