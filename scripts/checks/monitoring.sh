# SEKCJA 3: stos monitoringu oglądany od środka.
#
# Wszystkie zapytania idą z monitoring-1, bo usługi nasłuchują wyłącznie na
# adresie prywatnym - z zewnątrz widać je tylko przez tunel Cloudflare, który
# sprawdza sekcja 2. Tu interesuje nas stan samych usług, nie droga do nich.

_check_prometheus_ready() {
    local code
    code="$(ssh_http_code monitoring-1 "http://$MONITORING_IP:$PROMETHEUS_PORT/-/ready")"
    if [ "$code" = "200" ]; then
        ok "Prometheus /-/ready -> 200"
    else
        ko "Prometheus /-/ready -> 200" "otrzymano ${code:-brak odpowiedzi}"
    fi
}

# Martwy cel to najczęstsza cicha awaria w tym stosie: usługa chodzi, panel
# odpowiada, tylko metryki po prostu przestały przychodzić.
#
# Job `wolffire` celuje w /metrics aplikacji, której może jeszcze nie być.
# Bez SMOKE_EXPECT_APP wyciszamy go, żeby nie było fałszywego alarmu przed
# pierwszym wdrożeniem.
_check_prometheus_targets() {
    local json down_list down_count

    json="$(ssh_http_body monitoring-1 "http://$MONITORING_IP:$PROMETHEUS_PORT/api/v1/targets?state=active")"
    if [ -z "$json" ] || ! printf '%s' "$json" | jq -e '.data.activeTargets' >/dev/null 2>&1; then
        ko "Prometheus: zero celow DOWN" "nie udalo sie pobrac listy celow"
        return
    fi

    down_list="$(printf '%s' "$json" \
        | jq -r '.data.activeTargets[] | select(.health != "up") | "\(.labels.job)/\(.labels.instance)"')"

    if [ "${SMOKE_EXPECT_APP:-0}" != "1" ]; then
        down_list="$(printf '%s\n' "$down_list" | grep -v '^wolffire/' || true)"
    fi

    down_count="$(count_lines "$down_list")"
    if [ "$down_count" = "0" ]; then
        ok "Prometheus: zero celow DOWN"
    else
        ko "Prometheus: zero celow DOWN" \
           "$down_count DOWN: $(printf '%s\n' "$down_list" | sed '/^$/d' | tr '\n' ' ')"
    fi
}

_check_alertmanager() {
    local code
    code="$(ssh_http_code monitoring-1 "http://$MONITORING_IP:$ALERTMANAGER_PORT/api/v2/status")"
    if [ "$code" = "200" ]; then
        ok "Alertmanager /api/v2/status -> 200"
    else
        ko "Alertmanager /api/v2/status -> 200" "otrzymano ${code:-brak odpowiedzi}"
    fi
}

# /api/health zwraca stan bazy Grafany. Sam kod 200 nie wystarcza - Grafana
# odpowiada na to zapytanie także wtedy, gdy jej SQLite jest niedostępny.
_check_grafana_health() {
    local health db_state
    health="$(ssh_http_body monitoring-1 "http://$MONITORING_IP:$GRAFANA_PORT/api/health")"
    db_state="$(printf '%s' "$health" | jq -r '.database // "brak"' 2>/dev/null)"

    if [ "$db_state" = "ok" ]; then
        ok "Grafana /api/health -> 200 (baza: ok)"
    else
        ko "Grafana /api/health -> 200" "odpowiedz: ${health:-brak}"
    fi
}

# Sprawdza końcówkę łańcucha: hasło z SOPS -> zmienna w compose -> konto w Grafanie.
# Rozjazd na dowolnym ogniwie oznacza, że po awarii nikt się nie zaloguje.
# Hasło idzie przez stdin, nie w argumentach - inaczej trafiłoby do `ps`.
_check_grafana_login() {
    local password code
    password="$(secret_get grafana_admin_password)"

    if [ -z "$password" ]; then
        skip "Grafana: logowanie admina" "nie udalo sie odszyfrowac grafana_admin_password"
        return
    fi

    code="$(printf '%s\n' "$password" | ssh_do monitoring-1 \
        "read -r pw; curl -s -u \"admin:\$pw\" -o /dev/null -w '%{http_code}' --max-time 6 http://$MONITORING_IP:$GRAFANA_PORT/api/org")"
    unset password

    if [ "$code" = "200" ]; then
        ok "Grafana: logowanie admina haslem z SOPS -> 200"
    else
        ko "Grafana: logowanie admina haslem z SOPS -> 200" "otrzymano ${code:-brak odpowiedzi}"
    fi
}

# Etykieta `host` pochodzi z konfiguracji Alloya; każda maszyna z inventory
# powinna się w niej pojawić. Mniej niż LOKI_MIN_HOSTS oznacza, że agent logów
# gdzieś nie wysyła - a to awaria, której nie widać w żadnym panelu.
_check_loki_hosts() {
    local json count hosts
    json="$(ssh_http_body monitoring-1 "http://$MONITORING_IP:$LOKI_PORT/loki/api/v1/label/host/values")"
    count="$(printf '%s' "$json" | jq -r '(.data // []) | length' 2>/dev/null)"
    hosts="$(printf '%s' "$json" | jq -r '(.data // []) | join(", ")' 2>/dev/null)"

    if [ -n "${count:-}" ] && [ "$count" -ge "$LOKI_MIN_HOSTS" ] 2>/dev/null; then
        ok "Loki: logi z $count hostow (min. $LOKI_MIN_HOSTS)"
    else
        ko "Loki: logi z min. $LOKI_MIN_HOSTS hostow" "znaleziono ${count:-0}: ${hosts:-brak}"
    fi
}

_check_compose_containers() {
    local ps_out not_running
    ps_out="$(ssh_do monitoring-1 "sudo docker compose -f $MONITORING_DIR/compose.yml ps --format '{{.Name}} {{.State}}'")"

    if [ -z "$ps_out" ]; then
        ko "Stos monitoringu: wszystkie kontenery Up" "nie udalo sie odczytac stanu compose"
        return
    fi

    not_running="$(printf '%s\n' "$ps_out" | awk 'NF && $2 != "running" { printf "%s(%s) ", $1, $2 }')"
    if [ -z "$not_running" ]; then
        ok "Stos monitoringu: wszystkie kontenery Up ($(count_lines "$ps_out") szt.)"
    else
        ko "Stos monitoringu: wszystkie kontenery Up" "nie dzialaja: $not_running"
    fi
}

check_monitoring() {
    section "3. Monitoring (z wnetrza monitoring-1)"
    _check_prometheus_ready
    _check_prometheus_targets
    _check_alertmanager
    _check_grafana_health
    _check_grafana_login
    _check_loki_hosts
    _check_compose_containers
}
