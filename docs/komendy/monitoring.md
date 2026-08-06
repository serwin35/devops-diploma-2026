# Monitoring - komendy

Stos stoi na `monitoring-1` (`10.0.120.20`) w Docker Compose, świadomie **poza**
klastrem k3s: monitoring padający razem z monitorowaną infrastrukturą nie
zaalarmuje o jej padnięciu. W `/opt/monitoring/compose.yml` żyją Prometheus,
Alertmanager, calert, Loki i Grafana. Logi zbiera Alloy zainstalowany jako
pakiet na każdej maszynie z inventory.

> **Najczęstsza pomyłka w tym projekcie.** Porty stosu są opublikowane na
> adresie prywatnym maszyny, nie na `0.0.0.0`: `- "10.0.120.20:9090:9090"`.
> `curl localhost:9090` kończy się `Connection refused` **nawet w powłoce na
> samym `monitoring-1`**. Zawsze `10.0.120.20:<port>` albo tunel SSH. Wyjątek:
> `docker exec` do wnętrza kontenera, gdzie `localhost` jest tym kontenerem.

> **Zweryfikowano na żywo** 2026-08-05: 19/19 celów `up`, 15 reguł w 4 grupach,
> Loki z logami z 9/9 hostów, `amtool alert query` pokazuje `Watchdog` jako
> `active`, subskrypcja SNS potwierdzona.

---

## 1. Chcę zobaczyć panel

Normalna droga to przeglądarka i Cloudflare Access - `grafana.wolffire.dev`
(dashboardy, Explore dla Loki), `prometheus.wolffire.dev` (`/targets`,
`/alerts`, `/graph`), `alerts.wolffire.dev` (Alertmanager). Wszystkie trzy za
Zero Trust Access, pierwsze wejście to kod na e-mail. Kody odpowiedzi i ich
znaczenie: [RUNBOOK §7](../RUNBOOK.md).

**Droga awaryjna** - gdy Access marudzi albo tunel Cloudflare padł. Bastion ma
trasę do sieci prywatnej, więc przekierowujemy port lokalny na adres prywatny
monitoringu, a nie na `localhost` bastionu:

```bash
ssh -L 9090:10.0.120.20:9090 wf-bastion-1     # -> http://localhost:9090

# Wszystkie panele naraz, w tle, bez otwierania powłoki
ssh -f -N -L 9090:10.0.120.20:9090 -L 9093:10.0.120.20:9093 \
         -L 3000:10.0.120.20:3000 -L 3100:10.0.120.20:3100 wf-bastion-1
```

Adres po prawej stronie rozwiązuje **bastion**, nie Twój laptop - dlatego musi
tam być `10.0.120.20`. Lewa liczba to port lokalny i może być dowolna
(`-L 19090:10.0.120.20:9090`, gdy 9090 masz zajęte).

Z powłoki na maszynie:

```bash
ssh wf-monitoring-1
curl -s http://10.0.120.20:9090/-/ready      # Prometheus: TSDB gotowy
curl -s http://10.0.120.20:9093/-/healthy    # Alertmanager
curl -s http://10.0.120.20:3100/ready        # Loki
curl -s http://10.0.120.20:3000/api/health   # Grafana: {"database":"ok",...}
sudo docker compose -f /opt/monitoring/compose.yml ps
```

Hasło do Grafany: `grafana_admin_password` w
`ansible/group_vars/all/secrets.sops.yml` (`sops --decrypt`).

**Zanim zejdziesz do PromQL i API.** Z korzenia repozytorium są dwa cele, oba
wyłącznie do odczytu, i warto zacząć od nich, bo w kilkanaście sekund
odpowiadają na pytanie "czy w ogóle jest awaria, i po której stronie":

```bash
make status       # węzły i pody k3s, kontenery dev, kody HTTP obu środowisk
make test-infra   # testy dymne: terraform plan, ansible --check, zapytania HTTP
```

Reszta tego dokumentu to normalna praca na surowych narzędziach - `curl` do
API, `amtool`, LogQL. Cele `make` nie zastępują ich, tylko oszczędzają pierwsze
dwie minuty.

## 2. Co ten Prometheus zbiera

Cele nie są wpisywane ręcznie - `prometheus.yml.j2` wylicza je z inventory
Ansible'a, więc dodanie maszyny do inventory automatycznie włącza ją do
monitoringu. Świadomie bez operatora i automatycznego odkrywania: jawna lista
pokazuje dokładnie, co jest zbierane.

