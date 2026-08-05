data "cloudflare_account" "this" {
  filter = {
    name = var.account_name
  }
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.zone
  }
}

# Token, którym cloudflared na bastionie uwierzytelnia się przy zestawianiu tunelu.
# Nie jest atrybutem zasobu tunelu - trzeba go odczytać osobno.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = data.cloudflare_account.this.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}
