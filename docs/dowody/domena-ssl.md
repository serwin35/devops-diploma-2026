Domena z poprawnym SSL - dowody
================================

- [X] Domena własna z certyfikatem SSL ważnym dla wszystkich subdomen
- [X] Panele administracyjne za Cloudflare Zero Trust Access
- [X] Aplikacja dev publicznie dostępna bez logowania do Access

## Dowody zebrane na żywo (2026-08-05)

Certyfikat wildcard/apex ważny, wystawiony przez Google Trust Services
(Cloudflare Universal SSL):

```
$ echo | openssl s_client -connect grafana.wolffire.dev:443 -servername grafana.wolffire.dev \
    | openssl x509 -noout -issuer -subject -dates
issuer=C=US, O=Google Trust Services, CN=WE1
subject=CN=wolffire.dev
notBefore=Aug  3 21:52:43 2026 GMT
notAfter=Nov  1 22:50:20 2026 GMT
```

Panele administracyjne przekierowują na logowanie Cloudflare Access (nie
502/1033 - tunel żyje, Access chroni):

```
$ curl -sI https://grafana.wolffire.dev
HTTP/2 302
location: https://ha-ldz.cloudflareaccess.com/cdn-cgi/access/login/grafana.wolffire.dev?...

$ for d in grafana prometheus alerts proxmox jenkins; do
    curl -s -o /dev/null -w "$d: %{http_code}\n" "https://$d.wolffire.dev"
  done
grafana: 302
prometheus: 302
alerts: 302
proxmox: 302
jenkins: 302
```

Aplikacja dev jest świadomie **poza** Access - publiczny dostęp bez logowania
do Cloudflare, tylko logowanie aplikacji samej w sobie:

```
$ curl -sI https://dev.wolffire.dev
HTTP/2 302
location: https://dev.wolffire.dev/dashboard
set-cookie: wolffire-session=...; secure; httponly; samesite=lax
```

(potwierdzone też automatycznie przez `scripts/smoke-test.sh`, sekcja 2:
`https://dev.wolffire.dev -> HTTP 200, koncowy adres: /login`)

## Jak to jest zrobione

| Element | Plik |
|---|---|
| Strefa i ustawienia TLS (SSL strict, TLS 1.3, min. wersja, `always_use_https`) | [terraform/modules/base/cloudflare/zone_settings/](../../terraform/modules/base/cloudflare/zone_settings/) |
| Tunele per usługa (1 tunel = 1 maszyna) | [terraform/modules/base/cloudflare/tunnel/](../../terraform/modules/base/cloudflare/tunnel/) |
| Polityka Zero Trust Access (kto loguje się do panelu) | [terraform/modules/base/cloudflare/zero_trust_policy/](../../terraform/modules/base/cloudflare/zero_trust_policy/) |
| Rekordy DNS złożone per usługa | [terraform/modules/services/proxmox/{cicd,observability,proxmox,wolffire/dev,wolffire/prod}/](../../terraform/modules/services/proxmox/) |
| `cloudflared` na maszynie docelowej | rola Ansible [ansible/roles/cloudflared/](../../ansible/roles/cloudflared/) |

## Świadome decyzje / ograniczenia

- **Ustawienia strefy (`always_use_https`, `min_tls_version`, `tls_1_3`,
  nagłówek bezpieczeństwa) są jeszcze niezastosowane w Terraformie** -
  `terraform plan` pokazuje je jako „to add” (zob. [terraform.md](terraform.md)).
  Certyfikat i szyfrowanie działają już teraz dzięki domyślnym ustawieniom
  Cloudflare Universal SSL - te pięć zasobów dopina jawną, kontrolowaną z
  kodu politykę (np. wymuszenie TLS 1.3) zamiast polegać na domyślnych
  wartościach edge'a.
- **`wolffire.dev` (apex, produkcja) przekierowuje na `http://`, nie
  `https://`**, w nagłówku `location` odpowiedzi aplikacji
  (`location: http://wolffire.dev/dashboard`) - to bug na poziomie
  `APP_URL` aplikacji (Laravel generuje URL bez wymuszonego schematu HTTPS
  za proxy), a nie błąd konfiguracji Cloudflare/Terraform. Odnotowane
  uczciwie, wymaga poprawki `APP_URL`/`TrustProxies` w aplikacji.
- **`dev.wolffire.dev` jest świadomie bez Zero Trust Access** - ma to być
  publicznie dostępna aplikacja demonstracyjna, nie panel administracyjny;
  bezpieczeństwo zapewnia logowanie samej aplikacji.

## Zrzuty ekranu

![Kłódka w przeglądarce na grafana.wolffire.dev + widok certyfikatu (wystawca, ważność)](../zrzuty/domena-ssl-certificate.png)
![Ekran logowania Cloudflare Access po wejściu na panel administracyjny](../zrzuty/domena-ssl-access-login.png)

Related evidence: [vm.md](vm.md), [terraform.md](terraform.md), [firewall.md](firewall.md).
