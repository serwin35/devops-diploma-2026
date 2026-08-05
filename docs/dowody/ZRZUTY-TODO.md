# Zrzuty ekranu do zrobienia

Lista wszystkich zrzutów, na które pliki w `docs/dowody/` czekają. Zapisuj do
`docs/zrzuty/<nazwa>.png` - nazwy poniżej są dokładnie takie, jak w
odnośnikach `![...]` w plikach dowodowych.

Kolejność odpowiada w przybliżeniu wadze kryterium (od najważniejszych).

## Terraform (waga 6)

- **terraform-plan.png** - `sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -no-color'`
  w terminalu. Ma być widoczne: `Plan: 5 to add, 0 to change, 0 to destroy`
  oraz lista pięciu `cloudflare_zone_setting`. Zero zmian w maszynach/sieci.

## Maszyny wirtualne (waga 4)

- **vm-qm-list.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - panel Proxmox VE (UI, `https://<adres-hosta>:8006` albo
  `sudo qm list` w terminalu przez SSH na `wf-proxmox-1`). Ma być widoczne
  8 maszyn `running`.

## Docker (waga 6)

- **docker-compose-ps.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - terminal, `ssh wf-wolffire-dev-app-1 'sudo docker compose -f /opt/wolffire/compose.yml ps'`.
  7 kontenerów, status `healthy`.
- **docker-network-volume.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - terminal, `docker network ls` + `docker volume ls`
  na tej samej maszynie. Widoczna sieć `wolffire_wolffire` i 3 nazwane wolumeny.

## CI (waga 6)

- **ci-run-detail.png** [✅ ZEBRANE] - GitHub, zakładka Actions repo `WF-ChartApp-diploma`,
  przebieg `CI` na `main` (run 30962155580 albo nowszy sukces). Rozwinięty
  krok testów z widocznym `814 passed`.

## CD (waga 6)

