#!/bin/bash
# Claude Code status line — Neon Overdrive powerline edition
# Reads the session JSON payload from stdin and prints a 5-line status.
# Palette matches the Warp "Neon Overdrive" theme (~/.warp/themes/neon_overdrive2.yaml).
#
# Segment map (regrouped 2026-09-03; per-line width target ≤ ~115 columns):
#   Line 1 — WHERE:   ✦ model > context bar+% > ⛭ agents (only when > 0)
#                     > dir (fish-style abbreviated) > Δ lines > ◆ effort
#   Line 2 — WORK:    ⌂ worktree > ⎇ branch ✚dirty ⇡⇣ > PR state
#                     > ⚖ dual-review gate > ⬢ tix (ticket · phase · queue size)
#   Line 3 — SESSION: ⇅ in/out > per-model usage (non-zero only) > ⏱ duration
#                     > 5h/7d limits + ↻ reset
#   Line 4 — KNOWLEDGE: ● code-context (version) > dashboard :3333
#                       > ● rag-context (version) > ⚡ ollama + loaded model
#                       > ⏣ overdrive (setup version, ~/.claude/VERSION)
#   Line 5 — CREATE:  ● doc-creator (version) + ✎ its model · ● release-pilot
#                     (no model chip — it shares doc-creator's writer)
#                     > ● image-gen (version) + ◈ its model
#   Line 6 — TOOLS:   ⚙ rig · ⬢ tix · ⚖ dual-review · ⛁ rag-vault · ✓ rag-verify (versions;
#                     yellow = pre-1.0) — added 2026-10-09
#
# Lines 4+5 restored 2026-09-03 (they had been folded into a single "⬡ 6/6 rig"
# count for one afternoon). Every MCP server and local AI tool is named with its
# installed version again — but paid for differently than in the 5-line era: the
# four process checks share ONE `ps` snapshot, the version/model strings are read
# with fork-free bash loops (toml_val/json_val, not sed), and the whole probe —
# ollama's /api/ps model read included — sits behind the 10 s rig cache.
#
# Still deliberately dropped (see `neon-rig` skill / RAG system/claude-statusline.md):
#   · the `cc <version>` chip
#   · zero-valued chips (⛭ agents:0, in:0 out:0, fable:0 opus:0 sonnet:0)
#   · the ✎ output-style chip (✎ is doc-creator's model marker again)
#   · the 🎫 emoji (double-width, off-palette) → monochrome ⬢
#
# Perf contract: the old version spawned ~70 processes (~0.87 s/render). This one
# batches the payload into ONE jq call, gets branch+upstream+ahead/behind+dirty
# from ONE `git status --porcelain=v2 --branch`, replaces 4x pgrep with ONE `ps`
# snapshot, formats numbers/durations in pure bash, and caches the rig probe and
# the dual-review chip under ~/.claude/.statusline-cache.

# Ops Cockpit panes and cmux get the cockpit status line (2026-10-29); Warp keeps
# Neon Overdrive. STATUSLINE_STYLE=neon|cockpit forces one style.
case "${STATUSLINE_STYLE:-}" in
  cockpit) exec bash "$HOME/.claude/statusline-cockpit.sh" ;;
  neon) ;;
  *) if [ -n "${OPS_COCKPIT_PANE:-}" ] || [ -n "${CMUX_WORKSPACE_ID:-}" ]; then
       exec bash "$HOME/.claude/statusline-cockpit.sh"
     fi ;;
esac

input=$(cat)

# jq is required for parsing the JSON payload and transcripts. Fail
# gracefully with a helpful hint instead of a broken/empty status line.
if ! command -v jq >/dev/null 2>&1; then
  printf "%b\n" "\033[2;31mstatusline: jq not found — install it (e.g. brew install jq) for the full status line\033[0m"
  exit 0
fi

NOW=$(date +%s)   # single date(1) spawn, reused everywhere below
CACHE_DIR="$HOME/.claude/.statusline-cache"

# ---------- Neon Overdrive palette ----------
RESET='\033[0m'

# powerline segment colors as "R;G;B" (bg/fg pairs assembled per segment)
C_DARK="7;5;20"         # theme background — text on bright segments
C_ACCENT="238;79;255"   # vivid magenta accent
C_PANEL="18;14;40"      # panel shade A (darkened 2026-09-03 so the chevron
C_PANEL2="50;40;104"    # panel shade B   between two panel chips is visible)
C_TEXT="216;232;255"    # theme foreground
C_GREEN="5;255;161"
C_YELLOW="240;255;25"
C_RED="255;42;109"
C_MAGENTA="238;79;255"
C_CYAN="0;255;247"
C_BLUE="143;125;255"
C_GRAY="90;80;130"

# U+E0B0 powerline chevron via printf (bash 3.2 has no $'\u...' escapes)
PL_SEP=$(printf '\xee\x82\xb0')

