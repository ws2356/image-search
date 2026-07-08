resource "cloudflare_zone" "boldman_net" {
  name = var.zone_name

  account = {
    id = var.cf_account_id
  }
}

# ==========================================
# 根域名 (@) 与 泛域名 (*) 记录
# ==========================================

resource "cloudflare_dns_record" "root_a" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "@"
  type    = "A"
  content = var.origin_ip
  ttl     = 3600
  proxied = false # 如果需要 Cloudflare CDN 代理，可以改为 true
}

resource "cloudflare_dns_record" "wildcard_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "*"
  type    = "CNAME"
  content   = "boldman.net"
  ttl     = 300
  proxied = false
}

# ==========================================
# A 记录 (指向具体 IP)
# ==========================================

resource "cloudflare_dns_record" "tc_a" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "tc"
  type    = "A"
  content = var.origin_ip
  ttl     = 3600
  proxied = false
}

# ==========================================
# CNAME 记录 (别名指向)
# ==========================================

resource "cloudflare_dns_record" "api_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "api"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "f_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "f"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "grafana2_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "grafana2"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "imagesearch_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "imagesearch"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 900
  proxied = false
}

resource "cloudflare_dns_record" "imagesearch2_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "imagesearch2"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "otel_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "otel"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 900
  proxied = false
}

resource "cloudflare_dns_record" "otel2_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "otel2"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "s_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "s"
  type    = "CNAME"
  content   = "tc.boldman.net"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "dl_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "dl"
  content   = "tc.boldman.net"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

# ==========================================
# TXT 记录 (文本/认证)
# ==========================================

resource "cloudflare_dns_record" "dnsauth_imagesearch_txt" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "_dnsauth.imagesearch"
  type    = "TXT"
  content   = "_pysas4std07f9m7wvrb0wcdffrf5xe2"
  ttl     = 3600
}