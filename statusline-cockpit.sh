#!/bin/bash
# Claude Code status line — Ops Cockpit edition (added 2026-10-29).
# Shown when Claude runs in an Ops Cockpit pane (OPS_COCKPIT_PANE) or in cmux
# (CMUX_WORKSPACE_ID); statusline-command.sh hands over to this script.
# Palette = the cockpit's dark BrandPalette tokens (ops-cockpit
# Packages/CockpitCore/Sources/CockpitCore/Theme/BrandPalette.swift):
# page #0a0a0b, surface #121214, elevated #18181B, text #f4f4f5, sub #a1a1aa,
# faint #71717a, accent #6366F1, accentText #818CF8, status #10b981.
#
#   Line 1 — WHERE:  ◇ OPS COCKPIT > model > context bar % > dir > ⎇ branch
#   Line 3 — MCP:     code-context · rag-context · release-pilot · doc-creator · image-gen
#   Line 4 — TOOLS:   rig · tix · dual-review · rag-vault · rag-verify (versions)
#   Line 2 — CONTROL: claude auth (login / api key) > MCP mode (gateway / direct)
#                     > guardrails (deny · ask) > 5h / 7d limits
# Reads only small files; never ~/.claude.json (large, rewritten by Claude Code).

input=$(cat)
command -v jq >/dev/null 2>&1 || { printf 'ops cockpit · jq missing\n'; exit 0; }

R=$'\033[0m'
fg() { printf '\033[38;2;%sm' "$1"; }
bg() { printf '\033[48;2;%sm' "$1"; }
TEXT="244;244;245"; SUB="161;161;170"; FAINT="113;113;122"
ACCENT="99;102;241"; ACCENT_T="129;140;248"; OK="16;185;129"
WARN="228;181;103"; BAD="172;65;66"; ELEV="24;24;27"

