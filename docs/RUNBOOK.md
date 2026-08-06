# Runbook - komendy operacyjne

Ściąga do codziennej pracy i do obrony. Uzasadnienia decyzji:
[ARCHITECTURE.md](ARCHITECTURE.md). Status realizacji: [PLAN.md](PLAN.md).

Pełny, przeszukiwalny opis komend dla każdego narzędzia (z tabelami flag,
troubleshootingiem i przykładami wyjścia) jest w [`docs/komendy/`](komendy/):
[`terraform.md`](komendy/terraform.md), [`ansible.md`](komendy/ansible.md),
[`kubernetes.md`](komendy/kubernetes.md), [`docker.md`](komendy/docker.md),
[`monitoring.md`](komendy/monitoring.md), [`sops.md`](komendy/sops.md),
[`git.md`](komendy/git.md). Ten dokument zostaje skrótem operacyjnym i
scenariuszem obrony.

---

## 1. Awaria: brak dostępu do hypervisora

Objaw: `ssh wf-proxmox-1` zwraca timeout albo connection refused, maszyny są
nieosiągalne.

### Kolejność dróg wejścia

| # | Droga | Kiedy zadziała |
|---|---|---|
| 1 | `ssh wf-proxmox-1` (port 22022) | normalnie |
| 2 | `https://proxmox.wolffire.dev` -> Shell w UI | gdy żyje tunel **i** port 8006 jest przepuszczony |
| 3 | SSH po IPv6 na bastion | gdy Twoja sieć ma IPv6 |
| 4 | **KVM/IPMI w panelu OVH** | zawsze |
| 5 | **Tryb rescue OVH** | zawsze, nawet gdy system nie wstaje |

### Rescue OVH - procedura pełna

Panel OVH -> serwer -> *Boot* -> **Rescue** (`rescue64-pro`) -> restart. Hasło do
trybu rescue przychodzi mailem.

```bash
ssh root@<adres-rescue>

# Znajdz i zamontuj system produkcyjny
lsblk -f
mount /dev/md3 /mnt              # partycja root (ext4, md-raid)
```

Najczęstsze naprawy:

```bash
# A. sshd wrocil na port 22 (nadpisany drop-in)
cat > /mnt/etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
Port 22022
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication no
EOF

# B. UFW zablokowal routing miedzy segmentami / NAT
rm -f /mnt/etc/systemd/system/multi-user.target.wants/ufw.service
chroot /mnt ufw disable          # jesli chroot dziala

# C. fail2ban zbanowal Twoj adres
rm -f /mnt/var/lib/fail2ban/fail2ban.sqlite3

umount /mnt
```

Panel OVH -> *Boot* -> **Boot from hard disk** -> restart.

### Weryfikacja po naprawie

```bash
ssh wf-proxmox-1 'ss -tlnp | grep sshd'          # nasluchuje na 22022?
ssh wf-proxmox-1 'ufw status'                     # ma byc inactive na hypervisorze
ssh wf-proxmox-1 'sudo pve-firewall status'
ssh wf-proxmox-1 'sudo fail2ban-client status sshd'
```

---

## 2. Dostęp do maszyn

Dwa konta na każdej maszynie, dwa różne zastosowania:

| Konto | Kto go używa | Jak wejść |
|---|---|---|
| `ansible` (domyślne) | Ansible, procesy automatyczne, Ty na co dzień | `ssh wf-<host>-1` (user domyślny z `ssh_config`) |
| imienne, np. `mserwinowski` | Ludzie, do audytu/logowania z imienną tożsamością | `ssh mserwinowski@wf-<host>-1` |

Oba konta dostają na starcie ten sam zestaw kluczy (cloud-init) - imienne
konta zakłada później rola `login` na podstawie plików `keys/humans/*.pub`
(nazwa pliku = nazwa użytkownika). Dodanie osoby do projektu to jeden nowy
plik `.pub` w tym katalogu.

```bash
ssh wf-monitoring-1                     # konto maszynowe (ansible)
ssh mserwinowski@wf-monitoring-1        # konto imienne
```

Aliasy `wf-<host>-1` działają z dowolnego katalogu i dowolnego terminala -
autouzupełnianie działa, wpisz `wf-` i Tab.

| Alias | Maszyna | Co na niej stoi |
|---|---|---|
| `wf-proxmox-1` | hypervisor | Proxmox VE, SDN, ndppd |
| `wf-bastion-1` | bastion | **wyłącznie wejście SSH** - jedyna maszyna z publicznym adresem, bez paneli, bez cloudflared |
| `wf-cicd-1` | cicd-1 | Jenkins (kopie zapasowe), self-hosted runner GitHuba |
| `wf-monitoring-1` | monitoring-1 | Prometheus, Grafana, Loki, Alertmanager |
| `wf-wolffire-dev-app-1` | wolffire-dev-app-1 | aplikacja w Docker Compose (środowisko dev) |
| `wf-k3s-server-1` | k3s-server-1 | control plane klastra prod |
| `wf-k3s-agent-1` | k3s-agent-1 | pody aplikacji |
| `wf-k3s-agent-2` | k3s-agent-2 | pody aplikacji |
| `wf-wolffire-prod-db-1` | wolffire-prod-db-1 | Postgres + Redis produkcyjne (natywne pakiety, nie Docker) |

