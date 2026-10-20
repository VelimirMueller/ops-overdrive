# overdrive-tabs — spec

A Claude Code mod (function hooks, early-access API). Reference: `../ref/` (examples band.tsx, pane.tsx,
reference.md) and the API types `.claude-plugin/types/claude-code/index.d.ts` (grep it; ~15k lines).

## Look (terminal, inside an AbovePrompt band)
```
┏━━ ░▒▓█ ⏣ O V E R D R I V E █▓▒░ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 1.10.0 ━┓
┃ 1: code 2: tickets 3: claude 4: overdrive 5: serpent      click or ctrl+x tab → 1-5                       ┃
┃         ━━━━━━━━━━                                                                                        ┃
┃ linear  ODT-812 · build (opus) · 2h ago                                                                   ┃
┃ sprint  overdrive — status tabs mod  3 of 4 done                                                          ┃
┃ doing   ODT-4 Install mod, check it live                                                                  ┃
┗⸌∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿(◣▾◢)⟫≋≋≋✶━┛
```
- The box wraps the whole menu (open or collapsed), in `#EE4FFF`: `headerBox(bodyColumns, version)` gives the title
  edge (first row) and the fire-serpent edge (last row), each exactly `bodyColumns` code points. Every row between
  sits inside `┃ ` … ` ┃` walls in a Box of `innerCols(bodyColumns)` = cols − 4. Below 20 cols: no box, bare rows.
- Tabs: five plain Buttons `tab-code|tickets|claude|overdrive|serpent`, hotkeys `1`–`5`; active bold, others dim.
  Dim hint `click or ctrl+x tab → 1-5` only when it fits the inner width.
- Fixed height: always 8 rows (title edge, tabs, underline row, 4 body rows padded with blank walled rows, serpent edge).
- Underline `━` under the active tab (offset counts the `N: ` prefix and one gap per tab). Collapsed: blank underline row,
  one dim row `collapsed — press a tab to open`.
- Body rows: dim label padded to 8 cols + value, truncated to the inner width with `…`. Max 4 rows.
  - code: `branch` (+ ahead/behind), `changes` (`<n> changed` | `clean`), `review`, `commit` (`<sha> · <age> ago · <subject>`).
  - tickets: `linear` (newest `tix phase` file not `done`: `<ID> · <phase> (<by>) · <age> ago` | `no active ticket`),
    `sprint`, `doing` (1–2 IN_PROGRESS rows), `next` (first TODO of the open sprint, only while a row is free).
  - claude: `context`, `5-hour`, `week`, `cost`; ≥ 85 % → ` · hot` in red.
  - overdrive: `version`, `snapshot`, `changes`, `log`.
  - serpent: `serpent` (tail + one `∿` per turn + the mood's face + `⟫≋✶`), `mood`, `fed` (`<turns> turns · <tools> tools`),
    `fortune` (rotates per turn). Mood = `serpentMood(MoodInput)` in `hooks/tabs.ts`.
- Data refresh: all tabs at `session.start`; code + tickets + overdrive at `turn.complete`; code + tickets after every
  `Bash|Edit|Write|NotebookEdit|mcp__code-context__*` tool call; claude at `session.measure`; a tab on press.
- `e.props.hasSurvey` → `return next(e)`. `active` persists in `$.store` (`overdrive-tabs.active`), default `'code'`.

## State
`types/index.d.ts` is the contract (atoms `{ plugin: 'overdrive-tabs', key }`). Render hooks only `read` atoms;
all I/O happens in event hooks and writes atoms with `update`.

## Data (see types/index.d.ts for each field's source)
- code-context DB: `~/Desktop/Workspace/mcp-servers/data/context.db` (expand `~` via `$.env`/HOME, check the types),
  read with `$.process.run(['sqlite3','-readonly','-json',db, sql])`. Tables: `sprints(id,name,status,deleted_at,archived_at)`,
  `tickets(id,sprint_id,ticket_ref,title,status,deleted_at,updated_at)`. Sprint "open" = status not in ('closed','done')
  and deleted_at IS NULL and archived_at IS NULL.
- Every collector fails soft: a missing tool, non-zero exit or parse error gives null / 0, never throws.
- Parsers are pure functions (string in, value out) so they are unit-testable without processes.

## Done when
`claude plugin validate .`, `npx -y -p typescript@5.6.3 tsc -p .` and `claude plugin test .` are all green.
