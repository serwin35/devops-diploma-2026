# Kubernetes (k3s) - komendy

Produkcja aplikacji WolfFire działa na klastrze k3s: `k3s-server-1`
(control-plane) plus `k3s-agent-1` i `k3s-agent-2`. Dokument ułożony według
zadań ("chcę zobaczyć logi produkcji", "chcę wycofać wdrożenie"), nie
alfabetycznie po podkomendach. Skrót operacyjny jest w
[`RUNBOOK.md` sekcja 3](../RUNBOOK.md#3-kubernetes) - tu wersja pełna.

**Zanim zejdziesz do surowych komend**: `make status` (z korzenia repozytorium,
na stacji roboczej) daje jeden rzut oka na całość - `get nodes`, `get pods -n
wolffire`, kontenery dev i kody HTTP obu środowisk. Wyłącznie odczyt. Jeśli
wszystko jest zielone, dalej czytać nie trzeba; jeśli nie, reszta tego dokumentu
mówi, czym to rozebrać na części.

> k3s v1.31.5+k3s1, Ubuntu 24.04, containerd 1.7.23. Aplikacja: chart
> `helm/wolffire` w namespace `wolffire`. **Zweryfikowano na żywo 2026-08-05**:
> `get nodes` (3/3 Ready), `get pods -n wolffire` (6/6 Running), `helm list`
> (rewizja 10, tag `5fbbbc8`), `helm history`, `top nodes`, `describe ingress`,
> `exec ... php artisan`.

---

## 0. Dostęp: kubectl jest wyłącznie na serwerze

**Nie ma lokalnego `kubectl`.** Na stacji roboczej nie ma ani kubeconfigu, ani
klienta. Kubeconfig (`/etc/rancher/k3s/k3s.yaml`) leży na `k3s-server-1`
i czyta go wyłącznie root. Sam klient nie jest osobnym pakietem - jest wbudowany
w binarkę k3s i wywołuje się go jako `k3s kubectl`. Stąd jedyna poprawna
ścieżka:

```bash
ssh wf-k3s-server-1
sudo k3s kubectl get nodes

# Alias skracajacy reszte sesji (wraca przy kolejnym logowaniu)
echo "alias k='sudo k3s kubectl'" >> ~/.bashrc && source ~/.bashrc
```

**W dalszej części dokumentu `k` = `sudo k3s kubectl`.** Dwa komunikaty, o które
rozbija się pierwsza próba: `command not found: kubectl` znaczy, że szukasz
klienta, którego nie ma, a `The connection to the server localhost:8080 was
refused` - że zabrakło `sudo`, kubeconfig był nieczytelny i klient poszedł pod
domyślny adres.

Helm to osobna binarka (`/usr/local/bin/helm`, instaluje ją rola
`wolffire_prod`) i **nie dziedziczy** kubeconfigu z k3s - każde wywołanie
wymaga jawnego `--kubeconfig /etc/rancher/k3s/k3s.yaml`, też pod `sudo`.

Bastion (`wf-bastion-1`) występuje tu wyłącznie jako `ProxyJump` dla SSH
([`RUNBOOK.md` sekcja 2](../RUNBOOK.md#2-dostęp-do-maszyn)). Ruch HTTP aplikacji
przez niego **nie** idzie - patrz sekcja 2.

---

## 1. Co stoi w klastrze

Chart instaluje cztery deploymenty, dwa serwisy, ingress i Job migracji jako
hook. Wszystko w namespace `wolffire`.

```bash
k get deploy,rs,pods -n wolffire -o wide
k get svc,ingress -n wolffire
```

Stan z 2026-08-05 (skrót wyjścia, 6 podów `Running`):

```
NAME                                  READY   STATUS    RESTARTS   AGE   IP           NODE
wolffire-horizon-6cf6657566-xjs8t     1/1     Running   0          9h    10.42.1.26   k3s-agent-2
wolffire-nginx-6cf6988fcb-7shqq       1/1     Running   0          76m   10.42.2.16   k3s-agent-1
wolffire-php-55f5cd7998-7r5rd         1/1     Running   0          10h   10.42.0.13   k3s-server-1
wolffire-scheduler-5465b667dd-9vh4q   1/1     Running   0          10h   10.42.1.23   k3s-agent-2
```

| Komponent | Repliki | Obraz | Komenda | Strategia |
|---|---|---|---|---|
| `wolffire-php` | 2 | `.../php:<tag>` | domyślna (php-fpm 9000) | RollingUpdate |
| `wolffire-nginx` | 2 | `.../nginx:<tag>` | domyślna (nasłuch 8080) | RollingUpdate |
| `wolffire-horizon` | 1 | `.../php:<tag>` | `php artisan horizon` | **Recreate** |
| `wolffire-scheduler` | 1 | `.../php:<tag>` | `php artisan schedule:work` | **Recreate** |
| `wolffire-migrate` | Job | `.../php:<tag>` | `php artisan migrate --force` | hook pre-install/pre-upgrade |

`Recreate` przy Horizonie i schedulerze nie jest przypadkiem: dwie wersje
Horizona przetwarzające te same kolejki w trakcie rolloutu wykonałyby joby na
starym kodzie tuż po migracji bazy, a dwa schedulery odpaliłyby każde zadanie
podwójnie.

Job migracji normalnie **nie jest widoczny** - `helm.sh/hook-delete-policy`
kasuje go po sukcesie. Jeśli `k get jobs -n wolffire` go pokazuje, ostatnia
migracja **padła** i Job został do obejrzenia
(`k logs job/wolffire-migrate -n wolffire`). Postgres i Redis **nie stoją
w klastrze** - są na `10.0.140.10`, więc `k get pods -A` nigdy ich nie pokaże
i to jest stan prawidłowy ([`ARCHITECTURE.md`](../ARCHITECTURE.md), sekcja 7).

---

## 2. Jak ruch z internetu dociera do poda

```
przegladarka
  -> Cloudflare (CNAME wolffire.dev -> <id>.cfargotunnel.com, proxied)
  -> tunel wf-prod
  -> cloudflared jako usluga systemd NA k3s-server-1 (origin 10.0.130.10:80)
  -> ServiceLB k3s (daemonset svclb-traefik, port 80 na kazdym wezle)
  -> Service traefik (LoadBalancer, kube-system) -> pod traefik
  -> Ingress "wolffire" (regula host: wolffire.dev)
  -> Service wolffire-nginx :80 -> pod nginx :8080
  -> fastcgi_pass wolffire-php.wolffire.svc.cluster.local:9000 -> pod php-fpm
```

Dwie rzeczy bywają mylone. Po pierwsze, **bastion nie jest w tej ścieżce**:
`cloudflared` działa na maszynie z usługą, czyli na `k3s-server-1`
(`ansible/playbook.yml`, hosty `k3s_server`). Ruch nie przechodzi między
segmentami sieci i nie wymaga reguły firewalla dla portu 80 między `dmz` a
`k3s`; bastion obsługuje wyłącznie SSH. Po drugie, **TLS terminuje się na
Cloudflare**, nie w klastrze - dlatego `ingress.tls` w `values.yaml` jest puste,
a Ingress ma tylko port 80.

Sprawdzenie każdego przeskoku, od dołu ku górze:

```bash
k exec -n wolffire deploy/wolffire-php -- php artisan --version          # 5. aplikacja
k exec -n wolffire deploy/wolffire-nginx -- wget -qO- localhost:8080/up  # 4. nginx -> fastcgi
k get endpoints -n wolffire                                             # 3. Service ma pody
k describe ingress wolffire -n wolffire                                  # 2. regula Traefika
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: wolffire.dev" http://10.0.130.10/up
systemctl is-active cloudflared                                          # 0. tunel
```

Wynik z 2026-08-05: `curl` zwraca `200`, `cloudflared` jest `active`,
`describe ingress` pokazuje backend
`wolffire-nginx:http (10.42.1.28:8080,10.42.2.16:8080)`. Service `traefik` ma
`EXTERNAL-IP 10.0.130.10,10.0.130.11,10.0.130.12` - ServiceLB publikuje port 80
na **każdym** węźle i dlatego drain jednego węzła nie zrywa wejścia (sekcja 6).

---

## 3. Zadania codzienne

### Chcę zobaczyć, czy wszystko żyje

```bash
k get nodes -o wide                      # wezly, wersje, adresy, runtime
k get pods -n wolffire -o wide           # pody aplikacji wraz z wezlem
k get pods -A                            # takze kube-system
```

`-o wide` przy podach jest istotne - pokazuje kolumnę `NODE`, bez której nie
widać rozłożenia replik i demonstracja z `drain` traci sens.

### Chcę zobaczyć logi produkcji

```bash
k logs -f deploy/wolffire-php -n wolffire                  # kubectl sam wybiera pod
k logs -f -l app.kubernetes.io/component=php -n wolffire --max-log-requests 5
k logs <pod> -n wolffire --tail 100 --timestamps
k logs deploy/wolffire-horizon -n wolffire --since 15m
k logs <pod> -n wolffire --previous       # log kontenera, ktory ZGINAL
```

`--previous` to jedyny sposób, żeby zobaczyć, co aplikacja powiedziała tuż przed
śmiercią. Zwykłe `logs` po restarcie pokazuje log nowego, świeżo wstałego
kontenera - najczęściej pusty albo mylący.

Etykieta `app.kubernetes.io/component` (helper `wolffire.selectorLabels`)
przyjmuje wartości `php`, `nginx`, `horizon`, `scheduler`, `migrate`. Te same
logi trafiają do Loki - aplikacja pisze na `stderr` (`LOG_CHANNEL=stderr`),
zbiera je Alloy, zapytania opisuje [`monitoring.md`](monitoring.md).

### Chcę wejść do kontenera

```bash
k exec -it deploy/wolffire-php -n wolffire -- sh
```

Obrazy nie mają basha - `sh` jest jedyną powłoką. Kontener działa jako uid 1000
(`runAsNonRoot: true`, `capabilities: drop ALL`), więc `apt install` w środku
nie zadziała i nie powinien.

### Chcę zrestartować albo wycofać

```bash
k rollout restart deploy/wolffire-php -n wolffire
k rollout status deploy/wolffire-php -n wolffire     # czeka do konca rolloutu
k rollout history deploy/wolffire-php -n wolffire
k rollout undo deploy/wolffire-php -n wolffire       # o jedna rewizje
k rollout undo deploy/wolffire-php -n wolffire --to-revision=3
```

`rollout restart` podmienia pody po kolei bez zmiany obrazu ani wartości chartu -
jest bezpieczniejszy niż `delete pod`, bo respektuje strategię i sondy (przy
`Recreate` oznacza jednak krótką przerwę). **Uwaga na rozjazd stanu:**
`rollout undo` cofa tylko obiekt Deployment, a Helm nadal uważa, że wdrożony
jest tag z ostatniego `upgrade` - najbliższy przebieg CD albo Ansible nadpisze
cofnięty obraz z powrotem. Wycofaniem całego wdrożenia jest `helm rollback`
(sekcja 5).

### Chcę zobaczyć zdarzenia i zużycie

```bash
k get events -n wolffire --sort-by=.lastTimestamp | tail -20
k get events -n wolffire --field-selector type=Warning
k top nodes && k top pods -n wolffire
```

Bez `--sort-by` zdarzenia lecą w kolejności losowej i lista jest bezużyteczna.
`No resources found` to dobra wiadomość: retencja zdarzeń to domyślnie godzina,
więc pusty wynik znaczy "od godziny nic się nie stało".

```
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
k3s-agent-1    17m          0%     664Mi           26%
k3s-agent-2    24m          1%     1428Mi          57%
k3s-server-1   43m          2%     1200Mi          40%

wolffire-horizon-...   6m    730Mi     <- limit 768Mi, patrz nizej
wolffire-php-...       2m     48Mi
```

`top` działa dzięki `metrics-server` z `kube-system`; `error: Metrics API not
available` znaczy, że ten pod nie stoi. **Horizon siedzi tuż pod limitem 768Mi**
i jest to świadome ustawienie - domyślne 512Mi z `values.yaml` kończyło się
`OOMKilled` w pętli. Przy takim zapasie każdy dodatkowy proces PHP w tym podzie
wywala kontener (sekcja 4).

---

## 4. Operacje na aplikacji wewnątrz poda

Wszystko poniżej uruchamiaj w **deploymencie `wolffire-php`**, nie w Horizonie.

```bash
k exec -n wolffire deploy/wolffire-php -- php artisan migrate:status
k exec -n wolffire deploy/wolffire-php -- php artisan horizon:status
k exec -n wolffire deploy/wolffire-php -- php artisan queue:monitor default
k exec -n wolffire deploy/wolffire-php -- php artisan queue:failed
k exec -n wolffire deploy/wolffire-php -- php artisan cache:clear
k exec -it -n wolffire deploy/wolffire-php -- php artisan tinker
```

Wynik `queue:monitor` z 2026-08-05: `[redis] default ... [0] OK`, zero zadań
oczekujących.

> **Ostrzeżenie sprawdzone na żywo.** `k exec deploy/wolffire-horizon -- php artisan horizon:status`
> zakończył się komunikatem `command terminated with exit code 137` i
> **zrestartował poda Horizona**. Limit 768Mi jest ciasno dopasowany do samego
> Horizona (master, supervisory, workery), a dodatkowy proces PHP przekracza
> cgroup i kernel ubija kontener. Te same komendy w podzie `wolffire-php`
> (limit 512Mi, zużycie ok. 48Mi) działają bez problemu i czytają dokładnie ten
> sam Redis. Zasada: **artisan zawsze w podzie php**.

`php artisan tinker` w podzie produkcyjnym pisze do **prawdziwej bazy**
(`10.0.140.10`). Do odczytu jest dobry, do zapisu - tylko świadomie.

Czego tu nie ma i być nie powinno: ręcznego `php artisan migrate` (robi to Job
hookowy, żeby migracje nie ruszały równolegle w każdej replice) oraz ręcznego
`config:cache` (cache powstaje przy budowaniu obrazu, pod jest z założenia
niemodyfikowalny, a ręczne odpalenie zniknie przy pierwszym restarcie).

---

## 5. Helm

### Kto normalnie wdraża

Ręczny `helm upgrade` to **wyjątek**, nie procedura. **CD** (GitHub Actions,
`build.yml`, job `deploy-prod`) po zielonym buildzie łączy się po SSH przez
bastion na `k3s-server-1` i woła `helm upgrade --install ... --set
image.php.tag=<sha> --set image.nginx.tag=<sha>`. **Ansible** (rola
`wolffire_prod`) kopiuje chart do `/opt/wolffire-chart` i generuje
`/opt/wolffire-values.yaml` (tryb `0600`, sekrety), po czym woła
`helm upgrade --install` **tylko wtedy**, gdy zmienił się chart, plik values
albo release nie jest wdrożony - a zanim to zrobi, **odczytuje tag wdrożony
przez CD** i podstawia go zamiast domyślnego `latest`, żeby przebieg playbooka
nie cofał produkcji do starszego obrazu. Values leżą na maszynie, a nie
w repozytorium: dzięki temu CD nie musi znać żadnego sekretu aplikacji.

### Przegląd i wdrożony tag

```bash
sudo helm list -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml
sudo helm history wolffire -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml

sudo helm get values wolffire -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml -o json \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['image'])"
```

```
NAME      NAMESPACE  REVISION  UPDATED                  STATUS    CHART           APP VERSION
wolffire  wolffire   10        2026-08-05 20:06:24 UTC  deployed  wolffire-0.1.0  1.0.0

{'nginx': {..., 'tag': '5fbbbc8'}, 'php': {..., 'tag': '5fbbbc8'}}
```

> **`helm get values` bez filtra wypisuje sekrety** - hasło do bazy, hasło
> Redisa, `APP_KEY` i token do GHCR. Nie wklejaj surowego wyjścia do zrzutu
> ekranu ani do logu. Z tego samego powodu rola `wolffire_prod` używa
> `helm list` (same metadane), a nie `helm status` (zwraca sekcję `config`
> z wartościami wdrożenia).

### Wycofanie

```bash
sudo helm rollback wolffire 9 -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml --wait
```

`helm rollback` cofa **cały** release naraz: tag obrazu, ConfigMapy, Secrety
i limity - w przeciwieństwie do `kubectl rollout undo`, które dotyka jednego
Deploymentu. To jest właściwa komenda po nieudanym wdrożeniu. Czego nie cofa:
migracji bazy. Job jest hookiem `pre-upgrade`, więc przy rollbacku wykona się na
nowo (na starym obrazie), ale wykonanych migracji nie odwróci - kolumna
skasowana migracją zostaje skasowana.

### Wdrożenie ręczne

```bash
sudo helm upgrade wolffire /opt/wolffire-chart \
  --kubeconfig /etc/rancher/k3s/k3s.yaml -n wolffire \
  -f /opt/wolffire-values.yaml \
  --set image.php.tag=<sha> --set image.nginx.tag=<sha> \
  --wait --timeout 10m

# Podglad bez dotykania klastra
sudo helm template wolffire /opt/wolffire-chart -f /opt/wolffire-values.yaml | head -60
```

1. **`-f /opt/wolffire-values.yaml` jest obowiązkowe.** Bez niego `required`
   w szablonach zatrzyma instalację komunikatem "Podaj app.key ..." - i dobrze,
   bo alternatywą byłaby aplikacja z pustym hasłem.
2. **`--set image.php.tag`, nie `image.tag`.** Chart ma osobne tagi dla php
   i nginx; samo `image.tag` nie zmieni niczego, a `upgrade` zakończy się
   "pomyślnie" ze starym obrazem.
3. **`--wait` czeka na `Ready` wszystkich podów** i w razie problemu wisi do
   timeoutu. Obserwuj w drugim terminalu `k get pods -n wolffire -w`.

---

## 6. Scenariusz: przełożenie ruchu między węzłami (drain / uncordon)

Najmocniejszy pojedynczy pokaz Kubernetesa na obronie: wyłączamy węzeł
z eksploatacji, pody wstają na pozostałych, a strona **ani razu nie zwraca
błędu**. Dwa terminale.

### Terminal A: pętla dowodowa

Uruchom **zanim** cokolwiek zrobisz z węzłem i nie zatrzymuj do końca pokazu:

```bash
while true; do
  printf '%s ' "$(date +%H:%M:%S)"
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: wolffire.dev" http://10.0.130.10/up
  sleep 1
done
```

Oczekiwane wyjście to kolumna dwustek (`20:41:03 200`, `20:41:04 200`, ...).
Pętla idzie przez pełną ścieżkę - od ServiceLB do poda php - więc `502` albo
`000` w trakcie migracji podów jest prawdziwym sygnałem, nie artefaktem testu.

### Terminal B: kroki na klastrze

```bash
# 1. Stan wyjsciowy - zapamietaj, ktore pody sa na agent-1
k get pods -n wolffire -o wide

# 2. Wylaczenie wezla z planowania i wypchniecie podow
k drain k3s-agent-1 --ignore-daemonsets --delete-emptydir-data

# 3. Wezel jest SchedulingDisabled, pody wstaja gdzie indziej
k get nodes
k get pods -n wolffire -o wide -w        # Ctrl+C, gdy wszystko Running

# 4. Potwierdzenie, ze Service ma komplet endpointow
k get endpoints -n wolffire

# 5. Przywrocenie wezla do planowania
k uncordon k3s-agent-1 && k get nodes
```

Obie flagi `drain` są konieczne. `--ignore-daemonsets`, bo `svclb-traefik` jest
DaemonSetem, którego z definicji nie da się przenieść - bez tej flagi `drain`
odmawia startu. `--delete-emptydir-data`, bo pody php mają `storage/app` na
`emptyDir` i drain zatrzymałby się z ostrzeżeniem o utracie danych; utrata jest
tu akceptowana i udokumentowana jako ograniczenie dema.

Po `uncordon` pody **nie wracają same** - Kubernetes nie przenosi działających
podów bez powodu. Żeby rozłożyć je z powrotem:
`k rollout restart deploy/wolffire-php deploy/wolffire-nginx -n wolffire`.

### Dlaczego ruch nie ginie

Wejście: `svclb-traefik` jest DaemonSetem, a Service `traefik` ma `EXTERNAL-IP`
na wszystkich trzech węzłach; `cloudflared` celuje w `10.0.130.10`, a serwera
w tym demie nie drenujemy. nginx: 2 repliki na różnych węzłach, readiness na
`/up` przez fastcgi, więc Service usuwa pod z endpointów, zanim ten przestanie
odpowiadać. php: 2 repliki, sonda TCP na porcie fpm.

Czego ten pokaz **nie** udowadnia: odporności na utratę `k3s-server-1`.
Control-plane jest jednowęzłowy i jest to znane ograniczenie
([`ARCHITECTURE.md`](../ARCHITECTURE.md), sekcja 10) - drain na serwerze
wypchnąłby też poda Traefika i przerwa byłaby widoczna. Uzupełnieniem pokazu
jest `k scale deploy/wolffire-php -n wolffire --replicas=3`; też rozjeżdża stan
z chartem, więc trwała zmiana idzie przez `--set php.replicaCount=3`.

---

## 7. Troubleshooting

### `CrashLoopBackOff` - pod wstaje i zaraz pada

Kolejność jest istotna: `describe` mówi **dlaczego**, `logs --previous` mówi
**co aplikacja zdążyła powiedzieć**.

```bash
k get pods -n wolffire                   # 1. ile restartow, jak dawno
k describe pod <pod> -n wolffire         # 2. sekcja "Last State"
k logs <pod> -n wolffire --previous      # 3. log kontenera, ktory zginal
```

`OOMKilled` widać **tylko** w `Last State`, w logach nie ma po nim śladu.

| `Exit Code` / `Reason` | Znaczenie | Co dalej |
|---|---|---|
| `137` + `OOMKilled` | Kernel ubił kontener za przekroczenie limitu pamięci | Porównaj `Limits` z `k top pods`; limity w `values.yaml` i `values-prod.yaml.j2` |
| `1` + `Error` | Aplikacja padła sama | `logs --previous`: zwykle brak zmiennej środowiskowej albo baza nieosiągalna |
| `CreateContainerConfigError` | Brakuje ConfigMapy albo Secretu z `envFrom` | `k get cm,secret -n wolffire` |

Realny przykład z tego projektu: Horizon z domyślnym limitem 512Mi wpadał
w pętlę `exit 137` trzy sekundy po starcie. Naprawa jest w
`ansible/roles/wolffire_prod/templates/values-prod.yaml.j2`.

### `ImagePullBackOff` / `ErrImagePull`

GHCR jest **prywatny**. Chart tworzy Secret `wolffire-ghcr` (typ
`kubernetes.io/dockerconfigjson`) z wartości `ghcrUsername` i `ghcrToken`;
tokenowi wystarcza zakres `read:packages`.

```bash
k describe pod <pod> -n wolffire | sed -n '/Events/,$p'    # pelny komunikat
k get secret wolffire-ghcr -n wolffire -o jsonpath='{.type}'; echo
k get deploy wolffire-php -n wolffire -o jsonpath='{.spec.template.spec.imagePullSecrets}'; echo
```

| Komunikat w `Events` | Przyczyna |
|---|---|
| `401 Unauthorized` | Token wygasł albo jest zły - popraw `ghcr_token` w SOPS i przepuść rolę `wolffire_prod` |
| `denied` / `403` | Token bez `read:packages` albo pakiet niepowiązany z repozytorium |
| `manifest unknown` | Tag nie istnieje w rejestrze - literówka w `--set image.php.tag` |

Istnieje jeszcze druga kopia tego sekretu, `wolffire-migrate-ghcr`: hooki
startują, zanim helm utworzy zwykłe zasoby release'u, więc bez niej Job migracji
przy pierwszej instalacji nie miałby czym pobrać obrazu.

### `Pending` - pod nie ma gdzie wstać

```bash
k describe pod <pod> -n wolffire | sed -n '/Events/,$p'
k describe nodes | grep -A6 "Allocated resources"
```

`0/3 nodes are available: Insufficient memory` znaczy, że suma `requests`
przekracza pojemność - porównaj `requests` z `values.yaml` z `k top nodes`.
`untolerated taint {node.kubernetes.io/unschedulable}` znaczy, że węzeł został
zadrenowany i nikt nie zrobił `uncordon`. `unbound immediate
PersistentVolumeClaims` w tym projekcie wystąpić nie powinno - aplikacja używa
`emptyDir`.

### `helm upgrade` wisi do timeoutu

`--wait` czeka, aż wszystkie pody będą `Ready`. Nie zabijaj go w połowie -
przerwany upgrade zostawia release w stanie `pending-upgrade`. Obserwuj
w drugim terminalu `k get pods -n wolffire -w`. Jeśli release już utknął:

```bash
sudo helm list -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml --all
sudo helm rollback wolffire <ostatnia-dzialajaca> -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml
```

### Zbiorcza tabela

| Objaw | Sprawdź |
|---|---|
| `command not found: kubectl` | `sudo k3s kubectl`, alias `k` (sekcja 0) |
| `connection to localhost:8080 refused` | Brak `sudo`; dla helma brak `--kubeconfig` |
| Pod `CrashLoopBackOff` | `describe` -> `Last State`, potem `logs --previous` |
| Pod `OOMKilled` | `k top pods` kontra `Limits` w `describe` |
| Pod `ImagePullBackOff` | Secret `wolffire-ghcr`, zakres tokenu, istnienie tagu |
| Pod `Pending` | `describe pod` -> `Events`; `k get nodes` (czy nie `SchedulingDisabled`) |
| `502` z Traefika | `k get endpoints -n wolffire` - pusty znaczy, że żaden pod nginx nie jest `Ready` |
| Strona nie odpowiada, pody zdrowe | `systemctl is-active cloudflared`, potem `curl -H "Host: ..."` |
| Migracje nie przeszły | `k get jobs -n wolffire`, `k logs job/wolffire-migrate -n wolffire` |
| Po `drain` pody nie wstają | Za mało zasobów na pozostałych węzłach: `k describe pod` -> `Events` |

---

## Zobacz też

- [`RUNBOOK.md` sekcja 3](../RUNBOOK.md#3-kubernetes) - skrót operacyjny na obronę
- [`docker.md`](docker.md) - to samo dla środowiska dev na Compose
- [`monitoring.md`](monitoring.md) - metryki i logi klastra w Grafanie
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) - dlaczego baza stoi poza klastrem
- `helm/wolffire/` - źródło wszystkich nazw i wartości użytych wyżej
