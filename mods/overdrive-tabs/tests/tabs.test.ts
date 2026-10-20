import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import type { ClaudeInfo, CodeInfo, OverdriveInfo, TicketsInfo } from '../types'
import {
  DRAGON_ACCENT,
  MOODS,
  TABS,
  WALL_LEFT,
  WALL_RIGHT,
  claudeRows,
  codeRows,
  dragonRule,
  headerBox,
  innerCols,
  fmtAge,
  fmtDuration,
  nextActive,
  overdriveRows,
  serpentLine,
  serpentRows,
  showHint,
  storedToActive,
  tabOffset,
  tabWidth,
  tabsWidth,
  ticketsRows,
  truncate,
  underline,
} from '../hooks/tabs'

const CODE: CodeInfo = {
  branch: 'feat/odt-3',
  dirty: 3,
  ahead: 1,
  behind: 2,
  review: 'ds✓ glm✓ pass',
  lastCommit: { sha: 'a1b2c3d', subject: 'ODT-3: wire collectors', ageMin: 42 },
}

const TICKETS: TicketsInfo = {
  linear: { id: 'ODT-812', phase: 'build', by: 'opus', ageMin: 130 },
  sprints: [{ id: 22, name: 'overdrive — status tabs mod', done: 1, total: 4 }],
  inProgress: [
    { ref: 'ODT-3', title: 'Wire collectors' },
    { ref: 'ODT-2', title: 'Collectors' },
    { ref: 'ODT-1', title: 'Tab band skeleton' },
  ],
  next: { ref: 'ODT-4', title: 'Install mod' },
}

const CLAUDE: ClaudeInfo = {
  contextPct: 43,
  fiveHourPct: 62,
  fiveHourResetsAt: 90 * 60000,
  sevenDayPct: 31,
  sevenDayResetsAt: (2 * 1440 + 180) * 60000,
  costUsd: 12.5,
}

const OVERDRIVE: OverdriveInfo = {
  version: '1.7.2',
  lastSnapshot: { sha: 'f714e33', subject: 'ODT-1: tab band skeleton', ageMin: 184 },
  uncommitted: 2,
  warn: 1,
  critical: 0,
}

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 4,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 3 },
  view: {},
} as const

const stubState = (on: On, values: Readonly<Record<string, unknown>>): void => {
  on('state.get', ($, e, next) => {
    if (e.plugin === 'overdrive-tabs' && e.key in values) {
      return { value: { value: values[e.key], version: 1 } }
    }
    return next(e)
  })
}

const childText = (element: unknown): string => {
  if (typeof element === 'string') return element
  const record = element as { children?: unknown[] } | null
  if (record === null || typeof record !== 'object') return ''
  return (record.children ?? []).map(childText).join('')
}

const hasBoldChild = (element: { children?: unknown[] } | undefined): boolean =>
  (element?.children ?? []).some(
    child => (child as { props?: { bold?: unknown } } | null)?.props?.bold === true,
  )

test('nextActive switches tabs and closes the active one', () => {
  expect(nextActive('code', 'claude')).toBe('claude')
  expect(nextActive(null, 'overdrive')).toBe('overdrive')
  expect(nextActive('claude', 'claude')).toBeNull()
  expect(nextActive('code', 'code')).toBeNull()
})

test('truncate keeps what fits and cuts the rest with …', () => {
  expect(truncate('abc', 5)).toBe('abc')
  expect(truncate('abc', 3)).toBe('abc')
  expect(truncate('abcdef', 5)).toBe('abcd…')
  expect(truncate('abcdef', 1)).toBe('…')
  expect(truncate('abc', 0)).toBe('')
})

test('storedToActive defaults a first run to code', () => {
  expect(storedToActive(null)).toBe('code')
  expect(storedToActive(undefined)).toBe('code')
  expect(storedToActive('bogus')).toBe('code')
  expect(storedToActive(42)).toBe('code')
})

test('storedToActive maps none to collapsed and keeps known tabs', () => {
  expect(storedToActive('none')).toBeNull()
  expect(storedToActive('code')).toBe('code')
  for (const tab of TABS) expect(storedToActive(tab.id)).toBe(tab.id)
})

