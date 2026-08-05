output "ssl_mode" {
  value       = cloudflare_zone_setting.ssl.value
  description = "Obowiązujący tryb SSL strefy"
}

output "min_tls_version" {
  value       = cloudflare_zone_setting.min_tls_version.value
  description = "Najniższa akceptowana wersja TLS"
}

output "hsts" {
  value       = cloudflare_zone_setting.security_header.value
  description = "Konfiguracja nagłówka Strict-Transport-Security"
}
