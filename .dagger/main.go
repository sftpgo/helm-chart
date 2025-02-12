package main

import (
	"context"
	"dagger/sftpgo/internal/dagger"
	"fmt"
	"strings"
	"time"
)

const (
	helmVersion     = "3.16.1"
	helmDocsVersion = "v1.14.2"
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
		Version: version,
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
