<script setup lang="ts">
// Settings/status page: model state + per-folder index status summary.
import { computed, onMounted, ref } from 'vue'
import { api, ApiError } from '../api/client'
import type { StatusResponse } from '../api/types'

const status = ref<StatusResponse | null>(null)
const error = ref<string | null>(null)
const loading = ref(true)

const MODEL_STATE_META: Record<string, { label: string; type: 'success' | 'warning' | 'danger' }> = {
  ready: { label: '就绪', type: 'success' },
  loading: { label: '加载中', type: 'warning' },
  failed: { label: '加载失败', type: 'danger' },
}

const modelBadge = computed(() => {
  const state = status.value?.model_state
  return MODEL_STATE_META[state ?? ''] ?? { label: state ?? '未知', type: 'info' as const }
})

onMounted(async () => {
  try {
    status.value = await api.getStatus()
  } catch (e) {
    error.value = e instanceof ApiError ? `加载状态失败 (${e.status})` : '加载状态失败'
  } finally {
    loading.value = false
  }
})

async function refresh() {
  loading.value = true
  try {
    status.value = await api.getStatus()
    error.value = null
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="settings-view" v-loading="loading">
    <div class="settings-header">
      <h2>设置与状态</h2>
      <el-button @click="refresh">刷新</el-button>
    </div>

    <el-alert v-if="error" type="error" :title="error" :closable="false" />

    <template v-else-if="status">
      <section class="card">
        <h3>模型</h3>
        <el-tag :type="modelBadge.type" size="large">{{ modelBadge.label }}</el-tag>
      </section>

      <section class="card">
        <h3>文件夹索引状态({{ status.folders.length }})</h3>
        <el-table v-if="status.folders.length" :data="status.folders">
          <el-table-column prop="path" label="路径" min-width="320" />
          <el-table-column prop="status" label="状态" width="120">
            <template #default="{ row }">
              <el-tag size="small" :type="row.status === 2 ? 'success' : row.status === 3 ? 'warning' : 'info'">
                {{ row.status === 2 ? '已索引' : row.status === 3 ? '部分失败' : row.status === 1 ? '索引中' : '扫描中' }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="added_at" label="添加时间" width="200" />
        </el-table>
        <el-empty v-else description="还没有注册文件夹" />
      </section>
    </template>
  </div>
</template>

<style scoped>
.settings-view {
  display: flex;
  flex-direction: column;
  gap: var(--dts-space-m);
  padding: var(--dts-space-m);
  max-width: 860px;
}

.settings-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.card {
  border: 1px solid var(--dts-color-border);
  border-radius: var(--dts-radius-m);
  padding: var(--dts-space-m);
  background: var(--dts-color-bg-surface);
}
</style>
