# Dockerfiles and Charts

This repo holds container images and Helm charts.

- Each image is its own top-level folder with a `Dockerfile` and README, built
  and published to ghcr.io by its workflow in [.github/workflows](.github/workflows)
  when any of its files change.
- Each chart is its own folder under `charts/`, released to the `gh-pages`
  chart index by `chart.yaml` when anything under `charts/` changes on `main`.
  Dependency `.tgz` files are vendored by CI, never committed.

Image and chart for the same service should agree: bump the image tag and the
chart's `appVersion` (and `image.tag` default) in the same commit.

## Security

Ask the human to review changes before comitting.

Scan files with `gitleaks` before comitting.

Run a build check before comitting, e.g., `docker build --check ./xestrata`.

For chart changes run `helm lint ./charts/<name>` and, if versions changed,
`helm template` on it. Do not commit `Chart.lock` churn you cannot explain.
