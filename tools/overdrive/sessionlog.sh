#!/bin/bash
# Overdrive session log — bash helper, VENDORED from ~/.claude/tools/overdrive/sessionlog.sh
# (this repo must stay standalone). Contract: ~/.claude/tools/overdrive/SESSION-LOG.md.
#
#   SLOG_TOOL=rig SLOG_VERSION=0.2.0
#   . "$REPO_DIR/sessionlog.sh"     # the copy next to the script
#   slog INFO "doctor: 5/5 keys resolve"
#
# Run directly it is a CLI too:  sessionlog.sh WARN mytool@1.0 "message"
# Never fails the caller: every error is swallowed and slog always returns 0.

slog_path() {
  local dir="${OVERDRIVE_SESSION_LOG_DIR:-$HOME/.claude/.local_ai_setup_logs/sessions}"
  local id="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$id" ] || id="_nosession-$(date +%Y-%m-%d)"
  # a session id is a path component — keep it one. Claude Code ids are UUIDs, which this
  # maps to themselves. overdrive's own sessionlog.sh applies this exact replacement and
  # `overdrive session show/rm` find the file through it, so every copy keeps it as is.
  id="${id//[^A-Za-z0-9._-]/_}"
  printf '%s/%s.log' "$dir" "$id"
}

slog() { # $1 = INFO|WARN|CRITICAL, rest = message
  [ "${OVERDRIVE_SESSION_LOG:-1}" = 0 ] && return 0
  local level="$1"; shift
  case "$level" in INFO|WARN|CRITICAL) ;; *) level=WARN ;; esac
  local msg="$*" file
  msg="${msg//$'\n'/⏎}"; msg="${msg//$'\t'/ }"; msg="${msg:0:500}"
  file=$(slog_path)
  # append only to a regular file (or create one): a symlink planted at the log path
  # would redirect the append, anything else (a directory, a fifo) is not a log
  if [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then return 0; fi
  {
    [ -d "${file%/*}" ] || (umask 077; mkdir -p "${file%/*}")
    # no perl (never the case on macOS) = no breadcrumb: a bash `>>` cannot refuse a
    # symlink at open time, and a log that can be redirected is worse than none
    if command -v perl >/dev/null 2>&1; then
      # perl does both jobs: the timestamp with milliseconds (date +%N is GNU-only) and
      # ONE syswrite through O_APPEND|O_NOFOLLOW — the open itself refuses a symlink, so
      # there is no window between the check above and the write. O_NONBLOCK + the -f
      # test on the open handle refuse a fifo or anything else that is not a regular file.
      # (Fcntl exports O_NOFOLLOW on macOS and Linux; the tests write through this path.)
      perl -MFcntl -MTime::HiRes=time -MPOSIX=strftime -e '
        my ($f, $lvl, $tv, $pid, $msg) = @ARGV; my $t = time; my $sec = int $t;
        my $ms = int(($t - $sec) * 1000); $ms = 999 if $ms > 999;   # always 000-999
        my $z = strftime("%z", localtime $sec); substr($z, 3, 0) = ":";
        my $line = sprintf("%s.%03d%s\t%s\t%s\tpid=%s\t%s\n",
          strftime("%Y-%m-%dT%H:%M:%S", localtime $sec), $ms, $z, $lvl, $tv, $pid, $msg);
        sysopen(my $fh, $f, O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_NONBLOCK, 0600) or exit 1;
        -f $fh or exit 1; syswrite($fh, $line) or exit 1;' \
        "$file" "$level" "${SLOG_TOOL:-unknown}@${SLOG_VERSION:-0}" "$$" "$msg"
    fi
  } 2>/dev/null
  return 0
}

# Executed rather than sourced: sessionlog.sh LEVEL tool@version message...
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  [ $# -ge 3 ] || { echo "usage: sessionlog.sh INFO|WARN|CRITICAL tool@version message" >&2; exit 2; }
  _lvl="$1" _tv="$2"; shift 2
  SLOG_TOOL="${_tv%@*}" SLOG_VERSION="${_tv#*@}"
  slog "$_lvl" "$*"
fi
