output "zone_id" {
  description = "Cloudflare zone ID for boldman.net"
  value       = cloudflare_zone.boldman_net.id
}

output "nameservers" {
  description = "Cloudflare-assigned nameservers (update your registrar)"
  value       = cloudflare_zone.boldman_net.name_servers
}