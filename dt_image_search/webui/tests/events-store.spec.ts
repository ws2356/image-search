import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { setActivePinia, createPinia, disposePinia } from 'pinia'

vi.mock('../src/api/client', () => ({
  api: { getStatus: vi.fn() },
}))

import { api } from '../src/api/client'
import { useEventsStore } from '../src/stores/events'
import { useStatusStore } from '../src/stores/status'
import { useFoldersStore } from '../src/stores/folders'

class FakeWebSocket {
  static instances: FakeWebSocket[] = []
  onopen: (() => void) | null = null
  onmessage: ((msg: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  url: string

  constructor(url: string) {
    this.url = url
    FakeWebSocket.instances.push(this)
  }

  open() {
    this.onopen?.()
  }

  receive(payload: unknown) {
    this.onmessage?.({ data: JSON.stringify(payload) })
  }

  close() {
    this.onclose?.()
  }
}

describe('useEventsStore', () => {
  let pinia: ReturnType<typeof createPinia>

  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    vi.useFakeTimers()
    FakeWebSocket.instances = []
    vi.stubGlobal('WebSocket', FakeWebSocket as unknown as typeof WebSocket)
    sessionStorage.setItem('dts-auth', 'tok')
  })

  afterEach(() => {
    disposePinia(pinia)
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.clearAllMocks()
  })

  it('connects with the auth query param and dispatches envelopes', () => {
    const store = useEventsStore()
    store.connect()

    const ws = FakeWebSocket.instances[0]
    expect(ws.url).toContain('/events?auth=tok')

    ws.receive({ event: 'status_message', data: { message: 'indexing 1/2' } })
    expect(store.latestStatusMessage).toBe('indexing 1/2')

    ws.receive({ event: 'model_load_failed', data: {} })
    expect(store.modelLoadFailed).toBe(true)
  })

  it('notifies listeners on fs_changed for refresh flows', () => {
    const store = useEventsStore()
    const seen: string[] = []
    store.onEvent((event) => seen.push(event))

    store.connect()
    FakeWebSocket.instances[0].receive({ event: 'fs_changed', data: { event: { type: 'x', src_path: '/p/a.jpg' } } })

    expect(seen).toEqual(['fs_changed'])
  })

  it('reconnects with exponential backoff capped at 30s', async () => {
    const store = useEventsStore()
    store.connect()
    const first = FakeWebSocket.instances[0]

    // attempt 0 → 1s delay
    first.close()
    await vi.advanceTimersByTimeAsync(999)
    expect(FakeWebSocket.instances.length).toBe(1)
    await vi.advanceTimersByTimeAsync(1)
    expect(FakeWebSocket.instances.length).toBe(2)

    // attempt 1 → 2s delay
    FakeWebSocket.instances[1].close()
    await vi.advanceTimersByTimeAsync(1999)
    expect(FakeWebSocket.instances.length).toBe(2)
    await vi.advanceTimersByTimeAsync(1)
    expect(FakeWebSocket.instances.length).toBe(3)

    // attempt 2 → 4s delay
    FakeWebSocket.instances[2].close()
    await vi.advanceTimersByTimeAsync(4000)
    expect(FakeWebSocket.instances.length).toBe(4)

    // attempts 3-5: 8s, 16s, then 30s (2**5 would be 32s → capped at 30s)
    const delays = [8000, 16000, 30000]
    for (const delay of delays) {
      const count = FakeWebSocket.instances.length
      const last = FakeWebSocket.instances[count - 1]
      last.close()
      await vi.advanceTimersByTimeAsync(delay - 1)
      expect(FakeWebSocket.instances.length).toBe(count)  // still waiting
      await vi.advanceTimersByTimeAsync(1)
      expect(FakeWebSocket.instances.length).toBe(count + 1)  // reconnected
    }
  })

  it('refreshes status after (re)connect', async () => {
    ;(api.getStatus as ReturnType<typeof vi.fn>).mockResolvedValue({
      model_state: 'ready',
      folders: [],
    })

    const store = useEventsStore()
    store.connect()
    FakeWebSocket.instances[0].open()
    await vi.runAllTimersAsync()
    expect(api.getStatus).toHaveBeenCalledTimes(1)

    FakeWebSocket.instances[0].close()
    await vi.advanceTimersByTimeAsync(1000)
    FakeWebSocket.instances[1].open()
    await vi.runAllTimersAsync()
    expect(api.getStatus).toHaveBeenCalledTimes(2)
  })

  it('replaces stale folder/model state and banners after reconnect', async () => {
    const folder = { id: '1', path: '/photos/', status: 2, added_at: 'today' }
    vi.mocked(api.getStatus).mockResolvedValue({ model_state: 'ready', folders: [folder] })
    const events = useEventsStore()
    const status = useStatusStore()
    const folders = useFoldersStore()
    status.modelState = 'loading'
    folders.folders = [{ ...folder, status: 1 }]
    events.connect()
    const first = FakeWebSocket.instances[0]
    first.receive({ event: 'status_message', data: { message: 'indexing' } })
    first.receive({ event: 'model_load_failed', data: {} })
    first.close()
    await vi.advanceTimersByTimeAsync(1000)
    FakeWebSocket.instances[1].open()
    await vi.advanceTimersByTimeAsync(0)

    expect(status.modelState).toBe('ready')
    expect(folders.folders).toEqual([folder])
    expect(status.snapshot?.folders).toEqual([folder])
    expect(events.latestStatusMessage).toBeNull()
    expect(events.modelLoadFailed).toBe(false)
  })

  it('preserves progress messages received while the status request is pending', async () => {
    let finish!: (value: { model_state: string; folders: [] }) => void
    vi.mocked(api.getStatus).mockReturnValue(new Promise((resolve) => { finish = resolve }))
    const events = useEventsStore()
    events.connect()
    const ws = FakeWebSocket.instances[0]
    ws.open()
    ws.receive({ event: 'status_message', data: { message: 'new work' } })
    finish({ model_state: 'ready', folders: [] })
    await vi.advanceTimersByTimeAsync(0)
    expect(events.latestStatusMessage).toBe('new work')
  })

  it('reports a failed status refresh and recovers on the next connection', async () => {
    vi.mocked(api.getStatus).mockRejectedValueOnce(new Error('offline'))
    vi.mocked(api.getStatus).mockResolvedValueOnce({ model_state: 'failed', folders: [] })
    const events = useEventsStore()
    const status = useStatusStore()
    events.connect()
    FakeWebSocket.instances[0].open()
    await vi.advanceTimersByTimeAsync(0)
    expect(status.error).toContain('加载状态失败')
    FakeWebSocket.instances[0].close()
    await vi.advanceTimersByTimeAsync(1000)
    FakeWebSocket.instances[1].open()
    await vi.advanceTimersByTimeAsync(0)
    expect(status.error).toBeNull()
    expect(events.modelLoadFailed).toBe(true)
  })

  it('discards an old connection snapshot and stops reconnecting on disposal', async () => {
    let finish!: (value: { model_state: string; folders: [] }) => void
    vi.mocked(api.getStatus).mockReturnValue(new Promise((resolve) => { finish = resolve }))
    const events = useEventsStore()
    const status = useStatusStore()
    events.connect()
    FakeWebSocket.instances[0].open()
    FakeWebSocket.instances[0].close()
    events.disconnect()
    finish({ model_state: 'ready', folders: [] })
    await vi.advanceTimersByTimeAsync(30000)
    expect(status.snapshot).toBeNull()
    expect(FakeWebSocket.instances).toHaveLength(1)
    expect(events.connected).toBe(false)
  })
})
