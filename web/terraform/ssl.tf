resource "cloudflare_zone_settings_override" "boldman_net" {
  zone_id = cloudflare_zone.boldman_net.id

  settings {
    ssl                      = "strict"
    min_tls_version          = "1.2"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
  }
}
