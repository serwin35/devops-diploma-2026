CI (Jenkins lub inny) - dowody
================================

- [X] Wyzwalacze
- [X] Podział na kroki
- [ ] (Tylko Jenkins) - nie dotyczy: CI jest w GitHub Actions, nie w Jenkinsie

CI jest w **GitHub Actions**, na repozytorium aplikacji
(`serwin35/WF-ChartApp-diploma`) - kryterium dopuszcza „Jenkins **lub
inny**”. Jenkins w tym projekcie odpowiada za operacje na infrastrukturze
(kopie zapasowe), nie za CI aplikacji - uzasadnienie w
[ARCHITECTURE.md §8](../ARCHITECTURE.md#8-podział-cicd-github-actions-i-jenkins).

## Dowody zebrane na żywo (2026-08-05)

Wyzwalacz - `push` na `main` lub `develop` (nie na dowolną gałąź: PR
`develop->main` nie odpala testów po raz drugi, bo zmiany są już
zweryfikowane):

```yaml
# WF-ChartApp-diploma/.github/workflows/ci.yml
on:
  push:
    branches: [main, develop]
```

Podział na kroki - dwa równoległe joby, każdy z osobnymi krokami:

```
$ gh run view 30962155580 -R serwin35/WF-ChartApp-diploma
✓ main CI serwin35/WF-ChartApp-diploma#1
JOBS
✓ Tests (Pest) in 4m31s
✓ Code Style (Pint) in 2m38s
```

Rzeczywisty wynik testów w logu (nie tylko zielony ptaszek):

```
Tests:    814 passed (2303 assertions)
Code Style (Pint): PASS  ......................................... 616 files
```

Historia przebiegów pokazuje CI reagujące na kolejne pushe (sukcesy i
porażki - nie tylko wyselekcjonowane zielone):

```
$ gh run list -R serwin35/WF-ChartApp-diploma --workflow=ci.yml --limit 5
in_progress  feat(docker): add multi-stage php-fpm and nginx build images   develop  push
success      Merge pull request #2 from serwin35/develop                   main     push
failure      Merge pull request #1 from serwin35/main                     develop  push
failure      Update Readme.md                                              main     push
failure      Merge pull request #60 from CodeTronic-co/develop             main     push
```

## Jak to jest zrobione

| Element | Plik (repo aplikacji `WF-ChartApp-diploma`) |
|---|---|
| Workflow CI | `.github/workflows/ci.yml` |
| Job „Tests (Pest)” | uruchamia Postgres 18 i Redis 7 jako `services:` z healthcheckiem, potem `vendor/bin/pest --ci` |
| Job „Code Style (Pint)” | `vendor/bin/pint --test` |
| Sekret Composer (biblioteka płatna Flux UI Pro) | `secrets.COMPOSER_AUTH_JSON`, zapisywany do `auth.json` tylko na czas joba |

## Świadome decyzje / ograniczenia

- **Dwa równoległe joby** (testy, styl kodu) zamiast jednego sekwencyjnego -
  krótszy czas oczekiwania na wynik, a błąd stylu nie blokuje wyniku testów
  w tym samym przebiegu.
- **CI nie odpala się na dowolnej gałęzi** - świadomie ograniczone do `main`
  i `develop`, bo to jedyne gałęzie, z których cokolwiek się wdraża (zob.
  [cd.md](cd.md)); feature branche są weryfikowane dopiero przy pushu do
  `develop`.
- **Runner jest hostowany przez GitHuba**, nie self-hosted - to jest zmiana
  względem wcześniejszej wersji architektury (`ARCHITECTURE.md §8` wciąż
  opisuje runner self-hosted „wewnątrz segmentu apps”, co jest już
  nieaktualne). Obecny pipeline dociera do prywatnych maszyn wyłącznie w
  kroku wdrożenia, przez SSH proxy'owane bastionem - nie przez to, że sam
  runner stoi w sieci. Runnery/agenty jako osobne kryterium realizuje
  Jenkins z chmurą Docker - zob. [jenkins-agenty.md](jenkins-agenty.md).

## Zrzuty ekranu

![Zakładka Actions: przebieg CI z dwoma zielonymi jobami (Pest, Pint), rozwinięty log testów](../zrzuty/ci-run-detail.png)

Related evidence: [cd.md](cd.md), [testy.md](testy.md), [rejestr.md](rejestr.md).
