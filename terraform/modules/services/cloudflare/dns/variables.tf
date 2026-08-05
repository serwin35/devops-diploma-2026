variable "zone" {
  type        = string
  nullable    = false
  description = "Strefa DNS zarządzana przez ten moduł"
}

variable "account_name" {
  type        = string
  nullable    = false
  description = "Nazwa konta Cloudflare. Zawężenie wyszukiwania strefy do konkretnego konta - bez tego token widzący dwie strefy o tej samej nazwie trafiłby w losową"
}

variable "records" {
  type = map(object({
    # Nazwa hosta bez sufiksu strefy. Pominięcie = rekord na apeksie.
    name = optional(string)
    type = string
    # Dla TXT podajemy treść bez cudzysłowów - moduł dokleja je sam.
    content = string
    # Wymagane dla MX i SRV, ignorowane przez pozostałe typy.
    priority = optional(number)
    # 1 = automatyczny TTL po stronie Cloudflare.
    ttl = optional(number, 1)
    # Rekordy pocztowe i weryfikacyjne MUSZĄ być nieproxowane - proxy podmienia
    # adres na anycastowy Cloudflare, co dla MX oznacza brak dostarczenia poczty.
    proxied = optional(bool, false)
    # Widoczny w panelu Cloudflare - żeby ktoś klikający w UI wiedział, skąd rekord.
    comment = optional(string)
  }))
  nullable = false

  # Rekordy podaje wywołujący - moduł nie ma domyślnej listy, żeby nie istniały
  # dwa źródła prawdy o zawartości strefy (każda rozbieżność między domyślną
  # wartością a wywołaniem kończy się diffem przy każdym planie).
  #
  # Rekordów tuneli (jenkins., grafana., prometheus., alerts., proxmox., dev.)
  # NIE należy tu podawać. Tworzy je moduł base/cloudflare/tunnel razem
  # z tunelem, bo ich treść to identyfikator tunelu, który powstaje dopiero
  # przy apply. Zdublowanie ich tutaj skończyłoby się dwoma zasobami walczącymi
  # o ten sam rekord.
  description = "Rekordy DNS spoza tuneli. Kluczem jest nazwa logiczna - dodanie kolejnego rekordu to jeden wpis w tej mapie"
}

variable "dmarc_policy" {
  type        = string
  nullable    = false
  default     = "none"
  description = "Polityka DMARC dla listów, które nie przeszły SPF ani DKIM: none, quarantine, reject"

  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "Dopuszczalne wartosci: none, quarantine, reject."
  }
}

variable "dmarc_report_email" {
  type        = string
  default     = null
  description = "Adres, na który odbiorcy wysyłają zbiorcze raporty DMARC. Puste = brak raportów (polityka działa, ale nie wiadomo, kto podszywa się pod domenę)"
}

variable "ssl_mode" {
  type        = string
  nullable    = false
  default     = "strict"
  description = "Tryb SSL na odcinku Cloudflare - origin"
}

variable "min_tls_version" {
  type        = string
  nullable    = false
  default     = "1.2"
  description = "Najniższa wersja TLS akceptowana od przeglądarki"
}

variable "hsts_max_age" {
  type        = number
  nullable    = false
  default     = 31536000
  description = "Czas życia HSTS w sekundach"
}
