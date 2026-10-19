# Releasing `escalated_phoenix`

The Hex package is `escalated_phoenix`; the OTP application inside it is
`:escalated`. Publishing is done by `.github/workflows/publish.yml`.

## How to release

1. Bump `@version` in `mix.exs` and add a `CHANGELOG.md` entry. Merge to `master`.
2. Create a GitHub release with tag `v<version>` (e.g. `v0.2.2`) on that commit.
3. Publishing the release runs the `Publish` workflow, which:
   1. checks out the tag;
   2. fails if `mix.exs` `@version` does not equal the tag (without the `v`);
   3. fails if any runtime dependency is a git/path dependency (Hex rejects
      them, and a package relying on one installs for nobody);
   4. runs `mix hex.build`;
   5. runs `mix hex.publish --yes`, unless that version is already on Hex.

If `HEX_API_KEY` is not set, the publish step logs
`skipping: HEX_API_KEY not configured` and the run stays green. Nothing is
published.

## Required secret

| Secret | Value |
|---|---|
| `HEX_API_KEY` | A Hex API key with write access, created with `mix hex.user key generate --key-name escalated-phoenix-ci --permission api:write` |

Add it under repo Settings, Secrets and variables, Actions, New repository
secret. The first publish registers the `escalated_phoenix` name on Hex to the
account that owns the key.

## Publishing a tag that already exists

To publish a release that was tagged before the secret was added (for example
`v0.2.1`):

1. Add `HEX_API_KEY` as above.
2. Actions, `Publish`, Run workflow, keep the branch at `master`, enter the tag
   (`v0.2.1`), Run.

Or from a terminal: `gh workflow run publish.yml -f tag=v0.2.1`.

The workflow file comes from `master`, but the package is built from the tag,
so tags created before this workflow existed can be published. Re-running for a
version already on Hex is a no-op.

## Translations

The central `escalated-locale` catalogues are vendored under
`priv/gettext/{locale}/LC_MESSAGES/escalated.po`, because `escalated_locale` is
not on Hex. `test/escalated/gettext_test.exs` asserts they load without that
package, and `scripts/verify_package.exs` asserts the built package ships them.
