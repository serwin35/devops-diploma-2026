# Plan realizacji i status

Uzasadnienia decyzji: [ARCHITECTURE.md](ARCHITECTURE.md). Opis uruchomienia:
[README](../README.md). Dowody zebrane na żywo pod każde kryterium:
[docs/dowody/](dowody/) (indeks: [dowody/README.md](dowody/README.md)).

> Ten dokument został zaktualizowany 2026-08-05 na podstawie weryfikacji na
> żywej infrastrukturze (SSH, `kubectl`, `terraform plan`, `gh run list`,
> `curl`, AWS CLI), nie na podstawie deklaracji z wcześniejszych faz. Status
> jest celowo surowy - brak jest tam, gdzie dowód czegoś nie potwierdza, a
> nie tam, gdzie „jeszcze nie sprawdzono”.

## Stos technologiczny

| Obszar | Wybór |
|---|---|
| Wirtualizacja | Proxmox VE 9 na serwerze dedykowanym OVH (Xeon E-2386G, 32 GB RAM, 2× NVMe w ZFS mirror) |
| IaC | Terraform 1.14 (`bpg/proxmox`, `cloudflare`, `aws`) |
| Konfiguracja | Ansible (17 ról) |
| Orkiestracja | k3s (1 control-plane + 2 agentów) - wyłącznie dla aplikacji produkcyjnej |
| Konteneryzacja | Docker + Compose (dev, Jenkins, monitoring) |
| CI/CD | GitHub Actions, runner **hostowany przez GitHuba** - lint, testy, budowa i publikacja obrazu, wdrożenie na dev/prod, powiadomienia. Do prywatnych maszyn dociera przez SSH proxy'owane bastionem |
| Operacje na infrastrukturze | Jenkins (JCasC, agenty Docker) - kopie zapasowe bazy do S3 przez restic, zadanie cykliczne |
| Rejestr | **GHCR** (GitHub Container Registry), nie Docker Hub |
| Sekrety | SOPS + age |
| DNS / SSL / dostęp | Cloudflare: DNS, Tunnel (per maszyna usługowa), Zero Trust Access na panelach administracyjnych |
| Punkt wejścia | Bastion z publicznym IPv4/IPv6, wyłącznie port SSH 22022 otwarty; panele przez tunele Cloudflare terminowane lokalnie na maszynach usługowych |
| Monitoring | Prometheus, Grafana, Alertmanager, Loki + Grafana Alloy (agent logów) - Docker Compose poza klastrem |
| Chmura | AWS S3 - stan Terraforma (`terraform-states-wf`) i kopie zapasowe bazy (`wolffire-backups`), obie z rozdzielonymi tożsamościami IAM |
| Aplikacja | Adaptacja WolfFire (repo `WF-ChartApp-diploma`) - Laravel 13, PHP 8.4, Postgres 18, Redis 7, Horizon |

Uwaga: rejestr i model runnera CI zmieniły się w trakcie realizacji względem
wcześniejszej wersji tej tabeli (Docker Hub -> GHCR, self-hosted runner ->
runner GitHuba + SSH do bastionu). `docs/ARCHITECTURE.md` w kilku miejscach
wciąż opisuje wcześniejszy wariant - rozjazd odnotowany w
[dowody/dokumentacja.md](dowody/dokumentacja.md).

---

## Fazy

### Faza 1 - Fundament ✅

- [x] Struktura repozytorium: `terraform/`, `ansible/`, `keys/`, `docs/`, `helm/`, `scripts/`
- [x] SOPS + age, jeden klucz dla Terraforma i Ansible
- [x] Rozdzielone tożsamości SSH (`terraform`, `ansible`, konta imienne)
- [x] `Makefile` - `host`, `infra`, `configure`, `secrets`, `test-infra`

### Faza 2 - Bootstrap hosta ✅

- [x] `ansible/bootstrap-host.yml` - idempotentny, uruchamiany raz
- [x] Ograniczenie ARC ZFS-a, konta maszynowe, utwardzenie SSH (port 22022)
- [x] Użytkownik `terraform@pve`, token API

### Faza 3 - Terraform: warstwa hypervisora ✅

- [x] Moduł `proxmox/vm` - jedna maszyna, wywoływany 7× (8 maszyn, jedno
      wywołanie z `for_each` na dwóch agentach k3s)
- [x] Moduł `proxmox/bootstrap` - SDN Simple, cloud-init, grupy bezpieczeństwa,
      pule zasobów