### Co się dzieje pod spodem

```
Twoj laptop
   │  ssh wf-monitoring-1
   ├─ ~/.ssh/config -> Include -> ansible/ssh_config
   │     HostName    10.0.120.20     ← adres prywatny, nieosiagalny z internetu
   │     ProxyJump   %r@wf-bastion-1 ← wiec najpierw skok przez bastion, tym samym userem (%r)
   │     Port        22022
   │     IdentityFile keys/ansible_ed25519 (+ Twoj osobisty klucz)
   │
   ├─-> 51.83.139.3:22022      (bastion, jedyny publiczny adres IPv4)
   └─-> 10.0.120.20:22022      (monitoring-1, przez most SDN `apps`)
```

Jedno polecenie, dwa przeskoki, zero konfiguracji do zapamiętania.
Wyjątkiem od reguły "wszystko przez bastion" jest `wf-proxmox-1` - ma adres
publiczny bezpośrednio (potrzebny na etapie provisioningu i jako droga
awaryjna, patrz §1) i sam pełni rolę jump hosta dla Terraforma i dla ludzi
w razie awarii bastionu.

### Dlaczego prefiks `wf-`

`~/.ssh/config` wciąga konfiguracje innych projektów, w których istnieją hosty
o nazwach `proxmox-1` i `bastion-1`. Bez prefiksu SSH bierze **pierwsze
dopasowanie** i łączy się z cudzym serwerem - objawia się to błędem
„proxy loop detected" albo, gorzej, cichym zalogowaniem nie tam, gdzie trzeba.

Aliasy działają globalnie dzięki wpisowi na początku `~/.ssh/config`:

```
Include /Users/serwin/Projects/DevOps-Kurs/devops-diploma-2026/ansible/ssh_config
```

Gdyby go zabrakło, trzeba wskazać plik jawnie - samo `ssh` **nie czyta**
`./ssh_config` z bieżącego katalogu:

```bash
ssh -F ansible/ssh_config wf-monitoring-1
```

### Warianty użycia

```bash
# Komenda bez wchodzenia do powloki
ssh wf-monitoring-1 'docker compose -f /opt/monitoring/compose.yml ps'
ssh wf-k3s-server-1 'sudo k3s kubectl get pods -A'

# Kopiowanie plikow
scp raport.txt wf-monitoring-1:/tmp/
scp wf-monitoring-1:/opt/monitoring/prometheus.yml ./

# Tunel lokalny - panel w przegladarce z pominieciem Cloudflare.
# Przydaje sie, gdy Access marudzi albo chcesz cos sprawdzic bez logowania.
ssh -L 3000:10.0.120.20:3000 wf-bastion-1     # -> http://localhost:3000  (Grafana)
ssh -L 9090:10.0.120.20:9090 wf-bastion-1     # -> http://localhost:9090  (Prometheus)
ssh -L 8006:localhost:8006 wf-proxmox-1       # -> https://localhost:8006 (UI Proxmoxa)

# Trwale polaczenie w tle - kolejne ssh do tego hosta sa natychmiastowe
ssh -fN wf-monitoring-1
```

**Uwaga:** porty usług na maszynach docelowych są opublikowane na adresie
*prywatnym* maszyny (np. `10.0.120.20:9090`), nie na `localhost` ani
`0.0.0.0`. Tunel lokalny musi więc celować w ten adres, nie w `localhost`
maszyny docelowej - inaczej `ssh -L 9090:localhost:9090 wf-monitoring-1`
łączy się z portem, który tam w ogóle nie nasłuchuje.

### API Proxmoxa przez tunel SSH

API Proxmoxa (port 8006) nie jest wystawione do internetu. Terraform i
polecenia ręczne dochodzą do niego tunelem SSH na `127.0.0.1:18006`:

```bash
# To samo, co Makefile robi automatycznie przed 'plan'/'infra'
ssh -F ansible/ssh_config -O check wf-proxmox-1 2>/dev/null || \
  ssh -F ansible/ssh_config -fN -L 18006:localhost:8006 wf-proxmox-1
```

`-O check` sprawdza, czy tunel z poprzedniego uruchomienia (dzięki
`ControlPersist=120s` w `ansible/ssh_config`) wciąż żyje - jeśli tak, drugie
polecenie się nie wykonuje i nie ma próby podwójnego bindowania portu.
Terraform w `terraform/providers.tf` łączy się z `https://127.0.0.1:18006`.

### Gdy SSH nie chce się połączyć

