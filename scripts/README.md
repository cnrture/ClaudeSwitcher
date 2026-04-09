# Release scripts

This directory contains the release/distribution tooling for ClaudeSwitcher.

## One-time setup

### 0. Sparkle auto-update tools (critical)

Starting with v1.0.1, ClaudeSwitcher embeds the [Sparkle](https://sparkle-project.org) framework so users get in-app update notifications. The release pipeline needs Sparkle's CLI tools and a one-time ed25519 key pair.

**Step 1 — Download Sparkle CLI tools** (one-time per machine):

```sh
./scripts/setup-sparkle-tools.sh
```

This downloads the pinned Sparkle release tarball (2.9.1 by default) and installs `generate_keys`, `sign_update`, and `generate_appcast` into `~/.sparkle-tools/bin/`. The directory is outside the repo so it survives `swift package clean`.

**Step 2 — Generate the ed25519 key pair** (one-time, globally):

```sh
~/.sparkle-tools/bin/generate_keys
```

The command stores the **private** key in your macOS login Keychain and prints the **public** key to stdout. Copy the public key string and paste it into `ClaudeSwitcher/Info.plist` as the value of `SUPublicEDKey` (replacing the `REPLACE_WITH_GENERATED_PUBLIC_KEY` placeholder).

**Step 3 — Back up the private key (mandatory)**:

> **⚠️ CRITICAL — READ THIS CAREFULLY**
>
> If the ed25519 private key is ever lost (disk wipe, corrupted keychain, machine loss without a backup), **every current and future ClaudeSwitcher user is permanently locked on the version they already have**. Sparkle will reject any future release that isn't signed with this exact key. There is **no recovery path**. Apple can't help, GitHub can't help, Sparkle can't help.
>
> Back this key up **immediately** after generating it, in **at least two places**.

Run the backup helper:

```sh
./scripts/backup-sparkle-key.sh
```

The script:

1. Exports the private key to a temporary file
2. Prints its contents to stdout inside clear BEGIN/END markers
3. Securely deletes the temp file

**Copy the output** into your password manager (1Password, Bitwarden, Apple Passwords) as a Secure Note with:

- **Title**: ClaudeSwitcher Sparkle ed25519 private key
- **Tags**: `sparkle`, `ed25519`, `claudeswitcher`, `critical`
- **Notes**: "If this key is lost, no future ClaudeSwitcher update can be signed for existing users. Keep this forever."

Optionally, also stash the same output on an encrypted USB stick for offline disaster recovery.

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
2. Assemble a `.app` bundle from the binary + `Info.plist` + `AppIcon.icns`
3. Bundle `Sparkle.framework` into `Contents/Frameworks/`
4. Sign the Sparkle XPC services inside-out, then the framework, then the `.app`, all with hardened runtime
5. Submit to Apple's notary service and wait for the result
6. Staple the notarization ticket to the `.app`
7. Produce a final `release/ClaudeSwitcher.zip`
8. Run `sign_update` to generate the ed25519 signature for the zip
9. Append a new entry to `docs/appcast.xml` using the version from `Info.plist`

After the script completes, you manually commit `docs/appcast.xml`, push it, and publish the GitHub release. See the **Cutting v1.0.x** section below.

The output `release/ClaudeSwitcher.zip` can be uploaded to GitHub Releases, your website, or sent directly to users. When they unzip and open it, macOS will recognize it as a notarized app and launch it without any warnings — and thanks to Sparkle, they'll receive in-app notifications when you ship v1.0.2, v1.1.0, etc.

## Cutting v1.0.x (full release checklist)

Before starting, make sure the Sparkle one-time setup (section 0) is complete, and the GitHub Pages hosting for `claudeswitcher.candroid.dev` is live (see below).

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `ClaudeSwitcher/Info.plist`
2. Write release notes at the repo root: `RELEASE_NOTES_<version>.md` (e.g. `RELEASE_NOTES_1.0.1.md`). The release script will read this file and embed the contents into the appcast.
3. Run `./scripts/release.sh`. This builds, signs, notarizes, staples, signs the zip with ed25519, and updates `docs/appcast.xml`.
4. Review the appcast diff: `git diff docs/appcast.xml`
5. Commit and push both the version bump and the new appcast entry:
   ```sh
   git add ClaudeSwitcher/Info.plist docs/appcast.xml
   git commit -m "release: v<version>"
   git push
   ```
6. Create the GitHub release:
   ```sh
   gh release create v<version> release/ClaudeSwitcher.zip \
       --title "ClaudeSwitcher v<version>" \
       --notes-file RELEASE_NOTES_<version>.md
   ```
7. Update the Homebrew cask in `~/Documents/GitHub/homebrew-tap/Casks/claudeswitcher.rb`:
   - new `version`
   - new `sha256` from `shasum -a 256 release/ClaudeSwitcher.zip`
   Then commit and push the tap.

## Sparkle appcast hosting (one-time setup)

The `SUFeedURL` baked into `Info.plist` points to `https://claudeswitcher.candroid.dev/appcast.xml`. This is served by GitHub Pages from the `docs/` folder on the main branch of the ClaudeSwitcher repo.

**GitHub Pages configuration**:

1. On the repo: **Settings → Pages**
2. **Source**: *Deploy from a branch*
3. **Branch**: `main` / folder `/docs` → **Save**
4. After the first deploy (~30 s), put `claudeswitcher.candroid.dev` in the **Custom domain** input → **Save**
5. Once DNS propagates and the certificate is provisioned, enable **Enforce HTTPS**

**DNS configuration** (on your provider for `candroid.dev`):

```
Type:  CNAME
Host:  claudeswitcher
Value: cnrture.github.io.
TTL:   3600
```

Verify with:

```sh
dig +short claudeswitcher.candroid.dev CNAME
# → cnrture.github.io.

curl -sI https://claudeswitcher.candroid.dev/appcast.xml | head -1
# → HTTP/2 200
```

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
