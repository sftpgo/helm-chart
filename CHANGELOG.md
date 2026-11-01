# Changelog

All notable changes to the SFTPGo Helm chart are documented in this file.

Releases are tagged as `vX.Y.Z`; this file starts with the release after v0.48.0.

## [Unreleased]

### Upgrade notes

- **The default FTP passive port range changed from 50000-50020 to 30050-30070**, so that it works
  with `NodePort` services. If you enabled FTP without setting the range, update the firewall,
  load balancer and network policy rules that allow the passive ports, or keep the previous range:

  ```yaml
  ftpd:
    passivePortRange:
      start: 50000
      end: 50020
  ```

- Upgrades with `--reuse-values` keep the defaults of the previous chart version, including the
  50000-50020 range set by the deprecated `service.ports.ftp.passiveRange`. To use
  `ftpd.passivePortRange` instead, also set `service.ports.ftp.passiveRange` to null
  (e.g. `--set service.ports.ftp.passiveRange=null`).
- `services.<name>.ports.ftp.passiveRange` must now match the passive port range SFTPGo listens on,
  otherwise rendering fails. This also affects services set to the previous default range (50000-50020):
  remove the key and set `services.<name>.ftpPassive: true`, and set `ftpd.passivePortRange` if you
  want to keep that range.
- `NodePort` services now use the FTP passive ports as node ports (previously random). To expose
  them on another service, set `ftpPassive: false` on the `NodePort` service.
- Invalid configurations now fail at render time with an explicit message:
  - a built-in port listed without a port number (e.g. `services.<name>.ports.sftp: {}`), or a service
    whose listed ports all belong to disabled servers;
  - duplicate port names, ports or node ports, including node ports shared by different services;
  - port numbers outside 1-65535 or invalid port names;
  - `additionalPorts` entries without `containerPort`, named after an enabled built-in server or
    `telemetry`, or with names that are not valid container port names (max 15 characters).

### Added

- Additional service ports: besides the built-in servers, `service.ports` and `services.<name>.ports`
  accept arbitrary TCP ports with `port`, `targetPort`, `nodePort` and `appProtocol`. They can
  expose a server on more ports, expose `additionalPorts` entries (e.g. additional FTP bindings) on
  additional services, and target ports of extra containers ([#39](https://github.com/sftpgo/helm-chart/issues/39)).
- `additionalPorts` entries accept `nodePort` and `appProtocol` for the main service.
- `ftpd.passivePortRange`: the FTP passive port range.
- `ftpPassive` on `service` (default `true`) and `services.<name>` (default `false`): expose the FTP
  passive ports, also on services that do not expose the `ftp` port.
- `loadBalancerClass` for `LoadBalancer` services ([#74](https://github.com/sftpgo/helm-chart/issues/74)).
- `relabelings` and `metricRelabelings` for the `PodMonitor`.

### Changed

- The default FTP passive port range is 30050-30070 (see the upgrade notes).
- `NodePort` services set the node ports of the FTP passive ports to the passive ports.
- Gateway API: `TCPRoute` resources use `gateway.networking.k8s.io/v1` when the cluster serves it.
- SFTPGo 2.7.6.

### Deprecated

- `service.ports.ftp.passiveRange`: use `ftpd.passivePortRange`.
- `services.<name>.ports.ftp.passiveRange`: use `services.<name>.ftpPassive`.

### Fixed

- Additional services could expose a passive port range different from the one SFTPGo listens on,
  breaking FTP passive mode.
- Pods were restarted on every chart upgrade, even when the configuration was unchanged, because the
  `checksum/config` annotation hashed the chart version label.
- A whitespace-only line was rendered with custom service labels.
- Installation notes: the `LoadBalancer` URL printed the whole HTTP port configuration instead of the port,
  the `NodePort` URL used the node port of the first service port (SFTP, if enabled) instead of the HTTP one,
  and the port-forward command ignored `httpd.port` and `sftpd.port`.
