variable "account_name" {
  type        = string
  nullable    = false
  description = "Nazwa konta Cloudflare, w którym powstaje aplikacja Access"
}

variable "subdomain" {
  type        = string
  nullable    = false
  description = "Subdomena chronionej usługi. Przy wpisie na apeksie podaje się tu całą nazwę hosta, a zmienna zone zostaje pusta"
}

variable "zone" {
  type        = string
  default     = null
  description = "Strefa DNS chronionej usługi. Puste = aplikacja zostaje powiązana z kontem zamiast ze strefą (przypadek domeny apex)"
}

variable "allowed_emails" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Adresy e-mail dopuszczone do usługi"
}

variable "access_tokens" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Nazwy tokenów maszynowych omijających ekran logowania - dla klientów bez przeglądarki"
}

variable "allowed_ips" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Adresy IP, dla których ekran logowania Zero Trust jest pomijany"
}
