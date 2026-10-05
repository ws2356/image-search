// HTTP client for the index server. Business calls go here and only here;
// auth rides the X-Auth-Token header (XHR) or the auth query param (<img>).
import { getToken } from '../auth/token'
import type {
  BrowseResponse,
  FolderDto,
  FoldersResponse,
  SearchResponse,
  StatusResponse,
} from './types'

export class ApiError extends Error {
  readonly status: number
  readonly detail: unknown

  constructor(status: number, detail: unknown) {
    super(`API error ${status}: ${JSON.stringify(detail)}`)
    this.name = 'ApiError'
    this.status = status
    this.detail = detail
  }
}

export class ModelNotReady extends ApiError {
  readonly modelState: string

  constructor(modelState: string) {
    super(503, { model_state: modelState })
    this.name = 'ModelNotReady'
    this.modelState = modelState
  }
}

type Params = Record<string, string | number | undefined>

async function request<T>(path: string, init: RequestInit = {}, params?: Params): Promise<T> {
  const url = new URL(path, window.location.origin)
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined) url.searchParams.set(key, String(value))
    }
  }
  const headers = new Headers(init.headers)
  const token = getToken()
  if (token) headers.set('X-Auth-Token', token)

  const resp = await fetch(url.toString(), { ...init, headers })
  if (!resp.ok) {
    let detail: unknown = null
    try {
      detail = (await resp.json()).detail
    } catch {
      detail = null
    }
    if (
      resp.status === 503 &&
      detail &&
      typeof detail === 'object' &&
      'model_state' in (detail as Record<string, unknown>)
    ) {
      throw new ModelNotReady(String((detail as Record<string, unknown>).model_state))
    }
    throw new ApiError(resp.status, detail ?? resp.statusText)
  }
  if (resp.status === 204) return undefined as T
  return (await resp.json()) as T
}

function withAuthQuery(path: string): string {
  const url = new URL(path, window.location.origin)
  const token = getToken()
  if (token) url.searchParams.set('auth', token)
  return url.toString()
}

export const api = {
  listFolders: () => request<FoldersResponse>('/folders'),
  addFolder: (path: string) =>
    request<FolderDto>('/folders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path }),
    }),
  deleteFolder: (id: string) => request<void>(`/folders/${id}`, { method: 'DELETE' }),
  reindexFolder: (id: string) =>
    request<FolderDto>(`/folders/${id}/reindex`, { method: 'POST' }),
  search: (q: string, limit?: number) =>
    request<SearchResponse>('/search', {}, { q, limit }),
  browse: (folderId: string, path?: string) =>
    request<BrowseResponse>('/browse', {}, { folder_id: folderId, path }),
  thumbUrl: (id: string) => withAuthQuery(`/thumb/${id}`),
  fileUrl: (id: string) => withAuthQuery(`/file/${id}`),
  getStatus: () => request<StatusResponse>('/status'),
}
