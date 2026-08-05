data "cloudflare_account" "this" {
  filter = {
    name = var.account_name
  }
}

data "cloudflare_zone" "this" {
  count = var.zone != null ? 1 : 0

  filter = {
    name = var.zone
  }
}
