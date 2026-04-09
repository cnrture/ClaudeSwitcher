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

## Distributing to users

Once `release/ClaudeSwitcher.zip` is ready:

1. **GitHub Releases** (recommended): `gh release create v1.0.0 release/ClaudeSwitcher.zip --notes "..."`
2. **Direct download**: host the zip on any web server
3. **Homebrew cask**: submit a cask to homebrew-cask for `brew install --cask claudeswitcher`

Users download the zip, unzip it, and drag `ClaudeSwitcher.app` into `/Applications`. Because it's notarized and stapled, it launches with no Gatekeeper warnings, even offline.
