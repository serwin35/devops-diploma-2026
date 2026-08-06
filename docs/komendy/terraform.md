# Terraform - komendy

Terraform opisuje w tym repozytorium **warstwę pierwszą**: sieć SDN i storage na
hypervisorze, firewall Proxmoxa, osiem maszyn wirtualnych oraz stronę Cloudflare
(tunele, rekordy DNS, polityki Zero Trust). Wszystko, co dzieje się *wewnątrz*
maszyn, robi Ansible - patrz [`ansible.md`](ansible.md).

Oficjalnym wejściem jest `Makefile`, nie gołe `terraform`. Powód jest praktyczny,
nie estetyczny: samo `terraform plan` w tym repozytorium **nie zadziała**, bo
zabraknie mu tunelu do API Proxmoxa i poświadczeń providerów.

> Wersje (`terraform/providers.tf`, `terraform/bootstrap/versions.tf`):
> Terraform 1.14.4, `bpg/proxmox` 0.94.0, `cloudflare/cloudflare` 5.16.0,
> `hashicorp/random` 3.7.2, w bootstrapie `hashicorp/aws` 6.31.0.
> Stan główny: backend S3 `terraform-states-wf`, **128 zasobów**
> (zweryfikowano na żywo 2026-08-05). Stan bootstrapu: lokalny, 25 zasobów.

