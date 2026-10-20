// folded: every finished row starts closed (default) · changes: info rows closed · all: every row open
export type Mode = 'folded' | 'changes' | 'all'
// Per-row override of the mode's default: absent (null) follows the mode.
export type RowState = 'open' | 'closed' | null

declare module 'claude-code' {
  interface PluginState {
    'overdrive-tools': { mode: Mode; row: StateFamily<RowState> }
  }
}
