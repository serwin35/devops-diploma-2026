# Git - komendy i przepływ

Projekt żyje w dwóch repozytoriach na koncie `serwin35`. Oba mają ten sam model
gałęzi (`develop` -> pull request -> `main`), ale różny rytm pracy i różne
konsekwencje scalenia do `main`.

| Repo | Ścieżka lokalna | Zawiera | Widoczność |
|---|---|---|---|
| `devops-diploma-2026` | `~/Projects/DevOps-Kurs/devops-diploma-2026` | infrastruktura jako kod: Terraform, Ansible, Helm, dokumentacja | publiczne |
| `WF-ChartApp-diploma` | `~/Projects/DevOps-Kurs/WF-ChartApp-diploma` | aplikacja Laravel (adaptacja WolfFire) | prywatne, 308 commitów |

Stąd bierze się dwuznaczność, na którą łatwo trafić w dokumentacji: "push na
`develop`" w [RUNBOOK §13](../RUNBOOK.md) dotyczy repozytorium **aplikacji**,
bo tylko tam push uruchamia potok CI/CD. W repozytorium infrastruktury push nic
nie wdraża - zmiany idą przez `make plan` i `make infra`.

> **Zweryfikowano na żywo** 2026-08-05: infrastruktura - 15 commitów na
> `develop` scalonych przez PR nr 1 (270 plików, +16038/-1); aplikacja -
> gałęzie zsynchronizowane, PR-y nr 2 i 3 scalone.

---

## 1. Przepływ w repozytorium infrastruktury

Praca liniowa na `develop`, jedno scalenie do `main` przez pull request.

```
$ git log --oneline --graph
*   bb2cf5c Merge pull request #1 from serwin35/develop
|\
| * 93f9b84 Write documentation: architecture, runbook, command guides and evidence
| * 52df520 Add public SSH keys with usage notes
| * 5741eb3 Add dev-to-prod database sync script
| * b295886 Add read-only infrastructure smoke tests
| * a4bbc1e Configure Jenkins via JCasC with restic backup pipeline to S3
| * 4356d9e Stand up monitoring: Prometheus, Grafana, Loki, Alertmanager with dual alert channels
| * d14b480 Add Helm chart for WolfFire (php, nginx, horizon, scheduler, migrate job)
| * 536f92b Deploy k3s cluster and WolfFire application roles
| * 6bfe815 Install PostgreSQL and Redis with exporters
| * afcf326 Set up Ansible inventory, SSH config and base hardening roles
| * 75d5d70 Wire Cloudflare: per-machine tunnels, Zero Trust access and DNS no-mail policy
| * 9ea7dd4 Define service VMs: bastion, cicd, observability, wolffire dev and prod
| * 8913385 Provision Proxmox base: SDN network, storage, cloud-init and firewall groups
| * 2ccd421 Bootstrap AWS: state and backup buckets, IAM identities, SNS alerts topic
| * cd482da Add Makefile and SOPS-encrypted provider secrets
|/
* d6ac206 feat(secrets): manage tokens with SOPS and age
```

Kolejność commitów nie jest przypadkowa - odzwierciedla realną kolejność
budowy: najpierw stan i sekrety, potem AWS, Proxmox, maszyny, sieć,
konfiguracja maszyn, usługi, aplikacja, monitoring, CI, na końcu dokumentacja.
Żaden commit nie zależy od kodu z późniejszego, więc każdy da się odtworzyć
osobno.

Merge commit (`bb2cf5c`) jest zachowany świadomie, zamiast przewinięcia.
Historia pokazuje wtedy, że praca powstawała na gałęzi i weszła jednym
przeglądem, a nie że ktoś commitował prosto na `main`.

## 2. Przepływ w repozytorium aplikacji

Ten sam model gałęzi, ale każdy push ma skutki uboczne w GitHub Actions.

| Gałąź | Co wyzwala | Gdzie ląduje |
|---|---|---|
| dowolna (`feature/*`) | CI, Build | nigdzie - tylko obrazy z tagiem sha w GHCR |
| `develop` | CI, Build, **deploy-dev** | `wolffire-dev-app-1`, Docker Compose |
| `main` | CI, Build, **deploy-prod** | klaster k3s przez `helm upgrade` |

