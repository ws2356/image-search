import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { useLiveRefresh } from '../src/composables/useLiveRefresh'

class FakeEvents {
  private fns: Array<(event: string, data: Record<string, unknown>) => void> = []

  onEvent(fn: (event: string, data: Record<string, unknown>) => void): () => void {
    this.fns.push(fn)
    return () => {
      this.fns = this.fns.filter((f) => f !== fn)
    }
  }

  fire(event: string, data: Record<string, unknown> = {}) {
    this.fns.forEach((fn) => fn(event, data))
  }

  get listenerCount(): number {
    return this.fns.length
  }
}

describe('useLiveRefresh', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('invokes the callback once per fs_changed burst (debounced)', async () => {
    const calls = vi.fn()
    const events = new FakeEvents()
    useLiveRefresh(events, calls)

    events.fire('fs_changed')
    events.fire('fs_changed')
    expect(calls).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1000)
    expect(calls).toHaveBeenCalledTimes(1)
  })

  it('ignores other events', async () => {
    const calls = vi.fn()
    const events = new FakeEvents()
    useLiveRefresh(events, calls)

    events.fire('status_message')
    await vi.advanceTimersByTimeAsync(1000)
    expect(calls).not.toHaveBeenCalled()

    events.fire('fs_changed')
    await vi.advanceTimersByTimeAsync(1000)
    expect(calls).toHaveBeenCalledTimes(1)
  })

  it('unsubscribes on dispose', async () => {
    const calls = vi.fn()
    const events = new FakeEvents()
    const dispose = useLiveRefresh(events, calls)
    expect(events.listenerCount).toBe(1)

    dispose!()
    expect(events.listenerCount).toBe(0)
    events.fire('fs_changed')
    await vi.advanceTimersByTimeAsync(1000)
    expect(calls).not.toHaveBeenCalled()
  })
})