| Job | Port | Skąd cele | Co daje |
|---|---|---|---|
| `node` | 9100 | `groups['all']` | CPU, RAM, dyski, sieć każdej maszyny |
| `cadvisor` | 8081 | `groups['docker']` | zużycie zasobów per kontener |
| `docker` | 9323 | `groups['docker']` | demon Dockera: liczba kontenerów w stanach |
| `postgres` | 9187 | `groups['postgres']` | połączenia, transakcje, rozmiar bazy |
| `redis` | 9121 | `groups['redis']` | pamięć, klucze, trafienia cache |
| `wolffire` | 9253 | `groups['dev']` | eksporter php-fpm: workery, kolejka nasłuchu |

`docker` obok `cadvisor` nie jest duplikatem: cAdvisor widzi tylko kontenery,
które istnieją, a demon raportuje liczbę w stanie `stopped` - to jedyne
źródło, po którym da się wykryć kontener, który padł i **nie** wstał.

## 3. PromQL - zestaw, który realnie się przydaje

Wyrażenia poniżej to te same, które siedzą w dashboardach i regułach.

```promql
# Dostępność
up == 0                                       # tylko to, co padło
count(up == 1)                                # ile celów żyje
count(up{job="node"} == 1)                    # ile maszyn odpowiada
sum(ALERTS{alertstate="firing", alertname!="Watchdog"}) or vector(0)

# CPU w procentach - z czasu bezczynności, bo node_exporter nie wystawia
# zużycia wprost
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pamięć. MemAvailable, nie MemFree: cache i bufory system odda pod presją,
# więc MemFree zawsze wygląda alarmująco.
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Wolne miejsce, bez systemów wirtualnych
node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
  / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"} * 100

# Sieć, bez interfejsów wirtualnych i mostków Dockera
rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m])

# Czy przy obecnym tempie zabraknie miejsca w dobę
predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}[6h], 24*3600) < 0
```

`or vector(0)` jest istotne w kafelkach: bez niego pusty wynik daje
"No data" zamiast zera.

```promql
# Kontenery (cAdvisor)
sum by (instance, name) (rate(container_cpu_usage_seconds_total{name!=""}[5m]))
container_memory_working_set_bytes{name!=""}      # nie usage: usage wlicza cache stron
container_spec_memory_limit_bytes{name!=""} < 1e12 > 0   # bez limitu cAdvisor podaje absurd
sum(increase(container_oom_events_total[1h]))     # zabicia przez OOM
time() - container_start_time_seconds{name!=""}   # jak długo działa

# Restarty: changes(), nie increase(). container_start_time_seconds to znacznik
# czasu startu, nie licznik - increase() liczyłby różnice timestampów i dawał
# tysiące przy jednym restarcie.
sum by (instance, name) (changes(container_start_time_seconds{name!=""}[15m]))

# Kontenery zatrzymane - źródło: demon Dockera, nie cAdvisor
engine_daemon_container_states_containers{state="stopped"} > 0
```

`rate()` liczy przyrost na sekundę i wymaga licznika rosnącego monotonicznie
(`_total`); `increase()` to ta sama wartość razy okno. Do metryk będących
stanem (`container_start_time`, `node_memory_*`) żadne z nich nie pasuje.

```promql
# php-fpm. Laravel nie wystawia własnego /metrics - status FPM pokrywa warstwę
# operacyjną, a metryki biznesowe nie są przedmiotem tego monitoringu.
phpfpm_up                                # czy eksporter dochodzi do puli
phpfpm_active_processes                  # workery obsługujące żądanie teraz
phpfpm_idle_processes                    # wolne sloty
phpfpm_listen_queue                      # żądania czekające na wolny worker
phpfpm_max_children_reached              # ile razy pula uderzyła w sufit
rate(phpfpm_accepted_connections[5m])    # żądania na sekundę

# Baza i Redis
sum(pg_stat_activity_count) / max(pg_settings_max_connections) * 100
sum by (state) (pg_stat_activity_count{state!=""})
max(pg_stat_activity_max_tx_duration)                  # najdłuższa transakcja
rate(pg_stat_database_deadlocks{datname="wolffire"}[5m])
redis_up                                               # czy eksporter DOSZEDŁ do Redisa
redis_memory_used_bytes / clamp_min(redis_memory_max_bytes, 1) * 100
```

