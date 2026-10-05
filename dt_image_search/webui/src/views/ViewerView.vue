<script setup lang="ts">
// Full-size image viewer with keyboard navigation within the list the user
// came from (search results or browse listing).
import { computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api/client'
import { useViewerStore } from '../stores/viewer'

const route = useRoute()
const router = useRouter()
const viewer = useViewerStore()

const fileId = computed(() => String(route.params.fileId))
const prevId = computed(() => viewer.neighborOf(fileId.value, -1))
const nextId = computed(() => viewer.neighborOf(fileId.value, +1))

function goTo(id: string | null) {
  if (id) void router.push(`/viewer/${id}`)
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'ArrowLeft') goTo(prevId.value)
  else if (e.key === 'ArrowRight') goTo(nextId.value)
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <div class="viewer-view">
    <div class="viewer-toolbar">
      <el-button :disabled="!prevId" @click="goTo(prevId)">← 上一张</el-button>
      <el-button :disabled="!nextId" @click="goTo(nextId)">下一张 →</el-button>
      <span class="viewer-path">{{ fileId }}</span>
    </div>
    <div class="viewer-stage">
      <img class="viewer-image" :src="api.fileUrl(fileId)" :alt="fileId" />
    </div>
  </div>
</template>

<style scoped>
.viewer-view {
  display: flex;
  flex-direction: column;
  gap: var(--dts-space-s);
  height: calc(100vh - var(--dts-space-l));
  padding: var(--dts-space-m);
}

.viewer-toolbar {
  display: flex;
  align-items: center;
  gap: var(--dts-space-s);
}

.viewer-path {
  color: var(--dts-color-text-muted);
  font-size: var(--dts-font-size-s);
}

.viewer-stage {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 0;
  border-radius: var(--dts-radius-m);
  background: var(--dts-color-bg-page);
}

.viewer-image {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}
</style>
