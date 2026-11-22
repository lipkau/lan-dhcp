#!/bin/sh
# Prepare a release when the app (lan_dhcp/, apart from its changelog) changed since the last release
# tag: bump `version` in lan_dhcp/config.yaml, add the change subjects to lan_dhcp/CHANGELOG.md, check
# both, commit them and tag the commit v<version>. CI pushes the commit and the tag. Prints the new
# tag, or nothing when there is nothing to release. Needs the full history, the tags and `npm ci`.
#   .github/scripts/release.sh
#
# Each commit on main's first-parent line that changed the app contributes its subject: a squash or
# direct commit its own; a merge commit the subjects of the merged commits that changed the app, or,
# when the merge itself made the change, the pull request title GitHub puts in its body. The subjects
# decide the version: `type!:` is a major release, `feat:` a minor one, anything else a patch.
set -eu

cd "$(dirname "$0")/../.."
app=lan_dhcp

# Only stable tags on main's own line are a baseline: not v1.2.0-rc.1, not a tag on a merged branch.
last=$(git describe --tags --abbrev=0 --first-parent --match 'v[0-9]*' --exclude 'v*[!0-9.]*' 2>/dev/null || true)
if ! printf '%s\n' "$last" | grep -Eqx 'v[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "no v<major>.<minor>.<patch> tag on main's first-parent history to release from" >&2
    exit 1
fi
if git diff --quiet "$last" HEAD -- "$app" ":(exclude)$app/CHANGELOG.md"; then
    echo "nothing to release since $last" >&2
    exit 0
fi

subjects=
for commit in $(git rev-list --reverse --first-parent "$last..HEAD" -- "$app" ":(exclude)$app/CHANGELOG.md"); do
    if git rev-parse -q --verify "$commit^2" >/dev/null; then
        found=$(git log --reverse --no-merges --format=%s "$commit^1..$commit" -- "$app" \
            ":(exclude)$app/CHANGELOG.md")
        if [ -z "$found" ]; then
            found=$(git log -1 --format=%b "$commit" | sed -n '/[^[:space:]]/{p;q;}')
            [ -n "$found" ] || found=$(git log -1 --format=%s "$commit")
        fi
    else
        found=$(git log -1 --format=%s "$commit")
    fi
    subjects=$(printf '%s\n%s' "$subjects" "$found")
done
subjects=$(printf '%s\n' "$subjects" | sed '/^[[:space:]]*$/d')

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

# `feat(scope)!:  add x (#4)` becomes `- Breaking: Add x (#4)`.
entries=$(printf '%s\n' "$subjects" | awk '
    {
        gsub(/[[:space:]]+/, " ")
        breaking = match($0, /^[a-z]+(\([^)]*\))?!: /)
        sub(/^[a-z]+(\([^)]*\))?!?: /, "")
        sub(/^ /, "")
        sub(/ $/, "")
        $0 = toupper(substr($0, 1, 1)) substr($0, 2)
        print "- " (breaking ? "Breaking: " : "") $0
    }')

sed -i "s/^version:.*/version: \"$next\"/" "$app/config.yaml"
entries=$entries awk -v version="$next" '
    !done && /^## / { print "## " version "\n\n" ENVIRON["entries"] "\n"; done = 1 }
    { print }
' "$app/CHANGELOG.md" >"$app/CHANGELOG.md.new"
mv "$app/CHANGELOG.md.new" "$app/CHANGELOG.md"

# The tag's CI run runs the same checks; a release that fails them would never publish its image.
npx biome format --write "$app/CHANGELOG.md" >&2
npx biome ci "$app/CHANGELOG.md" >&2
.github/scripts/check-release.sh "v$next" >&2

git add "$app/config.yaml" "$app/CHANGELOG.md"
git commit -q -m "chore(release): $next"
git tag -a "v$next" -m "lan-dhcp $next"
echo "v$next"
