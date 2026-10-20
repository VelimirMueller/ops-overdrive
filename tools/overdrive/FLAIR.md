# Overdrive flair — the ASCII-art contract every local tool follows

Since overdrive 1.4.0 (2026-10-09). Every local tool shows the same nerdy-hacker look when a
human reads its output. Machines reading it (scripts, `--json`, pipes, statusline chips)
never see art. Like SESSION-LOG.md, each repo vendors its own small helper in its own
language. The helpers agree on this file, not on shared code.

## Where art appears

| Output | What | Budget |
|---|---|---|
| CLI on a TTY (stdout is a terminal) | Banner at start (≤ 6 lines), dividers, closing line with kaomoji + duration (+ tokens when the tool called a model) | helper cost < 2 ms |
| CLI not a TTY, `--json`, `--chip`, `--status --json`, `--quiet` | **No art at all** | — |
| MCP tool response (text) | ONE header line + ONE footer line, ≤ 72 chars each | ≤ 40 tokens per response |
| MCP tool response that callers parse as JSON | No art | — |
| Errors | Footer uses the fail kaomoji; the error text itself stays plain and first | — |

MCP responses go into Claude's context on every call, so they cost tokens and time. That
is why they get two short lines and never the big banner.

## Switches

- `OVERDRIVE_FLAIR=0` — no art anywhere.
- `OVERDRIVE_FLAIR=full` — big banners in MCP responses too (for screenshots).
- `NO_COLOR` set, or not a TTY → no ANSI colour. MCP responses never contain ANSI codes.

## Building blocks

**Glyph per tool** (same as the statusline):
`⚙ rig` · `⬢ tix` · `⚖ dual-review` · `⛁ rag-vault` · `✓ rag-verify` · `● code-context` ·
`◆ rag-context` · `✎ doc-creator` · `◈ image-gen` · `⚑ release-pilot`/`relpilot` · `⏣ overdrive`

**MCP header:** `<glyph> <tool> ▸ <action> ░▒▓` — e.g. `◆ rag-context ▸ search ░▒▓`
**MCP footer:** `<kaomoji> <duration>[ · <tokens> tok]` — e.g. `┬─┬ノ( º _ºノ) 79 ms`

**Kaomoji:**
- ok: `┬─┬ノ( º _ºノ)` · `(⌐■_■)` · `ᕙ(⇀‸↼‶)ᕗ` · `(•̀ᴗ•́)و`
- fail / changes requested: `(╯°□°)╯︵ ┻━┻` · `ಠ_ಠ`
- blocked / missing key: `¯\_(ツ)_/¯` · `(°ロ°)☝`

Pick by `pid % len` (or the ms of the duration), never a random API call.

**Quips** for CLI banners — pick one the same way:
`[ jacking in... ]` · `[ hack the planet ]` · `[ there is no spoon ]` · `[ sudo make me a sandwich ]` ·
`[ all your base are belong to us ]` · `[ it's a unix system, I know this ]` ·
`[ 0wning the build ]` · `[ ping 127.0.0.1 — still here ]`

**Divider:** `─` × 60, dim. **Progress / bars:** `░▒▓█`.

**Palette** (Neon Overdrive, 24-bit, TTY only): magenta `238;79;255` banners,
cyan `0;255;247` tool names, green `5;255;161` ok, yellow `240;255;25` warn,
red `255;42;109` fail, dim `90;80;130`.

**Fire-serpent ornament** (overdrive-tabs band + chat frames): a dragon along the line —
tail `⸌`, body `∿` fill, head `(◣▾◢)` with jaw `⟫` breathing fire `≋≋≋✶`. All glyphs are
one cell wide; never `》` (double width). At 60 cols: `⸌` + 49 × `∿` + `(◣▾◢)⟫≋≋≋✶` = 60.
The overdrive-tabs band opens with a fixed header box: `┏━━ ░▒▓█ ⏣ O V E R D R I V E █▓▒░ ━…━ <ver> ━┓`
over a serpent bottom edge `┗⸌∿…(◣▾◢)⟫≋≋≋✶━┛`, full band width.

**Block frame** (chat answers): open `┏━━ (◣▾◢)⟫≋ <LABEL> ━━━…┓`, close `┗` + `∿` fill +
`⸍━┛`; ≤ 60 chars; no right border on content lines; label in caps (2–4 words: `STATUS`,
`OPEN PRS`, `WHAT CHANGED`, `NEXT`).

## Timing and tokens (feeds `overdrive trace`)

Every command that finishes writes one session-log line (SESSION-LOG.md format):
`INFO … done <command> in <ms> ms[ tokens=<in>/<out>]`. Tokens only when the tool itself
called a model and the provider returned usage. Never estimate.

## Rules

1. Art never changes exit codes, never goes to stderr except with an error, never breaks `--json`.
2. Every helper error is swallowed. Flair never breaks the tool.
3. Tests run with `OVERDRIVE_FLAIR=0` unless they test flair itself; add one test that a
   non-TTY run contains no art.

## Reference implementation (bash)

`~/.claude/tools/overdrive/flair.sh`: `source` it, set `FLAIR_TOOL` and `FLAIR_GLYPH`,
call `flair_banner "<subtitle>"` at start, `flair_div` between sections and
`flair_done <exit> <start_ms> [tokens_in tokens_out]` at the end.