```
git push origin develop
   |
   v
[ CI ]  ci.yml    on: push (kazda galaz) + pull_request
   |      lint: Pint --test
   |      test: Pest --ci --parallel, uslugi postgres:18 + redis:7
   |
   | workflow_run: types [completed], if conclusion == 'success'
   v
[ Build ]  build.yml
        build:       php + nginx -> ghcr.io/serwin35/wf-chartapp-diploma
                     tag = <sha7>, dodatkowo :latest tylko dla main/develop
        deploy-dev:  if galaz == develop -> ssh przez bastion, IMAGE_TAG=<sha7>
                     w /opt/wolffire/.env, systemctl reload, smoke test /up
        deploy-prod: if galaz == main -> helm upgrade --install na k3s
        notify:      if always() -> wiadomosc na Google Chat
```

Trzy decyzje, które warto umieć uzasadnić:

- **CI leci na każdej gałęzi.** Build buduje obrazy wyłącznie z commitów
  z zielonym CI, więc brama jakości musi stać przed każdym commitem, nie tylko
  przed scaleniem.
- **Build startuje z `workflow_run`, nie z `push`.** Gdyby oba szły z `push`,
  obraz powstawałby równolegle z testami i mógłby wyjść z commitu, który
  właśnie oblał. Pod `workflow_run` domyślne `github.ref_name`/`github.sha`
  wskazują gałąź domyślną, a nie tę, która wyzwoliła CI - prawdziwe wartości
  bierzemy z `github.event.workflow_run.head_branch` i `head_sha`.
- **`concurrency` kolejkuje zamiast anulować** (`cancel-in-progress: false`).
  Przerwanie w połowie deployu zostawiłoby środowisko w stanie pośrednim: nowy
  tag w `.env`, stare kontenery.

Podgląd przebiegów bez wchodzenia na GitHuba:

```bash
cd ~/Projects/DevOps-Kurs/WF-ChartApp-diploma
gh run list --limit 10
gh run list --workflow=ci.yml --branch develop --limit 5
gh run watch                       # przebieg na żywo
gh run view --log-failed           # tylko logi kroków, które padły
```

## 3. Codzienne komendy w tym przepływie

```bash
# Zaczynam pracę
git switch develop
git pull --ff-only origin develop     # nie twórz merge'a przez przypadek
git switch -c feature/monitoring-sns
```

`--ff-only` jest istotne: domyślny `pull` przy rozjechanych gałęziach zrobi
merge i wstawi commit "Merge branch ...", którego nikt nie chciał. Jeśli
odmówi, to znaczy, że masz lokalne commity - i lepiej zobaczyć to wprost.

```bash
# Przygotowuję commit
git status                          # zawsze pierwsze
git diff                            # zmiany niezastagowane
git diff --staged                   # to, co faktycznie pójdzie w commit
git add ansible/roles/monitoring/   # po ścieżce, świadomie
git add -p ansible/roles/monitoring/templates/alerts.yml.j2
```

`git add -p` przechodzi przez zmiany fragment po fragmencie (`y` bierz,
`n` pomiń, `s` podziel, `q` wyjdź). To najprostszy sposób, żeby nie wrzucić
przypadkowego `dd()`, zakomentowanego eksperymentu albo odszyfrowanego
sekretu, który leżał w tym samym pliku.

**Nigdy `git add -A` ani `git add .` bez przejrzenia `git status`.**
W repozytorium infrastruktury łatwo o dodanie odszyfrowanego pliku sekretów
albo katalogu `.terraform/` - oba są w `.gitignore`, ale świeżo utworzony plik
poza wzorcem potrafi się prześlizgnąć.

```bash
git commit -m "Add SNS email channel alongside Google Chat"
git commit --amend                  # poprawka OSTATNIEGO commita, tylko przed pushem
git push -u origin feature/monitoring-sns
```

