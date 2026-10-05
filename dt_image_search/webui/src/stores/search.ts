import { defineStore } from 'pinia'
import { ref } from 'vue'
import { api, ModelNotReady } from '../api/client'
import type { SearchResultDto } from '../api/types'

const DEBOUNCE_MS = 300

export const useSearchStore = defineStore('search', () => {
  const query = ref('')
  const results = ref<SearchResultDto[]>([])
  const searching = ref(false)
  const modelState = ref<string | null>(null)

  let timer: ReturnType<typeof setTimeout> | null = null
  let seq = 0

  async function _execute(q: string) {
    seq += 1
    const my = seq
    searching.value = true
    try {
      const resp = await api.search(q)
      if (my !== seq) return // superseded by a newer query
      results.value = resp.results
      modelState.value = null
    } catch (e) {
      if (my !== seq) return
      if (e instanceof ModelNotReady) {
        // Show a hint, not a fake "no results" page.
        modelState.value = e.modelState
      } else {
        throw e
      }
    } finally {
      if (my === seq) searching.value = false
    }
  }

  function runSearch(q: string) {
    query.value = q
    if (timer) clearTimeout(timer)
    if (!q.trim()) {
      results.value = []
      modelState.value = null
      searching.value = false
      seq += 1 // invalidate any in-flight request
      return
    }
    timer = setTimeout(() => void _execute(q), DEBOUNCE_MS)
  }

  return { query, results, searching, modelState, runSearch }
})