- [x] Moduły usługowe: `bastion`, `cicd`, `observability`, `wolffire/dev`, `wolffire/prod`
- [x] Cztery segmenty SDN; SSH dopuszczone wyłącznie z bastionu
- [x] Stan zweryfikowany na żywo: `terraform state list` -> **125 zasobów**
      (root główny, bez licząc `terraform/bootstrap`)

### Faza 4 - AWS i stan zdalny ✅

- [x] Root `terraform/bootstrap/` ze stanem lokalnym: buckety S3 + IAM
- [x] Bucket `terraform-states-wf` - wersjonowanie, szyfrowanie SSE-S3, `use_lockfile`
- [x] Bucket `wolffire-backups` - cykl życia do Glacier IR, **bez uprawnienia
      usuwania** dla tożsamości Jenkinsa (zweryfikowane na żywo: `s3 rm` kończy
      się `AccessDenied` z jawnym `Deny`)
- [x] Rozdzielone tożsamości IAM: `wolffire-tf-state`, `wolffire-jenkins-backup`
      (zweryfikowane wzajemne odmowy dostępu między nimi)
- [x] Backend przełączony na S3 (`terraform/providers.tf`, `backend "s3"`)

Dowody: [dowody/state-s3.md](dowody/state-s3.md), [dowody/terraform.md](dowody/terraform.md).

### Faza 5 - Cloudflare 🔶

- [x] Strefa `wolffire.dev` w Terraformie, tunele per maszyna usługowa
      (hypervisor, `cicd-1`, `monitoring-1`, `wolffire-dev-app-1`, `k3s-server-1`)
- [x] Zero Trust Access na panelach: `proxmox.`, `jenkins.`, `grafana.`,
      `prometheus.`, `alerts.` (zweryfikowane: wszystkie zwracają 302 na
      logowanie Cloudflare Access)
- [x] Publicznie bez Access: `dev.wolffire.dev` (zweryfikowane: HTTP 200,
      sesja aplikacji)
- [ ] 5 ustawień strefy TLS (`always_use_https`, `min_tls_version`, `tls_1_3`,
      nagłówek bezpieczeństwa, SSL) zdefiniowanych w kodzie, ale jeszcze
      niezaaplikowanych - `terraform plan` pokazuje je jako „to add”
- [ ] Aplikacja SSH w Access (`ssh.wolffire.dev`) - bastion obecnie przyjmuje
      SSH bezpośrednio na porcie 22022, nie przez Access (zmiana architektury
      względem wcześniejszego planu, patrz `README.md`)

Dowody: [dowody/domena-ssl.md](dowody/domena-ssl.md).

### Faza 6 - Ansible: konfiguracja maszyn ✅

- [x] `hostname`, `login`, `security` (UFW + fail2ban + unattended-upgrades), `docker`
- [x] `ipv6_router`, `routes`, `cloudflared` - zweryfikowane na żywo (`systemctl
      is-active cloudflared` -> `active` na 5 maszynach)
- [x] `k3s` - server + 2 agentów, klaster `Ready`, zweryfikowany na żywo
- [x] `postgres`, `redis` - zweryfikowane (`pg_isready`, `PING` -> `PONG`)
- [x] `jenkins` - JCasC, agenty jako kontenery Dockera, zadanie backupowe
      z historią sukcesów
- [x] `monitoring`, `alloy` - Compose z Prometheusem, Grafaną, Alertmanagerem,
      Loki; logi z 9 hostów
- [x] `observability` - eksportery zweryfikowane jako cele `up` w Prometheusie
- [x] `wolffire`, `wolffire_prod` - Compose dev + Helm na k3s, oba działające
- [ ] Osobna rola `backup` - kopia zapasowa jest zaimplementowana jako
      pipeline Jenkinsa (`backup-pipeline.groovy.j2`), nie jako rola Ansible;
      działa i jest zweryfikowana (restic snapshoty w S3), ale organizacyjnie
      inaczej niż pierwotnie planowano
- [ ] `github_runner` (self-hosted) - świadomie zarzucone na rzecz runnera
      hostowanego przez GitHuba + SSH do bastionu w kroku wdrożenia (patrz
      Faza 8)

Dowody: [dowody/ansible.md](dowody/ansible.md), [dowody/kubernetes.md](dowody/kubernetes.md),
[dowody/jenkins-agenty.md](dowody/jenkins-agenty.md), [dowody/jcasc.md](dowody/jcasc.md),
[dowody/prometheus.md](dowody/prometheus.md), [dowody/grafana.md](dowody/grafana.md),
[dowody/alertmanager.md](dowody/alertmanager.md), [dowody/loki.md](dowody/loki.md).

