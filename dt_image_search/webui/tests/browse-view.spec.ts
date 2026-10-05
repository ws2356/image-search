import { describe, expect, it, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import { createPinia } from 'pinia'
import BrowseView from '../src/views/BrowseView.vue'
import FolderTree from '../src/components/FolderTree.vue'

vi.mock('../src/api/client', () => ({
  api: {
    listFolders: vi.fn().mockResolvedValue({ folders: [] }),
    browse: vi.fn(),
  },
}))

vi.mock('../src/stores/folders', () => {
  const store = {
    folders: [{ id: '5', path: '/photos/', status: 2, added_at: 'x' }],
    load: vi.fn(),
    add: vi.fn(),
    remove: vi.fn(),
    reindex: vi.fn(),
  }
  return { useFoldersStore: () => store }
})

import { api } from '../src/api/client'

const FOLDER = { id: '5', path: '/photos/', status: 2, added_at: 'x' }

function mountView() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: BrowseView },
      { path: '/search', component: { template: '<div />' } },
      { path: '/settings', component: { template: '<div />' } },
      { path: '/viewer/:fileId', component: { template: '<div />' } },
    ],
  })
  return mount(BrowseView, { global: { plugins: [router, createPinia()] } })
}

describe('BrowseView subfolder navigation', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    sessionStorage.clear()
    window.history.replaceState(null, '', '/')
    sessionStorage.setItem('dts-auth', 'tok')
  })

  it('lists direct files of the selected folder root', async () => {
    ;(api.browse as ReturnType<typeof vi.fn>).mockResolvedValue({
      folder: FOLDER,
      subfolders: [],
      files: [{ id: '1', path: '/photos/a.jpg', folder_id: '5', status: 1 }],
    })

    const wrapper = mountView()
    wrapper.findComponent(FolderTree).vm.$emit('select', FOLDER)
    await vi.dynamicImportSettled()
    await vi.waitFor(() => expect(api.browse).toHaveBeenCalledWith('5', '/photos/'))

    expect((api.browse as ReturnType<typeof vi.fn>).mock.calls[0][1]).toBe('/photos/')
  })

  it('descends into a subfolder with its full path', async () => {
    ;(api.browse as ReturnType<typeof vi.fn>).mockResolvedValue({
      folder: FOLDER,
      subfolders: [{ id: '5', path: '/photos/2024/', status: 2, added_at: 'x' }],
      files: [],
    })

    const wrapper = mountView()
    wrapper.findComponent(FolderTree).vm.$emit('select', FOLDER)
    await vi.waitFor(() => expect(wrapper.find('.subfolders .el-button').exists()).toBe(true))
    await wrapper.find('.subfolders .el-button').trigger('click')
    await vi.waitFor(() =>
      expect((api.browse as ReturnType<typeof vi.fn>).mock.calls.at(-1)).toEqual(['5', '/photos/2024/']),
    )
  })

  it('breadcrumb navigates back to the root', async () => {
    ;(api.browse as ReturnType<typeof vi.fn>).mockResolvedValue({
      folder: FOLDER,
      subfolders: [{ id: '5', path: '/photos/2024/', status: 2, added_at: 'x' }],
      files: [],
    })

    const wrapper = mountView()
    wrapper.findComponent(FolderTree).vm.$emit('select', FOLDER)
    await vi.waitFor(() => expect(wrapper.find('.subfolders .el-button').exists()).toBe(true))
    await wrapper.find('.subfolders .el-button').trigger('click')
    await vi.waitFor(() => expect(wrapper.find('.crumbs .el-link').exists()).toBe(true))
    const callsBefore = (api.browse as ReturnType<typeof vi.fn>).mock.calls.length

    await wrapper.find('.crumbs .el-link').trigger('click')  // “根目录” link
    await vi.waitFor(() => {
      const last = (api.browse as ReturnType<typeof vi.fn>).mock.calls.at(-1)
      expect(last).toEqual(['5', '/photos/'])
      expect((api.browse as ReturnType<typeof vi.fn>).mock.calls.length).toBeGreaterThan(callsBefore)
    })
  })
})
