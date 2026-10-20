import { atom, memberOf, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Mode, RowState } from '../types'
import { classify, summarize } from './classify'
import type { Kind } from './classify'
import { isMode, isOpenRow, toggledRow } from './rows'

const mode = atom({ plugin: 'overdrive-tools', key: 'mode' } as const, 'folded' as Mode)
const row = atom({ plugin: 'overdrive-tools', key: 'row' } as const, null as RowState)

// Neon Overdrive palette (FLAIR.md): magenta = change, cyan = info, yellow = run.
const COLOR: Record<Kind, string> = { info: '#00FFF7', change: '#EE4FFF', run: '#F0FF19' }
const TAG: Record<Kind, string> = { info: 'INF', change: 'CHG', run: 'RUN' }

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'tools',
      description: 'Tool rows: /tools folded (default) closes every row, /tools changes closes info rows, /tools all opens all; click a tag to toggle one row',
    })

    return next(e)
  })

  on('command.run', { command: 'tools' }, async ($, e) => {
    const arg = e.args.trim()
    const current = await read($, mode)
    const target: Mode = isMode(arg) ? arg : current === 'folded' ? 'all' : 'folded'
    await update($, mode, () => target)

    const layout = e.presentation.isFullscreen ? 'fullscreen layout, clicks reach the tags' : 'main-screen layout, clicks are not reported here'
    const what = target === 'all' ? 'every tool row is open.' : target === 'changes' ? 'info rows are folded, changes and runs are open.' : 'every finished row is folded; click a tag to open one.'

    return { text: `${what} (${layout})` }
  })

  // Every tool row: a clickable tag on the left of the engine's own drawing.
  // Clicking the tag folds or unfolds that one row; /tools sets the default.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const kind = classify(e.props.tool, e.props.input)
    const color = e.props.isErrored ? 'error' : COLOR[kind]
    const member = memberOf(row, e)
    const override = await read($, member)
    const isOpen = e.props.isRunning || isOpenRow(override, kind, await read($, mode))
    const engine = await next(e)
    const { Box, Button, Text } = $.ui.resolve(e)

    const toggle = async () => {
      try {
        const current = await read($, mode)
        await update($, member, state => toggledRow(state, kind, current))
      } catch (error) {
        $.ui.toast(`overdrive-tools: toggle failed: ${error instanceof Error ? error.message : String(error)}`)
      }
    }

    const tag = (
      <Button key={`odt-${e.props.tool_use_id}`} plain onPress={toggle}>
        <Text color={color}>▌</Text>
        <Text color={color} bold>{TAG[kind]}</Text>
        <Text color={color}>{isOpen ? ' ▾' : ' ▸'}</Text>
        {isOpen ? null : <Text dimColor> {summarize(e.props.tool, e.props.input)}</Text>}
      </Button>
    )

    return isOpen ? (
      <Box flexDirection="column">
        {tag}
        <Box flexDirection="row">
          <Text color={color}>▌ </Text>
          <Box flexDirection="column" flexGrow={1}>{engine}</Box>
        </Box>
      </Box>
    ) : (
      <Box flexDirection="column">{tag}</Box>
    )
  })

  // A folded run of reads that hides a change inside is unfolded, so every
  // change row gets its own colored line.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    const hasChange = e.props.calls.some(call => classify(call.tool, call.input) !== 'info')

    return hasChange && !e.props.isExpanded
      ? next({ ...e, props: { ...e.props, isExpanded: true } })
      : next(e)
  })
}
