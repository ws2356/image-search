<script setup lang="ts">
// App shell: top navigation + global status banner + routed view.
// Live events connect once here.
import { onMounted } from 'vue'
import { useEventsStore } from './stores/events'
import StatusBanner from './components/StatusBanner.vue'

const events = useEventsStore()

onMounted(() => {
  events.connect()
})
</script>

<template>
  <div class="app-root">
    <el-header class="app-header">
      <span class="app-title">AuSearch</span>
      <el-menu class="app-nav" mode="horizontal" :ellipsis="false" router>
        <el-menu-item index="/">浏览</el-menu-item>
        <el-menu-item index="/search">搜索</el-menu-item>
        <el-menu-item index="/settings">设置</el-menu-item>
      </el-menu>
    </el-header>
    <StatusBanner />
    <el-container class="app-container">
      <el-main>
        <router-view />
      </el-main>
    </el-container>
  </div>
</template>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  gap: var(--dts-space-l);
  border-block-end: 1px solid var(--dts-color-border);
  height: auto;
  padding: var(--dts-space-s) var(--dts-space-l);
}

.app-title {
  font-size: var(--dts-font-size-xl);
  font-weight: 600;
}

.app-nav {
  flex: 1;
  border-block-end: none;
}
</style>
