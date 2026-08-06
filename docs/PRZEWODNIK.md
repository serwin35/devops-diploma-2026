# Przewodnik po repozytorium

Praktyczna mapa: co gdzie leży, za co odpowiada, i który plik edytować w
typowych scenariuszach. Uzasadnienia decyzji architektonicznych są w
[ARCHITECTURE.md](ARCHITECTURE.md) - tu jest wyłącznie "gdzie i jak".

---

## 1. Drzewo katalogów

```
devops-diploma-2026/
├── Makefile                     # Wejście do wszystkiego: make bootstrap-host/infra/configure/secrets
├── .sops.yaml                   # Reguły szyfrowania SOPS - kto (klucz age) odszyfruje co
├── secrets.sops.yaml            # Poświadczenia providerów (Proxmox, Cloudflare, AWS) - zaszyfrowane
├── README.md                    # Start: architektura, wdrożenie od zera, dostęp
│
├── terraform/                   # WARSTWA 1: maszyny, sieć, firewall hypervisora, DNS, tunele
│   ├── main.tf                  # Spina wszystkie moduły usługowe + tunele Cloudflare
│   ├── locals.tf                # Segmenty SDN i adresy IP maszyn (jedno źródło prawdy)
│   ├── variables.tf             # Zmienne wejściowe root modułu
│   ├── outputs.tf                # ssh_jump_host, tokeny tuneli, hasło Proxmoxa
│   ├── providers.tf             # Wersje providerów + konfiguracja SSH providera proxmox
│   ├── bootstrap/                # Terraform Nr 0: buckety S3 + IAM (stan LOKALNY, `make bootstrap-aws`)
│   └── modules/
│       ├── base/                # Klocki reużywalne: 1 maszyna, 1 tunel, ustawienia strefy
│       │   ├── proxmox/vm/      # Jeden moduł maszyny wirtualnej - wywoływany 8×
│       │   └── cloudflare/      # tunnel/, zero_trust_policy/, zone_settings/
│       └── services/            # Złożenia klocków w konkretne maszyny/usługi
│           ├── proxmox/bootstrap/   # SDN, storage, cloud-init, grupy bezpieczeństwa, IPv6, tunel UI Proxmoxa
│           ├── proxmox/bastion/     # Jedyna maszyna z publicznym adresem
│           ├── proxmox/cicd/        # cicd-1 + tunel (Jenkins)
│           ├── proxmox/observability/ # monitoring-1 + tunel (Grafana, Prometheus, Alertmanager)
│           ├── proxmox/wolffire/dev/  # wolffire-dev-app-1 + tunel (dev)
│           ├── proxmox/wolffire/prod/ # k3s-server-1, 2× k3s-agent, wolffire-prod-db-1, S3 + tunel (apex)
│           └── cloudflare/dns/      # Rekordy poza tunelami (MX, SPF) + polityka TLS strefy
│
├── ansible/                     # WARSTWA 2: co działa WEWNĄTRZ maszyn
│   ├── ansible.cfg               # inventory, remote_user, ścieżka do ssh_config
│   ├── ssh_config                 # Jedyne źródło topologii SSH (porty, ProxyJump) - dla Ansible i ludzi
│   ├── inventory.yml               # Grupy maszyn + adresy prywatne (dane dla szablonów)
│   ├── playbook.yml                 # Kolejność: które role na jakich grupach hostów
│   ├── bootstrap-host.yml            # Krok zerowy - hardening świeżego hosta Proxmoxa
│   ├── requirements.yml               # Kolekcje Ansible Galaxy
│   ├── group_vars/                     # Zmienne per grupa (w tym `all/secrets.sops.yml`)
│   ├── host_vars/                       # Zmienne per pojedyncza maszyna (np. prefiksy IPv6)
│   └── roles/                            # Po jednej roli na funkcję - opis niżej, §4
│
├── helm/wolffire/                # Chart Helma aplikacji produkcyjnej (k3s)
│   ├── Chart.yaml                 # Wersja chartu i appVersion
│   ├── values.yaml                  # Wartości domyślne - repo obrazów GHCR, limity zasobów
│   └── templates/                    # Deployment/Service/Ingress/Secret/Job
│
├── scripts/                      # Testy dymne (odczyt) + operacje (sync baz)
│   ├── smoke-test.sh              # Wejście: `make test-infra` albo bezpośrednio
│   ├── lib/                        # config/report/run/ssh/secrets - biblioteka wspólna
│   └── checks/                      # Po jednym pliku na sekcję (net, panels, k3s, db, fw, tf, ansible)
│
├── keys/                         # Klucze SSH - WYŁĄCZNIE publiczne trafiają do repo
│   ├── README.md                  # Model tożsamości SSH
│   ├── *_ed25519.pub               # Klucze maszynowe (terraform, ansible)
│   └── humans/*.pub                 # Klucze osobiste - nazwa pliku = nazwa konta
│
└── docs/
    ├── ARCHITECTURE.md            # Decyzje projektowe i uzasadnienia ("dlaczego")
    ├── PRZEWODNIK.md               # Ten dokument ("gdzie i jak")
    ├── RUNBOOK.md                   # Komendy operacyjne, diagnostyka, obrona
    └── PLAN.md                       # Status realizacji per faza
```