| Komunikat | Przyczyna | Naprawa |
|---|---|---|
| `Host key verification failed` | maszyna dostała nowe klucze (np. po przepięciu cloud-inita) | `ssh-keygen -R "[10.0.120.20]:22022"` |
| `no such identity: ../keys/...` | względna ścieżka do klucza spoza katalogu `ansible/` | już naprawione - ścieżka jest bezwzględna |
| `Connection refused` | sshd nie nasłuchuje na tym porcie | `ssh wf-proxmox-1 'sudo qm guest exec <id> -- /usr/bin/ss -tln'` |
| `Operation timed out` | firewall odrzuca pakiety | `ssh wf-proxmox-1 'sudo pve-firewall compile \| grep <ip>'` |
| `proxy loop detected` | kolizja nazw z inną konfiguracją SSH | użyj aliasu z prefiksem `wf-` |
| `bind [127.0.0.1]:18006: Address already in use` | tunel API Proxmoxa już działa (poprzedni `ControlPersist`) | nieszkodliwe - użyj `-O check` zamiast zakładać nowy tunel |

---

## 3. Kubernetes

Klaster k3s: `k3s-server-1` (control-plane) + `k3s-agent-1`, `k3s-agent-2`.
Pełny zestaw komend (diagnostyka CrashLoop/OOM, Helm, rollout) jest w
[`docs/komendy/kubernetes.md`](komendy/kubernetes.md). Tu - skrót operacyjny.

```bash
ssh wf-k3s-server-1
sudo k3s kubectl get nodes -o wide
```

Wygodniej ustawić alias raz na maszynie:

```bash
echo "alias k='sudo k3s kubectl'" >> ~/.bashrc && source ~/.bashrc
```

### Podstawowy przegląd

```bash
k get nodes -o wide                     # wezly, wersje, adresy
k get pods -A                           # WSZYSTKIE pody, wszystkie przestrzenie
k get pods -n wolffire -o wide          # pody aplikacji wraz z wezlem
k get svc -A                            # serwisy
k get ingress -A                        # wejscia HTTP
k get deploy,rs -n wolffire             # deploymenty i replikasety
k get events -A --sort-by=.lastTimestamp | tail -20
```

Deploymenty aplikacji w namespace `wolffire`: `wolffire-php`, `wolffire-nginx`,
`wolffire-horizon`, `wolffire-scheduler` - wdrażane chartem Helm
`helm/wolffire`.

### Diagnostyka poda

```bash
k describe pod <nazwa> -n wolffire      # zdarzenia, powody restartow
k logs <nazwa> -n wolffire              # logi
k logs <nazwa> -n wolffire --previous   # logi poprzedniej instancji po crashu
k logs -f deploy/wolffire-php -n wolffire
k exec -it <nazwa> -n wolffire -- sh    # powloka w kontenerze
```

### Zasoby i kondycja

```bash
k top nodes                             # zuzycie CPU/RAM wezlow
k top pods -A
k get pvc -A                            # wolumeny trwale
k get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type
```

### Demonstracja na obronę

```bash
# 1. Skalowanie
k scale deploy/wolffire-php -n wolffire --replicas=3
k get pods -n wolffire -w               # obserwuj, jak wstaja

# 2. Rolling update (w praktyce robi to `helm upgrade --set image.tag=<sha>`)
k set image deploy/wolffire-php php=ghcr.io/serwin35/wf-chartapp-diploma/php:<sha> -n wolffire
k rollout status deploy/wolffire-php -n wolffire
k rollout history deploy/wolffire-php -n wolffire
k rollout undo deploy/wolffire-php -n wolffire      # wycofanie

# 3. Przelozenie podow na inny wezel
k drain k3s-agent-1 --ignore-daemonsets --delete-emptydir-data
k get pods -n wolffire -o wide          # pody sa juz na agent-2
k uncordon k3s-agent-1
```

---

## 4. Docker i Compose

Pełny zestaw komend (inspect, budowanie z sekretem BuildKit, GHCR) jest w
[`docs/komendy/docker.md`](komendy/docker.md).

```bash
ssh wf-monitoring-1

sudo docker ps                                    # dzialajace kontenery
sudo docker ps -a                                 # takze zatrzymane
sudo docker stats --no-stream                     # zuzycie zasobow
sudo docker images
sudo docker network ls && sudo docker volume ls
sudo docker logs -f prometheus
sudo docker exec -it grafana sh
```

Stos monitoringu w Compose stoi w `/opt/monitoring`:

```bash
cd /opt/monitoring
sudo docker compose ps
sudo docker compose logs -f --tail=50
sudo docker compose restart prometheus
sudo docker compose up -d                         # po zmianie compose.yml
sudo docker compose pull && sudo docker compose up -d   # aktualizacja obrazow
```

Stos aplikacji dev w `/opt/wolffire` ma katalog `0750 root:root` - samo
`cd` bez `sudo` kończy się `Permission denied`, nawet dla konta `ansible`:

```bash
sudo bash -c 'cd /opt/wolffire && docker compose ps'
```

Sprzątanie, gdy braknie miejsca:

