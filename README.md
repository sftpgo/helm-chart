# SFTPGo Helm Chart

[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

## Usage

```bash
helm install --generate-name --wait oci://ghcr.io/sftpgo/helm-charts/sftpgo
```

See the Helm chart [README](sftpgo/README.md) and [values.yaml](sftpgo/values.yaml) for more information.

## Contributing

TODO

## Releases

Releases are automatically pushed to the [GitHub Container Registry]() on tags.

To tag a new release after merging changes to `main`, run the following:

```bash
TAG=0.1.0
git tag -a v$TAG -m "Release $TAG"
git push origin v$TAG
```

## Attributions

This Helm chart was originally created by [@sagikazarmark](https://github.com/sagikazarmark/)
Maintenance under a [personal chart repository](https://github.com/sagikazarmark/helm-charts/tree/06ebf671519118f1ddabf1ba7dd7f4e2f85ea816/charts/sftpgo) has proven to be difficult, so it has been moved to this repository.

## License

The project is licensed under the [MIT License](LICENSE).
