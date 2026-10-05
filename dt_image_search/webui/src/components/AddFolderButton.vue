<script setup lang="ts">
// Opens the native folder picker through the shell bridge, then registers it.
// Hidden entirely when running in a plain browser (no shell API).
import { ref } from 'vue'
import { useFoldersStore } from '../stores/folders'
import { pickFolder, hasShellApi } from '../shell/bridge'

const emit = defineEmits<{ changed: [] }>()

const store = useFoldersStore()
const adding = ref(false)

async function onClick() {
  const dir = await pickFolder()
  if (!dir) return
  adding.value = true
  try {
    await store.add(dir)
    emit('changed')
  } finally {
    adding.value = false
  }
}
</script>

<template>
  <el-button v-if="hasShellApi()" type="primary" :loading="adding" @click="onClick">
    添加文件夹
  </el-button>
</template>
