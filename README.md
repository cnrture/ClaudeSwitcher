<div align="center">

# ClaudeSwitcher

**A lightweight macOS menu bar app to manage and switch between multiple Claude Code accounts with a single click.**

[![Latest Release](https://img.shields.io/github/v/release/cnrture/ClaudeSwitcher?style=flat-square&color=blue)](https://github.com/cnrture/ClaudeSwitcher/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/cnrture/ClaudeSwitcher/total?style=flat-square&color=green)](https://github.com/cnrture/ClaudeSwitcher/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?style=flat-square)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blueviolet?style=flat-square)](#license)

</div>

---

## Overview

If you juggle multiple Claude Code accounts — personal, work, a side project, or different organizations — ClaudeSwitcher lets you swap between them instantly from your menu bar. No more manual `/logout` dances, re-entering credentials, or losing context every time you switch.

The app safely backs up your Claude Code credentials and configuration per account, stores them securely in the macOS Keychain, and restores the right set when you switch — all with a single click.

## Features

- **Instant account switching** — swap accounts from the menu bar in a single click
- **Unlimited accounts** — add as many Claude Code accounts as you need
- **Secure by design** — credentials are stored in the macOS Keychain; config backups are written with `0600` permissions (owner-only)
- **Native menu bar experience** — built with SwiftUI, uses `MenuBarExtra`, zero dock clutter
- **Universal binary** — runs natively on both Apple Silicon and Intel Macs
- **Signed and notarized** — no Gatekeeper warnings, distributed via an Apple-notarized binary
- **In-app auto-updates** — powered by [Sparkle](https://sparkle-project.org), ed25519-signed, one-click install
- **Organization aware** — shows organization names alongside each account for easy identification

## Installation

### Homebrew (recommended)

```sh
brew install --cask cnrture/tap/claudeswitcher
```

This adds the tap and installs the latest signed, notarized release in one step.

### Manual download

1. Grab the latest `ClaudeSwitcher.zip` from [**Releases**](https://github.com/cnrture/ClaudeSwitcher/releases/latest)
2. Unzip and drag `ClaudeSwitcher.app` into your `/Applications` folder
3. Launch it — the icon will appear in your menu bar

Because the app is signed with a Developer ID and notarized by Apple, it opens without any security warnings, even offline.

## Getting Started

Once the app is running, look for the Claude Switcher icon in your menu bar.

### Adding your first account

1. Log in to **Claude Code** in your terminal as usual
2. Click the menu bar icon, then **+ Add Current Account**
3. Your current session is backed up — you'll see the account appear in the list

### Adding more accounts

1. Run `/logout` in your Claude Code session
2. Log in with a different account
3. Click **+ Add Current Account** again
4. Repeat for as many accounts as you want

### Switching between accounts

Just click any account in the list. ClaudeSwitcher will:

1. Back up your current session's credentials and config
2. Restore the target account's credentials into the Keychain
3. Update your Claude Code config file to point at the target organization

The next `claude` command you run will use the new account — no restart required.

### Removing an account

Click the `×` next to any account and confirm. The backup files and Keychain entries for that account will be cleaned up.

## Requirements

- **macOS 13** (Ventura) or later
- **Claude Code** installed and authenticated at least once (so there's a session to back up)
- Apple Silicon or Intel Mac — ClaudeSwitcher ships as a universal binary

## How It Works

ClaudeSwitcher is intentionally minimal. It doesn't communicate with Anthropic's servers, doesn't intercept traffic, and doesn't require any special permissions beyond what any app that writes to your home directory needs.

When you add an account, ClaudeSwitcher:

1. Reads the current Claude Code credentials from the macOS Keychain (service: `Claude Code-credentials`)
2. Reads the OAuth account metadata from `~/.claude/.claude.json` (or `~/.claude.json` on older setups)
3. Stores the credentials in a dedicated Keychain item (service: `claude-code`, account: `account-N-email`)
4. Writes a backup of the config file under `~/.claude-swap-backup/configs/` with owner-only permissions
5. Maintains an index of all accounts at `~/.claude-swap-backup/sequence.json`

When you switch accounts, it reverses the process for the target account and merges only the `oauthAccount` field into your live config, leaving the rest of your Claude Code settings untouched.

### Storage layout

```
~/.claude-swap-backup/
├── sequence.json                                # account index + active account number
└── configs/
    ├── .claude-config-1-alice@example.com.json  # config backup for account 1
    ├── .claude-config-2-bob@example.com.json    # config backup for account 2
    └── ...
```

Credentials themselves never touch the filesystem — they live entirely in the Keychain.

## Auto-updates

ClaudeSwitcher ships with the [Sparkle](https://sparkle-project.org) framework, the de-facto standard for macOS auto-updates (used by Sketch, Transmission, iTerm2, Alfred, and countless others).

**How it works**:

- The app periodically checks `https://claudeswitcher.candroid.dev/appcast.xml` in the background (roughly once per day)
- When a new version is available, Sparkle shows a native dialog describing the release
- You click **Install Update**, and the app downloads, verifies, installs, and relaunches automatically
- Every release is signed with an ed25519 key; Sparkle refuses unsigned or mis-signed updates, so even a compromised server can't push malicious code

You can also trigger a check manually anytime from **menu bar → Check for Updates…**

If you installed via Homebrew (`brew install --cask cnrture/tap/claudeswitcher`), you can continue to use `brew upgrade --cask claudeswitcher` — both paths work.

## Privacy & Security

- **No telemetry, no analytics, no tracking.** The only outbound request ClaudeSwitcher ever makes is the Sparkle appcast check, which fetches a public XML file from `claudeswitcher.candroid.dev` — no identifiers, no usage data.
- **Credentials stay in the Keychain.** Nothing sensitive is ever written to plaintext files.
- **Config backups are owner-only** (`chmod 600`) so other users on the same machine can't read them.
- **The binary is code-signed with a Developer ID and notarized by Apple**, so macOS can verify its integrity before every launch.
- **Updates are ed25519-signed.** Even if the appcast host were compromised, Sparkle would refuse any update that wasn't signed with the release key.
- **Source code is 100% open** — inspect what it does, or build it yourself.

## Building from Source

ClaudeSwitcher is a standard Swift Package Manager project. To build a debug binary:

```sh
git clone https://github.com/cnrture/ClaudeSwitcher.git
cd ClaudeSwitcher
swift build -c release
```

The binary will be at `.build/release/ClaudeSwitcher`.

To produce a signed, notarized `.app` bundle suitable for distribution, see [`scripts/README.md`](scripts/README.md) — the `scripts/release.sh` script automates the entire build → sign → notarize → staple → package pipeline.

## Troubleshooting

**"Claude config not found"** — ClaudeSwitcher looks for `~/.claude/.claude.json` or `~/.claude.json`. Make sure you've logged in to Claude Code at least once before adding your first account.

**"Cannot read current credentials"** — Your current Claude Code session isn't logged in, or the Keychain item is missing. Log in again and retry.

**Switched accounts but Claude Code still uses the old one** — Close and reopen your terminal session, or start a fresh `claude` invocation. The credentials are updated in the Keychain immediately, but long-running sessions may cache them.

**Menu bar icon not showing** — macOS hides menu bar extras when there's not enough room. Try quitting some menu bar apps, or use [Bartender](https://www.macbartender.com) / [Hidden Bar](https://github.com/dwarvesf/hidden) to manage the overflow.

## Contributing

Issues and pull requests are welcome. For feature requests or bug reports, please [open an issue](https://github.com/cnrture/ClaudeSwitcher/issues). If you'd like to contribute code, fork the repo, make your changes on a feature branch, and open a PR against `main`.

## License

Released under the MIT License. See [`LICENSE`](LICENSE) for details.

## Acknowledgments

ClaudeSwitcher is an independent community project and is not affiliated with, endorsed by, or sponsored by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic, PBC.
