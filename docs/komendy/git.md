# Git - flow projektu

Dwa osobne repozytoria, dwa różne rytmy pracy:

| Repo | Zawiera | Gałęzie |
|---|---|---|
| `devops-diploma-2026` (to repo) | Infrastruktura jako kod: Terraform, Ansible, Helm | `main` - praca liniowa, bez `develop` |
| `WF-ChartApp-diploma` (fork aplikacji) | Kod Laravela | `develop` -> środowisko dev, `main` -> produkcja (k3s) |

Ten podział odpowiada za dwuznaczność, na którą łatwo trafić w dokumentacji:
"push na `develop`" w [RUNBOOK §13](../RUNBOOK.md) dotyczy repo aplikacji, nie
tego repozytorium infrastruktury.

---

## Commity - Conventional Commits

Historia tego repo:

```
feat(secrets): manage tokens with SOPS and age
chore: ignore terraform state, secrets and generated files
Add initial project documentation and .gitignore file
```

Format: `<typ>(<zakres opcjonalny>): <opis w trybie rozkazującym, po angielsku>`.

| Typ | Kiedy użyć | Przykład z tego repo |
|---|---|---|
| `feat` | Nowa funkcjonalność infrastruktury (nowy moduł, nowa rola) | `feat(secrets): manage tokens with SOPS and age` |
| `fix` | Naprawa błędu w istniejącym kodzie | `fix(cloudflared): read tunnel token per machine, not globally` |
| `chore` | Porządki bez zmiany zachowania (`.gitignore`, formatowanie) | `chore: ignore terraform state, secrets and generated files` |
| `docs` | Wyłącznie dokumentacja | `docs(runbook): update panel table to match Zero Trust setup` |
| `refactor` | Zmiana struktury kodu bez zmiany zachowania | `refactor(cloudflare): split zero_trust into policy submodule` |

Zakres (`(...)`) nazywa moduł/rolę, której dotyczy zmiana - `secrets`,
`cloudflared`, `k3s`, `monitoring`, `runbook`. Bez zakresu, gdy zmiana dotyka
całego repo (`chore: ...`).

## Codzienny przepływ

```bash
git status                              # co jest zmienione, zanim cokolwiek zrobisz
git diff                                # przegląd zmian niezastagowanych
git add ansible/roles/monitoring/       # dodawaj świadomie, po ścieżce, nie -A
git commit -m "feat(monitoring): add cadvisor job to prometheus scrape config"
git push origin main
```

**Nigdy `git add -A`/`git add .` bez przejrzenia `git status` najpierw** -
w tym repo łatwo o przypadkowe dodanie odszyfrowanego pliku sekretów albo
`.terraform/` (oba są w `.gitignore`, ale świeżo utworzony plik poza wzorcem
potrafi się prześlizgnąć).

## Co nigdy nie trafia do repo

Wymuszone przez `.gitignore`, ale warto pamiętać *dlaczego*, sprawdzając diff
przed commitem:

| Wzorzec | Powód |
|---|---|
| `*.tfstate*` | Stan trafia do S3 (backend), nie do gita - i bywa w nim `random_password` jawnym tekstem |
| `keys.txt`, `*.agekey` | Prywatny klucz age - bez niego nikt nie odszyfruje `*.sops.yaml` |
| `keys/*_ed25519` | Prywatne klucze SSH - do repo trafiają wyłącznie `*.pub` |
| `*.tfvars` (poza `.example`) | Zmienne wejściowe bywają środowiskowe/lokalne, sekrety i tak idą przez SOPS |
| `ansible/.vault_pass` | Repo używa SOPS, nie Ansible Vault - ten plik to relikt po ewentualnej migracji |

`*.sops.yaml`/`*.sops.yml` **są** commitowane celowo - to zaszyfrowane
wartości, bezpieczne do trzymania w historii gita.

## Przydatne przy przeglądzie historii

```bash
git log --oneline --graph                        # zwięzła historia z gałęziami
git log --oneline --graph -- terraform/           # historia jednego katalogu
git log -p --follow -- ansible/roles/cloudflared/tasks/main.yml   # historia jednego pliku przez zmiany nazwy
git show <sha>                                    # pełna treść jednego commita
git diff main~5..main                             # zakres zmian z ostatnich 5 commitów
```

## Częste problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `git status` pokazuje zaszyfrowany plik jako zmieniony bez realnej zmiany treści | SOPS re-szyfruje przy każdym zapisie (inny IV) - patrz [`sops.md`](sops.md) | Nieszkodliwe; commituj tylko gdy wartość faktycznie się zmieniła |
| Przypadkowe dodanie `.terraform/` do stage | Katalog powstaje lokalnie po `terraform init`, wzorzec w `.gitignore` go łapie - ale nie jeśli ktoś użył `git add -f` | `git rm -r --cached terraform/.terraform` |
| Konflikt w pliku `*.sops.yaml` przy merge | Dwie osoby zmieniły różne sekrety równolegle - merge tekstowy szyfrogramu nie ma sensu | Nie mergować ręcznie: jedna strona robi `sops <plik>` ponownie na już zmergowanej bazie i dogrywa swoją wartość |