```bash
# Pull request
gh pr create --base develop --title "Add SNS email alert channel" \
  --body "Alertmanager publikuje do SNS obok kanalu Google Chat."
gh pr status                        # moje PR-y i te wymagające akcji
gh pr checks                        # stan CI dla bieżącej gałęzi
gh pr diff                          # przegląd zmian w terminalu
gh pr merge --merge --delete-branch
gh pr view 1 --json number,baseRefName,headRefName,changedFiles,additions,deletions
```

`--merge`, a nie `--squash`: w repozytorium infrastruktury każdy commit
odpowiada osobnemu, dającemu się odtworzyć etapowi budowy. Spłaszczenie 15
commitów do jednego skasowałoby dokładnie tę informację, która jest
najciekawsza - kolejność powstawania.

```bash
# Przeglądam historię
git log --oneline --graph --all --decorate       # historia z gałęziami zdalnymi
git log --oneline main..develop                  # co jest na develop, a nie ma na main
git log --oneline origin/main..HEAD              # co mam lokalnie, a nie wypchnąłem
git log --oneline --graph -- terraform/          # historia jednego katalogu
git log -p --follow -- ansible/roles/cloudflared/tasks/main.yml   # przez zmiany nazwy
git log -S 'alertmanager_sns_topic_arn' --oneline                 # kiedy pojawił się ciąg
git show --stat <sha>                            # lista plików i liczby linii
git show <sha>:sciezka/do/pliku                  # treść pliku z tamtego commita
git blame ansible/roles/monitoring/templates/alerts.yml.j2
```

`git show --stat 4356d9e` pokazuje wprost, że commit jest spójny tematycznie -
wszystkie zmienione pliki leżą w `roles/monitoring/` i `roles/alloy/`.
`git log -S` szuka commitów, w których liczba wystąpień danego ciągu się
zmieniła - najszybsza odpowiedź na "kiedy i po co to weszło", znacznie
skuteczniejsza niż `grep` po historii.

## 4. Zasady commitów w tym projekcie

Dwa repozytoria, dwie konwencje. To nie jest niekonsekwencja, tylko dopasowanie
do tego, co historia ma opisywać.

### Infrastruktura: tryb rozkazujący, bez prefiksów

```
Stand up monitoring: Prometheus, Grafana, Loki, Alertmanager with dual alert channels
Install PostgreSQL and Redis with exporters
Wire Cloudflare: per-machine tunnels, Zero Trust access and DNS no-mail policy
```

Format: `<Czasownik w trybie rozkazującym> <co>`, po angielsku, pierwsza litera
wielka, bez kropki, do ok. 72 znaków.

**Dlaczego bez `feat:`/`fix:`.** Conventional Commits istnieją po to, żeby
narzędzie mogło z nich wygenerować numer wersji i changelog. Infrastruktura nie
ma ani jednego, ani drugiego - ma stan, który albo odpowiada rzeczywistości,
albo nie. Prefiks `feat(monitoring):` przed opisem roli nie niesie tu
informacji, której nie ma już w ścieżce zmienionych plików, a kradnie 20 znaków
z jedynej linii, którą ktoś przeczyta w `git log --oneline`. Do tego podział na
`feat` i `fix` jest w infrastrukturze sztuczny: dodanie brakującej reguły UFW
jest jednocześnie jednym i drugim.

Dwa najstarsze commity (`d6ac206`, `a54cdfe`) używają jeszcze Conventional
Commits - pozostałość po pierwszym podejściu, świadomie niezmieniana, bo
przepisywanie historii wypchniętej na GitHuba to gorszy problem niż
niespójność w dwóch linijkach.

### Aplikacja: Conventional Commits

```
feat(scheduler): gate external integrations schedule behind INTEGRATIONS_SYNC_ENABLED flag
fix(cd): treat GHA cache export failures as non-fatal in image builds
fix(seeders): sync roles from pivot after users exist in DemoSeeder
chore: remove claude-mem generated files and local session data
```

Format: `<typ>(<zakres>): <opis w trybie rozkazującym, po angielsku>`. Typy:
`feat` (nowa funkcjonalność), `fix` (naprawa), `refactor` (struktura bez zmiany
zachowania), `test`, `chore` (porządki), `ci` (workflow), `docs`.

