<script setup lang="ts">
// App shell: global status banner + routed view. Live events connect once here.
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
    <StatusBanner />
    <el-container class="app-container">
      <el-main>
        <router-view />
      </el-main>
    </el-container>
  </div>
</template>

<style scoped>
.app-container {
  min-height: 100vh;
}
</style>
