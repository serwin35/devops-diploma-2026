# SOPS - komendy

SOPS trzyma w tym repozytorium wszystkie sekrety - zaszyfrowane, w gicie, obok
kodu, który ich używa. Nie ma osobnego magazynu haseł ani pliku `.env`
przesyłanego kanałem obocznym. Klucz prywatny (age) jest jedyną rzeczą, która
nigdy nie trafia do repozytorium.

> Wersje: `sops 3.13.3`, szyfrowanie kluczem age (`age-keygen` z pakietu `age`).
> Odbiorca: jeden klucz publiczny (`mateusz`) zadeklarowany w
> [`.sops.yaml`](../../.sops.yaml). Klucz prywatny:
> `~/.config/sops/age/keys.txt`. **Zweryfikowano na żywo** 2026-08-05:
> `sops exec-env` z podstawieniem zmiennych do Terraforma.

Kontekst architektoniczny (dlaczego dwa pliki, jaki jest podział
odpowiedzialności): [PRZEWODNIK §2](../PRZEWODNIK.md#2-root-repozytorium).
Skrót operacyjny: [RUNBOOK §10](../RUNBOOK.md).

---

## 1. `make` jako wejście

| Cel `make` | Co uruchamia pod spodem (dosłownie) | Kiedy używać |
|---|---|---|
| `make secrets` | `sops secrets.sops.yaml` | Dodanie albo zmiana poświadczenia **dostawcy** (Proxmox, Cloudflare, AWS). Otwiera odszyfrowaną treść w `$EDITOR` |
| `make secrets-app` | `sops ansible/group_vars/all/secrets.sops.yml` | To samo dla sekretów **wnętrza infrastruktury**: hasła baz, Grafany, Jenkinsa, klucz aplikacji |
| `make tf-plan` / `make tf-apply` | `sops exec-env secrets.sops.yaml '<terraform ...>'` | Sekrety wchodzą do Terraforma jako zmienne środowiskowe procesu potomnego |
| `make ansible-apply` / `make ansible-check` | `sops exec-env secrets.sops.yaml 'cd ansible && ansible-playbook playbook.yml [--check --diff]'` | To samo dla Ansible - rola `cloudflared` potrzebuje kluczy AWS, żeby odczytać token tunelu ze stanu |
| `make bootstrap-aws` | `sops exec-env secrets.sops.yaml 'terraform -chdir=terraform/bootstrap ...'` | Bootstrap AWS z poświadczeniami z SOPS-a |

Pierwsza linia `Makefile`, która dotyczy sekretów, jest tak samo ważna jak same
cele:

```make
export SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

SOPS_ENV := sops exec-env secrets.sops.yaml
```

### Co `make` dokłada do gołego `sops`

Cele `make` nie robią niczego, czego nie da się napisać ręcznie - opakowują
trzy rzeczy, o których trzeba pamiętać przy surowym wywołaniu:

1. **Klucz age wskazany jawnie.** SOPS domyślnie szuka klucza pod ścieżką XDG,
   a ta różni się między systemami: na macOS to
   `~/Library/Application Support/sops/age/keys.txt`, na Linuksie
   `~/.config/sops/age/keys.txt`. `Makefile` ustawia `SOPS_AGE_KEY_FILE` na
   wariant linuksowy, więc to samo repozytorium działa na laptopie i na agencie
   Jenkinsa bez rozjazdu. Operator `?=` sprawia, że własna wartość ze środowiska
   ma pierwszeństwo.
2. **Sekrety nie lądują na dysku.** `sops exec-env` odszyfrowuje plik w pamięci
   i przekazuje pary `KLUCZ=wartość` jako zmienne środowiskowe procesu
   potomnego. Nie powstaje plik tymczasowy, nic nie wpada do historii powłoki,
   a po zakończeniu procesu wartości znikają razem z nim.
3. **Jedna nazwa pliku w jednym miejscu.** Zmienna `SOPS_ENV` jest zdefiniowana
   raz i użyta w czterech celach - nie da się przez pomyłkę wskazać innego pliku
   sekretów w jednym z nich.

---

## 2. Dwa pliki z sekretami

| Plik | Zawiera | Kto czyta |
|---|---|---|
| `secrets.sops.yaml` (korzeń repozytorium) | Poświadczenia **zewnętrznych dostawców**: Proxmox, Cloudflare, AWS (stan), AWS (kopie zapasowe), token Composera | Terraform i Ansible przez `sops exec-env` w `Makefile` |
| `ansible/group_vars/all/secrets.sops.yml` | Sekrety **wewnątrz infrastruktury**: hasła baz, `APP_KEY`, tokeny GHCR/Jenkinsa/Grafany, hasło resticu, webhooki powiadomień | Ansible sam, w locie (`vars_plugins_enabled = community.sops` w `ansible.cfg`) - **bez osobnego kroku** |

Rozdzielenie jest celowe: inne cykle rotacji, inni czytelnicy, inny promień
rażenia przy wycieku.

Nazwy kluczy są jawne (SOPS szyfruje wyłącznie wartości), więc można je
wypisać bez odszyfrowywania czegokolwiek:

```console
$ grep -E '^[a-zA-Z_]+:' secrets.sops.yaml | sed 's/:.*/:/'
PROXMOX_VE_API_TOKEN:
PROXMOX_VE_INSECURE:
CLOUDFLARE_API_TOKEN:
AWS_ACCESS_KEY_ID:
AWS_SECRET_ACCESS_KEY:
BACKUP_AWS_ACCESS_KEY_ID:
BACKUP_AWS_SECRET_ACCESS_KEY:
COMPOSER_AUTH_JSON:
sops:
```

Nazwy w `secrets.sops.yaml` są **wielkimi literami nie przez przypadek**: trafią
one wprost do środowiska procesu, więc muszą się zgadzać z tym, czego szukają
providery (`PROXMOX_VE_API_TOKEN`, `CLOUDFLARE_API_TOKEN`,
`AWS_ACCESS_KEY_ID`). Plik ansiblowy używa z kolei małych liter, bo jego klucze
stają się zwykłymi zmiennymi Ansible (`jenkins_admin_password`,
`wolffire_db_password`, `restic_password`).

### Dwa komplety kluczy AWS

`secrets.sops.yaml` trzyma dwa niezależne komplety poświadczeń AWS:

- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` - użytkownik IAM
  `wolffire-tf-state`, prawa **tylko** do bucketa ze stanem Terraforma
  (`terraform-states-wf`),
- `BACKUP_AWS_ACCESS_KEY_ID` / `BACKUP_AWS_SECRET_ACCESS_KEY` - użytkownik
  `wolffire-jenkins-backup`, prawa **tylko** do bucketa kopii zapasowych
  (`wolffire-backups`), i to bez `DeleteObject` na danych.

Dlatego `aws s3 ls s3://wolffire-backups/` po zwykłym `sops exec-env` kończy się
`AccessDenied`. To nie jest błąd konfiguracji, tylko zamierzone rozdzielenie
uprawnień (`terraform/bootstrap/iam.tf`). Obejście w sekcji 3.4.

---

## 3. Codzienna praca

### 3.1 Jak dodać albo zmienić sekret

```bash
# Poświadczenia dostawców: Proxmox, Cloudflare, AWS
sops secrets.sops.yaml

# Sekrety wnętrza infrastruktury: hasła baz, Grafany, Jenkinsa, klucz aplikacji
sops ansible/group_vars/all/secrets.sops.yml

# Wymuszenie konkretnego edytora na jedno wywołanie
SOPS_EDITOR="code --wait" sops secrets.sops.yaml
```

> Albo krócej: `make secrets` i `make secrets-app` - dokładnie te dwa
> wywołania. Przydatne głównie dlatego, że nie trzeba pamiętać ścieżki do
> pliku ansiblowego.

SOPS otwiera odszyfrowaną treść w `$EDITOR` (albo `$SOPS_EDITOR`). Po zapisie
i zamknięciu edytora plik jest ponownie szyfrowany na odbiorców z `.sops.yaml`.
Jawna treść żyje wyłącznie w pliku tymczasowym edytora, przez czas sesji.

Jeżeli plik jeszcze nie istnieje, SOPS tworzy go od zera i szyfruje regułą
pasującą do jego ścieżki.

### 3.2 Jak podejrzeć hasło bez wchodzenia w edytor

```bash
# Cały plik na standardowe wyjście
sops --decrypt secrets.sops.yaml
sops --decrypt ansible/group_vars/all/secrets.sops.yml

# Jedna wartość, bez reszty pliku i bez jq
sops --decrypt --extract '["CLOUDFLARE_API_TOKEN"]' secrets.sops.yaml
sops --decrypt --extract '["jenkins_admin_password"]' ansible/group_vars/all/secrets.sops.yml
```

Selektor w `--extract` jest w składni podobnej do `jq`. Dla struktur
zagnieżdżonych łańcuchujesz nawiasy: `'["klucz"]["podklucz"]'`, dla list
używasz indeksu: `'["klucz"][0]'`.

Praktyczna uwaga: `--extract` nie dokleja znaku nowej linii tam, gdzie wartość
go nie ma, więc nadaje się do podstawiania w innych komendach:

```bash
kubectl create secret generic app \
  --from-literal=key="$(sops --decrypt --extract '["wolffire_app_key"]' \
     ansible/group_vars/all/secrets.sops.yml)"
```

### 3.3 Jak zmienić jedną wartość bez edytora

```bash
sops --set '["CLOUDFLARE_API_TOKEN"] "nowy-token"' secrets.sops.yaml
sops --set '["jenkins_admin_password"] "nowe-haslo"' \
  ansible/group_vars/all/secrets.sops.yml
```

Argument to selektor, spacja i **wartość w składni JSON** - stąd cudzysłowy
wokół łańcucha znaków. Wygodne w skryptach i w CI, gdzie nie ma interaktywnego
edytora. Uwaga na historię powłoki: wartość zostaje w `~/.zsh_history`. Przy
prawdziwym sekrecie albo poprzedź komendę spacją (jeśli masz
`HIST_IGNORE_SPACE`), albo użyj `make secrets`.

### 3.4 Jak uruchomić coś z sekretami w środowisku

```bash
# Podstawowy wzorzec - dokładnie to, co robi Makefile
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan'

# Szybki test, czy podstawienie w ogóle działa (bez ujawniania wartości)
sops exec-env secrets.sops.yaml 'env | grep -c TOKEN'
```

```text
2
```

Podmiana nazw zmiennych w locie - tak wywołuje się `aws-cli` kluczem backupowym
zamiast domyślnego klucza stanu:

```bash
sops exec-env secrets.sops.yaml \
  'AWS_ACCESS_KEY_ID=$BACKUP_AWS_ACCESS_KEY_ID \
   AWS_SECRET_ACCESS_KEY=$BACKUP_AWS_SECRET_ACCESS_KEY \
   aws s3 ls s3://wolffire-backups/ --region eu-north-1'
```

Cudzysłowy pojedyncze są tu konieczne: `$BACKUP_...` ma zostać rozwinięty przez
powłokę **potomną**, uruchomioną już z sekretami, a nie przez tę, w której
piszesz komendę.

### 3.5 Kiedy `exec-env` nie wystarcza

Gdy narzędzie chce ścieżkę do pliku, a nie zmiennych środowiskowych:

```bash
sops exec-file secrets.sops.yaml 'cat {}'
```

SOPS tworzy odszyfrowany plik tymczasowy (domyślnie w potoku FIFO, nie na
dysku), podstawia jego ścieżkę pod `{}` i sprząta po zakończeniu procesu.
W tym repozytorium nieużywane, ale to właściwa odpowiedź na pytanie "a jak
podać sekret programowi, który czyta tylko z pliku".

---

## 4. Operacje rzadsze

### 4.1 Jak dodać drugą osobę do odszyfrowywania

```bash
# 1. Nowa osoba generuje parę kluczy U SIEBIE i przekazuje TYLKO publiczny
age-keygen -o ~/.config/sops/age/keys.txt
# Public key: age1...
```

Dopisz jej klucz publiczny do `.sops.yaml`:

```yaml
keys:
  - &mateusz age1uh03ryvvtamnh2tzs94x8yqfzc20spuga9679jpkkednvjgccywqsuuye8
  - &anna    age1...

creation_rules:
  - path_regex: \.sops\.ya?ml$
    key_groups:
      - age:
          - *mateusz
          - *anna
```

Potem przepisz istniejące pliki na nowy zestaw odbiorców:

```bash
sops updatekeys secrets.sops.yaml
sops updatekeys ansible/group_vars/all/secrets.sops.yml
```

`updatekeys` pyta o potwierdzenie i wypisuje, kogo dodaje albo usuwa. Od tej
chwili obie osoby deszyfrują pliki własnym kluczem prywatnym - żaden sekret nie
przechodzi między nimi żadnym kanałem.

**Ważne:** `updatekeys` trzeba uruchomić na **każdym** zaszyfrowanym pliku
osobno. Sama zmiana w `.sops.yaml` działa wyłącznie na pliki tworzone od nowa.

### 4.2 Jak zrotować klucz age

Procedura dwuetapowa, żeby w żadnym momencie nie zostać bez dostępu:

```bash
# 1. Nowa para kluczy
age-keygen -o ~/.config/sops/age/keys-new.txt

# 2. Dopisz NOWY klucz publiczny do .sops.yaml OBOK starego (nie podmieniaj)
#    - w `keys:` nowy alias, w `key_groups:` obie kotwice

# 3. Przepisz pliki na oba klucze naraz
sops updatekeys secrets.sops.yaml
sops updatekeys ansible/group_vars/all/secrets.sops.yml

# 4. Sprawdź, że NOWY klucz faktycznie działa
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys-new.txt \
  sops --decrypt secrets.sops.yaml > /dev/null && echo OK

# 5. Dopiero teraz usuń stary klucz z .sops.yaml i powtórz updatekeys
sops updatekeys secrets.sops.yaml
sops updatekeys ansible/group_vars/all/secrets.sops.yml

# 6. Podmień plik klucza używany na co dzień
mv ~/.config/sops/age/keys-new.txt ~/.config/sops/age/keys.txt
```

`updatekeys` re-szyfruje wyłącznie **klucz danych** (data key) dla nowego
zestawu odbiorców. Nie dotyka samych wartości, więc nie musisz znać ani jednego
hasła, żeby kogoś dodać lub usunąć.

Jeżeli wyciekł nie klucz age, tylko konkretny sekret (token providera), rotacja
klucza age niczego nie załatwia - trzeba unieważnić token u dostawcy i wpisać
nowy przez `make secrets`.

### 4.3 Jak zmienić klucz danych, zostawiając odbiorców

```bash
sops rotate --in-place secrets.sops.yaml
```

Generuje nowy klucz danych i przeszyfrowuje nim wszystkie wartości. Stosowane,
gdy podejrzewasz, że wyciekła odszyfrowana kopia pliku - stary klucz danych
przestaje wtedy być cokolwiek wart.

### 4.4 Jak sprawdzić, czy plik jest zaszyfrowany

```bash
sops filestatus secrets.sops.yaml
```

```text
{"encrypted":true}
```

Przydatne w hooku pre-commit albo gdy po awarii edytora nie masz pewności, co
zapisałeś.

---

## 5. Troubleshooting

| Objaw | Przyczyna | Naprawa |
|---|---|---|
| `Failed to get the data key required to decrypt the SOPS file` | Brak klucza age albo klucz nie pasuje do żadnego odbiorcy w pliku | `echo $SOPS_AGE_KEY_FILE` i `ls -l "$SOPS_AGE_KEY_FILE"`. Jeśli plik istnieje, sprawdź, czy jego `public key` figuruje w `.sops.yaml`; jeśli nie - potrzebujesz `updatekeys` od kogoś, kto ma dostęp |
| Działa `make tf-plan`, nie działa gołe `sops --decrypt` | `SOPS_AGE_KEY_FILE` ustawia dopiero `Makefile`; w gołej powłoce SOPS szuka klucza pod ścieżką XDG systemu | `export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt` w bieżącej sesji, albo na stałe w `~/.zshrc` |
| macOS: klucz działa w terminalu, nie działa w PhpStormie albo VS Code | Aplikacje GUI nie czytają `~/.zshrc`, więc nie widzą wyeksportowanej zmiennej | Albo trzymaj klucz **także** pod macOS-ową ścieżką XDG: `mkdir -p ~/Library/Application\ Support/sops/age && ln -s ~/.config/sops/age/keys.txt ~/Library/Application\ Support/sops/age/keys.txt`, albo uruchamiaj wszystko przez `make` |
| `Error: MAC mismatch. File has ... expected ...` | Plik został zmieniony poza SOPS-em (ręczna edycja zaszyfrowanej treści, sklejenie konfliktu w gitcie, `sed` na pliku) | Nie da się tego "naprawić" - MAC chroni integralność. Odtwórz plik z historii gita (`git checkout HEAD -- secrets.sops.yaml`) i nanieś zmianę ponownie przez `make secrets` |
| Konflikt w gitcie na `secrets.sops.yaml` | Dwie osoby zmieniły plik; zaszyfrowane bloki nie scalają się liniowo | Weź jedną wersję w całości (`git checkout --theirs` albo `--ours`), potem `make secrets` i nanieś brakujące klucze ręcznie. Nigdy nie scalaj zaszyfrowanych linii |
| `git diff` pokazuje zmiany, choć nic nie zmieniłeś | SOPS przy każdym zapisie generuje nowy wektor inicjujący i nowy `lastmodified` | Zachowanie normalne. Jeśli przeszkadza, zamknij edytor bez zapisu, gdy nic nie zmieniałeś |
| Ansible nie widzi sekretu, zmienna pusta | Wyłączony plugin albo brak klucza age na maszynie, z której odpalasz playbook | `grep vars_plugins_enabled ansible/ansible.cfg` (ma zawierać `community.sops`) oraz `echo $SOPS_AGE_KEY_FILE` |
| Terraform: `No valid credential sources found` | Komenda uruchomiona bez `sops exec-env` | Owiń wywołanie albo użyj celu `make` (patrz [`terraform.md`](terraform.md)) |
| `AccessDenied` przy `aws s3 ls s3://wolffire-backups/` | Użyty klucz IAM stanu Terraforma, który celowo nie ma dostępu do bucketa kopii | Podstaw `BACKUP_AWS_ACCESS_KEY_ID` / `BACKUP_AWS_SECRET_ACCESS_KEY` (sekcja 3.4) |
| Nowo utworzony plik `*.sops.yml` nie jest szyfrowany | Ścieżka nie pasuje do `path_regex` w `.sops.yaml` | Reguła to `\.sops\.ya?ml$` - nazwa pliku musi kończyć się na `.sops.yaml` albo `.sops.yml` |

---

## 6. Jak to działa

### Szyfrowanie asymetryczne z jednym kluczem danych

SOPS nie szyfruje pliku kluczem age bezpośrednio. Losuje **klucz danych**
(symetryczny, AES256-GCM), szyfruje nim każdą wartość z osobna, a sam klucz
danych szyfruje kluczem publicznym każdego odbiorcy. Blok `sops:` na końcu
pliku przechowuje te zaszyfrowane kopie:

```yaml
sops:
    age:
        - enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
            -----END AGE ENCRYPTED FILE-----
          recipient: age1uh03ryvvtamnh2tzs94x8yqfzc20spuga9679jpkkednvjgccywqsuuye8
    lastmodified: "2026-08-04T22:07:01Z"
    mac: ENC[AES256_GCM,data:...]
    unencrypted_suffix: _unencrypted
    version: 3.13.3
```

Z tej konstrukcji wynikają dwie użyteczne własności. Po pierwsze, dodanie
odbiorcy to tylko doszyfrowanie klucza danych jego kluczem publicznym - stąd
`updatekeys` działa bez znajomości samych sekretów. Po drugie, `mac` jest
sumą kontrolną **całej** zawartości: każda ręczna modyfikacja pliku poza SOPS-em
zostanie wykryta przy pierwszej próbie odszyfrowania.

### Szyfrowane są wartości, nie nazwy kluczy

To decyzja projektowa SOPS-a i praktyczna zaleta w gicie: `git diff` pokazuje,
**który** sekret się zmienił, nie ujawniając czym on jest. Przegląd zmian
w pull requeście ma więc sens, mimo że treść pozostaje nieczytelna.

Wyjątek działa w drugą stronę: klucze z sufiksem `_unencrypted` zostają jawne
w całości. W tym repozytorium nie jest to używane.

### Reguły w `.sops.yaml`

```yaml
creation_rules:
  - path_regex: \.sops\.ya?ml$
    key_groups:
      - age:
          - *mateusz
```

Jedna reguła obejmuje wszystkie pliki sekretów w repozytorium: zarówno
`secrets.sops.yaml` w korzeniu, jak i `ansible/group_vars/all/secrets.sops.yml`.
Dzięki temu `sops <plik>` nie wymaga podawania odbiorcy w wierszu poleceń -
SOPS dopasowuje ścieżkę do reguły i sam wie, na kogo szyfrować.

`creation_rules` dotyczą **tworzenia** pliku. Plik już zaszyfrowany nosi listę
odbiorców w swoim bloku `sops:` i to ona rozstrzyga przy edycji - dlatego zmiana
`.sops.yaml` bez `updatekeys` nie zmienia niczego w istniejących plikach.

### Dwie drogi odszyfrowania w tym repozytorium

| Konsument | Mechanizm | Kiedy |
|---|---|---|
| Terraform | `sops exec-env` w `Makefile` - wartości jako zmienne środowiskowe procesu | `make tf-plan`, `make tf-apply`, `make bootstrap-aws` |
| Ansible | Plugin `community.sops` (`vars_plugins_enabled` w `ansible.cfg`) - odszyfrowanie `group_vars/**/*.sops.yml` przy starcie playbooka | Każde uruchomienie `ansible-playbook`, także `--check` |

Ansible **nie** potrzebuje `sops exec-env` do własnych sekretów, bo robi to
plugin. Potrzebuje go natomiast do poświadczeń AWS: rola `cloudflared` czyta
token tunelu ze stanu Terraforma w S3 (`cloud.terraform.terraform_output`),
a bez kluczy w środowisku pada na `No valid credential sources found`, zanim
dojdzie do reszty ról. Stąd `sops exec-env` również w celu `make ansible-apply`.

### Czego SOPS nie chroni

Odszyfrowany sekret w środowisku procesu jest widoczny dla tego procesu i jego
potomków. `sops exec-env ... 'env'` wypisze wszystko jawnym tekstem, a każdy
program uruchomiony w tej powłoce potomnej ma do tych wartości dostęp. SOPS
rozwiązuje problem **przechowywania i dystrybucji** sekretów, nie ich izolacji
w czasie wykonania. Dlatego zakres kluczy jest zawężony po stronie dostawcy
(dwa osobne konta IAM zamiast jednego, token Proxmoxa z ograniczonymi
uprawnieniami), a nie tylko po stronie pliku.
