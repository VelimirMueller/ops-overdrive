# shellcheck shell=bash
# VENDORED from ~/.claude/tools/overdrive/flair.sh (this repo stays standalone). Contract: FLAIR.md there.
# overdrive flair — reference bash helper (contract: FLAIR.md next to this file).
# Vendor a copy into your repo; do not source it from ~/.claude at runtime.
#   FLAIR_TOOL=rig FLAIR_GLYPH=⚙ ; . ./flair.sh
#   t0=$(flair_now_ms); flair_banner "doctor"; …; flair_done $? "$t0" [tok_in tok_out]
# Art only when stdout is a TTY and OVERDRIVE_FLAIR != 0. Every error is swallowed.

flair_on() {
  [ "${OVERDRIVE_FLAIR:-1}" = 0 ] && return 1
  [ -t 1 ] || return 1
  return 0
}
_flair_c() { # $1 = "R;G;B" -> sets colour unless NO_COLOR
  [ -n "${NO_COLOR:-}" ] && return 0
  printf '\033[38;2;%sm' "$1"
}
_flair_r() { [ -n "${NO_COLOR:-}" ] || printf '\033[0m'; }

flair_now_ms() { # milliseconds since epoch; perl is always on macOS, date +%N is not
  perl -MTime::HiRes=time -e 'printf "%d\n", time*1000' 2>/dev/null || echo $(( $(date +%s) * 1000 ))
}

flair_banner() { # $1 = subtitle (the command)
  flair_on || return 0
  local quips=("[ jacking in... ]" "[ hack the planet ]" "[ there is no spoon ]" \
    "[ sudo make me a sandwich ]" "[ all your base are belong to us ]" \
    "[ it's a unix system, I know this ]" "[ 0wning the build ]" "[ ping 127.0.0.1 — still here ]")
  local q="${quips[$(( $$ % ${#quips[@]} ))]}"
  {
    _flair_c "238;79;255"; printf '░▒▓█ '; _flair_c "0;255;247"
    printf '%s %s' "${FLAIR_GLYPH:-⏣}" "${FLAIR_TOOL:-tool}"
    _flair_c "238;79;255"; printf ' ▸ %s █▓▒░  ' "${1:-}"
    _flair_c "90;80;130"; printf '%s' "$q"; _flair_r; printf '\n'
  } 2>/dev/null || true
}

flair_div() {
  flair_on || return 0
  { _flair_c "90;80;130"; printf '%*s' 60 '' | tr ' ' '─'; _flair_r; printf '\n'; } 2>/dev/null || true
}

flair_done() { # $1 = exit code, $2 = start ms, [$3 tokens in, $4 tokens out]
  # shellcheck disable=SC1111  # the kaomoji contain unicode quote-like glyphs on purpose
  local rc="${1:-0}" t0="${2:-}" ms="" k ok=("┬─┬ノ( º _ºノ)" "(⌐■_■)" "ᕙ(⇀‸↼‶)ᕗ" "(•̀ᴗ•́)و") bad=("(╯°□°)╯︵ ┻━┻" "ಠ_ಠ")
  [ -n "$t0" ] && ms=$(( $(flair_now_ms) - t0 ))
  # the session-log line is written even without a TTY (it feeds `overdrive trace`)
  if command -v slog >/dev/null 2>&1; then
    slog INFO "done ${FLAIR_CMD:-run} in ${ms:-?} ms${3:+ tokens=$3/${4:-0}} (exit $rc)" 2>/dev/null || true
  fi
  flair_on || return 0
  if [ "$rc" = 0 ]; then k="${ok[$(( ${ms:-$$} % ${#ok[@]} ))]}"; _flair_c "5;255;161"
  else k="${bad[$(( ${ms:-$$} % ${#bad[@]} ))]}"; _flair_c "255;42;109"; fi
  {
    printf '%s ' "$k"; _flair_c "90;80;130"
    if [ -n "$ms" ]; then
      if [ "$ms" -ge 1000 ]; then printf '%d.%01ds' $((ms/1000)) $(((ms%1000)/100)); else printf '%d ms' "$ms"; fi
    fi
    [ -n "${3:-}" ] && printf ' · %s/%s tok' "$3" "${4:-0}"
    _flair_r; printf '\n'
  } 2>/dev/null || true
}
