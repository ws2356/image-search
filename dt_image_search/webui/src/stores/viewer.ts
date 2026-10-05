import { defineStore } from 'pinia'
import { ref } from 'vue'

// Page-local-ish context for the image viewer: the id list of the grid the
// user navigated from (search results or browse listing).
export const useViewerStore = defineStore('viewer', () => {
  const ids = ref<string[]>([])

  function setContext(newIds: string[]) {
    ids.value = newIds
  }

  function neighborOf(id: string, offset: number): string | null {
    const index = ids.value.indexOf(id)
    if (index === -1) return null
    const next = index + offset
    return next >= 0 && next < ids.value.length ? ids.value[next] : null
  }

  return { ids, setContext, neighborOf }
})
