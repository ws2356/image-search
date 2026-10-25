import { describe, expect, it, beforeEach, vi } from 'vitest'
import { hasShellApi, pickFolder, type ShellApi } from '../src/shell/bridge'

describe('shell bridge', () => {
  beforeEach(() => {
    delete window.pywebview
  })

  it('becomes available when pywebview injects its API', async () => {
    const api: ShellApi = {
      pick_folder: vi.fn().mockResolvedValue('/photos'),
      reveal: vi.fn().mockResolvedValue(undefined),
    }
    window.pywebview = { api }

    expect(hasShellApi()).toBe(false)
    window.dispatchEvent(new Event('pywebviewready'))

    expect(hasShellApi()).toBe(true)
    await expect(pickFolder()).resolves.toBe('/photos')
  })
})
