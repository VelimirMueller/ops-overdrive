import type { ClaudeInfo, CodeInfo, OverdriveInfo, SerpentInfo, TabId, TicketsInfo } from '../types'

export type Tab = {
  readonly id: TabId
  readonly key: string
  readonly label: string
  readonly hotkey: string
}

export const TABS: readonly Tab[] = [
  { id: 'code', key: 'tab-code', label: 'code', hotkey: '1' },
  { id: 'tickets', key: 'tab-tickets', label: 'tickets', hotkey: '2' },
  { id: 'claude', key: 'tab-claude', label: 'claude', hotkey: '3' },
  { id: 'overdrive', key: 'tab-overdrive', label: 'overdrive', hotkey: '4' },
  { id: 'serpent', key: 'tab-serpent', label: 'serpent', hotkey: '5' },
]

export const DEFAULT_ACTIVE: TabId = 'code'
export const COLLAPSED = 'none'

export const LABEL_COLS = 8
/** Body rows the box always shows, so it keeps one height on every tab. */
export const BODY_ROWS = 4
export const HINT = 'click or ctrl+x tab → 1-5'
const HINT_GAP = 6
const HOT_PCT = 85

export const DRAGON_ACCENT = '#EE4FFF'
const DRAGON_TAIL = '⸌'
const DRAGON_BODY = '∿'
const DRAGON_HEAD = '(◣▾◢)⟫≋≋≋✶'
const DRAGON_MIN = DRAGON_TAIL.length + DRAGON_HEAD.length + 3

/** The fire-serpent separator: tail first, `∿` coiling along the line, head at the
 *  right end — exactly `cols` code points wide, every glyph one cell. */
export const dragonRule = (cols: number): string => {
  if (cols < 1) return ''
  if (cols < DRAGON_MIN) return DRAGON_TAIL + DRAGON_BODY.repeat(cols - DRAGON_TAIL.length)
  return (
    DRAGON_TAIL + DRAGON_BODY.repeat(cols - DRAGON_TAIL.length - DRAGON_HEAD.length) + DRAGON_HEAD
  )
}

const HEADER_TITLE = '░▒▓█ ⏣ O V E R D R I V E █▓▒░'
const HEADER_TITLE_SHORT = '⏣ OVERDRIVE'
const HEADER_MIN = 20

/** The box's side walls: `┃ ` left and ` ┃` right of every row inside it. */
export const WALL_LEFT = '┃ '
export const WALL_RIGHT = ' ┃'
const WALLS = WALL_LEFT.length + WALL_RIGHT.length

/** True when the band is wide enough for the box around the menu. */
export const framed = (cols: number): boolean => cols >= HEADER_MIN

/** Columns left for the menu inside the box walls (all of them when unframed). */
export const innerCols = (cols: number): number => (framed(cols) ? cols - WALLS : cols)

/** The fixed two-line header box: title (and version) in the top edge, the fire
 *  serpent as the bottom edge. Every line is exactly `cols` code points; below
 *  HEADER_MIN cols there is no header. */
export const headerBox = (cols: number, version: string | null): string[] => {
  if (cols < HEADER_MIN) return []
  const tail = version !== null ? ` ${version} ━┓` : '━┓'
  const fits = (title: string, end: string) => 4 + title.length + 1 + end.length + 1 <= cols
  const [title, end] = fits(HEADER_TITLE, tail)
    ? [HEADER_TITLE, tail]
    : fits(HEADER_TITLE_SHORT, tail)
      ? [HEADER_TITLE_SHORT, tail]
      : [HEADER_TITLE_SHORT, '━┓']
  const head = `┏━━ ${title} `
  const top = head + '━'.repeat(Math.max(0, cols - head.length - end.length)) + end
  const bottom = `┗${dragonRule(cols - 3)}━┛`
  return [top, bottom]
}

export type Row = {
  readonly label: string
  readonly value: string
  readonly hot?: boolean
}

export const nextActive = (current: TabId | null, pressed: TabId): TabId | null =>
  current === pressed ? null : pressed

export const truncate = (text: string, cols: number): string => {
  if (cols <= 0) return ''
  return text.length <= cols ? text : `${text.slice(0, cols - 1)}…`
}

