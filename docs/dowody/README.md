# Dowody pod kryteria oceny - indeks

Dowody zebrane **na żywo** 2026-08-05 (SSH, `kubectl`, `terraform`, `gh`,
`curl`, AWS CLI z tożsamościami IAM projektu). Każdy plik: checklista
podpunktów, wklejone wyjścia komend, sekcja „Jak to jest zrobione” (ścieżki w
repo) i „Świadome decyzje/ograniczenia”. Miejsca na zrzuty ekranu są
oznaczone w treści; pełna lista do zrobienia: [ZRZUTY-TODO.md](ZRZUTY-TODO.md).

Status ✅ oznacza, że dowody na żywo są zebrane i kryterium jest pokryte
merytorycznie - zrzut ekranu jest uzupełnieniem wizualnym, nie warunkiem
tego statusu. ⚠️ oznacza kryterium z odnotowanym, realnym brakiem
(opisanym w danym pliku), nie tylko brakującym zrzutem.

## Obowiązkowe - 40 wag

| Kryterium | Waga | Plik | Status |
|---|---|---|---|
| Terraform | 6 | [terraform.md](terraform.md) | ✅ dowody zebrane |
| Docker | 6 | [docker.md](docker.md) | ✅ dowody zebrane |
| CI | 6 | [ci.md](ci.md) | ✅ dowody zebrane |
| CD | 6 | [cd.md](cd.md) | ✅ dowody zebrane - zielone przebiegi: main -> deploy-prod, develop -> deploy-dev (2026-08-05) |
| AWS EC2 / Virtual Machines | 4 | [vm.md](vm.md) | ✅ dowody zebrane |
| Ubuntu - firewall | 3 | [firewall.md](firewall.md) | ✅ dowody zebrane |
| GIT | 3 | [git-github.md](git-github.md) | ✅ dowody zebrane - 15 commitów scalonych do `main` przez PR nr 1 (2026-08-05) |
| GitHub | 3 | [git-github.md](git-github.md) | ⚠️ „fork” aplikacji nie jest technicznym forkiem GitHuba - patrz plik |
| Docker Hub (rejestr) | 1 | [rejestr.md](rejestr.md) | ✅ dowody zebrane (GHCR zamiast Docker Huba) |
| Dokumentacja MarkDown | 2 | [dokumentacja.md](dokumentacja.md) | ✅ dowody zebrane |

## Opcjonalne - 40 wag

| Kryterium | Waga | Plik | Status |
|---|---|---|---|
| Kubernetes | 6 | [kubernetes.md](kubernetes.md) | ✅ dowody zebrane |
| Ansible | 6 | [ansible.md](ansible.md) | ✅ dowody zebrane |
| Prometheus | 6 | [prometheus.md](prometheus.md) | ✅ dowody zebrane |
| Loki | 5 | [loki.md](loki.md) | ✅ dowody zebrane |
| Domena z poprawnym SSL | 4 | [domena-ssl.md](domena-ssl.md) | ✅ dowody zebrane |
| Grafana | 4 | [grafana.md](grafana.md) | ✅ dowody zebrane |
| Agenty Jenkins / inne runnery | 3 | [jenkins-agenty.md](jenkins-agenty.md) | ✅ dowody zebrane |
| Alert Manager | 2 | [alertmanager.md](alertmanager.md) | ✅ dowody zebrane |
| Unit testy / testy automatyczne | 2 | [testy.md](testy.md) | ✅ dowody zebrane |
| Terraform state w AWS S3 | 1 | [state-s3.md](state-s3.md) | ✅ dowody zebrane |
| Jenkins Configuration as Code | 1 | [jcasc.md](jcasc.md) | ✅ dowody zebrane |

## Co jeszcze zrobić przed obroną

1. **Zrzuty ekranu** - lista w [ZRZUTY-TODO.md](ZRZUTY-TODO.md); większość
   zebrana 2026-08-05 (28 plików w `docs/zrzuty/`), zostały pozycje
   terminalowe, mail alertu SNS i dwa zrzuty ręczne (ekran logowania
   Access w incognito, kłódka certyfikatu).
2. **Zrzut `git-infra-log.png`** - `git log --oneline --graph` po scaleniu
   PR nr 1 (historia jest już na `main`).

Rozwiązane od czasu pierwszego spisu: CD zielone na obu gałęziach
([cd.md](cd.md)), historia gita infrastruktury scalona do `main` (PR nr 1),
dokumentacja ujednolicona z faktycznym stanem (GHCR, tunele per maszyna,
kanał e-mail SNS), smoke test 34/34.

Related: [docs/PLAN.md](../PLAN.md) (status faz i pokrycia kryteriów),
[docs/RUNBOOK.md](../RUNBOOK.md) (scenariusz obrony krok po kroku).
