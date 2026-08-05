variable "account_name" {
  type        = string
  nullable    = false
  description = "Nazwa konta Cloudflare"
}

variable "zone" {
  type        = string
  nullable    = false
  description = "Strefa DNS, w której powstają rekordy"
}

variable "tunnel_name" {
  type        = string
  nullable    = false
  description = "Nazwa tunelu - jeden na maszynę, widoczna w panelu Cloudflare"
}

variable "services" {
  type = map(object({
    # Port usługi na localhoście maszyny, na której działa cloudflared.
    port = number
    # http albo https - schemat po stronie origin.
    scheme = optional(string, "http")
    # true = przed usługą staje Zero Trust Access; false = dostęp publiczny
    protected = optional(bool, true)
    # Pomija weryfikację certyfikatu origin (UI Proxmoxa ma własne CA).
    insecure_origin = optional(bool, false)
    # true = wpis na domenę apex zamiast subdomeny
    apex = optional(bool, false)
  }))
  nullable    = false
  description = "Usługi wystawiane przez ten tunel, kluczem jest subdomena"
}

variable "allowed_emails" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Adresy e-mail dopuszczone przez Zero Trust Access"
}

variable "origin_host" {
  type        = string
  nullable    = false
  default     = "localhost"
  description = "Adres, pod którym cloudflared znajduje usługi. Usługi tego projektu bindują na prywatnym IP maszyny (nie na loopbacku), więc moduł dostaje ten adres per maszyna"
}