pl_line=""
prev_bg=""
pl_new() { pl_line=""; prev_bg=""; }
pl_add() { # $1 = bg "R;G;B", $2 = fg "R;G;B", $3 = text
  if [ -n "$prev_bg" ]; then
    pl_line="${pl_line}\033[48;2;$1m\033[38;2;${prev_bg}m${PL_SEP}"
  fi
  # The lines go out through printf %b: a backslash or control character in
  # chip text (tool output, git, payload) must not become an escape sequence.
  local t=${3//\\/}; t=${t//[[:cntrl:]]/}
  pl_line="${pl_line}\033[48;2;$1m\033[38;2;$2m $t "
  prev_bg="$1"
}
pl_end() {
  [ -n "$prev_bg" ] && pl_line="${pl_line}${RESET}\033[38;2;${prev_bg}m${PL_SEP}${RESET}"
}
# alternate between the two panel shades so adjacent flags never share a bg
# (a chevron between same-colored segments would be invisible)
pl_alt() { [ "$prev_bg" = "$C_PANEL" ] && echo "$C_PANEL2" || echo "$C_PANEL"; }

# ---------- pure-bash formatters (no awk/sed spawns) ----------
fmt_num() { # 1234567 -> 1.2M · 48000 -> 48k · 512 -> 512
  local n=${1:-0}
  [ "$n" -ge 1000000 ] 2>/dev/null && { printf '%d.%dM' $((n/1000000)) $(((n%1000000)/100000)); return; }
  [ "$n" -ge 1000 ] 2>/dev/null && { printf '%dk' $((n/1000)); return; }
  printf '%d' "$n"
}

fmt_dur() { # ms -> 3h12m / 42m / 18s
  local s=$(( ${1:-0} / 1000 ))
  [ "$s" -ge 3600 ] && { printf '%dh%02dm' $((s/3600)) $(((s%3600)/60)); return; }
  [ "$s" -ge 60 ] && { printf '%dm' $((s/60)); return; }
  printf '%ds' "$s"
}

hash_str() { # any string -> 8 hex chars. FNV-1a 32-bit in pure bash builtins.
  # ~305 us/call and NO fork: `shasum` is a Perl script (15.8 ms) and even
  # cksum/md5 cost ~6 ms, which is real money against a ~120 ms render budget.
  local s="$1" h=2166136261 i c
  for ((i = 0; i < ${#s}; i++)); do
    printf -v c '%d' "'${s:i:1}"
    h=$(( (h ^ c) * 16777619 & 0xFFFFFFFF ))
  done
  printf '%08x' "$h"
}

round_int() { # "37.4" -> 37 ; "" -> empty
  [ -z "$1" ] && return
  printf '%.0f' "$1" 2>/dev/null
}

# ---------- fork-free config readers (MCP versions / local model names) ----------
# The 5-line version shelled out to `sed` once per file (6 forks, ~60 ms). These
# are bash `read` loops over small files: no fork at all. Both take the target
# VARIABLE NAME first and assign with `printf -v`, so they cost no command
# substitution either (a `$(...)` around a function still forks a subshell).
toml_val() { # $1 = varname, $2 = file, $3 = key -> first `key = "value"` line
  local __v="" __l
  if [ -r "$2" ]; then
    while IFS= read -r __l || [ -n "$__l" ]; do
      case "$__l" in
        # the space before `=` is what keeps `model` from matching `model_repo`
        "$3 = \""*) __l="${__l#*\"}"; __v="${__l%%\"*}"; break ;;
      esac
    done < "$2"
  fi
  printf -v "$1" '%s' "$__v"
}
json_val() { # $1 = varname, $2 = file, $3 = key -> first `"key": "value"`
  local __v="" __l
  if [ -r "$2" ]; then
    while IFS= read -r __l || [ -n "$__l" ]; do
      case "$__l" in
        *"\"$3\":"*) __l="${__l#*\"$3\":}"; __l="${__l#*\"}"; __v="${__l%%\"*}"; break ;;
      esac
    done < "$2"
  fi
  printf -v "$1" '%s' "$__v"
}
sh_val() { # $1 = varname, $2 = shell script, $3 = key -> first `KEY="value"` / `KEY=value`
  # Matches the key at line start or after a space/`;` (rag-verify sets
  # `SLOG_TOOL=… SLOG_VERSION=1.1.0` on one line). Stops at quote, space or `;`.
  local __v="" __l
  if [ -r "$2" ]; then
    while IFS= read -r __l || [ -n "$__l" ]; do
      case "$__l" in
        "$3="*|*" $3="*|*";$3="*)
          __l="${__l#*$3=}"; __l="${__l#\"}"; __v="${__l%%[\" ;]*}"; break ;;
      esac
    done < "$2"
  fi
  printf -v "$1" '%s' "$__v"
}

# ---------- Payload: ONE jq call for every field ----------
# Fields are joined with U+001F (unit separator) rather than a tab: bash `read`
# collapses runs of *whitespace* IFS characters, which would silently shift every
# field after an empty one. A non-whitespace IFS preserves empty fields.
US=$(printf '\x1f')
# The payload is untrusted text. `txt` drops C0/C1 controls, DEL, backslash
# (the lines are printed with %b) and bidi overrides. `num` lets only JSON
# numbers through, because those fields reach $(( )), where bash would run
# a command substitution hidden in a string. `ts` allows epoch or ISO-8601.
TXT_DEF='def txt: tostring | explode | map(select(. >= 32 and . != 127 and . != 92 and (. < 128 or . > 159) and (. < 8206 or . > 8207) and (. < 8234 or . > 8238) and (. < 8294 or . > 8297))) | implode;'
payload=$(printf '%s' "$input" | jq -r "$TXT_DEF"'
  def num: if type == "number" then tostring else "" end;
  def ts: if type == "number" then tostring
          elif type == "string" and test("^[0-9][0-9T:.Z+-]*$") then . else "" end;
  [ (.model.display_name // .model.id // "?" | txt),
    (.workspace.current_dir // .cwd // "." | txt),
    (.transcript_path // "" | txt),
    (.context_window.used_percentage | num),
    (.context_window.context_window_size | num),
    (.context_window.total_input_tokens | num),
    (.cost.total_lines_added | num),
    (.cost.total_lines_removed | num),
    (.cost.total_duration_ms | num),
    (.effort.level // "" | txt),
    (.rate_limits.five_hour.used_percentage | num),
    (.rate_limits.seven_day.used_percentage | num),
    (.rate_limits.five_hour.resets_at // .rate_limits.seven_day.resets_at | ts),
    (.workspace.git_worktree // "" | txt),
    (.pr.number | num),
    (.pr.review_state // "" | txt),
    (.rate_limits.five_hour.resets_at | ts),
    (.rate_limits.seven_day.resets_at | ts)
  ] | join("\u001f")' 2>/dev/null)

IFS="$US" read -r model cwd transcript used_pct cw_size cw_in ladd ldel \
  dur_ms effort five week reset_at worktree pr_num pr_state reset_5h reset_7d <<< "$payload"

# jq's own `// "?"` fallbacks only fire on valid JSON; if the payload is
# unparseable jq exits non-zero and $payload is empty, so backstop here too.
[ -z "$cwd" ] && cwd="."
[ -z "$model" ] && model="?"
# "Opus 5 (1M)" -> "Opus 5" — the context bar already reports the window
model="${model%% (*}"

# ================= LINE 1 — WHERE =================

# --- directory, fish-style: every component but the last collapses to one letter ---
dir_display="${cwd/#$HOME/\~}"
if [ "${#dir_display}" -gt 28 ]; then
  IFS='/' read -ra _parts <<< "$dir_display"
  _last=$(( ${#_parts[@]} - 1 )); _abbr=""
  for ((_i = 0; _i < _last; _i++)); do
    _p="${_parts[_i]}"
    if [ -z "$_p" ] || [ "$_p" = "~" ]; then _abbr="${_abbr}${_p}/"; else _abbr="${_abbr}${_p:0:1}/"; fi
  done
  dir_display="${_abbr}${_parts[_last]}"
fi

# --- context window usage: [bar] x% ---
[ -z "$used_pct" ] && [ -n "$cw_size" ] && [ -n "$cw_in" ] && [ "$cw_size" != "0" ] && \
  used_pct=$(( cw_in * 100 / cw_size ))
ctx_txt=""; ctx_rgb="$C_GREEN"
if [ -n "$used_pct" ]; then
  pct_int=$(round_int "$used_pct"); : "${pct_int:=0}"
  bar_len=10
  filled=$(( pct_int * bar_len / 100 )); [ "$filled" -gt "$bar_len" ] && filled=$bar_len
  [ "$filled" -lt 0 ] && filled=0
  if   [ "$pct_int" -ge 80 ]; then ctx_rgb="$C_RED"
  elif [ "$pct_int" -ge 50 ]; then ctx_rgb="$C_YELLOW"
  fi
  bar=""; for ((_i = 0; _i < filled; _i++)); do bar="${bar}█"; done
  for ((_i = filled; _i < bar_len; _i++)); do bar="${bar}░"; done
  ctx_txt="${bar} ${pct_int}%"
fi

# --- subagents currently running in parallel ---
# Best-effort count from the transcript (the statusline JSON exposes no agent
# count as of CC 2.1.218). Two launch modes, two completion signals:
#   sync agents:  the Agent tool_use stays without a real tool_result until done
#   background:   an immediate "Async agent launched successfully" tool_result,
#                 then a <task-notification> entry with the tool-use-id on finish
# Tool name is "Agent" since CC 2.1.63 ("Task" kept for old transcripts).
# Known miss: an agent resumed via SendMessage after notifying counts as done.
agents=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  a=$(jq -rRn '
    [inputs | fromjson?] as $entries
    | ([ $entries[] | select(.message.content != null) | .message.content[]?
        | select(.type=="tool_use" and (.name=="Agent" or .name=="Task")) | .id ]) as $launched
    | ([ $entries[] | select(.message.content != null) | .message.content[]?
        | select(.type=="tool_result")
        | select(
            ([.content] | flatten | map(if type=="object" then (.text // "") else tostring end) | join(" "))
            | startswith("Async agent launched") | not)
        | .tool_use_id ]) as $sync_done
    | ([ $entries[] | tostring | scan("<tool-use-id>([^<]+)</tool-use-id>") ] | flatten) as $notified
    | (($launched - $sync_done) - $notified) | length
  ' "$transcript" 2>/dev/null)
  [ -n "$a" ] && [ "$a" -ge 0 ] 2>/dev/null && agents="$a"
fi

# --- lines added/removed this session ---
lines_str=""
{ [ -n "$ladd" ] || [ -n "$ldel" ]; } && lines_str="+${ladd:-0} -${ldel:-0}"

pl_new
pl_add "$C_ACCENT" "$C_DARK" "✦ ${model}"
[ -n "$ctx_txt" ] && pl_add "$(pl_alt)" "$ctx_rgb" "$ctx_txt"
# agents chip appears ONLY while agents are actually running (was ⛭ agents:0 always)
[ "$agents" -gt 0 ] 2>/dev/null && pl_add "$C_ACCENT" "$C_DARK" "⛭ ${agents}"
pl_add "$(pl_alt)" "$C_CYAN" "${dir_display}"
[ -n "$lines_str" ] && pl_add "$(pl_alt)" "$C_CYAN" "Δ ${lines_str}"
if [ -n "$effort" ]; then
  case "$effort" in
    max)    eff_rgb="$C_RED" ;;
    xhigh)  eff_rgb="$C_MAGENTA" ;;
    high)   eff_rgb="$C_CYAN" ;;
    medium) eff_rgb="$C_BLUE" ;;
    *)      eff_rgb="$C_GRAY" ;;
  esac
  pl_add "$(pl_alt)" "$eff_rgb" "◆ ${effort}"
fi
pl_end
line1="$pl_line"

# ================= LINE 2 — WORK =================

# --- git: ONE porcelain=v2 call yields branch, upstream, ahead/behind and dirty ---
# (the old version needed rev-parse + branch --show-current + rev-parse --short
#  + status --porcelain + rev-list, five spawns, plus a grep -c to count)
git_branch=""; git_dirty=0; git_ahead=0; git_behind=0; git_skip=""
# `git status` can run a repo's own clean/process filters when it re-hashes a
# file. Reading config runs nothing, so a repo (or worktree) that defines a
# filter gets the branch only, from symbolic-ref, and no dirty count.
# Global and system filters (git-lfs) are the user's own config, not the repo's,
# so they stay allowed: a repo cannot write them.
if [ -d "$cwd" ] && git -C "$cwd" config --show-scope --get-regexp '^filter\.' 2>/dev/null \
     | grep -qE '^(local|worktree|command)'; then
  git_skip=1
  if ! git_branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null); then
    git_oid=$(git -C "$cwd" rev-parse -q --verify HEAD 2>/dev/null) && git_branch="(detached)"
  fi
elif [ -d "$cwd" ]; then
  while IFS= read -r _l; do
    case "$_l" in
      '# branch.head '*)  git_branch="${_l#\# branch.head }" ;;
      '# branch.oid '*)   git_oid="${_l#\# branch.oid }" ;;
      '# branch.ab '*)    _ab="${_l#\# branch.ab }"
                          git_ahead="${_ab%% *}"; git_ahead="${git_ahead#+}"
                          git_behind="${_ab##* }"; git_behind="${git_behind#-}" ;;
      '#'*)               ;;
      '')                 ;;
      *)                  git_dirty=$((git_dirty + 1)) ;;
    esac
  # The repo is not trusted: its config must not start fsmonitor or hook code.
  done < <(git -C "$cwd" -c core.fsmonitor=false -c core.hooksPath=/dev/null \
             -c core.untrackedCache=false -c core.attributesFile=/dev/null \
             --no-optional-locks status --porcelain=v2 --branch \
             --ignore-submodules=all 2>/dev/null)
fi
if [ -d "$cwd" ]; then
  # detached HEAD reports "(detached)" as branch.head — show the short sha instead
  [ "$git_branch" = "(detached)" ] && git_branch="${git_oid:0:7}"
  # A branch name may hold bidi or control characters: same filter as the payload.
  [ -n "$git_branch" ] && git_branch=$(printf '%s' "$git_branch" | jq -Rr "$TXT_DEF txt" 2>/dev/null)
fi

pl_new
# leaf only: the ".worktrees/" prefix is constant, and `tix branch
# --worktree` always names the dir after the ticket
[ -n "$worktree" ] && pl_add "$(pl_alt)" "$C_BLUE" "⌂ ${worktree##*/}"
if [ -n "$git_branch" ]; then
  br="$git_branch"; [ "${#br}" -gt 24 ] && br="${br:0:23}…"
  git_txt="⎇ ${br}"
  [ "${git_dirty:-0}" -gt 0 ] 2>/dev/null && git_txt="${git_txt} ✚${git_dirty}"
  [ -n "$git_skip" ] && git_txt="${git_txt} ✚?"
  [ "${git_ahead:-0}" -gt 0 ] 2>/dev/null && git_txt="${git_txt} ⇡${git_ahead}"
  [ "${git_behind:-0}" -gt 0 ] 2>/dev/null && git_txt="${git_txt} ⇣${git_behind}"
  if [ "${git_dirty:-0}" -gt 0 ] 2>/dev/null; then
    pl_add "$(pl_alt)" "$C_YELLOW" "$git_txt"
  else
    pl_add "$(pl_alt)" "$C_GREEN" "$git_txt"
  fi
fi
if [ -n "$pr_num" ]; then
  case "$pr_state" in
    approved)          pr_rgb="$C_GREEN" ;;
    changes_requested) pr_rgb="$C_RED" ;;
    draft)             pr_rgb="$C_GRAY" ;;
    *)                 pr_rgb="$C_YELLOW" ;;
  esac
  pr_label="PR #${pr_num}"; [ -n "$pr_state" ] && pr_label="${pr_label} ${pr_state}"
  pl_add "$(pl_alt)" "$pr_rgb" "$pr_label"
