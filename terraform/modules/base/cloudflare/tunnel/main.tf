locals {
  # Pełna nazwa hosta dla każdej usługi tego tunelu.
  hostnames = {
    for name, svc in var.services :
    name => svc.apex ? var.zone : "${name}.${var.zone}"
  }

  protected = {
    for name, svc in var.services : name => svc if svc.protected
  }
}

# Jeden tunel na MASZYNĘ, nie jeden na całą infrastrukturę.
#
# Wersja z pojedynczym tunelem na bastionie wymagała, żeby bastion miał trasę
# do wszystkich segmentów i żeby firewall przepuszczał do niego szeroki zakres
# portów. Do tego każda awaria bastionu odcinała wszystkie panele naraz.
#
# W tym modelu cloudflared stoi na maszynie z usługą i celuje w localhost -
# ruch nie opuszcza maszyny, nie trzeba żadnej reguły firewalla między
# segmentami, a awaria jednej maszyny nie dotyka pozostałych.
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = data.cloudflare_account.this.id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = data.cloudflare_account.this.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = concat(
      [
        for name, svc in var.services : {
          hostname = local.hostnames[name]
          # cloudflared działa na maszynie z usługą; origin_host to jej adres
          # prywatny, bo kontenery publikują porty na nim, nie na loopbacku.
          service = "${svc.scheme}://${var.origin_host}:${svc.port}"

          origin_request = {
            # UI Proxmoxa ma certyfikat podpisany przez własne CA.
            no_tls_verify = svc.insecure_origin
          }
        }
      ],
      # Reguła domykająca jest wymagana - bez niej Cloudflare odrzuca konfigurację.
      [{ service = "http_status:404" }]
    )
  }

  depends_on = [cloudflare_dns_record.this]
}

resource "cloudflare_dns_record" "this" {
  for_each = var.services

  zone_id = data.cloudflare_zone.this.zone_id
  name    = local.hostnames[each.key]
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# Zero Trust Access przed panelami administracyjnymi.
module "policy" {
  source   = "../zero_trust_policy"
  for_each = local.protected

  account_name   = var.account_name
  subdomain      = each.value.apex ? var.zone : each.key
  zone           = each.value.apex ? null : var.zone
  allowed_emails = var.allowed_emails
}
