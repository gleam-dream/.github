# Opens the version-bump pull request for a release of a Gleam package.
# It never tags and never publishes.
#
#   release <version>             the package at the repository root
#   release <package> <version>   a package elsewhere in the repository

die() {
  echo "release: $*" >&2
  exit 1
}

case $# in
1)
  wanted=""
  version="$1"
  ;;
2)
  wanted="$1"
  version="$2"
  ;;
*) die "usage: release [<package>] <major.minor.patch>" ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: release [<package>] <major.minor.patch>"

cd "$(git rev-parse --show-toplevel)"

manifest=gleam.toml
if [[ -n "$wanted" ]]; then
  manifest=""
  while IFS= read -r candidate; do
    if grep -qE "^name *= *\"$wanted\"" "$candidate"; then
      [[ -z "$manifest" ]] || die "two manifests are named $wanted: $manifest and $candidate"
      manifest="$candidate"
    fi
  done < <(git ls-files 'gleam.toml' '*/gleam.toml')
  [[ -n "$manifest" ]] || die "no gleam.toml in this repository is named $wanted"
fi
[[ -f "$manifest" ]] || die "no $manifest here"

package="$(sed -nE 's/^name *= *"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
current="$(sed -nE 's/^version *= *"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
if [[ "$manifest" == gleam.toml ]]; then
  prefix="v"
else
  prefix="$package-v"
fi

default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
default="${default:-main}"
[[ "$(git branch --show-current)" == "$default" ]] || die "run it on $default"
[[ -z "$(git status --porcelain)" ]] || die "the working tree has changes"
git fetch --quiet origin "$default" --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$default")" ]] || die "$default differs from origin/$default"
[[ "$version" != "$current" ]] || die "$manifest already declares $version"
[[ -z "$(git tag --list "$prefix$version")" ]] || die "tag $prefix$version exists"

branch="release/$prefix$version"
git switch --quiet --create "$branch"

# The package version, and its copy in every manifest that locks the package
# by path.
RELEASE_VERSION="$version" perl -pi -e \
  '$done ||= s/^version *= *"[^"]+"/version = "$ENV{RELEASE_VERSION}"/' "$manifest"
changed=("$manifest")
while IFS= read -r lock; do
  if grep -qE "name = \"$package\", version = \"$current\".*source = \"local\"" "$lock"; then
    RELEASE_PACKAGE="$package" RELEASE_VERSION="$version" perl -pi -e \
      's/(name = "\Q$ENV{RELEASE_PACKAGE}\E", version = ")[^"]+(".*source = "local")/$1$ENV{RELEASE_VERSION}$2/' "$lock"
    changed+=("$lock")
  fi
done < <(git ls-files 'manifest.toml' '*/manifest.toml')

title="build: release $package $version"
git add -- "${changed[@]}"
git commit --quiet --message "$title"
git push --quiet --set-upstream origin "$branch"

{
  echo "Sets the $package version to $version in $manifest and in the manifests that depend on it by path."
  echo
  if [[ -n "$(git tag --list "$prefix$current")" ]]; then
    echo "Changes since $prefix$current:"
    echo
    git log --format='- %s' "$prefix$current..origin/$default" -- "$(dirname "$manifest")"
    echo
  fi
  echo "Consumers that must change, and from which version: (fill in, or write none)"
} | gh pr create --title "$title" --body-file - --base "$default" --head "$branch"

echo "release: after the merge, tag the merge commit $prefix$version and push the tag."
