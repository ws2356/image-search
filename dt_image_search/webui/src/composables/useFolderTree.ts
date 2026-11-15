// Keep directory navigation local to the browse page; only roots are registered folders.
// Author: Codex
// Created: 2026-11-16
import { computed, ref, watch } from 'vue'
import { api } from '../api/client'
import type { FolderDto } from '../api/types'

export interface DirectoryNode {
  key: string
  root: FolderDto
  path: string
  label: string
  isRoot: boolean
}

interface Selection {
  folderId?: string
  path?: string
}

function directoryPath(path: string): string {
  return path.replaceAll('\\', '/').replace(/\/?$/, '/')
}

function nodeKey(folderId: string, path: string): string {
  return JSON.stringify([folderId, directoryPath(path)])
}

function directoryNode(root: FolderDto, path: string, isRoot = false): DirectoryNode {
  return {
    key: nodeKey(root.id, path),
    root,
    path: directoryPath(path),
    label: isRoot ? root.path : path.replace(/\/$/, '').split('/').at(-1) ?? path,
    isRoot,
  }
}

export function useFolderTree(folders: () => FolderDto[], selection: () => Selection) {
  const roots = computed(() => folders().map((folder) => directoryNode(folder, folder.path, true)))
  const expandedKeys = ref<string[]>([])
  const currentKey = computed(() => {
    const { folderId, path } = selection()
    return folderId && path ? nodeKey(folderId, path) : undefined
  })

  function expand(node: DirectoryNode) {
    if (!expandedKeys.value.includes(node.key)) expandedKeys.value.push(node.key)
  }

  function collapse(node: DirectoryNode) {
    expandedKeys.value = expandedKeys.value.filter((key) => key !== node.key)
  }

  // Breadcrumbs and directory buttons can select nodes that have not loaded yet.
  // Expanding their ancestors lets the lazy tree reveal and highlight the selection.
  watch(currentKey, () => {
    const { folderId, path } = selection()
    const root = folders().find((folder) => folder.id === folderId)
    if (!root || !path) return
    let ancestor = directoryPath(root.path)
    const destination = directoryPath(path)
    if (!destination.startsWith(ancestor)) return
    const keys = new Set(expandedKeys.value)
    for (const segment of destination.slice(ancestor.length).split('/').filter(Boolean)) {
      keys.add(nodeKey(root.id, ancestor))
      ancestor += `${segment}/`
    }
    expandedKeys.value = [...keys]
  }, { immediate: true })

  async function children(node: DirectoryNode): Promise<DirectoryNode[]> {
    const response = await api.browse(node.root.id, node.path)
    return response.subfolders.map((folder) => directoryNode(node.root, folder.path))
  }

  return { roots, expandedKeys, currentKey, expand, collapse, children }
}
