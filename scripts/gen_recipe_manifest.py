#!/usr/bin/env python3
"""Generate OpenUpdater/RecipeManifest.json from the bundled recipes.

The manifest lets the app sync recipes from GitHub at runtime without an app update:

  - `hash`    an opaque token over every recipe's contents. The app compares it to the
              hash it last synced; it never recomputes this itself (so it can't disagree
              with this script over newlines/ordering).
  - `recipes` one entry per recipe: filename, `sha` (sha256 of contents, so the app
              re-downloads only changed recipes), and `minApp` — the lowest OpenUpdater
              version that supports every feature the recipe uses. The app activates only
              recipes whose `minApp` is <= its own version, so a newer recipe using an
              engine feature an older app lacks is skipped instead of silently failing.

`minApp` is derived from FEATURES below. Add an entry whenever a new *gated* engine
feature lands (a recipe field/behavior older apps can't honor), mapped to the version
that introduced it.
"""

import hashlib
import json
import re
import sys
from pathlib import Path

# Recipe feature -> minimum OpenUpdater version that supports it. redirect/tar/the
# substring predicate all ship in 0.9.0 alongside recipe sync itself, so every
# sync-capable app already supports them; the mechanism exists for FUTURE features.
FEATURES = [
    (re.compile(r"(?m)^\s*type:\s*redirect\b"), "0.9.0"),  # redirect check type
    (re.compile(r"(?m)^\s*format:\s*tar\b"), "0.9.0"),  # tar / tar.gz archives
    (re.compile(r"\[[^\]]*~[^\]]*\]"), "0.9.0"),  # [field~value] json path predicate
]
BASELINE = "0.0.0"

# A download URL that hardcodes one CPU architecture installs the wrong build on the
# other kind of Mac — e.g. an Intel asset on Apple Silicon (runs slowly under Rosetta)
# or an arm64 asset on Intel (won't run at all). Recipes select the right build with the
# `{arch}` placeholder + `arch:` map instead. Flag any download URL that names an arch
# literally but lacks `{arch}`. `\b` won't do — `_` is a word char, so `x86_64` needs an
# explicit non-alphanumeric boundary.
ARCH_TOKEN = re.compile(
    r"(?<![A-Za-z0-9])(x86_64|amd64|aarch64|arm64|intel64|intel|x64)(?![A-Za-z0-9])",
    re.IGNORECASE,
)
# Bundle IDs where a literal single-arch download is intentional because upstream ships
# only that architecture, so there is no `{arch}` alternative to select.
ARCH_LINT_ALLOWLIST = {
    "com.yourcompany.converseen",  # upstream ships a macOS x86_64 build only
}

REPO_ROOT = Path(__file__).resolve().parent.parent
RECIPES_DIR = REPO_ROOT / "OpenUpdater" / "Recipes"
MANIFEST_PATH = REPO_ROOT / "OpenUpdater" / "RecipeManifest.json"


def version_tuple(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))


def min_app(text):
    versions = [version for pattern, version in FEATURES if pattern.search(text)]
    return max(versions, key=version_tuple) if versions else BASELINE


def download_urls(text):
    """Yield (line_number, url) for every `url:` under a `download:` block — including
    the per-channel `download:` blocks nested under `channels:`. Scoped to download
    blocks so an arch literal in a `check:` URL or the `arch:` map isn't mistaken for a
    hardcoded download."""
    block_indent = None  # indent of the active download: block, or None when outside one
    for lineno, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        header = re.match(r"(\s*)download:\s*$", line)
        if header:
            block_indent = len(header.group(1))
            continue
        if block_indent is not None:
            if indent <= block_indent:
                block_indent = None  # dedented out of the download block
            else:
                field = re.match(r"\s*url:\s*(.+?)\s*$", line)
                if field:
                    yield lineno, field.group(1).strip("'\"")


def arch_violations(text, bundle_id):
    """Download URLs that name a CPU arch literally without a `{arch}` placeholder."""
    if bundle_id in ARCH_LINT_ALLOWLIST:
        return []
    hits = []
    for lineno, url in download_urls(text):
        if "{arch}" in url:
            continue
        match = ARCH_TOKEN.search(url)
        if match:
            hits.append((lineno, match.group(0), url))
    return hits


def main():
    recipes = []
    digest_lines = []
    violations = []
    for path in sorted(RECIPES_DIR.glob("*.yml")):
        content = path.read_bytes()
        text = content.decode("utf-8")
        for lineno, token, url in arch_violations(text, path.stem):
            violations.append(f"{path.name}:{lineno}: '{token}' in download URL: {url}")
        sha = hashlib.sha256(content).hexdigest()
        recipes.append({"file": path.name, "minApp": min_app(text), "sha": sha})
        digest_lines.append(f"{path.name}:{sha}")

    if violations:
        print(
            "Recipe download URL hardcodes a CPU architecture (use the {arch} "
            "placeholder + an arch: map, or add the bundle id to ARCH_LINT_ALLOWLIST "
            "if upstream ships only one arch):",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1

    manifest = {
        "schema": 1,
        "hash": hashlib.sha256("\n".join(digest_lines).encode("utf-8")).hexdigest(),
        "recipes": recipes,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {MANIFEST_PATH.relative_to(REPO_ROOT)} ({len(recipes)} recipes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