# \x1f, not a tab: read collapses empty tab-separated fields and shifts the rest.
# Text fields lose control characters and backslashes; percentages are integers
# made by jq, so no payload text reaches $(( )) or a terminal escape.
# C0, DEL, C1 (CSI U+009B), backslash and bidi/format marks never reach the terminal.
TXT_DEF='def txt: tostring | explode | map(select(. >= 32 and . != 127 and . != 92 and (. < 128 or . > 159) and (. < 8206 or . > 8207) and (. < 8234 or . > 8238) and (. < 8294 or . > 8297))) | implode;'
IFS=$'\x1f' read -r model ctx cwd five seven < <(jq -r "$TXT_DEF"'
  def pct: if type == "number" then floor | tostring else "" end;
  [ (.model.display_name // .model.id // "claude" | txt),
    (.context_window.used_percentage | pct),
    (.workspace.current_dir // .cwd // "" | txt),
    (.rate_limits.five_hour.used_percentage | pct),
    (.rate_limits.seven_day.used_percentage | pct)
  ] | join("\u001f")' <<<"$input")

sep=" $(fg "$FAINT")│$R "
chip() { printf '%s%s %s %s' "$(bg "$1")" "$(fg "$2")" "$3" "$R"; }
pct_color() { local p=$1; [[ "$p" =~ ^[0-9]+$ ]] || { echo "$SUB"; return; }
  if [ "$p" -ge 85 ]; then echo "$BAD"; elif [ "$p" -ge 60 ]; then echo "$WARN"; else echo "$OK"; fi; }

# ---- line 1 ----
l1="$(chip "$ACCENT" "$TEXT" "◇ OPS COCKPIT")"
l1+=" $(fg "$TEXT")${model}$R"
if [[ "$ctx" =~ ^[0-9]+$ ]]; then
  p=$ctx; n=$(( p / 10 )); bar=""
  for ((i=0;i<10;i++)); do [ $i -lt $n ] && bar+="▰" || bar+="▱"; done
  l1+="${sep}$(fg "$(pct_color "$p")")${bar} ${p}%$R"
fi
if [ -n "$cwd" ]; then
  short=${cwd/#$HOME/\~}
  l1+="${sep}$(fg "$SUB")${short}$R"
  # Repo config must not run code: no fsmonitor, hooks or untracked cache.
  G=(git -C "$cwd" -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false
     -c core.attributesFile=/dev/null --no-optional-locks)
  br=$("${G[@]}" symbolic-ref --short -q HEAD 2>/dev/null | jq -Rr "$TXT_DEF txt")
  if [ -n "$br" ]; then
    l1+="${sep}$(fg "$ACCENT_T")⎇ ${br}$R"
    # `git status` can run a repo's own clean/process filter. Reading config runs
    # nothing, so a repo or worktree that defines a filter gets no dirty dot.
    # Global and system filters (git-lfs) are the user's own config: allowed.
    if "${G[@]}" config --show-scope --get-regexp '^filter\.' 2>/dev/null | grep -qE '^(local|worktree|command)'; then
      l1+="$(fg "$FAINT") ●?$R"
    else
      dirty=$("${G[@]}" status --porcelain -uno --ignore-submodules=all 2>/dev/null | head -1)
      [ -n "$dirty" ] && l1+="$(fg "$WARN") ●$R"
    fi
  fi
fi

# ---- line 2 ----
SUP="$HOME/Library/Application Support/OpsCockpit"
if [ -n "$ANTHROPIC_API_KEY" ]; then auth="$(fg "$WARN")⚿ api key$R"; else auth="$(fg "$OK")⚿ login$R"; fi
if [ -f "$SUP/cutover/state.json" ]; then
  mcp="$(fg "$OK")⬡ mcp gateway$R"
  if [ -f "$SUP/mcp-servers.json" ]; then
    k=$(jq '[.. | objects | select(has("enabled")) | select(.enabled == true)] | length' "$SUP/mcp-servers.json" 2>/dev/null)
    [ -n "$k" ] && mcp+="$(fg "$FAINT") · ${k} servers$R"
  fi
else
  mcp="$(fg "$SUB")⬡ mcp direct$R"
fi
rules="$SUP/interface-rules.json"
if [ -f "$rules" ]; then
  if d=$(jq '[.. | strings | select(. == "deny")] | length' "$rules" 2>/dev/null) &&
     a=$(jq '[.. | strings | select(. == "ask")] | length' "$rules" 2>/dev/null); then
    guard="$(fg "$ACCENT_T")⛨ guardrails$R $(fg "$BAD")${d} deny$R $(fg "$WARN")${a} ask$R"
  else
    guard="$(fg "$BAD")⛨ rules file broken · calls refused$R"
  fi
else
  guard="$(fg "$FAINT")⛨ no rules · allow all$R"
fi
l2="$(chip "$ELEV" "$SUB" "control")"
l2+=" ${auth}${sep}${mcp}${sep}${guard}"
lim=""
[ -n "$five" ] && lim+="$(fg "$(pct_color "$five")")5h ${five}%$R"
[ -n "$seven" ] && lim+="${lim:+ }$(fg "$(pct_color "$seven")")7d ${seven}%$R"
[ -n "$lim" ] && l2+="${sep}${lim}"

# ---- line 3 — MCP servers: up (●) / down (○) + version ----
# One `ps` snapshot, cached 10 s in its own file (the Neon cache is not written
# while only cockpit sessions run). Same process markers as statusline-command.sh.
CACHE="$HOME/.claude/.statusline-cache/cockpit-mcp.txt"
up=""
if [ -f "$CACHE" ] && [ $(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) )) -lt 10 ]; then
  read -r up < "$CACHE"
fi
if [ -z "$up" ]; then
  ps_all=$(ps -Ao args= 2>/dev/null)
  for marker in "vlm-code-context-mcp/dist/server" "rag_context.server" "release_pilot.server" \
                "doc_creator.server" "image_gen.server"; do
    case "$ps_all" in *"$marker"*) up+="1" ;; *) up+="0" ;; esac
  done
  mkdir -p "${CACHE%/*}" 2>/dev/null && printf '%s\n' "$up" > "$CACHE.$$" && mv -f "$CACHE.$$" "$CACHE"
