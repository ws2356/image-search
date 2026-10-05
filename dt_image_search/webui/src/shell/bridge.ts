// Bridge to the pywebview shell JS API. When the page is opened outside the
// shell (plain browser), the API is absent and callers degrade gracefully.
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

export function hasShellApi(): boolean {
  return shellApi() !== null
}

export async function pickFolder(): Promise<string | null> {
  return (await shellApi()?.pick_folder()) ?? null
}
