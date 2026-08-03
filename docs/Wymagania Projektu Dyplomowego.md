# Wymagania Projektu Dyplomowego - DevOps

## Główne Cele Projektu

> [!NOTE] Główne zadania
> 
> W ramach projektu dyplomowego należy zrealizować następujące cele:
> 
> 1. **Wybór Repozytorium:** Wybrać publicznie dostępne repozytorium (lub kilka) z kodem źródłowym aplikacji (mono- lub mikroserwisowej). Ewentualnie można przygotować jakąś podstawową aplikację.
>     
> 2. **Automatyzacja Infrastruktury (IaC):** Zautomatyzować proces tworzenia infrastruktury pod wdrożenie projektu.
>     
> 3. **Automatyzacja CI/CD:** Zautomatyzować procesy ciągłej integracji i ciągłego dostarczania.
>     
> 4. **Monitoring:** Skonfigurować monitoring dla infrastruktury oraz aplikacji.
>     

## Kryteria Zaliczenia

> [!SUCCESS] Warunki konieczne do spełnienia
> 
> - **Dokumentacja:** Repozytorium musi zawierać minimalną dokumentację opisującą jego zawartość oraz procesy budowania i wdrażania.
>     
> - **Infrastruktura jako Kod (IaC):** Infrastruktura powinna być możliwa do wdrożenia od zera za pomocą **niewielkiej ilości komend** oraz powinna być **idempotentna**.
>     
> - **Procesy CI/CD:**
>     
>     - **Commit do dowolnej gałęzi:** Musi uruchamiać etapy:
>         
>         - ✅ Budowanie aplikacji
>             
>         - ✅ Publikacja artefaktów w repozytorium (np. Nexus, Artifactory, Docker Hub)
>             
>     - **Commit do głównej gałęzi (master/main):** Musi dodatkowo uruchamiać automatyczne wdrożenie (deployment) na docelową infrastrukturę.
>         
>     - **Powiadomienia:** System musi wysyłać powiadomienia o wyniku budowania i wdrożenia do wybranego kanału komunikacji (e-mail, czat).
>         

### Wizualizacja Procesu CI/CD

```mermaid
graph TD
    A[Commit do dowolnej gałęzi] --> B{Uruchom Pipeline};
    B --> C[Budowanie];
    C --> D[Publikacja Artefaktu];
    
    subgraph "Tylko dla gałęzi master/main"
        E[Commit do master/main] --> F{Uruchom Pipeline};
        F --> G[Budowanie];
        G --> H[Publikacja Artefaktu];
        H --> I[Deployment];
    end

    D --> J((Powiadomienie o wyniku));
    I --> J;

    style E fill:#c9ffc9,stroke:#333,stroke-width:2px
    style I fill:#c9ffc9,stroke:#333,stroke-width:2px
```

## Opcjonalne Ulepszenia Projektu

> [!TIP] Dodatkowe możliwości
> 
> - **Bezpieczeństwo:** Implementacja SSL/TLS.
>     
> - **Skalowalność:** Uruchomienie wielu replik jednego serwisu z użyciem load balancera.
>     
> - **Konteneryzacja:** Użycie Dockera do spakowania aplikacji.
>     
> - **Orkiestracja:** Wykorzystanie Kubernetesa jako docelowej infrastruktury.
>     
> - **Testy:** Rozszerzenie o dodatkowe rodzaje testów (integracyjne, wydajnościowe).
>     
> - **Pełna Automatyzacja:** Automatyczna konfiguracja wszystkiego od zera (włącznie z CI/CD i monitoringiem).
>     
> - **Agregacja Logów:** Implementacja centralnego systemu zbierania logów (np. ELK Stack).
>     
> - **Dokumentacja Kodu:** Użycie narzędzi do generowania dokumentacji bezpośrednio z kodu.
>     

## Stos Technologiczny

> [!INFO] Sugerowane narzędzia
> 
> - **Infrastruktura:**
>     
>     - **IaC:** Terraform, Ansible, Terragrunt 
>         
>     - **Chmura/Wirtualizacja:** AWS, VirtualBox 
>         
>     - **Konteneryzacja:** Docker
>         
>     - **Orkiestracja:** Amazon EKS (Kubernetes)
>         
> - **CI/CD:**
>     
>     - **Serwer:** Jenkins, GitHub Actions
>         
> - **Powiadomienia:**
>     
>     - Email, Telegram, Slack, Discord
>         
> - **Monitoring:**
>     
>     - **Metryki:** Prometheus, Zabbix
>         
>     - **Wizualizacja:** Grafana
>         
> - **Logowanie:**
>     
>     - **Stack:** ELK (Elasticsearch, Logstash, Kibana), Grafana-Loki
>         

### Przykładowy Schemat Architektury

```mermaid
graph TD
    subgraph "Deweloper"
        A[Kod źródłowy w Git] -- push --> B[Serwer CI/CD];
    end

    subgraph "Proces CI/CD (np. Jenkins)"
        B -- trigger --> C{Pipeline};
        C --> D[Build];
        D --> E[Push Artefaktu do Rejestru];
    end
    
    subgraph "Infrastruktura (np. AWS EKS)"
        F[Terraform/Ansible] -- provision --> G{Klaster Kubernetes};
        E -- deploy --> G;
        G -- metryki --> H[Zabbix];
        G -- logi --> I[Loki];
    end

    subgraph "Monitoring & Alerty"
        H -- dane --> J[Grafana];
        I -- dane --> J;
        J -- alerty --> K[Powiadomienia];
    end

    C -- status --> K;
```

## Obrona Projektu

> [!ABSTRACT] Struktura prezentacji
> 
> 1. **Wprowadzenie (3-5 min):**
>     
>     - Krótki opis projektu.
>         
>     - Zastosowane narzędzia.
>         
>     - Podsumowanie wykonanej pracy i osiągniętych rezultatów.
>         
> 2. **Demonstracja (10-12 min):**
>     
>     - Praktyczny pokaz działania pipeline'u CI/CD (od commita do wdrożenia).
>         
> 3. **Pytania i Dyskusja (5-7 min):**
>     
>     - Sesja Q&A.
>         

## Przykładowe Repozytoria Aplikacji

> [!EXAMPLE] Repozytoria startowe
> 
> - **Golang Hello World:** [github.com/hackersandslackers/golang-helloworld](https://github.com/hackersandslackers/golang-helloworld "null")
>     
> - **Java Maven App:** [github.com/jenkins-docs/simple-java-maven-app](https://github.com/jenkins-docs/simple-java-maven-app "null")
>     
> - **Java Gradle App:**
>     
>     - [github.com/jitpack/gradle-simple](https://github.com/jitpack/gradle-simple "null")
>         
>     - [github.com/jhipster/jhipster-sample-app-gradle](https://github.com/jhipster/jhipster-sample-app-gradle "null")
>         
> - **Calculator App (różne technologie):** [github.com/HouariZegai/Calculator](https://github.com/HouariZegai/Calculator "null")
>
