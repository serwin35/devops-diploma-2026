data "cloudflare_account" "this" {
  filter = {
    name = var.account_name
  }
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.zone

    # Strefy szukamy w obrębie konkretnego konta. Token widzący więcej niż jedno
    # konto mógłby inaczej trafić w strefę o tej samej nazwie z cudzego konta.
    account = {
      id = data.cloudflare_account.this.id
    }
  }
}
