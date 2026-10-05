import { describe, expect, it, beforeEach, vi } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useFoldersStore } from '../src/stores/folders'

vi.mock('../src/api/client', () => ({
  api: {
    listFolders: vi.fn(),
    addFolder: vi.fn(),
    deleteFolder: vi.fn(),
    reindexFolder: vi.fn(),
  },
}))

import { api } from '../src/api/client'

const FOLDER_A = { id: '1', path: '/a/', status: 2, added_at: 'x' }
const FOLDER_B = { id: '2', path: '/b/', status: 0, added_at: 'x' }

describe('useFoldersStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  it('load() populates folders', async () => {
    ;(api.listFolders as ReturnType<typeof vi.fn>).mockResolvedValue({ folders: [FOLDER_A, FOLDER_B] })

    const store = useFoldersStore()
    await store.load()

    expect(store.folders).toEqual([FOLDER_A, FOLDER_B])
  })

  it('add() refreshes from the list regardless of 200/201 branch', async () => {
    ;(api.addFolder as ReturnType<typeof vi.fn>).mockResolvedValue(FOLDER_B)
    ;(api.listFolders as ReturnType<typeof vi.fn>).mockResolvedValue({ folders: [FOLDER_A, FOLDER_B] })

    const store = useFoldersStore()
    await store.add('/b')

    expect(api.addFolder).toHaveBeenCalledWith('/b')
    expect(store.folders).toEqual([FOLDER_A, FOLDER_B])  // exactly one entry for /b
  })

  it('remove() refreshes the list', async () => {
    ;(api.deleteFolder as ReturnType<typeof vi.fn>).mockResolvedValue(undefined)
    ;(api.listFolders as ReturnType<typeof vi.fn>).mockResolvedValue({ folders: [FOLDER_A] })

    const store = useFoldersStore()
    await store.remove('2')

    expect(api.deleteFolder).toHaveBeenCalledWith('2')
    expect(store.folders).toEqual([FOLDER_A])
  })
})
