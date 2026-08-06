output "pool_ids" {
  value       = { for pool in proxmox_virtual_environment_pool.this : pool.pool_id => pool.id }
  description = "Utworzone pule zasobów"
}

output "image_file_id" {
  value       = proxmox_virtual_environment_download_file.ubuntu.id
  description = "ID obrazu cloud-image Ubuntu"
}

output "cloud_init_file_id" {
  value       = proxmox_virtual_environment_file.cloud_init.id
  description = "ID snippetu cloud-init"
}

output "datastore_id" {
  value       = proxmox_virtual_environment_storage_zfspool.vmdata.id
  description = "Datastore na dyski VM-ek"
}

output "initial_password" {
  value       = random_password.initial.result
  sensitive   = true
  description = "Hasło początkowe użytkowników Proxmoxa - do zmiany po pierwszym logowaniu"
}

output "ipv6_subnets" {
  value       = local.ipv6_subnets
  description = "Podprefiksy IPv6 wydzielone dla segmentów wraz z adresem bramy na hoście"
}

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
