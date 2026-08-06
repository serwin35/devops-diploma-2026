# Klucz odczytuje się raz po apply i przenosi do SOPS:
#   terraform -chdir=terraform output -json wolffire_app_storage_credentials
output "wolffire_app_storage_credentials" {
  sensitive   = true
  description = "Klucz IAM wolffire-app (pliki aplikacji na S3) do przeniesienia do SOPS"
  value       = module.wolffire_prod.app_storage_credentials
}

output "ssh_jump_host" {
  description = "Host pośredniczący w połączeniach SSH - żadna VM-ka nie ma publicznego adresu"

  value = {
    host = one(values(var.proxmox_node_names))
    port = var.ssh_port
    user = var.ansible_user
  }
}

output "vnets" {
  description = "Segmenty sieciowe wraz z podsieciami"

  value = {
    for name, tag in local.vnets : name => {
      cidr    = "10.0.${tag}.0/24"
      gateway = "10.0.${tag}.1"
    }
  }
}

output "proxmox_initial_password" {
  value       = module.proxmox_bootstrap.initial_password
  sensitive   = true
  description = "Odczyt: terraform output -raw proxmox_initial_password. Zmienić po pierwszym logowaniu."
}

# Tokeny tuneli, kluczem jest nazwa tunelu. Ansible czyta stąd token dla maszyny,
# na której stawia cloudflared - dzięki temu sekret nie musi być kopiowany
# do SOPS-a i nie może się rozjechać ze stanem.
output "cloudflare_tunnel_tokens" {
  sensitive   = true
  description = "Tokeny cloudflared per tunel"

  value = {
    "wf-cicd"       = module.cicd.tunnel_token
    "wf-monitoring" = module.observability.tunnel_token
    "wf-proxmox"    = module.proxmox_bootstrap.tunnel_token
    "wf-dev"        = module.wolffire_dev.tunnel_token
    "wf-prod"       = module.wolffire_prod.tunnel_token
  }
}

output "public_hostnames" {
  description = "Nazwy hostów wystawione przez tunele"

  value = merge(
    module.cicd.hostnames,
    module.observability.hostnames,
    module.proxmox_bootstrap.hostnames,
    module.wolffire_dev.hostnames,
    module.wolffire_prod.hostnames,
  )
}
