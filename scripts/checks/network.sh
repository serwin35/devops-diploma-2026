# SEKCJA 1: sieć i dostęp SSH.
#
# Test najniższej warstwy - jeśli tu jest czerwono, większość kolejnych sekcji
# i tak nie ma jak się wykonać.

# Konto maszynowe `ansible` na każdej maszynie z inventory. Trasa (bezpośrednio
# albo ProxyJump przez bastion) wynika z ansible/ssh_config.
_check_ssh_to_all_hosts() {
    local host rc
    for host in $ALL_HOSTS; do
        if ssh_do "$host" 'exit 0'; then
            ok "SSH ansible@wf-$host odpowiada"
            continue
        fi
        rc=$?
        if is_timeout "$rc"; then
            ko "SSH ansible@wf-$host" "przekroczono limit ${TEST_TIMEOUT}s"
        else
            ko "SSH ansible@wf-$host" "polaczenie nieudane (kod $rc)"
        fi
    done
}

# Bastion to jedyny punkt wejścia z internetu. Sprawdzamy go osobno po adresie
# publicznym, bo poprzedni test szedł aliasem z ssh_config - a ten mógłby
# w przyszłości wskazywać na cokolwiek innego.
_check_bastion_public_port() {
    if tcp_probe "$BASTION_PUBLIC_IP" "$SSH_PORT"; then
        ok "Bastion osiagalny publicznie na $BASTION_PUBLIC_IP:$SSH_PORT"
    else
        ko "Bastion osiagalny publicznie na $BASTION_PUBLIC_IP:$SSH_PORT" "brak odpowiedzi"
    fi
}

check_network() {
    section "1. Siec i dostep SSH"
    _check_ssh_to_all_hosts
    _check_bastion_public_port
}
