# Ansible - komendy

Ansible odpowiada w tym repozytorium za wszystko, co dzieje się **wewnątrz**
maszyn. Same maszyny, sieć SDN i firewall hypervisora powstają wcześniej
w Terraformie - podział opisuje [PRZEWODNIK §4](../PRZEWODNIK.md).

> Wersja: ansible-core 2.21.2 (kolekcje w [`ansible/requirements.yml`](../../ansible/requirements.yml)).
> 9 hostów w inventory, 13 plays, 16 ról.
> **Zweryfikowano na żywo** 2026-08-05: `ansible all -m ping` (9/9 `pong`),
> `--syntax-check`, `--list-tags`, `--list-hosts`, `ansible-inventory --graph`.

Trzy rzeczy, które trzeba wiedzieć, zanim cokolwiek uruchomisz:

1. **Zawsze z katalogu `ansible/`.** Bez tego nie działa nic.
2. **Zawsze przez `sops exec-env`**, jeśli przebieg dotyka roli `jenkins`
   lub `cloudflared`.
3. **`--limit` przyjmuje nazwy z inventory**, nie aliasy SSH z prefiksem `wf-`.

---

## Skróty z `Makefile`

`Makefile` z korzenia repozytorium opakowuje trzy najczęstsze przebiegi. To
wyłącznie skróty - pod spodem jest dokładnie to, co opisuje reszta dokumentu,
a wszystko poza tymi trzema przypadkami uruchamiasz `ansible-playbook` wprost.

| Cel | Kiedy | Co robi pod spodem |
|---|---|---|
| `make bootstrap-host` | Raz, po instalacji Proxmoxa z OVH | `cd ansible && ansible-playbook bootstrap-host.yml` |
| `make ansible-check` | Przed każdym wdrożeniem: podgląd, nic nie zmienia | `sops exec-env secrets.sops.yaml 'cd ansible && ansible-playbook playbook.yml --check --diff'` |
| `make ansible-apply` | Wdrożenie konfiguracji na maszyny | `sops exec-env secrets.sops.yaml 'cd ansible && ansible-playbook playbook.yml'` |