test('fmtDuration renders whole minutes, hours and days', () => {
  expect(fmtDuration(0)).toBe('0m')
  expect(fmtDuration(59 * 1000)).toBe('0m')
  expect(fmtDuration(45 * 60000)).toBe('45m')
  expect(fmtDuration(60 * 60000)).toBe('1h 0m')
  expect(fmtDuration(90 * 60000)).toBe('1h 30m')
  expect(fmtDuration((2 * 1440 + 180) * 60000)).toBe('2d 3h')
  expect(fmtDuration(-5000)).toBe('0m')
})

test('fmtAge renders minutes, hours and days', () => {
  expect(fmtAge(0)).toBe('0m')
  expect(fmtAge(5)).toBe('5m')
  expect(fmtAge(59)).toBe('59m')
  expect(fmtAge(60)).toBe('1h')
  expect(fmtAge(1439)).toBe('23h')
  expect(fmtAge(1440)).toBe('1d')
  expect(fmtAge(4325)).toBe('3d')
})

test('tab geometry counts the 1: prefix and one gap per tab before it', () => {
  for (const tab of TABS) {
    expect(tabWidth(tab)).toBe(tab.hotkey.length + 2 + tab.label.length)
  }
  expect(tabsWidth()).toBe(52)
  expect(tabOffset(0)).toBe(0)
  expect(tabOffset(1)).toBe(8)
  expect(tabOffset(2)).toBe(19)
  expect(tabOffset(3)).toBe(29)
  expect(tabOffset(4)).toBe(42)
})

test('underline sits under the active tab and disappears when collapsed', () => {
  expect(underline('code')).toBe('━'.repeat(7))
  expect(underline('tickets')).toBe(`${' '.repeat(8)}${'━'.repeat(10)}`)
  expect(underline('claude')).toBe(`${' '.repeat(19)}${'━'.repeat(9)}`)
  expect(underline('overdrive')).toBe(`${' '.repeat(29)}${'━'.repeat(12)}`)
  expect(underline('serpent')).toBe(`${' '.repeat(42)}${'━'.repeat(10)}`)
  expect(underline(null)).toBeNull()
})

test('showHint needs room for tabs, gap and hint', () => {
  expect(showHint(96)).toBe(true)
  expect(showHint(83)).toBe(true)
  expect(showHint(82)).toBe(false)
})

test('innerCols leaves room for the two box walls', () => {
  expect(innerCols(100)).toBe(96)
  expect(innerCols(20)).toBe(16)
  expect(innerCols(19)).toBe(19)
})

test('dragonRule spans exactly cols code points, tail first, head last', () => {
  const HEAD = '(◣▾◢)⟫≋≋≋✶'
  for (const cols of [20, 21, 40, 80]) {
    const line = dragonRule(cols)
    expect([...line].length).toBe(cols)
    expect(line.startsWith('⸌')).toBe(true)
    expect(line.endsWith(HEAD)).toBe(true)
  }
  expect(dragonRule(20)).toBe(`⸌${'∿'.repeat(9)}${HEAD}`)
  expect(dragonRule(21)).toBe(`⸌${'∿'.repeat(10)}${HEAD}`)
  expect(dragonRule(40)).toBe(`⸌${'∿'.repeat(29)}${HEAD}`)
  expect(dragonRule(80)).toBe(`⸌${'∿'.repeat(69)}${HEAD}`)
})

test('dragonRule drops the head below 14 cols and draws nothing below 1', () => {
  expect(dragonRule(13)).toBe(`⸌${'∿'.repeat(12)}`)
  expect([...dragonRule(13)].length).toBe(13)
  expect(dragonRule(14)).toBe(`⸌${'∿'.repeat(3)}(◣▾◢)⟫≋≋≋✶`)
  expect(dragonRule(2)).toBe('⸌∿')
  expect(dragonRule(1)).toBe('⸌')
  expect(dragonRule(0)).toBe('')
  expect(dragonRule(-5)).toBe('')
})

test('headerBox draws two lines of exactly cols code points', () => {
  for (const cols of [20, 30, 45, 80, 140]) {
    for (const version of [null, '1.8.0']) {
      const lines = headerBox(cols, version)
      expect(lines.length).toBe(2)
      for (const line of lines) expect([...line].length).toBe(cols)
      expect(lines[0]?.startsWith('┏━━ ')).toBe(true)
      expect(lines[0]?.endsWith('━┓')).toBe(true)
      expect(lines[1]?.startsWith('┗⸌')).toBe(true)
      expect(lines[1]?.endsWith('━┛')).toBe(true)
    }
  }
  expect(headerBox(80, '1.8.0')[0]).toContain('O V E R D R I V E')
  expect(headerBox(80, '1.8.0')[0]).toContain(' 1.8.0 ━┓')
  expect(headerBox(80, '1.8.0')[1]).toContain('(◣▾◢)⟫≋≋≋✶')
  expect(headerBox(30, '1.8.0')[0]).toContain('⏣ OVERDRIVE')
  expect(headerBox(19, null)).toEqual([])
})

