#!/usr/bin/env bash
# sync-from-upstream.sh — overlay obra/superpowers onto this packaging repo,
# preserving the ZCode packaging shell. Idempotent: exits without a commit when
# the upstream commit has not moved.
#
# The packaging owns hooks/ outright. Upstream's SessionStart hook execs
# hooks/run-hook.cmd directly, which fails on ZCode because a source-archive
# install does not carry the executable bit (EACCES, exit 126) and the skill
# convention is never injected. hooks/ is excluded from the overlay and replaced
# by a `process` hook that hands the script to /bin/bash as an argument.
set -euo pipefail

# Overridable so a fork can be synced, and so the overlay can be exercised
# against a throwaway repository in tests.
UPSTREAM="${SUPERPOWERS_UPSTREAM:-https://github.com/obra/superpowers.git}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# `rsync --delete` into the wrong root is destructive and ROOT is derived from
# $0, so a copy of this script run from somewhere else would overlay whatever
# directory it happens to sit beside. Refuse anything that is not this repo.
if [[ "$ROOT" == "/" || ! -f "$ROOT/.zcode-plugin/plugin.json" || ! -d "$ROOT/skills" ]]; then
  echo "error: ${ROOT} is not the superpowers packaging repo; refusing to overlay" >&2
  exit 1
fi
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: ${ROOT} is not a git work tree; refusing to overlay" >&2
  exit 1
fi

LAST=""
[[ -f SYNCED-FROM ]] && LAST="$(grep -m1 '^commit:' SYNCED-FROM | awk '{print $2}')"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --depth 1 "$UPSTREAM" "$TMP/up"
NEW="$(git -C "$TMP/up" rev-parse HEAD)"

if [[ "$NEW" == "$LAST" ]]; then
  echo "upstream unchanged ($NEW)"
  exit 0
fi
echo "syncing upstream $LAST -> $NEW"

UPSTREAM_VERSION=""
for f in "$TMP/up/.claude-plugin/plugin.json" "$TMP/up/.codex-plugin/plugin.json" "$TMP/up/plugin.json"; do
  if [[ -f "$f" ]]; then
    UPSTREAM_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$f")"
    [[ -n "$UPSTREAM_VERSION" ]] && break
  fi
done

# Packaging-only paths that must survive the overlay. Everything else mirrors upstream.
rsync -a --delete \
  --exclude='/.git' \
  --exclude='/.github/' \
  --exclude='/.zcode-plugin/' \
  --exclude='/.claude-plugin/' \
  --exclude='/hooks/' \
  --exclude='/ZCODE-PACKAGING.md' \
  --exclude='/SYNCED-FROM' \
  --exclude='/scripts/sync-from-upstream.sh' \
  "$TMP/up/" ./

# Adopt upstream's version when it moved ahead; otherwise bump our patch, so
# ZCode always sees a version change (update detection is version-driven).
UPSTREAM_VERSION="$UPSTREAM_VERSION" python3 - <<'PY'
import json, os, re

paths = (".zcode-plugin/plugin.json", ".claude-plugin/plugin.json")

def parse(value):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", str(value).strip())
    return tuple(int(part) for part in match.groups()) if match else None

upstream_raw = os.environ.get("UPSTREAM_VERSION", "")
current_raw = ""
for path in paths:
    if os.path.exists(path):
        current_raw = str(json.load(open(path)).get("version", "0.0.0"))
        break

upstream, current = parse(upstream_raw), parse(current_raw)
if upstream and current and upstream > current:
    nxt = "%d.%d.%d" % upstream
    print("version: upstream %s ahead of packaging %s -> %s" % (upstream_raw, current_raw, nxt))
elif current:
    nxt = "%d.%d.%d" % (current[0], current[1], current[2] + 1)
    print("version: patch bump %s -> %s (upstream version %s)" % (current_raw, nxt, upstream_raw or "unknown"))
else:
    nxt = upstream_raw or "0.0.1"
    print("version: seeded %s from upstream" % nxt)

for path in paths:
    if not os.path.exists(path):
        continue
    data = json.load(open(path))
    data["version"] = nxt
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
PY

cat > SYNCED-FROM <<EOF
upstream: $UPSTREAM
commit: $NEW
upstream_version: ${UPSTREAM_VERSION:-unknown}
synced_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

git add -A
if git diff --cached --quiet; then
  echo "nothing to commit"
  exit 0
fi

if [[ "${CI:-}" == "true" ]]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi
git commit -q -m "sync: upstream superpowers ${NEW:0:7}"
git push
echo "synced and pushed (${NEW:0:7})"
