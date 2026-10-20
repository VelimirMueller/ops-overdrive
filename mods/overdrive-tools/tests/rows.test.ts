import { expect, test } from 'claude-code/testing'

import { isOpenRow, toggledRow } from '../hooks/rows'

test('folded mode closes every finished row', async () => {
  expect(isOpenRow(null, 'info', 'folded')).toBe(false)
  expect(isOpenRow(null, 'change', 'folded')).toBe(false)
  expect(isOpenRow(null, 'run', 'folded')).toBe(false)
  expect(toggledRow(null, 'change', 'folded')).toBe('open')
})

test('info rows follow the mode until clicked', async () => {
  expect(isOpenRow(null, 'info', 'changes')).toBe(false)
  expect(isOpenRow(null, 'info', 'all')).toBe(true)
  expect(isOpenRow(null, 'change', 'changes')).toBe(true)
  expect(isOpenRow(null, 'run', 'changes')).toBe(true)
})

test('an override wins over the mode', async () => {
  expect(isOpenRow('open', 'info', 'changes')).toBe(true)
  expect(isOpenRow('closed', 'change', 'all')).toBe(false)
})

test('a click flips the row every time', async () => {
  let state = toggledRow(null, 'info', 'changes')
  expect(state).toBe('open')
  state = toggledRow(state, 'info', 'changes')
  expect(state).toBe('closed')
  state = toggledRow(state, 'info', 'changes')
  expect(state).toBe('open')
  expect(toggledRow(null, 'run', 'all')).toBe('closed')
})
