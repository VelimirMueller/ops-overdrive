import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren } from 'claude-code'

import type { ClaudeInfo, CodeInfo, OverdriveInfo, TabId, TicketsInfo } from '../types'
import {
  ageMinutes,
  countLevels,
  parseGitLog,
  parseGitStatus,
  parseInProgress,
  parsePhaseFile,
  parseReviewStatus,
  parseSprints,
} from './collect'
import {
  BODY_ROWS,
  COLLAPSED,
  DRAGON_ACCENT,
  HINT,
  LABEL_COLS,
  TABS,
  WALL_LEFT,
  WALL_RIGHT,
  claudeRows,
  codeRows,
  framed,
  headerBox,
  innerCols,
  nextActive,
  overdriveRows,
  serpentMood,
  serpentRows,
  showHint,
  storedToActive,
  ticketsRows,
  truncate,
  underline,
} from './tabs'
import type { Row, Tab } from './tabs'

const STORE_KEY = 'overdrive-tabs.active'

const SPRINTS_SQL =
  "select s.id, s.name, sum(t.status='DONE') done, count(t.id) total " +
  'from sprints s left join tickets t on t.sprint_id=s.id and t.deleted_at is null ' +
  'where s.deleted_at is null and s.archived_at is null ' +
  "and s.status not in ('closed','done') group by s.id order by s.id desc limit 3"

const IN_PROGRESS_SQL =
  "select ticket_ref ref, title from tickets where status='IN_PROGRESS' and deleted_at is null " +
  'order by updated_at desc limit 3'

const NEXT_SQL =
  "select t.ticket_ref ref, t.title from tickets t join sprints s on s.id=t.sprint_id " +
  "where t.status='TODO' and t.deleted_at is null and s.deleted_at is null and s.archived_at is null " +
  "and s.status not in ('closed','done') order by s.id desc, t.priority, t.id limit 1"

/** Tool calls after which the code and tickets tabs read their data again. */
const REFRESHING_TOOL = /^(Bash|Edit|Write|NotebookEdit|mcp__code-context__.+)$/

export const activeAtom = atom({ plugin: 'overdrive-tabs', key: 'active' } as const, 'code')
export const codeAtom = atom({ plugin: 'overdrive-tabs', key: 'code' } as const, null)
export const ticketsAtom = atom({ plugin: 'overdrive-tabs', key: 'tickets' } as const, null)
export const serpentAtom = atom({ plugin: 'overdrive-tabs', key: 'serpent' } as const, { turns: 0, tools: 0 })
export const claudeAtom = atom({ plugin: 'overdrive-tabs', key: 'claude' } as const, null)
export const overdriveAtom = atom({ plugin: 'overdrive-tabs', key: 'overdrive' } as const, null)

let nowMs = 0

function toEpochMs(iso?: string): number | null {
  if (!iso) return null
  const ms = Date.parse(iso)
  return Number.isNaN(ms) ? null : ms
}

async function collectCode($: EngineInterface): Promise<CodeInfo> {
  const info: CodeInfo = {
    branch: null,
    dirty: 0,
    ahead: 0,
    behind: 0,
    review: null,
    lastCommit: null,
  }

  try {
    const git = await $.process.run(['git', 'status', '--porcelain=v2', '--branch'])
    if (git.exitCode === 0) {
      const status = parseGitStatus(git.stdout)
      info.branch = status.branch
      info.dirty = status.dirty
      info.ahead = status.ahead
      info.behind = status.behind
    }
  } catch {
    // not a repo, or git missing: keep nulls/zeros
  }

  try {
    const dr = await $.process.run(['dual-review', '--status'])
    info.review = parseReviewStatus(dr.stdout.split('\n')[0] ?? '')
  } catch {
    info.review = null
  }

  try {
    const log = await $.process.run(['git', 'log', '-1', '--format=%h%x1f%s%x1f%ct'])
    const row = log.exitCode === 0 ? parseGitLog(log.stdout.split('\n')[0] ?? '') : null
    if (row) info.lastCommit = { sha: row.sha, subject: row.subject, ageMin: ageMinutes(row.ct, nowMs) }
  } catch {
    info.lastCommit = null
  }

  return info
}

/** Newest `tix phase` file whose phase is not `done`; null when there is none. */
async function activeLinear($: EngineInterface, home: string): Promise<TicketsInfo['linear']> {
  const dir = `${home}/.claude/.statusline-cache/tix`
  const ls = await $.process.run(['ls', '-t', dir])
  if (ls.exitCode !== 0) return null
  const files = ls.stdout.split('\n').filter(f => /^phase-.+\.json$/.test(f)).slice(0, 5)
  const phases = await Promise.all(
    files.map(file => $.fs.read(`${dir}/${file}`).then(parsePhaseFile, () => null)),
  )
  const phase = phases.find(p => p !== null && p.phase !== 'done')
  if (phase == null) return null
  return { id: phase.id, phase: phase.phase, by: phase.by, ageMin: Math.max(0, Math.floor((nowMs - phase.atMs) / 60000)) }
}

