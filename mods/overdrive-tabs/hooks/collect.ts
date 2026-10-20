export type GitStatus = {
  branch: string | null
  dirty: number
  ahead: number
  behind: number
}

export type SprintRow = { id: number; name: string; done: number; total: number }
export type InProgressRow = { ref: string; title: string }
export type GitLogRow = { sha: string; subject: string; ct: number }

export function parseGitStatus(porcelainV2Branch: string): GitStatus {
  let branch: string | null = null
  let ahead = 0
  let behind = 0
  let dirty = 0

  for (const line of porcelainV2Branch.split('\n')) {
    if (line.startsWith('#')) {
      const head = /^# branch\.head (.+)$/.exec(line)
      if (head) {
        branch = head[1] === '(detached)' ? null : (head[1] ?? null)
      }
      const ab = /^# branch\.ab \+(\d+) -(\d+)/.exec(line)
      if (ab) {
        ahead = Number(ab[1] ?? 0)
        behind = Number(ab[2] ?? 0)
      }
    } else if (line.trim() !== '') {
      dirty += 1
    }
  }

  return { branch, dirty, ahead, behind }
}

export function parseReviewStatus(line: string): string | null {
  if (!line) return null

  const status = /\[(pass|stale|fail)\]/.exec(line)?.[1]
  if (!status) return null
  if (status === 'stale') return 'stale'
  if (status === 'fail') return 'fail'

  const marks = line.match(/(?:ds|glm|lock)[✓✗]\d*/g) ?? []
  const reviewers = marks.join(' ')
  return reviewers ? `${reviewers} pass` : 'pass'
}

export function ageMinutes(ct: number, nowMs: number): number {
  return Math.max(0, Math.floor((nowMs / 1000 - ct) / 60))
}

export function parseSprints(json: string): SprintRow[] {
  if (!json) return []
  try {
    const rows: unknown = JSON.parse(json)
    if (!Array.isArray(rows)) return []
    return rows.map(row => {
      const r = (row ?? {}) as Record<string, unknown>
      return {
        id: Number(r.id ?? 0),
        name: String(r.name ?? ''),
        done: Number(r.done ?? 0),
        total: Number(r.total ?? 0),
      }
    })
  } catch {
    return []
  }
}

export function parseInProgress(json: string): InProgressRow[] {
  if (!json) return []
  try {
    const rows: unknown = JSON.parse(json)
    if (!Array.isArray(rows)) return []
    return rows.map(row => {
      const r = (row ?? {}) as Record<string, unknown>
      return {
        ref: String(r.ref ?? ''),
        title: String(r.title ?? ''),
      }
    })
  } catch {
    return []
  }
}

export function parseGitLog(line: string): GitLogRow | null {
  if (!line) return null
  const parts = line.split('\x1f')
  if (parts.length < 3) return null
  const sha = parts[0] ?? ''
  if (!sha) return null
  return {
    sha,
    subject: parts[1] ?? '',
    ct: Number(parts[2] ?? 0),
  }
}

export function countLevels(log: string): { warn: number; critical: number } {
  let warn = 0
  let critical = 0
  for (const line of log.split('\n')) {
    if (/(^|\s)WARN(\s|$)/.test(line)) warn += 1
    if (/(^|\s)CRITICAL(\s|$)/.test(line)) critical += 1
  }
  return { warn, critical }
}

export type PhaseFile = { id: string; phase: string; by: string | null; atMs: number }

/** One `tix phase` cache file (`phase-<id>.json`); null when unreadable. */
export function parsePhaseFile(json: string): PhaseFile | null {
  try {
    const r = JSON.parse(json) as Record<string, unknown> | null
    if (r === null || typeof r !== 'object') return null
    const id = typeof r.identifier === 'string' ? r.identifier : ''
    const phase = typeof r.phase === 'string' ? r.phase : ''
    const atMs = typeof r.at === 'string' ? Date.parse(r.at) : Number.NaN
    if (!id || !phase || Number.isNaN(atMs)) return null
    return { id, phase, by: typeof r.by === 'string' && r.by ? r.by : null, atMs }
  } catch {
    return null
  }
}
