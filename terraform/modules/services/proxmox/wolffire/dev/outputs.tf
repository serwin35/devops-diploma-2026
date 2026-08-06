# Token czyta Ansible, który uruchamia cloudflared na maszynie - dzięki temu
# sekret nie przechodzi przez SOPS i nie może się rozjechać ze stanem.
output "tunnel_token" {
  value       = module.tunnel.tunnel_token
  sensitive   = true
  description = "Token cloudflared tunelu maszyny"
}

output "hostnames" {
  value       = module.tunnel.hostnames
  description = "Nazwy hostów wystawione przez tunel"
}
