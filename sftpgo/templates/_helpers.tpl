{{/*
Expand the name of the chart.
*/}}
{{- define "sftpgo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sftpgo.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "sftpgo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "sftpgo.labels" -}}
helm.sh/chart: {{ include "sftpgo.chart" . }}
{{ include "sftpgo.selectorLabels" . }}
{{- if .Values.image.tag }}
app.kubernetes.io/version: {{ regexReplaceAll "[^-A-Za-z0-9_.]" .Values.image.tag "_" | trimPrefix "v" | trunc 63 | trimSuffix "-" | trimSuffix "_" | trimSuffix "." | quote }}
{{- else if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sftpgo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sftpgo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "sftpgo.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sftpgo.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create a default fully qualified component name from the full app name and a component name.
We truncate the full name at 63 - 1 (last dash) - len(component name) chars because some Kubernetes name fields are limited to this (by the DNS naming spec)
and we want to make sure that the component is included in the name.

Usage: {{ include "sftpgo.componentname" (list . "component") }}
*/}}
{{- define "sftpgo.componentname" -}}
{{- $global := index . 0 -}}
{{- $component := index . 1 | trimPrefix "-" -}}
{{- printf "%s-%s" (include "sftpgo.fullname" $global | trunc (sub 62 (len $component) | int) | trimSuffix "-" ) $component | trimSuffix "-" -}}
{{- end -}}

{{/*
Compute a ConfigMap or Secret checksum from its data only, for the checksum/* pod annotations.
The full manifest carries the helm.sh/chart label, which changes on every chart version bump.
The template may render several documents, so hash the data of each one.
*/}}
{{- define "sftpgo.configMapOrSecretContentHash" -}}
{{- $data := list -}}
{{- range regexSplit "(?m)^---$" (include (print .ctx.Template.BasePath .name) .ctx) -1 -}}
{{- $data = append $data (pick (fromYaml .) "data" "stringData") -}}
{{- end -}}
{{ $data | toYaml | sha256sum }}
{{- end -}}

