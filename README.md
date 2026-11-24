# Shared workflows

Workflows that every `gleam-dream` package repository calls.

## Publishing a package to Hex

[`hex-publish.yml`](.github/workflows/hex-publish.yml) publishes one package
when its release tag is pushed. A person or an agent can do every step except
the last one: a release becomes public only when a Hex maintainer approves it
on hex.pm with a second factor.

### Cutting a release

1. Run `scripts/release <version>` on a clean, current `main`. It opens the
   version-bump pull request and stops there.
2. Review and merge the pull request.
3. Pull `main`, confirm its head is the merge commit, and tag it:
   `v<version>` for the package at the repository root, or
   `<package>-v<version>` for a package elsewhere in the repository.
4. Push the tag. The `Release` workflow uploads the package and its docs.
5. A Hex maintainer opens <https://hex.pm/dashboard>, reads the staged
   release, and approves it with a second factor. Hex drops a staged release
   that is not approved within 7 days.
6. Confirm the version is public:
   `curl -fsS https://hex.pm/api/packages/<package>/releases/<version>`.

The workflow refuses a tag whose commit is not on the default branch, whose
version differs from the package's `gleam.toml`, or whose version Hex already
lists.

### Undoing a release

- Before approval: reject the staged release on hex.pm, then delete the tag.
- Within 60 minutes of approval: `gleam hex revert --package <package> --version <version>`.
- After that: `gleam hex retire`. A public version cannot be removed.

### Setting up a package

A Hex owner of the package does this once.

1. On hex.pm, open the package's settings and turn on staged publishing.
2. On <https://hex.pm/dashboard/keys>, create a key with the permissions
   `publish:<package>` and `api:read`. A repository that publishes several
   packages gets one key with a `publish:` permission for each.
3. Store it in the repository:
   `gh secret set HEXPM_API_KEY --repo <owner>/<repository>`.
4. Add the caller workflow as `.github/workflows/release.yml`. The `tags`
   filter lists the packages this repository may publish.

```yaml
name: Release
on:
  push:
    tags:
      - "v[0-9]*"
permissions:
  contents: read
jobs:
  hex:
    uses: gleam-dream/.github/.github/workflows/hex-publish.yml@<commit>
    secrets:
      HEXPM_API_KEY: ${{ secrets.HEXPM_API_KEY }}
```

The first release of a new package needs no extra step: Hex turns staged
publishing on for a package whose first release comes from a key.