`phpfpm_listen_queue > 0` utrzymane dłużej niż chwilę oznacza, że żądania
czekają na workera; rosnący `phpfpm_max_children_reached` to ten sam objaw
z drugiej strony. `redis_up` a `up{job="redis"}`: pierwsza mówi, czy eksporter
dogadał się z Redisem, druga tylko czy sam eksporter odpowiada - martwy Redis
przy żywym eksporterze to realny scenariusz. `clamp_min(..., 1)` chroni przed
dzieleniem przez zero, gdy licznik pojawi się przed mianownikiem.

## 4. API Prometheusa curl-em

```bash
ssh wf-monitoring-1
P=http://10.0.120.20:9090

# Cele: job, instancja, stan
curl -s $P/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health)"' | sort

# Tylko to, co nie działa, razem z powodem
curl -s $P/api/v1/targets \
  | jq -r '.data.activeTargets[] | select(.health!="up")
           | "\(.labels.job) \(.scrapeUrl) \(.lastError)"'

# Ile up / ile wszystkich
curl -s $P/api/v1/targets \
  | jq '[.data.activeTargets[]] | "\(map(select(.health=="up")) | length)/\(length)"'

# Grupy reguł i liczba reguł w każdej
curl -s $P/api/v1/rules | jq -r '.data.groups[] | "\(.name): \(.rules | length)"'

curl -s $P/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname) \(.state)"'

# Zapytanie chwilowe: jedna wartość na serię. --data-urlencode jest konieczne,
# bo PromQL zawiera {, }, = i spacje
curl -sG $P/api/v1/query --data-urlencode 'query=up == 0' \
  | jq -r '.data.result[] | "\(.metric.job) \(.metric.instance)"'

# Zapytanie zakresowe: szereg czasowy. start/end/step są WYMAGANE
curl -sG $P/api/v1/query_range \
  --data-urlencode 'query=sum(rate(container_cpu_usage_seconds_total{name="wolffire-php"}[5m]))' \
  --data-urlencode "start=$(date -u -d '1 hour ago' +%s)" \
  --data-urlencode "end=$(date -u +%s)" \
  --data-urlencode 'step=60' | jq '.data.result[0].values | length'

# Jakie w ogóle są metryki, gdy nie pamiętasz nazwy
curl -s $P/api/v1/label/__name__/values | jq -r '.data[]' | grep -i phpfpm

# Przeładowanie konfiguracji bez restartu (--web.enable-lifecycle jest włączone)
curl -X POST $P/-/reload
```

Składnia `date -u -d '1 hour ago'` działa na maszynach (Linux); w powłoce na
macOS odpowiednikiem jest `date -u -v-1H`.

## 5. Alertmanager: co gdzie poszło i jak to wyciszyć

`amtool` nie jest zainstalowany na hoście - żyje w kontenerze `alertmanager`.
Wewnątrz kontenera `localhost:9093` jest poprawnym adresem.

```bash
ssh wf-monitoring-1
AM='sudo docker exec alertmanager amtool --alertmanager.url=http://localhost:9093'

$AM alert query                       # co jest aktywne
$AM alert query severity=critical     # filtrowanie po etykietach
$AM alert query -o extended           # pełne etykiety i adnotacje
```

```
Alertname              Starts At                Summary                        State
Watchdog               2026-08-05 20:08:48 UTC  Potok alertowania działa       active
WysokieZuzyciePamieci  2026-08-05 20:09:28 UTC  proxmox-1: pamięć powyżej 92%  active
```

Obecność `Watchdog` na tej liście jest dowodem, że ścieżka reguła ->
ewaluacja -> Alertmanager żyje. Jego **zniknięcie**, a nie pojawienie się,
jest sygnałem awarii potoku.

### Dokąd alert pojedzie (najważniejsza komenda przy "nie doszło")

```bash
$AM config routes
```

```
Routing tree:
.
└── default-route  receiver: gchat
    ├── {alertname="Watchdog"}  receiver: null
    ├── {severity=~"warning|critical"}  continue: true  receiver: sns-email
    ├── {severity="critical"}  receiver: gchat
    └── {severity="warning"}  receiver: gchat
```

