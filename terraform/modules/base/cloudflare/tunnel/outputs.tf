output "tunnel_id" {
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
  description = "ID tunelu"
}

# Trafia do Ansible, który uruchamia cloudflared na bastionie.
output "tunnel_token" {
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
  description = "Token uwierzytelniający cloudflared"
}

output "hostnames" {
  value       = local.hostnames
  description = "Nazwy hostów wystawione przez tunel"
}
