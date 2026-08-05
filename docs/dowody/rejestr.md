Docker Hub (lub inny rejestr) - dowody
=======================================

- [X] Publikacja obrazu z CI

Rejestrem jest **GHCR (GitHub Container Registry)**, nie Docker Hub -
kryterium dopuszcza „Docker Hub **lub inny**”. Uwaga: dokument
[ARCHITECTURE.md §10](../ARCHITECTURE.md#10-znane-ograniczenia) w tym repo
wciąż mówi „Docker Huba” - to zaległość dokumentacyjna po zmianie rejestru,
opisana niżej w sekcji ograniczeń.

## Dowody zebrane na żywo (2026-08-05)

Dwa pakiety, prywatne, z tagami `latest` i krótkim SHA commitu (niemutowalny
tag do wdrożenia):

```
$ gh api users/serwin35/packages?package_type=container -q '.[].name'
wf-chartapp-diploma/php
wf-chartapp-diploma/nginx
zoom-redirect

$ gh api users/serwin35/packages/container/wf-chartapp-diploma%2Fphp/versions \
    -q '.[].metadata.container.tags'
["latest","f24521b"]

$ gh api users/serwin35/packages/container/wf-chartapp-diploma%2Fphp -q '.visibility'
private
```

Obrazy faktycznie uruchomione, ściągnięte z tego rejestru (dev, Docker
Compose):

```
$ ssh wf-wolffire-dev-app-1 'sudo docker ps --format "{{.Image}}"'
ghcr.io/serwin35/wf-chartapp-diploma/nginx:latest
ghcr.io/serwin35/wf-chartapp-diploma/php:latest
ghcr.io/serwin35/wf-chartapp-diploma/php:latest
ghcr.io/serwin35/wf-chartapp-diploma/php:latest
```

Ten sam rejestr zasila też produkcję (k3s), zob. [kubernetes.md](kubernetes.md).

## Jak to jest zrobione

| Element | Plik |
|---|---|
| Budowa i publikacja (BuildKit -> GHCR) | `WF-ChartApp-diploma/.github/workflows/build.yml` (repo aplikacji) |
| Dockerfile PHP (multi-stage: composer -> runtime bez roota) | `.docker/php.dockerfile` |
| Dockerfile Nginx | `.docker/nginx.dockerfile` |
| Logowanie do GHCR w CI | `docker/login-action@v3` z `secrets.GITHUB_TOKEN`, uprawnienie `packages: write` |
| Ściąganie obrazu prywatnego przez Ansible (dev) | [ansible/roles/wolffire/](../../ansible/roles/wolffire/) - zadanie „Zaloguj się do rejestru obrazów” |
| Ściąganie obrazu prywatnego przez Helm (prod) | [helm/wolffire/templates/secret-ghcr.yaml](../../helm/wolffire/templates/secret-ghcr.yaml) - `imagePullSecrets` z tokenem `read:packages` |

Strategia tagowania: krótki SHA commitu jako tag niemutowalny (wdrożenie
wskazuje konkretną wersję), `latest` tylko dla gałęzi środowiskowych
(`main`, `develop`) - gałęzie robocze nie nadpisują `latest` pod
środowiskami.

## Świadome decyzje / ograniczenia

- **GHCR zamiast Docker Huba** - jeden token (`GITHUB_TOKEN`) obsługuje i
  push (CI), i pull (serwer), bez zakładania osobnego konta ani
  zarządzania kolejnym sekretem. Pakiety są prywatne, więc `imagePullSecrets`
  / `docker login` są realnie testowane, nie tylko deklarowane.
- **Ograniczenie zastane i rozwiązane (2026-08-05)**: pierwszy przebieg
  `build.yml` na `main` kończył się `403 Forbidden` przy pushu do GHCR.
  Przyczyną nie były uprawnienia `GITHUB_TOKEN` w repozytorium, lecz brak
  powiązania pakietów z repozytorium (Actions repository access pakietu).
  Po nadaniu dostępu Write (php) i odtworzeniu pakietu przez pierwszy push
  z Actions (nginx) CD publikuje obrazy poprawnie - szczegóły w
  [cd.md](cd.md).
- **`ARCHITECTURE.md` nie jest jeszcze zaktualizowany** po przejściu z
  Docker Huba na GHCR (nadal wspomina „Docker Huba” w sekcji o znanych
  ograniczeniach) - README już opisuje GHCR poprawnie. Rozjazd między tymi
  dwoma plikami jest odnotowany świadomie, a nie ukryty.

## Zrzuty ekranu

![Strona pakietu wf-chartapp-diploma/php na GHCR z tagami latest i sha](../zrzuty/rejestr-ghcr-package.png)

Related evidence: [docker.md](docker.md), [ci.md](ci.md), [cd.md](cd.md).