```bash
sudo docker system df                             # co zajmuje miejsce
sudo docker system prune -a --volumes             # UWAGA: kasuje nieuzywane wolumeny
```

---

## 5. Usługi systemowe

```bash
systemctl is-active <usluga>                      # jedno slowo: active/inactive
systemctl status <usluga>
sudo systemctl restart <usluga>
journalctl -u <usluga> -n 50 --no-pager
journalctl -u <usluga> -f                         # na zywo
journalctl -u <usluga> --since "10 min ago"
systemctl list-units --failed                     # co sie wysypalo
```

Usługi tego projektu:

| Usługa | Maszyna(y) | Co robi |
|---|---|---|
| `cloudflared` | cicd-1, monitoring-1, proxmox-1, wolffire-dev-app-1, k3s-server-1 | tunel Cloudflare **per maszyna** - bastion go NIE uruchamia, to wyłącznie wejście SSH |
| `ndppd` | proxmox-1 | proxy NDP dla IPv6 |
| `prometheus-node-exporter` | wszystkie | metryki systemowe |
| `docker` | cicd-1, monitoring-1, wolffire-dev-app-1 | silnik kontenerow |
| `fail2ban` | wszystkie | blokowanie atakow slownikowych |
| `k3s` / `k3s-agent` | k3s-server-1 / k3s-agent-1, k3s-agent-2 | klaster (control-plane / agenty) |
| `postgresql`, `redis-server` | wolffire-prod-db-1 | baza i kolejki produkcyjne, natywne pakiety (nie Docker) |
| `wolffire` | wolffire-dev-app-1 | jednostka systemd owijająca `docker compose` aplikacji dev |

### Szybki przegląd całej floty

```bash
cd ansible
ansible all -m shell -a 'systemctl is-active docker prometheus-node-exporter fail2ban' -o
ansible all -m shell -a 'uptime; free -h | head -2' -o
ansible all -m shell -a 'df -h / | tail -1' -o
```

---

## 6. Sieć i firewall

```bash
# Na maszynie gosciu
sudo ufw status verbose                           # reguly + polityki domyslne
sudo ufw status numbered
ss -tlnp                                          # co nasluchuje
ip -br a                                          # adresy

# Na hypervisorze
sudo pve-firewall status
sudo pve-firewall compile | head -40              # wygenerowane reguly
sudo qm list                                      # maszyny wirtualne
sudo qm config 110                                # konfiguracja jednej
```

**Na hypervisorze UFW ma być `inactive`** - firewall opisuje tam Terraform
(`pve-firewall`). Dwa narzędzia na tym samym nftables wchodzą sobie w drogę,
a domyślna polityka FORWARD UFW blokuje routing między segmentami SDN.

Test łączności między segmentami:

```bash
ssh wf-bastion-1 'nc -zv 10.0.120.20 3000'           # bastion -> Grafana
ssh wf-monitoring-1 'nc -zv 10.0.140.10 5432'        # monitoring -> Postgres
```

Gdy maszyna wisi - konsola przez agenta QEMU, bez SSH:

```bash
ssh wf-proxmox-1 'sudo qm guest exec 121 -- /bin/systemctl is-active docker'
ssh wf-proxmox-1 'sudo qm guest exec 121 -- /usr/bin/ss -tln'
```

---

## 7. Monitoring

Pełny zestaw (PromQL, API Prometheusa/Alertmanagera, LogQL) jest w
[`docs/komendy/monitoring.md`](komendy/monitoring.md).

```bash
# Czy Prometheus widzi wszystkie cele
ssh -L 9090:10.0.120.20:9090 wf-bastion-1
# -> http://localhost:9090/targets
```

Albo bez tunelu, prosto z maszyny - **adresem prywatnym, nie `localhost`**,
bo porty są opublikowane wyłącznie na `10.0.120.20`:

```bash
ssh wf-monitoring-1 'curl -s http://10.0.120.20:9090/api/v1/targets | jq -r ".data.activeTargets[] | \"\(.labels.job) \(.labels.instance) \(.health)\""'
ssh wf-monitoring-1 'curl -s http://10.0.120.20:9090/-/ready'
ssh wf-monitoring-1 'curl -s http://10.0.120.20:9090/api/v1/alerts | jq ".data.alerts"'
ssh wf-monitoring-1 'curl -s http://10.0.120.20:9093/-/healthy'                  # Alertmanager
ssh wf-monitoring-1 'curl -s http://10.0.120.20:3000/api/health'                  # Grafana
```

Panele przez przeglądarkę:

| Adres | Usługa | Ochrona |
|---|---|---|
| `https://proxmox.wolffire.dev` | UI hypervisora | Zero Trust Access |
| `https://grafana.wolffire.dev` | dashboardy | Zero Trust Access |
| `https://prometheus.wolffire.dev` | metryki i cele | Zero Trust Access |
| `https://alerts.wolffire.dev` | Alertmanager | Zero Trust Access |
| `https://jenkins.wolffire.dev` | Jenkins | Zero Trust Access |
| `https://dev.wolffire.dev` | aplikacja, środowisko dev | bez Access - logowanie na poziomie aplikacji |
| `https://wolffire.dev` | aplikacja, produkcja (k3s) | bez Access - logowanie na poziomie aplikacji |