{{/*
API version of the TCPRoute resources. Since Gateway API v1.6 TCPRoute is served as v1, in the
standard and experimental channels, and the standard channel no longer serves v1alpha2. Older
experimental channel CRDs only serve v1alpha2.
*/}}
{{- define "sftpgo.tcpRouteApiVersion" -}}
{{- if .Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1/TCPRoute" -}}
gateway.networking.k8s.io/v1
{{- else -}}
gateway.networking.k8s.io/v1alpha2
{{- end -}}
{{- end -}}

{{/*
FTP passive port range as JSON: {"start": N, "end": N, "legacy": bool}.
The deprecated service.ports.ftp.passiveRange wins if ftpd.passivePortRange has its default value.

Usage: {{ include "sftpgo.ftpPassiveRange" . | fromJson }}
*/}}
{{- define "sftpgo.ftpPassiveRange" -}}
{{- $range := deepCopy (.Values.ftpd.passivePortRange | default dict) -}}
{{- $legacy := (((.Values.service).ports).ftp).passiveRange | default dict -}}
{{- if $legacy -}}
{{- $merged := mergeOverwrite (deepCopy $range) (deepCopy $legacy) -}}
{{- /* Empty with --reuse-values from older chart versions. */ -}}
{{- $isDefault := or (empty $range) (and (eq (int ($range.start | default 0)) 30050) (eq (int ($range.end | default 0)) 30070)) -}}
{{- $differs := or (ne (int ($merged.start | default 0)) (int ($range.start | default 0))) (ne (int ($merged.end | default 0)) (int ($range.end | default 0))) -}}
{{- if and (not $isDefault) $differs -}}
{{- fail "service.ports.ftp.passiveRange is deprecated and conflicts with ftpd.passivePortRange: remove it, or set it to null if it comes from reused values (e.g. --set service.ports.ftp.passiveRange=null)" -}}
{{- end -}}
{{- $range = $merged -}}
{{- end -}}
{{- $fromLegacy := and (not (empty $legacy)) (or (hasKey $legacy "start") (hasKey $legacy "end")) -}}
{{- $start := int ($range.start | default 0) -}}
{{- $end := int ($range.end | default 0) -}}
{{- if or (lt $start 1) (lt $end $start) (gt $end 65535) -}}
{{- fail (printf "Invalid FTP passive port range %v-%v: set ftpd.passivePortRange.start and ftpd.passivePortRange.end, with 1 <= start <= end <= 65535" ($range.start | default "unset") ($range.end | default "unset")) -}}
{{- end -}}
{{- dict "start" $start "end" $end "legacy" $fromLegacy | toJson -}}
{{- end -}}

{{/*
Validate the additionalPorts entries.
*/}}
{{- define "sftpgo.validateAdditionalPorts" -}}
{{- $managed := dict "sftp" .Values.sftpd.enabled "ftp" .Values.ftpd.enabled "webdav" .Values.webdavd.enabled "http" .Values.httpd.enabled "telemetry" true -}}
{{- range $name, $port := .Values.additionalPorts -}}
{{- if get $managed $name -}}
{{- fail (printf "Additional port %q conflicts with a port managed by the chart" $name) -}}
{{- end -}}
{{- if or (gt (len $name) 15) (not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" $name)) (not (regexMatch "[a-z]" $name)) (contains "--" $name) -}}
{{- fail (printf "Invalid additional port name %q: use at most 15 lowercase letters, digits and non-consecutive hyphens, with at least one letter" $name) -}}
{{- end -}}
{{- if not (kindIs "map" $port) -}}
{{- fail (printf "Additional port %q must be a map with at least containerPort" $name) -}}
{{- end -}}
{{- include "sftpgo.validatePortNumber" (list (required (printf "containerPort is required for additional port %q" $name) $port.containerPort) (printf "containerPort of additional port %q" $name)) -}}
{{- end -}}
{{- end -}}

{{/*
Fail unless the value is a port number (1-65535).
Usage: {{ include "sftpgo.validatePortNumber" (list $value "description") }}
*/}}
{{- define "sftpgo.validatePortNumber" -}}
{{- $value := index . 0 -}}
{{- if or (not (regexMatch "^[0-9]+$" (toString $value))) (lt (int $value) 1) (gt (int $value) 65535) -}}
{{- fail (printf "Invalid %s: %v is not a port number (1-65535)" (index . 1) $value) -}}
{{- end -}}
{{- end -}}

{{/*
Render the ports of a Service (see "Additional ports" in the README).

Usage: {{ include "sftpgo.servicePorts" (dict "ctx" $ "name" "public" "service" $service "main" false) }}
*/}}
{{- define "sftpgo.servicePorts" -}}
{{- $v := .ctx.Values -}}
{{- $svcName := .name -}}
{{- $svc := .service -}}
{{- $main := .main -}}
{{- $cfg := $svc.ports | default dict -}}
{{- $additional := $v.additionalPorts | default dict -}}
{{- $withNodePorts := or (eq $svc.type "NodePort") (eq $svc.type "LoadBalancer") -}}
{{- $builtin := list
  (dict "name" "sftp" "enabled" $v.sftpd.enabled "appProtocol" "sftp-ssh" "label" "SFTP")
  (dict "name" "ftp" "enabled" $v.ftpd.enabled "appProtocol" "ftp" "label" "FTP")
  (dict "name" "webdav" "enabled" $v.webdavd.enabled "appProtocol" "webdav" "label" "WebDAV")
  (dict "name" "http" "enabled" $v.httpd.enabled "appProtocol" "http" "label" "HTTP") -}}
{{- $builtinNames := list "sftp" "ftp" "webdav" "http" -}}

{{- if $main -}}{{- include "sftpgo.validateAdditionalPorts" .ctx -}}{{- end -}}

{{- /* SFTPGo container port names -> appProtocol. */ -}}
{{- $chartPorts := dict "telemetry" "http" -}}
{{- range $builtin -}}
{{- if .enabled -}}{{- $_ := set $chartPorts .name .appProtocol -}}{{- end -}}
{{- end -}}
{{- range $name, $a := $additional -}}
{{- $_ := set $chartPorts $name ($a.appProtocol | default "") -}}
{{- end -}}
{{- /* Port names of extra containers and sidecar init containers. */ -}}
{{- $sidecarPorts := list -}}
{{- $containers := $v.extraContainers | default list -}}
{{- range $v.initContainers -}}
{{- if eq (toString .restartPolicy) "Always" -}}{{- $containers = append $containers . -}}{{- end -}}
{{- end -}}
{{- range $containers -}}
{{- range .ports -}}
{{- with .name -}}{{- $sidecarPorts = append $sidecarPorts . -}}{{- end -}}
{{- end -}}
{{- end -}}

{{- $ports := list -}}
{{- range $builtin -}}
{{- $srv := . -}}
{{- $listed := and (hasKey $cfg $srv.name) (not (kindIs "invalid" (index $cfg $srv.name))) -}}
{{- $p := dict -}}
{{- if $listed -}}
{{- $p = index $cfg $srv.name -}}
{{- if not (kindIs "map" $p) -}}
{{- fail (printf "Port %q of service %q must be a map, e.g. {port: 22}" $srv.name $svcName) -}}
{{- end -}}
{{- end -}}
{{- if and $srv.enabled (or $main $listed) -}}
{{- $port := dict "name" $srv.name "targetPort" $srv.name "protocol" "TCP" "appProtocol" $srv.appProtocol -}}
{{- $_ := set $port "port" (required (printf "%s service port is required for service %q" $srv.label $svcName) $p.port) -}}
{{- if and $withNodePorts $p.nodePort -}}{{- $_ := set $port "nodePort" $p.nodePort -}}{{- end -}}
{{- $ports = append $ports $port -}}
{{- end -}}

{{- if and $srv.enabled (eq $srv.name "ftp") -}}
{{- $range := include "sftpgo.ftpPassiveRange" $.ctx | fromJson -}}
{{- $passive := $main -}}
{{- if not $main -}}
{{- with $p.passiveRange -}}
{{- if or (ne (int .start) (int $range.start)) (ne (int .end) (int $range.end)) -}}
{{- $legacy := printf "%v-%v" (.start | default "unset") (.end | default "unset") -}}
{{- fail (printf "services.%s.ports.ftp.passiveRange (%s) does not match ftpd.passivePortRange (%v-%v): remove it, set services.%s.ftpPassive to true and, to keep that range, set ftpd.passivePortRange" $svcName $legacy $range.start $range.end $svcName) -}}
{{- end -}}
{{- $passive = true -}}
{{- end -}}
{{- end -}}
{{- if not (kindIs "invalid" $svc.ftpPassive) -}}{{- $passive = $svc.ftpPassive -}}{{- end -}}
{{- if $passive -}}
{{- /* Catch upgrades keeping the old 50000-50020 range; the cluster node port range may be custom. */ -}}
{{- if and (eq $svc.type "NodePort") $range.legacy (or (lt (int $range.start) 30000) (gt (int $range.end) 32767)) -}}
{{- fail (printf "The FTP passive port range %v-%v (deprecated service.ports.ftp.passiveRange) is outside the node port range (30000-32767) required by NodePort service %q: set ftpd.passivePortRange and set service.ports.ftp.passiveRange to null, or set ftpPassive to false" $range.start $range.end $svcName) -}}
{{- end -}}
{{- range $n := untilStep (int $range.start) (int (add $range.end 1)) 1 -}}
{{- $pp := dict "name" (printf "ftp-passive-%d" $n) "port" $n "targetPort" $n "protocol" "TCP" "appProtocol" "ftp" -}}
{{- if eq $svc.type "NodePort" -}}{{- $_ := set $pp "nodePort" $n -}}{{- end -}}
{{- $ports = append $ports $pp -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if $main -}}
{{- $ports = append $ports (dict "name" "telemetry" "port" 10000 "targetPort" "telemetry" "protocol" "TCP" "appProtocol" "http") -}}
{{- end -}}

{{- $customNames := list -}}
{{- if $main -}}{{- $customNames = keys $additional -}}{{- end -}}
{{- range $name, $p := $cfg -}}
{{- if and (not (has $name $builtinNames)) (not (kindIs "invalid" $p)) -}}{{- $customNames = append $customNames $name -}}{{- end -}}
{{- end -}}
{{- range $name := $customNames | uniq | sortAlpha -}}
{{- $p := dict -}}
{{- if hasKey $cfg $name -}}{{- $p = index $cfg $name -}}{{- end -}}
{{- if not (kindIs "map" $p) -}}
{{- fail (printf "Port %q of service %q must be a map, e.g. {port: 2200, targetPort: sftp}" $name $svcName) -}}
{{- end -}}
{{- if or (gt (len $name) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name)) -}}
{{- fail (printf "Invalid name %q for a port of service %q: use at most 63 lowercase letters, digits and hyphens" $name $svcName) -}}
{{- end -}}
{{- $a := dict -}}
{{- if hasKey $additional $name -}}{{- $a = index $additional $name -}}{{- end -}}
{{- $portNumber := $p.port | default $a.port | default $a.containerPort -}}
{{- $port := dict "name" $name "port" (required (printf "port is required for port %q of service %q" $name $svcName) $portNumber) -}}
{{- $nodePort := $p.nodePort -}}
{{- if $main -}}{{- $nodePort = $nodePort | default $a.nodePort -}}{{- end -}}
{{- if and $withNodePorts $nodePort -}}{{- $_ := set $port "nodePort" $nodePort -}}{{- end -}}
{{- $target := $p.targetPort | default $name -}}
{{- if regexMatch "^[0-9]+$" (toString $target) -}}
{{- include "sftpgo.validatePortNumber" (list $target (printf "targetPort of port %q of service %q" $name $svcName)) -}}
{{- $target = int $target -}}
{{- else if not (or (hasKey $chartPorts $target) (has $target $sidecarPorts)) -}}
{{- fail (printf "Port %q of service %q targets the container port %q, which does not exist. Set targetPort to an existing named port or declare it under additionalPorts" $name $svcName $target) -}}
{{- end -}}
{{- $_ := set $port "targetPort" $target -}}
{{- $_ := set $port "protocol" "TCP" -}}
{{- $inherited := "" -}}
{{- if kindIs "string" $target -}}{{- $inherited = get $chartPorts $target -}}{{- end -}}
{{- with $p.appProtocol | default $a.appProtocol | default $inherited -}}{{- $_ := set $port "appProtocol" . -}}{{- end -}}
{{- $ports = append $ports $port -}}
{{- end -}}

{{- if not $ports -}}
{{- fail (printf "At least one port is required for service %q: no listed port matches an enabled server" $svcName) -}}
{{- end -}}

{{- $seen := dict -}}
{{- range $port := $ports -}}
{{- include "sftpgo.validatePortNumber" (list $port.port (printf "port of port %q of service %q" $port.name $svcName)) -}}
{{- $keys := list (printf "name %q" $port.name) (printf "port %v" (int $port.port)) -}}
{{- with $port.nodePort -}}
{{- include "sftpgo.validatePortNumber" (list . (printf "nodePort of port %q of service %q" $port.name $svcName)) -}}
{{- $keys = append $keys (printf "node port %v" (int .)) -}}
{{- end -}}
{{- range $keys -}}
{{- if hasKey $seen . -}}
{{- fail (printf "Duplicate %s in service %q" . $svcName) -}}
{{- end -}}
{{- $_ := set $seen . true -}}
{{- end -}}
{{- end -}}

{{- range $ports }}
- name: {{ .name }}
  port: {{ .port }}
  {{- with .nodePort }}
  nodePort: {{ . }}
  {{- end }}
  targetPort: {{ .targetPort }}
  protocol: {{ .protocol }}
  {{- with .appProtocol }}
  appProtocol: {{ . }}
  {{- end }}
{{- end }}
{{- end -}}
