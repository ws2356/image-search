import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const tokensCss = readFileSync(resolve(__dirname, '../src/styles/tokens.css'), 'utf-8')

describe('design tokens', () => {
  it('defines the semantic --dts-* tokens', () => {
    for (const name of [
      '--dts-color-primary:',
      '--dts-color-bg-page:',
      '--dts-space-m:',
      '--dts-font-size-m:',
      '--dts-radius-s:',
    ]) {
      expect(tokensCss).toContain(name)
    }
  })

  it('maps Element Plus theme variables from --dts-* tokens', () => {
    expect(tokensCss).toContain('--el-color-primary: var(--dts-color-primary)')
    expect(tokensCss).toContain('--el-bg-color: var(--dts-color-bg-surface)')
  })
})
