<script setup lang="ts">
// Browse page: folder tree on the left, the selected folder's direct child
// images on the right (descend into subfolders; breadcrumb to go back up).
// UI only — all data comes from the index server API; live fs_changed events
// debounce-refresh the current view.
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api/client'
import type { FolderDto, FileDto } from '../api/types'
import { useFoldersStore } from '../stores/folders'
import { useViewerStore } from '../stores/viewer'
import { useEventsStore } from '../stores/events'
import { useLiveRefresh } from '../composables/useLiveRefresh'
import FolderTree from '../components/FolderTree.vue'
import ImageGrid from '../components/ImageGrid.vue'
import AddFolderButton from '../components/AddFolderButton.vue'

const router = useRouter()
const folderStore = useFoldersStore()
const viewer = useViewerStore()
const events = useEventsStore()
const hasFolders = computed(() => folderStore.folders.length > 0)
const selectedFolder = ref<FolderDto | null>(null)
const currentPath = ref<string>('')
const subfolders = ref<FolderDto[]>([])
const files = ref<FileDto[]>([])
const loadingFiles = ref(false)
const browseError = ref<string | null>(null)
const folderTree = ref<InstanceType<typeof FolderTree> | null>(null)
let browseRevision = 0

onMounted(() => {
  void refreshAll()
})

useLiveRefresh(events, () => { void refreshAll() })

watch(() => folderStore.folders, (folders) => {
  if (!selectedFolder.value) return
  const root = folders.find((folder) => folder.id === selectedFolder.value?.id)
  selectedFolder.value = root ?? null
  if (!root) {
    browseRevision += 1
    currentPath.value = ''
    files.value = []
    subfolders.value = []
    loadingFiles.value = false
    browseError.value = null
  }
})

async function refresh() {
  if (!selectedFolder.value) return
  const revision = ++browseRevision
  loadingFiles.value = true
  browseError.value = null
  files.value = []
  subfolders.value = []
  try {
    const resp = await api.browse(selectedFolder.value.id, currentPath.value)
    if (revision !== browseRevision) return
    files.value = resp.files
    subfolders.value = resp.subfolders
  } catch {
    if (revision === browseRevision) browseError.value = '无法读取目录，请确认目录仍存在且有访问权限后刷新'
  } finally {
    if (revision === browseRevision) loadingFiles.value = false
  }
}

async function refreshAll() {
  try {
    await folderStore.load()
    folderTree.value?.refresh()
    await refresh()
  } catch {
    browseError.value = '无法刷新文件夹列表，请重试'
  }
}

async function onSelect(folder: FolderDto, path: string = folder.path) {
  selectedFolder.value = folder
  currentPath.value = path
  await refresh()
}

async function descend(path: string) {
  currentPath.value = path
  await refresh()
}

async function toRoot() {
  if (selectedFolder.value) {
    currentPath.value = selectedFolder.value.path
    await refresh()
  }
}

function onTreeChanged() {
  void refreshAll()
}

function open(id: string) {
  viewer.setContext(files.value.map((f) => ({ id: f.id, path: f.path })))
  void router.push(`/viewer/${id}`)
}

const crumbs = computed(() => {
  if (!selectedFolder.value || !currentPath.value) return []
  const root = selectedFolder.value.path.replace(/\/?$/, '/')
  if (currentPath.value === root) return []
  let acc = root
  return currentPath.value.slice(root.length)
    .split('/')
    .filter(Boolean)
    .map((segment) => {
      acc += segment + '/'
      return { label: segment, path: acc }
    })
})
</script>

<template>
  <el-container class="browse-view">
    <el-aside width="var(--dts-layout-sidebar-width)" class="folder-aside">
      <div class="aside-header">
        <AddFolderButton @changed="onTreeChanged" />
        <el-button link @click="refreshAll">刷新</el-button>
      </div>
      <el-empty v-if="!hasFolders" description="还没有文件夹,点击“添加文件夹”开始" />
      <FolderTree
        v-else
        ref="folderTree"
        :selected-folder-id="selectedFolder?.id"
        :selected-path="currentPath"
        @select="onSelect"
        @changed="onTreeChanged"
      />
    </el-aside>
    <el-main class="files-main" v-loading="loadingFiles">
      <el-alert v-if="browseError" :title="browseError" type="error" :closable="false" />
      <el-empty v-if="!selectedFolder" description="选择左侧文件夹浏览图片" />
      <template v-else>
        <el-breadcrumb v-if="crumbs.length" class="crumbs">
          <el-breadcrumb-item>
            <el-link underline="never" @click="toRoot">根目录</el-link>
          </el-breadcrumb-item>
          <el-breadcrumb-item v-for="crumb in crumbs" :key="crumb.path">
            <el-link underline="never" @click="descend(crumb.path)">{{ crumb.label }}</el-link>
          </el-breadcrumb-item>
        </el-breadcrumb>

        <div v-if="subfolders.length" class="subfolders">
          <el-button
            v-for="sub in subfolders"
            :key="sub.path"
            size="small"
            @click="descend(sub.path)"
          >
            📁 {{ sub.path.replace(selectedFolder.path, '') }}
          </el-button>
        </div>

        <el-empty v-if="!files.length && !loadingFiles && !browseError" description="此目录下没有图片" />
        <ImageGrid v-else :items="files" @open="open" />
      </template>
    </el-main>
  </el-container>
</template>

<style scoped>
.browse-view {
  height: calc(100vh - var(--dts-space-l));
}

.folder-aside {
  border-inline-end: var(--dts-border-width) solid var(--dts-color-border);
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

.crumbs {
  margin-block-end: var(--dts-space-m);
}

.subfolders {
  display: flex;
  flex-wrap: wrap;
  gap: var(--dts-space-xs);
  margin-block-end: var(--dts-space-m);
}
</style>