Aplikacja (kod Laravela) mieszka w osobnym repozytorium - ten katalog opisuje
wyłącznie infrastrukturę i pipeline, nie kod aplikacji.

---

## 2. Root repozytorium

### `Makefile`

Jedyne wejście do operacji na infrastrukturze - nikt nie powinien wołać
`terraform` czy `ansible-playbook` bezpośrednio poza `Makefile`, bo traci się
`sops exec-env` i tunel SSH do API Proxmoxa.

| Cel | Co robi |
|---|---|
| `make bootstrap-host` | `ansible-playbook bootstrap-host.yml` - krok zerowy, jednorazowo |
| `make tf-apply` | `terraform apply` (przez SSH-tunel do API Proxmoxa, `PVE_TUNNEL`) |
| `make ansible-apply` | `ansible-playbook playbook.yml` - konfiguracja maszyn; `LIMIT=host TAGS=rola` zawężają |
| `make up` | `tf-apply` + `ansible-apply` razem |
| `make tf-plan` | `terraform plan` - podgląd zmian |
| `make secrets` | `sops secrets.sops.yaml` - sekrety dostawców (Proxmox, Cloudflare, AWS) |
| `make secrets-app` | `sops ansible/group_vars/all/secrets.sops.yml` - sekrety wnętrza (hasła baz, Grafany...) |
| `make bootstrap-aws` | Terraform bootstrap: buckety S3 + IAM (stan lokalny, raz) |
| `make ansible-check` | `ansible-playbook playbook.yml --check --diff` - na sucho; też przyjmuje `LIMIT`/`TAGS` |
| `make status` | Zdrowie całości: węzły k3s, pody, kontenery dev, kody HTTP - tylko odczyt |
| `make test-infra` | `scripts/smoke-test.sh` - testy dymne, tylko odczyt |
| `make snapshot` | Migawka wszystkich VM (`NAME=` nazwa, domyślnie znacznik czasu) |
| `make snapshot-list` | Lista migawek każdej maszyny |
| `make snapshot-rollback` | Powrót jednej maszyny: `VM=<id> NAME=<nazwa>` (niszczące!) |
| `make fmt` / `make validate` | Formatowanie i walidacja składni |

**PVE_TUNNEL** (linie 12-15): API Proxmoxa nie jest wystawione na internet -
`make tf-plan`/`make tf-apply` najpierw stawiają tunel SSH `127.0.0.1:18006` przez
`wf-proxmox-1` (`ControlPersist`, więc kolejne wywołania są natychmiastowe).
Port 8006 hosta jest zamknięty dla świata; jedyna droga do API to ten tunel
albo panel przez `https://proxmox.wolffire.dev` (Zero Trust Access).

**Co edytować:** nowy cel operacyjny - dopisz regułę z komentarzem `## opis`
(parsowany przez `make help`). Zmiana ścieżki do klucza age -
`SOPS_AGE_KEY_FILE` na górze pliku.

### `.sops.yaml`

Reguły szyfrowania: który plik (`path_regex`) szyfrować i na jaki klucz age
(`recipient`). Obecnie jeden odbiorca (`mateusz`) dla wszystkich plików
`*.sops.yaml`/`*.sops.yml` w repozytorium - obejmuje to zarówno
`secrets.sops.yaml` w korzeniu, jak i `ansible/group_vars/*/secrets.sops.yml`.

**Co edytować:** dochodzi drugi administrator z własnym kluczem age - dopisz
jego klucz publiczny do `key_groups`, potem uruchom `sops updatekeys` na
każdym zaszyfrowanym pliku, żeby mógł go odczytać.

### `secrets.sops.yaml`

