<script setup lang="ts">
// Opens the native folder picker through the shell bridge, then registers it.
// Hidden entirely when running in a plain browser (no shell API).
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { useFoldersStore } from '../stores/folders'
import { ApiError } from '../api/client'
import { pickFolder, hasShellApi } from '../shell/bridge'

const emit = defineEmits<{ changed: [] }>()

const store = useFoldersStore()
const adding = ref(false)

async function onClick() {
  try {
    adding.value = true
    const dir = await pickFolder()
    if (!dir) return
    await store.add(dir)
    emit('changed')
  } catch (error) {
    const status = error instanceof ApiError ? ` (${error.status})` : ''
    ElMessage.error(`添加文件夹失败${status}`)
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
