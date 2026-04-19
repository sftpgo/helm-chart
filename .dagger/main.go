package main

import (
	"context"
	"dagger/sftpgo/internal/dagger"
	"fmt"
	"strings"
	"time"
)

const (
	helmVersion     = "4.1.1"
	helmDocsVersion = "v1.14.2"

	// Gateway API CRDs version. Installed into the test cluster so that
	// HTTPRoute/TCPRoute scenarios can be rendered and applied. Bump as the
	// upstream project releases new versions; see
	// https://github.com/kubernetes-sigs/gateway-api/releases.
	gatewayAPIVersion = "v1.5.1"
)

type Sftpgo struct {
	// Project source directory
	//
	// +private
	Source *dagger.Directory
}

func New(
	// Project source directory.
	//
	// +defaultPath="/"
	// +ignore=[".devenv", ".direnv", ".github"]
	source *dagger.Directory,
) *Sftpgo {
	return &Sftpgo{
		Source: source,
	}
}

// Build the Helm chart package.
func (m *Sftpgo) Build(
	ctx context.Context,

	// Helm chart version.
	//
	// +optional
	version string,
) *dagger.File {
	return m.build(ctx, version).File()
}

func (m *Sftpgo) build(
	ctx context.Context,

	// Helm chart version.
	//
	// +optional
	version string,
) *dagger.HelmPackage {
	return m.chart().Package(dagger.HelmChartPackageOpts{
		Version: strings.TrimPrefix(version, "v"),
	})
}

// Lint the Helm chart.
func (m *Sftpgo) Lint(ctx context.Context) (string, error) {
	chart := m.chart()

	return chart.Lint().Stdout(ctx)
}

// Test the Helm chart.
func (m *Sftpgo) Test(
	ctx context.Context,

	// Kubernetes version (Rancher k3s image tag, eg. "v1.32.1-k3s1")
	//
	// +default="latest"
	// +optional
	version string,

	// Run a specific set of tests.
	//
	// +optional
	tests []string,

	// Stop execution on first test failure and open a terminal.
	//
	// +optional
	terminal bool,
) error {
	testDir := m.Source.Directory("tests")

	if len(tests) == 0 {
		testFiles, err := testDir.Entries(ctx)
		if err != nil {
			return err
		}

		for _, testFile := range testFiles {
			if !strings.HasSuffix(testFile, ".yaml") {
				continue
			}

			tests = append(tests, strings.TrimSuffix(testFile, ".yaml"))
		}
	}

	k8s := dag.K3S("test", dagger.K3SOpts{
		Image: "rancher/k3s:" + version,
	})

	// Start the Kubernetes cluster.
	_, err := k8s.Server().Start(ctx)
	if err != nil {
		return err
	}

	// Install Gateway API CRDs so scenarios that create HTTPRoute/TCPRoute
	// resources can be applied by helm. The experimental channel manifest
	// exceeds kubectl client-side apply size limits, so server-side apply is
	// required.
	if err := installGatewayAPICRDs(ctx, k8s); err != nil {
		return fmt.Errorf("install Gateway API CRDs: %w", err)
	}

	pkg := m.chart().Package().WithKubeconfigFile(k8s.Config())

	for _, test := range tests {
		_, err = pkg.
			Install(test, dagger.HelmPackageInstallOpts{
				Wait:            true,
				CreateNamespace: true,
				Namespace:       test,
				Values: []*dagger.File{
					testDir.File(test + ".yaml"),
				},
			}).
			Test(ctx, dagger.HelmReleaseTestOpts{
				Logs: true,
			})
		if err != nil {
			if terminal {
				dag.Container().
					From("bitnami/kubectl").
					WithoutEntrypoint().
					WithEnvVariable("CACHE", time.Now().String()).
					WithFile("/.kube/config", k8s.Config(), dagger.ContainerWithFileOpts{Permissions: 1001}).
					WithUser("1001").
					Terminal().
					Sync(ctx)
			}

			return err
		}
	}

	return nil
}

// Package and release the Helm chart.
func (m *Sftpgo) Release(
	ctx context.Context,

	// Helm chart version.
	version string,

	// GitHub actor (username or organization name).
	githubActor string,

	// GitHub token.
	githubToken *dagger.Secret,

	// GitHub account name (in case it's different from the GitHub Actor).
	//
	// +optional
	githubAccount string,
) error {
	if githubAccount == "" {
		githubAccount = githubActor
	}

	err := m.build(ctx, version).
		WithRegistryAuth("ghcr.io", githubActor, githubToken).
		Publish(ctx, fmt.Sprintf("oci://ghcr.io/%s/helm-charts", githubAccount))
	if err != nil {
		return err
	}

	return nil
}

// Generate the Helm chart documentation.
func (m *Sftpgo) Docs() *dagger.File {
	return m.chart().Directory().File("README.md")
}

func (m *Sftpgo) chart() *dagger.HelmChart {
	chart := m.Source.Directory("sftpgo")

	// Generate the README.md file using helm-docs.
	// See https://github.com/norwoodj/helm-docs
	readme := dag.HelmDocs(dagger.HelmDocsOpts{Version: helmDocsVersion}).Generate(chart)

	chart = chart.WithFile("README.md", readme)

	return dag.Helm(dagger.HelmOpts{Version: helmVersion}).Chart(chart)
}

// installGatewayAPICRDs installs the Gateway API experimental channel CRDs
// into the given k3s cluster.
//
// Only the experimental channel is installed: it is a superset of standard
// (HTTPRoute as v1 stable, TCPRoute/UDPRoute as v1alpha2). Since v1.5 the
// standard channel ships a ValidatingAdmissionPolicy (safe-upgrades) that
// blocks installing experimental CRDs on top of standard ones, so the two
// cannot be applied side-by-side.
//
// Server-side apply is required because the experimental manifest exceeds the
// client-side apply size limit.
func installGatewayAPICRDs(ctx context.Context, k8s *dagger.K3S) error {
	manifestURL := fmt.Sprintf(
		"https://github.com/kubernetes-sigs/gateway-api/releases/download/%s/experimental-install.yaml",
		gatewayAPIVersion,
	)

	ctr := dag.Container().
		From("bitnami/kubectl").
		WithoutEntrypoint().
		WithServiceBinding("k3s", k8s.Server()).
		WithFile("/.kube/config", k8s.Config(), dagger.ContainerWithFileOpts{Permissions: 1001}).
		WithEnvVariable("KUBECONFIG", "/.kube/config").
		WithUser("1001").
		WithExec([]string{"kubectl", "apply", "--server-side=true", "-f", manifestURL})

	for _, crd := range []string{
		"httproutes.gateway.networking.k8s.io",
		"tcproutes.gateway.networking.k8s.io",
	} {
		ctr = ctr.WithExec([]string{
			"kubectl", "wait", "--for=condition=established", "--timeout=60s", "crd/" + crd,
		})
	}

	_, err := ctr.Sync(ctx)
	return err
}
