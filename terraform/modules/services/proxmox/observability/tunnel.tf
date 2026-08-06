# Tunel Cloudflare tej maszyny - wystawia panele Grafany, Prometheusa
# i Alertmanagera. Uzasadnienie modelu "jeden tunel na maszynę" stoi w module
# bazowym.
module "tunnel" {
  source = "../../../base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-monitoring"
  origin_host    = module.monitoring-1.private_ip
  allowed_emails = var.allowed_emails

  services = {
    grafana    = { port = 3000 }
    prometheus = { port = 9090 }
    alerts     = { port = 9093 }
  }
}
