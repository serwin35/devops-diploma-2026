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

# Rekordy DNS należące do DOMENY tej usługi, ale niepochodzące z tunelu -
# np. TXT weryfikacji własności (Google Search Console, Facebook). Dzięki tej
# mapie rekord mieszka przy usłudze, do której należy, a nie w strefie.
# Rekordy ogólnostrefowe (poczta: MX, SPF, DMARC) zostają w module dns.
variable "extra_records" {
  type = map(object({
    type    = string
    content = string
    # null = rekord na hoście usługi (apex albo subdomena z `services`);
    # prefiks = rekord na <prefiks>.<zone>.
    name     = optional(string)
    ttl      = optional(number, 1)
    priority = optional(number)
    comment  = optional(string)
  }))
  nullable    = false
  default     = {}
  description = "Dodatkowe rekordy DNS usługi (np. TXT weryfikacji domeny), kluczem jest identyfikator w stanie"
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
