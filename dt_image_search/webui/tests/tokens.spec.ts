// Verify the shipped theme, including cascade order after component CSS.
// Author: Codex
// Created: 2026-11-13
// @vitest-environment node
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve } from 'node:path'
import { build } from 'vite'

const outputDir = mkdtempSync(resolve(tmpdir(), 'ausearch-theme-'))
let builtCss = ''

beforeAll(async () => {
  await build({ build: { outDir: outputDir }, logLevel: 'silent' })
  builtCss = readdirSync(resolve(outputDir, 'assets'))
    .filter((name) => name.endsWith('.css'))
    .map((name) => readFileSync(resolve(outputDir, 'assets', name), 'utf-8'))
    .join('\n')
}, 30000)

afterAll(() => rmSync(outputDir, { recursive: true, force: true }))

describe('design tokens', () => {
  it('defines the semantic --dts-* tokens', () => {
    for (const name of [
      '--dts-color-primary:',
      '--dts-color-bg-page:',
      '--dts-space-m:',
      '--dts-font-size-m:',
      '--dts-radius-s:',
    ]) {
      expect(builtCss).toContain(name)
    }
  })

  it('maps Element Plus theme variables from --dts-* tokens', () => {
    for (const [name, token] of [
      ['--el-color-primary', '--dts-color-primary'],
      ['--el-bg-color', '--dts-color-bg-surface'],
    ]) {
      const declarations = [...builtCss.matchAll(new RegExp(`${name}:([^;}]+)`, 'g'))]
      expect(declarations.at(-1)?.[1].trim()).toBe(`var(${token})`)
    }
  })

  it('keeps component colors and dimensions in design tokens', () => {
    const sourceDir = resolve(__dirname, '../src')
    const components = readdirSync(sourceDir, { recursive: true })
      .map(String)
      .filter((name) => name.endsWith('.vue'))
    for (const name of components) {
      const source = readFileSync(resolve(sourceDir, name), 'utf-8')
      expect(source, name).not.toMatch(/#[\da-f]{3,8}\b|\brgba?\(|\b\d+(?:\.\d+)?(?:px|rem|em)\b/i)
    }
  })
})
