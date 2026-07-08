resource "cloudflare_zone" "boldman_net" {
  name = var.zone_name

  account = {
    id = var.cf_account_id
  }
}

resource "cloudflare_record" "test" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "test"
  value   = var.origin_ip
  type    = "A"
  proxied = true
}
