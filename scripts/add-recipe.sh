#!/usr/bin/env bash
#
# add-recipe.sh — turn a recipe contribution (issue or PR) into a committed recipe.
#
# Interactive flow:
#   1. pick issues or PRs, then pick one open item
#   2. extract the proposed recipe YAML, drop the `enabled:` flag
#   3. preview it and confirm the target path
#   4. write it to OpenUpdater/Recipes/<bundle-id>.yml
#   5. verify with `make recipe-check`
#   6. commit (with confirmation)
#   7. close the item and post a thank-you comment (with confirmation)
#
# Requires: gh (authenticated), make, git. Set GITHUB_TOKEN to raise rate limits.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
RECIPES_DIR="OpenUpdater/Recipes"
THANK_YOU="Added recipe, thank you for the contribution!

- New recipes will be loaded without need for app update, so this is immediately available.
- If you have an existing custom recipe for this bundle, it will override the recipe on GitHub. Remove/disable your custom recipe to default to the newly added one"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

confirm() { # confirm "prompt" -> returns 0 for yes (default: yes)
  local reply
  read -r -p "$1 [Y/n] " reply
  [[ ! "$reply" =~ ^[Nn]$ ]]
}

command -v gh >/dev/null || die "gh CLI not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"

# --- 1a. issues or PRs --------------------------------------------------------
KIND="${1:-}"
if [[ -z "$KIND" ]]; then
  read -r -p "Source — [i]ssues or [p]ull requests? [i/p] " k
  case "$k" in
    p|P) KIND=pr ;;
    *)   KIND=issue ;;
  esac
elif [[ "$KIND" == "pr" || "$KIND" == "prs" ]]; then
  KIND=pr
else
  KIND=issue
fi

# --- 1b. list open items and pick one ----------------------------------------
bold "Open ${KIND}s:"
if [[ "$KIND" == "pr" ]]; then
  gh pr list --state open --limit 50 \
    --json number,title,author \
    -q '.[] | "  #\(.number)\t\(.title)  (@\(.author.login))"'
else
  gh issue list --state open --limit 50 \
    --json number,title,author \
    -q '.[] | "  #\(.number)\t\(.title)  (@\(.author.login))"'
fi
echo
read -r -p "Enter the ${KIND} number to import: " NUM
[[ "$NUM" =~ ^[0-9]+$ ]] || die "not a number: $NUM"

# --- 2. extract the recipe YAML ----------------------------------------------
# Pulls the first fenced code block out of markdown text on stdin.
extract_fence() {
  awk '
    /^[[:space:]]*```/ { if (infence) exit; infence=1; next }
    infence { print }
  '
}

RAW=""
if [[ "$KIND" == "pr" ]]; then
  # Prefer a recipe file actually changed by the PR (works across forks).
  read -r HEAD_SHA HEAD_REPO < <(
    gh pr view "$NUM" --json headRefOid,headRepository,headRepositoryOwner \
      -q '[.headRefOid, "\(.headRepositoryOwner.login)/\(.headRepository.name)"] | @tsv'
  )
  RECIPE_PATH="$(
    gh pr view "$NUM" --json files -q '.files[].path' \
      | grep -E "^${RECIPES_DIR}/.*\.ya?ml$" | head -1 || true
  )"
  if [[ -n "$RECIPE_PATH" ]]; then
    dim "Reading $RECIPE_PATH from $HEAD_REPO@${HEAD_SHA:0:7}"
    RAW="$(gh api "repos/${HEAD_REPO}/contents/${RECIPE_PATH}?ref=${HEAD_SHA}" \
      -q '.content' | base64 --decode)"
  else
    dim "No recipe file in the PR diff — falling back to the PR body."
    RAW="$(gh pr view "$NUM" --json body -q '.body' | extract_fence)"
  fi
else
  RAW="$(gh issue view "$NUM" --json body -q '.body' | extract_fence)"
fi

[[ -n "${RAW//[$'\n\t ']/}" ]] || die "no recipe YAML found in ${KIND} #$NUM"

# Drop the enabled flag; collapse leading/trailing blank lines.
RECIPE="$(printf '%s\n' "$RAW" \
  | sed '/^[[:space:]]*enabled[[:space:]]*:/d' \
  | awk 'BEGIN{started=0} /[^[:space:]]/{started=1} started{buf=buf $0 "\n"} END{sub(/\n+$/,"",buf); print buf}')"

field() { printf '%s\n' "$RECIPE" | grep -m1 "^$1:" | sed "s/^$1:[[:space:]]*//" | sed 's/^["'\'']//;s/["'\'']$//' | tr -d '\r'; }
ID="$(field id)"
NAME="$(field name)"
[[ -n "$ID" ]] || die "recipe has no 'id:' field"
DEST="$RECIPES_DIR/$ID.yml"

# --- 3. preview ---------------------------------------------------------------
echo
bold "── Recipe preview ─────────────────────────────"
printf '%s\n' "$RECIPE"
bold "───────────────────────────────────────────────"
echo "  id:     $ID"
echo "  name:   ${NAME:-<none>}"
echo "  dest:   $DEST"
[[ -f "$DEST" ]] && dim "  (overwrites an existing recipe)"
echo
confirm "Write this recipe to $DEST?" || die "aborted"

# --- 4. write -----------------------------------------------------------------
printf '%s\n' "$RECIPE" > "$DEST"
bold "Wrote $DEST"

# --- 5. verify ----------------------------------------------------------------
echo
bold "Verifying with make recipe-check ID=$ID …"
if ! make recipe-check ID="$ID"; then
  die "verification failed — recipe left in working tree at $DEST for you to fix"
fi
echo
confirm "Verification done. Looks correct?" || die "aborted — recipe left at $DEST"

# --- 6. commit ----------------------------------------------------------------
echo
MSG="feat(recipe): ${NAME:-$ID} (\`$ID\`)"
echo "Commit message: $MSG"
if confirm "Regenerate manifest and commit?"; then
  make manifest >/dev/null
  git add "$DEST" OpenUpdater/RecipeManifest.json
  git commit -m "$MSG"
  bold "Committed."
else
  dim "Skipped commit — recipe staged in working tree."
fi

# --- 7. close + comment -------------------------------------------------------
echo
if confirm "Close ${KIND} #$NUM and post the thank-you comment?"; then
  if [[ "$KIND" == "pr" ]]; then
    gh pr comment "$NUM" --body "$THANK_YOU"
    gh pr close "$NUM"
  else
    gh issue close "$NUM" --reason completed --comment "$THANK_YOU"
  fi
  bold "Closed ${KIND} #$NUM."
else
  dim "Left ${KIND} #$NUM open."
fi
