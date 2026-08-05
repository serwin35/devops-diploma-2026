locals {
  # DMARC domyka parę SPF + DKIM: mówi odbiorcy, co zrobić z listem, który
  # nie przeszedł weryfikacji, i dokąd odesłać raport.
  #
  # p=none to tryb obserwacji - nikt niczego nie odrzuca, ale raporty zbiorcze
  # pokazują, kto wysyła pocztę "z tej domeny". Dopiero po kilku tygodniach
  # takich raportów ma sens przejście na quarantine, a potem reject. Włączenie
  # reject od razu to najszybszy sposób na utratę własnej poczty transakcyjnej,
  # o której się zapomniało.
  #
  # adkim=r i aspf=r (relaxed) pozwalają, żeby list wyszedł z subdomeny -
  # tryb strict odrzucałby pocztę wysyłaną np. z mail.wolffire.dev.
  # fo=1 żąda raportu forensycznego także wtedy, gdy jeden z mechanizmów
  # przeszedł, a drugi nie - inaczej połowa przypadków jest niewidoczna.
  dmarc_content = join("; ", compact([
    "v=DMARC1",
    "p=${var.dmarc_policy}",
    # sp dotyczy subdomen. Bez niego subdomeny dziedziczą p, ale wpisujemy
    # jawnie, żeby zmiana p na reject nie objęła ich przypadkiem.
    "sp=${var.dmarc_policy}",
    var.dmarc_report_email == null ? null : "rua=mailto:${var.dmarc_report_email}",
    "adkim=r",
    "aspf=r",
    "fo=1",
  ]))

  # DMARC jest składany ze zmiennych, więc nie może być domyślną wartością
  # zmiennej `records` - Terraform nie dopuszcza tam odwołań do locals.
  declared = merge(var.records, {
    dmarc = {
      name    = "_dmarc"
      type    = "TXT"
      content = local.dmarc_content
      comment = "DMARC - polityka dla listow nieuwierzytelnionych"
    }
  })

  # Normalizacja do jednego kształtu. Bez tego `for_each` nie potrafi złożyć
  # mapy z obiektów o różnych zestawach pól.
  records = {
    for key, record in local.declared : key => {
      # Cloudflare oczekuje pełnej nazwy hosta, nie samego prefiksu.
      name = try(record.name, null) == null ? var.zone : "${record.name}.${var.zone}"
      type = record.type

      # Provider w wersji 5 przekazuje treść do API dosłownie, a API zwraca
      # rekordy TXT razem z cudzysłowami. Wysłanie treści bez nich daje wieczny
      # diff: plan chce zapisać `v=spf1 ...`, a stan odczytuje `"v=spf1 ..."`.
      #
      # Ograniczenie DNS: pojedynczy łańcuch TXT ma najwyżej 255 znaków. Dłuższe
      # wartości (klucze DKIM 2048-bit) trzeba podać jako kilka łańcuchów
      # rozdzielonych cudzysłowami - wtedy podaje się treść już ocytowaną,
      # a warunek niżej jej nie rusza.
      content = (
        record.type == "TXT" && !startswith(record.content, "\"")
        ? "\"${record.content}\""
        : record.content
      )

      priority = try(record.priority, null)
      ttl      = try(record.ttl, 1)
      proxied  = try(record.proxied, false)
      comment  = try(record.comment, null)
    }
  }
}
