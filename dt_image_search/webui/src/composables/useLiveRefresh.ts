// Composable: debounce-refresh a view when the server announces fs_changed
// over the WebSocket (file system changes land in batches).
import { getCurrentInstance, onUnmounted } from 'vue'
import type { useEventsStore } from '../stores/events'

const DEBOUNCE_MS = 1000

type EventsLike = ReturnType<typeof useEventsStore>

export function useLiveRefresh(
  events: EventsLike,
  onFsChanged: () => void,
  debounceMs: number = DEBOUNCE_MS,
): (() => void) | undefined {
  let timer: ReturnType<typeof setTimeout> | null = null

  const schedule = () => {
    if (timer) return
    timer = setTimeout(() => {
      timer = null
      onFsChanged()
    }, debounceMs)
  }

  const dispose = events.onEvent((event) => {
    if (event === 'fs_changed') schedule()
  })

  if (getCurrentInstance()) {
    onUnmounted(() => {
      if (timer) clearTimeout(timer)
      dispose?.()
    })
  }

  return dispose
}
