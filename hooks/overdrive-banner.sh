#!/bin/bash
# overdrive-banner — SessionStart hook: show the pink Overdrive banner to Velimir and
# remind Claude of the frame rules (output style `Overdrive`, ~/.claude/output-styles/).
#
# Prints ONE JSON object: `systemMessage` (shown to the user) + `additionalContext`
# (lands in Claude's context — keep it short, it costs tokens every session).
# Switches: OVERDRIVE_FLAIR=0 → no banner; NO_COLOR or OVERDRIVE_BANNER_COLOR=0 → no ANSI.
# Budget < 50 ms, pure bash 3.2, never fails the session (always exit 0).

ROOT="$HOME/.claude"
VER="?"; [ -f "$ROOT/VERSION" ] && IFS= read -r VER < "$ROOT/VERSION"
VER="${VER//[^0-9A-Za-z.+-]/}"; [ -n "$VER" ] || VER="?"  # semver chars only: VER goes into JSON unescaped

[ "${OVERDRIVE_FLAIR:-1}" = 0 ] && exit 0

COLOR=1
{ [ -n "${NO_COLOR:-}" ] || [ "${OVERDRIVE_BANNER_COLOR:-1}" = 0 ]; } && COLOR=0
# JSON-escaped ANSI (\u001b) so the escape survives the JSON round trip
c() { [ "$COLOR" = 1 ] && printf '\\u001b[38;2;%sm' "$1"; }
r() { [ "$COLOR" = 1 ] && printf '\\u001b[0m'; }
MAG="238;79;255"; CYA="0;255;247"; DIM="90;80;130"

quips=("[ jacking in... ]" "[ hack the planet ]" "[ there is no spoon ]" \
  "[ it's a unix system, I know this ]" "[ 0wning the build ]" "[ ping 127.0.0.1 — still here ]")
q="${quips[$(( $$ % ${#quips[@]} ))]}"

# art — the banner itself. Each line is one element; no backslashes or double quotes
# (they would need JSON escaping). Keep lines ≤ 60 chars.
art=(
  "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  "┃  ░▒▓█  ⏣  O V E R D R I V E  █▓▒░         ┃"
  "┃  ·  ·  jack in  ·  rig online  ·  ·       ┃"
  "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
)

msg="\\n"   # own line: the host prefixes the first line with "SessionStart:startup says:"
for line in "${art[@]}"; do msg="$msg$(c "$MAG")$line$(r)\\n"; done
msg="$msg$(c "$CYA")overdrive $VER$(r) $(c "$DIM")$q$(r)"

ctx="Overdrive output style is active: use the four FLAIR frames (skill start, skill finish, tool-result header, recap) in chat only; never in files, commits, PRs, Linear or RAG."

printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg" "$ctx"

# session log (SESSION-LOG.md contract): one INFO line, refuse a symlinked log path
sid=""
if [ ! -t 0 ]; then
  IFS= read -r -t 1 input || true
  [[ ${input:-} =~ \"session_id\":\ *\"([A-Za-z0-9._-]+)\" ]] && sid="${BASH_REMATCH[1]}"
fi
if [ "${OVERDRIVE_SESSION_LOG:-1}" != 0 ] && [ -n "$sid" ]; then
  dir="${OVERDRIVE_SESSION_LOG_DIR:-$ROOT/.local_ai_setup_logs/sessions}"
  log="$dir/$sid.log"
  { mkdir -p -m 700 "$dir" && [ ! -L "$log" ] && (umask 077
    ts=$(perl -MTime::HiRes=time -MPOSIX=strftime -e '$t=time; $z=strftime("%z",localtime $t); substr($z,3,0)=":"; printf "%s.%03d%s", strftime("%Y-%m-%dT%H:%M:%S",localtime $t), ($t-int $t)*1000, $z')
    printf '%s\tINFO\toverdrive-banner@%s\tpid=%s\tbanner shown\n' "$ts" "$VER" "$$" >> "$log"); } 2>/dev/null || true
fi
exit 0
