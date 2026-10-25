import { describe, expect, it, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import AddFolderButton from '../src/components/AddFolderButton.vue'

vi.mock('element-plus', async () => {
  const actual = await import('element-plus')
  return {
    ...actual,
    ElMessage: { error: vi.fn() },
  }
})

vi.mock('../src/shell/bridge', () => ({
  hasShellApi: vi.fn(),
  pickFolder: vi.fn(),
}))

vi.mock('../src/stores/folders', () => {
  const store = { add: vi.fn() }
  return { useFoldersStore: () => store }
})

import { hasShellApi, pickFolder } from '../src/shell/bridge'
import { useFoldersStore } from '../src/stores/folders'
import { ElMessage } from 'element-plus'

function mountButton() {
  return mount(AddFolderButton, {
    props: { onChanged: undefined },
  })
}

describe('AddFolderButton', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    delete window.pywebview
  })

  it('adds the selected folder and emits changed', async () => {
    ;(hasShellApi as ReturnType<typeof vi.fn>).mockReturnValue(true)
    ;(pickFolder as ReturnType<typeof vi.fn>).mockResolvedValue('/photos')
    ;(useFoldersStore().add as ReturnType<typeof vi.fn>).mockResolvedValue(undefined)

    const wrapper = mountButton()
    await wrapper.find('button').trigger('click')
    await vi.waitFor(() => expect(useFoldersStore().add).toHaveBeenCalledWith('/photos'))

    expect(wrapper.emitted('changed')).toEqual([[]])
    expect(wrapper.find('button').classes()).not.toContain('is-loading')
  })

  it('shows an error when folder registration fails', async () => {
    ;(hasShellApi as ReturnType<typeof vi.fn>).mockReturnValue(true)
    ;(pickFolder as ReturnType<typeof vi.fn>).mockResolvedValue('/photos')
    ;(useFoldersStore().add as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('offline'))

    const wrapper = mountButton()
    await wrapper.find('button').trigger('click')

    await vi.waitFor(() => expect(ElMessage.error).toHaveBeenCalledWith('添加文件夹失败'))
    expect(wrapper.emitted('changed')).toBeUndefined()
  })
})
