// overdrive-tabs state contract. Owned by the main session — implementers do not change it.
export type TabId = 'code' | 'tickets' | 'claude' | 'overdrive' | 'serpent'

/** Tab 1 — code: the git checkout the session runs in. */
export type CodeInfo = {
  branch: string | null        // `git branch --show-current`; null outside a repo
  dirty: number                // changed + untracked files (`git status --porcelain`)
  ahead: number                // commits ahead of upstream, 0 when none
  behind: number               // commits behind upstream, 0 when none
  review: string | null        // dual-review chip, e.g. "ds✓ glm✓ pass", "stale", "fail"; null when unknown
  lastCommit: { sha: string; subject: string; ageMin: number } | null  // git log -1 in the cwd
}

/** Tab 2 — tickets. Linear phase from the local `tix phase` cache; the rest from the LOCAL code-context DB (never Linear). */
export type TicketsInfo = {
  linear: { id: string; phase: string; by: string | null; ageMin: number } | null  // newest phase file not in phase "done"
  sprints: { id: number; name: string; done: number; total: number }[]   // code-context sprints with status not closed/done
  inProgress: { ref: string; title: string }[]                           // code-context tickets IN_PROGRESS, newest first, max 3
  next: { ref: string; title: string } | null                            // first TODO ticket of the first open sprint, by priority
}

/** Tab 3 — claude stats, from $.session.usage(). */
export type ClaudeInfo = {
  contextPct: number | null
  fiveHourPct: number | null
  fiveHourResetsAt: number | null   // epoch ms
  sevenDayPct: number | null
  sevenDayResetsAt: number | null   // epoch ms
  costUsd: number | null
}

/** Tab 4 — overdrive (~/.claude umbrella repo). */
export type OverdriveInfo = {
  version: string | null                                        // ~/.claude/VERSION
  lastSnapshot: { sha: string; subject: string; ageMin: number } | null  // git -C ~/.claude log -1
  uncommitted: number | null                                    // git -C ~/.claude status --porcelain line count
  warn: number                                                  // this session's overdrive log: WARN lines
  critical: number                                              // ... CRITICAL lines
}

/** Tab 5 — serpent, the session pet. Counters live for the session only. */
export type SerpentInfo = {
  turns: number   // turn.complete count — the serpent's length
  tools: number   // tool calls this session — what it ate
}

declare module 'claude-code' {
  interface PluginState {
    'overdrive-tabs': {
      active: TabId | null
      code: CodeInfo | null
      tickets: TicketsInfo | null
      claude: ClaudeInfo | null
      overdrive: OverdriveInfo | null
      serpent: SerpentInfo
    }
  }
}