fi

# --- dual-review: DeepSeek + GLM, both REQUIRED reviewers ---
# The tool computes the level itself ("LEVEL<TAB>TEXT") so CLI, hook and
# statusline can never disagree. Keys live in ~/.config/rig/keys.env; values are
# never printed. Levels: nokeys (red — the lead still owes the keys) · pass
# (green) · fail (red, "ds✗2" = blockers+majors) · blocked (yellow, a reviewer
# errored) · stale (tree changed since the review) · none (no review here).
# Cached for 5 s (per checkout) — it is the single slowest probe at ~230 ms, and
# the *gate* is enforced by the PreToolUse hook, not by this chip. Worst case the
# chip lags a fresh verdict by 5 s; it can never let something ship unreviewed.
DR_BIN="$HOME/.claude/tools/dual-review/dual-review.sh"
DR_TTL=5
dr_out=""
if [ -x "$DR_BIN" ]; then
  # Key by a hash of the checkout — dual-review keys its own cache the same way
  # (it uses `shasum -a 1 | cut -c1-12` on the repo root). The first cut at this
  # used the path with "/" -> "_" truncated to its last 60 chars, which was both
  # ugly (dr_elimir.mueller_Desktop_...) and WRONG: two checkouts sharing their
  # last 60 characters would share a cache entry, i.e. one worktree could display
  # another's review verdict. hash_str is exact and costs no fork.
  _dr_key=$(hash_str "$cwd")
  mkdir -p "$CACHE_DIR/chip" 2>/dev/null
  _dr_cache="$CACHE_DIR/chip/dr-${_dr_key}.txt"
  if [ -f "$_dr_cache" ]; then
    _dr_mt=$(stat -f %m "$_dr_cache" 2>/dev/null || echo 0)
    [ $(( NOW - _dr_mt )) -lt "$DR_TTL" ] 2>/dev/null && IFS= read -r dr_out < "$_dr_cache"
  fi
  if [ -z "$dr_out" ]; then
    dr_out=$(cd "$cwd" 2>/dev/null && "$DR_BIN" --chip 2>/dev/null)
    if [ -n "$dr_out" ]; then
      mkdir -p "$CACHE_DIR" 2>/dev/null
      _dr_tmp="$_dr_cache.$$"
      printf '%s\n' "$dr_out" > "$_dr_tmp" 2>/dev/null && mv -f "$_dr_tmp" "$_dr_cache" 2>/dev/null
      rm -f "$_dr_tmp" 2>/dev/null
    fi
  fi
  TAB=$(printf '\t')
  dr_level="${dr_out%%${TAB}*}"; dr_text="${dr_out#*${TAB}}"
  case "$dr_level" in
    nokeys)       pl_add "$C_RED" "$C_DARK" "$dr_text" ;;
    pass)         pl_add "$C_GREEN" "$C_DARK" "$dr_text" ;;
    fail)         pl_add "$C_RED" "$C_DARK" "$dr_text" ;;
    blocked)      pl_add "$C_YELLOW" "$C_DARK" "$dr_text" ;;
    stale)        pl_add "$C_PANEL" "$C_YELLOW" "$dr_text" ;;
    partial)      pl_add "$C_PANEL" "$C_YELLOW" "$dr_text" ;;   # PASS on --staged/--range/truncated: gate refuses it
    none|notrepo) pl_add "$C_PANEL" "$C_GRAY" "$dr_text" ;;
    *)            pl_add "$C_PANEL" "$C_GRAY" "⚖ review ?" ;;
  esac