Gdzie co leży w kodzie (który plik edytować przy jakiej zmianie) opisuje
[PRZEWODNIK §3](../PRZEWODNIK.md#3-terraform). Skrót operacyjny na obronę:
[RUNBOOK §8](../RUNBOOK.md).

---

## 1. `make` jako wejście

| Cel `make` | Co uruchamia pod spodem (dosłownie) | Kiedy używać |
|---|---|---|
| `make tf-plan` | `PVE_TUNNEL` + `sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan'` | Przed każdą zmianą infrastruktury. Nic nie zapisuje |
| `make tf-apply` | `PVE_TUNNEL` + `sops exec-env secrets.sops.yaml 'terraform -chdir=terraform apply'` | Wdrożenie zaakceptowanego planu |
| `make up` | `make tf-apply` + `make ansible-apply` | Pełne wdrożenie od zera (Terraform, potem Ansible) |
| `make fmt` | `terraform -chdir=terraform fmt -recursive` | Przed commitem, ujednolica wcięcia i wyrównania |
| `make validate` | `terraform -chdir=terraform validate` + `ansible-lint ansible/ \|\| true` | Szybka kontrola składni, bez kontaktu z API i bez sekretów |
| `make bootstrap-aws` | `sops exec-env secrets.sops.yaml 'terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap apply'`, potem `output -json credentials` | Jednorazowo, przed wszystkim innym. Tworzy buckety S3 i tożsamości IAM |
| `make help` | `grep`/`awk` po komentarzach `##` w `Makefile` | Gdy nie pamiętasz nazwy celu |

Aktualna lista celów prosto z repozytorium:

```console
$ make help
  help         Lista dostępnych celów
  aws          Krok zerowy AWS: buckety S3 i tożsamości IAM (stan lokalny, uruchamiany raz)
  secrets      Edycja poświadczeń dostawców (Proxmox, Cloudflare, AWS)
  secrets-app  Edycja sekretów wnętrza infrastruktury (hasła baz, Grafany, Jenkinsa...)
  host         Krok zerowy: hardening hosta Proxmoxa (root:22, jednorazowo po instalacji OVH)
  plan         Podgląd zmian w infrastrukturze
  infra        Terraform: sieć SDN, storage, firewall, maszyny wirtualne
  configure    Ansible: konfiguracja wszystkiego, co działa wewnątrz maszyn
  check        Ansible na sucho: co by się zmieniło, z diffem (nic nie zmienia)
  status       Szybki przegląd zdrowia: klaster, kontenery, odpowiedzi HTTP
  up           Pełne wdrożenie od zera
  fmt          Formatowanie
  validate     Walidacja składni
  test-infra   Testy dymne infrastruktury (tylko odczyt, nic nie zmienia)
```

### Co `make` dokłada do gołego `terraform`

Cele `make` nie robią niczego, czego nie da się napisać ręcznie - opakowują trzy
rzeczy, o których łatwo zapomnieć przy surowym wywołaniu:

1. **Sam otwiera tunel SSH do API Proxmoxa.** Zmienna `PVE_TUNNEL` najpierw
   sprawdza istniejące połączenie (`ssh -O check`), a dopiero gdy go nie ma,
   zakłada nowe przekierowanie `127.0.0.1:18006 -> localhost:8006` przez
   `wf-proxmox-1`. Bez tego provider `proxmox` nie ma z czym rozmawiać, bo port
   8006 hypervisora jest zamknięty dla świata.
2. **Wstrzykuje sekrety bez zapisu na dysk.** `sops exec-env secrets.sops.yaml`
   odszyfrowuje plik w pamięci i podaje pary `KLUCZ=wartość` jako zmienne
   środowiskowe procesu potomnego. Żaden token nie ląduje w pliku tymczasowym,
   w `terraform.tfvars` ani w historii powłoki. Szczegóły: [`sops.md`](sops.md).
3. **Wskazuje klucz age jawną ścieżką.** `export SOPS_AGE_KEY_FILE ?=
   $(HOME)/.config/sops/age/keys.txt` na górze `Makefile` sprawia, że to samo
   repozytorium działa na macOS (gdzie SOPS domyślnie szuka klucza w
   `~/Library/Application Support/sops/age/`) i na Linuksie, na przykład na
   agencie Jenkinsa, bez żadnej modyfikacji.

Wniosek praktyczny: cele `make` to skróty do najczęstszych wywołań i nic ponad
to. Na co dzień pracuje się gołym `terraform`, tylko trzeba pamiętać o dwóch
rzeczach: otwartym tunelu i owinięciu komendy w `sops exec-env`. Sekcja 2.0
pokazuje, jak przygotować sesję raz i mieć spokój do końca dnia.

---

## 2. Codzienna praca

### 2.0 Przygotowanie sesji (raz na terminal)

```bash
# 1. Klucz age. Bez tego sops nie odszyfruje pliku z poświadczeniami.
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt

# 2. Tunel do API Proxmoxa. -O check pyta, czy poprzedni jeszcze żyje,
#    więc powtórne uruchomienie tej linii jest bezpieczne.
ssh -F ansible/ssh_config -O check wf-proxmox-1 2>/dev/null \
  || ssh -F ansible/ssh_config -fN -L 18006:localhost:8006 wf-proxmox-1
```

Tunel jest potrzebny wyłącznie do komend, które rozmawiają z API Proxmoxa:
`plan`, `apply`, `refresh`, `import`, `console` na zasobach. `output`,
`state list`, `state show`, `fmt` i `validate` obchodzą się bez niego.

Wszystkie komendy niżej zakładają, że stoisz w **korzeniu repozytorium** - stąd
`-chdir=terraform` przy każdym wywołaniu. Alternatywnie wejdź do `terraform/`
i opuść tę flagę, ale wtedy ścieżka do `secrets.sops.yaml` robi się względna
(`../secrets.sops.yaml`) i łatwo o pomyłkę.

### 2.1 Podgląd zmian: `terraform plan`

```bash
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan'

# Bez zakładania blokady na stanie - gdy ktoś inny akurat robi apply
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -lock=false'

# Plan zapisany do pliku, żeby apply wykonał dokładnie to, co obejrzałeś
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -out=tf.plan'
```

> Albo krócej: `make tf-plan` - to samo wywołanie, plus tunel otwierany po drodze.

Skrócone wyjście dla infrastruktury bez zmian w kodzie:

```text
module.proxmox_bootstrap.proxmox_virtual_environment_vm...: Refreshing state...
module.bastion.module.bastion-1.proxmox_virtual_environment_vm.this: Refreshing state...
...
No changes. Your infrastructure matches the configuration.
```

Po zmianie w kodzie liczy się wyłącznie ostatnia linia podsumowania:

```text
Plan: 1 to add, 2 to change, 0 to destroy.
```

Reszta wyjścia to szczegóły `+` (dodanie), `~` (zmiana w miejscu), `-/+`
(odtworzenie zasobu) i `-` (usunięcie) przy poszczególnych atrybutach. Zanim
klikniesz `apply`, sprawdź przede wszystkim, czy nie ma niespodziewanego `-/+`
przy maszynie: to znaczy odtworzenie VM-ki, czyli utratę jej dysku.

`No changes.` na wdrożonej infrastrukturze to dowód idempotentności - dobry
materiał na obronę. Warunek: pracujesz na scalonej gałęzi, bez lokalnych
modyfikacji modułów.

### 2.2 Wdrożenie: `terraform apply`

```bash
# Pyta o potwierdzenie - wpisz "yes"
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform apply'

# Wykonanie planu zapisanego w 2.1 - nie pyta o nic, bo decyzja już zapadła
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform apply tf.plan'

# Bez pytania, świadomie. Tylko w CI albo gdy plan obejrzałeś przed chwilą.
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform apply -auto-approve'
```

> Albo krócej: `make tf-apply` (a razem z Ansible: `make up`).

Zakończenie wygląda tak:

```text
Apply complete! Resources: 1 added, 2 changed, 0 destroyed.

Outputs:
public_hostnames = { ... }
ssh_jump_host = { ... }
```

Jeżeli zmiana dotyka konfiguracji *wewnątrz* maszyn (pakiety, usługi, pliki),
po `apply` uruchom jeszcze Ansible - `make ansible-apply`, opis w
[`ansible.md`](ansible.md).

### 2.3 Co jest wdrożone: `terraform output`

```bash
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform output'
```

Rzeczywiste wyjście z tego repozytorium (skrócone o segmenty `dbs`, `dmz` i `k3s`):

```text
cloudflare_tunnel_tokens = <sensitive>
proxmox_initial_password = <sensitive>
public_hostnames = {
  "alerts" = "alerts.wolffire.dev"
  "dev" = "dev.wolffire.dev"
  "grafana" = "grafana.wolffire.dev"
  "jenkins" = "jenkins.wolffire.dev"
  "prod" = "wolffire.dev"
  "prometheus" = "prometheus.wolffire.dev"
  "proxmox" = "proxmox.wolffire.dev"
}
ssh_jump_host = {
  "host" = "57.128.192.26"
  "port" = 22022
  "user" = "ansible"
}
vnets = {
  "apps" = {
    "cidr" = "10.0.120.0/24"
    "gateway" = "10.0.120.1"
  }
}
```

`terraform output` czyta wyłącznie stan z S3 - nie dotyka API Proxmoxa, więc
działa **bez tunelu**. Potrzebuje tylko poświadczeń AWS, czyli `sops exec-env`.

| Output | Wrażliwy | Co zawiera |
|---|---|---|
| `ssh_jump_host` | nie | Adres, port (22022) i użytkownik do wejścia na hypervisor |
| `vnets` | nie | CIDR i brama każdego z czterech segmentów SDN |
| `public_hostnames` | nie | Nazwy hostów wystawione przez tunele Cloudflare |
| `proxmox_initial_password` | tak | Hasło administratora Proxmoxa, do zmiany po pierwszym logowaniu |
| `cloudflare_tunnel_tokens` | tak | Token tunelu per maszyna - czyta go rola `cloudflared` przez `cloud.terraform.terraform_output` |

### 2.4 Formatowanie i walidacja: `fmt`, `validate`

Obie komendy działają na samych plikach - bez sekretów, bez tunelu, bez sieci.
To najtańszy test po edycji `.tf`:

```console
$ terraform -chdir=terraform fmt -recursive
$ terraform -chdir=terraform validate
Success! The configuration is valid.
```

```bash
# Sprawdzenie bez zmieniania plików - nadaje się do CI, zwraca kod != 0
terraform -chdir=terraform fmt -recursive -check -diff
```

> Albo krócej: `make fmt` i `make validate`. Ten drugi dokłada
> `ansible-lint ansible/ || true` - człon `|| true` jest świadomy, brak
> zainstalowanego lintera nie może wywracać walidacji Terraforma.

`fmt -recursive` z korzenia `terraform/` obejmuje także podkatalog `bootstrap/`
i wszystkie moduły.

### 2.5 Odświeżenie stanu bez zmian: `refresh`

```bash
# Wersja zalecana - pokazuje dryf, ale niczego nie zapisuje
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -refresh-only'

# Wersja zapisująca odświeżony stan (pyta o potwierdzenie)
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform apply -refresh-only'
```

Odpowiedź na pytanie "czy ktoś dłubał w UI Proxmoxa albo Cloudflare". Terraform
odpytuje wszystkich dostawców i pokazuje różnice między rzeczywistością
a zapisanym stanem, nie proponując żadnych zmian w infrastrukturze. Wymaga
otwartego tunelu.

**Nigdy nie używaj `-lock=false` przy `apply`** - blokada w S3 jest jedyną
rzeczą, która chroni stan przed dwoma równoległymi zapisami.

---

## 3. Operacje rzadsze

### 3.1 Jak podejrzeć, co dokładnie Terraform trzyma o zasobie

```bash
# Wszystkie zasoby w stanie (128 pozycji)
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list'

# Same maszyny wirtualne - dowód, że jeden moduł obsługuje osiem VM-ek
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list' \
  | grep 'proxmox_virtual_environment_vm.this'
```

```text
module.bastion.module.bastion-1.proxmox_virtual_environment_vm.this
module.cicd.module.cicd-1.proxmox_virtual_environment_vm.this
module.observability.module.monitoring-1.proxmox_virtual_environment_vm.this
module.wolffire_dev.module.wolffire-dev-app-1.proxmox_virtual_environment_vm.this
module.wolffire_prod.module.k3s-agent["k3s-agent-1"].proxmox_virtual_environment_vm.this
module.wolffire_prod.module.k3s-agent["k3s-agent-2"].proxmox_virtual_environment_vm.this
module.wolffire_prod.module.k3s-server-1.proxmox_virtual_environment_vm.this
module.wolffire_prod.module.wolffire-prod-db-1.proxmox_virtual_environment_vm.this
```

Adresy są dwupoziomowe: moduł usługowy (`module.wolffire_prod`) opakowuje
wywołania współdzielonego modułu maszyny (`module.k3s-server-1`,
`module.k3s-agent["k3s-agent-1"]`). Klucz w nawiasach kwadratowych pojawia się
tam, gdzie moduł jest wołany przez `for_each`.

```bash
# Pełny zrzut atrybutów jednego zasobu - adres bierzesz z `state list`
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform state show "module.wolffire_prod.module.k3s-server-1.proxmox_virtual_environment_vm.this"'
```

To pierwsze narzędzie przy dryfie: porównaj pole po polu wyjście `state show`
z tym, co jest w pliku `.tf`.

### 3.2 Jak podejrzeć hasło albo token ze stanu

```bash
# Wartość oznaczona jako sensitive wymaga jawnego -raw
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform output -raw proxmox_initial_password'

# Struktura złożona - jako JSON, np. do jq
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform output -json cloudflare_tunnel_tokens' | jq 'keys'
```

Tokeny tuneli celowo **nie** są kopiowane do SOPS-a: rola `cloudflared` czyta je
wprost ze stanu, dzięki czemu nie mogą rozjechać się z tym, co faktycznie
istnieje w Cloudflare.

### 3.3 Jak dodać maszynę, która powstała ręcznie (`import`)

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform import \
     module.proxmox_bootstrap.proxmox_virtual_environment_firewall_ipset.admins \
     cluster/admins'
```

Składnia: `import <adres w konfiguracji> <identyfikator w API>`. Adres bierzesz
z kodu (nagłówek `resource "typ" "nazwa"` plus ścieżka modułów), identyfikator
z dokumentacji providera albo z UI Proxmoxa/Cloudflare. Po imporcie **zawsze**
uruchom `make tf-plan`: pokaże różnice między stanem faktycznym a konfiguracją,
które trzeba wyrównać ręcznie w `.tf`.

### 3.4 Jak odtworzyć jedną maszynę (`-replace`)

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform apply \
     -replace="module.bastion.module.bastion-1.proxmox_virtual_environment_vm.this"'
```

Zasób zostanie zniszczony i utworzony od nowa. Przy maszynie wirtualnej oznacza
to **utratę jej dysku** - dane odtwarza dopiero Ansible (`make ansible-apply`).

### 3.5 Jak ograniczyć zakres (`-target`)

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform apply -target=module.observability.module.tunnel'
```

Narzędzie diagnostyczne, nie codzienny przepływ. Powtarzalne używanie `-target`
rozjeżdża stan z konfiguracją, bo zależności poza celem nie są przeliczane.
Kolejny pełny `plan` i tak pokaże wszystko, co pominąłeś.

### 3.6 Jak usunąć zasób ze stanu, nie kasując go w rzeczywistości

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform state rm module.cloudflare_dns.cloudflare_dns_record.this["spf"]'
```

Terraform przestaje o nim wiedzieć, obiekt zostaje u dostawcy. Używane przy
przenoszeniu zasobu między modułami (najpierw `state rm`, potem `import` pod
nowym adresem) albo przy oddawaniu czegoś pod zarządzanie ręczne.

### 3.7 Odblokowanie zawieszonego stanu

```bash
# Identyfikator blokady (Lock Info: ID) podaje komunikat błędu
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform force-unlock 7f3c1a92-...'
```

Rób to **wyłącznie** wtedy, gdy masz pewność, że żaden inny `apply` nie działa -
na przykład po tym, jak poprzedni proces został ubity. Zdjęcie blokady podczas
trwającego zapisu potrafi uszkodzić stan.

### 3.8 Konsola do sprawdzania wyrażeń

```bash
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform console'
```

```text
> local.vnets
{ "apps" = 120, "dbs" = 140, "dmz" = 110, "k3s" = 130 }
> cidrhost("10.0.130.0/24", 10)
"10.0.130.10"
```

Przydaje się przy dopisywaniu adresacji w `locals.tf` - sprawdzasz wyrażenie,
zanim trafi do kodu. Wyjście `Ctrl+D`.

### 3.9 Podbicie wersji providera

```bash
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform init -upgrade'
```

Po zmianie `version` w `providers.tf`. Aktualizuje `.terraform.lock.hcl` - plik
**wchodzi do repozytorium**, bo gwarantuje identyczne wersje providerów u
wszystkich i w CI.

### 3.10 Praca z `terraform/bootstrap`

Osobny katalog to osobny root moduł, ze **stanem lokalnym** w
`terraform/bootstrap/terraform.tfstate` (plik jest w `.gitignore`, bo zawiera
klucze IAM). Uruchamiany raz, na starcie projektu.

Stan jest lokalny, więc komendy odczytujące nie potrzebują ani `sops exec-env`,
ani tunelu do Proxmoxa - działają wprost:

```bash
terraform -chdir=terraform/bootstrap state list
terraform -chdir=terraform/bootstrap output -json buckets
terraform -chdir=terraform/bootstrap show
```

```text
{"backups":{"name":"wolffire-backups","region":"eu-north-1"},
 "state":{"name":"terraform-states-wf","region":"us-east-1"}}
```

Co tam mieszka (25 zasobów): bucket na stan (`terraform-states-wf`, wersjonowany
i szyfrowany), bucket na kopie zapasowe (`wolffire-backups`, przejście do
Glacier), trzy tożsamości IAM (`tf_state`, `jenkins_backup`, `alertmanager`)
z politykami o minimalnym zakresie oraz temat SNS `wolffire-alerts` z subskrypcją
e-mail.

Wdrożenie zmian w tym katalogu, poświadczeniami z SOPS-a:

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap apply'
```

> Albo krócej: `make bootstrap-aws` - to samo wywołanie plus wypisanie kluczy IAM na
> koniec.

**Uwaga na poświadczenia.** Klucz IAM zapisany w SOPS-ie ma prawa **tylko** do
bucketa stanu - nie wystarczy do tworzenia użytkowników IAM, polityk ani tematów
SNS. Przy pierwszym uruchomieniu (albo przy dodaniu kolejnej tożsamości)
podstaw poświadczenia administracyjne konta AWS, z pominięciem SOPS-a:

```bash
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1 \
  terraform -chdir=terraform/bootstrap apply
```

Po `apply` przenieś wygenerowane klucze do SOPS-a:

```bash
terraform -chdir=terraform/bootstrap output -json credentials | jq
sops secrets.sops.yaml      # albo: make secrets
```

Zmiana adresu alertów (`variables.tf`, `alerts_email`) wymaga ponownego
potwierdzenia subskrypcji linkiem z maila - do wymuszenia ponownej wysyłki
służy `-replace=aws_sns_topic_subscription.alerts_email`.

---

## 4. Troubleshooting

| Objaw | Przyczyna | Naprawa |
|---|---|---|
| `dial tcp 127.0.0.1:18006: connect: connection refused` | Tunel SSH do API Proxmoxa nie żyje (padło połączenie albo `ControlPersist` wygasł) | `ssh -F ansible/ssh_config -fN -L 18006:localhost:8006 wf-proxmox-1`, patrz sekcja 2.0. Cele `make tf-plan`/`make tf-apply` robią to same |
| `bind [127.0.0.1]:18006: Address already in use` | Tunel z poprzedniego uruchomienia nadal działa - port jest zajęty przez Twój własny proces | Nieszkodliwe. Sprawdź `ssh -F ansible/ssh_config -O check wf-proxmox-1`; zamknięcie: `ssh -F ansible/ssh_config -O exit wf-proxmox-1` |
| `401 Unauthorized` z API Proxmoxa mimo poprawnego tokenu | Po restarcie `pveproxy`/`pvedaemon` (albo po `apt upgrade` na hoście) stary tunel wskazuje na zamknięte gniazdo i przekazuje ruch donikąd | Zamknij i otwórz tunel ponownie (`-O exit`, potem `make tf-plan`). Jeśli nie pomoże, zweryfikuj token: `sops --decrypt --extract '["PROXMOX_VE_API_TOKEN"]' secrets.sops.yaml` |
| `No valid credential sources found` | Komenda uruchomiona bez `sops exec-env` - backend S3 nie dostał kluczy AWS | Owiń wywołanie: `sops exec-env secrets.sops.yaml '...'` albo użyj celu `make` |
| `Error acquiring the state lock` | Inny `apply` trzyma blokadę w S3 (`use_lockfile = true`) | Poczekaj do końca tamtego przebiegu. Gdy proces został ubity: `terraform force-unlock <ID>` (sekcja 3.7) |
| `plan` pokazuje zmianę mimo braku zmian w kodzie | Dryf po ręcznej edycji w UI Proxmoxa albo Cloudflare, ewentualnie rozjazd normalizacji (kolejność list, wielkość liter) | `state show` zasobu i porównanie pole po polu z `.tf`. Zmiana ręczna: albo cofnij ją w UI, albo przenieś do kodu i zaakceptuj plan |
| `Error: Backend initialization required` | Zmienił się blok `backend` albo katalog `.terraform/` jest świeży | `sops exec-env secrets.sops.yaml 'terraform -chdir=terraform init'` |
| `Provider produced inconsistent final plan` | Rozjazd wersji providera z zapisanym stanem po ręcznej podmianie | `terraform init -upgrade`, potem ponowny `plan`. Jeśli wraca, przypnij wersję w `providers.tf` do tej, którą zapisuje stan |
| `This resource cannot be destroyed from Terraform` (ostrzeżenie) | Ustawienia strefy Cloudflare (`cloudflare_zone_setting`) nie mają odpowiednika DELETE w API | Ostrzeżenie informacyjne, nie błąd. Nic nie robimy |
| `AccessDenied` przy operacji na bucketach w `terraform/bootstrap` | Użyty klucz IAM stanu, który celowo nie ma praw do IAM ani SNS | Podstaw poświadczenia administratora AWS (sekcja 3.10) |

---

## 5. Jak to działa

### Tunel na porcie 18006

API Proxmoxa (port 8006) nie jest wystawione do internetu - firewall
hypervisora przepuszcza je wyłącznie z sieci wewnętrznej i z adresów
administracyjnych. Terraform łączy się więc z `https://127.0.0.1:18006`
(zmienna `proxmox_endpoint` w `terraform.tfvars`), a ruch idzie tunelem SSH
przez `wf-proxmox-1`.

Komenda z sekcji 2.0 jest dokładnie tym, co siedzi w zmiennej `PVE_TUNNEL`
w `Makefile`. `-O check` pyta multipleksera, czy połączenie z poprzedniego
wywołania jeszcze żyje: jeśli tak, nie dzieje się nic i `plan` startuje
natychmiast; jeśli nie, zakładane jest nowe przekierowanie w tle (`-fN`).
Druga droga do panelu, niezależna od tunelu SSH, to
`https://proxmox.wolffire.dev` za Cloudflare Zero Trust.

Provider `proxmox` używa tunelu wyłącznie do **API**. Wgrywanie snippetów
cloud-init idzie osobnym kanałem: blok `ssh {}` w `providers.tf`, kluczem
`keys/terraform_ed25519`, na konto `terraform` (port 22022). Dlatego awaria
tunelu objawia się błędem połączenia z `127.0.0.1:18006`, a problem z kluczem
`terraform_ed25519` - błędem dopiero na etapie tworzenia maszyny.

### Stan w S3 i blokada

```hcl
backend "s3" {
  bucket       = "terraform-states-wf"
  key          = "terraform.tfstate"
  region       = "us-east-1"
  use_lockfile = true
  encrypt      = true
}
```

`encrypt = true` szyfruje stan po stronie serwera (bucket ma też włączone
domyślne szyfrowanie i wersjonowanie). `use_lockfile = true` to nowszy mechanizm
blokady: zamiast tabeli DynamoDB Terraform kładzie obok stanu plik
`terraform.tfstate.tflock` i to on rozstrzyga, kto ma prawo zapisu. Mniej
ruchomych części, jedna usługa zamiast dwóch, ten sam efekt - dwa równoległe
`apply` nie zdeptają sobie stanu.

Poświadczenia do bucketa to `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
z `secrets.sops.yaml`, należące do użytkownika IAM `wolffire-tf-state`, który ma
dostęp **tylko** do tego bucketa.

### Dwa katalogi Terraforma

| Katalog | Stan | Co tworzy | Jak uruchamiany |
|---|---|---|---|
| `terraform/bootstrap/` | lokalny plik | Buckety S3, tożsamości IAM, temat SNS | `make bootstrap-aws`, raz na starcie projektu |
| `terraform/` | S3 (`terraform-states-wf`) | Sieć SDN, storage, firewall, 8 maszyn, tunele i DNS Cloudflare | `make tf-plan` / `make tf-apply`, na co dzień |

Podział wynika z problemu kury i jajka: katalog, który tworzy bucket na stan,
nie może trzymać swojego stanu w tym buckecie, bo w chwili pierwszego `apply`
bucket jeszcze nie istnieje. Komentarz w `terraform/bootstrap/versions.tf`
mówi o tym wprost. Konsekwencje na co dzień: `terraform/bootstrap` nie ma
blokady współdzielonej (bo stan jest lokalny), więc jest to katalog dla jednej
osoby i pojedynczych, świadomych uruchomień, a jego `terraform.tfstate` nigdy
nie trafia do repozytorium.

### Gdzie są sekrety

Nie ma ich w `terraform.tfvars`. Ten plik trzyma wyłącznie dane jawne: adres
endpointu, nazwy nodów, port SSH, klucze publiczne, listę adresów
administracyjnych. Wszystkie tokeny wchodzą zmiennymi środowiskowymi z
`secrets.sops.yaml` - providery `proxmox`, `cloudflare` i backend S3 czytają je
same, bez ani jednej linijki w kodzie Terraforma. Dlatego blok
`provider "cloudflare" {}` jest pusty. Pełny opis pliku z sekretami i pracy
z SOPS-em: [`sops.md`](sops.md).
