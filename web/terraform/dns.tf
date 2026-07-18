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


# ==========================================
# CNAME 记录 (别名指向)
# ==========================================

resource "cloudflare_dns_record" "www_cname" {
  zone_id = cloudflare_zone.boldman_net.id
  name    = "www"
  type    = "CNAME"
  content   = "@"
  ttl     = 1
  proxied = true
}


# ==========================================
# TXT 记录 (文本/认证)
# ==========================================
