# Monitoring - komendy

Stos stoi na `monitoring-1` w Docker Compose: Prometheus, Grafana, Loki,
Alertmanager, calert (adapter do Google Chat). Wszystkie porty są
**opublikowane na adresie prywatnym maszyny (`10.0.120.20`), nie na
`localhost`** - `curl localhost:9090` z tej samej maszyny kończy się
`Connection refused`, nawet w powłoce na `monitoring-1`. Używaj zawsze adresu
prywatnego albo tunelu SSH.

> **Zweryfikowano na żywo** 2026-08-05: 19/19 celów Prometheusa `up`,
> 15 reguł alertowych w 4 grupach, Loki z logami z 9/9 hostów, Grafana
> `/api/health` -> `database: ok`, `amtool` wewnątrz kontenera `alertmanager`.

---

## Dostęp

```bash
# Tunel - panel w przeglądarce z pominięciem Cloudflare Access
ssh -L 9090:10.0.120.20:9090 wf-bastion-1   # -> http://localhost:9090
ssh -L 3000:10.0.120.20:3000 wf-bastion-1   # -> http://localhost:3000 (Grafana)

# Bezpośrednio z maszyny, adresem prywatnym (NIE localhost)
ssh wf-monitoring-1
curl -s http://10.0.120.20:9090/-/ready
```

## PromQL przydatne na obronę

| Zapytanie | Co pokazuje |
|---|---|
| `up` | 1/0 dla każdego celu - najszybszy dowód, że coś żyje/nie żyje |
| `sum(up) / count(up)` | Ułamek celów `up` - jedna liczba na cały klaster monitoringu |
| `rate(node_cpu_seconds_total{mode="idle"}[5m])` | Zużycie CPU w oknie 5 min, per rdzeń |
| `rate(container_cpu_usage_seconds_total{name=~"wolffire.*"}[5m])` | CPU kontenerów aplikacji |
| `predict_linear(node_filesystem_avail_bytes[6h], 4*3600)` | Prognoza zapełnienia dysku za 4h na podstawie ostatnich 6h - pokazuje trend, nie tylko stan |
| `phpfpm_processes_total{state="active"}` | Aktywne workery PHP-FPM (eksporter `wolffire`) |
| `ALERTS{alertstate="firing"}` | Wszystkie aktywne alerty wprost z silnika Prometheusa |

Uruchamiane w przeglądarce na `https://prometheus.wolffire.dev/graph`, albo
przez API poniżej.

## API Prometheusa

```bash
ssh wf-monitoring-1

# Cele - job, instancja, health
curl -s http://10.0.120.20:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health)"'

# Ile celów up / ile w sumie
curl -s http://10.0.120.20:9090/api/v1/targets \
  | jq '[.data.activeTargets[] | select(.health=="up")] | length'

# Reguły alertowe (grupy + liczba reguł)
curl -s http://10.0.120.20:9090/api/v1/rules \
  | jq '.data.groups[] | {name, rules: (.rules | length)}'

# Aktywne alerty
curl -s http://10.0.120.20:9090/api/v1/alerts | jq '.data.alerts'

# Gotowość silnika (200 = TSDB załadowany, gotowy na zapytania)
curl -s -o /dev/null -w '%{http_code}\n' http://10.0.120.20:9090/-/ready

# Pojedyncze zapytanie PromQL przez API
curl -sG http://10.0.120.20:9090/api/v1/query --data-urlencode 'query=up'
```

## Alertmanager - amtool i wyciszanie

`amtool` nie jest zainstalowany na hoście - żyje wewnątrz kontenera
`alertmanager`. Wywołuj przez `docker exec`.

```bash
ssh wf-monitoring-1

# Lista aktywnych alertów
sudo docker exec alertmanager amtool alert --alertmanager.url=http://localhost:9093

# Lista wyciszeń
sudo docker exec alertmanager amtool silence --alertmanager.url=http://localhost:9093

# Wyciszenie na 2h - np. planowany restart maszyny, żeby nie zasypać kanału
sudo docker exec alertmanager amtool silence add \
  --alertmanager.url=http://localhost:9093 \
  alertname="InstanceDown" instance="monitoring-1" \
  --duration=2h --comment="planowany restart"

# Zdjęcie wyciszenia przed czasem
sudo docker exec alertmanager amtool silence expire <id> \
  --alertmanager.url=http://localhost:9093

# To samo bez amtool, czystym REST API
curl -s http://10.0.120.20:9093/api/v2/status | jq '.cluster.status'
curl -s http://10.0.120.20:9093/api/v2/alerts | jq length
```

Reguły alertowe leżą w `ansible/roles/monitoring/templates/alerts.yml.j2`
(4 grupy, 15 reguł) - trasa do Google Chat idzie przez `calert`, konfiguracja
w `alertmanager.yml.j2` i `calert.toml.j2`.

## LogQL dla Loki

Etykiety realnie obecne w tym Loki: `job` (`docker` / `systemd-journal`),
`host` (nazwa maszyny bez prefiksu `wf-`), `container`/`service_name`
(nazwa kontenera), `unit` (jednostka systemd, tylko dla `job="systemd-journal"`).

```bash
ssh wf-monitoring-1

# Logi jednego kontenera aplikacji
curl -sG http://10.0.120.20:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="docker", container="wolffire-php"}' \
  --data-urlencode 'limit=20'

# Logi systemowe jednej usługi na jednej maszynie
curl -sG http://10.0.120.20:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="systemd-journal", host="k3s-server-1", unit="k3s.service"}'

# Filtr treści (grep na strumieniu logów)
curl -sG http://10.0.120.20:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="docker", container="wolffire-php"} |= "ERROR"'

# Jakie wartości ma dana etykieta - przydatne, gdy nie pamiętasz nazw
curl -s http://10.0.120.20:3100/loki/api/v1/label/container/values
```

W przeglądarce: Grafana -> Explore -> datasource Loki -> to samo zapytanie
w polu LogQL, z podglądem na żywo.

## Grafana przez API

```bash
ssh wf-monitoring-1

curl -s http://10.0.120.20:3000/api/health              # {"database":"ok",...}

# Endpointy wymagające danych - potrzebują auth (401 bez niego)
curl -s -u admin:<haslo_z_sops> http://10.0.120.20:3000/api/datasources
curl -s -u admin:<haslo_z_sops> http://10.0.120.20:3000/api/search?query=wolffire
```

Hasło admina: `grafana_admin_password` w
`ansible/group_vars/all/secrets.sops.yml` (`sops --decrypt`).

## Częste problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `curl: (7) Failed to connect... localhost:9090` z `monitoring-1` | Port opublikowany tylko na adresie prywatnym, nie na `0.0.0.0`/`localhost` | Użyj `10.0.120.20:9090`, nie `localhost:9090` |
| Cel `down` w `/targets` | UFW blokuje port eksportera z adresu Prometheusa | `sudo ufw status` na maszynie docelowej - sprawdź regułę dla `10.0.120.20` |
| Alert nie dociera na kanał | `calert` padł albo trasa w `alertmanager.yml` się nie zgadza | `docker logs calert`; `curl .../api/v2/status` |
| `amtool: command not found` | Próba uruchomienia na hoście zamiast w kontenerze | `docker exec alertmanager amtool ...` |
| Zapytanie LogQL zwraca pustą listę | Zła nazwa etykiety albo zbyt wąski zakres czasu (domyślnie `query_range` bez `start`/`end` bierze ostatnią godzinę) | `label/<nazwa>/values`, dodaj `--data-urlencode start=...` |
