# ZCode packaging of superpowers

This repository is a **thin packaging shell** around
[obra/superpowers](https://github.com/obra/superpowers). The skill library in
`skills/` is upstream's, mirrored as-is by a daily sync. Only the parts that
cannot survive verbatim on ZCode are replaced here.

## Why the repackaging exists

Upstream registers its SessionStart hook as a Claude Code `command` hook:

```json
{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start", "shell": "bash" }
```

That asks the hook runner to **exec** `hooks/run-hook.cmd`. Upstream's own
repository and release archive do carry the executable bit on that file, but the
copy ZCode installs does not: installing from a GitHub source goes through an
archive download, and the mode is lost on the way in. The exec then fails with
`EACCES` (exit 126), every session records `hook.run.failed`, and the whole skill
convention is never injected. The plugin still installs and lists its skills,
which makes the failure silent: the library looks installed but never primes the
model to reach for it.

The same thing happens to any plugin that registers a `command` hook invoking a
bundled script, so this is worth remembering beyond superpowers. Dropping the
dependency on file modes is the fix; the packaging below never consults one.

## What this packaging changes

| Path | Owner | Note |
| --- | --- | --- |
| `skills/` | upstream | mirrored verbatim, replaced on every sync |
| everything else not listed below | upstream | mirrored verbatim |
| `hooks/` | **packaging** | upstream's hook files are dropped; replaced by a ZCode `process` hook |
| `.zcode-plugin/plugin.json` | **packaging** | ZCode manifest |
| `.claude-plugin/plugin.json` | **packaging** | same manifest for compatibility |
| `.github/` | **packaging** | CI for this packaging |
| `scripts/sync-from-upstream.sh` | **packaging** | the sync itself |
| `SYNCED-FROM` | generated | upstream commit and version last mirrored |
| `ZCODE-PACKAGING.md` | **packaging** | this file |

`hooks/hooks.json` is a `process` hook, which runs an executable with an argument
vector and no shell:

```json
{ "type": "process", "command": "/bin/bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"] }
```

`/bin/bash` is the executable and the script is only an argument, so **the
executable bit is never consulted**. `hooks/session-start.sh` reads
`skills/using-superpowers/SKILL.md` and emits ZCode's top-level
`{"additionalContext": ...}`. It is written for the bash 3.2 that macOS ships,
because that is what `/bin/bash` resolves to on ZCode Desktop.

Every shell entry point the packaging itself invokes is reached through an
explicit interpreter (`bash scripts/sync-from-upstream.sh`), and both of those
files ship without the executable bit. Upstream's own test and tooling scripts
keep whatever mode upstream tracks; nothing here depends on it.

`sync-from-upstream.sh` derives its root from its own location and then runs
`rsync --delete`, so it refuses to start unless that root actually looks like
this repository (`.zcode-plugin/plugin.json` and `skills/` present, and a git
work tree). A copy of the script run from the wrong directory must fail loudly
instead of overlaying whatever directory it happens to sit beside.

## Following upstream

`.github/workflows/zcode-sync-upstream.yml` runs
`bash scripts/sync-from-upstream.sh` daily (`17 3 * * *`) and on demand. The
script clones upstream, and when the commit moved it overlays everything except
the packaging-owned paths listed above, then commits and pushes.

The version in both manifests is reconciled on each sync: it adopts upstream's
version when upstream moved ahead, and otherwise takes a patch bump so ZCode
always sees a version change (its update detection is version-driven).

After a sync lands, ZCode still needs the plugin update action — a market refresh
updates the catalog, not the installed copy.
