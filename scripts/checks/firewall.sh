# SEKCJA 6: firewall i izolacja segmentów.
#
# Testy ODWROTNE: sukcesem jest BRAK połączenia. Każdy z nich pilnuje reguły,
# której naruszenie jest cichą luką - nic się nie psuje, nic nie alarmuje,
# po prostu coś jest otwarte szerzej, niż zakładał projekt.

# Do Postgresa ma sięgać wyłącznie segment k3s. Monitoring zbiera metryki
# z eksportera na 9187 i nie ma powodu dotykać 5432.
#
# Wynik próby tłumaczymy na SŁOWO po stronie zdalnej. Gdybyśmy patrzyli na kod
# wyjścia `ssh`, kod 124 byłby dwuznaczny: oznaczałby i zablokowane połączenie
# (sukces testu), i zerwaną sesję SSH (błąd narzędzia).
_check_no_route_to_postgres() {
    local verdict
    verdict="$(ssh_do monitoring-1 "timeout 6 bash -c 'exec 3<>/dev/tcp/$DB_IP/$POSTGRES_PORT' >/dev/null 2>&1; \
        rc=\$?; \
        if [ \$rc -eq 0 ]; then echo CONNECTED; \
        elif [ \$rc -eq 124 ]; then echo TIMEOUT; \
        else echo REFUSED; fi")"

    case "$verdict" in
        TIMEOUT)
            ok "monitoring-1 NIE ma dostepu do $DB_IP:$POSTGRES_PORT (pakiety odrzucane po cichu)"
            ;;
        REFUSED)
            ok "monitoring-1 NIE ma dostepu do $DB_IP:$POSTGRES_PORT (polaczenie odrzucone)"
            ;;
        CONNECTED)
            ko "monitoring-1 NIE ma dostepu do $DB_IP:$POSTGRES_PORT" \
               "polaczenie ZOSTALO nawiazane - firewall przepuszcza za duzo"
            ;;
        *)
            ko "monitoring-1 NIE ma dostepu do $DB_IP:$POSTGRES_PORT" \
               "nie udalo sie wykonac testu na monitoring-1 (SSH?)"
            ;;
    esac
}

# Panele mają być dostępne wyłącznie przez tunel Cloudflare. Port 8006
# (interfejs Proxmoxa) i 3000 (Grafana) nie mogą odpowiadać na publicznym IP.
_check_port_closed_publicly() {
    local ip="$1" port="$2"

    if tcp_probe "$ip" "$port" 8; then
        ko "Port $port zamkniety publicznie na $ip" \
           "port ODPOWIADA z internetu - uslugi maja chodzic tylko przez tunel"
    else
        ok "Port $port zamkniety publicznie na $ip"
    fi
}

check_firewall() {
    section "6. Firewall i izolacja segmentow (testy odwrotne)"
    _check_no_route_to_postgres
    _check_port_closed_publicly "$PROXMOX_PUBLIC_IP" 8006
    _check_port_closed_publicly "$PROXMOX_PUBLIC_IP" 3000
}
