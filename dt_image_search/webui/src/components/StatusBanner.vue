<script setup lang="ts">
// Global status banner: latest status_message from the live event stream,
// plus the model-load-failure alarm. Rendered once in App.vue.
import { useEventsStore } from '../stores/events'

const store = useEventsStore()
</script>

<template>
  <el-alert
    v-if="store.modelLoadFailed"
    class="banner"
    type="error"
    :closable="true"
    title="模型加载失败"
    description="本地模型加载失败,索引与搜索暂不可用。请重启应用重试。"
    @close="store.clearModelLoadFailed()"
  />
  <el-alert
    v-else-if="store.latestStatusMessage"
    class="banner"
    type="info"
    :closable="true"
    :title="store.latestStatusMessage"
    @close="store.clearStatusMessage()"
  />
</template>

<style scoped>
.banner {
  border-radius: var(--dts-radius-s);
}
</style>
