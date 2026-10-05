import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { api, ApiError, ModelNotReady } from '../src/api/client'
import { getToken, resetToken } from '../src/auth/token'

const ORIGIN = window.location.origin

type FetchCall = { url: string; init?: RequestInit }

function mockFetch(handler: (url: string, init?: RequestInit) => Response | Promise<Response>) {
  const calls: FetchCall[] = []
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    return handler(url, init)
  })
  vi.stubGlobal('fetch', fn)
  return { calls, fn }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function navigate(path: string) {
  window.history.replaceState(null, '', path)
}

describe('token', () => {
  beforeEach(() => {
    resetToken()
    sessionStorage.clear()
    navigate('/')
  })

  it('extracts auth from the URL once and strips it', () => {
    navigate('/?auth=tok123')
    expect(getToken()).toBe('tok123')
    expect(window.location.search).toBe('')  // stripped from the address bar
    expect(getToken()).toBe('tok123')  // stable across calls
  })

  it('falls back to sessionStorage', () => {
    sessionStorage.setItem('dts-auth', 'stored')
    expect(getToken()).toBe('stored')
  })

  it('returns null without any auth', () => {
    expect(getToken()).toBeNull()
  })
})

describe('api client', () => {
  beforeEach(() => {
    resetToken()
    sessionStorage.clear()
    navigate('/')
    sessionStorage.setItem('dts-auth', 'tok123')
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('injects the X-Auth-Token header', async () => {
    const { calls } = mockFetch(() => jsonResponse({ folders: [] }))
    await api.listFolders()
    const headers = new Headers(calls[0].init?.headers)
    expect(headers.get('X-Auth-Token')).toBe('tok123')
    expect(calls[0].url).toBe(`${ORIGIN}/folders`)
  })

  it('addFolder posts JSON body', async () => {
    const { calls } = mockFetch(() => jsonResponse({ id: '5', path: '/p/', status: 0, added_at: 'x' }, 201))
    await api.addFolder('/p')
    expect(calls[0].init?.method).toBe('POST')
    expect(JSON.parse(String(calls[0].init?.body))).toEqual({ path: '/p' })
  })

  it('thumbUrl/fileUrl carry auth as query param', () => {
    expect(api.thumbUrl('7')).toBe(`${ORIGIN}/thumb/7?auth=tok123`)
    expect(api.fileUrl('7')).toBe(`${ORIGIN}/file/7?auth=tok123`)
  })

  it('browse/search send query params', async () => {
    const { calls } = mockFetch(() => jsonResponse({ results: [] }))
    await api.search('cat', 10)
    expect(calls[0].url).toBe(`${ORIGIN}/search?q=cat&limit=10`)
  })

  it('maps 401 to ApiError', async () => {
    mockFetch(() => jsonResponse({ detail: 'unauthorized' }, 401))
    await expect(api.listFolders()).rejects.toMatchObject({ status: 401, name: 'ApiError' })
    await expect(api.listFolders()).rejects.toBeInstanceOf(ApiError)
  })

  it('maps 404 to ApiError', async () => {
    mockFetch(() => jsonResponse({ detail: 'folder not found' }, 404))
    await expect(api.deleteFolder('9')).rejects.toMatchObject({ status: 404 })
  })

  it('maps 503 model_state to ModelNotReady', async () => {
    mockFetch(() => jsonResponse({ detail: { model_state: 'loading' } }, 503))
    await expect(api.search('cat')).rejects.toBeInstanceOf(ModelNotReady)
    await expect(api.search('cat')).rejects.toMatchObject({ modelState: 'loading' })
  })
})
