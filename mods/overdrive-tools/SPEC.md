# overdrive-tools — spec

A Claude Code mod (function hooks, early-access API). Sibling of `overdrive-tabs`; same tsconfig and test kit.

## Look (terminal, every ToolUse row in the transcript)
```
▌INF ▸ Read /Users/…/hooks/register.tsx            ← folded info row, one line
▌RUN ▾
▌ ⏺ Bash(printf 'a\nb')                            ← open row: the engine's own drawing
▌   a
▌   b
▌CHG ▾
▌ ⏺ Write(/path/file.txt)
```
- Kind per row from `hooks/classify.ts`: `info` (Read, Grep, Glob, WebFetch, MCP get/list/search/rag_*),
  `change` (Edit, Write, MCP create/update/save/delete), `run` (Bash, Agent, Workflow, unknown).
  `classifyBash(command)` decides info vs change for shell commands; until written every Bash row is `run`.
- Colors (Neon Overdrive): info `#00FFF7`, change `#EE4FFF`, run `#F0FF19`, an errored call `error`.
- The tag is a plain Button keyed `odt-<tool_use_id>`; a click toggles that row's member of the state family
  `overdrive-tools.row` (`'open' | 'closed' | null`). `hooks/rows.ts` resolves override + mode to open/closed.
- Modes: `folded` (default, every finished row closed), `changes` (info closed, change and run open), `all`
  (everything open); `/tools <mode>` sets one, bare `/tools` toggles folded ↔ all. A running call stays open. The command's output names the layout (clicks arrive only in fullscreen).
- A `ToolGroup` (folded run of reads) that holds a change row is unfolded so the change gets its own line.
- Hover reveal was tried and dropped: the terminal did not report the pointer.

## Checks
`claude plugin validate mods/overdrive-tools` · `tsc -p mods/overdrive-tools` · `claude plugin test mods/overdrive-tools`