Kolejność jest zamierzona: **`make ansible-check` przed `make ansible-apply`**, tak samo jak
`make tf-plan` przed `make tf-apply` po stronie Terraforma. Zanim uwierzysz w wynik,
przeczytaj [Kiedy `--check` kłamie](#kiedy---check-kłamie) - na węzłach k3s
zobaczysz `changed` przy w pełni zbieżnym stanie.

Trzy cele poboczne: `make up` (`infra` + `configure`, wdrożenie od zera),
`make status` (przegląd zdrowia - węzły i pody k3s, kontenery dev, kody HTTP
obu środowisk; czysty odczyt po SSH, bez Ansible, dobry zaraz po
`make ansible-apply`) oraz `make secrets` / `make secrets-app` do edycji dwóch
plików z sekretami - różnicę tłumaczy
[Dwa niezależne strumienie sekretów](#dwa-niezależne-strumienie-sekretów).

### Dlaczego `make bootstrap-host` nie ma `sops exec-env`

`bootstrap-host.yml` uruchamia się na **świeżym** hoście, na którym nie ma jeszcze
ani użytkownika `terraform@pve`, ani tokenu API. To on ten token dopiero tworzy
i wypisuje na konsolę, żebyś przeniósł go do SOPS-a (`make secrets`). Nie ma więc
czego odszyfrowywać. Playbook łączy się `root`em na porcie 22, a nie kontem
`ansible` na 22022, bo żadne z nich jeszcze nie istnieje:

```bash
make bootstrap-host                                                     # pierwszy przebieg, port 22
cd ansible
ansible-playbook bootstrap-host.yml -e bootstrap_ssh_port=22022   # kolejne, nowym portem
ansible-playbook bootstrap-host.yml -e bootstrap_ssh_port=22022 \
  -e keep_legacy_ssh_port=false                               # gdy 22022 sprawdzone: zamknij 22
```

### Dlaczego cele `make` robią `cd ansible`

Bo `ansible.cfg` jest wczytywany **wyłącznie** z katalogu bieżącego (albo
`ANSIBLE_CONFIG`), a wszystkie ścieżki w nim są względne: `inventory.yml`,
`roles/`, `ssh_config`. Uruchomienie `ansible-playbook ansible/playbook.yml`
z korzenia repozytorium nie kończy się czytelnym błędem - kończy się przebiegiem
bez inventory, bez `remote_user: ansible`, bez pluginu SOPS i bez ProxyJumpa.
Objaw to zwykle "brak hostów" albo `Permission denied` na wszystkim naraz.

Uwaga na ścieżkę pliku sekretów: `make` odpala `sops exec-env` z korzenia repo
(`secrets.sops.yaml`), a `cd ansible` dzieje się dopiero **wewnątrz** owijacza.
Gdy uruchamiasz ręcznie z katalogu `ansible/`, ścieżka jest o poziom wyżej:
`../secrets.sops.yaml`.

---

## Codzienna praca

Wszystkie polecenia poniżej zakładają, że jesteś w `ansible/`.

### Cały playbook

```bash
cd ansible
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml'
```

Albo krócej, z korzenia repozytorium: `make ansible-apply`.

Przebieg to 13 plays w ustalonej
kolejności: najpierw role wspólne na `all` (`hostname`, `login`, `security`,
`observability`, `alloy`), potem routing (`ipv6_router` na hypervisorze, `routes`
na bastionie), tunele Cloudflare, Docker, k3s, aplikacja produkcyjna, bazy,
Jenkins, monitoring i na końcu środowisko dev. Kolejność nie jest przypadkowa -
`security` musi otworzyć porty, zanim usługa zacznie na nich nasłuchiwać,
a `docker` musi stać, zanim `jenkins` zbuduje obrazy.

### Jedna maszyna

```bash
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml --limit monitoring-1'
```

`--limit` przyjmuje **nazwy hostów z `inventory.yml`** albo nazwy grup. Poprawne
wartości to dokładnie te:

| Hosty | Grupy |
|---|---|
| `proxmox-1`, `bastion-1`, `cicd-1`, `monitoring-1`, `k3s-server-1`, `k3s-agent-1`, `k3s-agent-2`, `wolffire-prod-db-1`, `wolffire-dev-app-1` | `proxmox`, `bastion`, `cicd`, `observability`, `k3s`, `k3s_server`, `k3s_agent`, `postgres`, `redis`, `docker`, `dev`, `prod` |

**`wf-monitoring-1` NIE jest poprawną wartością dla `--limit`.** Prefiks `wf-`
należy do aliasów w `ssh_config` i służy wyłącznie do nawiązania połączenia
(`ansible_host: wf-monitoring-1` w inventory). Podanie aliasu daje
`Could not match supplied host pattern` i przebieg kończy się bez zrobienia
czegokolwiek - łatwo to przeoczyć, bo to ostrzeżenie, nie błąd.

Kilka celów naraz i wykluczenia działają jak zwykle:

```bash
--limit 'k3s-agent-1,k3s-agent-2'    # dwie maszyny
--limit 'prod:!wolffire-prod-db-1'   # cała grupa prod bez bazy
--limit 'docker:&dev'                # część wspólna dwóch grup
```

Jeden host bywa w kilku grupach naraz (`wolffire-prod-db-1` jest w `postgres`,
`redis` i `prod`), więc `ansible-inventory --graph` bywa szybszy niż zgadywanie.

### Jedna rola

Każda rola ma tag o swojej nazwie, kilka ma dodatkowe tagi tematyczne.
Listę pobierzesz zawsze aktualną wprost z playbooka:

```bash
ansible-playbook playbook.yml --list-tags
```

Stan na dziś:

| Play (hosty) | Tagi |
|---|---|
| `all` | `hostname`, `login`, `users`, `sudo`, `ssh`, `security`, `firewall`, `fail2ban`, `updates`, `observability`, `alloy`, `logs` |
| `proxmox` | `ipv6` |
| `bastion` | `routes`, `network` |
| `cicd:observability:proxmox:dev` | `cloudflared` |
| `docker` | `docker` |
| `k3s_server`, `k3s_agent` | `k3s` |
| `k3s_server` (drugi przebieg) | `wolffire_prod`, `cloudflared` |
| `postgres` / `redis` | `postgres` / `redis` |
| `cicd` | `jenkins` |
| `observability` | `monitoring` |
| `dev` | `wolffire` |

```bash
# Docker wszędzie, gdzie stoi
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml --tags docker'

# Konta imienne - po dodaniu klucza do keys/humans/
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml --tags login'

# Reguły firewalla / monitoring na jednej maszynie
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit k3s-server-1 --tags firewall'
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --tags monitoring'
```

`--limit` i `--tags` mnożą się przez siebie: `--limit` wybiera maszyny, `--tags`
wybiera zadania. Kombinacja obu to najszybsza pętla iteracji przy pracy nad rolą.
`--skip-tags` działa odwrotnie i przydaje się, gdy chcesz pominąć jedną wolną
rolę: `--skip-tags jenkins` oszczędza budowanie obrazów kontrolera i agenta.

### Przebieg na sucho

```bash
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --check --diff'

# To samo w czytelniejszym formacie wyjścia
ANSIBLE_STDOUT_CALLBACK=yaml sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --check --diff'
```

`--check` symuluje przebieg bez zapisu, `--diff` dokłada treść różnicy
w plikach szablonowych. Ta sama para flag na całym playbooku, bez `--limit`, to
`make ansible-check` z korzenia repozytorium - używaj go, gdy chcesz obejrzeć wszystko
przed wdrożeniem, a wersji z `--limit` przy pracy nad jedną maszyną.

**Uwaga na sekrety w `--diff`.** Szablony podstawiają hasła (Grafana, k3s,
baza aplikacji), więc `--diff` wypisuje je na konsolę w jawnej postaci.
Z tego samego powodu test dymny (`scripts/checks/ansible.sh`) uruchamia
`--check` świadomie **bez** `--diff` - interesuje go tylko licznik `changed`.

### Kiedy `--check` kłamie

`--check` to symulacja, a nie przewidywanie przyszłości. Trzy przypadki, w których
raportuje `changed` mimo w pełni zbieżnego stanu na maszynie:

- **`get_url` bez sumy kontrolnej.** Moduł nie może pobrać pliku, więc nie ma czego
  porównać z tym, co leży na dysku, i domyślnie zgłasza zmianę. Dotyczy pobierania
  kluczy GPG (`roles/docker`, `roles/alloy`), skryptu instalacyjnego k3s
  (`roles/k3s/tasks/main.yml`) i binarki `redis_exporter`.
- **`community.general.ufw` z zakresami portów.** Na węzłach k3s
  (`group_vars/k3s/main.yml`) reguły mają postać `1:65535` dla całego segmentu.
  Moduł nie potrafi dopasować zakresu do już istniejącej reguły w `ufw status`
  i za każdym razem melduje `changed`. Realnie `ufw` reguły nie duplikuje.
- **Zadania `command`/`shell` są w `--check` domyślnie pomijane** (`skipped`).
  Tam, gdzie ich wynik jest potrzebny dalej (`register` + `until`, walidacja
  `sshd -t`), role mają jawne `check_mode: false` - patrz komentarz
  w `roles/login/tasks/ssh.yml`. To celowy wyjątek: te zadania nic nie zmieniają,
  a bez nich przebieg `--check` kończyłby się fałszywym błędem.

Efekt jest mylący w obie strony. Na `monitoring-1`, gdzie nie ma ani zakresów
portów, ani niezabezpieczonego `get_url` (dashboardy chroni `stat` +
`when: not item.stat.exists`), `--check --diff` daje czyste `changed=0`.
Na `k3s-server-1` przy tak samo zbieżnym stanie zobaczysz kilka `changed`.
**`changed` w `--check` nie jest więc dowodem, że coś jest nie tak** - dowodem
idempotentności jest dopiero drugi realny przebieg. Podobnie `failed` w `--check`
zwykle oznacza zadanie, którego Ansible nie potrafi zasymulować, a nie zepsutą
maszynę; istotne jest to, że przebieg urywa się w tym miejscu i dalsza część
playbooka pozostaje niesprawdzona.

### Demonstracja idempotentności

```bash
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml' | tee /tmp/run1.log
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml' | tee /tmp/run2.log
grep -A20 'PLAY RECAP' /tmp/run2.log
```

W drugim przebiegu, bez żadnej zmiany pomiędzy, każda linia `PLAY RECAP` powinna
mieć `changed=0 failed=0`. To samo automatycznie robi test dymny:

```bash
SMOKE_FULL=1 make test-infra    # sekcja 8 sumuje changed= i failed= z PLAY RECAP
```

### Sprawdzenia bez dotykania maszyn

```bash
ansible-playbook playbook.yml --syntax-check   # samo parsowanie YAML i ról
ansible-playbook playbook.yml --list-hosts     # które maszyny obejmie który play
ansible-playbook playbook.yml --list-tags      # dostępne tagi, play po playu
ansible-playbook playbook.yml --list-tasks     # pełna lista zadań w kolejności
ansible-inventory --graph                      # drzewo grup
ansible-inventory --list                       # pełny JSON razem z hostvars
```

Żadne z nich nie potrzebuje `sops exec-env` ani połączenia z maszynami.
`--syntax-check` uruchamiaj po każdej edycji ról, kosztuje sekundę.
`--list-hosts` przydaje się po dopisaniu maszyny do inventory: pokazuje, do
których plays trafiła, czyli jakie role faktycznie dostanie.

### Wznowienie od konkretnego zadania

Gdy przebieg wywalił się w połowie długiej roli, nie ma sensu odtwarzać
wszystkiego od początku:

```bash
# Nazwa zadania musi być dokładna - wyciągnij ją z --list-tasks
ansible-playbook playbook.yml --list-tasks --limit cicd-1 | grep -i obraz

sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit cicd-1 --start-at-task="Zbuduj obraz kontrolera"'
```

Dwa zastrzeżenia. Po pierwsze, `--start-at-task` **pomija** wszystko wcześniejsze
razem z `set_fact` i `register`, więc zadanie korzystające z faktu ustawionego
wyżej padnie na niezdefiniowanej zmiennej (w roli `jenkins` dotyczy to
`docker_gid`, odczytywanego z maszyny osobnym zadaniem). Po drugie, pominięte
zadania nie wywołują handlerów. Do jednorazowej diagnostyki to dobre, do
wdrożenia nie - tam zawężaj przez `--tags`, bo tag obejmuje całą rolę razem
z jej zadaniami przygotowawczymi.

---

## Diagnostyka

### Czy maszyny w ogóle odpowiadają

```bash
cd ansible
ansible all -m ping
```

`ping` to moduł Ansible, nie ICMP: łączy się po SSH, uruchamia Pythona na maszynie
i odsyła `pong`. To pierwszy test po zmianie w `ssh_config`, `inventory.yml`
albo po odtworzeniu maszyny w Terraformie. **Nie wymaga sekretów** - działa nawet
bez `SOPS_AGE_KEY_FILE`, bo nie dotyka żadnej roli.

Wynik z 2026-08-05 (9/9, skrócony):

```
proxmox-1    | SUCCESS => {"ping": "pong", "discovered_interpreter_python": "/usr/bin/python3.13"}
bastion-1    | SUCCESS => {"ping": "pong", "discovered_interpreter_python": "/usr/bin/python3.12"}
monitoring-1 | SUCCESS => {"ping": "pong", ...}
... (pozostałe 6 maszyn tak samo)
```

Hypervisor ma Pythona 3.13 (Debian 13), goście 3.12 (Ubuntu 24.04) - to normalne,
Ansible wykrywa interpreter sam.

### Fakty o maszynie

```bash
ansible monitoring-1 -m setup                              # wszystko (długie)
ansible all -m setup -a 'filter=ansible_memtotal_mb'       # jedna wartość
ansible all -m setup -a 'filter=ansible_distribution*'     # dystrybucja i wersja
ansible k3s -m setup -a 'filter=ansible_default_ipv4'      # adresacja
```

Nazwy faktów przydają się przy pisaniu ról - `roles/docker` używa
`ansible_distribution` i `ansible_architecture` do zbudowania URL-a repozytorium.

### Podgląd zmiennych

```bash
ansible-inventory --host monitoring-1               # zmienne bez uruchamiania playbooka

# Wartość tak, jak widzi ją zadanie (z rozwinięciem Jinja)
ansible monitoring-1  -m debug -a 'var=private_ip'
ansible cicd-1        -m debug -a 'var=group_names'
ansible k3s-server-1  -m debug -a 'msg={{ ufw_extra }}'

# Sekret z group_vars/all/secrets.sops.yml - plugin odszyfrowuje go w locie
ansible monitoring-1 -m debug -a 'var=grafana_admin_password'

# Drugi strumień: pusty BEZ owijacza, wypełniony z nim
ansible cicd-1 -m debug -a 'var=jenkins_backup_aws_access_key_id'
sops exec-env ../secrets.sops.yaml \
  'ansible cicd-1 -m debug -a "var=jenkins_backup_aws_access_key_id"'
```

Zapytanie o `grafana_admin_password` jest dobrym testem pluginu
`community.sops`: jeśli zwróci `VARIABLE IS NOT DEFINED`, problem jest w kluczu
age albo w `ansible.cfg`, a nie w roli.

### Ad hoc na maszynach

```bash
ansible monitoring-1 -m shell -a 'docker ps'
ansible all -m shell -a 'systemctl is-active docker prometheus-node-exporter fail2ban'
ansible all -m shell -a 'df -h / | tail -1'
ansible k3s -m shell -a 'systemctl status k3s --no-pager -l'
ansible cicd-1 -m shell -a 'docker logs --tail 50 jenkins'
```

Moduły `shell` i `command` służą **wyłącznie do odczytu**. Zmiana konfiguracji
zawsze idzie przez rolę - inaczej zniknie przy najbliższym `make ansible-apply`
i, co gorsza, nikt nie będzie wiedział, że tam była.

### Poziomy szczegółowości

`ansible.cfg` ustawia `verbosity = 1` na stałe, więc podstawowe wyjście już
zawiera zwrotki modułów (`msg`, zmienione ścieżki). Wyżej: `-vv` dokłada ścieżki
wykonywanych plików zadań, `-vvv` pełne polecenie SSH i argumenty modułu,
`-vvvv` ładowanie wtyczek połączenia i eskalacji uprawnień.

```bash
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --tags monitoring -vvv'
```

Do problemów z połączeniem `-vvv` jest właściwym poziomem: pokazuje pełną komendę
`ssh` razem z `-F ssh_config` i `ProxyJump`, więc od razu widać, czy Ansible idzie
tą samą drogą co Twój ręczny `ssh`.

---

## Gdy coś nie działa

| Objaw | Przyczyna | Naprawa |
|---|---|---|
| `assert` w roli `jenkins`: `Brak BACKUP_AWS_ACCESS_KEY_ID / BACKUP_AWS_SECRET_ACCESS_KEY w środowisku` | Playbook uruchomiony bez `sops exec-env`. `group_vars/cicd/main.yml` czyta te klucze przez `lookup('env', ...)`, więc bez owijacza dostają pustą wartość | Owiń polecenie: `sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml'`. Assert jest celowy - lepiej ubić wdrożenie teraz, niż odkryć w nocy Jenkinsa z pustym poświadczeniem i kopią, która się nie wykonała |
| `No valid credential sources found` na roli `cloudflared` | To samo źródło: rola czyta token tunelu ze stanu Terraforma w S3 (`cloud.terraform.terraform_output`), a poświadczenia AWS przychodzą ze środowiska | Jak wyżej. Dotyczy również przebiegów `--check` |
| `Could not match supplied host pattern, ignoring: wf-monitoring-1` i `skipping: no hosts matched` | Do `--limit` podany alias SSH zamiast nazwy hosta z inventory | Użyj `monitoring-1`. Aliasy `wf-*` istnieją tylko w `ssh_config` i nigdy nie są nazwami hostów Ansible |
| `ERROR! the playbook: playbook.yml could not be found`, albo przebieg bez inventory i `Permission denied` na wszystkim naraz | Uruchomienie z korzenia repozytorium: `ansible.cfg` nie jest wczytany, więc nie działa ani `inventory`, ani `roles_path`, ani `ssh_args = -F ssh_config` | `cd ansible` przed każdym poleceniem. Cele `make` robią to za Ciebie |
| `UNREACHABLE! ... Host key verification failed` po odtworzeniu maszyny | `host_key_checking = True` plus `StrictHostKeyChecking accept-new`: nowy klucz hosta na starym adresie wygląda jak podmiana | `ssh-keygen -R '[10.0.120.20]:22022'` (adres i port z `ssh_config`), potem `ansible monitoring-1 -m ping`, żeby przyjąć nowy klucz |
| `UNREACHABLE! ... Permission denied (publickey)` | Klucz maszynowy nie trafił na maszynę (cloud-init nie dokończył) albo `IdentityFile` wskazuje nie tam | `ssh -F ssh_config -v wf-monitoring-1` pokaże, który klucz jest oferowany. Ścieżki w `ssh_config` są bezwzględne właśnie po to, żeby plik działał też wciągnięty z `~/.ssh/config` |
| Każde zadanie trwa kilka sekund, przebieg po 9 maszynach ciągnie się w nieskończoność | Zerwany multipleks SSH: bez `ControlPersist` każde zadanie zestawia nowe połączenie, a przez bastion oznacza to dwa uściski dłoni zamiast zera | `ansible.cfg` ma `ControlMaster=auto -o ControlPersist=120s` i `pipelining = true`. Sprawdź gniazdo: `ssh -F ssh_config -O check wf-bastion-1`. Jeśli zwisło: `ssh -F ssh_config -O exit wf-bastion-1` i uruchom ponownie |
| `ssh proxmox-1` wchodzi na zupełnie inny serwer | Kolizja nazw: `~/.ssh/config` wciąga konfiguracje innych projektów, w których też są hosty `proxmox-1` i `bastion-1` | Zawsze z prefiksem: `ssh wf-proxmox-1`. Po to prefiks istnieje - patrz komentarz na górze `ansible/ssh_config` |
| `VARIABLE IS NOT DEFINED` przy sekrecie z `group_vars/all/secrets.sops.yml` | Plugin `community.sops` nie odszyfrował pliku: brak klucza prywatnego age albo kolekcja nie jest zainstalowana | Sprawdź `~/.config/sops/age/keys.txt` i `SOPS_AGE_KEY_FILE`; `ansible-galaxy collection install -r requirements.yml`. Test niezależny: `sops --decrypt group_vars/all/secrets.sops.yml` |
| To samo zadanie melduje `changed` w każdym **realnym** przebiegu | Brak poprawnego `changed_when` albo moduł, który nie potrafi porównać stanu | Wzorzec rozwiązania jest w rolach `wolffire` i `wolffire_prod`: `changed_when` liczony z wejść (hash szablonu), nie z tekstu wyjścia. W `roles/monitoring` ten sam problem rozwiązuje `stat` + `when: not item.stat.exists` zamiast `get_url` z `force: false` |
| Zadanie wisi na `until`/`retries` | Usługa faktycznie nie wstała, nie tylko startuje wolno | Wejdź na maszynę: `systemctl status <usługa>`, `journalctl -u <usługa> -n 50` |
| `ansible-lint` zgłasza błędy w plikach `CLAUDE.md` wewnątrz ról | To pliki metadanych, nie YAML | Ignoruj. `make validate` i tak kończy `ansible-lint` z `|| true` |

---

## Jak to działa

### Dwa niezależne strumienie sekretów

Projekt trzyma sekrety w dwóch plikach i mylenie ich to najczęstsze źródło
nieporozumień. Pełny opis w [`sops.md`](sops.md), tu skrót istotny dla Ansible:

| Plik | Jak trafia do Ansible | Zawiera | Edycja |
|---|---|---|---|
| `secrets.sops.yaml` (korzeń repo) | Zmienne środowiskowe przez `sops exec-env`, czytane w rolach przez `lookup('env', ...)` | Poświadczenia dostawców: Proxmox, Cloudflare, AWS (stan i backupy) | `make secrets` |
| `ansible/group_vars/all/secrets.sops.yml` | Plugin `community.sops` odszyfrowuje **w locie** przy starcie playbooka, bez osobnego kroku | Sekrety wnętrza infrastruktury: hasła baz, `APP_KEY`, tokeny GHCR/Jenkins/Grafana, webhooki | `make secrets-app` |

Drugi strumień działa dzięki jednej linii w `ansible.cfg`:

```ini
vars_plugins_enabled = host_group_vars,community.sops.sops
```

Plugin traktuje `*.sops.yml` w `group_vars/` i `host_vars/` jak zwykłe pliki
zmiennych, tyle że deszyfruje je kluczem age w pamięci. Nigdzie na dysku nie
powstaje wersja jawna i nie ma kroku "odszyfruj przed uruchomieniem", o którym
można zapomnieć. **Ten strumień nie wymaga `sops exec-env`** - działa zawsze,
o ile masz klucz prywatny.

Pierwszy strumień owijacza wymaga, bo `lookup('env', ...)` czyta środowisko
procesu. Puste wartości nie powodują błędu same z siebie, więc rola `jenkins`
sprawdza je jawnie zadaniem `assert` - inaczej wdrożenie skończyłoby się
Jenkinsem z pustym poświadczeniem do bucketa kopii, a awaria wyszłaby dopiero
w nocy, przy pierwszym zadaniu backupu.

### Połączenia: ssh_config zamiast inventory

Nietypowe dla Ansible, ale świadome: `inventory.yml` **nie** opisuje sposobu
łączenia. Nie ma tam ani `ansible_port`, ani `ansible_ssh_common_args`.
Zamiast tego `ansible.cfg` mówi:

```ini
ssh_args = -F ssh_config -o ControlMaster=auto -o ControlPersist=120s
```

a cała topologia (port 22022, `ProxyJump %r@wf-bastion-1`, ścieżki kluczy) siedzi
w `ansible/ssh_config`. `ansible_host` w inventory to alias z tego pliku, a nie
adres IP. Zysk: `ssh wf-monitoring-1` z terminala idzie dokładnie tą samą drogą
co Ansible, więc problem z połączeniem diagnozuje się jednym poleceniem, a nie
dwiema osobnymi konfiguracjami, które mogą się rozjechać. Adresy IP są
w inventory (`private_ip`) jako **dane** dla szablonów Prometheusa, Loki i k3s,
a nie jako parametry połączenia.

Bezpośrednio osiągalne są dwie maszyny: `wf-bastion-1` (publiczne IPv4)
i `wf-proxmox-1` (hypervisor, docelowo też tylko z bastionu). Cała reszta idzie
przez bastion - dlatego zerwany multipleks SSH boli podwójnie, każde zadanie
płaci wtedy za dwa uściski dłoni.

### Konto maszynowe kontra konto imienne

```
Ansible     -> user `ansible`  (remote_user w ansible.cfg)
Ty domyślnie -> user `ansible`  (User wf-* w ssh_config)
Ty imiennie  -> ssh mserwinowski@wf-monitoring-1
```

`ProxyJump %r@wf-bastion-1` podstawia `%r`, czyli nazwę użytkownika z polecenia,
więc ta sama tożsamość idzie na oba przeskoki - nie trzeba osobno konfigurować
logowania na bastion. Konta imienne zakłada rola `login` na podstawie plików
`keys/humans/*.pub`, gdzie nazwa pliku jest nazwą użytkownika; dodanie osoby to
wrzucenie klucza i `ansible-playbook playbook.yml --tags login`.

Konto `ansible` ma `sudo` bez hasła, a `ansible.cfg` ustawia `become = true`
globalnie - dlatego żadne polecenie w tym dokumencie nie potrzebuje
`--ask-become-pass` ani `-b`.

---

## Powiązane

- [PRZEWODNIK §4](../PRZEWODNIK.md) - co robi każda rola i co edytować w typowych scenariuszach
- [RUNBOOK §2](../RUNBOOK.md) - dostęp do maszyn, tunel do API Proxmoxa, gdy SSH nie chce się połączyć
- [`sops.md`](sops.md) - edycja sekretów, rotacja klucza, dodanie odbiorcy
- [`terraform.md`](terraform.md) - warstwa niżej: maszyny, sieć, firewall