Interpretacja kodów odpowiedzi:

| Kod | Znaczenie |
|---|---|
| **302** -> `cloudflareaccess.com` | poprawnie - Access żąda logowania |
| **302** -> `/login` albo `/dashboard` na tej samej domenie | poprawnie - to przekierowanie aplikacji, nie Access |
| **502** | tunel dotarł do bastionu, ale usługa docelowa nie odpowiada |
| **1033** | tunel nie działa - sprawdź `cloudflared` na maszynie usługi (NIE na bastionie) |
| **brak odpowiedzi** | rekord DNS nie istnieje albo nie jest proxied |

### Alerty e-mail (AWS SNS)

Alerty warning/critical idą równolegle na Google Chat i e-mail. Operacje
wokół kanału e-mail:

```bash
# Stan subskrypcji (ConfirmationPending = nikt nie kliknal linku z maila,
# Deleted = ktos kliknal "unsubscribe" w stopce)
aws sns list-subscriptions-by-topic   --topic-arn arn:aws:sns:us-east-1:195275647734:wolffire-alerts

# Odtworzenie skasowanej subskrypcji (wymaga poswiadczen admina AWS,
# a po apply - PONOWNEGO potwierdzenia linkiem z maila)
terraform -chdir=terraform/bootstrap apply   -replace=aws_sns_topic_subscription.alerts_email

# Testowy alert przez pelny potok (trafi na Chat i e-mail po ~30 s group_wait)
ssh wf-monitoring-1 'sudo docker exec alertmanager amtool alert add   --alertmanager.url=http://localhost:9093   alertname=Test severity=warning instance=test   --annotation=summary="Test kanalow alertowania"'

# Czy wiadomosci realnie wychodza (metryki tematu; wymaga poswiadczen AWS)
aws cloudwatch get-metric-statistics --namespace AWS/SNS   --metric-name NumberOfNotificationsDelivered   --dimensions Name=TopicName,Value=wolffire-alerts   --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)"   --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)"   --period 300 --statistics Sum
```

Uwaga: kazdy mail SNS ma w stopce link "unsubscribe" - klikniecie
natychmiast wylacza kanal (status Deleted) i wymaga procedury powyzej.

---

## 8. Terraform

Pełny zestaw (state, import, `-replace`/`-target`, output sensitive) jest w
[`docs/komendy/terraform.md`](komendy/terraform.md).

```bash
make tf-plan                                         # podglad zmian (otwiera tunel do API Proxmoxa)
make tf-apply                                        # apply
make validate

# Recznie, gdy potrzeba czegos spoza Makefile
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -lock=false'
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list'
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state show module.wolffire_prod.module.k3s-server-1.proxmox_virtual_environment_vm.this'
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform output'
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform output -raw proxmox_initial_password'
```

**Test idempotentności** - po `apply` na zamkniętej gałęzi musi zwrócić
`No changes`:

```bash
make tf-plan
```

Import zasobu, który powstał poza stanem:

```bash
sops exec-env secrets.sops.yaml \
  'terraform -chdir=terraform import module.proxmox_bootstrap.proxmox_virtual_environment_firewall_ipset.admins cluster/admins'
```

---

## 9. Ansible

Pełny zestaw (wektory debugowania, `-vvv`, `ANSIBLE_STDOUT_CALLBACK`) jest w
[`docs/komendy/ansible.md`](komendy/ansible.md).

```bash
cd ansible

ansible all -m ping                               # czy wszystko odpowiada
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-hosts
ansible-inventory --graph                         # struktura grup

# Uruchomienia wybiorcze
ansible-playbook playbook.yml --limit monitoring-1
ansible-playbook playbook.yml --tags docker
ansible-playbook playbook.yml --check --diff      # na sucho, z podgladem zmian

# Doraznie
ansible monitoring-1 -m shell -a 'docker ps'
ansible all -m setup -a 'filter=ansible_memtotal_mb'
```

**Pełny playbook i `--check` wymagają `sops exec-env`** - rola `cloudflared`
czyta token tunelu z outputu Terraforma w S3, więc bez poświadczeń AWS w
środowisku pada na `No valid credential sources found`, zanim dojdzie do
reszty ról:

```bash
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml --check --diff'
```

Przez `make` (z odszyfrowanymi sekretami):

```bash
make ansible-apply                                    # caly playbook
make bootstrap-host                                         # bootstrap hypervisora
```

---

## 10. Sekrety (SOPS)

Pełny zestaw (`--set`, `--extract`, rotacja klucza, dodanie odbiorcy) jest w
[`docs/komendy/sops.md`](komendy/sops.md).