- **cd-build-workflow-jobs.png** [✅ ZEBRANE - zielony przebieg #3 na main: build -> deploy-prod -> notify; dodatkowo cd-build-deploy-dev.png (#6, develop -> deploy-dev)] - zakładka Actions, przebieg workflow `Build`.
  Widoczne drzewo jobów: budowa obrazów -> deploy-dev/deploy-prod -> notify.
  Najlepiej użyć **kolejnego, udanego** przebiegu po naprawieniu uprawnień
  `GITHUB_TOKEN` (zob. `cd.md`) - jeśli naprawa nastąpi przed obroną, podmień
  ten zrzut na zielony przebieg.
- **cd-google-chat-notification.png** [✅ ZEBRANE - historia PORAZKA->SUKCES (main i develop) w pokoju Alerty] - kanał Google Chat z wiadomością od
  workflow (widoczny branch, commit, status `build`/`deploy-dev`/`deploy-prod`).

## Ubuntu - firewall (waga 3)

- **firewall-ufw-dev.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - terminal, `ssh wf-wolffire-dev-app-1 'sudo ufw status verbose'`.
  Widoczne reguły ze źródłowymi adresami IP, nie `Anywhere`.

## GIT / GitHub (waga 3 + 3)

- **git-app-commit-history.png** [✅ ZEBRANE] - GitHub, `WF-ChartApp-diploma` -> zakładka
  commitów na `main`, widoczna liczba commitów (308) i kilka wiadomości w
  stylu Conventional Commits.
- **git-infra-log.png** [✅ ZEBRANE - historia po scaleniu PR nr 1: 15 commitów
  develop -> merge do main]

## Dokumentacja (waga 2)

Brak zrzutu - kryterium pokryte samą treścią plików `.md` w repozytorium
(zob. `dokumentacja.md`).

## Terraform state w S3 (waga 1)

- **state-s3-bucket-console.png** [✅ ZEBRANE (+ state-s3-encryption.png)] - konsola AWS S3, bucket `terraform-states-wf`,
  z widoczną zakładką „Properties” pokazującą `Versioning: Enabled` i
  `Default encryption: Enabled (SSE-S3)`.

## Domena z SSL (waga 4)

- **domena-ssl-certificate.png** - przeglądarka, `https://grafana.wolffire.dev`,
  kłódka -> szczegóły certyfikatu (wystawca Google Trust Services, ważność).
- **domena-ssl-access-login.png** - ekran logowania Cloudflare Access po
  wejściu na dowolny panel administracyjny (np. `grafana.wolffire.dev`).

## Kubernetes (waga 6)

- **kubernetes-nodes.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - terminal na `wf-k3s-server-1`,
  `sudo k3s kubectl get nodes -o wide`. 3 węzły `Ready`.
- **kubernetes-pods-wolffire.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - `sudo k3s kubectl get pods -n wolffire -o wide`,
  pody rozłożone na różnych węzłach (kolumna `NODE`).
- **kubernetes-drain-demo.png** - demonstracja na żywo: `k drain k3s-agent-1
  --ignore-daemonsets --delete-emptydir-data`, potem `k get pods -n wolffire
  -o wide -w` pokazujący przełożenie podów na `k3s-agent-2`. Najmocniejszy
  pojedynczy zrzut w całej obronie (`docs/RUNBOOK.md §13`).

## Agenty Jenkins / inne runnery (waga 3)

- **jenkins-agenty-cloud-config.png** [✅ ZEBRANE (obraz wolffire/jenkins-agent, cap 2)] - Jenkins UI -> Manage Jenkins -> Clouds
  -> `docker`, widoczna konfiguracja chmury agentów (obraz, `containerCap`,
  `PULL_NEVER`).
- **jenkins-agenty-build-log.png** [✅ ZEBRANE (#6: restic snapshot 5e49a82b + Finished: SUCCESS)] - log przebiegu `infra-backup` #4 (konsola
  builda w UI), widoczny `restic backup` i `Finished: SUCCESS`.

## Jenkins CasC (waga 1)

- **jcasc-config-page.png** [✅ ZEBRANE (/var/jenkins_casc/jenkins.yaml)] - Jenkins UI -> Manage Jenkins -> Configuration as
  Code, strona pokazująca źródło `/var/jenkins_casc/jenkins.yaml`.
- **jcasc-job-history.png** [✅ ZEBRANE (Stage View, 4 zielone + 1 czerwony)] - widok zadania `infra-backup` w UI: harmonogram
  (`H 2 * * *`) i historia 4 przebiegów (2 czerwone, 2 zielone).

## Ansible (waga 6)

- **ansible-check-diff.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - terminal, pełny `PLAY RECAP` z
  `ansible-playbook playbook.yml --check --diff` na 9 hostach.

## Prometheus (waga 6)

- **prometheus-targets.png** [✅ ZEBRANE (+ prometheus-targets-2.png)] - `https://prometheus.wolffire.dev/targets`,
  wszystkie cele zielone/`UP` (19 pozycji).
- **prometheus-alerts.png** [✅ ZEBRANE (+ prometheus-alerts-firing.png z Watchdogiem)] - `https://prometheus.wolffire.dev/alerts`, lista
  15 reguł, `Watchdog` w stanie `firing`.

## Grafana (waga 4)

- **grafana-dashboard.png** [✅ ZEBRANE] - dashboard z metrykami węzłów/kontenerów, najlepiej
  taki, gdzie widać dane zarówno ze środowiska Compose, jak i k3s.
- **grafana-login.png** [✅ ZEBRANE (zalogowany admin)] - ekran logowania Grafany (albo już zalogowany profil
  admina - pokazuje, że hasło z SOPS działa).

## Alertmanager (waga 2)

- **alertmanager-ui.png** [✅ ZEBRANE] - `https://alerts.wolffire.dev`, lista reguł/alertów.
- **alertmanager-gchat-notification.png** [✅ ZEBRANE (alert AKTYWNY + ROZWIAZANY z calert)] - przykładowa wiadomość na Google
  Chat wysłana przez `calert` (może być testowa/historyczna).

## Loki (waga 5)

- **loki-explore-query.png** [✅ ZEBRANE] - Grafana -> Explore -> źródło Loki, zapytanie
  LogQL (np. `{host=~".+"}`) z logami z kilku hostów w wynikach.

## Testy automatyczne (waga 2)

- **testy-pest-ci-log.png** [✅ ZEBRANE] - GitHub Actions, log kroku testów w CI aplikacji,
  widoczne `Tests: 814 passed (2303 assertions)`.
- **testy-smoke-test-summary.png** [✅ ZEBRANE - render prawdziwego wyjścia komendy] - terminal, pełne podsumowanie
  `make test-infra` (`OK: 34 BLAD: 0 POMINIETE: 1`).

---

**Uwaga ogólna**: część zrzutów (Cloudflare Access, GHCR, Google Chat) wymaga
zalogowania się w przeglądarce na konto właściciela projektu - nie da się
ich zebrać automatycznie przez CLI. Pozostałe (terminal/SSH/`kubectl`) można
odtworzyć jedną komendą z bloków „Dowody zebrane na żywo” w każdym pliku.

---

## Zebrane automatycznie 2026-08-05 (sesja przeglądarkowa)

Pliki w `docs/zrzuty/`. Bonusowe zrzuty Cloudflare (poza pierwotną listą):

- **cloudflare-dns-records.png** - 12 rekordów DNS wolffire.dev (7 × Tunnel, Proxied)
- **cloudflare-tunnels.png** - Tunnels & Mesh: wf-cicd/dev/monitoring/prod/proxmox, wszystkie `Healthy`
- **cloudflare-access-apps.png** - 5 aplikacji Access (jenkins/grafana/proxmox/prometheus/alerts)
- **cloudflare-ssl-strict.png** - tryb Full (strict), "Mode last changed 27 minutes ago" (apply Terraforma)
- **cloudflare-hsts-tls12.png** - HSTS On (12 mies., subdomeny, preload) + Minimum TLS 1.2
- **cloudflare-edge-cert.png** - certyfikat Universal aktywny do 2026-11-01

Brakujące (wymagają Twojego działania):
4. domena-ssl-access-login.png - okno incognito -> grafana.wolffire.dev
5. domena-ssl-certificate.png - kłódka w pasku adresu (dialog przeglądarki, ręcznie)