async function collectTickets($: EngineInterface): Promise<TicketsInfo> {
  const info: TicketsInfo = { linear: null, sprints: [], inProgress: [], next: null }

  const home = await $.env.get('HOME').catch(() => undefined)
  if (!home) return info

  try {
    info.linear = await activeLinear($, home)
  } catch {
    info.linear = null
  }

  try {
    const db = `${home}/Desktop/Workspace/mcp-servers/data/context.db`
    const [sprintsRes, inProgressRes, nextRes] = await Promise.all([
      $.process.run(['sqlite3', '-readonly', '-json', db, SPRINTS_SQL]),
      $.process.run(['sqlite3', '-readonly', '-json', db, IN_PROGRESS_SQL]),
      $.process.run(['sqlite3', '-readonly', '-json', db, NEXT_SQL]),
    ])
    if (sprintsRes.exitCode === 0) info.sprints = parseSprints(sprintsRes.stdout)
    if (inProgressRes.exitCode === 0) info.inProgress = parseInProgress(inProgressRes.stdout)
    if (nextRes.exitCode === 0) info.next = parseInProgress(nextRes.stdout)[0] ?? null
  } catch {
    // missing DB or sqlite3: keep empty arrays
  }

  return info
}

async function collectClaude($: EngineInterface): Promise<ClaudeInfo> {
  const info: ClaudeInfo = {
    contextPct: null,
    fiveHourPct: null,
    fiveHourResetsAt: null,
    sevenDayPct: null,
    sevenDayResetsAt: null,
    costUsd: null,
  }

  try {
    const usage = await $.session.usage()
    info.contextPct = usage.context.percent ?? null
    info.costUsd = usage.cost?.usd ?? null
    for (const rl of usage.rateLimits) {
      if (rl.kind === 'five_hour') {
        info.fiveHourPct = rl.percentUsed
        info.fiveHourResetsAt = toEpochMs(rl.resetsAt)
      } else if (rl.kind === 'seven_day') {
        info.sevenDayPct = rl.percentUsed
        info.sevenDayResetsAt = toEpochMs(rl.resetsAt)
      }
    }
  } catch {
    // keep nulls
  }

  return info
}

async function collectOverdrive($: EngineInterface): Promise<OverdriveInfo> {
  const info: OverdriveInfo = {
    version: null,
    lastSnapshot: null,
    uncommitted: null,
    warn: 0,
    critical: 0,
  }

  let home: string | undefined
  try {
    home = await $.env.get('HOME')
  } catch {
    home = undefined
  }
  if (!home) return info

  const claudeDir = `${home}/.claude`

  try {
    const version = await $.fs.read(`${claudeDir}/VERSION`)
    info.version = version.trim() || null
  } catch {
    info.version = null
  }

  try {
    const log = await $.process.run([
      'git',
      '-C',
      claudeDir,
      'log',
      '-1',
      '--format=%h%x1f%s%x1f%ct',
    ])
    if (log.exitCode === 0) {
      const row = parseGitLog(log.stdout.split('\n')[0] ?? '')
      if (row) {
        info.lastSnapshot = { sha: row.sha, subject: row.subject, ageMin: ageMinutes(row.ct, nowMs) }
      }
    }
  } catch {
    info.lastSnapshot = null
  }

  try {
    const status = await $.process.run(['git', '-C', claudeDir, 'status', '--porcelain'])
    if (status.exitCode === 0) {
      info.uncommitted = status.stdout.split('\n').filter(l => l.trim() !== '').length
    }
  } catch {
    info.uncommitted = null
  }

  try {
    const sessionId = await $.session.id()
    const logPath = `${claudeDir}/.local_ai_setup_logs/sessions/${sessionId}.log`
    const log = await $.fs.read(logPath)
    const counts = countLevels(log)
    info.warn = counts.warn
    info.critical = counts.critical
  } catch {
    // missing/unreadable log: keep 0/0
  }

  return info
}

/** Read one tab's data again. The serpent has no collector: its counters move on events. */
async function refresh($: EngineInterface, tab: TabId): Promise<void> {
  const tick = await $.clock.now().catch(() => null)
  if (tick !== null) nowMs = tick

  try {
    if (tab === 'code') {
      const info = await collectCode($)
      await update($, codeAtom, () => info)
    } else if (tab === 'tickets') {
      const info = await collectTickets($)
      await update($, ticketsAtom, () => info)
    } else if (tab === 'claude') {
      const info = await collectClaude($)
      await update($, claudeAtom, () => info)
    } else if (tab === 'overdrive') {
      const info = await collectOverdrive($)
      await update($, overdriveAtom, () => info)
    }
  } catch {
    return
  }
}

