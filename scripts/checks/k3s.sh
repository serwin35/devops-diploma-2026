# SEKCJA 4: klaster k3s.
#
# Wszystko przez `kubectl get` z control plane - żadnego apply, żadnego
# skalowania. Kubeconfig k3s leży pod rootem, stąd `sudo`.

_check_nodes_ready() {
    local nodes total ready bad
    nodes="$(ssh_do k3s-server-1 'sudo kubectl get nodes --no-headers')"

    if [ -z "$nodes" ]; then
        ko "k3s: $K3S_EXPECTED_NODES wezly w stanie Ready" "kubectl nie zwrocil wyniku"
        return
    fi

    total="$(count_lines "$nodes")"
    ready="$(printf '%s\n' "$nodes" | awk '$2 == "Ready"' | wc -l | tr -d ' ')"
    bad="$(printf '%s\n' "$nodes" | awk 'NF && $2 != "Ready" { printf "%s(%s) ", $1, $2 }')"

    # Sprawdzamy obie liczby: sam licznik Ready przepuściłby klaster, do którego
    # dołączył czwarty, nieplanowany węzeł.
    if [ "$ready" = "$K3S_EXPECTED_NODES" ] && [ "$total" = "$K3S_EXPECTED_NODES" ]; then
        ok "k3s: $ready/$K3S_EXPECTED_NODES wezly Ready"
    else
        ko "k3s: $K3S_EXPECTED_NODES wezly w stanie Ready" \
           "Ready $ready z $total; problemy: ${bad:-brak}"
    fi
}

# Completed jest poprawnym stanem końcowym - tak wyglądają zadania
# helm-install-traefik, które k3s uruchamia raz przy starcie klastra.
_check_kube_system_pods() {
    local pods bad
    pods="$(ssh_do k3s-server-1 'sudo kubectl get pods -n kube-system --no-headers')"

    if [ -z "$pods" ]; then
        ko "k3s: kube-system bez podow w zlym stanie" "kubectl nie zwrocil wyniku"
        return
    fi

    bad="$(printf '%s\n' "$pods" | awk 'NF && $3 != "Running" && $3 != "Completed" { printf "%s(%s) ", $1, $3 }')"
    if [ -z "$bad" ]; then
        ok "k3s: kube-system - wszystkie pody Running/Completed ($(count_lines "$pods") szt.)"
    else
        ko "k3s: kube-system bez podow w zlym stanie" "$bad"
    fi
}

# `kubectl top` działa tylko wtedy, gdy metrics-server zbiera dane z kubeletów.
# To najprostszy dowód, że warstwa metryk klastra jest sprawna - a od niej
# zależy autoskalowanie.
_check_metrics_server() {
    local top count
    top="$(ssh_do k3s-server-1 'sudo kubectl top nodes --no-headers')"
    count="$(count_lines "$top")"

    if [ -n "$top" ] && [ "$count" -ge "$K3S_EXPECTED_NODES" ]; then
        ok "k3s: kubectl top nodes zwraca metryki dla $count wezlow"
    else
        ko "k3s: kubectl top nodes dziala" "brak metryk (metrics-server nie odpowiada?)"
    fi
}

check_k3s() {
    section "4. Klaster k3s (z wnetrza k3s-server-1)"
    _check_nodes_ready
    _check_kube_system_pods
    _check_metrics_server
}