**Dlaczego tu tak.** Aplikacja jest wersjonowana, wdrażana wielokrotnie
dziennie i ma 308 commitów historii odziedziczonej z repozytorium firmowego,
która już tę konwencję stosuje. Zakres (`scheduler`, `ksef`, `documents`,
`google-drive`) nazywa domenę biznesową i przy 300 commitach realnie skraca
szukanie. Zmiana konwencji w połowie życia repozytorium dałaby historię gorszą
niż jedna niedoskonała konwencja stosowana konsekwentnie.

### Wspólne, niezależnie od repo

- Tryb rozkazujący, nie przeszły: "Add", nie "Added" - commit opisuje, co
  **zrobi** po zastosowaniu.
- Wyłącznie angielski, jak każdy inny identyfikator w projekcie.
- Jeden commit = jedna zamknięta zmiana. Jeśli w opisie pojawia się "oraz",
  prawdopodobnie powinny być dwa commity.
- Ciało commita (po pustej linii) opisuje **dlaczego**; "co" widać w diffie.

## 5. Co nigdy nie trafia do repozytorium

Wymuszone przez `.gitignore`, ale warto pamiętać dlaczego, sprawdzając diff:

| Wzorzec | Powód |
|---|---|
| `*.tfstate*` | stan idzie do S3, nie do gita - i bywa w nim `random_password` jawnym tekstem |
| `keys.txt`, `*.agekey` | prywatny klucz age; bez niego nikt nie odszyfruje `*.sops.yaml` |
| `keys/*_ed25519` | prywatne klucze SSH; do repo trafiają wyłącznie `*.pub` |
| `*.tfvars` (poza `.example`) | zmienne bywają lokalne, sekrety i tak idą przez SOPS |
| `ansible/.vault_pass` | repo używa SOPS, nie Ansible Vault |
| `.terraform/` | katalog roboczy z providerami, setki megabajtów |

`*.sops.yaml` i `*.sops.yml` **są** commitowane celowo - to zaszyfrowane
wartości, bezpieczne w historii.

## 6. Operacje ratunkowe

Od najmniej do najbardziej niszczących.

```bash
# Cofnięcie zmian w plikach
git restore plik.yml                     # przywróć z HEAD
git restore --staged plik.yml            # wyjmij ze stage, zachowaj zmiany
git restore --source=HEAD~3 plik.yml     # weź wersję sprzed 3 commitów
```

`--staged` operuje na indeksie, bez `--staged` na katalogu roboczym - i tylko
ta druga forma kasuje pracę bezpowrotnie.

```bash
# Odłożenie pracy na bok
git stash push -m "polowiczna konfiguracja alloy"
git stash push -u                        # razem z plikami nieśledzonymi
git stash list; git stash show -p stash@{0}
git stash pop                            # przywróć i usuń ze schowka
git stash apply stash@{1}                # przywróć, zostaw w schowku
```

Schowek jest lokalny i nie idzie na GitHuba. Zostawiona tam praca ginie razem
z katalogiem - dlatego zawsze z `-m` i nie na dłużej niż dzień.

```bash
# Cofnięcie commita PRZED pushem
git reset --soft HEAD~1     # cofa commit, zmiany zostają w stage
git reset HEAD~1            # cofa commit, zmiany w katalogu roboczym (--mixed)
git reset --hard HEAD~1     # cofa commit RAZEM ZE ZMIANAMI
```

> **Ostrzeżenie.** `--hard` kasuje niescommitowane zmiany bez pytania i bez
> kosza. Przed każdym `--hard` uruchom `git status`. Commit, który już
> istniał, odzyskasz przez `git reflog`; zmiany, które nigdy nie były
> w żadnym commicie, przepadają na zawsze.

```bash
git reflog                  # pozycje HEAD z ostatnich ~90 dni
git reset --hard HEAD@{2}   # powrót do stanu sprzed dwóch operacji
```

```bash
# Porządkowanie historii TYLKO przed pushem
git log --oneline origin/develop..HEAD    # tylko te commity wolno przepisywać
git rebase -i HEAD~5
```

