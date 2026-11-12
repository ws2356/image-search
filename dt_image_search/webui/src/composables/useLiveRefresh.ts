// Composable: debounce-refresh a view when the server announces fs_changed
// over the WebSocket (file system changes land in batches).
import { getCurrentInstance, onUnmounted } from 'vue'
import type { useEventsStore } from '../stores/events'

const DEBOUNCE_MS = 1000

type EventsLike = Pick<ReturnType<typeof useEventsStore>, 'onEvent'>

export function useLiveRefresh(
  events: EventsLike,
  onFsChanged: () => void,
  debounceMs: number = DEBOUNCE_MS,
): () => void {
  let timer: ReturnType<typeof setTimeout> | null = null

  const schedule = () => {
    if (timer) return
    timer = setTimeout(() => {
      timer = null
      onFsChanged()
    }, debounceMs)
  }

  const unsubscribe = events.onEvent((event) => {
    if (event === 'fs_changed' || event === 'status_refreshed') schedule()
  })

  const dispose = () => {
    if (timer) clearTimeout(timer)
    timer = null
    unsubscribe()
  }

  if (getCurrentInstance()) onUnmounted(dispose)

  return dispose
}
