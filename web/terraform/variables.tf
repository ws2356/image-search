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

variable "cf_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "home_ip6" {
  description = "Public IPV6 address of the home"
  type        = string
}