export const isTabId = (value: unknown): value is TabId => TABS.some(tab => tab.id === value)

export const storedToActive = (stored: unknown): TabId | null =>
  stored === COLLAPSED ? null : isTabId(stored) ? stored : DEFAULT_ACTIVE

export const fmtDuration = (ms: number): string => {
  const minutes = Math.max(0, Math.floor(ms / 60000))
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  const mins = minutes % 60
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export const fmtAge = (minutes: number): string => {
  if (minutes < 60) return `${minutes}m`
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h`
  return `${Math.floor(minutes / 1440)}d`
}

/** A plain button draws `1: label` — the prefix as drawn counts in its width. */
export const tabWidth = (tab: Tab): number => tab.hotkey.length + 2 + tab.label.length

/** Columns before the tab at `index`: the tabs before it plus one gap each. */
export const tabOffset = (index: number): number =>
  TABS.slice(0, index).reduce((sum, tab) => sum + tabWidth(tab), index)

export const tabsWidth = (): number =>
  TABS.reduce((sum, tab) => sum + tabWidth(tab), 0) + TABS.length - 1

export const showHint = (cols: number): boolean => tabsWidth() + HINT_GAP + HINT.length <= cols

/** The `━` row under the active tab; null when collapsed. */
export const underline = (active: TabId | null): string | null => {
  if (active === null) return null
  const index = TABS.findIndex(tab => tab.id === active)
  const tab = TABS[index]
  if (tab === undefined) return null
  return `${' '.repeat(tabOffset(index))}${'━'.repeat(tabWidth(tab))}`
}

const reviewText = (review: string | null): string => {
  if (review === null) return 'unknown'
  if (review === 'stale') return 'stale'
  if (review === 'fail') return 'failed'
  if (review === 'pass') return 'passed'
  const who: string[] = []
  if (review.includes('ds')) who.push('ds')
  if (review.includes('glm')) who.push('glm')
  return who.length > 0 ? `passed (${who.join(' + ')})` : 'lockfile only — not reviewed'
}

export const codeRows = (info: CodeInfo): Row[] => {
  const branch = [info.branch ?? 'not a git repo']
  if (info.ahead > 0) branch.push(`${info.ahead} ahead`)
  if (info.behind > 0) branch.push(`${info.behind} behind`)

  return [
    { label: 'branch', value: branch.join(' · ') },
    { label: 'changes', value: info.dirty === 0 ? 'clean' : `${info.dirty} changed` },
    { label: 'review', value: reviewText(info.review) },
    {
      label: 'commit',
      value:
        info.lastCommit === null
          ? 'no commits'
          : `${info.lastCommit.sha} · ${fmtAge(info.lastCommit.ageMin)} ago · ${info.lastCommit.subject}`,
    },
  ]
}

export const ticketsRows = (info: TicketsInfo): Row[] => {
  const linear = info.linear
  const rows: Row[] = [
    {
      label: 'linear',
      value:
        linear === null
          ? 'no active ticket'
          : `${linear.id} · ${linear.phase}${linear.by !== null ? ` (${linear.by})` : ''} · ${fmtAge(linear.ageMin)} ago`,
    },
  ]

  const sprint = info.sprints[0]
  rows.push({
    label: 'sprint',
    value: sprint === undefined ? 'no open sprint' : `${sprint.name}  ${sprint.done} of ${sprint.total} done`,
  })

  const first = info.inProgress[0]
  if (first === undefined) {
    rows.push({ label: 'doing', value: 'nothing in progress' })
  } else {
    rows.push({ label: 'doing', value: `${first.ref} ${first.title}` })
    const second = info.inProgress[1]
    if (second !== undefined) rows.push({ label: '', value: `${second.ref} ${second.title}` })
  }

  if (rows.length < 4 && info.next !== null) rows.push({ label: 'next', value: `${info.next.ref} ${info.next.title}` })

  return rows
}

const windowRow = (label: string, pct: number | null, resetsAt: number | null, nowMs: number): Row | null => {
  if (pct === null) return null
  const parts = [`${pct}%`]
  if (resetsAt !== null) parts.push(`resets in ${fmtDuration(resetsAt - nowMs)}`)
  const hot = pct >= HOT_PCT
  if (hot) parts.push('hot')
  return { label, value: parts.join(' · '), hot: hot === true ? true : undefined }
}

export const claudeRows = (info: ClaudeInfo, nowMs: number): Row[] => {
  const rows: Row[] = []

  if (info.contextPct !== null) {
    const hot = info.contextPct >= HOT_PCT
    rows.push({
      label: 'context',
      value: hot ? `${info.contextPct}% used · hot` : `${info.contextPct}% used`,
      hot: hot === true ? true : undefined,
    })
  }
  const fiveHour = windowRow('5-hour', info.fiveHourPct, info.fiveHourResetsAt, nowMs)
  if (fiveHour !== null) rows.push(fiveHour)
  const week = windowRow('week', info.sevenDayPct, info.sevenDayResetsAt, nowMs)
  if (week !== null) rows.push(week)
  if (info.costUsd !== null) rows.push({ label: 'cost', value: `$${info.costUsd.toFixed(2)} this session` })

  return rows
}

export const overdriveRows = (info: OverdriveInfo): Row[] => [
  { label: 'version', value: info.version ?? 'unknown' },
  {
    label: 'snapshot',
    value:
      info.lastSnapshot === null
        ? 'no snapshot'
        : `${info.lastSnapshot.sha} · ${fmtAge(info.lastSnapshot.ageMin)} ago · ${info.lastSnapshot.subject}`,
  },
  {
    label: 'changes',
    value:
      info.uncommitted === null ? 'unknown' : info.uncommitted === 0 ? 'clean' : `${info.uncommitted} uncommitted`,
  },
  {
    label: 'log',
    value: info.warn === 0 && info.critical === 0 ? 'clean' : `${info.warn} warnings · ${info.critical} critical`,
  },
]

/** What the serpent's mood can see. `hotPct` is the highest of context, 5-hour and week. */
export type MoodInput = {
  readonly turns: number
  readonly tools: number
  readonly review: string | null
  readonly hotPct: number | null
  readonly warn: number
  readonly critical: number
  readonly dirty: number
}

/** The serpent's head (exactly 5 one-cell glyphs, like `(◣▾◢)`) and one mood word. */
export type Mood = { readonly face: string; readonly text: string }

export const MOODS = {
  fierce: { face: '(◣▾◢)', text: 'fierce' },
  happy: { face: '(◕▾◕)', text: 'happy' },
  hungry: { face: '(°▾°)', text: 'hungry — feed it a ticket' },
  sleepy: { face: '(-▾-)', text: 'sleepy' },
  panic: { face: '(⊙▾⊙)', text: 'panicking' },
  angry: { face: '(╬▾╬)', text: 'angry — review failed' },
} as const satisfies Record<string, Mood>

/** The serpent's mood: always fierce (Velimir, 2026-10-12). MoodInput stays for a later rule. */
export const serpentMood = (s: MoodInput): Mood => {
  void s
  return MOODS.fierce
}

export const FORTUNES: readonly string[] = [
  'the serpent approves of small diffs',
  'a green dual-review is worth two hot fixes',
  'today the lockfile sleeps. let it.',
  'ship on tuesday, never on friday',
  'every TODO is a promise to future you',
  'the cache lies. bump the version.',
  'tables were flipped so code could be fixed  ┬─┬ノ( º _ºノ)',
  'read the log before you blame the model',
]

export const fortune = (turns: number): string => FORTUNES[turns % FORTUNES.length] ?? ''

/** The serpent: tail, one `∿` per turn (capped to `cols`), the mood's head, fire. */
export const serpentLine = (turns: number, face: string, cols: number): string => {
  const head = `${face}⟫≋✶`
  const room = Math.max(0, cols - DRAGON_TAIL.length - head.length)
  return DRAGON_TAIL + DRAGON_BODY.repeat(Math.min(Math.max(1, turns), room)) + head
}

export const serpentRows = (info: SerpentInfo, mood: Mood, cols: number): Row[] => [
  { label: 'serpent', value: serpentLine(info.turns, mood.face, cols - LABEL_COLS) },
  { label: 'mood', value: mood.text },
  { label: 'fed', value: `${info.turns} turns · ${info.tools} tools` },
  { label: 'fortune', value: fortune(info.turns) },
]
