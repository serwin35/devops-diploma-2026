{{/*
Nazwa aplikacji - podstawa etykiet.
*/}}
{{- define "wolffire.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Pełna nazwa release'u. Gdy release nazywa się tak jak chart, nie sklejamy
"wolffire-wolffire" - stąd warunek contains.
*/}}
{{- define "wolffire.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "wolffire.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Etykiety wspólne dla wszystkich obiektów.
*/}}
{{- define "wolffire.labels" -}}
helm.sh/chart: {{ include "wolffire.chart" . }}
app.kubernetes.io/name: {{ include "wolffire.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Etykiety selektora per komponent. Wywołanie:
  include "wolffire.selectorLabels" (dict "ctx" . "component" "php")
Selektor jest niemutowalny w Deploymencie, dlatego trzymamy go minimalnym.
*/}}
{{- define "wolffire.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wolffire.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "wolffire.phpImage" -}}
{{- printf "%s:%s" .Values.image.php.repository (default .Chart.AppVersion .Values.image.php.tag) -}}
{{- end }}

{{- define "wolffire.nginxImage" -}}
{{- printf "%s:%s" .Values.image.nginx.repository (default .Chart.AppVersion .Values.image.nginx.tag) -}}
{{- end }}

{{/*
Nazwa DNS serwisu php-fpm. Jedno źródło prawdy - korzysta z niej Service
oraz configmapa nginx, więc nie ma szansy na rozjazd upstreamu z serwisem.
*/}}
{{- define "wolffire.phpServiceName" -}}
{{- include "wolffire.fullname" . }}-php
{{- end }}

{{/*
Zawartość .dockerconfigjson dla prywatnego GHCR (zakodowana base64).
*/}}
{{- define "wolffire.imagePullSecretData" -}}
{{- $u := required "Podaj ghcrUsername (--set ghcrUsername=...)" .Values.ghcrUsername -}}
{{- $t := required "Podaj ghcrToken (--set ghcrToken=..., token z read:packages)" .Values.ghcrToken -}}
{{- printf `{"auths":{"ghcr.io":{"username":%q,"password":%q,"auth":%q}}}` $u $t (printf "%s:%s" $u $t | b64enc) | b64enc -}}
{{- end }}

{{/*
Env niewrażliwe. Wspólny szablon dla zwykłej ConfigMapy i jej kopii hookowej
dla migracji - jedna definicja, zero dryfu między nimi.
Zestaw zmiennych odpowiada ansible/roles/wolffire/templates/env.j2.
*/}}
{{- define "wolffire.configEnv" -}}
APP_NAME: "WolfFire"
APP_ENV: {{ .Values.app.env | quote }}
APP_DEBUG: {{ .Values.app.debug | quote }}
APP_URL: {{ .Values.app.url | quote }}
APP_LOCALE: "pl"
APP_FALLBACK_LOCALE: "en"
{{- /* Logi na stderr kontenera - zbiera je stos observability, nie plik. */}}
LOG_CHANNEL: "stderr"
LOG_LEVEL: {{ .Values.app.logLevel | quote }}
DB_CONNECTION: "pgsql"
DB_HOST: {{ .Values.db.host | quote }}
DB_PORT: {{ .Values.db.port | quote }}
DB_DATABASE: {{ .Values.db.database | quote }}
DB_USERNAME: {{ .Values.db.username | quote }}
REDIS_CLIENT: "phpredis"
REDIS_HOST: {{ .Values.redis.host | quote }}
REDIS_PORT: {{ .Values.redis.port | quote }}
CACHE_STORE: "redis"
QUEUE_CONNECTION: "redis"
SESSION_DRIVER: "redis"
SESSION_LIFETIME: {{ .Values.app.sessionLifetime | quote }}
BROADCAST_CONNECTION: "log"
HORIZON_PREFIX: "wolffire_horizon:"
FILESYSTEM_DISK: {{ .Values.app.filesystemDisk | quote }}
{{- if eq .Values.app.filesystemDisk "s3" }}
AWS_BUCKET: {{ required "Podaj s3.bucket przy filesystemDisk=s3" .Values.s3.bucket | quote }}
AWS_DEFAULT_REGION: {{ .Values.s3.region | quote }}
AWS_USE_PATH_STYLE_ENDPOINT: "false"
{{- end }}
MAIL_MAILER: "log"
MAIL_FROM_ADDRESS: {{ .Values.mail.fromAddress | quote }}
MAIL_FROM_NAME: "WolfFire"
{{- /* Bez dostępu do Nexo/KSeF/ShipX harmonogram integracji tylko zapycha
kolejki - patrz config/integrations.php w aplikacji. */}}
INTEGRATIONS_SYNC_ENABLED: {{ .Values.app.integrationsSyncEnabled | quote }}
{{- /* Integracje zewnętrzne celowo puste - dev nie dotyka systemów klienta. */}}
NEXO_DMSERVICE_URL: ""
NEXO_DMSERVICE_TOKEN: ""
NEXO_CODETRONIC_URL: ""
NEXO_CODETRONIC_TOKEN: ""
{{- end }}

{{/*
Env wrażliwe - trafiają wyłącznie do Secretów. `required` zatrzymuje
instalację bez sekretów, zamiast wypuścić aplikację z pustym hasłem.
*/}}
{{- define "wolffire.secretEnv" -}}
APP_KEY: {{ required "Podaj app.key (APP_KEY Laravela, format base64:...)" .Values.app.key | quote }}
DB_PASSWORD: {{ required "Podaj db.password" .Values.db.password | quote }}
REDIS_PASSWORD: {{ required "Podaj redis.password" .Values.redis.password | quote }}
{{- if eq .Values.app.filesystemDisk "s3" }}
AWS_ACCESS_KEY_ID: {{ required "Podaj s3.accessKeyId przy filesystemDisk=s3" .Values.s3.accessKeyId | quote }}
AWS_SECRET_ACCESS_KEY: {{ required "Podaj s3.secretAccessKey przy filesystemDisk=s3" .Values.s3.secretAccessKey | quote }}
{{- end }}
{{- end }}

{{/*
Kontekst bezpieczeństwa poda: obrazy są zbudowane pod uid/gid 1000 (user app),
a fsGroup dba o zapisywalność emptyDir bez ręcznego grzebania w uprawnieniach.
*/}}
{{- define "wolffire.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "wolffire.containerSecurityContext" -}}
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
{{- end }}
