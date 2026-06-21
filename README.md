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
- 🔄 **Per-app re-scan** — re-check a single app on demand, so updates applied elsewhere are picked up right away.
- ⬆️ **One-click updates** — download, verify, and replace an app in place. Update one, several, or all at once.
- 🧩 **Works with many sources** — GitHub Releases, Sparkle appcasts (auto-detected), and direct HTTP/JSON/XML/YAML version feeds.
- 🪶 **Lives in your menubar** — a quick popover for a glance, plus a full window for the details.
- 🔔 **Release notes** — jump straight to an app's changelog before you update.
- 🙈 **Ignore lists** — silence an app entirely, or skip just one version you don't want.
- 🧭 **Spot the gaps** — see which apps have no update source yet, and report them in a click to help grow coverage.
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

### Right-click options

Right-click any app for more options:

- **Re-scan App** — re-check just this app. Handy if you updated it elsewhere and
  want OpenUpdater to notice the new version right away.
- **Ignore this app** — stop showing updates for it.
- **Ignore this version** — skip a specific version but keep getting future ones.
- **Check for pre-releases** — include beta builds for that app.

Manage everything you've ignored under **Preferences → Ignore List**.

### Preferences

Open **Preferences** (⌘,) to:

- Add a **GitHub access token** to raise the update-check rate limit (optional;
  stored encrypted in your Keychain).
- Review and clear your **ignore list**.
- See your **unsupported apps** — the ones with no update source yet. From here you
  can copy or export their bundle IDs, or open a pre-filled GitHub issue to request
  support, which helps grow the community registry.

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

## Contributing

OpenUpdater's coverage grows through community-maintained **update recipes** — that
open registry of update sources is the whole point of the project. There are two ways
to help, and the first needs no fork.

### Request an app (no fork needed)

Open an **[Add an app](https://github.com/chenasraf/OpenUpdater/issues/new?template=add_recipe.yml)**
issue with the app's name, bundle identifier, and where its releases live. A maintainer
can turn that into a recipe — and if you've drafted the YAML yourself, you can paste it
right into the issue.

> Tip: the in-app **Preferences → Unsupported** tab lists every installed app that has
> no recipe yet. Each row has a **Request…** button that opens this issue form
> pre-filled with the app's name and bundle id (or use **Report All…** to file one
> issue covering the whole list).

### Write a recipe (pull request)

A recipe is a small YAML file telling OpenUpdater how to find an app's latest version
(and, ideally, where to download it). One file per app.

1. **Name the file after the bundle identifier:**
   `OpenUpdater/Recipes/<bundle-id>.yml` — e.g. `com.github.wez.wezterm.yml`. Find an
   app's bundle id with:
   ```sh
   osascript -e 'id of app "WezTerm"'
   ```
2. **Pick a source type** (`check.type`). Most apps fit one of:
   - `github_releases` — the newest release of a GitHub repo (most common).
   - `sparkle` — a Sparkle appcast feed. Only needed when an app sets its feed in
     code; apps with a static `SUFeedURL` are detected automatically, no recipe.
   - `html` / `xml` — pull a version out of a page with a regex.
   - `json` / `yaml` — read a version from an API or feed by key path.
3. **Add a `download` block** so updates install in one click — or omit it for a
   "check-only" recipe that just detects new versions and links out.
4. **Keep real recipes comment-free.** The documented template is the single source of
   field docs: [`docs/recipe-template.yml`](docs/recipe-template.yml).

A minimal GitHub example:

```yaml
id: com.github.wez.wezterm
name: WezTerm
homepage: https://wezterm.org

check:
  type: github_releases
  repo: wezterm/wezterm
  tag_pattern: '^\d'

download:
  url: https://github.com/wezterm/wezterm/releases/download/{tag}/WezTerm-macos-{tag}.zip
  format: zip

changelog:
  url: https://github.com/wezterm/wezterm/releases/tag/{tag}
```

URL placeholders: `{tag}`, `{version}`, `{major}` / `{minor}` / `{patch}`, and
`{arch}`. The template documents every field, the arch mapping, version normalization,
and tag filtering (`tag_pattern` / `tag_ignore` for skipping rolling tags like
`nightly`).

**Testing:** drop the file in `OpenUpdater/Recipes/`, rebuild, and confirm the app
shows in the Updates tab with the right version (recipes are bundled as resources, so a
rebuild picks them up). A malformed recipe is skipped silently — if your app doesn't
appear, double-check the YAML and that the filename matches the bundle id exactly.

### Bugs and ideas

Use the
**[bug report](https://github.com/chenasraf/OpenUpdater/issues/new?template=bug_report.yml)**
or
**[feature request](https://github.com/chenasraf/OpenUpdater/issues/new?template=feature_request.yml)**
templates.