test('codeRows renders branch, changes, review and last commit', () => {
  expect(codeRows(CODE)).toEqual([
    { label: 'branch', value: 'feat/odt-3 · 1 ahead · 2 behind' },
    { label: 'changes', value: '3 changed' },
    { label: 'review', value: 'passed (ds + glm)' },
    { label: 'commit', value: 'a1b2c3d · 42m ago · ODT-3: wire collectors' },
  ])
})

test('codeRows drops ahead/behind when zero and words the empty case', () => {
  expect(
    codeRows({ ...CODE, dirty: 0, ahead: 0, behind: 0, review: null, branch: null, lastCommit: null }),
  ).toEqual([
    { label: 'branch', value: 'not a git repo' },
    { label: 'changes', value: 'clean' },
    { label: 'review', value: 'unknown' },
    { label: 'commit', value: 'no commits' },
  ])
})

test('codeRows words every review status', () => {
  const review = (r: string) => codeRows({ ...CODE, review: r })[2]?.value
  expect(review('stale')).toBe('stale')
  expect(review('fail')).toBe('failed')
  expect(review('lock✓ pass')).toBe('lockfile only — not reviewed')
  expect(review('ds✓ pass')).toBe('passed (ds)')
})

test('ticketsRows renders linear phase, sprint and two doing rows', () => {
  expect(ticketsRows(TICKETS)).toEqual([
    { label: 'linear', value: 'ODT-812 · build (opus) · 2h ago' },
    { label: 'sprint', value: 'overdrive — status tabs mod  1 of 4 done' },
    { label: 'doing', value: 'ODT-3 Wire collectors' },
    { label: '', value: 'ODT-2 Collectors' },
  ])
})

test('ticketsRows shows the next TODO when a row is free and words the empty case', () => {
  expect(ticketsRows({ ...TICKETS, inProgress: [] })[3]).toEqual({ label: 'next', value: 'ODT-4 Install mod' })
  expect(ticketsRows({ linear: null, sprints: [], inProgress: [], next: null })).toEqual([
    { label: 'linear', value: 'no active ticket' },
    { label: 'sprint', value: 'no open sprint' },
    { label: 'doing', value: 'nothing in progress' },
  ])
})

test('serpentLine grows one ∿ per turn and never overflows its columns', () => {
  expect(serpentLine(0, '(◣▾◢)', 40)).toBe('⸌∿(◣▾◢)⟫≋✶')
  expect(serpentLine(3, '(◕▾◕)', 40)).toBe('⸌∿∿∿(◕▾◕)⟫≋✶')
  expect([...serpentLine(500, '(◣▾◢)', 30)].length).toBe(30)
})

test('serpentRows draws the pet, its mood, what it ate and a fortune', () => {
  const rows = serpentRows({ turns: 2, tools: 9 }, MOODS.happy, 60)
  expect(rows.map(r => r.label)).toEqual(['serpent', 'mood', 'fed', 'fortune'])
  expect(rows[0]?.value).toBe('⸌∿∿(◕▾◕)⟫≋✶')
  expect(rows[1]?.value).toBe('happy')
  expect(rows[2]?.value).toBe('2 turns · 9 tools')
})

test('claudeRows renders labelled usage rows with resets and cost', () => {
  expect(claudeRows(CLAUDE, 0)).toEqual([
    { label: 'context', value: '43% used' },
    { label: '5-hour', value: '62% · resets in 1h 30m' },
    { label: 'week', value: '31% · resets in 2d 3h' },
    { label: 'cost', value: '$12.50 this session' },
  ])
})