Trasy sprawdzane są po kolei, a pierwsze dopasowanie normalnie kończy
wyszukiwanie. `Watchdog` jest **pierwszy** i idzie do `null`, żeby żadna
kolejna reguła nie mogła go przechwycić i zasypać kanału co 4 godziny; trasa
`sns-email` ma `continue: true`, więc alert po dopasowaniu leci dalej w dół
drzewa.

**Pułapka, na której ten routing raz się wyłożył:** gdy dopasuje się
JAKAKOLWIEK trasa potomna, receiver trasy głównej przestaje być fallbackiem.
Zanim istniała jawna trasa `severity="warning"`, alert warning dopasowywał
`sns-email` (z `continue`), po czym nie pasował już do niczego - i kończył na
samym e-mailu, choć intuicja podpowiada, że "spadnie" do `gchat`
z default-route. Nie spadnie. Objaw z 2026-08-06: `KontenerZatrzymany`
przyszedł mailem, na Chacie cisza, a calert od doby nie dostał ani jednego
`/dispatch`. Stąd zasada: **każda waga ma swoją jawną trasę do `gchat`**,
a receiver default-route jest tylko siatką na alerty bez etykiety `severity`.

```bash
# Test suchy: gdzie trafi alert o takich etykietach, bez wysyłania czegokolwiek
$AM config routes test severity=critical alertname=BazaNieodpowiada
# -> sns-email,gchat   (dwa odbiorcy: dowód, że continue: true działa)
$AM config routes test severity=warning alertname=KontenerZatrzymany
# -> sns-email,gchat   (samo sns-email = wróciła pułapka opisana wyżej)

# Walidacja pliku konfiguracji
sudo docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
docker run --rm -v "$PWD:/w" prom/alertmanager:v0.28.0 amtool check-config /w/alertmanager.yml
```

### Alert testowy przez pełny potok

Ta komenda **wysyła realne powiadomienie** na Chat i e-mail.

```bash
# Cytowanie: wartość adnotacji zawiera spacje, więc CAŁY argument idzie
# w apostrofach, a wartość dodatkowo w cudzysłowie. Bez tego shell rozbije
# "Test kanalow" na dwa argumenty, a amtool zwróci "invalid label".
$AM alert add alertname=TestKanaluEmail severity=warning instance=test \
  --annotation='summary="Test kanalow alertowania"' \
  --annotation='description="Alert wygenerowany recznie, nie z reguly"'
```

Alert bez `--end` wygasa po `resolve_timeout` (5 min), a po wygaśnięciu leci
`[RESOLVED]`, bo receivery mają `send_resolved: true`. Pierwsze powiadomienie
przyjdzie po `group_wait`, czyli ok. 30 sekund - nie natychmiast.

### Wyciszenia

```bash
$AM silence query                                        # co jest wyciszone
$AM silence query --expired                              # co już wygasło
$AM silence add alertname=MaszynaNieodpowiada instance=monitoring-1 \
  --duration=2h --comment='planowany restart hypervisora'
$AM silence add 'instance=~"wolffire-dev.*"' --duration=1h --comment='wdrozenie 2.1'
$AM silence expire <id>
$AM silence expire $($AM silence query -q)               # wszystkie naraz
```

Zawsze z `--comment` - lista wyciszeń bez komentarzy po tygodniu jest
bezużyteczna, bo nikt nie wie, czy wciąż są uzasadnione.

To samo czystym REST API:

```bash
A=http://10.0.120.20:9093
curl -s $A/api/v2/status | jq '{cluster: .cluster.status, uptime: .uptime}'
curl -s $A/api/v2/alerts | jq -r '.[] | "\(.labels.alertname) \(.labels.severity) \(.status.state)"'
curl -s $A/api/v2/alerts | jq -r '.[] | select(.status.silencedBy|length > 0) | .labels.alertname'
curl -s $A/api/v2/silences | jq -r '.[] | "\(.id) \(.status.state) \(.comment)"'
curl -s $A/api/v2/status | jq -r '.config.original'      # konfiguracja z żywego procesu
```

`silencedBy` to najprostsza odpowiedź na "czy ten alert nie doszedł, bo ktoś
go wyciszył".

## 6. Kanał e-mail przez AWS SNS

