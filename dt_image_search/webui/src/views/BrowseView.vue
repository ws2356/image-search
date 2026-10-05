<script setup lang="ts">
// Browse page: folder tree on the left, the selected folder's direct child
// images on the right. UI only — all data comes from the index server API.
import { onMounted, ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api/client'
import type { FolderDto, FileDto } from '../api/types'
import { useFoldersStore } from '../stores/folders'
import { useViewerStore } from '../stores/viewer'
import FolderTree from '../components/FolderTree.vue'
import ImageGrid from '../components/ImageGrid.vue'
import AddFolderButton from '../components/AddFolderButton.vue'

const router = useRouter()
const folderStore = useFoldersStore()
const viewer = useViewerStore()
const hasFolders = computed(() => folderStore.folders.length > 0)
const selectedFolder = ref<FolderDto | null>(null)
const files = ref<FileDto[]>([])
const loadingFiles = ref(false)

onMounted(() => {
  void folderStore.load()
})

async function refresh() {
  if (!selectedFolder.value) return
  loadingFiles.value = true
  try {
    files.value = (await api.browse(selectedFolder.value.id)).files
  } finally {
    loadingFiles.value = false
  }
}

async function onSelect(folder: FolderDto) {
  selectedFolder.value = folder
  await refresh()
}

function onTreeChanged() {
  if (selectedFolder.value) {
    void refresh()
  }
}

function open(id: string) {
  viewer.setContext(files.value.map((f) => f.id))
  void router.push(`/viewer/${id}`)
}
</script>

<template>
  <el-container class="browse-view">
    <el-aside width="320px" class="folder-aside">
      <div class="aside-header">
        <AddFolderButton @changed="onTreeChanged" />
        <el-button link @click="refresh">刷新</el-button>
      </div>
      <el-empty v-if="!hasFolders" description="还没有文件夹,点击“添加文件夹”开始" />
      <FolderTree v-else @select="onSelect" @changed="onTreeChanged" />
    </el-aside>
    <el-main class="files-main">
      <el-empty v-if="!selectedFolder" description="选择左侧文件夹浏览图片" />
      <ImageGrid v-else :items="files" @open="open" />
    </el-main>
  </el-container>
</template>

<style scoped>
.browse-view {
  height: calc(100vh - var(--dts-space-l));
}

.folder-aside {
  border-inline-end: 1px solid var(--dts-color-border);
  padding: var(--dts-space-m);
  overflow: auto;
}

.aside-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-block-end: var(--dts-space-m);
}

.files-main {
  overflow: auto;
}
</style>
