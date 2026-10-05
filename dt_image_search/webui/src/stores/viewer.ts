import { defineStore } from 'pinia'
import { ref } from 'vue'

export interface ViewerItem {
  id: string
  path: string
}

// Context for the image viewer: the items of the grid the user navigated
// from (search results or browse listing).
export const useViewerStore = defineStore('viewer', () => {
  const items = ref<ViewerItem[]>([])

  function setContext(newItems: ViewerItem[]) {
    items.value = newItems
  }

  function current(id: string): ViewerItem | null {
    return items.value.find((item) => item.id === id) ?? null
  }

  function neighborOf(id: string, offset: number): string | null {
    const index = items.value.findIndex((item) => item.id === id)
    if (index === -1) return null
    const next = index + offset
    return next >= 0 && next < items.value.length ? items.value[next].id : null
  }

  return { items, setContext, current, neighborOf }
})