Poświadczenia **providerów zewnętrznych** - czyta je zarówno Terraform
(`sops exec-env` w `Makefile`), jak i wybrane role Ansible (`lookup('env', ...)`
dla kluczy backupu Jenkinsa). Zawiera: `PROXMOX_VE_API_TOKEN`,
`PROXMOX_VE_INSECURE`, `CLOUDFLARE_API_TOKEN`, `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` (stan Terraforma), `BACKUP_AWS_ACCESS_KEY_ID` /
`BACKUP_AWS_SECRET_ACCESS_KEY` (Jenkins), `COMPOSER_AUTH_JSON`.

To **nie** jest to samo co `ansible/group_vars/all/secrets.sops.yml` - tamten
plik trzyma sekrety *wewnątrz* infrastruktury (hasła baz, tokeny aplikacji),
ten trzyma poświadczenia do *zewnętrznych* dostawców. Rozdzielenie jest
celowe: różne cykle rotacji, różni czytelnicy.

**Co edytować:** nowy sekret zewnętrzny (np. token kolejnego providera) -
`make secrets`, dopisz klucz `NAZWA: wartość`, zapisz. SOPS sam doszyfruje
plik zgodnie z regułą w `.sops.yaml`.

---

## 3. `terraform/`

### Pliki root modułu

| Plik | Za co odpowiada |
|---|---|
| `main.tf` | Wywołania modułów usługowych (`bastion`, `cicd`, `observability`, `wolffire/dev`, `wolffire/prod`) + 5 modułów `cloudflare/tunnel` (po jednym na maszynę usługową) + moduł DNS strefy |
| `locals.tf` | `vnets` (numer segmentu = 3. oktet podsieci) i `vm_ips` (adresy maszyn, których dotykają tunele i Prometheus) - **jedno źródło prawdy** dla adresacji |
| `variables.tf` | Zmienne wejściowe: `proxmox_endpoint`, `ssh_port` (22022), `bastion_public_ip`/`bastion_mac_address`, `ipv6_prefix`, `access_emails` |
| `outputs.tf` | `ssh_jump_host`, `vnets`, `proxmox_initial_password` (sensitive), `cloudflare_tunnel_tokens` (czyta je rola `cloudflared`), `public_hostnames` |
| `providers.tf` | Wersje providerów (`bpg/proxmox` 0.94.0, `cloudflare` 5.16.0) + backend S3 (`terraform-states-wf`, `use_lockfile`) + blok SSH providera proxmox (klucz `terraform_ed25519`) |

**Co edytować w typowych scenariuszach:**

- **Nowa maszyna** -> nowy moduł w `modules/services/proxmox/<nazwa>/main.tf`
  wołający `modules/base/proxmox/vm` (wzoruj się na `cicd/main.tf` - 20 linii),
  dopisz `vm_id` unikalny w obrębie segmentu, `private_ip` z `vnets` w
  `locals.tf`, `firewall_sgs` z listy grup w `bootstrap/locals.tf`. Potem
  wywołanie modułu w `main.tf`. Po stronie Ansible: wpis w `ansible/inventory.yml`
  (grupa + `private_ip`), host w `ansible/ssh_config` (`ProxyJump %r@wf-bastion-1`),
  przypisanie ról w `ansible/playbook.yml`.
- **Nowy port** dostępny z internetu przez tunel -> dopisz usługę do `services`
  w `tunnel.tf` modułu usługowego maszyny (np.
  `terraform/modules/services/proxmox/observability/tunnel.tf`).
  Port dostępny *między segmentami* (np. nowy eksporter) -> nowa reguła w
  odpowiedniej grupie bezpieczeństwa w
  `terraform/modules/services/proxmox/bootstrap/locals.tf` (patrz §3.1 niżej)
  **oraz** odpowiadająca reguła UFW w Ansible (`security/tasks/open_ports.yml`,
  wołana z roli, która instaluje usługę).
- **Zmiana wersji providera** -> `providers.tf`, `required_providers`, potem
  `terraform init -upgrade`.

### 3.1 `modules/services/proxmox/bootstrap/locals.tf` - grupy bezpieczeństwa

To jest **serce firewalla hypervisora**. Lokalny blok `security_groups`
(linie 24-235) definiuje grupy nazwane po funkcji, nie po maszynie:

| Grupa | Linie | Co przepuszcza |
|---|---|---|
| `base` | 28-53 | SSH (22022) z `dmz` (bastion) i z hypervisora (bootstrap); ICMP/ICMPv6 wewnątrz - doczepiana do **każdej** maszyny |
| `http` | 57-96 | HTTP/HTTPS z `dmz`, zakres 3000-9999 dla paneli, port 3100 (Loki push) z całej sieci wewnętrznej, port 80 dla scrape z monitoringu |
| `metrics` | 99-137 | Porty eksporterów (9100, 8081, 9323, 9253, 9187, 9121) - wyłącznie z adresu Prometheusa |
| `bastion` | 144-150 | **Jedyna** reguła wpuszczająca ruch z internetu - SSH 22022, nic więcej |
| `k3s-api` / `k3s-internal` | 152-168 | API klastra (6443) z sieci wewnętrznej; cały ruch wewnątrz segmentu `k3s` |
| `prod-postgres` / `prod-redis` | 170-194 | Baza z klastra k3s + pg_dump z CI/CD |
| `host-admin` | 198-234 | Reguły na sam hypervisor: SSH administratora, UI Proxmoxa (8006) tylko z sieci wewnętrznej, ICMP/ICMPv6, node_exporter |

**Nowy port dla istniejącej usługi** -> dopisz regułę (`name`, `protocol`,
`port`, `source`) do właściwej grupy tutaj. `source` odwołuje się do aliasu
(nazwa segmentu, `+hypervisor`, `+admins`) albo adresu z `aliases` (linie
10-20 tego samego pliku - merge nazw segmentów + `cicd`/`monitoring` jako
pojedyncze IP).

**Nowa grupa** dla nowego typu usługi -> dopisz klucz do `security_groups`,
potem podepnij go do maszyny przez `firewall_sgs` w jej module (§3, wyżej).

### 3.2 Pozostałe moduły `base/`

- **`base/proxmox/vm/`** - jeden moduł maszyny wirtualnej, wywoływany 8×.
  `main.tf`: firewall domyślnie `DROP` + grupa `base` zawsze doczepiona
  (linie 111-138), karta publiczna tylko gdy `mac_address != null` (praktycznie
  wyłącznie bastion), `ignore_changes` na `user_data_file_id` (cloud-init nie
  odtwarza maszyny przy zmianie konfiguracji Ansible).
- **`base/cloudflare/tunnel/`** - jeden tunel = jedna maszyna. `main.tf`
  tworzy tunel, rekord CNAME per usługa i (dla usług `protected: true`)
  podpina `zero_trust_policy`. Komentarz w pliku tłumaczy, dlaczego nie ma
  już jednego tunelu na bastionie.
- **`base/cloudflare/zero_trust_policy/`** - polityka Access: e-maile
  wpuszczające + opcjonalny bypass dla tokenów maszynowych/adresów IP.
- **`base/cloudflare/zone_settings/`** - przełączniki bezpieczeństwa strefy
  (SSL `strict`, `always_use_https`, min. TLS 1.2, HSTS) - wołane z
  `modules/services/cloudflare/dns`, nie z `main.tf` root.

### 3.3 `terraform/bootstrap/` - AWS, stan lokalny

Uruchamiane raz, ręcznie (`make bootstrap-aws`), **zanim** cokolwiek innego istnieje -
tworzy bucket na stan Terraforma (`state`, wersjonowany, szyfrowany, 90 dni
retencji starych wersji) i bucket na kopie zapasowe (`backups`, przejście do
Glacier po 30 dniach) oraz dwie tożsamości IAM: `wolffire-tf-state` (pełny
dostęp do bucketa stanu) i `wolffire-jenkins-backup` (zapis do bucketa kopii,
**bez** prawa `DeleteObject` na danych - `iam.tf`, blok `DenyDelete`; jedyny
wyjątek to `locks/*`, bo restic musi sprzątać własne pliki blokad). Klucze
trafiają ręcznie do `make secrets`.

Tu mieszka też kanał e-mail alertów (`sns.tf`): temat SNS `wolffire-alerts`,
subskrypcja e-mail (wymaga jednorazowego potwierdzenia linkiem z maila)
i trzecia tożsamość IAM `wolffire-alertmanager` z samym `sns:Publish`.
ARN tematu przechodzi do `ansible/group_vars/observability/main.yml`,
klucze do SOPS (`alertmanager_sns_*`).

**Co edytować:** zmiana retencji kopii -> `variables.tf` (`backup_retention_days`).
Kolejna tożsamość IAM z innym zakresem -> nowy `aws_iam_user` + polityka w `iam.tf`.
Zmiana adresu alertów -> `variables.tf` (`alerts_email`) + apply + ponowne
potwierdzenie subskrypcji.

