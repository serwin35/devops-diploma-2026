# Tunel Cloudflare produkcji - celuje w węzeł serwera k3s, przez który wchodzi
# Traefik. Uzasadnienie modelu "jeden tunel na maszynę" stoi w module bazowym.
module "tunnel" {
  source = "../../../../base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-prod"
  origin_host    = module.k3s-server-1.private_ip
  allowed_emails = var.allowed_emails

  services = {
    # Domena apex - produkcja. Publiczna, kontrola dostępu należy do aplikacji.
    prod = { port = 80, protected = false, apex = true }
  }

  # Rekordy domeny produkcyjnej niepochodzące z tunelu dopisuje się tutaj -
  # przy usłudze, do której należą. Przykład (weryfikacja Google Search
  # Console; name = null oznacza apex, czyli samą wolffire.dev):
  #
  #   extra_records = {
  #     google_site_verification = {
  #       type    = "TXT"
  #       content = "google-site-verification=<token>"
  #       comment = "Weryfikacja wlasnosci domeny w Google Search Console"
  #     }
  #   }
}