W edytorze: `pick` zostaw, `reword` zmień opis, `squash` scal z poprzednim,
`fixup` scal bez opisu, `drop` usuń; zmiana kolejności linii zmienia kolejność
commitów.

> **Granica jest twarda: rebase wyłącznie na commitach, których nie ma na
> GitHubie.** Rebase tworzy nowe commity z nowymi identyfikatorami. Jeśli stare
> były już wypchnięte, każdy, kto je pobrał, ma rozjechaną historię, a jedynym
> sposobem wypchnięcia jest `push --force`, który u kogoś innego kasuje pracę.

```bash
# Cofnięcie czegoś, co JUŻ poszło na GitHuba
git revert <sha>                         # nowy commit odwracający tamten
git revert --no-commit <sha1>..<sha2>    # zakres, jeden zbiorczy commit
git revert -m 1 <sha-merge>              # cofnięcie merge'a
```

`revert` dokłada commit zamiast przepisywać historię, więc jest bezpieczny na
gałęziach współdzielonych. Przy merge'u `-m 1` jest obowiązkowe - mówi Gitowi,
którego rodzica traktować jako "przed zmianą".

## 7. Praca z dwoma repozytoriami naraz

Typowa zmiana dotyka obu: workflow w aplikacji odwołuje się do ścieżek
tworzonych przez rolę Ansible w infrastrukturze.

```bash
git rev-parse --show-toplevel      # gdzie jestem
git branch --show-current
git remote -v                      # dokąd to leci
```

Zdalne adresy to odpowiednio `github.com/serwin35/devops-diploma-2026.git`
i `github.com/serwin35/WF-ChartApp-diploma.git`, oba pod `origin`.

`git -C <ścieżka>` uruchamia komendę w innym repozytorium bez zmiany katalogu:

```bash
APP=~/Projects/DevOps-Kurs/WF-ChartApp-diploma
git -C "$APP" status -sb
git -C "$APP" remote -v
git -C "$APP" log --oneline origin/main..origin/develop   # co czeka na produkcję
gh -R serwin35/WF-ChartApp-diploma run list --limit 5
gh -R serwin35/devops-diploma-2026 pr list --state all
```

Kolejność przy zmianie dotykającej obu repozytoriów: **najpierw
infrastruktura** (rola Ansible tworzy katalog albo jednostkę systemd), potem
aplikacja (workflow z niej korzysta). Odwrotna kolejność daje czerwony deploy
z komunikatem o brakującej ścieżce - dokładnie tym, który `build.yml` wypisuje
jawnie zamiast pozwolić helmowi paść kryptycznym błędem.

## 8. Częste problemy

### Push odrzucony (`fetch first`)

Ktoś (albo Ty z innej maszyny) wypchnął coś w międzyczasie.

```bash
git fetch origin
git log --oneline HEAD..origin/develop     # co przyszło z zewnątrz
git log --oneline origin/develop..HEAD     # co masz lokalnie
git pull --rebase origin develop           # przenieś swoje commity na wierzch
git push origin develop
```

`--rebase` daje liniową historię i jest właściwy dla własnej gałęzi roboczej.
Na gałęzi, z której korzysta ktoś inny, bezpieczniejszy jest zwykły merge
(`git pull --no-rebase`).

**Nie rozwiązuj tego przez `git push --force`.** Jeśli naprawdę musisz
nadpisać zdalną gałąź, użyj `--force-with-lease` - odmówi, jeśli zdalna gałąź
zmieniła się od Twojego ostatniego `fetch`, czyli dokładnie w sytuacji,
w której `--force` skasowałby cudzą pracę.

### Konflikt przy merge

```bash
git status                              # sekcja "Unmerged paths"
git diff --name-only --diff-filter=U    # sama lista plików w konflikcie
```

W pliku szukasz znaczników `<<<<<<< HEAD`, `=======`, `>>>>>>> develop`.
Rozwiązanie polega na zostawieniu poprawnej treści i **usunięciu wszystkich
trzech znaczników**.