else
  pl_add "$C_PANEL" "$C_RED" "⚖ dual-review tool missing"
fi

# --- tix: Linear-ticket CLI + the Claude pipeline ---
# `tix chip` prints "LEVEL<TAB>TEXT" from a 60 s queue cache + the local phase
# file (never blocks on network): active ticket from the branch name, its state,
# the pipeline phase (spec ▸ plan ▸ build ▸ review ▸ ship) with the model that ran
# it, and the "mine N (…)" queue. nokey = red until LINEAR_API_KEY lands in
# ~/.config/rig/keys.env. Details: `pipeline` + `linear-ticket` skills.
# Two display edits applied here so `tix` itself stays untouched:
#   · 🎫 -> ⬢   (the emoji was double-width and off-palette in a line-art strip)
#   · the "(todo 1 · doing 3 · review 5 · backlog 3)" breakdown is dropped —
#     nested parens inside a chip were the widest thing on the old line 5
TIX_BIN=$(command -v tix 2>/dev/null); [ -z "$TIX_BIN" ] && [ -x "$HOME/.bun/bin/tix" ] && TIX_BIN="$HOME/.bun/bin/tix"
if [ -n "$TIX_BIN" ]; then
  tix_out=$(cd "$cwd" 2>/dev/null && "$TIX_BIN" chip 2>/dev/null)
  TAB=$(printf '\t')
  tix_level="${tix_out%%${TAB}*}"; tix_text="${tix_out#*${TAB}}"
  [ -z "$tix_out" ] && { tix_level="error"; tix_text="⬢ tix ?"; }
  tix_text="${tix_text/🎫/⬢}"
  [[ "$tix_text" =~ ^(.*)\ \(todo.*\)$ ]] && tix_text="${BASH_REMATCH[1]}"
  case "$tix_level" in
    nokey)      pl_add "$C_RED" "$C_DARK" "$tix_text" ;;
    ok|notrepo) pl_add "$(pl_alt)" "$C_CYAN" "$tix_text" ;;
    stale)      pl_add "$(pl_alt)" "$C_GRAY" "$tix_text" ;;
    warn)       pl_add "$(pl_alt)" "$C_YELLOW" "$tix_text" ;;
    *)          pl_add "$(pl_alt)" "$C_RED" "$tix_text" ;;
  esac
