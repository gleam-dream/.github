# Publishes the Gleam package a release tag names. Run by the shared
# workflow, from the root of the caller's checkout.
#
# Reads TAG, COMMIT and DEFAULT_BRANCH, and HEXPM_API_KEY for the upload.
# With CHECK_ONLY=1 it stops before the upload.
#
# The tag is `v<version>` for the package at the repository root, or
# `<package>-v<version>` for a package elsewhere in the repository.

fail() {
  echo "::error::$*"
  exit 1
}

summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
root="$(git rev-parse --show-toplevel)"
cd "$root"

if [[ "$TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)$ ]]; then
  version="${BASH_REMATCH[1]}"
  manifest=gleam.toml
elif [[ "$TAG" =~ ^([a-z][a-z0-9_]*)-v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)$ ]]; then
  wanted="${BASH_REMATCH[1]}"
  version="${BASH_REMATCH[2]}"
  manifest=""
  while IFS= read -r candidate; do
    if grep -qE "^name *= *\"$wanted\"" "$candidate"; then
      [[ -z "$manifest" ]] || fail "Two manifests are named $wanted: $manifest and $candidate"
      manifest="$candidate"
    fi
  done < <(git ls-files 'gleam.toml' '*/gleam.toml')
  [[ -n "$manifest" ]] || fail "No gleam.toml in this repository is named $wanted"
else
  fail "Tag $TAG is neither v<version> nor <package>-v<version>"
fi

name="$(sed -nE 's/^name *= *"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
declared="$(sed -nE 's/^version *= *"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
[[ "$declared" == "$version" ]] ||
  fail "Tag $TAG names version $version, but $manifest declares $declared"

git merge-base --is-ancestor "$COMMIT" "origin/$DEFAULT_BRANCH" ||
  fail "Commit $COMMIT is not on $DEFAULT_BRANCH. Tag the merge commit of the release pull request."

release="https://hex.pm/api/packages/$name/releases/$version"
status="$(curl -sS -o /dev/null -w '%{http_code}' "$release")"
case "$status" in
404) ;;
200) fail "Hex already lists $name $version" ;;
*) fail "Hex answered $status for $name $version" ;;
esac

echo "Checked: $TAG is $name $version at $(dirname "$manifest"), on $DEFAULT_BRANCH, new to Hex."
if [[ "${CHECK_ONLY:-}" == 1 ]]; then
  exit 0
fi

# Gleam comes from the caller's own flake. `--yes` leaves one prompt for
# versions below 1.0.0, and Gleam exits 0 when that prompt is declined, so
# the output is checked.
log="$(mktemp)"
(
  cd "$(dirname "$manifest")"
  printf 'I am not using semantic versioning\n' |
    nix develop "$root" --command gleam publish --yes 2>&1 | tee "$log"
)
if grep -q 'Not publishing' "$log"; then
  fail "Gleam declined to publish"
fi

# Gleam reports success for a staged upload too, so ask Hex.
for _ in 1 2 3 4 5 6; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' "$release")"
  [[ "$status" == 200 ]] && break
  sleep 10
done
if [[ "$status" == 200 ]]; then
  echo "$name $version is public: https://hex.pm/packages/$name/$version" >>"$summary"
else
  {
    echo "$name $version was uploaded and Hex does not list it yet (status $status)."
    echo "A maintainer approves it at https://hex.pm/dashboard with a second factor."
    echo "Hex drops a staged release that is not approved within 7 days."
  } >>"$summary"
  echo "::notice::$name $version waits for approval on hex.pm"
fi
