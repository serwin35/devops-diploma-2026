# Ustawienia bezpieczeństwa strefy. Każde jest osobnym zasobem, bo API Cloudflare
# traktuje je jako niezależne przełączniki - jedno nieudane nie blokuje pozostałych.
#
# Token API musi mieć grupę uprawnień "Zone Settings: Edit". Sam "DNS: Edit"
# nie wystarcza - odczyt /zones/<id>/settings kończy się wtedy błędem 9109
# i plan wywala się, zanim cokolwiek pokaże.

# Tryb SSL opisuje połączenie Cloudflare -> origin, a NIE przeglądarka -> Cloudflare.
#
# flexible oznacza czyste HTTP na tym odcinku: ruch wychodzi z centrum danych
# Cloudflare w internet niezaszyfrowany, więc kłódka w przeglądarce kłamie.
# Do tego każda usługa, która sama wymusza HTTPS, wpada w pętlę przekierowań.
#
# full akceptuje dowolny certyfikat origin, także wygasły i samopodpisany -
# czyli nie chroni przed podszyciem się pod origin.
#
# strict wymaga certyfikatu zaufanego i zgodnego z nazwą hosta. W tej
# infrastrukturze origin jest po drugiej stronie tunelu cloudflared, który
# zestawia sesję TLS z certyfikatem Cloudflare - warunek jest spełniony
# z definicji i nie kosztuje nic dodatkowego.
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = var.ssl_mode
}

# Przekierowanie http -> https realizowane na krawędzi, zanim zapytanie w ogóle
# dotrze do origin.
#
# Domena kończy się na .dev, a cały ten TLD jest wpisany na listę HSTS preload
# wkompilowaną w przeglądarki - Chrome, Firefox i Safari same zamieniają http://
# na https:// jeszcze przed wysłaniem pakietu. To ustawienie nie jest więc
# zabezpieczeniem dla przeglądarek, tylko dla wszystkiego innego: curl-a,
# skryptów, klientów API i webhooków, które listy preload nie znają.
resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = var.always_use_https ? "on" : "off"
}

# TLS 1.0 i 1.1 są wycofane (RFC 8996) - mają złamane szyfry CBC i SHA-1
# w podpisach uzgadniania. TLS 1.2 to najniższa wersja, która zdaje audyty
# PCI DSS i testy SSL Labs na ocenę A.
resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.zone_id
  setting_id = "min_tls_version"
  value      = var.min_tls_version
}

# TLS 1.3 skraca uzgadnianie do jednego obiegu i usuwa z zestawu szyfrów
# wszystko, co nie zapewnia forward secrecy. Włączenie nie odcina starszych
# klientów - negocjacja spada wtedy do wersji z min_tls_version.
resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id    = var.zone_id
  setting_id = "tls_1_3"
  value      = var.tls_1_3 ? "on" : "off"
}

# HSTS: przeglądarka, która raz zobaczyła ten nagłówek, przez max_age odmawia
# połączenia po http nawet gdy użytkownik sam wpisze taki adres. Zamyka to
# okno na atak SSL stripping przy pierwszym zapytaniu w sesji.
#
# preload przy .dev jest formalnością - TLD siedzi na liście preload w całości,
# więc żadna subdomena wolffire.dev nigdy nie zostanie odpytana po http przez
# przeglądarkę. Zostaje włączone dla spójności: gdyby ta sama konfiguracja
# wylądowała na domenie spoza listy, zachowa się tak samo.
#
# include_subdomains obejmuje panele wystawione przez tunele (jenkins., grafana.,
# proxmox.) - to one wożą sesje administracyjne i to one najbardziej tracą
# na degradacji do http.
#
# Uwaga na kolejność wdrożenia: max_age roku oznacza, że cofnięcie strefy
# na http wymaga odczekania roku albo wyczyszczenia stanu w każdej przeglądarce.
# Włączamy to dopiero, gdy HTTPS na wszystkich hostach działa.
resource "cloudflare_zone_setting" "security_header" {
  zone_id    = var.zone_id
  setting_id = "security_header"

  value = {
    strict_transport_security = {
      enabled            = var.hsts_enabled
      max_age            = var.hsts_max_age
      include_subdomains = var.hsts_include_subdomains
      preload            = var.hsts_preload
      nosniff            = var.hsts_nosniff
    }
  }
}
