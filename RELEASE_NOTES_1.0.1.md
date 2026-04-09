## What's new

- **Custom app icon** — ClaudeSwitcher now ships with a proper icon you'll see in Finder, Launchpad, and the Get Info panel (crafted by me, with a lot of iteration 😄).
- **In-app auto-updates** — ClaudeSwitcher now uses [Sparkle](https://sparkle-project.org) to check for new versions in the background and install them with a single click. No more checking GitHub manually or waiting for `brew upgrade`.

## How auto-updates work

Every running copy of ClaudeSwitcher periodically checks `https://claudeswitcher.candroid.dev/appcast.xml` (roughly once a day). When a new release is available, Sparkle pops up a native macOS dialog describing the update — click **Install Update** and ClaudeSwitcher downloads, verifies, installs, and relaunches itself.

You can also trigger a check manually anytime:

> **Menu bar → Check for Updates…**

Every release is signed with an ed25519 key. Sparkle refuses any update that isn't signed with the correct key, so even a compromised server can't push malicious code to you.

## How to upgrade

### If you installed via Homebrew

```sh
brew upgrade --cask cnrture/tap/claudeswitcher
```

### If you downloaded manually

This is the last release you'll ever have to download manually. Starting with v1.0.1, the built-in auto-updater will handle all future releases. One more manual upgrade:

1. Download `ClaudeSwitcher.zip` below
2. Unzip and drag `ClaudeSwitcher.app` to `/Applications` (replace the old one)
3. Relaunch from your menu bar

Future releases will install themselves automatically.

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac (universal binary)
- Signed with Developer ID, notarized by Apple, hardened runtime enabled

## Privacy

The only outbound request ClaudeSwitcher makes is the Sparkle appcast fetch (a single public XML file). No analytics, no telemetry, no tracking, no identifiers sent anywhere.
