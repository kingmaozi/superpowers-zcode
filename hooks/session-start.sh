#!/bin/bash
# SessionStart injection for the ZCode packaging of superpowers.
#
# Upstream ships hooks/run-hook.cmd and expects the hook runner to exec that file
# directly. ZCode installs from a source archive, which does not carry the
# executable bit, so the exec fails with EACCES (exit 126) and the skill
# convention is never injected. This packaging registers the hook as a ZCode
# `process` entry instead: /bin/bash is the executable and this file is only an
# argument, so no executable bit is involved.
#
# Emits ZCode's top-level additionalContext. Must stay compatible with the
# system bash 3.2 that macOS ships, which is what /bin/bash resolves to there.
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${HOOK_DIR}/.." && pwd)"
SKILL_FILE="${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md"

# Without the skill body there is nothing worth injecting; stay silent instead
# of failing the session start.
[ -r "$SKILL_FILE" ] || exit 0

# JSON string escaping. Control characters other than the whitespace escaped
# below are dropped, because a raw one would make the output unparseable.
escape_json() {
  local s
  s="$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

PREAMBLE='<EXTREMELY_IMPORTANT>
You have superpowers, packaged for ZCode.

Packaging notes. These describe this repackaging, not the skill library:
- Reach the library through the Skill tool as "superpowers:<name>", for example
  superpowers:brainstorming or superpowers:systematic-debugging.
- The Claude Code SessionStart hook from upstream is replaced here, because it
  depends on an executable bit that a ZCode install does not preserve. Reading
  this text means the replacement ran.
- The "Platform Adaptation" section inside the skill lists no reference file for
  ZCode, so there is nothing extra to load for this harness.

Below is the full content of the superpowers using-superpowers skill.
</EXTREMELY_IMPORTANT>'

SKILL_BODY="$(cat "$SKILL_FILE")"

printf '{"additionalContext": "%s"}\n' "$(escape_json "${PREAMBLE}

${SKILL_BODY}")"