### Faza 7 - Aplikacja ✅ (z zastrzeżeniem)

- [x] Adaptacja WolfFire na konto osobiste (`WF-ChartApp-diploma`), 308
      commitów - **nie jest to techniczny fork GitHuba** (`fork: false` w
      API), tylko repozytorium założone z wypchniętą historią; patrz
      [dowody/git-github.md](dowody/git-github.md)
- [x] Wielostopniowy `Dockerfile` (`.docker/{php,nginx}.dockerfile`) - build
      composer/node, runtime bez roota, obrazy realnie zbudowane i uruchomione
- [x] `compose.yml` dla dev - własna sieć (`wolffire_wolffire`), 3 nazwane wolumeny
- [x] Chart Helma dla proda - Deployment, Service, Job migracji, Secret GHCR;
      **bez** Ingress (ruch idzie przez Traefik wbudowany w k3s) i **bez** HPA
- [ ] `FILESYSTEM_DISK=s3` - nie zweryfikowano w tej sesji (poza zakresem
      zebranych dowodów)
- [ ] Endpoint `/metrics` dla Prometheusa - aplikacja ma job `wolffire` w
      Prometheusie tylko dla środowiska dev, nie dla podów na k3s

Dowody: [dowody/docker.md](dowody/docker.md), [dowody/kubernetes.md](dowody/kubernetes.md),
[dowody/rejestr.md](dowody/rejestr.md).

### Faza 8 - CI/CD ✅ (z zastrzeżeniem)

- [x] GitHub Actions: Pint, Pest (814 testów, 2303 asercje), budowa obrazu,
      publikacja do **GHCR** (nie Docker Huba - zmiana świadoma)
- [x] GitHub Actions: wdrożenie na dev (`develop`, reload Compose) i prod
      (`main`, `helm upgrade` na k3s) przez SSH proxy'owane bastionem
- [x] Powiadomienia - Google Chat, zweryfikowane na żywo (wysłane nawet przy
      porażce builda)
- [x] Jenkins: `pg_dump` -> restic -> S3, zweryfikowane (4 przebiegi, 2 sukcesy,
      snapshoty w buckecie); **bez** `vzdump` maszyn przez API Proxmoxa -
      świadomie odrzucone (uzasadnienie w `ARCHITECTURE.md` i
      `backup-pipeline.groovy.j2`), bez testu odtworzenia
- [x] CD naprawione i zielone na obu gałęziach (2026-08-05): przyczyną braku
      dostępu był brak powiązania pakietów GHCR z repozytorium (Actions
      repository access), nie ustawienia tokenu. Do tego eksport cache GHA
      jest nie-fatalny (`ignore-error=true`). Szczegóły w
      [dowody/cd.md](dowody/cd.md).

Dowody: [dowody/ci.md](dowody/ci.md), [dowody/cd.md](dowody/cd.md), [dowody/testy.md](dowody/testy.md).

### Faza 9 - Dokumentacja i obrona 🔶

- [x] `README.md`, `docs/ARCHITECTURE.md`, `docs/PRZEWODNIK.md`,
      `docs/RUNBOOK.md`, `keys/README.md`, `docs/komendy/*.md`
- [x] `docs/dowody/` - dowody zebrane na żywo pod każde kryterium (ten katalog)
- [ ] Zrzuty ekranu - lista w [dowody/ZRZUTY-TODO.md](dowody/ZRZUTY-TODO.md)
      (30 pozycji, żadna jeszcze niezrobiona)
- [ ] Nagranie pełnego przebiegu pipeline'u jako materiał zapasowy na obronę
- [ ] Weryfikacja wdrożenia od zera na czystym stanie
- [ ] **Zacommitowanie i wypchnięcie pracy** - repozytorium infrastruktury ma
      w historii gita tylko 4 commity; cały pokazany wyżej dorobek leży
      niescommitowany w katalogu roboczym (patrz [dowody/git-github.md](dowody/git-github.md))

---

## Pokrycie kryteriów oceny

Legenda: ✅ dowody zebrane na żywo, kryterium pokryte · ⚠️ dowody zebrane,
ale z odnotowanym realnym brakiem (nie tylko brakującym zrzutem) · 🔶 częściowe.
Pełne dowody, komendy i pliki źródłowe: [docs/dowody/](dowody/).

### Obowiązkowe - 40 wag