```bash
git add <plik>
git merge --continue        # albo: git rebase --continue
git merge --abort           # wycofanie się z całego merge'a
git checkout --ours plik.yml     # zostaw wersję z bieżącej gałęzi
git checkout --theirs plik.yml   # zostaw wersję z wciąganej gałęzi
```

**Konflikt w `*.sops.yaml` rozwiązuje się inaczej.** Tekstowy merge
szyfrogramu da plik, którego SOPS nie odszyfruje. Procedura: odrzuć jedną
stronę w całości (`--ours` albo `--theirs`), a potem `sops <plik>` na już
scalonej bazie i wpisz brakującą wartość ręcznie - patrz [sops.md](sops.md).

### Zaszyfrowany plik zawsze wygląda na zmieniony

SOPS re-szyfruje przy każdym zapisie innym wektorem inicjalizacyjnym, więc
`git status` pokazuje zmianę nawet bez zmiany wartości. Nieszkodliwe -
commituj tylko wtedy, gdy faktycznie coś zmieniłeś, w przeciwnym razie
`git checkout -- secrets.sops.yaml`.

### Przypadkowe dodanie `.terraform/`

```bash
git rm -r --cached terraform/.terraform     # usuwa z indeksu, zostawia na dysku
```

### Sekret w commicie - procedura

Jedyny przypadek w tym dokumencie, w którym kolejność kroków ma znaczenie
krytyczne.

**Jeśli commit NIE został jeszcze wypchnięty:**

```bash
# 1. NIE PUSHUJ.
# 2. Sprawdź, w ilu commitach to siedzi
git log -S '<fragment_sekretu>' --oneline

# 3a. Sekret jest w ostatnim commicie i tylko tam
git reset --soft HEAD~1
# usuń wartość z pliku albo przenieś ją do *.sops.yaml
git add <plik>
git commit -m "Store SNS credentials in SOPS instead of plain text"

# 3b. Sekret jest głębiej, ale wciąż lokalnie
git rebase -i <sha-przed-sekretem>    # 'edit' na commicie z sekretem
```

**Jeśli commit JUŻ poszedł na GitHuba:**

Czyszczenie historii (`filter-repo`, `--force`) jest wtórne i **nie rozwiązuje
problemu**. GitHub trzyma commity osiągalne przez API długo po przepisaniu
gałęzi, forki zachowują własne kopie, a każdy klon i cache CI ma swoją.
Traktuj sekret jako skompromitowany od momentu pushu i zacznij od rotacji:

```
1. UNIEWAZNIJ sekret u zrodla - to jedyny krok, ktory naprawde dziala:
   token Cloudflare       -> panel Cloudflare: usun token, wygeneruj nowy
   klucz IAM AWS          -> aws iam delete-access-key, potem create-access-key
   haslo Proxmoxa/Grafany -> zmien w panelu
   klucz SSH              -> usun z authorized_keys na WSZYSTKICH maszynach
   webhook Google Chat    -> usun integracje, utworz nowa
2. Wprowadz nowa wartosc: sops secrets.sops.yaml
3. Przewdroz: make infra / ansible-playbook, zaleznie od tego, co jej uzywa
4. Dopiero teraz, opcjonalnie, wyczysc historie - bez kroku 1 to teatr
5. Odnotuj incydent; przy kluczu AWS sprawdz CloudTrail pod katem uzycia
```

Prewencja jest tańsza niż rotacja: `git diff --staged` przed każdym commitem,
`git add` po ścieżce zamiast `-A`, sekrety wyłącznie w `*.sops.yaml`.

### Odzyskanie usuniętej gałęzi

```bash
git reflog                            # znajdź ostatni sha z tamtej gałęzi
git switch -c odzyskana <sha>
```

Reflog trzyma pozycje `HEAD` domyślnie 90 dni, więc "skasowałem gałąź przed
scaleniem" prawie nigdy nie jest sytuacją bez wyjścia.

Powiązane: [dowody/git-github.md](../dowody/git-github.md),
[dowody/ci.md](../dowody/ci.md), [dowody/cd.md](../dowody/cd.md),
[sops.md](sops.md), [RUNBOOK §13](../RUNBOOK.md).
