# Terraform - komendy

Wszystkie polecenia idą przez `sops exec-env secrets.sops.yaml`, bo poświadczenia
providerów (Proxmox, Cloudflare, backend S3) są zaszyfrowane. Bez tego owijacza
`terraform` startuje bez zmiennych środowiskowych i pada na uwierzytelnianiu.

API Proxmoxa nie jest wystawione do internetu - Terraform dochodzi tunelem SSH
(`127.0.0.1:18006`). `make plan` i `make infra` otwierają go automatycznie
(`PVE_TUNNEL` w Makefile, `ControlPersist` utrzymuje połączenie). Komendy ręczne
poniżej wymagają otwartego tunelu - patrz [RUNBOOK §2a](../RUNBOOK.md).

> Wersja: Terraform 1.14.4, providery `bpg/proxmox` 0.94.0, `cloudflare` 5.16.0.
> Stan: backend S3 (`terraform-states-wf`), 8 maszyn z jednego modułu
> [`modules/base/proxmox/vm`](../../terraform/modules/base/proxmox/vm),
> **zweryfikowano na żywo** 2026-08-05 (125 zasobów w stanie).

---

## Skróty z Makefile

| Komenda | Co robi | Kiedy użyć |
|---|---|---|
| `make plan` | Otwiera tunel do API Proxmoxa, uruchamia `terraform plan` | Przed każdym `apply` - podgląd, zero zmian |
| `make infra` | To samo + `terraform apply` | Wdrożenie zmian infrastruktury |
| `make fmt` | `terraform fmt -recursive` | Przed commitem - ujednolica formatowanie |
| `make validate` | `terraform validate` + `ansible-lint` | Szybka kontrola składni bez kontaktu z API |

## Ręczne wywołania

Gdy potrzebujesz czegoś spoza `Makefile`, owijaj każde polecenie w
`sops exec-env secrets.sops.yaml '...'` i uruchamiaj z korzenia repozytorium
(albo dodaj `-chdir=terraform`).

```bash
# Podgląd zmian bez blokady stanu (bezpieczne przy równoległym make plan)
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -lock=false'

# Pełny apply
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform apply'

# Formatowanie i walidacja
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate
```

### Czytanie planu

`Plan: X to add, Y to change, Z to destroy.` na końcu wyjścia to jedyna linia,
która się liczy - reszta to szczegóły `~`/`+`/`-` przy każdym atrybucie.
Zerowy plan (`No changes.`) na gotowej infrastrukturze dowodzi idempotentności
(dobre pod obronę - patrz RUNBOOK §13).

**Uwaga ze stanu faktycznego:** plan może pokazywać zmiany, jeśli w repo są
niescalone modyfikacje modułów (np. w trakcie refaktoryzacji). Zero zmian
oczekuj dopiero na commitowanej, zamkniętej gałęzi.

## Stan (`state`)

```bash
# Lista wszystkich zasobów w stanie
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list'

# Liczba zasobów - dowód skali pod obronę
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list' | wc -l

# Szczegóły jednego zasobu (adres bierzesz z `state list`)
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform state show "module.wolffire_prod.module.k3s-server-1.proxmox_virtual_environment_vm.this"'
```

Adresy modułów w tym repo są zagnieżdżone: moduł usługowy
(`module.wolffire_prod`) opakowuje wywołania współdzielonego modułu maszyny
(`module.k3s-server-1`, `module.k3s-agent["k3s-agent-1"]`, ...). Dowód, że jeden
moduł `base/proxmox/vm` obsługuje wszystkie 8 maszyn:

```bash
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list' \
  | grep 'proxmox_virtual_environment_vm.this'
```

### Import

Gdy zasób powstał ręcznie albo poza Terraformem (np. w konsoli Proxmoxa) i ma
wejść pod zarządzanie:

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform import module.proxmox_bootstrap.proxmox_virtual_environment_firewall_ipset.admins cluster/admins'
```

Składnia: `import <adres_modułu.zasobu> <id_w_API>`. Adres bierzesz z kodu
(`resource "..." "..."` w pliku `.tf`), id - z dokumentacji providera albo
z UI Proxmoxa/Cloudflare.

### `-replace` i `-target`

```bash
# Wymuś odtworzenie jednej maszyny (np. po ręcznej, niepożądanej zmianie w UI)
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform apply -replace="module.bastion.module.bastion-1.proxmox_virtual_environment_vm.this"'

# Ogranicz apply do jednego modułu - debugowanie, nie do codziennej pracy
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform apply -target=module.cloudflare_monitoring'
```

`-target` psuje spójność stanu przy powtarzalnym użyciu - traktuj go jako
narzędzie diagnostyczne, nie standardowy przepływ. Kolejny `plan` bez `-target`
i tak pokaże wszystko, co pominąłeś.

## Output

```bash
# Wszystkie outputy (sensitive są ukryte jako "(sensitive value)")
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform output'

# Pojedynczy output jako JSON
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform output -json vnets'

# Wartość oznaczona jako sensitive - trzeba jawnie zażądać -raw
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform output -raw proxmox_initial_password'
```

Outputy w tym repo (`terraform/outputs.tf`):

| Output | Sensitive | Co zawiera |
|---|---|---|
| `ssh_jump_host` | nie | Host, port i user do SSH na Proxmoxa |
| `vnets` | nie | CIDR i brama każdego segmentu SDN |
| `proxmox_initial_password` | tak | Hasło administratora Proxmoxa (zmień po pierwszym logowaniu) |
| `cloudflare_tunnel_tokens` | tak | Token tunelu per maszyna - czyta go rola `cloudflared` w Ansible |
| `public_hostnames` | nie | Nazwy hostów wystawione przez tunele |

## Częste problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `No valid credential sources found` | Brak `sops exec-env` - provider nie dostał zmiennych | Owiń komendę w `sops exec-env secrets.sops.yaml '...'` |
| `dial tcp 127.0.0.1:18006: connect: connection refused` | Tunel SSH do API Proxmoxa nie żyje | `make plan` (otwiera go automatycznie) albo ręcznie: `ssh -F ansible/ssh_config -fN -L 18006:localhost:8006 wf-proxmox-1` |
| `Error acquiring the state lock` | Inny proces trzyma lock na S3 (`use_lockfile`) | Poczekaj, aż się skończy, albo sprawdź, czy nie zawisł poprzedni `apply` |
| `plan` pokazuje zmianę przy niezmienionej konfiguracji | Rozjazd normalizacji wartości (np. kolejność list) | `state show` zasobu kontra plik `.tf` - porównaj pole po polu |
| `This resource cannot be destroyed from Terraform` (warning) | Ustawienia strefy Cloudflare (`cloudflare_zone_setting`) nie mają odpowiednika DELETE w API | Nieszkodliwe - informacyjne ostrzeżenie, nie błąd |
