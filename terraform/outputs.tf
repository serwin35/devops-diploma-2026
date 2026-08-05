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
    "wf-cicd"       = module.cloudflare_cicd.tunnel_token
    "wf-monitoring" = module.cloudflare_monitoring.tunnel_token
    "wf-proxmox"    = module.cloudflare_proxmox.tunnel_token
    "wf-dev"        = module.cloudflare_dev.tunnel_token
    "wf-prod"       = module.cloudflare_prod.tunnel_token
  }
}

output "public_hostnames" {
  description = "Nazwy hostów wystawione przez tunele"

  value = merge(
    module.cloudflare_cicd.hostnames,
    module.cloudflare_monitoring.hostnames,
    module.cloudflare_proxmox.hostnames,
    module.cloudflare_dev.hostnames,
    module.cloudflare_prod.hostnames,
  )
}
