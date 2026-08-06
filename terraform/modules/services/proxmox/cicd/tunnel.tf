# Tunel Cloudflare tej maszyny - wystawia panel Jenkinsa. Uzasadnienie modelu
# "jeden tunel na maszynę" stoi w module bazowym.
module "tunnel" {
  source = "../../../base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-cicd"
  origin_host    = module.cicd-1.private_ip
  allowed_emails = var.allowed_emails

  services = {
    jenkins = { port = 8080 }
  }
}