```bash
make secrets                                      # edycja w edytorze

sops --decrypt secrets.sops.yaml                  # podglad
sops --decrypt ansible/group_vars/all/secrets.sops.yml

# Pojedyncza wartosc, bez otwierania edytora
sops --set '["CLOUDFLARE_API_TOKEN"] "nowy-token"' secrets.sops.yaml

# Uruchomienie czegokolwiek z sekretami w srodowisku
sops exec-env secrets.sops.yaml 'env | grep -c TOKEN'
```

Klucz age: `~/.config/sops/age/keys.txt` (na macOS dowiązany też do
`~/Library/Application Support/sops/age/`). **Bez niego nic nie ruszy.**

---

## 11. Kopie zapasowe i snapshoty

Snapshot wszystkich maszyn - **zrób to przed obroną**:

```bash
# Najkrócej - identyfikatory maszyn pobierane na żywo z qm list:
make snapshot NAME=przed-obrona     # migawka wszystkich maszyn
make snapshot-list                  # co mamy
make snapshot-rollback VM=130 NAME=przed-obrona   # powrót JEDNEJ maszyny (+start)

# To samo surowymi komendami:
ssh wf-proxmox-1 'for id in $(sudo qm list | awk "NR>1 {print \$1}"); do \
  sudo qm snapshot $id przed-obrona --description "stan sprzed demonstracji"; done'

ssh wf-proxmox-1 'sudo qm listsnapshot 130'
ssh wf-proxmox-1 'sudo qm rollback 130 przed-obrona'
```

Przeniesienie danych aplikacji dev -> prod (zrzut bazy, czyszczenie kolejek,
restart Horizona, weryfikacja) robi jeden skrypt:

```bash
./scripts/sync-dev-db-to-prod.sh
```

Kopie zapasowe robi zadanie Jenkinsa `infra-backup` (harmonogram `H 2 * * *`,
`pg_dump` + `restic` do S3). Restic ma **własny** komplet poświadczeń AWS,
osobny od tych, których używa Terraform do stanu - domyślny `aws s3 ls
s3://wolffire-backups/` przez `secrets.sops.yaml` kończy się `AccessDenied`,
bo klucz stanu Terraforma nie ma prawa czytać tego bucketa (celowe rozdzielenie
uprawnień, `terraform/bootstrap/iam.tf`):

```bash
sops exec-env secrets.sops.yaml \
  'AWS_ACCESS_KEY_ID=$BACKUP_AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$BACKUP_AWS_SECRET_ACCESS_KEY \
   aws s3 ls s3://wolffire-backups/ --region eu-north-1'
```

---

## 12. Typowe usterki

| Objaw | Prawdopodobna przyczyna | Sprawdź |
|---|---|---|
| `ssh` timeout do maszyny | firewall hypervisora albo UFW | `ssh wf-proxmox-1 'sudo pve-firewall compile \| grep <ip>'` |
| `ssh` connection refused | sshd nie nasłuchuje na tym porcie | `qm guest exec <id> -- /usr/bin/ss -tln` |
| 502 na panelu | usługa nie działa | `docker compose ps` na maszynie docelowej |
| 1033 na panelu | tunel padł | `ssh wf-<maszyna-usługi> 'systemctl status cloudflared'` - **nie** na bastionie, on go nie uruchamia |
| `curl: (7) Connection refused` na `localhost:<port>` z maszyny usługi | port opublikowany na adresie prywatnym, nie na `localhost` | użyj adresu prywatnego maszyny (np. `10.0.120.20:9090`) |
| `permission denied` przy `cd /opt/wolffire` | katalog `0750 root:root` | `sudo bash -c 'cd /opt/wolffire && ...'` |
| Cel w Prometheusie `down` | UFW blokuje port eksportera | `sudo ufw status` na maszynie docelowej |
| Maszyny bez internetu | UFW na hypervisorze blokuje FORWARD | `ssh wf-proxmox-1 'sudo ufw status'` -> ma być `inactive` |
| `terraform plan` zawsze pokazuje zmianę | rozjazd normalizacji wartości | porównaj `state show` z konfiguracją |
| Ansible nie widzi sekretów | brak klucza age | `echo $SOPS_AGE_KEY_FILE` |
| `AccessDenied` przy `aws s3 ls s3://wolffire-backups/` | użyty klucz stanu Terraforma zamiast klucza backupowego | podstaw `BACKUP_AWS_ACCESS_KEY_ID`/`BACKUP_AWS_SECRET_ACCESS_KEY` (§11) |

---

## 13. Scenariusz obrony - co pokazać na każde kryterium

Demonstracja trwa 10-12 minut, więc kolejność ma znaczenie: najpierw rzeczy
o największej wadze, potem reszta. Kolumna „dowód" to konkretny ekran lub
wyjście komendy, które zamyka temat bez tłumaczenia.

### Obowiązkowe - 40 wag

