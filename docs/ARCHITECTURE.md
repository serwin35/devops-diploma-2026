# Architektura - decyzje i uzasadnienia

Dokument opisuje **dlaczego** infrastruktura wygląda tak, a nie inaczej.
Opis *co* gdzie stoi znajduje się w [README](../README.md), a *gdzie w plikach*
to znajdziesz - w [PRZEWODNIK.md](PRZEWODNIK.md).

---

## 1. Dlaczego własny Proxmox, a nie chmura publiczna

Kryterium oceny brzmi „AWS ec2 **lub Virtual Machines**" - maszyny na własnym
hypervisorze liczą się identycznie. Chmura nie daje tu żadnej przewagi, a odbiera:

- **Monitoring jest pamięciożerny.** Prometheus, Grafana, Loki i Alertmanager to
  najcięższy blok całego projektu. Na 32 GB własnego RAM-u dostają tyle, ile
  potrzebują; na kredytach chmurowych trzeba by je dusić.
- **Kubernetes wymaga wielu węzłów, żeby cokolwiek pokazać.** Trzy maszyny k3s
  na własnym żelazie kosztują zero. Dopiero na klastrze wielowęzłowym da się
  zademonstrować `kubectl drain` i przełożenie podów.
- **Reużywalność Terraforma widać dopiero przy skali.** Osiem maszyn z jednego
  modułu to dowód; przy rozliczaniu za godzinę odruchowo ogranicza się liczbę
  zasobów.
- **Brak `terraform destroy` między sesjami.** Infrastruktura stoi cały czas,
  zrzuty ekranu do dokumentacji można robić kiedykolwiek, a przed obroną nic
  nie trzeba odtwarzać.
- **Snapshoty.** Przed demonstracją robi się snapshot wszystkich maszyn - jeśli
  pokaz się wywróci, powrót zajmuje kilkanaście sekund.