else
  pl_add "$(pl_alt)" "$C_RED" "⬢ tix missing → tix/install.sh"
fi
pl_end
line2="$pl_line"

# ================= LINE 3 — SESSION =================

# --- current-session tokens + per-model usage (main transcript + its subagents) ---
sess_in=0; sess_out=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  SESS_FILES=("$transcript")
  sess_subdir="${transcript%.jsonl}/subagents"
  if [ -d "$sess_subdir" ]; then
    while IFS= read -r -d '' f; do SESS_FILES+=("$f"); done < <(find "$sess_subdir" -name '*.jsonl' -print0 2>/dev/null)
  fi
  sess_stats=$(cat "${SESS_FILES[@]}" 2>/dev/null | jq -rRn '
    [inputs | fromjson? | select(.message.usage != null)]
    | reduce .[] as $x ({i:0,o:0,bm:{}};
        .i += (($x.message.usage.input_tokens // 0) + ($x.message.usage.cache_creation_input_tokens // 0) + ($x.message.usage.cache_read_input_tokens // 0))
        | .o += ($x.message.usage.output_tokens // 0)
        | .bm[$x.message.model // "unknown"] += (($x.message.usage.input_tokens // 0) + ($x.message.usage.output_tokens // 0) + ($x.message.usage.cache_creation_input_tokens // 0) + ($x.message.usage.cache_read_input_tokens // 0)))
    | "\(.i)\u001f\(.o)\u001f" + ((.bm
        | to_entries
        | map(.key |= (if test("fable") then "fable"
                       elif test("opus") then "opus"
                       elif test("sonnet") then "sonnet"
                       elif test("haiku") then "haiku"
                       else (sub("^claude-";"") | sub("-[0-9]{8}$";"")) end))
        | group_by(.key) | map({key: .[0].key, value: (map(.value) | add)})
        | map(select(.value > 0)) | sort_by(-.value)
        | map("\(.key)=\(.value)") | join(","))
      )' 2>/dev/null)
  if [ -n "$sess_stats" ]; then
    IFS="$US" read -r sess_in sess_out sess_models <<< "$sess_stats"
  fi
fi

# Only models that actually burned tokens are shown (the old line always printed
# "fable:0 opus:0 sonnet:0", ~24 columns of zeros for most of a session).
usage_parts=""
if [ -n "$sess_models" ]; then
  IFS=',' read -ra _mods <<< "$sess_models"
  for _m in "${_mods[@]}"; do
    [ -z "$_m" ] && continue
    usage_parts="${usage_parts}${usage_parts:+ · }${_m%%=*} $(fmt_num "${_m##*=}")"
  done
fi

# --- session wall-clock duration (USD cost intentionally not shown) ---
dur_str=""
[ -n "$dur_ms" ] && dur_str="⏱ $(fmt_dur "$dur_ms")"

# --- rate-limit usage (Claude subscription 5h/7d windows) ---
five_i=$(round_int "$five"); week_i=$(round_int "$week")
lim_str=""
[ -n "$five_i" ] && lim_str="5h:${five_i}%"
[ -n "$week_i" ] && lim_str="${lim_str}${lim_str:+ }7d:${week_i}%"
# --- limit reset countdown (5h window; falls back to 7d) ---
# resets_at may be epoch seconds or an ISO-8601 string depending on CC version;
# parse both defensively — on any parse failure the segment just doesn't render.
if [ -n "$reset_at" ]; then
  reset_epoch=""
  case "$reset_at" in
    *T*) iso="${reset_at%%.*}"; iso="${iso%Z}"
         reset_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null) ;;
    *)   reset_epoch="${reset_at%.*}" ;;
  esac
  if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt 0 ] 2>/dev/null; then
    _secs=$(( reset_epoch - NOW ))
    if [ "$_secs" -gt 0 ]; then
      if [ "$_secs" -ge 3600 ]; then _reset_fmt="$((_secs/3600))h $(((_secs%3600)/60))m"
      else _reset_fmt="$((_secs/60))m"; fi
      lim_str="${lim_str}${lim_str:+ }↻ ${_reset_fmt}"
    fi
  fi
fi
# --- rate-limit cache for `rig quota` ---
# The statusline is the only thing that sees the session payload, so it is the
# only place that can hand the 5h/7d numbers to other tools (`rig quota` gates
# the pipeline's Opus waves on them). Written only when a window reported a
# number; atomic (temp file + mv) so a reader never sees a half-written file.
# CONTRACT — do not change the key names: {five_hour, seven_day, resets_at, ts}.
# resets_at stays "5h reset, else 7d" for old readers; resets_at_5h / resets_at_7d
# (added 2026-10-10) carry each window's own reset so `rig quota` can name the right one.
if [ -n "$five" ] || [ -n "$week" ]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null
  _rl_tmp="$CACHE_DIR/.rate-limits.$$.json"
  # Claude Code ends a slow status line with a signal; without the trap the
  # empty temp file stays behind (15 orphans seen 2026-10-29).
  trap 'rm -f "$_rl_tmp"' EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
  if jq -n --arg five "$five" --arg week "$week" --arg reset "${reset_at:-}" \
      --arg r5 "${reset_5h:-}" --arg r7 "${reset_7d:-}" --argjson ts "$NOW" \
      'def rst(x): if (x == "" or x == "null") then null
                  elif (x | test("^[0-9]+(\\.[0-9]+)?$")) then (x | tonumber) else x end;
       {five_hour: (if ($five == "" or $five == "null") then null else ($five | tonumber) end),
        seven_day: (if ($week == "" or $week == "null") then null else ($week | tonumber) end),
        resets_at: (if ($reset == "" or $reset == "null") then null
                    elif ($reset | test("^[0-9]+(\\.[0-9]+)?$")) then ($reset | tonumber)
                    else $reset end),
        resets_at_5h: rst($r5),
        resets_at_7d: rst($r7),
        ts: $ts}' > "$_rl_tmp" 2>/dev/null; then
    mv -f "$_rl_tmp" "$CACHE_DIR/rate-limits.json" 2>/dev/null
  else
    rm -f "$_rl_tmp" 2>/dev/null
  fi
  trap - EXIT TERM INT
fi

# color rate-limit segment by the hotter of the two windows
lim_rgb="$C_TEXT"
_worst=${five_i:-0}; [ "${week_i:-0}" -gt "$_worst" ] 2>/dev/null && _worst=${week_i:-0}
if   [ "$_worst" -ge 80 ] 2>/dev/null; then lim_rgb="$C_RED"
elif [ "$_worst" -ge 50 ] 2>/dev/null; then lim_rgb="$C_YELLOW"
fi

pl_new
pl_add "$C_PANEL" "$C_MAGENTA" "⇅ $(fmt_num "${sess_in:-0}")/$(fmt_num "${sess_out:-0}")"
[ -n "$usage_parts" ] && pl_add "$(pl_alt)" "$C_MAGENTA" "$usage_parts"
[ -n "$dur_str" ] && pl_add "$(pl_alt)" "$C_GREEN" "$dur_str"
[ -n "$lim_str" ] && pl_add "$(pl_alt)" "$lim_rgb" "$lim_str"
pl_end
line3="$pl_line"

# ================= RIG PROBE (feeds lines 4 + 5) =================
# The four stdio MCP servers are children of Claude Code -> matched against ONE
# `ps -Ao args=` snapshot in-shell (the 5-line version used 4x pgrep, ~70 ms).
# The two HTTP services get a /dev/tcp probe: a refused connection fails
# instantly, so no curl and no timeout. Ollama's *loaded model* needs a real HTTP
# read, which is the main reason the whole probe sits behind a cache.
#
# Cached for RIG_TTL seconds; a hit costs ONE stat(1). Cache layout, US-joined:
#   code-context · rag-context · doc-creator · image-gen · ui · ollama · ollama-model
# each service field being 1 (up) or 0 (down). The short-lived 2026-09-03 cache
# format had 3 fields (up/total/down) — such a file leaves $s_oll empty and is
# just re-probed, so no cache flush is needed after this change.
RIG_TTL=10
RIG_CACHE="$CACHE_DIR/rig.txt"
s_ccx=""; s_rag=""; s_doc=""; s_img=""; s_ui=""; s_oll=""; ollama_model=""; s_rel=""
if [ -f "$RIG_CACHE" ]; then
  _rig_mt=$(stat -f %m "$RIG_CACHE" 2>/dev/null || echo 0)
  if [ $(( NOW - _rig_mt )) -lt "$RIG_TTL" ] 2>/dev/null; then
    IFS="$US" read -r s_ccx s_rag s_doc s_img s_ui s_oll ollama_model s_rel < "$RIG_CACHE"
  fi
fi
if [ -z "$s_oll" ] || [ -z "$s_rel" ]; then   # cache miss (or a cache written before a field was added)
  _ps=$(ps -Ao args= 2>/dev/null)
  _rig_proc() { # $1 = varname, $2 = cmdline substring
    case "$_ps" in *"$2"*) printf -v "$1" '1' ;; *) printf -v "$1" '0' ;; esac
  }
  _rig_port() { # $1 = varname, $2 = tcp port on localhost
    if (exec 3<>/dev/tcp/127.0.0.1/"$2") 2>/dev/null; then
      exec 3>&- 3<&- 2>/dev/null
      printf -v "$1" '1'
    else
      printf -v "$1" '0'
    fi
  }
  _rig_proc s_ccx "vlm-code-context-mcp/dist/server"
  _rig_proc s_rag "rag_context.server"
  _rig_proc s_doc "doc_creator.server"
  _rig_proc s_img "image_gen.server"
  _rig_proc s_rel "release_pilot.server"
  _rig_port s_ui  3333
  _rig_port s_oll 11434
  # Loaded model via a raw HTTP/1.0 GET on /api/ps (no curl; 1.0 so the server
  # closes the connection itself). NB: `if (exec 3<>...)` above is a SUBSHELL, so
  # fd 3 is already closed here — reconnect for real. Models idle-unload after
  # ~5 min -> "idle". Several can be loaded at once (embedder + writer) and the
  # order varies, so prefer the non-embedding one, else whatever came first.
  if [ "$s_oll" = 1 ] && exec 3<>/dev/tcp/127.0.0.1/11434 2>/dev/null; then
    printf 'GET /api/ps HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3
    # the JSON body is the last line and has NO trailing newline, so the final
    # `read` exits non-zero while still filling $_l — keep that partial line.
    _body=""; _l=""
    while IFS= read -r -t 1 _l <&3; do _body="$_l"; done
    [ -n "$_l" ] && _body="$_l"
    exec 3>&- 3<&- 2>/dev/null
    # name extraction in-shell: the old version piped grep -o into sed (2 forks)
    _rest="$_body"; _first=""
    while :; do
      case "$_rest" in
        *'"name":"'*) _rest="${_rest#*\"name\":\"}"; _n="${_rest%%\"*}" ;;
        *) break ;;
      esac
      [ -z "$_first" ] && _first="$_n"
      case "$_n" in *embed*) ;; *) ollama_model="$_n"; break ;; esac
    done
    [ -z "$ollama_model" ] && ollama_model="$_first"
    ollama_model="${ollama_model%:latest}"
    ollama_model="${ollama_model%%-*}"
  fi
  mkdir -p "$CACHE_DIR" 2>/dev/null
  _rig_tmp="$RIG_CACHE.$$"
  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "$s_ccx" "$US" "$s_rag" "$US" "$s_doc" "$US" "$s_img" "$US" \
    "$s_ui" "$US" "$s_oll" "$US" "$ollama_model" "$US" "$s_rel" > "$_rig_tmp" 2>/dev/null \
    && mv -f "$_rig_tmp" "$RIG_CACHE" 2>/dev/null
  rm -f "$_rig_tmp" 2>/dev/null