| Kryterium | W | Dowód |
|---|---|---|
| **GIT** | 3 | `git log --oneline --graph \| head -30` - Conventional Commits, przyrostowa historia |
| **GitHub** | 3 | Dwa repozytoria w przeglądarce: infrastruktura + fork aplikacji |
| **Terraform** | 6 | `terraform state list \| wc -l` (125 zasobów), potem `modules/base/proxmox/vm` i 8 wywołań w `services/` - **jeden moduł, osiem maszyn** |
| **Maszyny wirtualne** | 4 | `sudo qm list` (8 działających) + `sudo pve-firewall compile \| grep DROP` - polityka domyślna |
| **Ubuntu - firewall** | 3 | `ssh wf-monitoring-1 'sudo ufw status verbose'` - reguły ze źródłami, nie „allow any" |
| **Docker** | 6 | Na `wolffire-dev-app-1`: `docker ps`, `docker network ls`, `docker volume ls`, `sudo bash -c 'cd /opt/wolffire && docker compose ps'` - cztery podpunkty kryterium na czterech ekranach |
| **Docker Hub / rejestr** | 1 | Strona pakietu GHCR z tagami `sha` i `latest` |
| **CI** | 6 | Zakładka Actions: przebieg z podziałem na kroki (lint -> testy -> build -> push), wyzwalacz `push` |
| **CD** | 6 | Ten sam przebieg: job wdrożeniowy, wynik na maszynie, powiadomienie na kanale |
| **Dokumentacja** | 2 | README z diagramem, ARCHITECTURE, PLAN, ten runbook, `docs/komendy/` |

### Opcjonalne - 40 wag

| Kryterium | W | Dowód |
|---|---|---|
| **Kubernetes** | 6 | `k get nodes` (3 węzły Ready) -> `k get pods -n wolffire -o wide` -> `k drain k3s-agent-1` -> pody wstają na drugim. **To jest najmocniejszy pojedynczy pokaz w całej obronie** |
| **Ansible** | 6 | `sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml --check --diff'` na gotowej infrastrukturze -> `changed=0 failed=0`. Potem `ls roles/` (12 ról) |
| **Prometheus** | 6 | `prometheus.wolffire.dev/targets` - 19/19 celów `UP`, wyliczone z inventory |
| **Loki** | 5 | Grafana -> Explore -> zapytanie LogQL po logach aplikacji (`{job="docker", container="wolffire-php"}`) |
| **Domena i SSL** | 4 | Kłódka w przeglądarce + `curl -I https://grafana.wolffire.dev` -> 302 na Access |
| **Grafana** | 4 | Dashboard z metrykami węzłów i kontenerów (5 dashboardów prowizjonowanych) |
| **Runnery** | 3 | Ustawienia repo -> runner self-hosted `Idle`, plus agenty Jenkinsa jako efemeryczne kontenery |
| **Alertmanager** | 2 | `alerts.wolffire.dev` + 15 reguł w `roles/monitoring/templates/alerts.yml.j2` (4 grupy) |
| **Testy** | 2 | Krok Pest w logu przebiegu CI |
| **Stan w S3** | 1 | `terraform output` -> backend `s3` w `terraform/providers.tf`, `use_lockfile = true` |
| **Jenkins CasC** | 1 | `jenkins.yaml.j2` skonfigurowany wyłącznie z pliku - pokazać YAML obok działającego `jenkins.wolffire.dev` |

### Pokaz przepływu od commita do wdrożenia

Rdzeń demonstracji, około 4 minuty:

```bash
# 1. Zmiana w aplikacji (w repo WF-ChartApp-diploma, gałąź develop)
git commit -am "demo: zmiana widoczna na stronie" && git push origin develop

# 2. Actions - przebieg na zywo, podzial na kroki

# 3. Rejestr - nowy tag obrazu w GHCR

# 4. Wdrozenie
ssh wf-wolffire-dev-app-1 'sudo bash -c "cd /opt/wolffire && docker compose ps"'

# 5. Aplikacja
open https://dev.wolffire.dev

# 6. Powiadomienie na kanale
```

### Demonstracje na życzenie komisji - przećwiczone scenariusze

Trzy pokazy, o które komisja prosi najczęściej. Każdy przećwiczony w całości
na tej infrastrukturze; czasy realne.

#### A. Kubernetes przekłada ruch (drain węzła, ~3 minuty)

Przygotuj TRZY terminale, zanim zaczniesz mówić:

```bash
# Terminal A - podgląd podów na żywo (zostaje włączony przez cały pokaz)
ssh wf-k3s-server-1
sudo k3s kubectl get pods -n wolffire -o wide -w

# Terminal B - dowód ciągłości ruchu (sznurek dwusetek to sedno pokazu)
while true; do curl -s -o /dev/null -w "%{http_code} " https://wolffire.dev; sleep 1; done

# Terminal C - sterowanie
ssh wf-k3s-server-1
sudo k3s kubectl get nodes -o wide          # stan wyjściowy: 3 węzły Ready
sudo k3s kubectl drain k3s-agent-1 --ignore-daemonsets --delete-emptydir-data
```

