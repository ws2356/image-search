import { defineStore } from 'pinia'
import { ref } from 'vue'
import { api } from '../api/client'
import { getToken } from '../auth/token'

type Listener = (event: string, data: Record<string, unknown>) => void

const BASE_DELAY_MS = 1000
const MAX_DELAY_MS = 30000

export const useEventsStore = defineStore('events', () => {
  const latestStatusMessage = ref<string | null>(null)
  const modelLoadFailed = ref(false)
  const connected = ref(false)

  let ws: WebSocket | null = null
  let attempt = 0
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
    ws = new WebSocket(`${proto}://${window.location.host}/events?auth=${encodeURIComponent(token)}`)
    ws.onopen = () => {
      connected.value = true
      attempt = 0 // reset backoff after a successful connection
      void api.getStatus() // refresh state after (re)connect
    }
    ws.onmessage = (msg) => {
      const envelope = JSON.parse(String(msg.data)) as { event: string; data: Record<string, unknown> }
      handle(envelope.event, envelope.data ?? {})
    }
    ws.onclose = () => {
      ws = null
      connected.value = false
      scheduleReconnect()
    }
    ws.onerror = () => {
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
      latestStatusMessage.value = String(data.message ?? '')
    } else if (event === 'model_load_failed') {
      modelLoadFailed.value = true
    }
    listeners.forEach((fn) => fn(event, data))
  }

  function clearStatusMessage() {
    latestStatusMessage.value = null
  }

  function clearModelLoadFailed() {
    modelLoadFailed.value = false
  }

  return {
    latestStatusMessage,
    modelLoadFailed,
    connected,
    onEvent,
    connect,
    clearStatusMessage,
    clearModelLoadFailed,
  }
})