fi

# Installed versions and configured local models, straight off disk — 6 files,
# zero forks (see toml_val/json_val at the top). code-context is an npm package
# (package.json); the three Python MCPs carry their version in pyproject.toml.
MCP_DIR="$HOME/Desktop/Workspace/mcp-servers"
json_val ccx_ver "$MCP_DIR/vlm-code-context/node_modules/vlm-code-context-mcp/package.json" "version"
toml_val rag_ver "$MCP_DIR/vlm-rag-context/pyproject.toml" "version"
toml_val doc_ver "$MCP_DIR/vlm-doc-creator/pyproject.toml" "version"
toml_val img_ver "$MCP_DIR/vlm-image-gen/pyproject.toml" "version"
toml_val rel_ver "$MCP_DIR/vlm-release-pilot/pyproject.toml" "version"
toml_val doc_model "$MCP_DIR/vlm-doc-creator/config.toml" "model"
doc_model="${doc_model%:latest}"; doc_model="${doc_model%%-*}"  # qwen2.5:32b-instruct-q4_K_M -> qwen2.5:32b
# doc-creator 1.3.0 writes on a chain (`[writer] chain = ["deepseek", "glm", "local"]`);
# show the chain, "local" named after the model, unless local_only pins it to the Mac.
# Fork-free like toml_val: one read loop, parameter expansion only.
doc_chain="" doc_lonly=""
if [ -r "$MCP_DIR/vlm-doc-creator/config.toml" ]; then
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in
      "chain = ["*) _l="${_l#*[}"; _l="${_l%%]*}"; _l="${_l//\"/}"; _l="${_l// /}"; doc_chain="${_l//,/›}" ;;
      "local_only = true"*) doc_lonly=1 ;;
    esac
  done < "$MCP_DIR/vlm-doc-creator/config.toml"
