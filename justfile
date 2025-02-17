[private]
default:
  @just --list

# regenerate the readme of the chart
docs:
    dagger call docs contents > sftpgo/README.md

# tag and release
release bump='minor':
    #!/usr/bin/env bash
    set -euo pipefail

    git checkout main > /dev/null 2>&1
    git diff-index --quiet HEAD || (echo "Git directory is dirty" && exit 1)

    version=$(semver bump {{bump}} $(git tag --sort=v:refname | tail -1 || echo "v0.0.0"))
    tag=v$version

    echo "Tagging chart with version ${version}"
    read -n 1 -p "Proceed (y/N)? " answer
    echo

    case ${answer:0:1} in
        y|Y )
        ;;
        * )
            echo "Aborting"
            exit 1
        ;;
    esac

    git tag -a $tag -m "Release: ${version}"
    git push origin $tag
