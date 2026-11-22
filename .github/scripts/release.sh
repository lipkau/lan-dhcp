#!/bin/sh
# Prepare a release when the app (lan_dhcp/, apart from its changelog) changed since the last release
# tag: bump `version` in lan_dhcp/config.yaml, add the commit subjects to lan_dhcp/CHANGELOG.md, commit
# both and tag the commit v<version>. CI pushes the commit and the tag. Prints the new tag, or nothing
# when there is nothing to release. Needs the full history and the tags.
#   .github/scripts/release.sh
#
# The commit subjects decide the version: `type!:` is a major release, `feat:` a minor one, anything
# else a patch.
set -eu

cd "$(dirname "$0")/../.."
app=lan_dhcp

last=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*')
if git diff --quiet "$last" HEAD -- "$app" ":(exclude)$app/CHANGELOG.md"; then
    echo "nothing to release since $last" >&2
    exit 0
fi

subjects=$(git log --no-merges --format=%s "$last..HEAD" -- "$app")
if printf '%s\n' "$subjects" | grep -Eq '^[a-z]+(\([^)]*\))?!:'; then
    bump="major"
elif printf '%s\n' "$subjects" | grep -Eq '^feat(\([^)]*\))?:'; then
    bump="minor"
else
    bump="patch"
fi

current=${last#v}
major=${current%%.*}
rest=${current#*.}
minor=${rest%%.*}
patch=${rest#*.}
case $bump in
major) next="$((major + 1)).0.0" ;;
minor) next="$major.$((minor + 1)).0" ;;
patch) next="$major.$minor.$((patch + 1))" ;;
esac

# `feat(scope)!: add x (#4)` becomes `- Breaking: Add x (#4)`.
entries=$(printf '%s\n' "$subjects" | awk '
    {
        breaking = match($0, /^[a-z]+(\([^)]*\))?!: /)
        sub(/^[a-z]+(\([^)]*\))?!?: /, "")
        $0 = toupper(substr($0, 1, 1)) substr($0, 2)
        print "- " (breaking ? "Breaking: " : "") $0
    }')

sed -i "s/^version:.*/version: \"$next\"/" "$app/config.yaml"
entries=$entries awk -v version="$next" '
    !done && /^## / { print "## " version "\n\n" ENVIRON["entries"] "\n"; done = 1 }
    { print }
' "$app/CHANGELOG.md" >"$app/CHANGELOG.md.new"
mv "$app/CHANGELOG.md.new" "$app/CHANGELOG.md"

git add "$app/config.yaml" "$app/CHANGELOG.md"
git commit -q -m "chore(release): $next"
git tag -a "v$next" -m "lan-dhcp $next"
echo "v$next"
