# Dockerfiles and Charts

This repo holds container images and Helm charts.

- Each image is its own folder under `images/` with a `Dockerfile` and README,
  built by its workflow in [.github/workflows](.github/workflows) when any of
  its files change and published to ghcr.io. An image a running deployment
  pins by tag (`images/valheim`, `images/stationeers`) publishes only from a
  release tag, so no commit can change what it runs; a branch push for those
  builds the image as a check and pushes nothing.
- Each chart is its own folder under `charts/`, released to the `gh-pages`
  chart index by `chart.yaml` when anything under `charts/` changes on `main`.
  Dependency `.tgz` files are vendored by CI, never committed.

Tags are namespaced so an image release cannot trigger another image's build
(a tag push ignores `paths:`): image releases are `<image>-v<version>`
(`xestrata-vxe0.2.2-1`) and publish image tag `<version>`, chart releases are
`<chart>-<version>` (`xestrata-0.1.1`) from `Chart.yaml`, branch pushes publish
the branch name (except an image a running deployment pins by tag, which
publishes only from a release tag).

Image and chart for the same service should agree: bump the image tag and the
chart's `appVersion` (and `image.tag` default) in the same commit.

## Security

Ask the human to review changes before committing.

Scan files with `gitleaks` before committing.

Run a build check before committing, e.g. `docker build --check ./images/xestrata`.

Validate workflow edits with `actionlint`.

For chart changes run `helm lint ./charts/<name>` and, if versions changed,
`helm template` on it. Do not commit `Chart.lock` churn you cannot explain.
