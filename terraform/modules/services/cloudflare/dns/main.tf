# Rekordy strefy, których źródłem NIE jest tunel: poczta, weryfikacje, DMARC.
#
# Podział jest celowy. Rekordy tuneli są produktem ubocznym zestawienia tunelu -
# ich treść to jego identyfikator, znany dopiero po utworzeniu. Trzyma je więc
# ten sam moduł, który tworzy tunel. Tutaj zostaje reszta strefy, która żyje
# własnym cyklem i nie znika razem z przebudową tunelu.
#
# Rekordy zastane w strefie (MX, SPF) istnieją już w Cloudflare. Cloudflare
# odrzuca próbę utworzenia identycznego rekordu (błąd 81058), więc przed
# pierwszym apply trzeba je wciągnąć do stanu:
#   terraform import 'module.<nazwa>.cloudflare_dns_record.this["mx_primary"]' <zone_id>/<record_id>
resource "cloudflare_dns_record" "this" {
  for_each = local.records

  zone_id = data.cloudflare_zone.this.zone_id

  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  priority = each.value.priority
  ttl      = each.value.ttl
  proxied  = each.value.proxied
  comment  = each.value.comment
}

# Polityka TLS strefy. Uzasadnienie każdego przełącznika stoi przy zasobach
# w module bazowym - wartości podajemy tu jawnie, żeby czytając wywołanie
# widzieć całą postawę bezpieczeństwa strefy bez wchodzenia do modułu.
module "settings" {
  source = "../../../base/cloudflare/zone_settings"

  zone_id = data.cloudflare_zone.this.zone_id

  ssl_mode                = var.ssl_mode
  min_tls_version         = var.min_tls_version
  always_use_https        = true
  tls_1_3                 = true
  hsts_enabled            = true
  hsts_max_age            = var.hsts_max_age
  hsts_include_subdomains = true
  hsts_preload            = true
  hsts_nosniff            = true
}
