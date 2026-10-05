<script setup lang="ts">
// Registered-folder tree with index-status badges and per-node removal.
import { useFoldersStore } from '../stores/folders'
import type { FolderDto } from '../api/types'

const store = useFoldersStore()

const emit = defineEmits<{
  select: [folder: FolderDto]
  changed: []
}>()

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
  <el-tree
    class="folder-tree"
    :data="store.folders"
    node-key="id"
    :props="{ label: 'path' }"
    :expand-on-click-node="false"
    highlight-current
    @node-click="emit('select', $event as FolderDto)"
  >
    <template #default="{ data }">
      <span class="folder-node">
        <el-tag size="small" :type="badge(data.status).type">{{ badge(data.status).label }}</el-tag>
        <span class="folder-path" :title="data.path">{{ data.path }}</span>
        <el-popconfirm title="移除该文件夹并删除其索引?" confirm-button-text="移除" cancel-button-text="取消" @confirm="onDelete(data as FolderDto)">
          <template #reference>
            <el-button class="delete-btn" link type="danger" size="small">移除</el-button>
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

.folder-node:hover .delete-btn {
  visibility: visible;
}
</style>
