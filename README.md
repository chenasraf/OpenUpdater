<div align="center">
  <img src="docs/icon.png" width="128" alt="OpenUpdater app icon" />
  <h1>OpenUpdater</h1>
  <p><strong>Keep every Mac app up to date — from one open, community-driven source.</strong></p>
</div>

OpenUpdater is a lightweight macOS menubar app that scans the apps in your `/Applications` folder,
finds newer versions, and updates them in a click. It isn't limited to App Store or any single
package manager — it covers regular Mac apps: GitHub releases, Sparkle-based apps, and direct
downloads.

OpenUpdater provides a crowdsourced, community-maintained set of update sources. Coverage grows as
people add recipes, so OpenUpdater can keep up with apps that have no built-in updater of their own.

<div align="center">
  <img src="docs/screenshots/screenshot-01.png" width="820" alt="OpenUpdater showing available updates" />
</div>

## Features

- 🔍 **Automatic scanning** — reads your installed apps and checks each for a newer version.
- 🔄 **Per-app re-scan** — re-check a single app on demand, so updates applied elsewhere are picked
  up right away.
- ⬆️ **One-click updates** — download, verify, and replace an app in place. Update one, several, or
  all at once.
- 🧩 **Works with many sources** — GitHub Releases, Sparkle appcasts (auto-detected), and direct
  HTTP/JSON/XML/YAML version feeds.
- 🪶 **Lives in your menubar** — a quick popover for a glance, plus a full window for the details.
- 🔔 **Release notes** — jump straight to an app's changelog before you update.
- 🙈 **Ignore lists** — silence an app entirely, or skip just one version you don't want.
- 🧭 **Spot the gaps** — see which apps have no update source yet, and report them in a click to
  help grow coverage.
- 🧪 **Pre-releases** — opt into beta/pre-release builds on a per-app basis.
- 🌿 **Release channels** — for apps with more than one stream (Firefox/Thunderbird ESR, LibreOffice
  Fresh/Still, Blender LTS, …), pick which one to track per app.
- 🔐 **Optional GitHub token** — raises GitHub's rate limit for faster, more reliable checks (stored
  encrypted in your Keychain).

## Installation