async function bodyRows($: EngineInterface, current: TabId | null, cols: number): Promise<Row[] | null> {
  if (current === 'code') {
    const info = await read($, codeAtom)
    return info === null ? null : codeRows(info)
  }
  if (current === 'tickets') {
    const info = await read($, ticketsAtom)
    return info === null ? null : ticketsRows(info)
  }
  if (current === 'claude') {
    const info = await read($, claudeAtom)
    return info === null ? null : claudeRows(info, nowMs)
  }
  if (current === 'overdrive') {
    const info = await read($, overdriveAtom)
    return info === null ? null : overdriveRows(info)
  }
  if (current === 'serpent') {
    const [pet, code, claude, overdrive] = await Promise.all([
      read($, serpentAtom),
      read($, codeAtom),
      read($, claudeAtom),
      read($, overdriveAtom),
    ])
    const pcts = [claude?.contextPct, claude?.fiveHourPct, claude?.sevenDayPct].filter(
      (p): p is number => typeof p === 'number',
    )
    const mood = serpentMood({
      turns: pet.turns,
      tools: pet.tools,
      review: code?.review ?? null,
      hotPct: pcts.length > 0 ? Math.max(...pcts) : null,
      warn: overdrive?.warn ?? 0,
      critical: overdrive?.critical ?? 0,
      dirty: code?.dirty ?? 0,
    })
    return serpentRows(pet, mood, cols)
  }
  return null
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const stored = await $.store.get(STORE_KEY)
    const value = storedToActive(stored)
    await update($, activeAtom, () => value)

    await Promise.all(TABS.map(tab => refresh($, tab.id)))

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await update($, serpentAtom, pet => ({ ...pet, turns: pet.turns + 1 }))
    await Promise.all([refresh($, 'code'), refresh($, 'tickets'), refresh($, 'overdrive')])

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const result = await next(e)

    try {
      await update($, serpentAtom, pet => ({ ...pet, tools: pet.tools + 1 }))
      if (REFRESHING_TOOL.test(e.tool)) await Promise.all([refresh($, 'code'), refresh($, 'tickets')])
    } catch {
      // bookkeeping only: never fail or repeat the tool call over it
    }

    return result
  }).catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    await refresh($, 'claude')

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }

    const cols = e.props.bodyColumns
    const inner = innerCols(cols)
    const current = await read($, activeAtom)
    const rows = await bodyRows($, current, inner)
    const { Box, Button, Text } = $.ui.resolve(e)

    const press = (tab: Tab) => async () => {
      const value = await update($, activeAtom, now => nextActive(now, tab.id))

      await $.store.set(STORE_KEY, value === null ? COLLAPSED : value)
      await refresh($, tab.id)
    }

    const mark = underline(current)
    const version = (await read($, overdriveAtom))?.version ?? null
    const [top, bottom] = headerBox(cols, version)
    const walled = framed(cols)

    /** One menu row: inside the box walls when framed, bare otherwise. */
    const wall = (key: string, content: RenderChildren) =>
      walled ? (
        <Box key={key}>
          <Text color={DRAGON_ACCENT}>{WALL_LEFT}</Text>
          <Box width={inner}>{content}</Box>
          <Text color={DRAGON_ACCENT}>{WALL_RIGHT}</Text>
        </Box>
      ) : (
        <Box key={key}>{content}</Box>
      )

    const tabs = (
      <Box columnGap={1}>
        {TABS.map(tab => (
          <Button
            key={tab.key}
            label={tab.label}
            hotkey={tab.hotkey}
            plain
            dimColor={current !== tab.id}
            onPress={press(tab)}
          >
            {current === tab.id ? <Text bold>{tab.label}</Text> : tab.label}
          </Button>
        ))}
        {showHint(inner) && <Text dimColor>{' '.repeat(5) + HINT}</Text>}
      </Box>
    )

    const body =
      current === null
        ? [wall('body-collapsed', <Text dimColor>collapsed — press a tab to open</Text>)]
        : rows === null || rows.length === 0
          ? [wall('body-loading', <Text dimColor>loading…</Text>)]
          : rows.map((row, index) =>
              wall(
                `body-${index}`,
                <Box>
                  <Text dimColor>{truncate(row.label.padEnd(LABEL_COLS), inner)}</Text>
                  <Text color={row.hot === true ? 'red' : undefined}>
                    {truncate(row.value, inner - LABEL_COLS)}
                  </Text>
                </Box>,
              ),
            )
    const filler = Array.from({ length: Math.max(0, BODY_ROWS - body.length) }, (_, index) =>
      wall(`body-fill-${index}`, <Text> </Text>),
    )

    return (
      <Box flexDirection="column">
        {top !== undefined && <Text color={DRAGON_ACCENT}>{top}</Text>}
        {wall('tabs', tabs)}
        {wall('mark', <Text>{mark ?? ' '}</Text>)}
        {body}
        {filler}
        {bottom !== undefined && <Text color={DRAGON_ACCENT}>{bottom}</Text>}
      </Box>
    )
  })
}
