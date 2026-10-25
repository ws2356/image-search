// Bridge to the pywebview shell JS API. When the page is opened outside the
// shell (plain browser), the API is absent and callers degrade gracefully.
import { computed, ref } from 'vue'

export interface ShellApi {
  pick_folder(): Promise<string | null>
  reveal(path: string): Promise<void>
}

declare global {
  interface Window {
    pywebview?: { api?: ShellApi }
  }
}

export function shellApi(): ShellApi | null {
  return window.pywebview?.api ?? null
}

// pywebview injects the JS API after the first page load; tracking it in a
// ref lets Vue render controls as soon as that injection happens.
const currentApi = ref<ShellApi | null>(shellApi())
const shellReady = computed(() => currentApi.value !== null)

function syncShellApi(): void {
  currentApi.value = shellApi()
}

window.addEventListener('pywebviewready', syncShellApi)

export function hasShellApi(): boolean {
  return shellReady.value
}

export async function pickFolder(): Promise<string | null> {
  return (await currentApi.value?.pick_folder()) ?? null
}
