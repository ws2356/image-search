<script setup lang="ts">
// Thumbnail grid shared by search results and browse listings.
// Element Plus components are auto-imported; styles only use --dts-* tokens.
import { api } from '../api/client'

export interface GridItem {
  id: string
  path: string
  score?: number
}

withDefaults(defineProps<{ items: GridItem[]; showScore?: boolean }>(), { showScore: false })

const emit = defineEmits<{ open: [id: string] }>()

function open(id: string) {
  emit('open', id)
}
</script>

<template>
  <div class="image-grid">
    <button
      v-for="item in items"
      :key="item.id"
      class="grid-cell"
      type="button"
      @click="open(item.id)"
    >
      <el-image
        class="thumb"
        :src="api.thumbUrl(item.id)"
        fit="cover"
        lazy
      >
        <template #error>
          <div class="thumb-fallback">?</div>
        </template>
      </el-image>
      <el-tag v-if="showScore && item.score !== undefined" class="score-tag" size="small" type="info">
        {{ item.score.toFixed(3) }}
      </el-tag>
    </button>
  </div>
</template>

<style scoped>
.image-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: var(--dts-space-s);
}

.grid-cell {
  position: relative;
  border: none;
  padding: 0;
  background: none;
  cursor: pointer;
  border-radius: var(--dts-radius-m);
  overflow: hidden;
}

.thumb {
  width: 100%;
  aspect-ratio: 1;
  display: block;
  background: var(--dts-color-bg-page);
}

.thumb-fallback {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  color: var(--dts-color-text-muted);
  font-size: var(--dts-font-size-xl);
}

.score-tag {
  position: absolute;
  inset-block-end: var(--dts-space-xs);
  inset-inline-start: var(--dts-space-xs);
}
</style>
