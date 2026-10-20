import { expect, test } from 'claude-code/testing'

import { classify, classifyMcp, summarize } from '../hooks/classify'

test('reads are info, edits are change', async () => {
  expect(classify('Read', { file_path: 'a.ts' })).toBe('info')
  expect(classify('Grep', { pattern: 'x' })).toBe('info')
  expect(classify('Edit', { file_path: 'a.ts' })).toBe('change')
  expect(classify('Write', { file_path: 'a.ts' })).toBe('change')
})

test('mcp tools split on their verb', async () => {
  expect(classifyMcp('mcp__code-context__search_files')).toBe('info')
  expect(classifyMcp('mcp__rag-context__rag_search')).toBe('info')
  expect(classifyMcp('mcp__code-context__update_ticket')).toBe('change')
  expect(classifyMcp('mcp__signoz__signoz_create_alert')).toBe('change')
})

test('bash falls to run until the classifier is written', async () => {
  expect(classify('Bash', { command: 'git status' })).toBe('run')
})

test('summarize keeps one short line', async () => {
  expect(summarize('Read', { file_path: '/x/y.ts' })).toBe('Read /x/y.ts')
  expect(summarize('Bash', { command: 'ls', description: 'List files' })).toBe('Bash List files')
  expect(summarize('Grep', { pattern: 'a'.repeat(80) }).length).toBe(60)
})
