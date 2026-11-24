#!/bin/sh
# Test .github/scripts/release.sh in throwaway repositories: which changes release, the version each
# kind of subject gives, the changelog lines, and the release baseline. Needs git and `npm ci`.
#   tests/release.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
n=0

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

# A repository at release v1.0.0 with the release scripts and the Biome setup.
repo() {
    n=$((n + 1))
    dir="$work/repo$n"
    mkdir -p "$dir/lan_dhcp" "$dir/.github/scripts"
    cp "$root/.github/scripts/release.sh" "$root/.github/scripts/check-release.sh" "$dir/.github/scripts/"
    cp "$root/biome.json" "$root/.editorconfig" "$root/.gitignore" "$dir/"
    ln -s "$root/node_modules" "$dir/node_modules"
    printf 'name: LAN DHCP\nversion: "1.0.0"\n' >"$dir/lan_dhcp/config.yaml"
    printf '# Changelog\n\n## 1.0.0\n\n- First release.\n' >"$dir/lan_dhcp/CHANGELOG.md"
    echo FROM >"$dir/lan_dhcp/Dockerfile"
    echo docs >"$dir/README.md"
    cd "$dir"
    git init -q -b main
    git config user.name test
    git config user.email test@example.invalid
    git config commit.gpgSign false
    git config tag.gpgSign false
    git config rerere.enabled false
    git add -A
    git commit -q -m "feat: first release"
    git tag -a v1.0.0 -m v1.0.0
}

change() { # <file> <subject>
    echo "$2" >>"$1"
    git add "$1"
    git commit -q -m "$2"
}

# Runs release.sh and checks the tag it prints, its exit status, and the changelog entry it wrote.
expect() { # <case> <tag or nothing> [changelog line ...]
    name=$1 want=$2
    shift 2
    status=0
    got=$(.github/scripts/release.sh 2>"$work/stderr") || status=$?
    if [ "$status" != 0 ]; then
        fail "$name: release.sh exited $status: $(tail -n 3 "$work/stderr")"
        return
    fi
    [ "$got" = "$want" ] || fail "$name: tag '$got', want '$want'"
    [ -n "$want" ] || return 0
    [ "$(git describe --tags --exact-match)" = "$want" ] || fail "$name: HEAD isn't tagged $want"
    grep -qx "version: \"${want#v}\"" lan_dhcp/config.yaml || fail "$name: config.yaml isn't ${want#v}"
    entry=$(awk '/^## / { n++ } n == 1 && /^- /' lan_dhcp/CHANGELOG.md)
    lines=$(printf '%s\n' "$@")
    [ "$entry" = "$lines" ] || fail "$name: changelog entry
$entry
want
$lines"
}

repo
change README.md "docs: outside the app"
expect "a change outside lan_dhcp/" ""
change lan_dhcp/CHANGELOG.md "docs: changelog only"
expect "a changelog-only change" ""
change lan_dhcp/Dockerfile "fix(deps): update alpine (#5)"
expect "fix" v1.0.1 "- Update alpine (#5)"
expect "a second run" ""
change lan_dhcp/Dockerfile "feat: add a page"
change lan_dhcp/Dockerfile "Tidy the  entrypoint"
expect "feat and a plain subject" v1.1.0 "- Add a page" "- Tidy the entrypoint"
# The backticks and backslashes are the point: they must reach the changelog unchanged.
# shellcheck disable=SC2016
change lan_dhcp/Dockerfile 'fix:   keep `seed`   and \back\slashes  '
# shellcheck disable=SC2016
expect "spaces, code and backslashes" v1.1.1 '- Keep `seed` and \back\slashes'
change lan_dhcp/Dockerfile "refactor(config)!: rename the option"
expect "breaking change" v2.0.0 "- Breaking: Rename the option"

repo
change lan_dhcp/Dockerfile "fix: before a pre-release"
git tag -a v1.0.1-rc.1 -m rc
change lan_dhcp/Dockerfile "fix: after a pre-release"
expect "a pre-release tag isn't a baseline" v1.0.1 "- Before a pre-release" "- After a pre-release"

repo
git checkout -q -b side
change lan_dhcp/Dockerfile "feat: on a branch"
change README.md "docs: on a branch"
git tag -a v9.0.0 -m side
git checkout -q main
# main moves on, so the merged branch's tag is the nearest one to the merge.
change notes.txt "docs: on main"
git merge -q --no-ff side -m "Merge pull request #7 from owner/side" -m "Add things"
expect "a merge lists its app commits, not a merged branch's tag" v1.1.0 "- On a branch"

repo
git checkout -q -b side
change README.md "docs: only the readme"
git checkout -q main
git merge -q --no-ff --no-commit side >/dev/null 2>&1
echo resolved >>lan_dhcp/Dockerfile
git add lan_dhcp/Dockerfile
git commit -q -m "Merge pull request #8 from owner/side" -m "feat!: change the app in the merge"
expect "a merge that changes the app itself" v2.0.0 "- Breaking: Change the app in the merge"

repo
git tag -d v1.0.0 >/dev/null
change lan_dhcp/Dockerfile "fix: no baseline"
if .github/scripts/release.sh >/dev/null 2>&1; then
    fail "no release tag: release.sh succeeded"
fi

if [ "$failures" != 0 ]; then
    echo "$failures failed" >&2
    exit 1
fi
echo "release.sh: all cases pass"
