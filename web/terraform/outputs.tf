output "zone_id" {
  description = "Cloudflare zone ID for boldman.net"
  value       = cloudflare_zone.boldman_net.id
}

output "nameservers" {
  description = "Cloudflare-assigned nameservers (update your registrar)"
  value       = cloudflare_zone.boldman_net.name_servers
}

output "test_record_fqdn" {
  description = "FQDN of the test A record"
  value       = cloudflare_record.test.hostname
}
