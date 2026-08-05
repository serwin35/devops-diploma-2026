#!/usr/bin/env bash
# Przenosi dane aplikacji z dev na prod: zrzut bazy dev (kontener Postgresa
# na maszynie dev) -> odtworzenie na prod (natywny Postgres na prod-db),
# potem czyszczenie osieroconych kluczy aplikacji w Redisie i restart
# horizona, żeby nie mielił jobów wskazujących na dane sprzed podmiany.
#
# Użycie: ./scripts/sync-dev-db-to-prod.sh   (z katalogu głównego repo)
#
# Kontekst: DemoSeeder korzysta z fake(), a obraz produkcyjny nie zawiera
# zależności deweloperskich (fakerphp/faker) - seed możliwy tylko na dev,
# na prod wędruje gotowy zrzut.
set -euo pipefail

SSH="ssh -F ansible/ssh_config"
DEV_HOST=wf-wolffire-dev-app-1
PROD_DB_HOST=wf-wolffire-prod-db-1
K3S_HOST=wf-k3s-server-1
DUMP=$(mktemp /tmp/wolffire-dev-XXXX.dump)
trap 'rm -f "$DUMP"' EXIT

echo "==> Zrzut bazy dev (kontener wolffire-postgres)"
$SSH $DEV_HOST "sudo docker exec wolffire-postgres pg_dump -U wolffire -d wolffire -Fc" > "$DUMP"
ls -lh "$DUMP"

echo "==> Odtworzenie na prod (z zerwaniem aktywnych sesji aplikacji)"
$SSH $PROD_DB_HOST "sudo -u postgres psql -d wolffire -tAc \
  \"select pg_terminate_backend(pid) from pg_stat_activity where datname='wolffire' and pid<>pg_backend_pid();\" >/dev/null"
# --clean --if-exists: zrzut sam usuwa i odtwarza obiekty; --no-owner plus
# ALTER ROLE niżej gwarantują, że właścicielem zostaje user aplikacji.
$SSH $PROD_DB_HOST "sudo -u postgres pg_restore -d wolffire --clean --if-exists --no-owner --exit-on-error" < "$DUMP"
# REASSIGN OWNED BY postgres jest zabronione (rola systemowa), więc własność
# przepinamy per obiekt: tabele, sekwencje i widoki schematu public.
$SSH $PROD_DB_HOST "sudo -u postgres psql -q -d wolffire -c \"DO \\\$\\\$ DECLARE r record; BEGIN \
  FOR r IN SELECT tablename AS n FROM pg_tables WHERE schemaname='public' LOOP EXECUTE format('ALTER TABLE public.%I OWNER TO wolffire', r.n); END LOOP; \
  FOR r IN SELECT sequencename AS n FROM pg_sequences WHERE schemaname='public' LOOP EXECUTE format('ALTER SEQUENCE public.%I OWNER TO wolffire', r.n); END LOOP; \
  FOR r IN SELECT table_name AS n FROM information_schema.views WHERE table_schema='public' LOOP EXECUTE format('ALTER VIEW public.%I OWNER TO wolffire', r.n); END LOOP; \
END \\\$\\\$;\""

echo "==> Czyszczenie kluczy aplikacji w Redisie (osierocone joby/cache)"
$SSH $PROD_DB_HOST 'PASS=$(sudo grep -oP "(?<=^requirepass ).*" /etc/redis/redis.conf); \
  for db in 0 1; do \
    redis-cli -h 10.0.140.10 -a "$PASS" -n $db --no-auth-warning --scan --pattern "*wolffire*" \
      | xargs -r -n 50 redis-cli -h 10.0.140.10 -a "$PASS" -n $db --no-auth-warning del >/dev/null; \
  done'

echo "==> Restart horizona i czyszczenie cache aplikacji"
$SSH $K3S_HOST "sudo k3s kubectl exec -n wolffire deploy/wolffire-php -- php artisan optimize:clear >/dev/null \
  && sudo k3s kubectl rollout restart deploy/wolffire-horizon -n wolffire \
  && sudo k3s kubectl rollout status deploy/wolffire-horizon -n wolffire --timeout=120s"

echo "==> Weryfikacja"
$SSH $K3S_HOST "sudo k3s kubectl exec -n wolffire deploy/wolffire-php -- php artisan tinker \
  --execute=\"echo 'users: '.App\\\\Models\\\\User::count().' | firmy: '.App\\\\Models\\\\Company::count();\""
curl -s --max-time 15 -o /dev/null -w "wolffire.dev: %{http_code}\n" -L https://wolffire.dev

echo "GOTOWE"
