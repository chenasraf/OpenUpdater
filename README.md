<div align="center">
  <img src="docs/icon.png" width="128" alt="OpenUpdater app icon" />
  <h1>OpenUpdater</h1>
  <p><strong>Keep every Mac app up to date — from one open, community-driven source.</strong></p>
</div>

OpenUpdater is a lightweight macOS menubar app that scans the apps in your
`/Applications` folder, finds newer versions, and updates them in a click. It
isn't limited to App Store or any single package manager — it covers regular Mac
apps: GitHub releases, Sparkle-based apps, and direct downloads.

The **"open"** part is the registry of *where* to find updates: a crowdsourced,
community-maintained set of update sources. Coverage grows as people add recipes,
so OpenUpdater can keep up with apps that have no built-in updater of their own.

<div align="center">
  <img src="docs/screenshots/screenshot-01.png" width="820" alt="OpenUpdater showing available updates" />
</div>

## Features

- 🔍 **Automatic scanning** — reads your installed apps and checks each for a newer version.
- ⬆️ **One-click updates** — download, verify, and replace an app in place. Update one, several, or all at once.
- 🧩 **Works with many sources** — GitHub Releases, Sparkle appcasts (auto-detected), and direct HTTP/JSON/XML/YAML version feeds.
- 🪶 **Lives in your menubar** — a quick popover for a glance, plus a full window for the details.
- 🔔 **Release notes** — jump straight to an app's changelog before you update.
- 🙈 **Ignore lists** — silence an app entirely, or skip just one version you don't want.
- 🧪 **Pre-releases** — opt into beta/pre-release builds on a per-app basis.
- 🔐 **Optional GitHub token** — raises GitHub's rate limit for faster, more reliable checks (stored encrypted in your Keychain).

## Installation

1. Download the latest **`OpenUpdater.dmg`** from the
   [Releases page](https://github.com/chenasraf/OpenUpdater/releases/latest).
2. Open the DMG and drag **OpenUpdater** into your **Applications** folder.
3. Launch it from Applications. OpenUpdater appears in your menubar (the
   two-arrows icon).

> [!NOTE]
> The first time you open it, macOS may ask you to confirm. If it's blocked,
> right-click the app in Finder and choose **Open**, then confirm.

**Requirements:** macOS 15 (Sequoia) or later.

## Usage

### The menubar

Click the menubar icon for a quick popover listing available updates. From there
you can check for updates, open the full window, or quit.

Closing the main window (⌘W) keeps OpenUpdater running quietly in the menubar so
it can keep checking in the background. To quit entirely, use **⌘Q** (it'll ask
to confirm).

### Checking and updating

- The **Updates** tab lists every app with a newer version, showing the new
  version next to your installed one.
- Click **Update** on a row to update a single app.
- Select multiple rows (click, ⌘-click, ⇧-click) and use **Update Selected** to
  update a batch, or **Update All** to update everything at once.
- A running update shows live progress; click the **✕** to cancel it.
- The **Installed** tab shows all your apps and whether each is up to date.

Press the refresh button (top-right) any time to check again.

### Ignoring apps

Right-click any app for more options:

- **Ignore this app** — stop showing updates for it.
- **Ignore this version** — skip a specific version but keep getting future ones.
- **Check for pre-releases** — include beta builds for that app.

Manage everything you've ignored under **Preferences → Ignore List**.

### Preferences

Open **Preferences** (⌘,) to:

- Add a **GitHub access token** to raise the update-check rate limit (optional;
  stored encrypted in your Keychain).
- Review and clear your **ignore list**.

## How it works

For each installed app, OpenUpdater figures out the latest version using the best
available source:

- **Sparkle** — apps that advertise a Sparkle feed are detected automatically, no
  configuration needed.
- **Update recipes** — a small YAML file per app describes where to look (a GitHub
  repo, a download page, a version API, etc.). These recipes are the open,
  community-maintained registry at the heart of the project.

When you update, OpenUpdater downloads the new build, verifies it's the right app
and validly signed, then swaps it into place — sending the old version to the
Trash.

## Contributing update recipes

Want OpenUpdater to support an app it doesn't recognize yet? Add a recipe. Each
recipe is a short YAML file named after the app's bundle identifier. See
[`docs/recipe-template.yml`](docs/recipe-template.yml) for a fully documented
template covering every field and source type.