fi
if [ -n "$doc_chain" ] && [ -z "$doc_lonly" ]; then
  doc_model="${doc_chain//local/${doc_model:-local}}"
fi
toml_val img_model "$MCP_DIR/vlm-image-gen/config.toml" "model"  # kept whole: z-image-turbo

# ================= LINE 4 — KNOWLEDGE =================
# ● up / ○ down, no words. Server chips carry the installed version; the
# dashboard and ollama are ports, so they carry what you'd type to reach them.
pl_new
if [ "$s_ccx" = 1 ]; then
  pl_add "$C_GREEN" "$C_DARK" "● code-context${ccx_ver:+ $ccx_ver}"
else
  pl_add "$C_RED" "$C_DARK" "○ code-context${ccx_ver:+ $ccx_ver}"
fi
if [ "$s_ui" = 1 ]; then
  pl_add "$C_PANEL2" "$C_CYAN" "ui :3333"
else
  pl_add "$C_PANEL2" "$C_YELLOW" "ui ○ /ccui"
fi
if [ "$s_rag" = 1 ]; then
  pl_add "$C_GREEN" "$C_DARK" "● rag-context${rag_ver:+ $rag_ver}"
else
  pl_add "$C_RED" "$C_DARK" "○ rag-context${rag_ver:+ $rag_ver}"
