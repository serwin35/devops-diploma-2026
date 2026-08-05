# SEKCJA 5: bazy danych.
#
# Testy idą z wnętrza maszyny bazodanowej, bo firewall celowo nie wpuszcza tam
# nikogo poza segmentem k3s - i to właśnie sprawdza sekcja 6. Obie usługi
# nasłuchują na adresie prywatnym (bind {{ private_ip }}), nie na loopbacku,
# więc odpytujemy je po $DB_IP, a nie po 127.0.0.1.

_check_postgres_ready() {
    if ssh_do wolffire-prod-db-1 "pg_isready -h $DB_IP -p $POSTGRES_PORT -t 5" >/dev/null; then
        ok "PostgreSQL: pg_isready na $DB_IP:$POSTGRES_PORT"
    else
        ko "PostgreSQL: pg_isready na $DB_IP:$POSTGRES_PORT" "baza nie przyjmuje polaczen"
    fi
}

# Hasło odszyfrowywane RAZ i podawane przez stdin do zmiennej REDISCLI_AUTH.
# Dzięki temu nie ma go ani w argumentach `ssh` (widocznych lokalnie), ani
# w `ps` na maszynie docelowej - inaczej niż przy `redis-cli -a <haslo>`.
_check_redis_ping() {
    local password pong
    password="$(secret_get wolffire_redis_password)"

    if [ -z "$password" ]; then
        skip "Redis: PING -> PONG" "nie udalo sie odszyfrowac wolffire_redis_password"
        return
    fi

    pong="$(printf '%s\n' "$password" | ssh_do wolffire-prod-db-1 \
        "read -r REDISCLI_AUTH; export REDISCLI_AUTH; redis-cli --no-auth-warning -h $DB_IP -p $REDIS_PORT PING")"
    unset password

    if [ "$pong" = "PONG" ]; then
        ok "Redis: uwierzytelnione PING -> PONG"
    else
        ko "Redis: uwierzytelnione PING -> PONG" "otrzymano: ${pong:-brak odpowiedzi}"
    fi
}

# pg_up / redis_up równe 1 znaczy, że eksporter nie tylko odpowiada na /metrics,
# ale faktycznie połączył się ze swoją bazą. Sam kod 200 na /metrics niczego tu
# nie dowodzi - eksporter wystawia je także wtedy, gdy nie ma połączenia.
_check_exporter_metric() {
    local label="$1" port="$2" metric_name="$3"
    local line

    line="$(ssh_do wolffire-prod-db-1 \
        "curl -s --max-time 6 http://$DB_IP:$port/metrics | grep -E '^$metric_name '")"

    if [ "$(printf '%s' "$line" | awk '{print $2}')" = "1" ]; then
        ok "$label :$port -> $metric_name 1"
    else
        ko "$label :$port -> $metric_name 1" "otrzymano: ${line:-brak metryki}"
    fi
}

check_databases() {
    section "5. Bazy danych (z wnetrza wolffire-prod-db-1)"
    _check_postgres_ready
    _check_redis_ping
    _check_exporter_metric "postgres_exporter" "$POSTGRES_EXPORTER_PORT" "pg_up"
    _check_exporter_metric "redis_exporter"    "$REDIS_EXPORTER_PORT"    "redis_up"
}
