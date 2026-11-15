<script setup lang="ts">
// Lazy directory tree; status and removal belong only to registered roots.
import { ref } from 'vue'
import type { LoadFunction } from 'element-plus'
import { useFoldersStore } from '../stores/folders'
import { useFolderTree, type DirectoryNode } from '../composables/useFolderTree'
import type { FolderDto } from '../api/types'

const props = defineProps<{ selectedFolderId?: string; selectedPath?: string }>()
const store = useFoldersStore()
const { roots, expandedKeys, currentKey, expand, collapse, children } = useFolderTree(
  () => store.folders,
  () => ({ folderId: props.selectedFolderId, path: props.selectedPath }),
)
const generation = ref(0)
const loadError = ref<string | null>(null)

const emit = defineEmits<{
  select: [folder: FolderDto, path: string]
  changed: []
}>()

const loadNode: LoadFunction = async (node, resolve, reject) => {
  if (node.level === 0) {
    resolve(roots.value)
    return
  }
  const directory = node.data as DirectoryNode
  const requestGeneration = generation.value
  try {
    const nodes = await children(directory)
    resolve(nodes)
    if (requestGeneration === generation.value) loadError.value = null
  } catch {
    if (requestGeneration === generation.value) loadError.value = `无法读取 ${directory.path}，请重试`
    reject()
  }
}

function refresh() {
  loadError.value = null
  generation.value += 1
}

defineExpose({ refresh })

const STATUS_META: Record<number, { label: string; type: 'info' | 'primary' | 'success' | 'warning' }> = {
  0: { label: '扫描中', type: 'info' },
  1: { label: '索引中', type: 'primary' },
  2: { label: '已索引', type: 'success' },
  3: { label: '部分失败', type: 'warning' },
}

function badge(status: number) {
  return STATUS_META[status] ?? { label: `状态 ${status}`, type: 'info' as const }
}

async function onDelete(folder: FolderDto) {
  await store.remove(folder.id)
  emit('changed')
}
</script>

<template>
  <el-alert v-if="loadError" :title="loadError" type="error" :closable="false" />
  <el-tree
    :key="generation"
    class="folder-tree"
    :data="roots"
    node-key="key"
    :props="{ label: 'label' }"
    lazy
    :load="loadNode"
    :default-expanded-keys="expandedKeys"
    :current-node-key="currentKey"
    :auto-expand-parent="false"
    :expand-on-click-node="true"
    highlight-current
    @node-click="(data: DirectoryNode) => emit('select', data.root, data.path)"
    @node-expand="expand"
    @node-collapse="collapse"
  >
    <template #default="{ data }">
      <span class="folder-node">
        <el-tag v-if="data.isRoot" size="small" :type="badge(data.root.status).type">{{ badge(data.root.status).label }}</el-tag>
        <span class="folder-path" :title="data.path">{{ data.label }}</span>
        <el-popconfirm v-if="data.isRoot" title="移除该文件夹并删除其索引?" confirm-button-text="移除" cancel-button-text="取消" @confirm="onDelete(data.root)">
          <template #reference>
            <el-button class="delete-btn" link type="danger" size="small" @click.stop>移除</el-button>
          </template>
        </el-popconfirm>
      </span>
    </template>
  </el-tree>
</template>

<style scoped>
.folder-tree {
  background: transparent;
}

.folder-node {
  display: flex;
  align-items: center;
  gap: var(--dts-space-s);
  width: 100%;
  min-width: 0;
  padding-inline-end: var(--dts-space-s);
}

.folder-path {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--dts-font-size-s);
}

.delete-btn {
  visibility: hidden;
}

.folder-node:hover .delete-btn,
.folder-node:focus-within .delete-btn {
  visibility: visible;
}
</style>
