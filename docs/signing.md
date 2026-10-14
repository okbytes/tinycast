# Signing

Tinycast is signed with team `P4RDBS9676`, the paid Apple Developer account, and nothing else:

- **Debug builds** — Xcode's ⌘R and `scripts/install-dev.sh` — sign with **Apple Development**,
  which `project.yml` names as the default identity.
- **Release builds** sign with **Developer ID Application** and are notarized by
  `scripts/release.sh`, so they open on any Mac without a Gatekeeper warning.

A team is not optional. The keyboard helper's XPC check requires both ends to carry the same team
ID ([key-remap.md](features/key-remap.md)), and macOS keys the Accessibility and Input Monitoring
grants to the designated requirement, which a team identity keeps stable across rebuilds and
releases. A build signed some other way loses Hyper and asks for both grants again.

## Setup (once per Mac)

- **Every Mac that builds:** sign in to Xcode with the Apple ID (**Settings → Accounts**). Xcode
  makes the Apple Development certificate; `security find-identity -p codesigning -v` lists it.
- **The Mac that cuts releases**, additionally:
  1. In Xcode, **Settings → Accounts → Manage Certificates → + → Developer ID Application**.
  2. Store notarization credentials under the profile name `release.sh` expects, using an
     app-specific password from appleid.apple.com:

     ```sh
     xcrun notarytool store-credentials tinycast --apple-id <apple-id> --team-id P4RDBS9676
     ```

- **Macs that only install** need neither: `scripts/install.sh` needs only `gh`, logged in.

## Releasing

```sh
./scripts/release.sh 0.12.0   # build, verify, notarize, staple, tag v0.12.0, publish
./scripts/install.sh          # on any Mac: the latest release into ~/Applications
```

`release.sh` refuses a dirty tree or a version already tagged, signs Release with Developer ID,
runs `verify-signature.sh`, notarizes the zipped app with the `tinycast` profile and staples the
ticket, so the published zip opens offline. It then pushes the tag and attaches the zip to a GitHub
release on this private repo, with the commits since the last release as notes. `install.sh` checks
the download passes Gatekeeper before it replaces the installed copy, so a build that skipped
notarization never lands.

## Hardened runtime

**Release only**, on every target: `ENABLE_HARDENED_RUNTIME: YES`, which notarization requires.
Debug builds go without it; nothing local needs it. The flag is not part of the designated
requirement, so turning it on costs no Accessibility grant. Each entitlement in
`Tinycast/Tinycast.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info and the System Events–driven system actions die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |
| `com.apple.security.personal-information.calendars` | `requestFullAccessToEvents()` returns `false` in milliseconds with no dialog, and Tinycast never appears under System Settings › Calendars |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources Tinycast does not use. That grants nothing — only
`Tinycast.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

`./scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on every binary in `Contents/Helpers`, an intact nested seal, no `get-task-allow`, and an
entitlement for every usage string `Info.plist` declares. `release.sh` runs it before notarizing:
a nested binary missing the runtime flag is the most common notarization rejection, and a usage string
missing its entitlement ships a permission that can never be granted.

## Moving from an older build

The first team-signed build replaces one signed without a team, so macOS treats it as a new app for
TCC: grant Accessibility and Input Monitoring once more. Every release after that keeps them.
