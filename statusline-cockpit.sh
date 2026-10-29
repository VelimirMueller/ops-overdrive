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
  G=(git -C "$cwd" -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false --no-optional-locks)
  br=$("${G[@]}" symbolic-ref --short -q HEAD 2>/dev/null | jq -Rr "$TXT_DEF txt")
  if [ -n "$br" ]; then
    dirty=$("${G[@]}" status --porcelain -uno 2>/dev/null | head -1)
    l1+="${sep}$(fg "$ACCENT_T")⎇ ${br}$R"; [ -n "$dirty" ] && l1+="$(fg "$WARN") ●$R"
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

printf '%s\n%s\n' "$l1" "$l2"
