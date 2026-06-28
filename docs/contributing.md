# Contributing to OpenUpdater

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
   [`docs/recipe-template.yml`](recipe-template.yml).

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