1. Download the latest **`OpenUpdater.dmg`** from the
   [Releases page](https://github.com/chenasraf/OpenUpdater/releases/latest).
2. Open the DMG and drag **OpenUpdater** into your **Applications** folder.
3. Launch it from Applications. OpenUpdater appears in your menubar (the two-arrows icon).

> [!NOTE]  
> The first time you open it, macOS may ask you to confirm. If it's blocked, right-click the app in
> Finder and choose **Open**, then confirm.

**Requirements:** macOS 15 (Sequoia) or later.

## Usage

### The menubar

Click the menubar icon for a quick popover listing available updates. From there you can check for
updates, open the full window, or quit.

Closing the main window (⌘W) keeps OpenUpdater running quietly in the menubar so it can keep
checking in the background. To quit entirely, use **⌘Q** (it'll ask to confirm).

### Checking and updating

- The **Updates** tab lists every app with a newer version, showing the new version next to your
  installed one.
- Click **Update** on a row to update a single app.
- Select multiple rows (click, ⌘-click, ⇧-click) and use **Update Selected** to update a batch, or
  **Update All** to update everything at once.
- A running update shows live progress; click the **✕** to cancel it.
- The **Installed** tab shows all your apps and whether each is up to date.

Press the refresh button (top-right) any time to check again.

### Right-click options

Right-click any app for more options:

- **Re-scan App** — re-check just this app. Handy if you updated it elsewhere and want OpenUpdater
  to notice the new version right away.
- **Ignore this app** — stop showing updates for it.
- **Ignore this version** — skip a specific version but keep getting future ones.
- **Check for pre-releases** — include beta builds for that app.
- **Release Channel** — for apps that publish more than one stream (e.g. Firefox Stable vs ESR,
  LibreOffice Fresh vs Still, Blender Latest vs LTS), choose which one to follow. Only shown when a
  recipe defines multiple channels.

Manage everything you've ignored under **Preferences → Ignore List**.

### Preferences

Open **Preferences** (⌘,) to:

- Add a **GitHub access token** to raise the update-check rate limit (optional; stored encrypted in
  your Keychain).
- Review and clear your **ignore list**.
- See your **unsupported apps** — the ones with no update source yet. From here you can copy or
  export their bundle IDs, or open a pre-filled GitHub issue to request support, which helps grow
  the community registry.
- Install or remove the optional **Background Helper** (see
  [Installing updates](#installing-updates) below).

## How it works

For each installed app, OpenUpdater figures out the latest version using the best available source:

- **Sparkle** — apps that advertise a Sparkle feed are detected automatically, no configuration
  needed.
- **Update recipes** — a small YAML file per app describes where to look (a GitHub repo, a download
  page, a version API, etc.). These recipes are the open, community-maintained registry at the heart
  of the project.

When you update, OpenUpdater downloads the new build, verifies it's the right app and validly
signed, then swaps it into place — sending the old version to the Trash.

### Installing updates

Most updates are a simple swap — replacing an app in `/Applications` with a newer copy — and need no
special permissions. Two cases need administrator rights: an app that ships as a `.pkg` installer,
and replacing an app you don't have write access to (e.g. one installed by another admin or sitting
in a protected location). For those, OpenUpdater shows the standard macOS password prompt for that
one install.

If you'd rather not be asked each time, install the optional **Background Helper** from
**Preferences → Background Helper**. It's a small privileged service that performs exactly those two
operations — running `.pkg` installers and replacing protected apps — so that, once set up, updates
apply without a password prompt. Setup is one-time:

1. Click **Install Helper…**.
2. Approve **OpenUpdater** in **System Settings → General → Login Items & Extensions** when macOS
   asks (the helper status then shows _Installed and enabled_).

The helper runs as a separate XPC daemon, registered through Apple's `SMAppService`. It only acts on
requests from OpenUpdater itself — every call is checked against the app's code signature before
anything runs — and does nothing beyond installing/replacing apps. You can take it out at any time
with **Remove**, which unregisters the daemon; OpenUpdater falls back to the per-install password
prompt. The helper is entirely optional — everything works without it.

## Contributing

OpenUpdater's coverage grows through community-maintained **update recipes** — that open registry of
update sources is the whole point of the project. There are a few ways to help, and most need no
fork.

### Request an app (no fork needed)

Open an
**[Add an app](https://github.com/chenasraf/OpenUpdater/issues/new?template=add_recipe.yml)** issue
with the app's name, bundle identifier, and where its releases live. A maintainer can turn that into
a recipe — and if you've drafted the YAML yourself, you can paste it right into the issue.

> Tip: the in-app **Preferences → Unsupported** tab lists every installed app that has no recipe
> yet. Each row's **⋯** menu can **Request on GitHub** (a pre-filled issue) or **Create Custom
> Recipe** (see below); **Report All…** files one issue for the whole list.

### Build a recipe in the app (no fork, no rebuild)

OpenUpdater can author and run recipes for you — no Xcode needed. Open **Preferences → Custom
Recipes** (or pick **Create Custom Recipe** from an app's **⋯** menu in the **Unsupported** tab) to
get an editable YAML pane with:

- **Live validation** as you type, plus an **enable/disable** switch per recipe.
- **Override built-in recipes** — a custom recipe with the same bundle id wins, so you can fix or
  tweak coverage for an app without waiting for a release.
- **Submit Recipe…**, which opens a pre-filled GitHub issue with your YAML attached so it can be
  folded into the shared registry.

Custom recipes live in `~/Library/Application Support/OpenUpdater/Recipes/` and take effect
immediately — this is the easiest way to write and test a recipe before contributing it. New drafts
start disabled until you fill in the details and flip them on.

### Write a recipe (pull request)

A recipe is a small YAML file telling OpenUpdater how to find an app's latest version (and, ideally,
where to download it). One file per app.

1. **Name the file after the bundle identifier:** `OpenUpdater/Recipes/<bundle-id>.yml` — e.g.
   `com.github.wez.wezterm.yml`. Find an app's bundle id with:
   ```sh
   osascript -e 'id of app "WezTerm"'
   ```
2. **Pick a source type** (`check.type`). Most apps fit one of:
   - `github_releases` — the newest release of a GitHub repo (most common).
   - `sparkle` — a Sparkle appcast feed. Only needed when an app sets its feed in code; apps with a
     static `SUFeedURL` are detected automatically, no recipe.
   - `html` / `xml` — pull a version out of a page with a regex.
   - `json` / `yaml` — read a version from an API or feed by key path.
3. **Add a `download` block** so updates install in one click — or omit it for a "check-only" recipe
   that just detects new versions and links out.
4. **Keep real recipes comment-free.** The documented template is the single source of field docs:
   [`docs/recipe-template.yml`](docs/recipe-template.yml).

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

URL placeholders: `{tag}`, `{version}`, `{major}` / `{minor}` / `{patch}`, and `{arch}`. The
template documents every field, the arch mapping, version normalization, and tag filtering
(`tag_pattern` / `tag_ignore` for skipping rolling tags like `nightly`).

To offer multiple **release channels** (ESR/LTS/Still, etc.), add a `channels` list — each channel's
`check`/`download` overlay the base, and the user picks one per app. For sources that move over
time, a channel can derive part of its URL with `resolve` (look a value up from another page) and
`select: latest` (take the highest of several matches) instead of hardcoding it. See the template
for both.

### Bugs and ideas

Use the
**[bug report](https://github.com/chenasraf/OpenUpdater/issues/new?template=bug_report.yml)** or
**[feature request](https://github.com/chenasraf/OpenUpdater/issues/new?template=feature_request.yml)**
templates.