---

## 4. `ansible/`

### Pliki konfiguracyjne

| Plik | Za co odpowiada |
|---|---|
| `ansible.cfg` | `inventory.yml` jako źródło, `remote_user: ansible`, `roles_path`, plugin `community.sops` (deszyfrowanie `*.sops.yml` w locie) |
| `ssh_config` | **Jedyne** źródło topologii SSH - port 22022, `ProxyJump %r@wf-bastion-1`, ścieżki kluczy. Używane przez `ansible_connection: ssh` (`ssh_args = -F ssh_config`) i przez ludzi bezpośrednio |
| `inventory.yml` | Grupy (`bastion`, `cicd`, `observability`, `k3s_server`, `k3s_agent`, `postgres`, `redis`, `docker`, `dev`, `prod`) + `private_ip` jako dane dla szablonów (Prometheus, Loki) |
| `playbook.yml` | Kolejność wykonania: role wspólne na `all`, potem `ipv6_router` na `proxmox`, `routes` na `bastion`, `cloudflared` na `cicd:observability:proxmox:dev` + osobno na `k3s_server`, potem role per usługa |
| `bootstrap-host.yml` | Krok zerowy - patrz README, sekcja "Dlaczego `make bootstrap-host` jest osobno" |
| `requirements.yml` | Kolekcje: `cloud.terraform` (czyta tokeny tuneli ze stanu), `community.sops`, `community.docker`, `community.postgresql`, `ansible.posix` |
| `group_vars/all/main.yml` | Zmienne wspólne: `ssh_port`, adresy IP maszyn używane w regułach (`bastion_ip`, `monitoring_ip`, `cicd_ip`, `db_ip`, `k3s_subnet`), kanał alertów |
| `group_vars/all/secrets.sops.yml` | Sekrety **wewnętrzne**: hasła baz, `k3s_token`, `ghcr_token`, `jenkins_admin_password`, `restic_password`, webhooki powiadomień |
| `group_vars/<grupa>/main.yml` | Zmienne per grupa, m.in. `cloudflared_tunnel_name` (musi zgadzać się z nazwą tunelu w `terraform/main.tf`) |
| `host_vars/proxmox-1/main.yml` | `ipv6_delegated_prefixes` - podprefiksy IPv6 per segment (wyliczone z `ipv6_prefix` w Terraformie) |

**Co edytować w typowych scenariuszach:**

- **Nowa maszyna** -> wpis w `inventory.yml` (grupa + `private_ip`), host
  w `ssh_config`, przypisanie ról w `playbook.yml` (`- hosts: <grupa>` /
  `roles: [...]`). Jeśli maszyna dostaje własny tunel Cloudflare - dopisz
  `cloudflared_tunnel_name` w jej `group_vars`.
- **Nowy sekret wewnętrzny** (hasło, token) -> `sops ansible/group_vars/all/secrets.sops.yml`,
  dopisz klucz, użyj go w roli jako zmiennej o tej samej nazwie (plugin
  `community.sops` odszyfrowuje plik automatycznie przy starcie playbooka).

### Role - jednym akapitem każda

