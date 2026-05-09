Cloudflare setup checklist for aurora.boldman.net.
1. Add site + DNS
- Add boldman.net to Cloudflare.
- In DNS, set aurora record to your origin IP and turn Proxy ON (orange cloud).

1. SSL/TLS settings
- SSL/TLS mode: Full (strict).
- Ensure origin cert is valid for aurora.boldman.net (Let’s Encrypt or Cloudflare Origin Cert).
- Enable Always Use HTTPS.

1. Performance toggles
- Enable Brotli.
- Enable HTTP/3 (with QUIC).
- Enable Auto Minify (HTML/CSS/JS) only if your assets are safe to minify.

1. Cache Rules (important)
- Rule A (static assets):
    - Expression: http.host eq "aurora.boldman.net" and (http.request.uri.path contains "/assets/" or http.request.uri.path matches "(?i)\\.(png|jpg|jpeg|webp|gif|svg|css|js)$")
    - Action: Cache eligibility = Eligible
    - Edge TTL = 1 month (or 1 week if you release frequently)
    - Browser TTL = Respect origin (or 1 day)
- Rule B (HTML shell):
    - Expression: http.host eq "aurora.boldman.net" and http.request.uri.path eq "/"
    - Action: Cache eligible, Edge TTL = 5–30 min (prevents stale homepage while improving first load).
- Rule C (dynamic/admin, if any):
    - Expression: paths like /api/*, /admin/*, /login*
    - Action: Bypass cache.
    
1. Origin headers (nginx)
    
- For static files, keep long cache headers (for example Cache-Control: public, max-age=31536000, immutable with hashed filenames).
- For index.html, use short/no-cache headers so deployments propagate.
1. Purge strategy after deploy
- Prefer filename hashing for assets.
- Purge only changed paths (or purge all if needed).

1. Verify it works
  - Run:
   - curl -I https://aurora.boldman.net/
   - curl -I https://aurora.boldman.net/assets/...png
  - Check headers show Cloudflare and cache behavior:
   - cf-cache-status: HIT (after first request)
   - content-encoding: br or gzip