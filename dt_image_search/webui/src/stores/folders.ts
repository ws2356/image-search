import { defineStore } from 'pinia'
import { ref } from 'vue'
import { api } from '../api/client'
import type { FolderDto } from '../api/types'

export const useFoldersStore = defineStore('folders', () => {
  const folders = ref<FolderDto[]>([])

  async function load() {
    folders.value = (await api.listFolders()).folders
  }

  /** Idempotent: both the 201-created and 200-already-registered branches
   * converge to a single list refresh. */
  async function add(path: string) {
    await api.addFolder(path)
    await load()
  }

  async function remove(id: string) {
    await api.deleteFolder(id)
    await load()
  }

  async function reindex(id: string) {
    await api.reindexFolder(id)
    await load()
  }

  return { folders, load, add, remove, reindex }
})
