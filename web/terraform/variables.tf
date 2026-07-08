variable "cf_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "origin_ip" {
  description = "Public IP address of the origin server"
  type        = string
}

variable "zone_name" {
  description = "Cloudflare zone domain name"
  type        = string
  default     = "boldman.net"
}