| Rola | Co robi |
|---|---|
| `hostname` | Ustawia hostname zgodny z inventory na każdej maszynie poza hypervisorem (Proxmox nie obsługuje zmiany nazwy węzła) i wpisuje go do `/etc/hosts` (127.0.1.1), żeby `sudo` nie czekało na DNS. |
| `login` | Trzy podzadania: konta imienne z `keys/humans/*.pub` (`users.yml`), sudo bez hasła (`sudo.yml`), utwardzenie SSH (`ssh.yml`). |
| `security` | UFW (domyślnie `deny incoming`, reguły wpuszczające **przed** włączeniem polityki), fail2ban na SSH, `unattended-upgrades`. Zawiera też `open_ports.yml` - reużywalne zadanie wołane przez inne role, żeby reguła firewalla mieszkała obok usługi, która ją uzasadnia. |
| `observability` | `node_exporter` na **każdej** maszynie, nasłuch na `private_ip` (nie na adresie domyślnym - na bastionie domyślna trasa idzie przez interfejs publiczny). |
| `alloy` | Agent logów Grafana Alloy - journald na każdej maszynie, gniazdo Dockera tam, gdzie Docker stoi. Wysyła do Loki na `monitoring-1`. |
| `ipv6_router` | Wyłącznie na `proxmox`: włącza forwarding IPv6 i proxy NDP (`ndppd`), odpowiada za publiczną adresację `dmz`. Kończy się `ping6` do Cloudflare jako testem żywotności. |
| `routes` | Wyłącznie na `bastion`: dopisuje trasę statyczną do segmentów wewnętrznych przez interfejs prywatny (karta publiczna inaczej przechwyciłaby cały ruch). |
| `cloudflared` | Instaluje `cloudflared`, czyta token tunelu **ze stanu Terraforma** (`cloud.terraform.terraform_output`, nie z SOPS - token nie może się rozjechać ze stanem), stawia jednostkę systemd. Uruchamiana na `cicd`, `observability`, `proxmox`, `dev` **i osobno** na `k3s_server` - **nie** na `bastion`. |
| `docker` | Docker Engine + Compose plugin, `daemon.json` (limit logów, `live-restore`, metryki na `private_ip`), cAdvisor jako kontener uprzywilejowany. |
| `k3s` | Wspólna część (`tasks/main.yml`) + `server.yml` (control plane, Traefik jako ingress, port 80/443 tylko z bastionu, kubeconfig z podmienionym adresem) + `agent.yml` (dołączanie do klastra przez `K3S_TOKEN`, weryfikacja `Ready` na wszystkich węzłach). |
| `wolffire_prod` | Instaluje Helm, kopiuje `helm/wolffire` na `k3s-server-1`, generuje `values-prod.yaml.j2` z sekretami, `helm upgrade --install` (uruchamiane tylko gdy coś się realnie zmieniło - `helm list`, nie `helm status`, żeby nie logować sekretów), weryfikuje pody i odpowiedź aplikacji przez Traefik. |
| `postgres` | Postgres z PGDG (nie z Ubuntu - potrzebna wersja 18), tworzy bazę i użytkownika aplikacji, odbiera publiczny `CONNECT`, tworzy rolę eksportera z `pg_monitor` (bez superusera), `postgres_exporter` jako pakiet dystrybucji (maszyna bazy celowo nie ma Dockera). |
| `redis` | Redis 7 z repo Ubuntu (celowo nie z `packages.redis.io`, żeby `apt upgrade` nie przeskoczył majora), `vm.overcommit_memory=1` (fork przy przepisywaniu AOF), `redis_exporter` jako binarka z GitHuba z wersjonowanym katalogiem i dowiązaniem `current`. |
| `jenkins` | Buduje własne obrazy kontrolera i agenta (tag = hash z treści Dockerfile), agent doklejony o `pg_dump` + `restic` do `jenkins/inbound-agent`, cała konfiguracja z JCasC (`jenkins.yaml.j2` - zadanie `infra-backup`, poświadczenia, chmura agentów jako kontenery Docker), weryfikacja logu startu pod kątem błędów JCasC. |
| `monitoring` | Prometheus + Grafana + Alertmanager + Loki + `calert` (adapter na Google Chat) w Compose na `monitoring-1`. Montuje **katalogi**, nie pojedyncze pliki (patrz ARCHITECTURE §9, pkt 4). Pobiera gotowe dashboardy z grafana.com i podmienia placeholdery źródeł danych; własne dashboardy WolfFire są szablonami Jinja. |
| `wolffire` | Środowisko dev: loguje się do GHCR, generuje `.env`/`compose.yml`, jednostka systemd `wolffire.service`, migracje jako osobny kontener (`docker compose run --rm --no-deps`), cache Laravela odbudowywany bezwarunkowo (żyje w warstwie zapisu kontenera). |

### 4.1 Monitoring - gdzie dodać alert / dashboard

- **Nowy alert** -> `ansible/roles/monitoring/templates/alerts.yml.j2`. Reguł
  jest celowo mało (komentarz na górze pliku) - dodawaj tylko sygnały, które
  faktycznie wymagają reakcji. Wzorzec: `expr`, `for` (żeby chwilowy skok nie
  wywołał powiadomienia), `labels.severity`, `annotations.summary/description`.
- **Nowy dashboard z grafana.com** -> dopisz wpis `plik: id` do
  `grafana_dashboards` w `ansible/roles/monitoring/defaults/main.yml` (id to
  numer z URL-a dashboardu). Rola sama pobierze go przy następnym przebiegu
  i podmieni placeholdery źródeł danych.
- **Własny dashboard** -> nowy szablon `dashboard-<nazwa>.json.j2` w
  `templates/`, dopisany do pętli `Wgraj własne dashboardy` w
  `ansible/roles/monitoring/tasks/main.yml` (linie 117-131).