Alerty `warning` i `critical` idą równolegle na Chat i e-mail. Alertmanager
publikuje natywnie (`sns_configs` z podpisem SigV4), a subskrypcja e-mail
tematu `wolffire-alerts` dostarcza wiadomość. SNS zamiast własnego MTA albo
SES: zero walki z reputacją IP i filtrami spamu, a domena celowo deklaruje
brak poczty (null MX, SPF `-all`, DMARC `reject`). Uprawnienia minimalne:
użytkownik IAM `wolffire-alertmanager` ma wyłącznie `sns:Publish` na ten jeden
temat, więc kompromitacja klucza z maszyny monitoringu nie daje dostępu ani do
stanu Terraforma, ani do kopii zapasowych.

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-1:195275647734:wolffire-alerts
```

| Co widać w `SubscriptionArn` | Znaczenie |
|---|---|
| pełny ARN z identyfikatorem | potwierdzona, alerty wychodzą |
| `PendingConfirmation` | AWS wysłał link "Confirm subscription", nikt nie kliknął - **alerty nie wychodzą** |
| `Deleted` | ktoś kliknął "unsubscribe" w stopce maila |

**Pułapka: link unsubscribe.** Każda wiadomość SNS ma go w stopce. Kliknięcie
natychmiast wyłącza kanał i **nie generuje żadnego sygnału po stronie
Alertmanagera** - ten dalej publikuje do tematu z kodem 200, tylko nikt tych
wiadomości już nie dostaje. Awaria całkowicie cicha: `amtool alert query`
pokazuje alerty, logi są czyste, a skrzynka milczy. Wykrywalna wyłącznie
komendą wyżej albo metrykami CloudWatch niżej.

**Odtworzenie po unsubscribe.** Subskrypcji w stanie `Deleted` nie da się
reaktywować, a Terraform sam z siebie nie zauważy problemu, bo w stanie ma
zasób, który formalnie istnieje. Stąd jawne `-replace`:

```bash
terraform -chdir=terraform/bootstrap apply \
  -replace=aws_sns_topic_subscription.alerts_email
```

Po `apply` AWS wysyła **nowy** link potwierdzający na adres z
`var.alerts_email`; do kliknięcia subskrypcja jest `PendingConfirmation`
i kanał nadal milczy. Wymaga poświadczeń admina AWS, nie klucza
`wolffire-alertmanager` (ten ma tylko `sns:Publish`).

Poniższe komendy `aws` uruchamiasz **lokalnie**, nie na maszynie - stąd składnia
`date` w wariancie macOS (`-v-2H`); na Linuksie `-d '2 hours ago'`.

```bash
# Czy wiadomości realnie wychodzą (wymaga poświadczeń AWS)
for M in NumberOfMessagesPublished NumberOfNotificationsDelivered NumberOfNotificationsFailed; do
  echo "== $M"; aws cloudwatch get-metric-statistics --namespace AWS/SNS --metric-name "$M" \
    --dimensions Name=TopicName,Value=wolffire-alerts \
    --start-time "$(date -u -v-2H +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 --statistics Sum --query 'Datapoints[].Sum'
done
```

`Published > 0` przy `Delivered = 0` oznacza dokładnie jedno: Alertmanager
robi swoje, a problem jest po stronie subskrypcji.

## 7. Loki i LogQL

Logi zbiera Alloy zainstalowany jako pakiet (nie kontener - musi czytać
journald hosta i gniazdo Dockera) i wysyła do
`http://10.0.120.20:3100/loki/api/v1/push`. Loki jednowęzłowy, chunki na dysku
lokalnym, bez klastra i bez S3 - przy ośmiu maszynach rozproszony Loki byłby
czystą złożonością. Retencja 7 dni (`168h`).

Etykiety są celowo skromne: każda tworzy osobny strumień, a nadmiar etykiet
o dużej liczności (np. identyfikator żądania) rozsadza indeks.

| Etykieta | Wartości |
|---|---|
| `job` | `docker`, `systemd-journal` - dwa źródła, nic więcej |
| `host` | `bastion-1`, `cicd-1`, `k3s-agent-1/2`, `k3s-server-1`, `monitoring-1`, `proxmox-1`, `wolffire-dev-app-1`, `wolffire-prod-db-1` - nazwa **bez** prefiksu `wf-` |
| `container` | `wolffire-php`, `wolffire-nginx`, `wolffire-horizon`, `wolffire-scheduler`, `wolffire-postgres`, `wolffire-redis`, `prometheus`, `grafana`, `calert`, ... (tylko `job="docker"`) |
| `unit` | `k3s.service`, `docker.service`, `alloy.service`, `cloudflared.service`, `fail2ban.service`, ... (tylko `job="systemd-journal"`) |
| `level`, `stream` | poziom z journald; `stdout`/`stderr` z Dockera |

