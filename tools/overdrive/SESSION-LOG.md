# Overdrive session log — the contract every local tool follows

Since overdrive 1.1.0 (2026-10-09). Every local tool (rig, dual-review, rag-vault, tix,
code-context, rag-context, doc-creator, image-gen, release-pilot, overdrive) writes to
ONE shared log per Claude Code session. Because each line is written immediately, the
log is still there when a session crashes. A finished session removes it with
`/remove-log` (`overdrive session rm`).

Each repo carries its own small helper in its own language (no dependency on
`~/.claude`). The helpers agree on this file format, not on shared code.

## Where

    ${OVERDRIVE_SESSION_LOG_DIR:-~/.claude/.local_ai_setup_logs/sessions}/<id>.log

- `<id>` = `$CLAUDE_CODE_SESSION_ID`. Claude Code exports it to Bash commands and
  to every stdio MCP server it spawns.
- No session id (launchd job, plain terminal) → `_nosession-YYYY-MM-DD.log`.
- Create the directory with mode 0700 and the file with mode 0600.
- `OVERDRIVE_SESSION_LOG=0` turns logging off (tests set `OVERDRIVE_SESSION_LOG_DIR`
  to a temp dir instead).

## Line format

One line per event, fields separated by TAB:

    <ts>\t<LEVEL>\t<tool>@<version>\tpid=<pid>\t<message>

- `ts`: local ISO-8601 with offset and milliseconds, e.g. `2026-10-09T10:12:03.123+02:00`.
- `LEVEL`: exactly one of `INFO`, `WARN`, `CRITICAL`, padded to no width.
- `message`: one line. Replace newlines with `⏎` and tabs with a space, and cut it
  to 500 characters.

## Structured fields (optional, since 2026-10-29)

A message can carry up to four `key=value` fields. Ops Cockpit reads them to place a
line in a workflow (ops-cockpit #225). Every field is optional, and a line without
them stays valid: readers fall back to the free-form text.

| Field | Value | Meaning |
|---|---|---|
| `wf=` | workflow id, e.g. `ship`, `release` | The workflow the line belongs to |
| `step=` | step number or id, e.g. `3`, `commit-push-pr` | The step inside that workflow |
| `state=` | `idle`, `spec`, `plan`, `build`, `review`, `ship` or `done` | The session state after this line |
| `evt=` | `start`, `end` or `gate` | What the line marks: a step began, ended, or a gate decided |

Rules:

- A field is one whole space-separated token. Put it anywhere in the message, usually
  at the end: `verdict PASS: deepseek=approved glm=approved wf=ship step=1 evt=gate`.
- A value has 1–64 characters of `A-Z a-z 0-9 . _ : / -`. No spaces, no quotes.
- `state=` and `evt=` values are lowercase and exactly one of the listed names.
- Each key once per line. A reader takes the first occurrence and ignores the rest.
- A reader ignores a field whose value breaks a rule, as if the field were absent.
- The fields are metadata like the rest of the line: rule 4 below still applies.

## Levels

| Level | Use it when | Examples |
|---|---|---|
| `INFO` | Normal milestones | command started/finished, which provider or model served, cache hit, PR opened |
| `WARN` | Degraded, but the tool carried on | retry, fallback hop, optional key missing, stale input, skipped step |
| `CRITICAL` | The tool failed its job, or a safety gate tripped | unhandled exception, required key missing, gate BLOCKED, write failed, verdict HOLD on incomplete input |

A review requesting changes is WARN, not CRITICAL: the reviewer did its job. CRITICAL stays for a gate that could not decide (BLOCKED, required key missing).

## Rules

1. **One `write()` per line with O_APPEND, flushed immediately.** Lines stay under
   4 KB, so concurrent writers (MCP servers next to CLIs) never interleave mid-line.
2. **Refuse anything but a regular file.** Open with `O_APPEND|O_CREAT|O_NOFOLLOW`
   (mode 0600) and check the open handle is a regular file. A symlink planted at the log
   path must not redirect the append. If the language cannot refuse a symlink at open
   time, write nothing.
3. **Logging never breaks the tool.** Every error inside the helper is swallowed.
4. **Never log content or secrets.** No key values, tokens, diff text, PR or ticket
   bodies, prompts, model output, file contents, or full vendor error text (log the
   class and status code). Names, ids, counts, durations and SHAs are fine.
5. Log about 1 line per meaningful step. This is a breadcrumb trail, not a trace.

## Reference implementation (bash)

`~/.claude/tools/overdrive/sessionlog.sh`:
`source` it, set `SLOG_TOOL` and `SLOG_VERSION`, then call `slog WARN "message"`.
