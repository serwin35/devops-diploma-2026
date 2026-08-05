# Docker i Compose - komendy

Dokument ułożony według zadań ("chcę zobaczyć logi kontenera", "chcę wdrożyć
nowy obraz na dev"), nie alfabetycznie po podkomendach. Skrót operacyjny jest
w [`RUNBOOK.md` sekcja 4](../RUNBOOK.md#4-docker-i-compose) - tu wersja pełna.

Węzły k3s **nie** są w grupie `docker` - tam kontenerami zarządza Kubernetes,
patrz [`kubernetes.md`](kubernetes.md).

**Zanim zejdziesz do surowych komend**: `make status` (z korzenia repozytorium,
na stacji roboczej) pokazuje w jednym wyjściu kontenery dev, pody produkcji
i kody HTTP obu środowisk. Wyłącznie odczyt, dobry punkt startu przed
diagnozowaniem czegokolwiek. Dalej w tym dokumencie są już wyłącznie zwykłe
komendy `docker` i `docker compose` wykonywane na maszynach.

> **Zweryfikowano na żywo 2026-08-05**: `docker ps` na wszystkich trzech
> maszynach, `docker compose ps` w `/opt/wolffire` i `/opt/jenkins`,
> `docker network ls`, `docker volume ls`, `docker system df`,
> `docker inspect` (zdrowie i licznik restartów), `systemctl cat wolffire`.

---

## 0. Dostęp: gdzie i jak

Trzy maszyny, każda osiągalna aliasem z `ansible/ssh_config` (przez bastion,
patrz [`RUNBOOK.md` sekcja 2](../RUNBOOK.md#2-dostęp-do-maszyn)):

| Maszyna | Alias SSH | Adres | Katalog stosu | Rola Ansible |
|---|---|---|---|---|
| aplikacja dev | `wf-wolffire-dev-app-1` | 10.0.120.30 | `/opt/wolffire` | `wolffire` |
| monitoring | `wf-monitoring-1` | 10.0.120.20 | `/opt/monitoring` | `monitoring` |
| CI/CD | `wf-cicd-1` | 10.0.120.10 | `/opt/jenkins` | `jenkins` |

**Wszystko idzie przez `sudo`.** Konto imienne nie jest w grupie `docker` -
w tej grupie jest wyłącznie konto maszynowe `ansible`, bo członkostwo w niej
jest równoważne uprawnieniom roota (`ansible/roles/docker/defaults/main.yml`).

Uprawnienia katalogów nie są jednakowe: `/opt/wolffire` i `/opt/jenkins` mają
`0750 root:root` (w drugim leży hasło administratora), `/opt/monitoring` ma
`0755`. Do dwóch pierwszych wchodź **całą komendą** pod `sudo`, nie samym
`docker compose`:

```bash
sudo bash -c 'cd /opt/wolffire && docker compose ps'
```

Powód jest praktyczny: Compose czyta `.env` z katalogu projektu i to z niego
podstawia `${IMAGE_TAG}` do nazw obrazów (`.env.app` z sekretami aplikacji jest
przekazywany kontenerom przez `env_file`). Uruchomiony z innego katalogu Compose
nie znajdzie `.env` i zgłosi `IMAGE_TAG variable is not set`. Oba pliki są
**kropkowe**, więc `ls -l` ich nie pokaże - potrzebne jest `sudo ls -la`.

---

## 1. Mapa trzech stosów

### Stos aplikacji dev - `/opt/wolffire`, projekt `wolffire`, 7 kontenerów

Szablon: `ansible/roles/wolffire/templates/compose.yml.j2`. Nazwy kontenerów są
ustawione jawnie (`container_name`), więc nie mają przyrostków `-1`.

```
NAMES                   STATUS                       PORTS
wolffire-nginx          Up About an hour (healthy)   80/tcp, 10.0.120.30:80->8080/tcp
wolffire-fpm-exporter   Up About an hour             10.0.120.30:9253->9253/tcp
wolffire-php            Up About an hour (healthy)   9000/tcp
wolffire-scheduler      Up About an hour (healthy)   9000/tcp
wolffire-horizon        Up About an hour (healthy)   9000/tcp
wolffire-postgres       Up About an hour (healthy)   5432/tcp
wolffire-redis          Up About an hour (healthy)   6379/tcp
```

| Usługa | Kontener | Obraz | Rola |
|---|---|---|---|
| `nginx` | `wolffire-nginx` | `.../nginx:${IMAGE_TAG}` | jedyny publikowany port HTTP |
| `php` | `wolffire-php` | `.../php:${IMAGE_TAG}` | php-fpm |
| `horizon` | `wolffire-horizon` | ten sam obraz php | `php artisan horizon` |
| `scheduler` | `wolffire-scheduler` | ten sam obraz php | `php artisan schedule:work` |
| `postgres` | `wolffire-postgres` | `postgres:18-alpine` | baza dev (w klastrze prod jest zewnętrzna) |
| `redis` | `wolffire-redis` | `redis:7-alpine` | kolejki i cache |
| `fpm-exporter` | `wolffire-fpm-exporter` | `hipages/php-fpm_exporter:2.2.0` | metryki fpm dla Prometheusa |

Trzy procesy aplikacji (`php`, `horizon`, `scheduler`) używają **tego samego
obrazu** i różnią się wyłącznie komendą - rozjazd wersji między nimi jest
niemożliwy z definicji.

Porty publikowane są na **adresie prywatnym**, nie na `0.0.0.0`
(`10.0.120.30:80->8080`) - z zewnątrz wchodzi się tunelem Cloudflare, który
terminuje na tej samej maszynie.

Detale, które łatwo przeoczyć w szablonie: `postgres_data` montowany jest pod
`/var/lib/postgresql`, a **nie** pod `.../data` (od Postgresa 18 obraz oficjalny
przeniósł `PGDATA` o katalog wyżej i montowanie po staremu kończy się odmową
startu); Redis ma `--maxmemory-policy noeviction`, bo trzyma kolejki Horizona
i domyślna polityka eksmisji po cichu kasowałaby zadania; `postgres` i `redis`
mają `healthcheck`, a aplikacja zależy od nich przez
`condition: service_healthy`, bo inaczej wstaje szybciej niż baza i wysypuje się
na pierwszym zapytaniu. Statusy `(healthy)` przy `php`, `nginx`, `horizon`
i `scheduler` pochodzą z instrukcji `HEALTHCHECK` **w obrazie**, nie z compose'a.

### Stos monitoringu - `/opt/monitoring`, projekt `monitoring`, 5 kontenerów

Szablon: `ansible/roles/monitoring/templates/compose.yml.j2`.

```
NAMES          STATUS             PORTS
prometheus     Up About an hour   10.0.120.20:9090->9090/tcp
loki           Up About an hour   10.0.120.20:3100->3100/tcp
alertmanager   Up About an hour   10.0.120.20:9093->9093/tcp
grafana        Up About an hour   10.0.120.20:3000->3000/tcp
calert         Up About an hour   6000/tcp
```

`calert` tłumaczy webhook Alertmanagera na format wiadomości Google Chat -
jako jedyny nie publikuje portu na hoście, bo rozmawia z nim tylko Alertmanager
z tej samej sieci. Cały stos stoi **poza klastrem k3s** celowo: monitoring
padający razem z monitorowaną infrastrukturą nie zaalarmuje o jej padnięciu.

Konfiguracje montowane są jako **katalogi**, nie pojedyncze pliki - bind mount
pliku przypina się do inode'a, a Ansible zapisuje szablony atomowo przez
`rename()`, więc kontener widziałby starą treść do końca życia.

### Stos Jenkinsa - `/opt/jenkins`, projekt `jenkins`, 1 kontener

Szablon: `ansible/roles/jenkins/templates/compose.yml.j2`.

```
SERVICE   STATUS             PORTS
jenkins   Up About an hour   10.0.120.10:8080->8080/tcp, 50000/tcp
```

Kontroler jest jeden, ale obrazów w składzie jest więcej - agenty to
**efemeryczne kontenery** tworzone przez chmurę Dockera Jenkinsa i kasowane po
minucie bezczynności. Dlatego `docker ps` na `cicd-1` w spoczynku pokazuje tylko
Jenkinsa, a `docker images` - dwa repozytoria:

```
REPOSITORY               TAG            SIZE
wolffire/jenkins         cb8434c69bbe   981MB
wolffire/jenkins-agent   6dd970d059bd   543MB
```

Tag jest **skrótem z treści** Dockerfile i listy wtyczek, nie `:local`. Powód
jest konkretny: przy składzie obrazów containerd nadpisanie tagu usuwa poprzedni
obraz natychmiast, kontener zostaje z odwołaniem do nieistniejącego ID,
a `docker compose images` (wołane przez moduł `docker_compose_v2` przy każdym
przebiegu) kończy się błędem `No such image` i wywraca całą rolę.

Kontener ma zamontowane `/var/run/docker.sock` - kto ma dostęp do gniazda
Dockera, ten ma roota na maszynie. To **podniesienie uprawnień** przyjęte
świadomie: maszyna jest dedykowana CI, do UI wchodzi się wyłącznie przez
Cloudflare Access, a buildy nie chodzą na kontrolerze. Pełne uzasadnienie jest
w komentarzu szablonu `jenkins/templates/compose.yml.j2`.

### Kontener spoza Compose: cAdvisor

Na **każdej** z trzech maszyn działa dodatkowo `cadvisor` (port `8081`),
uruchamiany modułem `community.docker.docker_container` z roli `docker`, a nie
Compose'em. Nie zobaczysz go w `docker compose ps` - tylko w `docker ps`. Port
8081, a nie 8080, bo na `cicd-1` osiemdziesiątkę zajmuje Jenkins.

---

## 2. Zadania codzienne

### Chcę zobaczyć, co działa

```bash
sudo docker ps
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"   # krocej
sudo docker ps -a                                    # takze zatrzymane
sudo bash -c 'cd /opt/wolffire && docker compose ps' # tylko dany stos
```

Format tabelaryczny jest wygodniejszy pod zrzut ekranu - domyślna tabela ma
kolumny `CONTAINER ID`, `IMAGE` i `COMMAND`, które przy długich nazwach z GHCR
rozjeżdżają wiersz na kilka linii.

### Chcę zobaczyć logi

```bash
sudo docker logs -f --tail 50 wolffire-php
sudo docker logs --since 15m --timestamps prometheus
sudo bash -c 'cd /opt/wolffire && docker compose logs -f --tail=50'          # caly stos
sudo bash -c 'cd /opt/wolffire && docker compose logs -f --tail=50 horizon'  # jedna usluga
```

`--tail` jest istotne: demon ma ustawiony limit `10m` na plik i 3 pliki
rotacji (`docker_log_max_size`), więc `docker logs` bez ograniczenia potrafi
wypluć dziesiątki megabajtów.

Te same logi trafiają do Loki - Alloy czyta je z gniazda Dockera (dlatego
użytkownik `alloy` jest dopisany do grupy `docker`). Zapytania opisuje
[`monitoring.md`](monitoring.md).

### Chcę wejść do kontenera

```bash
sudo docker exec -it wolffire-php sh
sudo docker exec -it wolffire-php php artisan migrate:status
sudo docker exec -it wolffire-postgres psql -U wolffire -d wolffire
sudo docker exec -it grafana sh

# Redis wymaga hasla - podaj je jawnie zamiast wklejac do historii powloki
sudo docker exec -it wolffire-redis redis-cli --no-auth-warning -a '<haslo>' ping
```

Obrazy aplikacji nie mają basha - `sh` jest jedyną powłoką. Hasło Redisa jest
wymagane także na dev: `.env.app` jest wspólnym szablonem z produkcją, a klient
php-redis wysyła `AUTH` bezwarunkowo, więc Redis bez `requirepass` odrzuciłby
połączenie błędem `ERR AUTH called without any password configured`. Wartość
leży w `/opt/wolffire/.env.app` (czytelnym tylko dla roota) i w SOPS.

### Chcę zrestartować jedną usługę

```bash
sudo bash -c 'cd /opt/monitoring && docker compose restart prometheus'
sudo bash -c 'cd /opt/wolffire && docker compose restart horizon'

# Po recznej zmianie compose.yml - odtwarza tylko to, co sie zmienilo
sudo bash -c 'cd /opt/monitoring && docker compose up -d'

# Aktualizacja obrazow do najnowszych wg tagow w compose
sudo bash -c 'cd /opt/monitoring && docker compose pull && docker compose up -d'
```

`restart` zatrzymuje i wznawia **ten sam** kontener (konfiguracja bez zmian),
`up -d` **odtwarza** kontener, gdy zmienił się obraz, zmienne albo definicja
usługi. Do podmiany wersji zawsze `up -d`, nigdy `restart`.

Zmiany w plikach w `/opt/*` **znikną przy najbliższym przebiegu Ansible** -
źródłem prawdy są szablony w repozytorium. Edycja na maszynie jest dobra do
diagnozy, nie do trwałej naprawy.

---

## 3. Jak CD wdraża na dev

Mechanizm jest celowo minimalny: pipeline **nie ma dostępu do gniazda Dockera**
i nie musi umieć Compose'a. Wdrożenie to podmiana jednej linii i przeładowanie
jednostki systemd.

```bash
# Dokladnie to robi job deploy-dev z workflow build.yml (przez SSH z bastionu):
echo "IMAGE_TAG=${SHA_SHORT}" | sudo tee /opt/wolffire/.env
sudo systemctl reload wolffire
sleep 15 && curl -sf http://10.0.120.30/up      # smoke test
```

Jednostka `wolffire.service` (szablon
`ansible/roles/wolffire/templates/wolffire.service.j2`) opakowuje Compose:

```ini
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/wolffire

ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down

# reload = pobierz obrazy wg IMAGE_TAG i podmien kontenery. To caly deployment.
ExecReload=/usr/bin/docker compose pull --quiet
ExecReload=/usr/bin/docker compose up -d --remove-orphans

TimeoutStartSec=600
```

Kluczowe własności: `Type=oneshot` z `RemainAfterExit=yes` sprawia, że jednostka
nie pilnuje procesu (robi to demon Dockera przez `restart: unless-stopped`),
tylko opisuje stan "stos ma być podniesiony" - `systemctl is-active wolffire`
zwraca `active` także wtedy, gdy żaden proces jednostki nie żyje. **`reload`,
nie `restart`**: `restart` zrobiłby `down` i `up`, czyli pełną przerwę, a
`reload` to `pull` plus `up -d`, po którym Compose odtwarza tylko te kontenery,
w których zmienił się obraz. `TimeoutStartSec=600`, bo pierwszy `pull` z GHCR
potrafi przekroczyć domyślne 90 sekund.

Diagnostyka wdrożenia:

```bash
systemctl is-active wolffire
systemctl status wolffire --no-pager
sudo journalctl -u wolffire -n 50 --no-pager      # tu widac wyjscie pull/up
sudo grep IMAGE_TAG /opt/wolffire/.env            # jaki tag jest teraz ustawiony
sudo bash -c 'cd /opt/wolffire && docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"'
```

> **Znany rozjazd.** Rola `wolffire` ustawia `.env` z wartości
> `wolffire_image_tag` (domyślnie `latest`), więc **przebieg playbooka cofa tag
> wdrożony przez CD**. Odczyt z 2026-08-05 pokazuje `IMAGE_TAG=latest`
> i obrazy `.../php:latest` na wszystkich kontenerach aplikacji. Produkcja ma
> ten problem rozwiązany - rola `wolffire_prod` przed wdrożeniem odczytuje tag
> z `helm get values` i go zachowuje. Na dev takiego odczytu nie ma. Skutek jest
> łagodny (`latest` wskazuje ostatni udany build), ale wdrożenie przestaje być
> odtwarzalne co do commita.

---

## 4. Rejestr GHCR

Obrazy `ghcr.io/serwin35/wf-chartapp-diploma/{php,nginx}` są w **prywatnym**
rejestrze. Maszyna dev loguje się do niego przy każdym przebiegu roli
(`community.docker.docker_login`) tokenem o zakresie wyłącznie `read:packages` -
nie ma prawa publikować, tylko pobierać. Poświadczenia lądują w
`/root/.docker/config.json`, dlatego `docker pull` działa tylko pod `sudo`.

```bash
# Recznie, gdy trzeba odswiezyc logowanie
echo "$GHCR_TOKEN" | sudo docker login ghcr.io -u serwin35 --password-stdin

# Czy dany tag w ogole istnieje w rejestrze
sudo docker manifest inspect ghcr.io/serwin35/wf-chartapp-diploma/php:5fbbbc8 | head -5
```

Publikacja odbywa się wyłącznie w CI (repozytorium `WF-ChartApp-diploma`),
tokenem z `write:packages`. Każdy build dostaje dwa tagi: `<sha>` do wdrożeń
(niepodmienialny, używa go `helm upgrade --set image.php.tag` i `.env` na dev)
oraz `latest` do ręcznych testów.

Sekrety budowania idą przez BuildKit, nie przez `ARG` - argumenty budowania
zostają w historii warstw i są czytelne dla każdego, kto obraz pobierze:

```bash
DOCKER_BUILDKIT=1 docker build \
  --secret id=composer_auth,src=./auth.json \
  -t ghcr.io/serwin35/wf-chartapp-diploma/php:local .
```

```dockerfile
RUN --mount=type=secret,id=composer_auth,target=/root/.composer/auth.json \
    composer install --no-dev --optimize-autoloader
```

---

## 5. Sieci i wolumeny

Każdy stos ma **własną sieć o jawnej nazwie**, a nie sieć domyślną - kontenery
znajdują się nawzajem po nazwie usługi, a ruch nie miesza się między stosami.

```
NETWORK ID     NAME                DRIVER    <- wolffire-dev-app-1
d285822161da   wolffire_wolffire   bridge

NETWORK ID     NAME                    DRIVER    <- monitoring-1
8e2c6b456a05   monitoring_monitoring   bridge

NETWORK ID     NAME      DRIVER                  <- cicd-1
a6138fb68978   jenkins   bridge
```

Zwróć uwagę na asymetrię: Compose domyślnie prefiksuje nazwę sieci nazwą
projektu (stąd `wolffire_wolffire`), ale sieć Jenkinsa ma jawne `name: jenkins`.
To nie jest niekonsekwencja - do tej nazwy odwołuje się szablon agenta
w `jenkins.yaml`, a z prefiksem chmura agentów podłączałaby kontenery do
nieistniejącej sieci.

Wolumeny nazwane trzymają wszystko, co ma przeżyć odtworzenie kontenerów:

| Wolumen | Co w nim jest |
|---|---|
| `wolffire_postgres_data` | baza dev |
| `wolffire_redis_data` | AOF Redisa (kolejki) |
| `wolffire_app_storage` | `storage/app` Laravela |
| `monitoring_prometheus_data`, `monitoring_loki_data` | szereg czasowy metryk i chunki logów |
| `monitoring_grafana_data`, `monitoring_alertmanager_data` | dashboardy, użytkownicy, stan wyciszeń |
| `jenkins_jenkins_home` | `JENKINS_HOME`: zadania, historia, klucze poświadczeń |

```bash
sudo docker volume ls
sudo docker volume inspect wolffire_postgres_data --format '{{.Mountpoint}}'
sudo docker network inspect wolffire_wolffire --format \
  '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

Wolumeny z losowymi nazwami (długi ciąg szesnastkowy) to anonimowe wolumeny
obrazów - na `cicd-1` jest ich dziesięć, zostały po efemerycznych agentach.
Te da się sprzątnąć, nazwanych **nie**.

---

## 6. Diagnostyka

```bash
# Zdrowie i licznik restartow - dziala takze dla zatrzymanego kontenera
sudo docker inspect --format '{{.Name}} {{.State.Health.Status}} restarts={{.RestartCount}}' \
  wolffire-php wolffire-nginx wolffire-postgres

# Ostatnia proba healthchecku wraz z wyjsciem komendy
sudo docker inspect --format '{{json .State.Health}}' wolffire-postgres | jq

# Co jest zamontowane, w jakich sieciach
sudo docker inspect --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' grafana
sudo docker inspect prometheus | jq '.[0].State, .[0].NetworkSettings.Networks'

# Zuzycie zasobow
sudo docker stats --no-stream
sudo docker system df
```

Wynik z 2026-08-05 (dev): `/wolffire-php healthy restarts=0`,
`/wolffire-nginx healthy restarts=0`, `/wolffire-postgres healthy restarts=0`.
Monitoring: `Images 6 / 1.647GB`, `Local Volumes 4 / 342.8MB`, `RECLAIMABLE 0B`.

`docker inspect` odpowiada nawet dla zatrzymanego kontenera, `docker stats` -
nie. To jest pierwszy krok, gdy kontener jest `Up`, a aplikacja nie odpowiada:
sprawdź `.State.Health.Status` (`healthy` / `unhealthy` / `starting`) zamiast
zgadywać z samego `docker ps`.

### Sprzątanie

```bash
sudo docker system df                       # NAJPIERW: co faktycznie zajmuje miejsce
sudo docker image prune -a                  # tylko nieuzywane obrazy
sudo docker builder prune                   # tylko cache budowania
```

> **`docker system prune -a --volumes` kasuje także nieużywane wolumeny.**
> "Nieużywany" znaczy "nie podpięty do istniejącego kontenera" - wolumen usługi
> chwilowo wyłączonej albo odtwarzanej łapie się na tę definicję. Na maszynie
> z danymi (`monitoring-1`, `wolffire-dev-app-1`) to jest komenda, która potrafi
> skasować szereg czasowy Prometheusa. Zawsze `system df` przed, a jeśli to
> możliwe - węższe `image prune` zamiast `system prune`.

---

## 7. Troubleshooting

| Objaw | Przyczyna | Co zrobić |
|---|---|---|
| `permission denied` przy `cd /opt/wolffire` | Katalog `0750 root:root` | `sudo bash -c 'cd /opt/wolffire && ...'`, nie samo `sudo docker ...` |
| `IMAGE_TAG variable is not set` | Compose uruchomiony z innego katalogu niż `/opt/wolffire` | Wejdź do katalogu stosu jako root; `.env` jest plikiem kropkowym, sprawdź `sudo ls -la` |
| `unauthorized` przy `pull` z GHCR | Token wygasł, zły zakres albo logowanie zrobione bez `sudo` | `sudo docker login ghcr.io`; sprawdź `read:packages` |
| Kontener `Up`, aplikacja nie odpowiada | Healthcheck jeszcze `starting` albo faktycznie `unhealthy` | `docker inspect --format '{{json .State.Health}}' <kontener>` - `Log` zawiera wyjście komendy |
| `no space left on device` | Stare obrazy i cache budowania | `docker system df`, potem `image prune -a` (patrz ostrzeżenie wyżej) |
| Zmiana w `/opt/*` zniknęła | Ansible nadpisuje szablony | Popraw źródło w `ansible/roles/*/templates/` |

### Kontener `unhealthy`

```bash
sudo docker inspect --format '{{json .State.Health}}' wolffire-postgres | jq '.Log[-1]'
sudo docker logs --tail 50 wolffire-postgres
```

`.State.Health.Log` zawiera wyjście **samej komendy healthchecku** wraz z kodem
wyjścia - często odpowiada wprost, czego brakuje, podczas gdy log aplikacji
milczy. Przykład z tego stosu: healthcheck Redisa woła `redis-cli -a <haslo>
ping`, więc rozjazd hasła między `.env.app` a komendą w compose objawia się
jako `unhealthy` przy działającym kontenerze.

Zależność `condition: service_healthy` sprawia, że `unhealthy` postgresa albo
Redisa **blokuje start** php, horizona i schedulera - naprawiaj od bazy w górę.

### Port zajęty

```bash
sudo ss -tlnp | grep -E ':(80|8080|8081|3000|9090)\b'
sudo docker ps --format '{{.Names}}\t{{.Ports}}'
```

Realny przypadek z tego projektu: cAdvisor domyślnie słucha na 8080, czyli na
porcie Jenkinsa - tunel Cloudflare kierował `jenkins.wolffire.dev` prosto na
cAdvisora. Stąd `cadvisor_port: 8081` w `ansible/roles/docker/defaults/main.yml`.
Porty są publikowane na adresie prywatnym, więc konflikt dotyczy pary
`adres:port`, nie samego numeru.

### Kontener restartuje się w pętli

```bash
sudo docker inspect --format '{{.RestartCount}} {{.State.ExitCode}} {{.State.Error}}' <kontener>
sudo docker logs --tail 100 <kontener>
sudo docker events --since 30m --filter container=<kontener>
```

Interpretacja kodu wyjścia: `137` to zabicie sygnałem KILL (najczęściej brak
pamięci), `1` to błąd aplikacji, `0` przy `restart: unless-stopped` oznacza
proces kończący się normalnie i podnoszony w kółko - zwykle zła komenda
w definicji usługi.

Rosnący `RestartCount` przy pustym logu znaczy, że kontener ginie **przed**
startem aplikacji: sprawdź `docker events` i `docker inspect` sekcję `Config`.

---

## Zobacz też

- [`RUNBOOK.md` sekcja 4](../RUNBOOK.md#4-docker-i-compose) - skrót operacyjny
- [`kubernetes.md`](kubernetes.md) - te same zadania dla produkcji na k3s
- [`monitoring.md`](monitoring.md) - metryki kontenerów (cAdvisor) i logi (Loki)
- [`ansible.md`](ansible.md) - jak przepuścić rolę, która te stosy generuje