Nazwa hosta w Loki jest tym samym `inventory_hostname`, co etykieta `instance`
w Prometheusie - dzięki temu da się skakać między metrykami a logami tej samej
maszyny bez tłumaczenia nazw.

Zapytanie LogQL ma zawsze **selektor strumienia** w klamrach (obowiązkowy,
korzysta z indeksu) i opcjonalny **potok** filtrów za `|`. Filtry potoku, od
najtańszego: `|= "ERROR"` zawiera dosłownie,
`!= "healthz"` nie zawiera, `|~ "(?i)error"` pasuje do wyrażenia regularnego,
`!~ "GET /up"` nie pasuje. Dalej `| json` (rozbiór pola po polu) i `| pattern`
(dla logów, które JSON-em nie są).

```bash
ssh wf-monitoring-1
L=http://10.0.120.20:3100
Q="curl -sG $L/loki/api/v1/query_range --data-urlencode"

# Wszystko z ostatniej godziny. Selektor musi coś dopasowywać - samo {} to błąd
$Q 'query={host=~".+"}' --data-urlencode 'limit=20' | jq -r '.data.result[].values[][1]'

$Q 'query={job="systemd-journal", host="k3s-server-1", unit="k3s.service"}'

# Błędy aplikacji bez szumu z sond
$Q 'query={job="docker", container=~"wolffire-(php|horizon)"} |= "ERROR" != "healthz"'

# Logi Laravela w JSON: parsujemy i filtrujemy po polu
$Q 'query={job="docker", container="wolffire-php"} | json | level="error"'

# Kody odpowiedzi nginksa - pattern, bo to nie jest JSON
$Q 'query={job="docker", container="wolffire-nginx"} | pattern `<_> - <_> [<_>] "<_>" <status> <_>` | status=~`5..`'

# Metryki z logów: tempo błędów per kontener, ruch per host
curl -sG $L/loki/api/v1/query --data-urlencode \
  'query=sum by (container) (rate({job="docker", host="wolffire-dev-app-1"} |~ "(?i)error" [1m]))'
curl -sG $L/loki/api/v1/query --data-urlencode \
  'query=sum by (host) (count_over_time({job="systemd-journal"} [5m]))'

# Podpowiedzi, gdy nie pamiętasz nazw
curl -s $L/loki/api/v1/labels | jq -r '.data[]'
curl -s $L/loki/api/v1/label/container/values | jq -r '.data[]'
curl -s $L/loki/api/v1/label/unit/values | jq -r '.data[]' | grep -v '^session-'
```

`rate()` i `count_over_time()` idą przez `/query` (chwilowe) albo
`/query_range` ze `step` - w odróżnieniu od surowych zapytań logowych, które
zawsze przez `query_range`. W przeglądarce: Grafana -> Explore -> źródło Loki,
z uzupełnianiem etykiet; gotowe panele to dashboardy "Logi" i "Logi aplikacji".

## 8. calert - tłumacz na Google Chat

Alertmanager wysyła własny format JSON, którego Google Chat nie rozumie - Chat
oczekuje prostego `{"text": "..."}`. calert stoi w tej samej sieci Dockera
i jest adresowany nazwą usługi (`http://calert:6000/dispatch`), więc nie ma
opublikowanego portu na zewnątrz.

```bash
sudo docker logs -f calert                      # na żywo, przy teście alertu
sudo docker exec calert cat /app/config/message.tmpl
```

W logach szukasz pary linii: `dispatching alerts to google chat` (calert
przyjął) i zaraz po niej `"POST http://calert:6000/dispatch ... - 200`
(Alertmanager dostał odpowiedź). Brak drugiej linii albo kod inny niż 200
oznacza problem po stronie calert albo webhooka Chatu.

