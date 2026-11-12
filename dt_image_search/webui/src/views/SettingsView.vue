<script setup lang="ts">
// Settings/status page: model state + per-folder index status summary.
import { computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useStatusStore } from '../stores/status'

const statusStore = useStatusStore()
const { snapshot: status, error, loading } = storeToRefs(statusStore)

const MODEL_STATE_META: Record<string, { label: string; type: 'success' | 'warning' | 'danger' }> = {
  ready: { label: '就绪', type: 'success' },
  loading: { label: '加载中', type: 'warning' },
  failed: { label: '加载失败', type: 'danger' },
}

const modelBadge = computed(() => {
  const state = status.value?.model_state
  return MODEL_STATE_META[state ?? ''] ?? { label: state ?? '未知', type: 'info' as const }
})

onMounted(() => {
  void statusStore.refresh()
})
</script>

<template>
  <div class="settings-view" v-loading="loading">
    <div class="settings-header">
      <h2>设置与状态</h2>
      <el-button @click="statusStore.refresh">刷新</el-button>
    </div>

    <el-alert v-if="error" type="error" :title="error" :closable="false" />

    <template v-else-if="status">
      <section class="card">
        <h3>模型</h3>
        <el-tag :type="modelBadge.type" size="large">{{ modelBadge.label }}</el-tag>
      </section>

      <section class="card">
        <h3>文件夹索引状态({{ status.folders.length }})</h3>
        <el-table v-if="status.folders.length" :data="status.folders" table-layout="auto">
          <el-table-column prop="path" label="路径" />
          <el-table-column prop="status" label="状态">
            <template #default="{ row }">
              <el-tag size="small" :type="row.status === 2 ? 'success' : row.status === 3 ? 'warning' : 'info'">
                {{ row.status === 2 ? '已索引' : row.status === 3 ? '部分失败' : row.status === 1 ? '索引中' : '扫描中' }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="added_at" label="添加时间" />
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
  max-width: var(--dts-layout-settings-width);
}

.settings-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.card {
  border: var(--dts-border-width) solid var(--dts-color-border);
  border-radius: var(--dts-radius-m);
  padding: var(--dts-space-m);
  background: var(--dts-color-bg-surface);
}
</style>
