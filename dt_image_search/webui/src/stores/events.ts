import { defineStore } from 'pinia'
import { computed, onScopeDispose, ref } from 'vue'
import { getToken } from '../auth/token'
import { useStatusStore } from './status'

type Listener = (event: string, data: Record<string, unknown>) => void

const BASE_DELAY_MS = 1000
const MAX_DELAY_MS = 30000

export const useEventsStore = defineStore('events', () => {
  const latestStatusMessage = ref<string | null>(null)
  const failureDismissed = ref(false)
  const connected = ref(false)
  const status = useStatusStore()
  const modelLoadFailed = computed(() => status.modelState === 'failed' && !failureDismissed.value)

  let ws: WebSocket | null = null
  let attempt = 0
  let messageRevision = 0
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null
  const listeners = new Set<Listener>()

  function onEvent(fn: Listener): () => void {
    listeners.add(fn)
    return () => {
      listeners.delete(fn)
    }
  }

  function connect() {
    if (ws) return
    const token = getToken()
    if (!token) return // unauthenticated (plain browser) → no live events

    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const socket = new WebSocket(`${proto}://${window.location.host}/events?auth=${encodeURIComponent(token)}`)
    ws = socket
    socket.onopen = async () => {
      if (ws !== socket) return
      connected.value = true
      attempt = 0 // reset backoff after a successful connection
      const previousMessageRevision = messageRevision
      const refreshed = await status.refresh()
      if (!refreshed || ws !== socket) return
      if (messageRevision === previousMessageRevision) latestStatusMessage.value = null
      failureDismissed.value = false
      listeners.forEach((fn) => fn('status_refreshed', {}))
    }
    socket.onmessage = (msg) => {
      const envelope = JSON.parse(String(msg.data)) as { event: string; data: Record<string, unknown> }
      handle(envelope.event, envelope.data ?? {})
    }
    socket.onclose = () => {
      if (ws !== socket) return
      ws = null
      connected.value = false
      status.cancelRefresh()
      scheduleReconnect()
    }
    socket.onerror = () => {
      /* close handler drives reconnection */
    }
  }

  function scheduleReconnect() {
    if (reconnectTimer) return
    const delay = Math.min(BASE_DELAY_MS * 2 ** attempt, MAX_DELAY_MS)
    attempt += 1
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      connect()
    }, delay)
  }

  function handle(event: string, data: Record<string, unknown>) {
    if (event === 'status_message') {
      messageRevision += 1
      latestStatusMessage.value = String(data.message ?? '')
    } else if (event === 'model_load_failed') {
      failureDismissed.value = false
      status.cancelRefresh()
      status.modelState = 'failed'
    }
    listeners.forEach((fn) => fn(event, data))
  }

  function clearStatusMessage() {
    latestStatusMessage.value = null
  }

  function clearModelLoadFailed() {
    failureDismissed.value = true
  }

  function disconnect() {
    if (reconnectTimer) clearTimeout(reconnectTimer)
    reconnectTimer = null
    const socket = ws
    ws = null
    socket?.close()
    connected.value = false
    status.cancelRefresh()
  }

  onScopeDispose(disconnect)

  return {
    latestStatusMessage,
    modelLoadFailed,
    connected,
    onEvent,
    connect,
    disconnect,
    clearStatusMessage,
    clearModelLoadFailed,
  }
})
