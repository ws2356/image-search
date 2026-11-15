// Exercise lazy directory navigation with the real tree and folder store.
// Author: Codex
// Created: 2026-11-16
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import FolderTree from '../src/components/FolderTree.vue'
import { useFoldersStore } from '../src/stores/folders'
import type { FolderDto } from '../src/api/types'

vi.mock('../src/api/client', () => ({
  api: { browse: vi.fn() },
}))

import { api } from '../src/api/client'

const PHOTOS: FolderDto = { id: '1', path: '/photos/', status: 2, added_at: 'x' }
const WORK: FolderDto = { id: '2', path: '/work/', status: 1, added_at: 'x' }
let wrapper: VueWrapper

function row(path: string) {
  const result = wrapper.findAll('.el-tree-node__content')
    .find((content) => content.find('.folder-path').attributes('title') === path)
  if (!result) throw new Error(`Missing directory row: ${path}`)
  return result
}

function renderTree() {
  const pinia = createPinia()
  setActivePinia(pinia)
  useFoldersStore().folders = [PHOTOS, WORK]
  wrapper = mount(FolderTree, { global: { plugins: [pinia] } })
}

describe('FolderTree directories', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.browse).mockImplementation(async (id, path) => ({
      folder: id === PHOTOS.id ? PHOTOS : WORK,
      subfolders: path === '/photos/'
        ? [{ ...PHOTOS, path: '/photos/2026/' }, { ...PHOTOS, path: '/photos/empty/' }]
        : path === '/photos/2026/' ? [{ ...PHOTOS, path: '/photos/2026/trip/' }] : [],
      files: [],
    }))
  })

  afterEach(() => wrapper?.unmount())

  it('shows independent registered roots without recursively scanning them', () => {
    renderTree()
    expect(wrapper.findAll('.folder-path').map((label) => label.text())).toEqual(['/photos/', '/work/'])
    expect(api.browse).not.toHaveBeenCalled()
  })

  it('expands successive directory levels with root ownership and distinct path keys', async () => {
    renderTree()
    await row('/photos/').trigger('click')
    await flushPromises()
    expect(row('/photos/2026/').text()).toBe('2026')
    expect(row('/photos/empty/').text()).toBe('empty')
    expect(api.browse).toHaveBeenCalledTimes(1)

    await row('/photos/2026/').trigger('click')
    await flushPromises()
    expect(api.browse).toHaveBeenLastCalledWith('1', '/photos/2026/')
    expect(row('/photos/2026/trip/').exists()).toBe(true)
    expect(wrapper.emitted('select')?.at(-1)).toEqual([PHOTOS, '/photos/2026/'])
    expect(row('/work/').exists()).toBe(true)
    expect(wrapper.findAll('.delete-btn')).toHaveLength(2)
    expect(wrapper.findAll('.el-tag')).toHaveLength(2)
  })

  it('keeps empty directories selectable and collapses without fetching again', async () => {
    renderTree()
    await row('/photos/').trigger('click')
    await flushPromises()
    await row('/photos/empty/').trigger('click')
    await flushPromises()
    expect(wrapper.emitted('select')?.at(-1)).toEqual([PHOTOS, '/photos/empty/'])
    const calls = vi.mocked(api.browse).mock.calls.length
    await row('/photos/').trigger('click')
    await row('/photos/').trigger('click')
    await flushPromises()
    expect(api.browse).toHaveBeenCalledTimes(calls)
  })

  it('allows a failed directory load to be retried', async () => {
    vi.mocked(api.browse).mockRejectedValueOnce(new Error('offline'))
    renderTree()
    await row('/photos/').trigger('click')
    await flushPromises()
    expect(wrapper.find('.el-alert').text()).toContain('无法读取 /photos/')
    await row('/photos/').trigger('click')
    await flushPromises()
    expect(row('/photos/2026/').exists()).toBe(true)
    expect(wrapper.find('.el-alert').exists()).toBe(false)
  })

  it('reloads expanded branches on refresh and shows newly created directories', async () => {
    renderTree()
    await row('/photos/').trigger('click')
    await flushPromises()
    vi.mocked(api.browse).mockResolvedValue({
      folder: PHOTOS, subfolders: [{ ...PHOTOS, path: '/photos/new/' }], files: [],
    })
    wrapper.vm.$.exposed!.refresh()
    await flushPromises()
    expect(row('/photos/new/').exists()).toBe(true)
    expect(wrapper.findAll('.folder-path').some((label) => label.text() === '2026')).toBe(false)
  })

  it('reveals and highlights a directory selected through breadcrumbs or browse buttons', async () => {
    renderTree()
    await wrapper.setProps({ selectedFolderId: '1', selectedPath: '/photos/2026/trip/' })
    await flushPromises()
    expect(row('/photos/2026/trip/').element.parentElement?.classList.contains('is-current')).toBe(true)
    expect(api.browse).toHaveBeenCalledWith('1', '/photos/2026/')
  })

  it('updates roots when a folder is registered or removed', async () => {
    renderTree()
    useFoldersStore().folders = [WORK, { ...PHOTOS, id: '3', path: '/archive/' }]
    await flushPromises()
    expect(wrapper.findAll('.folder-path').map((label) => label.text())).toEqual(['/work/', '/archive/'])
  })
})
