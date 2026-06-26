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

REPO_ROOT = Path(__file__).resolve().parent.parent
RECIPES_DIR = REPO_ROOT / "OpenUpdater" / "Recipes"
MANIFEST_PATH = REPO_ROOT / "OpenUpdater" / "RecipeManifest.json"


def version_tuple(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))


def min_app(text):
    versions = [version for pattern, version in FEATURES if pattern.search(text)]
    return max(versions, key=version_tuple) if versions else BASELINE


def main():
    recipes = []
    digest_lines = []
    for path in sorted(RECIPES_DIR.glob("*.yml")):
        content = path.read_bytes()
        sha = hashlib.sha256(content).hexdigest()
        recipes.append(
            {"file": path.name, "minApp": min_app(content.decode("utf-8")), "sha": sha}
        )
        digest_lines.append(f"{path.name}:{sha}")

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
