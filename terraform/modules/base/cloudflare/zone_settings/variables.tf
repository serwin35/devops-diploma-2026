variable "zone_id" {
  type        = string
  nullable    = false
  description = "ID strefy. Moduł bazowy dostaje gotowe ID zamiast nazwy, żeby nie powtarzać zapytania o strefę w każdym module, który z niego korzysta"
}

variable "ssl_mode" {
  type        = string
  nullable    = false
  default     = "strict"
  description = "Tryb SSL między Cloudflare a origin: off, flexible, full, strict"

  validation {
    condition     = contains(["off", "flexible", "full", "strict"], var.ssl_mode)
    error_message = "Dopuszczalne wartosci: off, flexible, full, strict."
  }
}

variable "min_tls_version" {
  type        = string
  nullable    = false
  default     = "1.2"
  description = "Najniższa wersja TLS akceptowana od przeglądarki"

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.min_tls_version)
    error_message = "Dopuszczalne wartosci: 1.0, 1.1, 1.2, 1.3."
  }
}

variable "always_use_https" {
  type        = bool
  nullable    = false
  default     = true
  description = "Przekierowanie 301 z http:// na https:// na krawędzi Cloudflare"
}

variable "tls_1_3" {
  type        = bool
  nullable    = false
  default     = true
  description = "Obsługa TLS 1.3 od strony przeglądarki"
}

variable "hsts_enabled" {
  type        = bool
  nullable    = false
  default     = true
  description = "Nagłówek Strict-Transport-Security dodawany przez Cloudflare do odpowiedzi"
}

variable "hsts_max_age" {
  type        = number
  nullable    = false
  default     = 31536000
  description = "Czas życia HSTS w sekundach. 31536000 = rok, minimum wymagane przez listę preload"
}

variable "hsts_include_subdomains" {
  type        = bool
  nullable    = false
  default     = true
  description = "Rozszerza HSTS na wszystkie subdomeny strefy"
}

variable "hsts_preload" {
  type        = bool
  nullable    = false
  default     = true
  description = "Dopisuje dyrektywę preload do nagłówka HSTS"
}

variable "hsts_nosniff" {
  type        = bool
  nullable    = false
  default     = true
  description = "Nagłówek X-Content-Type-Options: nosniff dodawany razem z HSTS"
}
