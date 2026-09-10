# Release checklist

One-time setup (the account holder does this):

1. In Xcode ▸ Settings ▸ Accounts, sign in with the Apple ID for team
   `65KL68N9K8` and click **Manage Certificates ▸ + ▸ Developer ID Application**.
2. Create an app-specific password at https://appleid.apple.com and store it:
   ```bash
   xcrun notarytool store-credentials LeadsheetStudio --apple-id <you@example.com> --team-id 65KL68N9K8
   ```
3. `gh auth status` (gh lives in `~/bin/gh/bin`) must show the `srm-personal` account.

Per release:

1. Update `CHANGELOG.md` with a `## x.y.z` section.
2. `cd ImprovisorApp && VERSION=x.y.z ./scripts/release.sh`
   — runs the tests, archives, exports with Developer ID, builds and notarizes
   the DMG, commits the version bump and tags `vx.y.z`. Nothing is published yet.
3. Open `build/Leadsheet-Studio-x.y.z.dmg`, drag the app to Applications, launch
   it and try a tune (Gatekeeper should not complain; `spctl -a -vv` in the
   notarize step printed `accepted`).
4. `VERSION=x.y.z PUBLISH=1 ./scripts/release.sh` — pushes the branch and tag
   and creates the GitHub Release with the DMG and its SHA-256.
5. Optionally update `Casks/leadsheet-studio.rb` with the new version and hash.

Individual steps: `scripts/archive.sh`, `scripts/export.sh`,
`scripts/make_dmg.sh`, `scripts/notarize.sh`.
