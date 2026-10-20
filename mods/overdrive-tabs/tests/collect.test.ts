import { describe, expect, test } from 'claude-code/testing'

import {
  ageMinutes,
  countLevels,
  parseGitLog,
  parseGitStatus,
  parseInProgress,
  parsePhaseFile,
  parseReviewStatus,
  parseSprints,
} from '../hooks/collect'

const PASS = 'dual-review: \u2696 ds\u2713 glm\u2713 [pass] \u2014 report: /tmp/dr-report.md'
const STALE = '\u2696 review stale (PASS 17m ago) [stale]'
const FAIL = 'ds\u2713 glm\u27171 [fail]'

describe('parseGitStatus', () => {
  test('parses branch, dirty, ahead and behind', () => {
    const out = [
      '# branch.oid abc1234',
      '# branch.head feat/odt-2',
      '# branch.upstream origin/feat/odt-2',
      '# branch.ab +1 -0',
      '1 .M N... 100644 100644 100644 abc123 def456 src/a.ts',
      '1 M. N... 100644 100644 100644 abc123 def456 src/b.ts',
      '? untracked.txt',
    ].join('\n')

    expect(parseGitStatus(out)).toEqual({
      branch: 'feat/odt-2',
      dirty: 3,
      ahead: 1,
      behind: 0,
    })
  })

  test('detached HEAD yields null branch', () => {
    const out = ['# branch.oid abc1234', '# branch.head (detached)'].join('\n')
    expect(parseGitStatus(out).branch).toBeNull()
  })

  test('behind upstream and clean tree', () => {
    const out = ['# branch.head main', '# branch.ab +0 -3'].join('\n')
    expect(parseGitStatus(out)).toEqual({ branch: 'main', dirty: 0, ahead: 0, behind: 3 })
  })

  test('empty input yields defaults', () => {
    expect(parseGitStatus('')).toEqual({ branch: null, dirty: 0, ahead: 0, behind: 0 })
  })
})

describe('parseReviewStatus', () => {
  test('pass carries the reviewer glyphs', () => {
    expect(parseReviewStatus(PASS)).toBe('ds\u2713 glm\u2713 pass')
  })

  test('stale collapses to the word', () => {
    expect(parseReviewStatus(STALE)).toBe('stale')
  })

  test('fail collapses to the word', () => {
    expect(parseReviewStatus(FAIL)).toBe('fail')
  })

  test('none / nokeys are unknown', () => {
    expect(parseReviewStatus('dual-review: \u2696 review: none [none]')).toBeNull()
    expect(parseReviewStatus('dual-review: \u2696 keys missing: ds\u00b7glm [nokeys]')).toBeNull()
  })

  test('a lockfile-only pass names the lock reviewer', () => {
    expect(parseReviewStatus('⚖ lock✓ [pass]')).toBe('lock✓ pass')
  })

  test('lock sits beside ds and glm in the marks', () => {
    expect(parseReviewStatus('⚖ ds✓ lock✓ glm✓ [pass]')).toBe('ds✓ lock✓ glm✓ pass')
  })

  test('empty line is null', () => {
    expect(parseReviewStatus('')).toBeNull()
  })
})

describe('ageMinutes', () => {
  test('whole minutes from a ms now against a s commit time', () => {
    expect(ageMinutes(1760000000, (1760000000 + 90 * 60) * 1000)).toBe(90)
    expect(ageMinutes(1760000000, (1760000000 + 59) * 1000)).toBe(0)
    expect(ageMinutes(1760000000, (1760000000 + 90 * 60 + 30) * 1000)).toBe(90)
  })

  test('never negative', () => {
    expect(ageMinutes(1760000000, (1760000000 - 300) * 1000)).toBe(0)
  })
})

describe('parseSprints', () => {
  test('maps id, name, done and total', () => {
    const json =
      '[{"id":22,"name":"overdrive \u2014 status tabs mod","done":0,"total":4},' +
      '{"id":21,"name":"Demo sprint","done":6,"total":7}]'
    expect(parseSprints(json)).toEqual([
      { id: 22, name: 'overdrive \u2014 status tabs mod', done: 0, total: 4 },
      { id: 21, name: 'Demo sprint', done: 6, total: 7 },
    ])
  })

  test('null done (no tickets) coerces to 0', () => {
    expect(parseSprints('[{"id":1,"name":"empty","done":null,"total":0}]')).toEqual([
      { id: 1, name: 'empty', done: 0, total: 0 },
    ])
  })

  test('invalid json is empty', () => {
    expect(parseSprints('not json')).toEqual([])
    expect(parseSprints('')).toEqual([])
  })

  test('a non-array object is empty', () => {
    expect(parseSprints('{"id":1}')).toEqual([])
  })
})

describe('parseInProgress', () => {
  test('maps ref and title', () => {
    const json =
      '[{"ref":"ODT-2","title":"Collectors and parsers for the three tabs"},' +
      '{"ref":"ODT-1","title":"Tab band skeleton"}]'
    expect(parseInProgress(json)).toEqual([
      { ref: 'ODT-2', title: 'Collectors and parsers for the three tabs' },
      { ref: 'ODT-1', title: 'Tab band skeleton' },
    ])
  })

  test('invalid json is empty', () => {
    expect(parseInProgress('oops')).toEqual([])
  })
})

describe('parseGitLog', () => {
  test('splits sha, subject and commit time', () => {
    const line = `abc1234\x1fODT-2: collectors and parsers\x1f1760000000`
    expect(parseGitLog(line)).toEqual({
      sha: 'abc1234',
      subject: 'ODT-2: collectors and parsers',
      ct: 1760000000,
    })
  })

  test('missing fields are null', () => {
    expect(parseGitLog('')).toBeNull()
    expect(parseGitLog('abc1234')).toBeNull()
  })
})

describe('countLevels', () => {
  test('counts WARN and CRITICAL lines', () => {
    const log = [
      '2026-10-10T04:55:01Z WARN rig quota HOT 4h58m/5h window',
      '2026-10-10T04:55:02Z INFO some routine note',
      '2026-10-10T04:55:03Z CRITICAL sessionlog.sh missing next to script',
      '2026-10-10T04:55:04Z WARN another warning',
    ].join('\n')
    expect(countLevels(log)).toEqual({ warn: 2, critical: 1 })
  })

  test('tolerates a level at line start', () => {
    expect(countLevels('WARN no leading timestamp')).toEqual({ warn: 1, critical: 0 })
  })

  test('does not match words containing the level', () => {
    expect(countLevels('WARNING CRITICALITY')).toEqual({ warn: 0, critical: 0 })
  })

  test('empty log is zeroed', () => {
    expect(countLevels('')).toEqual({ warn: 0, critical: 0 })
  })
})

describe('parsePhaseFile', () => {
  test('reads a tix phase cache file', () => {
    const json = '{"repo":"/x","identifier":"ODT-777","phase":"build","by":"opus","at":"2026-09-04T12:14:36.202Z"}'
    expect(parsePhaseFile(json)).toEqual({
      id: 'ODT-777',
      phase: 'build',
      by: 'opus',
      atMs: Date.parse('2026-09-04T12:14:36.202Z'),
    })
  })

  test('keeps by null when missing and refuses broken files', () => {
    expect(parsePhaseFile('{"identifier":"ODT-1","phase":"spec","at":"2026-09-04T12:00:00Z"}')?.by).toBeNull()
    expect(parsePhaseFile('{"identifier":"ODT-1","phase":"spec"}')).toBeNull()
    expect(parsePhaseFile('not json')).toBeNull()
    expect(parsePhaseFile('')).toBeNull()
  })
})