- **Nowy port panelu dostępny z internetu** -> dopisz usługę w
  `terraform/modules/services/proxmox/observability/tunnel.tf`.

---

## 5. `helm/wolffire/`

| Plik | Za co odpowiada |
|---|---|
| `Chart.yaml` | Wersja chartu (`version`) i wersja aplikacji domyślna (`appVersion`) |
| `values.yaml` | Wartości domyślne: repozytoria obrazów **GHCR** (`ghcr.io/serwin35/wf-chartapp-diploma/{php,nginx}`), puste sekrety oznaczone jako wymagane (instalacja bez nich ma się wywalić), limity zasobów, `filesystemDisk: local` (patrz ARCHITECTURE §7 - `emptyDir`, nie S3) |
| `templates/deployment-php.yaml` | `storage/app` montowany jako `emptyDir` - świadome ograniczenie dema (komentarz w pliku) |
| `templates/deployment-nginx.yaml` | Nginx jako sidecar/serwis przed PHP-FPM |
| `templates/deployment-horizon.yaml` / `deployment-scheduler.yaml` | Kolejki Laravel Horizon i scheduler - zawsze 1 replika schedulera |
| `templates/job-migrate.yaml` | Migracje jako hook Helma, osobny Job z tego samego obrazu |
| `templates/ingress.yaml` | Ingress na klasę `traefik` (wbudowany w k3s) |
| `templates/secret-ghcr.yaml` | `dockerconfigjson` budowany z `ghcrUsername`/`ghcrToken` - GHCR jest prywatny |
| `templates/secret-env.yaml` | Sekrety aplikacji (klucz Laravela, hasła bazy/Redisa) |

**Co edytować w typowych scenariuszach:**

- **Zmiana wersji obrazu** - w produkcji robi to CD (`helm upgrade --set
  image.php.tag=<sha> --set image.nginx.tag=<sha>`), **nie** edytuj `values.yaml`
  ręcznie dla wdrożenia. Zmiana wersji *domyślnej* (np. do dema bez CD) ->
  `values.yaml`, klucze `image.php.tag` / `image.nginx.tag`, albo
  `wolffire_image_tag` w `ansible/roles/wolffire_prod/defaults/main.yml`
  (zmienna przekazywana do `helm upgrade` przez rolę).
- **Nowa zmienna środowiskowa aplikacji** -> `values.yaml` (sekcja `app:`),
  potem `templates/configmap-env.yaml` albo `secret-env.yaml` (jeśli wrażliwa),
  potem `ansible/roles/wolffire_prod/templates/values-prod.yaml.j2`, jeśli
  wartość ma pochodzić z sekretów Ansible.
- **Więcej replik PHP-FPM** -> `values.yaml`, `php.replicaCount` - pamiętaj
  o ograniczeniu `emptyDir` (ARCHITECTURE §7): przy >1 replice trzeba
  najpierw przełączyć `filesystemDisk` na `s3`.

---

## 6. `scripts/`

Testy dymne całej infrastruktury - **wyłącznie odczyt**: Terraform w trybie
`plan -lock=false`, Ansible w trybie `--check`, reszta to zapytania HTTP,
`kubectl get` i próby połączenia TCP.