test('claudeRows omits null rows and yields nothing when all null', () => {
  expect(claudeRows({ ...CLAUDE, fiveHourResetsAt: null, costUsd: null }, 0)).toEqual([
    { label: 'context', value: '43% used' },
    { label: '5-hour', value: '62%' },
    { label: 'week', value: '31% · resets in 2d 3h' },
  ])
  expect(
    claudeRows(
      {
        contextPct: null,
        fiveHourPct: null,
        fiveHourResetsAt: null,
        sevenDayPct: null,
        sevenDayResetsAt: null,
        costUsd: null,
      },
      0,
    ),
  ).toEqual([])
})

test('claudeRows marks a window at or past 85 % as hot', () => {
  const rows = claudeRows({ ...CLAUDE, fiveHourPct: 87, fiveHourResetsAt: 45 * 60000 }, 0)
  expect(rows).toEqual([
    { label: 'context', value: '43% used' },
    { label: '5-hour', value: '87% · resets in 45m · hot', hot: true },
    { label: 'week', value: '31% · resets in 2d 3h' },
    { label: 'cost', value: '$12.50 this session' },
  ])
  expect(claudeRows({ ...CLAUDE, contextPct: 85 }, 0)[0]?.value).toBe('85% used · hot')
})

test('overdriveRows renders version, snapshot, changes and log rows', () => {
  expect(overdriveRows(OVERDRIVE)).toEqual([
    { label: 'version', value: '1.7.2' },
    { label: 'snapshot', value: 'f714e33 · 3h ago · ODT-1: tab band skeleton' },
    { label: 'changes', value: '2 uncommitted' },
    { label: 'log', value: '1 warnings · 0 critical' },
  ])
  expect(overdriveRows({ ...OVERDRIVE, uncommitted: 0, warn: 0, critical: 0 })).toEqual([
    { label: 'version', value: '1.7.2' },
    { label: 'snapshot', value: 'f714e33 · 3h ago · ODT-1: tab band skeleton' },
    { label: 'changes', value: 'clean' },
    { label: 'log', value: 'clean' },
  ])
})

test('first draw shows a dim loading row, the hint and the underline on terminal', async ($, on) => {
  mock.store(on)

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  const loading = await ui.find({ type: 'Text', text: 'loading…' })
  expect(loading).toBeDefined()
  expect(loading?.props.dimColor).toBe(true)

  const hint = await ui.find({ type: 'Text', text: 'click or ctrl+x tab → 1-5' })
  expect(hint?.props.dimColor).toBe(true)

  expect(await ui.find({ type: 'Text', text: '━'.repeat(7) })).toBeDefined()

  await ui.unmount()
})

test('the box wraps the menu: title edge first, walls on every row, serpent edge last', async ($, on) => {
  mock.store(on)
  stubState(on, { code: CODE })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  const [top, bottom] = headerBox(100, null)
  expect(await ui.find({ type: 'Text', text: top })).toBeDefined()
  const dragon = await ui.find({ type: 'Text', text: bottom })
  expect(dragon).toBeDefined()
  expect(dragon?.props.color).toBe(DRAGON_ACCENT)
  expect(dragon?.props.dimColor).not.toBe(true)

  const drawn = (await ui.drawn()) as { children?: unknown[] } | null
  const children = (drawn?.children ?? []) as { type?: string; props?: { color?: string } }[]
  expect(children[0]?.type).toBe('Text')
  expect(children[0]?.props?.color).toBe(DRAGON_ACCENT)
  expect(childText(children[children.length - 1])).toBe(bottom)
  const walls = await ui.findAll({ type: 'Text', text: WALL_LEFT })
  expect(walls.length).toBe((await ui.findAll({ type: 'Text', text: WALL_RIGHT })).length)
  expect(walls.length).toBe(2 + 4)
  expect(children.length).toBe(1 + 2 + 4 + 1)
  for (const wall of walls) expect(wall.props.color).toBe(DRAGON_ACCENT)

  await ui.press({ key: 'tab-code' })

  expect(await ui.find({ type: 'Text', text: 'collapsed — press a tab to open' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: top })).toBeDefined()
  const collapsedDragon = await ui.find({ type: 'Text', text: bottom })
  expect(collapsedDragon).toBeDefined()
  expect(collapsedDragon?.props.color).toBe(DRAGON_ACCENT)

  await ui.unmount()
})

