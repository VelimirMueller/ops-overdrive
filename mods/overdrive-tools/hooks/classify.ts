// What a tool call did, as the transcript colors it.
//   info   → read-only: the row is context, nothing on disk or remote moved
//   change → something on disk, in git, in Linear or in an MCP store changed
//   run    → a process ran whose effect the name alone does not tell
export type Kind = 'info' | 'change' | 'run'

const INFO_TOOLS = new Set([
  'Read', 'Grep', 'Glob', 'LS', 'WebFetch', 'WebSearch', 'ToolSearch',
  'Skill', 'ListAgents', 'Monitor', 'LSP', 'ReadMcpResourceTool', 'ListMcpResourcesTool',
])
const CHANGE_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])
const RUN_TOOLS = new Set(['Agent', 'Workflow'])

// MCP tool names that only read: get_*, list_*, search_*, rag_*, who_imports …
const MCP_READ = /^(get|list|search|find|read|query|describe|health|status|who_|exports_|rag_|fetch|analyze|ping|export)/

export function classify(tool: string, input: unknown): Kind {
  if (CHANGE_TOOLS.has(tool)) return 'change'
  if (INFO_TOOLS.has(tool)) return 'info'
  if (RUN_TOOLS.has(tool)) return 'run'
  if (tool === 'Bash') return classifyBash(commandOf(input))
  if (tool.startsWith('mcp__')) return classifyMcp(tool)
  return 'run'
}

export function classifyMcp(tool: string): Kind {
  const name = tool.split('__').pop() ?? ''
  return MCP_READ.test(name) ? 'info' : 'change'
}

export function commandOf(input: unknown): string {
  if (typeof input === 'object' && input !== null && 'command' in input) {
    const c = (input as { command?: unknown }).command
    return typeof c === 'string' ? c : ''
  }
  return ''
}

// TODO(velimir): your call. A Bash row is 'info' when the command only reads
// (git status/log/diff, ls, cat, grep, rig quota, tix lint, dual-review --status,
// relpilot scan …) and 'change' when it writes (git commit/push, tix new/comment,
// overdrive snapshot/bump, rm/mv, npm install, sed -i …). Everything else is 'run'.
// Keep it to a few regexes; `command` is the raw text the model sent, possibly
// several commands joined with && or ;. Until filled, every Bash row is 'run'.
export function classifyBash(command: string): Kind {
  void command
  return 'run'
}

// One short line for a folded tag: the file, the pattern or the command head.
export function summarize(tool: string, input: unknown, max = 60): string {
  const i = (typeof input === 'object' && input !== null ? input : {}) as Record<string, unknown>
  const pick = (...keys: string[]) => {
    for (const k of keys) {
      const v = i[k]
      if (typeof v === 'string' && v.trim() !== '') return v.trim()
    }
    return ''
  }
  const detail = tool === 'Bash'
    ? pick('description', 'command')
    : pick('file_path', 'pattern', 'query', 'url', 'skill', 'prompt', 'description')
  const text = `${tool}${detail ? ` ${detail}` : ''}`.replace(/\s+/g, ' ')
  return text.length > max ? `${text.slice(0, max - 1)}…` : text
}