Szablon (`calert-message.tmpl.j2`) używa znaczników Go, nie Jinja - stąd blok
`{% raw %}` w źródle. Buduje ikonę zależną od `severity` i `status`, pogrubione
`summary`, opis, etykiety (alert, maszyna, waga, stan, punkt montowania, job)
oraz stopkę z odnośnikami do paneli. `thread_ttl = "12h"` zbiera alerty o tej
samej przyczynie w jeden wątek.

## 9. Reguły - co znaczą i co zrobić

15 reguł w 4 grupach (`alerts.yml.j2`). Reguł jest celowo mało: alert, który
odzywa się codziennie, przestaje być czytany. Klauzula `for` wymaga spełnienia
warunku **nieprzerwanie** - przy `scrape_interval: 15s` wartość `10m` to 40
kolejnych sprawdzeń, więc chwilowy skok nic nie wyśle.

| Alert | Waga / `for` | Pierwszy ruch |
|---|---|---|
| `MaszynaNieodpowiada` | critical / 3m | `ssh` na maszynę, a jak nie wchodzi - konsola w Proxmoksie |
| `AplikacjaNieodpowiada` | critical / 5m | `docker ps` na `wolffire-dev-app-1`, logi php-fpm |
| `BazaNieodpowiada` | critical / 3m | `systemctl status postgresql` na `wolffire-prod-db-1` |
| `RedisNieodpowiada` | critical / 3m | `redis-cli ping`; kolejki Horizona stoją |
| `BrakMiejscaNaDysku` | critical / 5m | `docker system prune`, rotacja logów, natychmiast |
| `EksporterNieodpowiada` | warning / 10m | `systemctl status prometheus-node-exporter`, `docker ps` |
| `KontenerRestartujeSie` | warning / 10m | `docker logs --tail 100 <nazwa>` - szukaj przyczyny wyjścia |
| `KontenerZatrzymany` | warning / 2m | `docker ps -a`, potem logi kontenera `Exited`; krótkie `for`, bo compose nie zostawia stanu `stopped` przy wdrożeniach |
| `MaloMiejscaNaDysku`, `DyskZapelniSieWDobe` | warning / 15m, 1h | `df -h`, `docker system df`, `du -sh /var/lib/docker/*` |
| `WysokieZuzyciePamieci`, `WysokieObciazenieCPU` | warning / 20m | `top`; sprawdź najpierw, czy to nie trwający build |
| `RedisBliskoLimituPamieci` | warning / 10m | pilne przy `noeviction`: 100% to błędy zapisu, nie spowolnienie |
| `PostgresBliskoLimituPolaczen` | warning / 10m | `pg_stat_activity`; rozwiązaniem jest PgBouncer, nie większe `max_connections` |
| `Watchdog` | none | nic; niepokoić ma jego **zniknięcie** |

`inhibit_rules` wycisza wszystkie alerty `warning` z maszyny, która ma aktywny
`MaszynaNieodpowiada` - jedna padnięta maszyna daje jedno powiadomienie, nie
sześć.

## 10. Troubleshooting

Pierwszy ruch przy każdym z poniższych objawów jest ten sam: `make status`
(albo `make test-infra`, gdy chcesz też sprawdzić Terraform i Ansible) - patrz
§1. Dopiero gdy wiadomo, **co** nie działa, schodzimy do komend niżej.

### Cel jest DOWN w `/targets`

Po kolei, od najtańszego:

```bash
# 1. Co dokładnie mówi Prometheus - lastError jest konkretny
ssh wf-monitoring-1 'curl -s http://10.0.120.20:9090/api/v1/targets \
  | jq -r ".data.activeTargets[] | select(.health!=\"up\") | \"\(.scrapeUrl) \(.lastError)\""'

# 2. Czy eksporter żyje na maszynie docelowej i odpowiada lokalnie.
#    Jeśli odpowiada, problem jest w sieci, nie w usłudze.
ssh wf-<maszyna> 'systemctl status prometheus-node-exporter --no-pager; curl -s localhost:9100/metrics | head -3'

# 3. Czy firewall przepuszcza z adresu Prometheusa
ssh wf-<maszyna> 'sudo ufw status numbered | grep -E "9100|8081|9187|9121|9323"'

# 4. Czy Prometheus dochodzi tam z siebie
ssh wf-monitoring-1 'curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://<ip>:9100/metrics'
```

