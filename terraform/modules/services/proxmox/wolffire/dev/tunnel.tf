# Tunel Cloudflare tej maszyny - wystawia środowisko deweloperskie.
# Uzasadnienie modelu "jeden tunel na maszynę" stoi w module bazowym.
module "tunnel" {
  source = "../../../../base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-dev"
  origin_host    = module.wolffire-dev-app-1.private_ip
  allowed_emails = var.allowed_emails

  services = {
    # Środowisko deweloperskie jest publiczne - kontrola dostępu należy
    # do samej aplikacji, nie do warstwy sieciowej.
    dev = { port = 80, protected = false }
  }
}
