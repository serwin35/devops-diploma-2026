# Docker i Compose - komendy

Dotyczy trzech maszyn z grupy `docker` w inventory: `cicd-1` (Jenkins),
`monitoring-1` (Prometheus/Grafana/Loki/Alertmanager), `wolffire-dev-app-1`
(aplikacja). Węzły k3s **nie** są w tej grupie - tam kontenerami zarządza
Kubernetes, patrz [`kubernetes.md`](kubernetes.md).

> **Zweryfikowano na żywo** 2026-08-05: `docker ps` na `wolffire-dev-app-1`
> (8 kontenerów) i `monitoring-1` (5 kontenerów przez `docker compose ps`),
> `docker compose ps` na `cicd-1` (Jenkins + cAdvisor).

---

## Przegląd kontenerów

```bash
ssh wf-monitoring-1

sudo docker ps                                    # działające kontenery
sudo docker ps -a                                 # także zatrzymane
sudo docker stats --no-stream                      # zużycie CPU/RAM/sieć jednorazowo
sudo docker images
sudo docker network ls && sudo docker volume ls
sudo docker logs -f prometheus
sudo docker logs --tail 50 --timestamps grafana
sudo docker exec -it grafana sh
```

`docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"` daje krótszy,
czytelniejszy widok niż domyślna tabela - przydatne pod zrzut ekranu na obronę.

## Compose

Stosy w tym projekcie: `/opt/monitoring` (Prometheus/Grafana/Loki/Alertmanager/
calert), `/opt/jenkins` (kontroler + agent-image), `/opt/wolffire`
(aplikacja dev).

```bash
cd /opt/monitoring
sudo docker compose ps
sudo docker compose logs -f --tail=50
sudo docker compose restart prometheus
sudo docker compose up -d                         # po ręcznej zmianie compose.yml
sudo docker compose pull && sudo docker compose up -d   # aktualizacja obrazów
```

**`/opt/wolffire` ma uprawnienia `0750 root:root`** - zwykłe `cd` bez `sudo`
kończy się `Permission denied`, nawet dla użytkownika `ansible`. Wejdź całą
komendą pod `sudo`, nie tylko `docker compose`:

```bash
sudo bash -c 'cd /opt/wolffire && docker compose ps'
```

Bez tego Compose nie znajdzie `.env` (tag obrazu) i `.env.app` (sekrety
aplikacji) leżących obok `compose.yml` w tym samym katalogu.

## Inspect - health, mounts, networks

```bash
sudo docker inspect --format '{{json .State.Health}}' wolffire-php | jq
sudo docker inspect --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' grafana
sudo docker inspect --format '{{range $net,$cfg := .NetworkSettings.Networks}}{{$net}}: {{$cfg.IPAddress}}{{"\n"}}{{end}}' prometheus

# Krócej, bez formatowania - cały JSON
sudo docker inspect prometheus | jq '.[0].State, .[0].NetworkSettings.Networks'
```

`docker inspect` odpowiada, nawet gdy kontener jest zatrzymany - `docker stats`
nie. To pierwszy krok, gdy kontener jest `Up` ale aplikacja nie odpowiada:
sprawdź `.State.Health.Status` (`healthy`/`unhealthy`/`starting`) zamiast
zgadywać z samego `docker ps`.

## Sprzątanie

```bash
sudo docker system df                             # co zajmuje miejsce
sudo docker system prune -a --volumes             # UWAGA: kasuje NIEUŻYWANE wolumeny i obrazy
```

`system df` przed `prune` - na dysku produkcyjnym łatwo skasować coś, co
wygląda na nieużywane, a jest wolumenem z danymi wyłączonej chwilowo usługi.

## Budowanie z sekretem BuildKit

Obraz aplikacji buduje się w CI (repozytorium `WF-ChartApp-diploma`), z
sekretem przekazanym przez `--secret`, nie przez `ARG` - argumenty budowania
trafiają do historii warstw obrazu (`docker history`) i są czytelne dla
każdego, kto go ściągnie.

```bash
DOCKER_BUILDKIT=1 docker build \
  --secret id=composer_auth,src=./auth.json \
  -t ghcr.io/serwin35/wf-chartapp-diploma/php:local .
```

W `Dockerfile` odpowiada temu:

```dockerfile
RUN --mount=type=secret,id=composer_auth,target=/root/.composer/auth.json \
    composer install --no-dev --optimize-autoloader
```

Sekret istnieje wyłącznie na czas wykonania tej jednej warstwy - nie zostaje
w finalnym obrazie i nie da się go odzyskać przez `docker history`.

## GHCR - logowanie i publikacja

Rejestr obrazów: `ghcr.io/serwin35/wf-chartapp-diploma/{php,nginx}`. Maszyna
`wolffire-dev-app-1` loguje się tokenem o zakresie wyłącznie `read:packages`
(rola `wolffire`, moduł `community.docker.docker_login`) - nie ma prawa
publikacji, tylko pobierania.

```bash
# Logowanie (token z uprawnieniem write:packages po stronie CI)
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-user> --password-stdin

# Publikacja
docker tag wolffire-php:local ghcr.io/serwin35/wf-chartapp-diploma/php:<sha>
docker push ghcr.io/serwin35/wf-chartapp-diploma/php:<sha>
docker tag wolffire-php:local ghcr.io/serwin35/wf-chartapp-diploma/php:latest
docker push ghcr.io/serwin35/wf-chartapp-diploma/php:latest
```

Dwa tagi na obraz nie są przypadkiem: `<sha>` daje precyzyjne, niepodmienialne
odwołanie do wdrożenia (używa go `helm upgrade --set image.tag=<sha>` i plik
`.env` na dev), `latest` służy do ręcznych testów i przeglądania rejestru
w przeglądarce.

## Częste problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `permission denied` przy `cd /opt/wolffire` | Katalog `0750 root:root` | `sudo bash -c 'cd /opt/wolffire && ...'`, nie samo `sudo docker ...` |
| `docker compose ps` pokazuje `IMAGE_TAG variable is not set` | Brak `.env` w katalogu roboczym (uruchomione z innego cwd albo bez `sudo`) | Wejdź do katalogu stosu jako root, patrz wyżej |
| `docker: unauthorized` przy `pull` z GHCR | Token wygasł albo ma zły zakres | `docker login ghcr.io` ponownie; sprawdź `read:packages`/`write:packages` |
| Kontener `Up` ale aplikacja nie odpowiada | Health check jeszcze się nie ustabilizował albo faktycznie jest `unhealthy` | `docker inspect --format '{{json .State.Health}}' <kontener>` |
| `no space left on device` | Nagromadzone stare obrazy/warstwy build cache | `docker system df` -> `docker system prune -a --volumes` (po weryfikacji, że nic ważnego nie zniknie) |
