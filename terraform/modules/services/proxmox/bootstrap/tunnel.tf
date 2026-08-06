# Tunel Cloudflare hypervisora - wystawia UI Proxmoxa. Mieszka w module warstwy
# hosta, bo cloudflared działa na samym hypervisorze, nie na żadnej VM-ce.
# Jedyny tunel bez origin_host: celuje w domyślny localhost.
module "tunnel" {
  source = "../../../base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-proxmox"
  allowed_emails = var.allowed_emails

  services = {
    proxmox = {
      port   = 8006
      scheme = "https"
      # Hypervisor ma certyfikat podpisany przez własne CA Proxmoxa.
      insecure_origin = true
    }
  }
}
