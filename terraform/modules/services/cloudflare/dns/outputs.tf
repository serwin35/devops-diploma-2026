output "zone_id" {
  value       = data.cloudflare_zone.this.zone_id
  description = "ID strefy - do przekazania modułom, które dopisują własne rekordy"
}

output "account_id" {
  value       = data.cloudflare_account.this.id
  description = "ID konta Cloudflare, w którym leży strefa"
}

output "records" {
  value       = { for key, record in cloudflare_dns_record.this : key => record.name }
  description = "Nazwy hostów rekordów zarządzanych przez ten moduł"
}

output "dmarc" {
  value       = local.dmarc_content
  description = "Obowiązująca polityka DMARC - do sprawdzenia bez zaglądania do panelu"
}
