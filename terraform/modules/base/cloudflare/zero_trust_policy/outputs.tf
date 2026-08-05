# Poświadczenia tokenów maszynowych, kluczem jest nazwa tokenu. Klient wysyła
# oba nagłówki (CF-Access-Client-Id / -Secret) i omija ekran logowania.
output "access_token_client_ids" {
  value       = { for token in var.access_tokens : token => cloudflare_zero_trust_access_service_token.this[token].client_id }
  sensitive   = true
  description = "Identyfikatory klienta tokenów maszynowych"
}

output "access_token_client_secrets" {
  value       = { for token in var.access_tokens : token => cloudflare_zero_trust_access_service_token.this[token].client_secret }
  sensitive   = true
  description = "Sekrety tokenów maszynowych"
}
