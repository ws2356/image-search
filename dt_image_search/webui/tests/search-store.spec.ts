import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { ModelNotReady } from '../src/api/client'
import { useSearchStore } from '../src/stores/search'

vi.mock('../src/api/client', () => {
  class ModelNotReady extends Error {
    modelState: string
    constructor(state: string) {
      super('model not ready')
      this.modelState = state
    }
  }
  class ApiError extends Error {}
  return {
    api: { search: vi.fn() },
    ModelNotReady,
    ApiError,
  }
})

import { api } from '../src/api/client'

describe('useSearchStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.clearAllMocks()
  })

  it('debounces bursts into one request with the latest query', async () => {
    const store = useSearchStore()
    const searchMock = api.search as ReturnType<typeof vi.fn>
    searchMock.mockResolvedValue({ results: [] })

    store.runSearch('c')
    store.runSearch('ca')
    store.runSearch('cat')
    expect(searchMock).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(300)
    expect(searchMock).toHaveBeenCalledTimes(1)
    expect(searchMock).toHaveBeenCalledWith('cat')
  })

  it('clears results immediately for an empty query', async () => {
    const store = useSearchStore()
    store.results = [{ id: '1', path: 'x', folder_id: '1', score: 1 }]

    await store.runSearch('   ')

    expect(store.results).toEqual([])
    expect(api.search).not.toHaveBeenCalled()
  })

  it('maps ModelNotReady to modelState instead of faking empty results', async () => {
    const store = useSearchStore()
    const searchMock = api.search as ReturnType<typeof vi.fn>
    searchMock.mockRejectedValue(new ModelNotReady('loading'))

    store.runSearch('cat')
    await vi.advanceTimersByTimeAsync(300)

    expect(store.modelState).toBe('loading')
    expect(store.results).toEqual([])
    expect(store.searching).toBe(false)
  })

  it('marks searching while the request is in flight', async () => {
    const store = useSearchStore()
    const searchMock = api.search as ReturnType<typeof vi.fn>
    let resolveFetch: (v: unknown) => void
    searchMock.mockReturnValue(new Promise((resolve) => (resolveFetch = resolve)))

    store.runSearch('cat')
    await vi.advanceTimersByTimeAsync(300)
    expect(store.searching).toBe(true)

    resolveFetch!({ results: [] })
    await vi.runAllTimersAsync()
    expect(store.searching).toBe(false)
    expect(store.modelState).toBeNull()
  })

  it('drops stale responses from superseded queries', async () => {
    const store = useSearchStore()
    const searchMock = api.search as ReturnType<typeof vi.fn>
    let resolveFirst: (v: unknown) => void
    searchMock.mockImplementationOnce(
      () => new Promise((resolve) => (resolveFirst = resolve)),
    )
    searchMock.mockResolvedValueOnce({ results: [{ id: '2', path: 'b', folder_id: '1', score: 0.9 }] })

    store.runSearch('first')
    await vi.advanceTimersByTimeAsync(300)
    store.runSearch('second')
    await vi.advanceTimersByTimeAsync(300)
    resolveFirst!({ results: [{ id: '1', path: 'a', folder_id: '1', score: 0.1 }] })
    await vi.runAllTimersAsync()

    expect(store.results).toEqual([{ id: '2', path: 'b', folder_id: '1', score: 0.9 }])
  })
})
