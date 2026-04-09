# Release scripts

This directory contains the release/distribution tooling for ClaudeSwitcher.

## One-time setup

### 1. Apple Developer account

You need an active Apple Developer Program membership and a **Developer ID Application** certificate installed in your login keychain. Verify with:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see something like:
```
Developer ID Application: CANER TURE (39Z244SGXG)
```

### 2. App-specific password for notarization

Notarization requires credentials for Apple's notary service. The recommended approach is an **app-specific password**:

1. Go to https://appleid.apple.com → Sign-In and Security → App-Specific Passwords
2. Generate a new password (label it something like "ClaudeSwitcher Notary")
3. Copy the password — it will look like `abcd-efgh-ijkl-mnop`

### 3. Store the credentials in a notarytool keychain profile

Run this once. You'll be prompted for the app-specific password you just created:

```sh
xcrun notarytool store-credentials ClaudeSwitcherNotary \
    --apple-id "your-apple-id@example.com" \
    --team-id "39Z244SGXG"
```

This saves the credentials to your login keychain under the profile name `ClaudeSwitcherNotary`. The release script looks for this profile by default.

Verify it works:

```sh
xcrun notarytool history --keychain-profile ClaudeSwitcherNotary
```

## Cutting a release

With setup done, producing a signed + notarized build is a single command:

```sh
./scripts/release.sh
```

The script will:

1. Build a universal release binary (arm64 + x86_64) via Swift Package Manager
2. Assemble a `.app` bundle from the binary + `Info.plist`
3. Code sign with hardened runtime using your Developer ID
4. Submit to Apple's notary service and wait for the result
5. Staple the notarization ticket to the `.app`
6. Produce a final `release/ClaudeSwitcher.zip` ready for distribution

The output `release/ClaudeSwitcher.zip` can be uploaded to GitHub Releases, your website, or sent directly to users. When they unzip and open it, macOS will recognize it as a notarized app and launch it without any warnings.

## Overrides

You can override any of the script's defaults via environment variables:

```sh
SIGNING_IDENTITY="Developer ID Application: Some Other Name (TEAMID)" \
NOTARY_PROFILE="SomeOtherProfile" \
BUNDLE_ID="com.example.ClaudeSwitcher" \
    ./scripts/release.sh
```

## App icon

The app icon workflow uses a single source-of-truth PNG and regenerates the `.icns` on every release:

1. Design your icon at `1024x1024` (see spec below)
2. Export from Figma / Sketch / Illustrator as a PNG
3. Save it to `ClaudeSwitcher/Resources/AppIcon.png` (this path is tracked in git)
4. Run `./scripts/make-icon.sh` to generate `AppIcon.icns` locally (optional — `release.sh` does this automatically on every build)
5. Run `./scripts/release.sh` — it regenerates the `.icns` from the master PNG and bundles it into the app

The generated `AppIcon.icns` is in `.gitignore` because it's a build artifact derived from the source PNG. Only the master PNG needs to be committed.

### Quick test without a full release

If you just want to verify that your icon looks right before doing a full signed/notarized build:

```sh
./scripts/make-icon.sh
open ClaudeSwitcher/Resources/AppIcon.icns  # Preview.app shows all resolutions
```

### Design spec (Figma / Sketch)

Follow Apple's [Human Interface Guidelines for macOS app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) when designing:

- **Canvas**: `1024x1024` pixels
- **Safe area**: keep the visible content inside an `824x824` box centered in the canvas (100px padding on each side)
- **Shape**: modern macOS icons use a rounded-square ("squircle") silhouette — apply a corner radius of roughly `225px` (approximately 22% of the canvas width) to get the native look
- **Background**: opaque; no transparent background for the body of the icon (transparency in the corners is fine — that's how the squircle shape works)
- **Format**: PNG, 32-bit with alpha channel
- **Export**: Figma → select frame → Export → PNG, `1x`, download

### Verifying the result

After running `make-icon.sh` and then `release.sh`, open `release/ClaudeSwitcher.app` in Finder. You should see the new icon in:

- Finder (large and small views)
- The Dock when the app runs
- Launchpad
- `Get Info` panel (`⌘I`)

If the icon still looks like a generic document, try clearing the macOS icon cache:

```sh
sudo rm -rf /Library/Caches/com.apple.iconservices.store
killall Finder Dock
```

## Distributing to users

Once `release/ClaudeSwitcher.zip` is ready:

1. **GitHub Releases** (recommended): `gh release create v1.0.0 release/ClaudeSwitcher.zip --notes "..."`
2. **Direct download**: host the zip on any web server
3. **Homebrew cask**: submit a cask to homebrew-cask for `brew install --cask claudeswitcher`

Users download the zip, unzip it, and drag `ClaudeSwitcher.app` into `/Applications`. Because it's notarized and stapled, it launches with no Gatekeeper warnings, even offline.
