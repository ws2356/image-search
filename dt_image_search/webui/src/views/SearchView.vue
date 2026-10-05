<script setup lang="ts">
// Text-to-image search page: debounced query → merged per-folder CLIP results.
import { useSearchStore } from '../stores/search'
import { useViewerStore } from '../stores/viewer'
import { useRouter } from 'vue-router'
import ImageGrid from '../components/ImageGrid.vue'

const store = useSearchStore()
const viewer = useViewerStore()
const router = useRouter()

function open(id: string) {
  viewer.setContext(store.results.map((r) => ({ id: r.id, path: r.path })))
  void router.push(`/viewer/${id}`)
}
</script>

<template>
  <div class="search-view">
    <el-input
      class="search-input"
      v-model="store.query"
      placeholder="描述要找的图片,例如:海滩日落"
      clearable
      @input="store.runSearch"
    >
      <template #prefix>
        <el-icon><i-search /></el-icon>
      </template>
    </el-input>

    <el-alert
      v-if="store.modelState === 'loading'"
      class="state-alert"
      type="info"
      :closable="false"
      title="模型加载中"
      description="本地模型正在加载,搜索暂不可用,稍候再试。"
    />
    <el-alert
      v-else-if="store.modelState === 'failed'"
      class="state-alert"
      type="error"
      :closable="false"
      title="模型加载失败"
      description="本地模型加载失败,请重启应用或检查模型缓存。"
    />

    <ImageGrid v-else-if="store.results.length" :items="store.results" show-score @open="open" />
    <el-empty v-else-if="!store.searching" description="输入关键词在本地文件夹中搜索图片" />
  </div>
</template>

<style scoped>
.search-view {
  display: flex;
  flex-direction: column;
  gap: var(--dts-space-m);
  padding: var(--dts-space-m);
}

.search-input {
  max-width: 640px;
  font-size: var(--dts-font-size-m);
}
</style>