Co komentować w trakcie: w terminalu A pody z `k3s-agent-1` przechodzą w
`Terminating`, nowe wstają na `k3s-agent-2`; w terminalu B kody 200 lecą
bez przerwy, bo nginx ma dwie repliki na różnych węzłach. Węzeł w
`get nodes` pokazuje `Ready,SchedulingDisabled`.

Po pokazie KONIECZNIE przywróć węzeł do harmonogramowania:

```bash
sudo k3s kubectl uncordon k3s-agent-1
```

Wariant krótszy (gdy mało czasu) - samoleczenie Deploymentu:

```bash
sudo k3s kubectl delete pod -n wolffire -l app.kubernetes.io/component=php --wait=false
sudo k3s kubectl get pods -n wolffire      # nowy pod wstaje w kilka sekund
```

#### B. Ansible: samonaprawa i idempotentność (~2 minuty)

Najkrótszy dowód, że konfiguracja to kod, a nie stan ręcznie wyklikany:

```bash
# 1. Kontrolowane psucie: kasujemy konfigurację alertów na maszynie monitoringu
ssh wf-monitoring-1 'sudo rm /opt/monitoring/prometheus/alerts.yml'

# 2. Playbook wykrywa brak i odtwarza plik (widać changed + przeładowanie)
cd ansible
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --tags monitoring'

# 3. Drugi przebieg - stan docelowy osiągnięty, nic do roboty
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --tags monitoring'
# PLAY RECAP: changed=0 failed=0
```

Zasady poprawnego uruchamiania Ansible w tym repo (pełny opis:
[`docs/komendy/ansible.md`](komendy/ansible.md)):

- zawsze z katalogu `ansible/` (tam mieszka `ansible.cfg` i względne ścieżki kluczy),
- zawsze przez `sops exec-env` - bez sekretów rola Jenkinsa celowo zatrzymuje
  przebieg assertem, zamiast wdrożyć pustą konfigurację,
- `--limit` przyjmuje nazwy hostów z inventory (`monitoring-1`), nie aliasy
  SSH (`wf-monitoring-1`),
- albo po prostu: `make ansible-apply` (całość) / `make ansible-check` (na sucho, z diffem).

#### C. Make jako pulpit operatora (~1 minuta, dobre otwarcie)

```bash
make help       # lista wszystkich operacji z opisami
make status     # zdrowie całości: węzły, pody, kontenery dev, kody HTTP
make tf-plan       # kod == rzeczywistość: No changes (tunel do API wstaje sam)
make test-infra # 34 testy dymne, wyłącznie odczyt
```

`make status` na początku prezentacji ustawia kontekst w 15 sekund: komisja
widzi klaster, kontenery i działające aplikacje, zanim padnie pierwsze
pytanie. Reszta pokazu to schodzenie w głąb od tego obrazka.

### Przygotowanie dzień wcześniej

- [ ] `make snapshot NAME=przed-obrona` (§11) - powrót w kilkanaście sekund, gdyby demo padło
- [ ] `make tf-plan` -> `No changes` (dowód idempotentności bez czekania na `apply`)
- [ ] Terminal zalogowany na `k3s-server-1` w osobnej karcie
- [ ] Sesja Cloudflare Access odświeżona (ważna 6 h)
- [ ] Nagranie pełnego przebiegu pipeline'u jako materiał zapasowy
- [ ] Karty przeglądarki otwarte: Grafana, Prometheus, Actions, oba repozytoria
- [ ] Pokazy A-C przećwiczone raz w całości (z zegarkiem)
- [ ] `ssh -fN wf-k3s-server-1 wf-monitoring-1 wf-wolffire-dev-app-1` - multipleksowanie
      sprawia, że każde kolejne `ssh` przy komisji wchodzi natychmiast
- [ ] Odrodzone pliki `CLAUDE.md` skasowane, jeśli pokazujesz katalog na żywo:
      `find . -iname "claude*.md" -not -path "./.git/*" -delete`

### Prawdopodobne pytania i gdzie jest odpowiedź

| Pytanie | Sekcja |
|---|---|
| Jak wdrażacie się od zera? | README -> `make bootstrap-host`, `make tf-apply`, `make ansible-apply` |
| Gdzie trzymacie sekrety? | ARCHITECTURE §4 - SOPS, i dlaczego nie Vault; [`docs/komendy/sops.md`](komendy/sops.md) |
| Dlaczego nie chmura? | ARCHITECTURE §1 |
| Jak zabezpieczyliście dostęp? | ARCHITECTURE §2 i §3 - trzy warstwy, cztery segmenty |
| Co, jeśli padnie tunel? | Cztery niezależne drogi wejścia - RUNBOOK §1 |
| Czy to jest idempotentne? | `make tf-plan` na żywo -> `No changes` |
| Dlaczego baza poza klastrem? | ARCHITECTURE §7 - `local-path` przy jednym hoście |
