import type { Mode, RowState } from '../types'
import type { Kind } from './classify'

// What a row shows when nobody clicked it.
export const defaultOpen = (kind: Kind, mode: Mode): boolean =>
  mode === 'all' ? true : mode === 'changes' ? kind !== 'info' : false

export const MODES: readonly Mode[] = ['folded', 'changes', 'all']
export const isMode = (value: string): value is Mode => (MODES as readonly string[]).includes(value)

// Whether a row is open now: its own override wins, else the mode's default.
export const isOpenRow = (override: RowState, kind: Kind, mode: Mode): boolean =>
  override === null ? defaultOpen(kind, mode) : override === 'open'

// The override a click leaves behind: the opposite of what the row shows now.
export const toggledRow = (override: RowState, kind: Kind, mode: Mode): RowState =>
  isOpenRow(override, kind, mode) ? 'closed' : 'open'
