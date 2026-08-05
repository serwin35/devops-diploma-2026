Dokumentacja MarkDown - dowody
================================

- [X] Dokumentacja architektury i uruchomienia
- [X] Runbook operacyjny
- [X] Plan i status realizacji
- [X] Dokumentacja dowodowa pod kryteria (ten katalog)

## Dowody

Pliki obecne w repozytorium, wszystkie w Markdown:

```
$ find docs -maxdepth 1 -name "*.md" -o -maxdepth 1 -name "*.md" | sort
docs/ARCHITECTURE.md
docs/Kryteria oceny.md
docs/PLAN.md
docs/PRZEWODNIK.md
docs/RUNBOOK.md
docs/Wymagania Projektu Dyplomowego.md
docs/dowody/*.md            (ten katalog - 20 plików, jeden na kryterium)
docs/komendy/*.md           (7 plików - ściągi komend per temat)
README.md
keys/README.md
```

Rozmiar i struktura (nie pliki-atrapy):

```
$ wc -l README.md docs/ARCHITECTURE.md docs/RUNBOOK.md docs/PLAN.md docs/PRZEWODNIK.md
     214 README.md
     299 docs/ARCHITECTURE.md
     572 docs/RUNBOOK.md
     ~155 docs/PLAN.md
     ~200+ docs/PRZEWODNIK.md
```

## Jak to jest zrobione

| Plik | Rola |
|---|---|
| [README.md](../../README.md) | Start: diagram architektury (Mermaid), tabela maszyn, wdrożenie od zera trzema komendami |
| [docs/ARCHITECTURE.md](../ARCHITECTURE.md) | **Dlaczego** - uzasadnienia decyzji (własny Proxmox zamiast chmury, sieć bez publicznych adresów, SOPS zamiast Vaulta, podział Terraform/Ansible, podział CI/CD…) |
| [docs/PRZEWODNIK.md](../PRZEWODNIK.md) | **Gdzie** - mapa katalogów repozytorium, co edytować w typowych scenariuszach |
| [docs/RUNBOOK.md](../RUNBOOK.md) | **Jak** - komendy operacyjne, diagnostyka awarii, scenariusz obrony z tabelą kryterium->dowód |
| [docs/PLAN.md](../PLAN.md) | Status realizacji per faza i per kryterium oceny |
| [docs/komendy/](../komendy/) | Ściągi komend per narzędzie (git, docker, kubernetes, terraform, ansible, monitoring, sops) |
| [docs/dowody/](.) | Ten katalog - dowody zebrane na żywo, jeden plik na kryterium oceny |
| [keys/README.md](../../keys/README.md) | Model tożsamości SSH |

## Świadome decyzje / ograniczenia

- **Diagram architektury jako Mermaid w README**, nie jako obrazek - renderuje
  się wprost na GitHub, więc nie wymaga osobnego eksportu i nie starzeje się
  jako martwy PNG.
- **Cztery poziomy dokumentacji** (README = co i jak uruchomić, ARCHITECTURE
  = dlaczego, PRZEWODNIK = gdzie co jest, RUNBOOK = jak diagnozować) zamiast
  jednego rozrośniętego pliku - każdy ma inny cel czytania.
- **Rozjazd między `ARCHITECTURE.md` a bieżącym stanem repo**: `README.md`
  był aktualizowany równolegle ze zmianami infrastruktury (GHCR zamiast
  Docker Huba, bastion bez `cloudflared`, runner GitHuba zamiast
  self-hosted), a `docs/ARCHITECTURE.md` w kilku miejscach wciąż opisuje
  wcześniejszy wariant. Ten katalog (`docs/dowody/`) i `docs/PLAN.md` opisują
  stan **faktyczny**, zweryfikowany na żywo, i w kilku miejscach jawnie
  zaznaczają tę rozbieżność (np. [rejestr.md](rejestr.md),
  [ci.md](ci.md)) zamiast ją wygładzać.
- **Ten katalog dowodowy nie jest wpisany w `README.md`/`RUNBOOK.md`** jako
  osobna pozycja - celowe, bo jest materiałem na obronę, a nie dokumentacją
  operacyjną projektu.

Related evidence: [git-github.md](git-github.md) - historia commitów tej
dokumentacji.
