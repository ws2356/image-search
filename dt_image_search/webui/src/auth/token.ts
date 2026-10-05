// One-time auth token plumbing for the web UI.
// The shell loads the page with ?auth=<token>; it is consumed once, cached in
// memory + sessionStorage, and stripped from the address bar.
let cached: string | null = null

const STORAGE_KEY = 'dts-auth'

/** Test/re-entry hook: forget the in-memory token (equivalent to a fresh page load). */
export function resetToken(): void {
  cached = null
}

export function getToken(): string | null {
  if (cached !== null) return cached

  const url = new URL(window.location.href)
  const auth = url.searchParams.get('auth')
  if (auth) {
    cached = auth
    sessionStorage.setItem(STORAGE_KEY, auth)
    url.searchParams.delete('auth')
    window.history.replaceState(null, '', url.toString())
    return cached
  }

  cached = sessionStorage.getItem(STORAGE_KEY)
  return cached
}
