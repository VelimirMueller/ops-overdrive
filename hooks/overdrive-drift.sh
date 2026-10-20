#!/bin/bash
# overdrive-drift — SessionStart hook: has a pinned component moved since the last
# snapshot? If so, record it with `overdrive snapshot --if-drift` in the BACKGROUND.
#
# Budget: < 150 ms, prints nothing (SessionStart stdout would land in Claude's context).
# Cheap on purpose — pure bash reads, no git/jq/--version forks on the happy path:
#   * git rows   HEAD SHA from .git/HEAD → refs/… or packed-refs ("+dirty" is ignored:
#                that needs `git status`, the full snapshot sees it)
#   * pkg rows   pyproject.toml / package.json version of each vlm-* MCP server
#   * bin rows   tix, dual-review, relpilot, rig from their version files, not `--version`
#   * NOT checked: ollama models, claude/ollama binaries (too slow — the snapshot has them)
# Order and format follow gen_lock() in ~/.claude/tools/overdrive/overdrive; keep in step.
#
# `--check` prints the drifting rows and exits 1 on drift, 0 when clean (for testing).
# Bash 3.2 compatible (/bin/bash on macOS): no associative arrays, no mapfile.

ROOT="$HOME/.claude"
LOCK="${OVERDRIVE_LOCK:-$ROOT/overdrive.lock}"   # override: tests only
MCP_DIR="$HOME/Desktop/Workspace/mcp-servers"
OVERDRIVE="${OVERDRIVE_BIN:-$ROOT/tools/overdrive/overdrive}"   # override: tests only
CHECK=0; [ "${1:-}" = --check ] && CHECK=1

[ -f "$LOCK" ] || exit 0

head_sha() { # $1 = repo dir → first 10 hex of HEAD, or nothing
  local g="$1/.git" h ref sha r
  [ -f "$g/HEAD" ] || return 0
  IFS= read -r h < "$g/HEAD" || true
  if [ "${h#ref: }" != "$h" ]; then
    ref="${h#ref: }"
    if [ -f "$g/$ref" ]; then
      IFS= read -r h < "$g/$ref" || true
    else
      h=""
      if [ -f "$g/packed-refs" ]; then
        while read -r sha r; do [ "$r" = "$ref" ] && { h="$sha"; break; }; done < "$g/packed-refs"
      fi
    fi
  fi
  [ -n "$h" ] && printf '%s' "${h:0:10}"
}

first_match() { # $1 = file, $2 = regex with one group → first group of the first match
  local l
  [ -f "$1" ] || return 0
  while IFS= read -r l; do
    if [[ $l =~ $2 ]]; then printf '%s' "${BASH_REMATCH[1]}"; return 0; fi
  done < "$1"
}
RE_PY='^version *= *"([^"]*)"'
RE_NPM='"version": *"([^"]*)"'
RE_SH='^VERSION="([^"]*)"'

# the cheap view of the world, one "name kind pin" row per line
now=""
add() { now="$now$1 $2 $3"$'\n'; }
# ~/Desktop/RAG is pinned in the lock but NOT watched here: every rag-vault commit moves its
# SHA, and that produced 9 of 11 "auto: component drift" commits (2026-10-19). The weekly
# snapshot still pins it.
for d in "$ROOT/tools/rig" "$ROOT/tools/dual-review" "$ROOT/tools/rag-vault" \
         "${OVERDRIVE_SRC:-$HOME/Desktop/Workspace/dev/personal/overdrive}" "$MCP_DIR" "$MCP_DIR"/vlm-*; do
  [ -d "$d/.git" ] || continue
  sha=$(head_sha "$d"); add "~${d#"$HOME"}" git "${sha:-no-commits}"
done
for d in "$MCP_DIR"/vlm-*; do
  v=""
  if [ -f "$d/pyproject.toml" ]; then v=$(first_match "$d/pyproject.toml" "$RE_PY")
  elif [ -f "$d/node_modules/vlm-code-context-mcp/package.json" ]; then
    v=$(first_match "$d/node_modules/vlm-code-context-mcp/package.json" "$RE_NPM"); fi
  [ -n "$v" ] && add "${d##*/}" pkg "$v"
done
for bin in tix dual-review relpilot rig; do
  command -v "$bin" >/dev/null 2>&1 || continue
  case "$bin" in
    tix)         v=$(first_match "$HOME/Desktop/Workspace/dev/personal/tix/package.json" "$RE_NPM") ;;
    dual-review) v=$(first_match "$ROOT/tools/dual-review/dual-review.sh" "$RE_SH") ;;
    relpilot)    v=$(first_match "$MCP_DIR/vlm-release-pilot/pyproject.toml" "$RE_PY") ;;
    rig)         v=""; [ -f "$ROOT/tools/rig/VERSION" ] && IFS= read -r v < "$ROOT/tools/rig/VERSION" ;;
  esac
  add "$bin" bin "${v:-present}"
done

# the same rows from the lock (dirty flag dropped, only the bins checked above)
pinned=""
while read -r name kind pin _; do
  case "$name" in ''|\#*|'~/Desktop/RAG') continue ;; esac
  case "$kind" in
    git) pinned="$pinned$name git ${pin%+dirty}"$'\n' ;;
    pkg) pinned="$pinned$name pkg $pin"$'\n' ;;
    bin) case "$name" in tix|dual-review|relpilot|rig) pinned="$pinned$name bin $pin"$'\n' ;; esac ;;
  esac
done < "$LOCK"

[ "$now" = "$pinned" ] && exit 0

if [ "$CHECK" = 1 ]; then
  diff <(printf '%s' "$pinned") <(printf '%s' "$now") | grep '^[<>]'
  exit 1
fi

# drift: hand the real work to overdrive in the background, fully detached, silent here.
# Its own lines (and the commit) go to the session log via overdrive's slog/flair_done.
sid=""
if [ ! -t 0 ]; then
  IFS= read -r -t 1 input || true
  [[ ${input:-} =~ \"session_id\":\ *\"([A-Za-z0-9._-]+)\" ]] && sid="${BASH_REMATCH[1]}"
fi
[ -x "$OVERDRIVE" ] || exit 0
CLAUDE_CODE_SESSION_ID="${sid:-${CLAUDE_CODE_SESSION_ID:-}}" OVERDRIVE_FLAIR=0 \
  nohup "$OVERDRIVE" snapshot --if-drift "auto: component drift" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