test('code body draws labelled rows on terminal and truncates inside the walls', async ($, on) => {
  mock.store(on)
  stubState(on, { code: CODE })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  const label = await ui.find({ type: 'Text', text: 'branch' })
  expect(label?.props.dimColor).toBe(true)
  expect(await ui.find({ type: 'Text', text: 'feat/odt-3 · 1 ahead · 2 behind' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'passed (ds + glm)' })).toBeDefined()

  await ui.redraw({ ...BAND, bodyColumns: 24 })
  expect(await ui.find({ type: 'Text', text: 'feat/odt-3 …' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'click or ctrl+x tab → 1-5' })).toBeUndefined()

  await ui.unmount()
})

test('tickets body draws the linear phase and code-context tickets', async ($, on) => {
  mock.store(on)
  stubState(on, { tickets: TICKETS, active: 'tickets' })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  expect(await ui.find({ type: 'Text', text: 'ODT-812 · build (opus) · 2h ago' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'ODT-3 Wire collectors' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'ODT-2 Collectors' })).toBeDefined()

  await ui.unmount()
})

test('serpent body draws the pet with the counters it was fed', async ($, on) => {
  mock.store(on)
  stubState(on, { serpent: { turns: 3, tools: 12 }, active: 'serpent' })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  expect(await ui.find({ type: 'Text', text: /^⸌∿∿∿\(.▾.\)⟫≋✶$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '3 turns · 12 tools' })).toBeDefined()

  await ui.unmount()
})

test('claude body draws usage rows and a red hot window on terminal', async ($, on) => {
  mock.store(on)
  stubState(on, { claude: CLAUDE, active: 'claude' })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  expect(await ui.find({ type: 'Text', text: '43% used' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '62% · resets in 1h 30m' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '31% · resets in 2d 3h' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '$12.50 this session' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: `${' '.repeat(19)}${'━'.repeat(9)}` })).toBeDefined()

  await ui.unmount()
})

test('a window at 85 % draws hot in red on terminal', async ($, on) => {
  mock.store(on)
  stubState(on, {
    claude: { ...CLAUDE, fiveHourPct: 87, fiveHourResetsAt: 45 * 60000 },
    active: 'claude',
  })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  const hot = await ui.find({ type: 'Text', text: '87% · resets in 45m · hot' })
  expect(hot).toBeDefined()
  expect(hot?.props.color).toBe('red')

  await ui.unmount()
})

test('overdrive body draws version, snapshot, changes and log on terminal', async ($, on) => {
  mock.store(on)
  stubState(on, { overdrive: OVERDRIVE, active: 'overdrive' })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  expect(await ui.find({ type: 'Text', text: 'f714e33 · 3h ago · ODT-1: tab band skeleton' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '2 uncommitted' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '1 warnings · 0 critical' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: `${' '.repeat(29)}${'━'.repeat(12)}` })).toBeDefined()

  await ui.unmount()
})

test('band switches tabs, bolds the active one and collapses on terminal', async ($, on) => {
  mock.store(on)
  stubState(on, { code: CODE })

  const ui = await $.ui.mount({
    plugin: 'overdrive-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND,
  })

  const codeTab = await ui.find({ key: 'tab-code' })
  expect(codeTab?.props.dimColor).not.toBe(true)
  expect(hasBoldChild(codeTab)).toBe(true)
  expect(codeTab?.props.plain).toBe(true)
  expect(codeTab?.props.hotkey).toBe('1')
  expect(childText(codeTab)).toBe('code')

  await ui.press({ key: 'tab-claude' })

  const claudeTab = await ui.find({ key: 'tab-claude' })
  expect(claudeTab?.props.dimColor).not.toBe(true)
  expect(hasBoldChild(claudeTab)).toBe(true)
  expect((await ui.find({ key: 'tab-code' }))?.props.dimColor).toBe(true)
  expect(await ui.find({ type: 'Text', text: 'passed (ds + glm)' })).toBeUndefined()

  await ui.press({ key: 'tab-claude' })

  const collapsed = await ui.find({ type: 'Text', text: 'collapsed — press a tab to open' })
  expect(collapsed).toBeDefined()
  expect(collapsed?.props.dimColor).toBe(true)
  for (const tab of TABS) expect(await ui.findAll({ type: 'Text', text: new RegExp(`^${underline(tab.id)}$`) })).toHaveLength(0)
  const collapsedRows = ((await ui.drawn()) as { children?: unknown[] } | null)?.children ?? []
  expect(collapsedRows.length).toBe(1 + 2 + 4 + 1)

  await ui.unmount()
})