| `lastError` | Znaczenie |
|---|---|
| `connection refused` | usługa nie działa na tej maszynie |
| `i/o timeout` | pakiety nie dochodzą - UFW albo grupa bezpieczeństwa w Proxmoksie |
| `context deadline exceeded` | eksporter odpowiada, ale za wolno (przeciążona maszyna) |
| `no such host` | adres z inventory się nie zgadza |

Porty eksporterów muszą się zgadzać z grupą `metrics` w Terraformie i regułami
UFW z roli bazowej. Zmiana portu w `roles/monitoring/defaults/main.yml` bez
zmiany w obu tych miejscach kończy się dokładnie tym objawem.

### Alert nie doszedł na kanał

Ścieżka ma pięć ogniw. Sprawdzaj w tej kolejności:

```bash
ssh wf-monitoring-1     # dalej korzystamy ze zmiennych $P, $A i $AM z góry

# 1. Czy reguła firuje w Prometheusie. Jeśli nie, problem jest w wyrażeniu
#    albo w `for`, nie w powiadamianiu
curl -s $P/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname) \(.state)"'

# 2. Czy alert dotarł do Alertmanagera
$AM alert query

# 3. Czy nie jest wyciszony albo zdławiony przez inhibit_rules
curl -s $A/api/v2/alerts | jq -r '.[] | select((.status.silencedBy|length)>0
  or (.status.inhibitedBy|length)>0) | "\(.labels.alertname) \(.status.silencedBy)"'

# 4. Dokąd trasa go kieruje
$AM config routes

# 5a. Kanał Chat: czy calert dostał i wypchnął
sudo docker logs --tail 20 calert

# 5b. Kanał e-mail: czy subskrypcja żyje
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:us-east-1:195275647734:wolffire-alerts
```

Najczęstsze rozstrzygnięcia:

- Firuje w Prometheusie, nie ma go w Alertmanagerze -> sekcja `alerting`
  w `prometheus.yml` i sieć Dockera między kontenerami.
- Jest, `silencedBy` niepuste -> ktoś zostawił wyciszenie, `silence expire <id>`.
- Jest, nie jest wyciszony, `severity=none` -> trafił na trasę `null` (tak
  właśnie działa `Watchdog` i to jest poprawne).
- Chat dostaje, e-mail nie -> subskrypcja SNS w stanie `Deleted`, patrz §6.
- E-mail dochodzi, Chat nie -> alert utknął na trasie `sns-email` i nie
  dopasował żadnej trasy `gchat`; `$AM config routes test severity=warning`
  musi pokazać dwa odbiorcy - patrz pułapka routingu w §5.
- Nic nie dochodzi i **nie ma `Watchdog` w Alertmanagerze** -> padł cały potok,
  nie pojedynczy kanał; zacznij od `docker compose ps`.

### Pozostałe

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `curl: (7) ... localhost:9090` z `monitoring-1` | port tylko na adresie prywatnym | `10.0.120.20:9090` |
| `amtool: command not found` | uruchamiane na hoście, nie w kontenerze | `sudo docker exec alertmanager amtool ...` |
| `amtool: invalid label` przy `alert add` | adnotacja ze spacją bez cudzysłowów | `--annotation='summary="tresc ze spacjami"'` |
| LogQL zwraca pustą listę | zła etykieta, wąski zakres czasu albo host bez Alloya | `label/<nazwa>/values`; dodaj `start=` |
| Puste tylko panele logów | Alloy padł na maszynie źródłowej | `systemctl status alloy` tam |
| Zmiana w `alerts.yml` nie działa | brak przeładowania konfiguracji | `curl -X POST http://10.0.120.20:9090/-/reload` |
| Prometheus nie widzi zmiany po Ansible | podmontowany plik zamiast katalogu | montujemy katalogi (`./prometheus/`) - komentarz w `compose.yml.j2` |
| 502 na `grafana.wolffire.dev` | tunel doszedł, usługa nie odpowiada | `docker compose ps` na `monitoring-1` |
| Błąd 1033 | `cloudflared` nie działa na maszynie usługi | `systemctl status cloudflared` **na `monitoring-1`**, nie na bastionie |

Powiązane: [RUNBOOK §7](../RUNBOOK.md), [dowody/prometheus.md](../dowody/prometheus.md),
[dowody/alertmanager.md](../dowody/alertmanager.md), [dowody/loki.md](../dowody/loki.md),
[dowody/grafana.md](../dowody/grafana.md), [docker.md](docker.md).