fi
ver_of() { # $1 = file, $2 = key; first `key = "x"` (toml) or `"key": "x"` (json)
  [ -r "$1" ] || return 0
  sed -n -E "s/^[[:space:]]*\"?$2\"?[[:space:]]*[:=][[:space:]]*\"([^\"]+)\".*/\1/p" "$1" | head -1
}
MCP_DIR="$HOME/Desktop/Workspace/mcp-servers"
# Bash arrays and ${var:i:1} are fine: the file is #!/bin/bash and
# statusline-command.sh starts it with `exec bash`. macOS only (stat -f %m).
names=(code-context rag-context release-pilot doc-creator image-gen)
vers=("$(ver_of "$MCP_DIR/vlm-code-context/node_modules/vlm-code-context-mcp/package.json" version)"
      "$(ver_of "$MCP_DIR/vlm-rag-context/pyproject.toml" version)"
      "$(ver_of "$MCP_DIR/vlm-release-pilot/pyproject.toml" version)"
      "$(ver_of "$MCP_DIR/vlm-doc-creator/pyproject.toml" version)"
      "$(ver_of "$MCP_DIR/vlm-image-gen/pyproject.toml" version)")
l3="$(chip "$ELEV" "$SUB" "mcp    ")"
for i in 0 1 2 3 4; do
  [ "$i" -gt 0 ] && l3+="$(fg "$FAINT") ·$R"
  if [ "${up:$i:1}" = 1 ]; then l3+=" $(fg "$OK")●$R"; else l3+=" $(fg "$FAINT")○$R"; fi
  l3+=" $(fg "$TEXT")${names[$i]}$R"; [ -n "${vers[$i]}" ] && l3+=" $(fg "$FAINT")${vers[$i]}$R"
done

# ---- line 4 — local CLIs: version, amber = pre-1.0, red ○ = missing ----
T="$HOME/.claude/tools"
tool() { # $1 = label, $2 = version
  if [ -z "$2" ]; then printf ' %s%s ○%s' "$(fg "$BAD")" "$1" "$R"
  elif [ "${2%%.*}" = 0 ]; then printf ' %s%s %s%s%s' "$(fg "$TEXT")" "$1" "$(fg "$WARN")" "$2" "$R"
  else printf ' %s%s %s%s%s' "$(fg "$TEXT")" "$1" "$(fg "$ACCENT_T")" "$2" "$R"; fi
}
rig_v=""; [ -r "$T/rig/VERSION" ] && read -r rig_v < "$T/rig/VERSION"
vault_v=""; [ -r "$T/rag-vault/VERSION" ] && read -r vault_v < "$T/rag-vault/VERSION"
verify_v=$(sed -n -E 's/.*SLOG_VERSION=\"?([0-9][^\" ;]*).*/\1/p' "$T/rag-verify/rag-verify.sh" 2>/dev/null | head -1)
dr_v=$(sed -n -E 's/^VERSION=\"?([0-9][^\" ;]*).*/\1/p' "$T/dual-review/dual-review.sh" 2>/dev/null | head -1)
tix_v=$(ver_of "$HOME/Desktop/Workspace/dev/personal/tix/package.json" version)
l4="$(chip "$ELEV" "$SUB" "tools  ")"
l4+="$(tool "⚙ rig" "$rig_v")$(fg "$FAINT") ·$R$(tool "⬢ tix" "$tix_v")$(fg "$FAINT") ·$R$(tool "⚖ dual-review" "$dr_v")"
l4+="$(fg "$FAINT") ·$R$(tool "⛁ rag-vault" "$vault_v")$(fg "$FAINT") ·$R$(tool "✓ rag-verify" "$verify_v")"

printf '%s\n%s\n%s\n%s\n' "$l1" "$l2" "$l3" "$l4"
