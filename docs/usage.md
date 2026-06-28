# Using OpenUpdater

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
- Install or remove the optional **Background Helper** (see [Installing updates](#installing-updates)
  below).

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
