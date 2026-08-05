# Tokeny maszynowe: pozwalają dobić się do chronionej usługi bez przeglądarki
# (health check, webhook). Powstają tylko wtedy, gdy wywołujący o nie poprosi.
resource "cloudflare_zero_trust_access_service_token" "this" {
  for_each = var.access_tokens

  account_id = data.cloudflare_account.this.id
  name       = "Token ${each.value} for ${local.domain}"
}

# Polityka wpuszczająca - lista adresów e-mail. Uwierzytelnienie robi Cloudflare
# (one-time PIN albo dostawca tożsamości), usługa za tunelem nie widzi anonimów.
resource "cloudflare_zero_trust_access_policy" "this" {
  account_id       = data.cloudflare_account.this.id
  decision         = "allow"
  name             = "${local.domain} allow"
  session_duration = "6h"

  include = [for user in var.allowed_emails : {
    email = {
      email = user
    }
  }]
}

# Polityka omijająca ekran logowania - dla tokenów maszynowych i zaufanych
# adresów IP. Powstaje tylko wtedy, gdy jest co do niej wpisać.
resource "cloudflare_zero_trust_access_policy" "bypass" {
  count = length(var.access_tokens) > 0 || length(var.allowed_ips) > 0 ? 1 : 0

  account_id = data.cloudflare_account.this.id
  decision   = "bypass"
  name       = "${local.domain} bypass"

  include = concat(
    [for token in var.access_tokens : {
      service_token = {
        token_id = cloudflare_zero_trust_access_service_token.this[token].id
      }
    }],
    [for ip in var.allowed_ips : {
      ip = {
        ip = ip
      }
    }]
  )
}

resource "cloudflare_zero_trust_access_application" "this" {
  domain = local.domain
  type   = "self_hosted"

  # Aplikacja na apeksie należy do konta, aplikacja na subdomenie - do strefy.
  account_id = var.zone == null ? data.cloudflare_account.this.id : null
  zone_id    = var.zone != null ? data.cloudflare_zone.this[0].id : null

  # precedence wyznacza kolejność sprawdzania: najpierw polityka wpuszczająca,
  # dopiero potem bypass.
  policies = concat(
    [
      {
        id         = cloudflare_zero_trust_access_policy.this.id
        precedence = 1
      }
    ],
    length(cloudflare_zero_trust_access_policy.bypass) > 0 ? [
      {
        id         = cloudflare_zero_trust_access_policy.bypass[0].id
        precedence = 2
      }
    ] : []
  )

  # allow_authenticate_via_warp świadomie pominięte: wymaga skonfigurowanej
  # sesji Cloudflare One Client w koncie, a nie używamy klienta WARP -
  # uwierzytelnienie idzie przez przeglądarkę.
}
