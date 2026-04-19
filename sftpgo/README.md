# sftpgo

Full-featured and highly configurable SFTP, HTTP/S, FTP/S and WebDAV server.

**Homepage:** <https://sftpgo.com>

## TL;DR;

```bash
helm install --generate-name --wait oci://ghcr.io/sftpgo/helm-charts/sftpgo
```

## Configuration

SFTPGo has an extensive set of [configuration](https://docs.sftpgo.com/latest/config-file/) options allowing you to control the large set of features it provides.

The following options are available to configure SFTPGo when installing it with this chart.

**Note:** environmental configurations (like port bindings, certain directories, etc) are configured by the chart or the container image using flags and environment variables and they cannot be configured using a config file.

### values.yaml

Setting the `config` key in the values file is the easiest way to configure SFTPGo:

```yaml
config:
    sftpd:
        max_auth_tries: 10
```

### Custom volume mount

A custom configuration file can be mounted using the `volumes` and `volumeMounts` keys (see [Values](#values)).

By default, SFTPGo looks at the following locations for configuration (in the order of precedence):

- `/var/lib/.config/sftpgo`
- `/etc/sftpgo` (already mounted by this chart)

You can mount a config map or a secret to `/var/lib/.config/sftpgo`.

**Note:** this method will override all configuration set in `values.yaml`.

**Example:**

```yaml
# configmap.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-sftpgo-config
data:
  sftpgo.yaml: |-
    sftpd:
        max_auth_retries: 10
```

```yaml
# values.yaml

volumes:
  - name: custom-config # config is already taken
    configMap:
      name: custom-sftpgo-config

volumeMounts:
  - name: custom-config # config is already taken
    mountPath: /var/lib/sftpgo/.config/sftpgo
```

Alternatively, you can mount the config file to any arbitrary location (except `/etc/sftpgo`) and set the `SFTPGO_CONFIG_FILE` environment variable (using `env` or `envFrom`, see [Values](#values)).

### Custom services

The primary service created by the chart includes every enabled server (including HTTP and telemetry).
This can be a problem when you want to expose specific (but not all) servers to the internet using a `LoadBalancer` type service.

The `services` option in the values file allows you to create custom services enabling specific server ports.

The following example exposes the SFTP server (and **only** the SFTP server) using a `LoadBalancer` service:

```yaml
services:
  sftp-public:
    annotations:
      external-dns.alpha.kubernetes.io/hostname: sftp.mydomain.com.
    type: LoadBalancer
    ports:
      sftp: 22
```

Additional services accept the same options as the `service` option in the values file and
require at least one port.

### Gateway API

The chart can expose SFTPGo via [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) resources
in addition to (or instead of) Ingress. `HTTPRoute` is used for UI, REST API and WebDAV; `TCPRoute`
is used for SFTP and FTP.

**Prerequisites**

- A `Gateway` resource must already be configured in the cluster. The chart only creates `*Route`
  resources and attaches them to an existing Gateway via `parentRefs`.
- `HTTPRoute` is part of the Gateway API **standard** channel (GA in `gateway.networking.k8s.io/v1`,
  Gateway API v1.0, October 2023). Any conformant controller supports it.
- `TCPRoute` is only available in the Gateway API **experimental** channel (`v1alpha2`). The
  experimental CRDs must be installed in the cluster, and the controller must support TCPRoute.
  Controller support varies: for example Istio and Envoy Gateway support it; some controllers
  (e.g. upstream Nginx Gateway Fabric) do not.

**Path-prefix semantics**

Understanding how SFTPGo serves its different surfaces helps pick the right `pathPrefix` and
filters:

| Surface | Served at | Notes |
|---------|-----------|-------|
| Web UI (admin + client) | `{httpd.web_root}/web/...` | Static asset URLs are rewritten by SFTPGo to include `web_root`, so the external path must match. Set `pathPrefix` equal to `httpd.web_root` (default `/`). |
| REST API | `/api/v2/...` | Always at `/api`, regardless of `web_root`. To expose the API at a different external prefix, set `pathPrefix` and add a `URLRewrite` filter (see below). |
| WebDAV | `{webdavd.bindings[].prefix}/...` | Similar to UI: set `pathPrefix` to match the configured binding prefix (default `/`). |

**Example: UI and API behind the same Gateway**

```yaml
httpd:
  enabled: true

gatewayApi:
  httpRoutes:
    ui:
      enabled: true
      hostnames:
        - sftpgo.example.com
      parentRefs:
        - name: my-gateway
          namespace: gateway-system
          sectionName: https
      # pathPrefix defaults to "/" — matches the default httpd.web_root
    api:
      enabled: true
      hostnames:
        - sftpgo.example.com
      parentRefs:
        - name: my-gateway
          namespace: gateway-system
          sectionName: https
      # pathPrefix defaults to "/api" — no rewrite needed
```

**Example: API exposed at a custom external prefix via URLRewrite**

SFTPGo does not apply `web_root` to the REST API, so to expose it at `/sftpgo/api` externally you
need to strip the `/sftpgo` prefix before the request reaches the backend:

```yaml
gatewayApi:
  httpRoutes:
    api:
      enabled: true
      hostnames:
        - gw.example.com
      parentRefs:
        - name: my-gateway
          namespace: gateway-system
      pathPrefix: /sftpgo/api
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /api
```

**Example: SFTP via TCPRoute**

```yaml
sftpd:
  enabled: true

gatewayApi:
  tcpRoutes:
    sftp:
      enabled: true
      parentRefs:
        - name: my-gateway
          namespace: gateway-system
          sectionName: sftp
```

Note: for FTP, only the control port is routed. Passive data ports (`service.ports.ftp.passiveRange`)
require separate handling (typically a dedicated `LoadBalancer` Service) because Gateway API does
not model port ranges.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalPorts | object | `{}` | Additional ports to expose in the deployment and service. |
| affinity | object | `{}` | [Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity) configuration. See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#scheduling) for details. |
| api.ingress.annotations | object | `{}` | Annotations to be added to the ingress. |
| api.ingress.className | string | `""` | Ingress [class name](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class). |
| api.ingress.enabled | bool | `false` | Enable [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/). |
| api.ingress.hosts | list | See [values.yaml](values.yaml). | Ingress host configuration. |
| api.ingress.tls | list | See [values.yaml](values.yaml). | Ingress TLS configuration. |
| autoscaling | object | Disabled by default. | Autoscaling configuration (see [values.yaml](values.yaml) for details). |
| config | object | `{}` | Application configuration. See the [official documentation](https://docs.sftpgo.com/latest/config-file/). |
| deploymentAnnotations | object | `{}` | Annotations to be added to deployment. |
| deploymentLabels | object | `{}` | Labels to be added to deployment. |
| deploymentStrategy | object | `{}` | Define the [strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy) to replace old Pods by new ones during updates. |
| env | object | `{}` | Additional environment variables passed directly to containers using a simplified key-value syntax. |
| envFrom | list | `[]` | Additional environment variables mounted from [secrets](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables) or [config maps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#configure-all-key-value-pairs-in-a-configmap-as-container-environment-variables). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables) for details. |
| envVars | list | `[]` | Additional environment variables passed directly to containers. See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables) for details. |
| extraContainers | list | `[]` | Additional [containers](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers) to run in the same pod (e.g., sidecars). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#containers) for details. |
| ftpd.enabled | bool | `false` | Enable FTP service. |
| ftpd.port | int | `2021` | Container FTP port. Set to 0 to disable the service. The 'enabled' flag may be removed in the future in favor of this setting. |
| fullnameOverride | string | `""` | A name to substitute for the full names of resources. |
| gatewayApi | object | `{"httpRoutes":{"api":{"annotations":{},"backend":{},"enabled":false,"filters":[],"hostnames":[],"labels":{},"parentRefs":[],"pathPrefix":"/api"},"ui":{"annotations":{},"backend":{},"enabled":false,"filters":[],"hostnames":[],"labels":{},"parentRefs":[],"pathPrefix":"/"},"webdav":{"annotations":{},"backend":{},"enabled":false,"filters":[],"hostnames":[],"labels":{},"parentRefs":[],"pathPrefix":"/"}},"tcpRoutes":{"ftp":{"annotations":{},"backend":{},"enabled":false,"labels":{},"parentRefs":[]},"sftp":{"annotations":{},"backend":{},"enabled":false,"labels":{},"parentRefs":[]}}}` | [Gateway API](https://gateway-api.sigs.k8s.io/) routes configuration. HTTPRoute is part of the Gateway API standard channel (GA in v1). TCPRoute requires the experimental channel CRDs to be installed in the cluster. See the README for compatibility details and path-prefix semantics. |
| gatewayApi.httpRoutes.api.annotations | object | `{}` | Annotations to be added to the API HTTPRoute. |
| gatewayApi.httpRoutes.api.backend | object | `{}` | Backend override. Defaults to the main chart Service on the HTTP port. Accepted keys: `kind`, `name`, `port`, `weight`. |
| gatewayApi.httpRoutes.api.enabled | bool | `false` | Enable [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) for the REST API. |
| gatewayApi.httpRoutes.api.filters | list | `[]` | [Filters](https://gateway-api.sigs.k8s.io/api-types/httproute/#filters-optional) applied to the route (e.g. URLRewrite, RequestHeaderModifier). Passed through verbatim. |
| gatewayApi.httpRoutes.api.hostnames | list | `[]` | Hostnames for the API HTTPRoute. Leave empty to match any hostname accepted by the parent Gateway. |
| gatewayApi.httpRoutes.api.labels | object | `{}` | Labels to be added to the API HTTPRoute. |
| gatewayApi.httpRoutes.api.parentRefs | list | `[]` | ParentRefs for the API HTTPRoute. At least one entry is required for the route to be attached to a Gateway. |
| gatewayApi.httpRoutes.api.pathPrefix | string | `"/api"` | Path prefix for the API route. The REST API is always served at `/api` by SFTPGo (not affected by `httpd.web_root`). Use a custom prefix together with a `URLRewrite` filter if you need a different external path. |
| gatewayApi.httpRoutes.ui.annotations | object | `{}` | Annotations to be added to the UI HTTPRoute. |
| gatewayApi.httpRoutes.ui.backend | object | `{}` | Backend override. Defaults to the main chart Service on the HTTP port. Accepted keys: `kind`, `name`, `port`, `weight`. |
| gatewayApi.httpRoutes.ui.enabled | bool | `false` | Enable [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) for the web UI. |
| gatewayApi.httpRoutes.ui.filters | list | `[]` | [Filters](https://gateway-api.sigs.k8s.io/api-types/httproute/#filters-optional) applied to the route (e.g. URLRewrite, RequestHeaderModifier). Passed through verbatim. |
| gatewayApi.httpRoutes.ui.hostnames | list | `[]` | Hostnames for the UI HTTPRoute. Leave empty to match any hostname accepted by the parent Gateway. |
| gatewayApi.httpRoutes.ui.labels | object | `{}` | Labels to be added to the UI HTTPRoute. |
| gatewayApi.httpRoutes.ui.parentRefs | list | `[]` | ParentRefs for the UI HTTPRoute. At least one entry is required for the route to be attached to a Gateway. |
| gatewayApi.httpRoutes.ui.pathPrefix | string | `"/"` | Path prefix for the UI route. Should match the `httpd.web_root` configured in SFTPGo (default `/`). |
| gatewayApi.httpRoutes.webdav.annotations | object | `{}` | Annotations to be added to the WebDAV HTTPRoute. |
| gatewayApi.httpRoutes.webdav.backend | object | `{}` | Backend override. Defaults to the main chart Service on the WebDAV port. Accepted keys: `kind`, `name`, `port`, `weight`. |
| gatewayApi.httpRoutes.webdav.enabled | bool | `false` | Enable [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/) for WebDAV. |
| gatewayApi.httpRoutes.webdav.filters | list | `[]` | [Filters](https://gateway-api.sigs.k8s.io/api-types/httproute/#filters-optional) applied to the route (e.g. URLRewrite, RequestHeaderModifier). Passed through verbatim. |
| gatewayApi.httpRoutes.webdav.hostnames | list | `[]` | Hostnames for the WebDAV HTTPRoute. Leave empty to match any hostname accepted by the parent Gateway. |
| gatewayApi.httpRoutes.webdav.labels | object | `{}` | Labels to be added to the WebDAV HTTPRoute. |
| gatewayApi.httpRoutes.webdav.parentRefs | list | `[]` | ParentRefs for the WebDAV HTTPRoute. At least one entry is required for the route to be attached to a Gateway. |
| gatewayApi.httpRoutes.webdav.pathPrefix | string | `"/"` | Path prefix for the WebDAV route. Should match the WebDAV binding prefix configured in SFTPGo (default `/`). |
| gatewayApi.tcpRoutes.ftp.annotations | object | `{}` | Annotations to be added to the FTP TCPRoute. |
| gatewayApi.tcpRoutes.ftp.backend | object | `{}` | Backend override. Defaults to the main chart Service on the FTP control port. Accepted keys: `kind`, `name`, `port`, `weight`. |
| gatewayApi.tcpRoutes.ftp.enabled | bool | `false` | Enable [TCPRoute](https://gateway-api.sigs.k8s.io/api-types/tcproute/) for FTP. Requires the Gateway API experimental channel CRDs. Only routes the FTP control port; passive data ports are not handled. |
| gatewayApi.tcpRoutes.ftp.labels | object | `{}` | Labels to be added to the FTP TCPRoute. |
| gatewayApi.tcpRoutes.ftp.parentRefs | list | `[]` | ParentRefs for the FTP TCPRoute. At least one entry is required for the route to be attached to a Gateway. |
| gatewayApi.tcpRoutes.sftp.annotations | object | `{}` | Annotations to be added to the SFTP TCPRoute. |
| gatewayApi.tcpRoutes.sftp.backend | object | `{}` | Backend override. Defaults to the main chart Service on the SFTP port. Accepted keys: `kind`, `name`, `port`, `weight`. |
| gatewayApi.tcpRoutes.sftp.enabled | bool | `false` | Enable [TCPRoute](https://gateway-api.sigs.k8s.io/api-types/tcproute/) for SFTP. Requires the Gateway API experimental channel CRDs. |
| gatewayApi.tcpRoutes.sftp.labels | object | `{}` | Labels to be added to the SFTP TCPRoute. |
| gatewayApi.tcpRoutes.sftp.parentRefs | list | `[]` | ParentRefs for the SFTP TCPRoute. At least one entry is required for the route to be attached to a Gateway. |
| hostNetwork | bool | `false` | Run pods in the host network of nodes. Warning: The use of host network is [discouraged](https://kubernetes.io/docs/concepts/configuration/overview/#services). Make sure to use it only when absolutely necessary. |
| httpd.enabled | bool | `true` | Enable HTTP service. |
| httpd.port | int | `8080` | Container HTTP port. Set to 0 to disable the service. The 'enabled' flag may be removed in the future in favor of this setting. |
| image.pullPolicy | string | `"IfNotPresent"` | [Image pull policy](https://kubernetes.io/docs/concepts/containers/images/#updating-images) for updating already existing images on a node. |
| image.repository | string | `"ghcr.io/drakkan/sftpgo"` | Name of the image repository to pull the container image from. |
| image.tag | string | `""` | Image tag override for the default value (chart appVersion). When set, it replaces the whole tag and `image.variant` is ignored. |
| image.variant | string | `""` | Override the default image variant. Example: "distroless-slim". Ignored when `image.tag` is set. See the [official documentation](https://docs.sftpgo.com/latest/docker/#image-variants). |
| imagePullSecrets | list | `[]` | Reference to one or more secrets to be used when [pulling images](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/#create-a-pod-that-uses-your-secret) (from private registries). |
| initContainers | list | `[]` | Add [init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) to the pod. |
| nameOverride | string | `""` | A name in place of the chart name for `app:` labels. |
| networkPolicy | object | `{"egress":[],"enabled":false,"ingress":[],"policyTypes":[]}` | [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) configuration. |
| networkPolicy.egress | list | `[]` | Egress rules. |
| networkPolicy.enabled | bool | `false` | Enable creation of NetworkPolicy resources. |
| networkPolicy.ingress | list | `[]` | Ingress rules. |
| networkPolicy.policyTypes | list | `[]` | Specifies the policy types. Defaults to Ingress and Egress if not specified. |
| nodeSelector | object | `{}` | [Node selector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector) configuration. |
| pdb | object | `{"enabled":false}` | [Pod Disruption Budget](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) configuration. See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/pod-disruption-budget-v1/) for details. Note: minAvailable and maxUnavailable cannot be used simultaneously. |
| pdb.enabled | bool | `false` | Enable Pod Disruption Budget creation. |
| persistence.annotations | object | `{}` | Annotations to be added to the PVC. |
| persistence.enabled | bool | `false` | Enable persistent storage for the /var/lib/sftpgo directory, saving state of the default sqlite db. |
| persistence.pvc | object | `{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"5Gi"}},"storageClassName":""}` | Create the pvc desired specificiation. |
| podAnnotations | object | `{}` | Annotations to be added to pods. |
| podLabels | object | `{}` | Labels to be added to pods. |
| podMonitor | object | `{"annotations":{},"enabled":false,"interval":"1m","labels":{},"scrapeTimeout":"10s"}` | Prometheus PodMonitor configuration. See the [Prometheus Operator documentation](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.PodMonitor) for details. |
| podMonitor.annotations | object | `{}` | Additional annotations for the PodMonitor resource. |
| podMonitor.enabled | bool | `false` | Enable PodMonitor resource for Prometheus Operator to scrape pod metrics. |
| podMonitor.interval | string | `"1m"` | Scrape interval (e.g., 10s, 1m). |
| podMonitor.labels | object | `{}` | Additional labels for the PodMonitor resource. Useful if your Prometheus Operator requires specific labels to discover the monitor. |
| podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout (e.g., 10s). |
| podPriorityClassName | string | `nil` | Pod priority class name. |
| podSecurityContext | object | `{"fsGroup":1000}` | Pod [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#security-context) for details. |
| podTerminationGracePeriodSeconds | string | `nil` | Duration in seconds the pod needs to terminate gracefully. See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle) for details. Should be set in conjunction with SFTPGO_GRACE_TIME environment variable. Expected value: number of seconds (int64). |
| replicaCount | int | `1` | Number of replicas (pods) to launch. |
| resources | object | No requests or limits. | Container resource [requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#resources) for details. |
| revisionHistoryLimit | int | `10` | Number of old ReplicaSets to retain to allow rollback. |
| securityContext | object | `{}` | Container [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#security-context-1) for details. |
| service.annotations | object | `{}` | Annotations to be added to the service. |
| service.externalTrafficPolicy | string | `nil` | Route external traffic to node-local or cluster-wide endoints. Useful for [preserving the client source IP](https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/#preserving-the-client-source-ip). |
| service.labels | object | `{}` | labels to be added to the service. |
| service.loadBalancerIP | string | `nil` | Only applies when the service type is LoadBalancer. Load balancer will get created with the IP specified in this field. |
| service.loadBalancerSourceRanges | list | `[]` | If specified (and supported by the cloud provider), traffic through the load balancer will be restricted to the specified client IPs. Valid values are IP CIDR blocks. |
| service.ports.ftp.nodePort | int | `nil` | FTP node port (when applicable). |
| service.ports.ftp.passiveRange.end | int | `50020` | FTP passive range end port. |
| service.ports.ftp.passiveRange.start | int | `50000` | FTP passive range start port. |
| service.ports.ftp.port | int | `21` | FTP service port. |
| service.ports.http.nodePort | int | `nil` | REST API node port (when applicable). |
| service.ports.http.port | int | `80` | REST API service port. |
| service.ports.sftp.nodePort | int | `nil` | SFTP node port (when applicable). |
| service.ports.sftp.port | int | `22` | SFTP service port. |
| service.ports.webdav.nodePort | int | `nil` | WebDAV node port (when applicable). |
| service.ports.webdav.port | int | `81` | WebDAV service port. |
| service.sessionAffinity | string | `nil` | Enable client IP based session affinity. [More info](https://kubernetes.io/docs/concepts/services-networking/service/#virtual-ips-and-service-proxies) |
| service.type | string | `"ClusterIP"` | Kubernetes [service type](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types). |
| serviceAccount.annotations | object | `{}` | Annotations to be added to the service account. |
| serviceAccount.automountServiceAccountToken | bool | `true` | Automount API credentials for the Service Account. |
| serviceAccount.create | bool | `true` | Enable service account creation. |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and create is true, a name is generated using the fullname template. |
| services | object | `{}` | Additional services exposing servers (SFTP, FTP, WebDAV, HTTP) individually. The schema matches the one under the `service` key. Additional services need at least one port. |
| sftpd.enabled | bool | `true` | Enable SFTP service. |
| sftpd.port | int | `2022` | Container SFTP port. Set to 0 to disable the service. The 'enabled' flag may be removed in the future in favor of this setting. |
| tolerations | list | `[]` | [Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) for node taints. See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#scheduling) for details. |
| topologySpreadConstraints | list | `[]` | [Topology Spread Constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/) configuration. Accepts a list of constraints. The legacy object format is also supported for backward compatibility. |
| ui.ingress.annotations | object | `{}` | Annotations to be added to the ingress. |
| ui.ingress.className | string | `""` | Ingress [class name](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class). |
| ui.ingress.enabled | bool | `false` | Enable [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/). |
| ui.ingress.hosts | list | See [values.yaml](values.yaml). | Ingress host configuration. |
| ui.ingress.tls | list | See [values.yaml](values.yaml). | Ingress TLS configuration. |
| volumeMounts | list | `[]` | Additional [volume mounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-volume-storage/). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#volumes-1) for details. |
| volumes | list | `[]` | Additional storage [volumes](https://kubernetes.io/docs/concepts/storage/volumes/). See the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#volumes-1) for details. |
| webdavd.enabled | bool | `false` | Enable WebDAV service. |
| webdavd.port | int | `8081` | Container WebDAV port. Set to 0 to disable the service. The 'enabled' flag may be removed in the future in favor of this setting. |

## Attributions

This Helm chart was originally created by [@sagikazarmark](https://github.com/sagikazarmark/).