| Kryterium | Waga | Gdzie realizowane | Status |
|---|---|---|---|
| GIT | 3 | Historia repo aplikacji (308 commitów); repo infrastruktury ma tylko 4 commity, reszta niescommitowana | ⚠️ |
| GitHub | 3 | Dwa repozytoria; „fork” aplikacji nietechniczny (nie przez przycisk Fork) | ⚠️ |
| Terraform | 6 | 125 zasobów w stanie, moduł `vm` reużywalny ×7 (8 maszyn) | ✅ |
| Maszyny wirtualne (VM) | 4 | Proxmox, 8 maszyn `running`, firewall `DROP`, bastion jedyny punkt wejścia | ✅ |
| Ubuntu - firewall | 3 | UFW aktywny na 8/8 maszynach, reguły źródłowe | ✅ |
| Docker | 6 | Compose na dev (7 kontenerów), monitoring (5), Jenkins; sieci i wolumeny nazwane | ✅ |
| Docker Hub (rejestr) | 1 | GHCR (`ghcr.io/serwin35/wf-chartapp-diploma`), 2 pakiety prywatne | ✅ |
| CI | 6 | GitHub Actions, 2 joby (Pest 814 testów, Pint 616 plików), wyzwalacz `push` | ✅ |
| CD | 6 | GitHub Actions, `build.yml`: GHCR -> deploy dev/prod -> notify; zielone przebiegi na main (prod) i develop (dev) | ✅ |
| Dokumentacja MarkDown | 2 | README, ARCHITECTURE, PRZEWODNIK, RUNBOOK, PLAN, `docs/dowody/`, `docs/komendy/` | ✅ |

### Opcjonalne - 40 wag

| Kryterium | Waga | Gdzie realizowane | Status |
|---|---|---|---|
| Stan Terraforma w S3 | 1 | Bucket `terraform-states-wf`, wersjonowanie + szyfrowanie + lock natywny | ✅ |
| Domena z poprawnym SSL | 4 | `wolffire.dev`, certyfikat ważny, panele za Access, dev publiczne | ✅ |
| Kubernetes | 6 | k3s 3 węzły, aplikacja na wszystkich, brak HPA/PVC (świadomie) | ✅ |
| Agenty Jenkins / inne runnery | 3 | Chmura Docker Jenkinsa, agenty efemeryczne, historia przebiegów | ✅ |
| Jenkins Configuration as Code | 1 | Cały kontroler z `jenkins.yaml.j2`, zadanie z Job DSL | ✅ |
| Ansible | 6 | 17 ról, `--check --diff` prawie zerowy dryf (3-4 „changed” per host, tryb suchy) | ✅ |
| Prometheus | 6 | 19 celów `up`, 15 reguł alertów (`Watchdog` firing) | ✅ |
| Grafana | 4 | Zdrowa, logowanie z SOPS, dashboardy Compose+k3s | ✅ |
| Alertmanager | 2 | `ready`, odbiorca `gchat` przez `calert` | ✅ |
| Loki | 5 | Logi z 9 hostów, zapytywalne LogQL | ✅ |
| Testy automatyczne | 2 | Pest 814/814, testy dymne infrastruktury 34/34 | ✅ |

**19 z 21 pozycji ma pełne, niebudzące zastrzeżeń pokrycie dowodowe. Dwie
(GIT, CD) mają dowody zebrane, ale z odnotowanym realnym brakiem do
naprawienia przed obroną** - szczegóły w [dowody/README.md](dowody/README.md#co-jeszcze-zrobić-przed-obroną).

---

## Otwarte kwestie

| Temat | Potrzebne |
|---|---|
| GIT | Zacommitować i wypchnąć cały niescommitowany dorobek (Terraform, Ansible, Helm, dokumentacja, skrypty) - patrz [dowody/git-github.md](dowody/git-github.md) |
| CD | Naprawić uprawnienia `GITHUB_TOKEN` w repo `WF-ChartApp-diploma` (Settings -> Actions -> Workflow permissions), żeby `build.yml` mógł pushować do GHCR z `main` - patrz [dowody/cd.md](dowody/cd.md) |
| Cloudflare | Zaaplikować 5 ustawień strefy TLS pokazanych jako „to add” w `terraform plan` |
| Dokumentacja | Ujednolicić `ARCHITECTURE.md` z bieżącym stanem (GHCR zamiast Docker Huba, model bastionu, model runnera CI) |
| Zrzuty ekranu | 30 pozycji w [dowody/ZRZUTY-TODO.md](dowody/ZRZUTY-TODO.md), żadna jeszcze niezrobiona |
| Obrona | Nagranie pełnego przebiegu pipeline'u jako materiał zapasowy; snapshoty maszyn przed demonstracją (`docs/RUNBOOK.md §11`) |
