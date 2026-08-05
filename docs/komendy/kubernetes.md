# Kubernetes (k3s) - komendy

Klaster: `k3s-server-1` (control-plane) + `k3s-agent-1`, `k3s-agent-2`.
`kubectl` jest wbudowany w binarkę k3s - nie ma osobnej instalacji.
Wszystkie komendy poniżej idą przez `sudo`, bo `kubeconfig`
(`/etc/rancher/k3s/k3s.yaml`) czyta wyłącznie root.

```bash
ssh wf-k3s-server-1
sudo k3s kubectl get nodes
```

Wygodniej ustawić alias raz na maszynie (przetrwa do następnego logowania):

```bash
echo "alias k='sudo k3s kubectl'" >> ~/.bashrc && source ~/.bashrc
```

Poniżej `k` = `sudo k3s kubectl`.

> Wersja klastra: k3s v1.31.5+k3s1, Ubuntu 24.04. Aplikacja: chart Helm
> `wolffire` w namespace `wolffire` (deploymenty `wolffire-php`, `wolffire-nginx`,
> `wolffire-horizon`, `wolffire-scheduler`). **Zweryfikowano na żywo** 2026-08-05:
> `get nodes` (3/3 Ready), `get pods -n wolffire` (6/6 Running), `helm list`,
> `rollout history`.

---

## Przegląd

```bash
k get nodes -o wide                     # węzły, wersje, adresy
k get pods -A                           # WSZYSTKIE pody, wszystkie przestrzenie
k get pods -n wolffire -o wide          # pody aplikacji wraz z węzłem
k get svc -A                            # serwisy
k get ingress -A                        # wejścia HTTP (Traefik)
k get deploy,rs -n wolffire             # deploymenty i replicasety
k get events -A --sort-by=.lastTimestamp | tail -20
```

## Diagnostyka poda

```bash
k describe pod <nazwa> -n wolffire      # zdarzenia, powody restartów
k logs <nazwa> -n wolffire              # logi
k logs <nazwa> -n wolffire --previous   # logi POPRZEDNIEJ instancji po crashu
k logs -f deploy/wolffire-php -n wolffire
k exec -it <nazwa> -n wolffire -- sh    # powłoka w kontenerze
```

### Wektor debugowania CrashLoop / OOM

Kolejność ma znaczenie - `describe` mówi *dlaczego*, `logs --previous` mówi
*co się stało tuż przed śmiercią*:

1. `k get pods -n wolffire` - status `CrashLoopBackOff` / `OOMKilled`?
2. `k describe pod <nazwa> -n wolffire` - sekcja `Last State` (kod wyjścia,
   `Reason: OOMKilled` widać tu, nie w `logs`) i `Events` (restarty, ile razy).
3. `k logs <nazwa> -n wolffire --previous` - komunikat aplikacji tuż przed
   ubiciem. **Zwykłe `logs` (bez `--previous`) pokazuje log NOWEGO kontenera**
   po restarcie - pusty albo mylący, jeśli szukasz przyczyny poprzedniej śmierci.
4. Jeśli `OOMKilled` - `k describe pod` sekcja `Limits`/`Requests`, porównaj
   z `helm/wolffire/values.yaml`.

## Zasoby i kondycja

```bash
k top nodes                             # zużycie CPU/RAM węzłów
k top pods -A
k get pvc -A                            # wolumeny trwałe (local-path)
k get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type
```

## Helm

Chart trafia na maszynę przez Ansible (`ansible/roles/wolffire_prod`), CD robi
tylko `helm upgrade --set`. Values produkcyjne leżą na `k3s-server-1`
(`0600`, więc `sudo` jest konieczne).

```bash
sudo helm list -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml
sudo helm history wolffire -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml
sudo helm rollback wolffire <rewizja> -n wolffire --kubeconfig /etc/rancher/k3s/k3s.yaml

# Wdrożenie nowego tagu obrazu - dokładnie to robi pipeline CD
sudo helm upgrade wolffire /opt/wolffire/chart \
  --kubeconfig /etc/rancher/k3s/k3s.yaml -n wolffire \
  -f /opt/wolffire/values.yaml \
  --set image.tag=<sha> --wait --timeout 10m
```

## Rolling update i skalowanie

```bash
# Skalowanie
k scale deploy/wolffire-php -n wolffire --replicas=3
k get pods -n wolffire -w               # obserwuj, jak wstają

# Rolling update ręczny (poza Helmem - do szybkiego testu)
k set image deploy/wolffire-php php=ghcr.io/serwin35/wf-chartapp-diploma/php:<sha> -n wolffire
k rollout status deploy/wolffire-php -n wolffire
k rollout history deploy/wolffire-php -n wolffire
k rollout undo deploy/wolffire-php -n wolffire      # wycofanie o jedną rewizję
```

Poza demonstracją zmianę obrazu wprowadza `helm upgrade --set image.tag=...`
(patrz wyżej), nie `kubectl set image` - inaczej `values.yaml` na dysku
przestaje odpowiadać rzeczywistemu stanowi klastra.

## Przełożenie podów między węzłami

```bash
k drain k3s-agent-1 --ignore-daemonsets --delete-emptydir-data
k get pods -n wolffire -o wide          # pody są już na agent-2
k uncordon k3s-agent-1
```

Najmocniejszy pojedynczy pokaz Kubernetesa na obronie: `drain` widocznie
przenosi ruch na drugi węzeł, `uncordon` przywraca stan.

## Port-forward

```bash
sudo k3s kubectl port-forward -n wolffire deploy/wolffire-php 9000:9000
```

Przydaje się do podłączenia lokalnego narzędzia (np. debuggera PHP) wprost do
poda, z pominięciem Service i Ingress.

## Częste problemy

| Objaw | Przyczyna | Sprawdź |
|---|---|---|
| `command not found: kubectl` | `kubectl` nie jest samodzielnym binarnym plikiem w tej instalacji | Użyj `sudo k3s kubectl` albo alias `k` |
| `The connection to the server localhost:8080 was refused` | Brak `--kubeconfig`, albo brak `sudo` | Dodaj `sudo` i/lub `--kubeconfig /etc/rancher/k3s/k3s.yaml` (helm) |
| Pod `Pending` | Brak zasobów na węźle albo PVC nie może się przypiąć | `k describe pod` -> sekcja `Events`; `k get pvc -A` |
| Pod `CrashLoopBackOff` | Aplikacja pada przy starcie | `k logs --previous` (patrz wektor debugowania wyżej) |
| `helm upgrade` wisi do timeoutu | `--wait` czeka na `Ready` wszystkich podów, a jeden nie wstaje | `k get pods -n wolffire -w` w drugim terminalu podczas `upgrade` |
| Po `drain` pody nie wstają na drugim węźle | Za mało zasobów na pozostałych węzłach albo `PodDisruptionBudget` blokuje | `k get events -n wolffire --sort-by=.lastTimestamp` |