**AWS zostaje wyłącznie jako S3**, bo jedno kryterium nazywa go wprost
(„Terraform state w AWS S3"). Bucket na stan, drugi na kopie zapasowe.
Koszt: grosze miesięcznie.

---

## 2. Sieć - cztery segmenty, jeden punkt wejścia

Wszystkie maszyny poza bastionem stoją w prywatnych segmentach SDN z NAT-em.
Bastion jest jedyną maszyną z publicznym adresem i jedyną, do której internet
w ogóle może się dobić - ale wpuszcza wyłącznie SSH.

| Segment | Podsieć | Co zawiera |
|---|---|---|
| `dmz` | 10.0.110.0/24 | Bastion - jedyna maszyna z publicznym adresem |
| `apps` | 10.0.120.0/24 | CI/CD, monitoring, środowisko dev |
| `k3s` | 10.0.130.0/24 | Węzły klastra |
| `dbs` | 10.0.140.0/24 | Postgres i Redis produkcyjne |

Numer segmentu jest jednocześnie trzecim oktetem podsieci (`apps = 120` -> `10.0.120.0/24`),
więc adresacji nie da się rozjechać - wynika z jednej liczby. W strefie Simple nie jest
to tag VLAN: mosty są izolowane bez tagowania, a numer pozostaje czystą konwencją.

Użyta jest strefa SDN typu **Simple**, nie EVPN. EVPN buduje overlay VXLAN między
węzłami klastra - przy jednym fizycznym serwerze nie ma między czym go budować.

### Bastion: jedyny punkt wejścia, wyłącznie SSH

Bastion ma **dwa publiczne adresy** - IPv4 (dodatkowy adres OVH przypięty
wirtualnym MAC-iem, druga karta sieciowa wpięta prosto w `vmbr0`) i IPv6
(z darmowego bloku `/64` routowanego przez OVH na serwer). Mimo to grupa
bezpieczeństwa `bastion` w Terraformie dopuszcza **wyłącznie SSH na porcie
22022** - żadnej reguły dla 80 ani 443. `cloudflared` na tej maszynie w ogóle
nie stoi, więc nie ma czego chronić na warstwie HTTP. Ochronę SSH stanowi
logowanie wyłącznie kluczem, fail2ban i limit `MaxAuthTries`.

Ruch aplikacyjny i panele administracyjne idą **inną drogą**: każda maszyna
usługowa (hypervisor, `cicd-1`, `monitoring-1`, `wolffire-dev-app-1`,
`k3s-server-1`) uruchamia własny `cloudflared` i terminuje własny tunel
lokalnie, celując we własny `localhost` albo adres prywatny. Ten ruch nigdy
nie przechodzi przez bastiona.

Wcześniejsza wersja architektury zakładała jeden tunel na bastionie,
przekazujący połączenia do wszystkich segmentów - wymagało to trasy do
każdego z nich i szerokiego zakresu portów otwartego z `dmz`, a awaria
bastionu odcinała wszystkie panele naraz. Tunel per maszyna (`terraform/main.tf`,
moduły `cloudflare_*`) usuwa oba te problemy: ruch nie opuszcza maszyny,
firewall hypervisora nie potrzebuje reguł międzysegmentowych dla portów
paneli, a awaria jednej usługi nie dotyka pozostałych.

Konsekwencje w regułach firewalla:

- grupa `base`, doczepiana do każdej maszyny, dopuszcza SSH **wyłącznie z
  segmentu `dmz`** - czyli tylko z bastionu - oraz z hypervisora, na czas
  provisioningu;
- grupa `http` dopuszcza z `dmz` ruch aplikacyjny i porty paneli - używane,
  gdy operator loguje się na bastiona i stamtąd łączy się dalej po sieci
  wewnętrznej, a nie przez sam tunel Cloudflare (ten idzie lokalnie na
  maszynie usługowej i nie dotyka `dmz` w ogóle);
- sam bastion nie ma żadnej reguły wejściowej poza obowiązkową grupą `base`
  i portem eksportera metryk.

Wyjątkiem jest zbiór adresów `hypervisor` (bramy wszystkich vnetów) dopuszczony
do SSH. Jest potrzebny wyłącznie na etapie provisioningu - zanim bastion zostanie
skonfigurowany, to hypervisor pełni rolę jump hosta. Po uruchomieniu bastiona
Ansible przełącza się na niego, a SSH hosta (docelowo) zostaje zamknięte dla
adresów spoza listy administratorów.

### IPv6: darmowa trzecia droga wejścia

Router OVH routuje na serwer cały blok `/64` za darmo i traktuje go jako
on-link na `vmbr0`. Host pełni rolę routera dla segmentu `dmz`:

| | |
|---|---|
| Blok OVH | `2001:41d0:602:4f1a::/64` - on-link na `vmbr0` |
| Podprefiks segmentu `dmz` | `2001:41d0:602:4f1a:6e::/80` |
| Brama (host) | `2001:41d0:602:4f1a:6e::1` |
| Bastion | `2001:41d0:602:4f1a:6e::10` |

Indeks podprefiksu to **numer segmentu**, nie kolejna liczba - podprefiks o indeksie 0
zawierałby adres samego hosta, który używa adresu z wyzerowaną częścią hosta.

Router OVH uważa, że cały `/64` leży na jego łączu, więc pyta o adresy przez NDP.
Maszyny stoją jednak za hostem - dlatego host odpowiada w ich imieniu (`ndppd`
z regułą na cały podprefiks) i routuje ruch dalej. Kolejna maszyna w segmencie
dostaje publiczne IPv6 bez żadnej zmiany po stronie hosta. Zweryfikowane na
żywo: `ip -6 addr` na bastionie pokazuje adres globalny, a `ping6` z bastiona
do `2606:4700:4700::1111` (Cloudflare) przechodzi.

Pułapka, na którą trzeba uważać: włączenie `net.ipv6.conf.all.forwarding`
domyślnie **wyłącza przyjmowanie Router Advertisements**, co potrafi odciąć
hostowi jego własną trasę domyślną. Stąd `accept_ra = 2`.

IPv6 jest trzecią, niezależną drogą wejścia obok tunelu Cloudflare (droga
codzienna dla paneli i aplikacji) i SSH po IPv4 bastionu (droga codzienna dla
operatora) - przydatna, gdy jeden z tamtych dwóch zawiedzie, i nie kosztuje
nic dodatkowego ponad ten sam adres IPv4, który i tak trzeba było wykupić.

### To nie jest obejście braku adresów IP

Mimo że bastion ma publiczny adres, powierzchnia ataku zostaje minimalna: nie
ma żadnego otwartego portu HTTP do skanowania, dostęp do paneli wymaga
uwierzytelnienia w Cloudflare Access zanim ruch w ogóle dotknie serwera, a SSH
chroni klucz, fail2ban i niestandardowy port. Pozostałe siedem maszyn nie ma
żadnego publicznego adresu w ogóle.

---

## 3. Bezpieczeństwo - trzy warstwy

| Warstwa | Mechanizm | Gdzie opisana |
|---|---|---|
| Hypervisor | Firewall Proxmoxa, polityka wejściowa `DROP`, grupy bezpieczeństwa | Terraform |
| System gościa | UFW, domyślnie `deny incoming` | Ansible, rola `security` |
| Aplikacja | fail2ban na SSH, `unattended-upgrades` | Ansible, rola `security` |

Ta sama reguła istnieje w dwóch miejscach **celowo** - błąd w jednej warstwie
nie otwiera maszyny.

Grupy bezpieczeństwa są nazwane po funkcji, nie po maszynie: `http`, `metrics`,
`k3s-api`, `k3s-internal`, `prod-postgres`, `prod-redis`, `bastion`, `host-admin`.
Maszyna dostaje zestaw grup wynikający z jej roli, a nie własną listę reguł.

Porty eksporterów (`9100`, `8081`, `9323`, `9253`, `9187`, `9121`) są otwarte
**wyłącznie dla adresu Prometheusa**, nie dla całego segmentu.

---

## 4. Tożsamości i sekrety

### Trzy rozdzielone tożsamości SSH

| Klucz | Właściciel | Zasięg |
|---|---|---|
| `terraform_ed25519` | Terraform | wyłącznie host Proxmoxa |
| `ansible_ed25519` | Ansible | host + wszystkie maszyny |
| `humans/*.pub` | ludzie | konta imienne |

Terraform używa SSH tylko do wgrania snippetów cloud-init na hosta - nie ma po
co wchodzić na maszyny gości, więc jego klucz nie jest tam wsiewany.

### SOPS zamiast Ansible Vault i HashiCorp Vault

Rozważone trzy warianty:

- **HashiCorp Vault** - odrzucony. Zero wag w kryteriach, a realne ryzyko:
  po restarcie maszyny Vault wstaje zapieczętowany i wszystkie wdrożenia stają.
- **Ansible Vault** - działa, ale obsługuje tylko Ansible. Terraform zostałby
  z sekretami w `tfvars`.
- **SOPS + age** - wybrany. Jeden klucz obsługuje oba narzędzia, zero dodatkowej
  infrastruktury, a szyfrowanie na poziomie wartości sprawia, że historia zmian
  w gicie pozostaje czytelna.

### Sekret, którego nie ma

Hasło administratora Proxmoxa generuje `random_password` w Terraformie.
Nie jest nigdzie wpisywane ani przechowywane poza stanem, a `ignore_changes`
pilnuje, żeby zmiana hasła w panelu nie była cofana przy kolejnym `apply`.

**Świadome ograniczenie:** `random_password` trafia do stanu jawnym tekstem.
Dlatego bucket ze stanem ma włączone szyfrowanie i wąskie uprawnienia IAM,
i dlatego jest oddzielony od bucketa z kopiami zapasowymi.

---

## 5. Podział Terraform / Ansible

Granica jest ostra: **Terraform kończy pracę w momencie, gdy istnieje maszyna
z adresem IP i regułami firewalla.** Co się w niej uruchamia - należy do Ansible.

```
Terraform                          Ansible
─────────                          ───────
maszyna, CPU, RAM, dysk            pakiety, usługi, konfiguracja
sieć SDN, NAT                      UFW, fail2ban
firewall hypervisora               Docker, k3s, Postgres, Redis
DNS, tunele Cloudflare              Prometheus, Grafana, Loki, cloudflared
buckety S3, IAM                    Jenkins, kontenery aplikacji
```

Dzięki temu zmiana konfiguracji nie wymaga odtwarzania maszyny. Cloud-init robi
absolutne minimum (użytkownik, klucze, port SSH, `qemu-guest-agent`) - gdyby
robił więcej, każda poprawka konfiguracji oznaczałaby przebudowę maszyny.

---

## 6. Dlaczego dwa środowiska różnymi technologiami

`wolffire-dev-app-1` używa Docker Compose, produkcja stoi na k3s. To nie jest
niekonsekwencja - każde środowisko dowodzi czego innego:

| Środowisko | Technologia | Co pokazuje |
|---|---|---|
| dev | Docker Compose | obrazy, kontenery, **sieci i wolumeny** - w Kubernetesie te pojęcia znikają za abstrakcjami |
| prod | k3s + Helm | Deployment, Service, Ingress, skalowanie replik, rolling update |

Do obu środowisk trafia **ten sam obraz** z **GHCR** (GitHub Container Registry) -
jeden artefakt, dwa sposoby wdrożenia.

---

## 7. Decyzje wokół Kubernetesa

**Klaster obsługuje wyłącznie warstwę bezstanową aplikacji.** Postgres i Redis
stoją poza nim, na dedykowanej maszynie. Powód: przy jednym fizycznym hoście
jedynym dostępnym provisionerem jest `local-path`, który przypina wolumen do
konkretnego węzła - czyli stanowa usługa traci mobilność, ale zachowuje całą
złożoność Kubernetesa. Baza na osobnej maszynie jest prostsza i szybsza.

**Trzy węzły zamiast jednego**, bo dopiero wtedy da się pokazać, że klaster
faktycznie jest klastrem: `kubectl drain` na agencie i pody wstają na drugim.

**Pliki aplikacji stoją tymczasowo na `emptyDir`, docelowo mają trafić do S3.**
`storage/app` w chart Helma (`helm/wolffire/templates/deployment-php.yaml`)
montowany jest jako `emptyDir` - świadome ograniczenie na potrzeby dema: przy
więcej niż jednej replice PHP-FPM każdy pod ma osobną kopię i pliki giną przy
restarcie, bo k3s w tym układzie nie oferuje wolumenu RWX. Docelowa poprawka
to `FILESYSTEM_DISK=s3` (`app.filesystemDisk=s3` w wartościach chartu) -
wartość domyślna w `values.yaml` to jednak `local`.

---

## 8. Podział CI/CD: GitHub Actions i Jenkins

Dwa narzędzia, dwa rozłączne zakresy - żadne nie dubluje pracy drugiego:

| | GitHub Actions | Jenkins |
|---|---|---|
| Zakres | cykl życia aplikacji | operacje na infrastrukturze |
| Gdzie działa | runner **hostowany przez GitHub** | kontener na `cicd-1` |
| Wyzwalacz | `push` na dowolną gałąź | harmonogram (`H 2 * * *`) |
| Zadania | lint, testy Pest, budowa obrazu, publikacja do GHCR, wdrożenie, powiadomienia | `vzdump` maszyn, `pg_dump`, restic do S3, zadanie `infra-backup` |

Kryteria mówią „CI (Jenkins **lub inny**)" i „CD (Jenkins **lub inny**)", więc
obie wagi bierze GitHub Actions. Jenkinsowi zostaje `Jenkins Configuration as
Code` oraz udział w kryterium runnerów - i przede wszystkim rola, w której
jest naprawdę dobry: zadania cykliczne dotykające infrastruktury.

### Jak wdrożenie dociera do maszyn bez publicznego adresu

GitHub Actions korzysta z **runnerów hostowanych przez GitHuba** - nie stoją
w tej infrastrukturze i nie mają jak bezpośrednio dosięgnąć maszyn w prywatnych
segmentach SDN. Krok lint/testy/build nie potrzebuje nic więcej niż dostęp do
internetu i publikuje obraz do GHCR. Krok wdrożenia musi jednak połączyć się
z maszyną docelową - robi to po SSH, proxy'owanym przez **publiczny adres
IPv4 bastionu** (akcja `appleboy/ssh-action` z hostem pośredniczącym
ustawionym na bastiona), a stamtąd `ProxyJump` do `wolffire-dev-app-1`
(gałąź `develop`) albo `k3s-server-1` (gałąź `main`, `helm upgrade --install
--set image.*.tag=<sha>`).

To jedyne miejsce, w którym pipeline dotyka adresu publicznego - i jedyny
ruch spoza SSH administratora, jaki bastion w ogóle przepuszcza.

### Jenkins zamiast Watchtowera

Watchtower to aktualizacja pull-based: nie wiadomo kiedy wdrożył, nie ma wycofania,
bramki jakości ani powiadomienia. Kryterium CD wymaga wyzwalaczy, współpracy
z infrastrukturą i powiadomień - Watchtower nie spełnia żadnego z tych punktów.
Kopie zapasowe jako zadanie Jenkinsa dają jedno i drugie: harmonogram, historię
przebiegów i alert, gdy kopia się nie powiedzie.

Agenty Jenkinsa to efemeryczne kontenery Docker budowane z własnego obrazu
(`ansible/roles/jenkins/templates/agent-Dockerfile.j2`), doklejającego `pg_dump`
i `restic` do oryginalnego `jenkins/inbound-agent` - dzięki temu zostaje
standardowy sposób podłączania agenta (JNLP), a dochodzi tylko to, czego
brakuje do zadania backupowego. Cała konfiguracja kontrolera - użytkownicy,
poświadczenia, chmura agentów, samo zadanie - pochodzi z JCasC
(`jenkins.yaml.j2`), w UI nie ma nic do ręcznego ustawienia.

Jenkins dostaje **osobny token API Proxmoxa z rolą ograniczoną do wykonywania
kopii**, nie `Administrator` - token do backupów nie ma prawa kasować maszyn.
Podobnie tożsamość IAM `wolffire-jenkins-backup` ma prawo zapisu do bucketa
kopii, ale nie ma prawa `s3:DeleteObject` (`terraform/bootstrap/iam.tf`) -
przejęty token albo błąd w skrypcie nie skasuje kopii zapasowych.

---

## 9. Monitoring poza klastrem

Prometheus, Grafana, Loki i Alertmanager stoją na osobnej maszynie w Docker
Compose, nie w k3s. Cztery powody:

1. **Monitoring, który pada razem z monitorowaną infrastrukturą, nie zaalarmuje
   o jej padnięciu.** Stojąc obok klastra, przeżywa jego awarię i wysyła alert.
2. **Jawne `scrape_configs` zamiast operatora.** Ręcznie napisana konfiguracja
   pokazuje zrozumienie działania Prometheusa; `ServiceMonitor` pokazuje
   umiejętność instalacji charta Helma.
3. **Zużycie pamięci.** `kube-prometheus-stack` ciągnie operator, CRD,
   `kube-state-metrics` i eksporter na każdym węźle - około dwa razy więcej RAM-u
   niż te same usługi w Compose.
4. **Montowanie katalogów, nie pojedynczych plików.** Bind mount pojedynczego
   pliku przypina się do inode'a, a moduł `template` Ansible zapisuje nową
   treść atomowo przez `rename()` - kontener widziałby starą treść aż do
   restartu, a reload przeładowywałby właśnie ją. `compose.yml.j2`
   (`ansible/roles/monitoring/templates/compose.yml.j2`) montuje więc całe
   katalogi konfiguracyjne (`./prometheus/`, `./alertmanager/`, `./loki/`,
   `./calert/`), nie pojedyncze pliki wewnątrz nich - reload configu przez
   Ansible od razu trafia do kontenera.

Jedna Grafana pokazuje oba środowiska naraz - Compose i k3s.

### Alerty dwoma kanałami: Google Chat i e-mail (AWS SNS)

Alertmanager wysyła każdy alert warning/critical równolegle na dwa kanały:
przez calert na pokój Google Chat (kanał operacyjny) i przez natywne
`sns_configs` do tematu AWS SNS z subskrypcją e-mail (kanał zapasowy,
niezależny od Google). Trasa z `continue: true` w `alertmanager.yml.j2`
sprawia, że dopasowanie do kanału e-mail nie zatrzymuje przetwarzania
i alert trafia też do trasy Chata.

Wybór SNS zamiast własnego serwera pocztowego lub SES jest świadomy:
dostarczalność zapewnia nadawca AWS, bez budowania reputacji własnego IP
i bez walki z filtrami spamu. Temat, subskrypcja i dedykowany użytkownik
IAM (wyłącznie `sns:Publish` na ten jeden temat) są w Terraformie
(`terraform/bootstrap/sns.tf`), klucze w SOPS.

Konsekwentnie domena sama nie wysyła i nie odbiera żadnej poczty i mówi
to wprost rekordami DNS (moduł `cloudflare/dns`): null MX `0 .`
(RFC 7505), SPF `v=spf1 -all` i DMARC `p=reject`. Zastane rekordy MX
poprzedniego operatora zostały usunięte przez Terraform.

### Harmonogram integracji wyłączany flagą

Aplikacja w oryginale synchronizuje się z zewnętrznymi systemami (Nexo,
KSeF, ShipX, Dysk Google) harmonogramem w `routes/console.php`. Środowiska
tego projektu nie mają dostępu do żadnego z tych systemów, więc scheduler
kolejkowałby joby bez szans powodzenia - a ich obsługa potrafiła zabić
workera Horizona limitem pamięci. Jedna zmienna `INTEGRATIONS_SYNC_ENABLED=false`
(ConfigMap charta na prod, `env.j2` na dev) wyłącza rejestrację całego
harmonogramu po stronie aplikacji (`config/integrations.php`).

---

## 10. Znane ograniczenia

- **Jeden fizyczny serwer to pojedynczy punkt awarii.** Mitygacja: snapshoty
  wszystkich maszyn przed demonstracją oraz nagranie pełnego przebiegu pipeline'u
  jako materiał zapasowy.
- **`random_password` w stanie Terraforma** - opisane w sekcji 4.
- **`storage/app` na `emptyDir`, nie na S3** - opisane w sekcji 7. Przy więcej
  niż jednej replice PHP-FPM uploady nie są współdzielone między podami.
- **Aplikacja zależy od płatnej biblioteki** (Flux UI Pro). Obraz budowany jest
  w CI i publikowany do GHCR, więc odtworzenie środowiska nie wymaga licencji -
  ale przebudowa obrazu od zera już tak.
- **Klucze SSH bez hasła**, bo używają ich procesy nieinteraktywne. Ochroną jest
  to, że nigdy nie opuszczają stacji roboczej.