fi
if [ "$s_oll" = 1 ]; then
  pl_add "$C_PANEL2" "$C_CYAN" "⚡ ollama ${ollama_model:-idle}"
else
  pl_add "$C_PANEL2" "$C_YELLOW" "⚡ ollama ○"
fi
# overdrive = the whole local setup as one versioned tool (local git at ~/.claude,
# `overdrive` CLI). Builtin `read`, no fork — the version only changes on a bump.
od_ver=""
[ -f "$HOME/.claude/VERSION" ] && read -r od_ver < "$HOME/.claude/VERSION"
pl_add "$C_ACCENT" "$C_DARK" "⏣ overdrive ${od_ver:-?}"
pl_end
line4="$pl_line"

# ================= LINE 5 — CREATE =================
# doc-creator and image-gen, each as a server chip + its configured model. The
# model chips are colored apart (cyan ✎ text / magenta ◈ raster) so the pair
# doesn't read as one four-chip blur. Both show ○ until Claude Code is restarted
# after an install — they are stdio children, spawned by the client, not daemons.
pl_new
if [ "$s_doc" = 1 ]; then
  pl_add "$C_GREEN" "$C_DARK" "● doc-creator${doc_ver:+ $doc_ver}"
else
  pl_add "$C_RED" "$C_DARK" "○ doc-creator${doc_ver:+ $doc_ver}"
fi
pl_add "$C_PANEL2" "$C_CYAN" "✎ ${doc_model:-no model}"
if [ "$s_img" = 1 ]; then
  pl_add "$C_GREEN" "$C_DARK" "● image-gen${img_ver:+ $img_ver}"
else
  pl_add "$C_RED" "$C_DARK" "○ image-gen${img_ver:+ $img_ver}"
fi
pl_add "$C_PANEL2" "$C_MAGENTA" "◈ ${img_model:-no model}"
if [ "$s_rel" = 1 ]; then
  pl_add "$C_GREEN" "$C_DARK" "● release-pilot${rel_ver:+ $rel_ver}"
else
  pl_add "$C_RED" "$C_DARK" "○ release-pilot${rel_ver:+ $rel_ver}"
fi
pl_end
line5="$pl_line"

# ================= LINE 6 — TOOLS =================
# The local CLIs that have no server process: version straight off disk (5 small
# file reads, zero forks). Yellow version = still pre-1.0, cyan = 1.0+; a red
# chip means the script is gone. Added 2026-10-09 so every tool of the setup is
# visible somewhere — before this only the MCP servers carried a version.
TOOLS_DIR="$HOME/.claude/tools"
# rig and rag-vault keep their version in a VERSION file since 1.0.0 (builtin read, no fork)
rig_ver=""; [ -r "$TOOLS_DIR/rig/VERSION" ] && read -r rig_ver < "$TOOLS_DIR/rig/VERSION"
vault_ver=""; [ -r "$TOOLS_DIR/rag-vault/VERSION" ] && read -r vault_ver < "$TOOLS_DIR/rag-vault/VERSION"
rver_ver=""; sh_val rver_ver "$TOOLS_DIR/rag-verify/rag-verify.sh"       SLOG_VERSION
dr_ver="";   sh_val dr_ver   "$TOOLS_DIR/dual-review/dual-review.sh"     VERSION
tix_ver=""; json_val tix_ver "$HOME/Desktop/Workspace/dev/personal/tix/package.json" "version"
tool_chip() { # $1 = glyph+name, $2 = version ("" = not installed)
  if [ -z "$2" ]; then
    pl_add "$C_PANEL" "$C_RED" "$1 ○"
  elif [ "${2%%.*}" = 0 ]; then
    pl_add "$(pl_alt)" "$C_YELLOW" "$1 $2"
  else
    pl_add "$(pl_alt)" "$C_CYAN" "$1 $2"
  fi
}
pl_new
tool_chip "⚙ rig" "$rig_ver"
tool_chip "⬢ tix" "$tix_ver"
tool_chip "⚖ dual-review" "$dr_ver"
tool_chip "⛁ rag-vault" "$vault_ver"
tool_chip "✓ rag-verify" "$rver_ver"
pl_end
line6="$pl_line"

# ================= Print =================
printf "%b\n" "$line1"
printf "%b\n" "$line2"
printf "%b\n" "$line3"
printf "%b\n" "$line4"
printf "%b\n" "$line5"
printf "%b\n" "$line6"
exit 0
