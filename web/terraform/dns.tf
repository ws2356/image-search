resource "cloudflare_zone" "boldman_net" {
  name = var.zone_name

  account = {
    id = var.cf_account_id
  }
}

resource "cloudflare_dns_record" "test" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "test"
  content = var.origin_ip
  type    = "A"
  ttl     = 1
  proxied = true
}
