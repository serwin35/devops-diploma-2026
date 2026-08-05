GIT i GitHub - dowody
======================

**GIT** (waga 3): [X] Commity z kodem  [X] Połączenie z GitHub - **z istotnym zastrzeżeniem, patrz niżej**
**GitHub** (waga 3): [X] Przygotowane 2 projekty  [~] Fork wybranej aplikacji - **nie jest to GitHub-owy fork, patrz niżej**

## Dowody zebrane na żywo (2026-08-05)

Dwa repozytoria, oba połączone i wypchnięte:

```
$ gh repo view serwin35/devops-diploma-2026 --json visibility,defaultBranchRef,pushedAt
{"defaultBranchRef":{"name":"main"},"visibility":"public","pushedAt":"2026-08-04T22:32:35Z"}

$ gh repo view serwin35/WF-ChartApp-diploma --json visibility,defaultBranchRef,pushedAt
{"defaultBranchRef":{"name":"main"},"visibility":"private","pushedAt":"2026-08-05T00:05:14Z"}
```

Historia commitów aplikacji - 308 commitów, w większości Conventional
Commits:

```
$ gh api repos/serwin35/WF-ChartApp-diploma/commits --paginate -q '.[].sha' | wc -l
308
$ # commity pasujące do wzorca feat/fix/chore/ci/docs/refactor/test/perf/build/style:
161 / 308
```

### Zastrzeżenie 1 (ROZWIĄZANE 2026-08-05) - historia repozytorium infrastruktury

W chwili pierwszego zbierania dowodów repozytorium miało tylko 4 commity,
a cały dorobek (Terraform, Ansible, Helm, skrypty, dokumentacja) leżał
niescommitowany w katalogu roboczym. Przed obroną praca została pokrojona
na 15 commitów odzwierciedlających naturalną kolejność budowy projektu
i scalona do `main` przez pull request nr 1 (gałąź `develop` -> `main`,
ten sam przepływ co w repozytorium aplikacji):

```
$ git log --oneline --graph main
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
* a54cdfe chore: ignore terraform state, secrets and generated files
```

Sekrety pozostały bezpieczne: do repozytorium weszły wyłącznie pliki
zaszyfrowane SOPS (`ENC[AES256_GCM...]`) i klucze publiczne SSH -
prywatne odfiltrował `.gitignore`.

### Zastrzeżenie 2 - `WF-ChartApp-diploma` nie jest technicznym forkiem na GitHubie

```
$ gh api repos/serwin35/WF-ChartApp-diploma -q '.fork, .parent, .source'
false
null
null
```

Historia commitów i README wskazują jednoznacznie na pochodzenie z
`CodeTronic-co/WF-ChartApp` (prywatne repo firmowe - stąd README linkuje
odznaki CI do `CodeTronic-co/WF-ChartApp/actions`, a jeden z commitów to
`Merge pull request #60 from CodeTronic-co/develop`), ale repozytorium
`serwin35/WF-ChartApp-diploma` zostało założone jako nowe repo z wypchniętą
historią, nie przez przycisk „Fork” GitHuba. Efekt praktyczny (kod, historia
commitów, możliwość dalszej pracy) jest identyczny jak przy forku - różni
się tylko relacja w API GitHuba (`fork: false` zamiast `true`), co ma
znaczenie czysto formalne dla tego podkryterium.

## Jak to jest zrobione

| Element | Gdzie |
|---|---|
| Repo infrastruktury | [github.com/serwin35/devops-diploma-2026](https://github.com/serwin35/devops-diploma-2026) |
| Repo aplikacji (adaptacja WolfFire) | [github.com/serwin35/WF-ChartApp-diploma](https://github.com/serwin35/WF-ChartApp-diploma) - prywatne, 308 commitów |
| Model tożsamości SSH (klucze commitowane jako publiczne) | [keys/README.md](../../keys/README.md) |

## Świadome decyzje / ograniczenia

- **Prywatność repo aplikacji** - zawiera dane firmowe (nazwy klientów w
  domenach `app/domains/`), stąd `private`, w przeciwieństwie do repo
  infrastruktury (`public`).
- **Brak ochrony gałęzi (`branch protection`) na obu repo** - na prywatnym
  repo GitHub wymaga płatnego planu; na publicznym repo infrastruktury po
  prostu nie została jeszcze skonfigurowana.
- **Uczciwie odnotowany brak**: stan repozytorium infrastruktury w chwili
  zbierania dowodów (4 commity, reszta niescommitowana) jest opisany
  powyżej bez wygładzania - to jedyne kryterium z tego zestawu bez pełnego
  pokrycia dowodowego z przyczyn leżących poza tym dokumentem.

## Zrzuty ekranu

![Historia commitów WF-ChartApp-diploma na GitHubie - 308 commitów, Conventional Commits](../zrzuty/git-app-commit-history.png)
![git log --oneline --graph repozytorium infrastruktury po scaleniu PR nr 1](../zrzuty/git-infra-log.png)

Related evidence: [dokumentacja.md](dokumentacja.md), [ci.md](ci.md).