| Plik | Rola |
|---|---|
| `smoke-test.sh` | Wejście - dobiera sekcje (`net panels monitoring k3s db fw tf ansible`), definiuje kolejność (od sieci, przez usługi, po kod) |
| `lib/config.sh` | **Jedyne miejsce** do aktualizacji adresów/portów/limitów czasu, gdy zmienia się infrastruktura |
| `lib/report.sh` | Kolory, liczniki, `ok`/`ko`/`skip`, podsumowanie na końcu |
| `lib/run.sh` | Limit czasu, próba TCP, narzędzia tekstowe |
| `lib/ssh.sh` | Multipleksowane połączenia SSH do maszyn (bez powtarzania handshake'u) |
| `lib/secrets.sh` | Odczyt poświadczeń z SOPS na potrzeby testów |
| `checks/*.sh` | Po jednym pliku na sekcję - `network.sh`, `panels.sh`, `monitoring.sh`, `k3s.sh`, `databases.sh`, `firewall.sh`, `terraform.sh`, `ansible.sh` |
| `sync-dev-db-to-prod.sh` | Operacyjny (JEDYNY zapisujący): zrzut bazy dev -> odtworzenie na prod + przepięcie właścicieli, czyszczenie kluczy aplikacji w Redisie, restart Horizona, weryfikacja. Używany, bo `DemoSeeder` wymaga zależności deweloperskich (faker), których obraz produkcyjny celowo nie ma |

**Co edytować:** nowa maszyna albo usługa, którą smoke-test ma sprawdzać ->
`lib/config.sh` (adres/port), potem odpowiedni plik w `checks/`. Zmienne
sterujące: `SMOKE_EXPECT_APP=1` (aplikacja już wdrożona), `SMOKE_FULL=1`
(dodaje test idempotentności Ansible), `SMOKE_SKIP_TF=1`.

---

## 7. `keys/`

| Ścieżka | Zawartość |
|---|---|
| `README.md` | Model tożsamości SSH - kto używa którego klucza i dlaczego |
| `terraform_ed25519.pub` / `ansible_ed25519.pub` | Klucze maszynowe (publiczne) |
| `terraform_ed25519` / `ansible_ed25519` | Klucze maszynowe (prywatne) - **gitignored** |
| `humans/*.pub` | Klucze osobiste; nazwa pliku = nazwa konta zakładanego przez rolę `login` |

**Co edytować:** nowa osoba z dostępem -> jej `*.pub` do `keys/humans/`,
`ansible-playbook playbook.yml --tags login` zakłada jej konto na wszystkich
maszynach. Rotacja klucza maszynowego -> procedura w `keys/README.md`
("Odtworzenie od zera").

---

## 8. `docs/`

| Plik | Do czego służy |
|---|---|
| `ARCHITECTURE.md` | *Dlaczego* infrastruktura wygląda tak, a nie inaczej - decyzje i kompromisy |
| `PRZEWODNIK.md` | *Gdzie* i *jak* - ten dokument |
| `RUNBOOK.md` | Komendy operacyjne, diagnostyka awarii, ściąga na obronę |
| `PLAN.md` | Status realizacji per faza, pokrycie kryteriów oceny |

**Co edytować:** nowa decyzja architektoniczna z uzasadnieniem ->
`ARCHITECTURE.md`, nowa sekcja numerowana. Nowa procedura operacyjna ->
`RUNBOOK.md`. Zmiana w plikach opisanych w tym przewodniku -> aktualizuj
odpowiedni akapit tutaj, żeby dokument nie rozjechał się ze stanem
faktycznym.

---

## 9. Ściąga: co edytować w typowych scenariuszach

| Scenariusz | Pliki |
|---|---|
| **Nowa maszyna** | `terraform/modules/services/proxmox/<usługa>/main.tf` (nowy moduł VM) -> `terraform/main.tf` (wywołanie) -> `ansible/inventory.yml` (grupa + adres) -> `ansible/ssh_config` (host + ProxyJump) -> `ansible/playbook.yml` (role) |
| **Nowy port międzysegmentowy** | `terraform/modules/services/proxmox/bootstrap/locals.tf` (reguła w grupie bezpieczeństwa) + `ansible/roles/<rola>/tasks/main.yml` (wywołanie `security/open_ports.yml`) |
| **Nowy port publiczny przez tunel** | `terraform/main.tf`, sekcja `services` odpowiedniego modułu `cloudflare_*` |
| **Nowy sekret zewnętrzny** (provider) | `make secrets` -> `secrets.sops.yaml` |
| **Nowy sekret wewnętrzny** (hasło, token appki) | `sops ansible/group_vars/all/secrets.sops.yml` |
| **Nowy alert** | `ansible/roles/monitoring/templates/alerts.yml.j2` |
| **Nowy dashboard (gotowiec)** | `ansible/roles/monitoring/defaults/main.yml`, słownik `grafana_dashboards` |
| **Nowy dashboard (własny)** | `ansible/roles/monitoring/templates/dashboard-<nazwa>.json.j2` + pętla w `tasks/main.yml` |
| **Zmiana wersji obrazu aplikacji** | CD: `helm upgrade --set image.*.tag`. Ręcznie/domyślnie: `helm/wolffire/values.yaml` albo `ansible/roles/wolffire_prod/defaults/main.yml` (`wolffire_image_tag`) |
| **Zmiana wersji obrazu infrastruktury** (Prometheus, Grafana, ...) | `ansible/roles/monitoring/defaults/main.yml` - zmienne `*_image` |
| **Nowa osoba z dostępem SSH** | `keys/humans/<login>.pub` -> `ansible-playbook playbook.yml --tags login` |
